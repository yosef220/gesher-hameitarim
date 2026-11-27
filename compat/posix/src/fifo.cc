// gesher-base: cross-process POSIX FIFOs (mkfifo, mkfifoat, S_IFIFO reparse
// points, and kernel named-pipe rendezvous integrated with pipe_io and OFD).
#include "fifo_internal.h"

#include <bcrypt.h>
#include <errno.h>
#include <fcntl.h>
#include <io.h>
#include <limits.h>
#include <poll.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <winioctl.h>
#include <winternl.h>

#include <algorithm>
#include <atomic>
#include <cstdio>
#include <cstring>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "event_internal.h"
#include "internal.h"
#include "ofd_internal.h"
#include "record_lock_descriptors.h"

namespace gesher {
namespace {

constexpr uint32_t kFifoShmMagic = 0x4F464946u;  // 'FIFO'
constexpr uint32_t kFifoShmVersion = 1u;
constexpr size_t kMaxFifoHolders = 64;
constexpr size_t kMaxFifoWaiters = 64;
constexpr unsigned kPipeBufSize = 65536u;
constexpr unsigned kAtomicPipeBuf = 4096u;

constexpr char kFifoModeEaName[] = "GESHER.FIFOMODE";
constexpr UCHAR kFifoModeEaNameLen = sizeof(kFifoModeEaName) - 1;

struct FifoKey {
  uint32_t vol = 0;
  uint32_t idx_hi = 0;
  uint32_t idx_lo = 0;

  bool operator<(const FifoKey& o) const {
    if (vol != o.vol) return vol < o.vol;
    if (idx_hi != o.idx_hi) return idx_hi < o.idx_hi;
    return idx_lo < o.idx_lo;
  }
};

struct FifoHolder {
  DWORD pid = 0;
  uint64_t handle = 0;
};

struct FifoWaiter {
  DWORD pid = 0;
  uint64_t seq = 0;
  uint8_t want_writer = 0;
  uint8_t active = 0;
  uint8_t reserved[6]{};
};

struct FifoShm {
  uint32_t magic;
  uint32_t version;
  uint64_t pipe_generation;
  char pipe_gate[33];
  uint8_t connected_once;
  uint8_t pad[6];
  uint64_t reader_opens;
  uint64_t writer_opens;
  FifoHolder readers[kMaxFifoHolders];
  FifoHolder writers[kMaxFifoHolders];
  FifoWaiter waiters[kMaxFifoWaiters];
};

std::mutex g_umask_mutex;
std::atomic<uint64_t> g_waiter_seq{1};

mode_t ReadCurrentUmask() {
  std::lock_guard<std::mutex> lock(g_umask_mutex);
  int old = _umask(0);
  if (old < 0) return 0022;
  _umask(old);
  return static_cast<mode_t>(old & 0777);
}

// --- NTFS Extended Attribute for FIFO POSIX mode (matches memfd_seals.cc) ---

struct IoStatus {
  union {
    LONG status;
    void* pointer;
  };
  ULONG_PTR information;
};
using SetEaFn = LONG(NTAPI*)(HANDLE, IoStatus*, void*, ULONG);
using QueryEaFn = LONG(NTAPI*)(HANDLE, IoStatus*, void*, ULONG, BOOLEAN, void*, ULONG, ULONG*, BOOLEAN);

struct EaApi {
  SetEaFn set = nullptr;
  QueryEaFn query = nullptr;
};

const EaApi& GetEaApi() {
  static const EaApi api = [] {
    EaApi a;
    HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
    if (ntdll) {
      a.set = reinterpret_cast<SetEaFn>(reinterpret_cast<void*>(GetProcAddress(ntdll, "NtSetEaFile")));
      a.query = reinterpret_cast<QueryEaFn>(reinterpret_cast<void*>(GetProcAddress(ntdll, "NtQueryEaFile")));
    }
    return a;
  }();
  return api;
}

struct FullModeEa {
  ULONG next_offset;
  UCHAR flags;
  UCHAR ea_name_length;
  USHORT ea_value_length;
  char ea_name[kFifoModeEaNameLen + 1];
  uint32_t value;
};

// --- Named pipe query helpers ---

#ifndef FILE_PIPE_LISTENING_STATE
#define FILE_PIPE_DISCONNECTED_STATE 1
#define FILE_PIPE_LISTENING_STATE 2
#define FILE_PIPE_CONNECTED_STATE 3
#define FILE_PIPE_CLOSING_STATE 4
#endif

struct PipeLocalInfo {
  ULONG NamedPipeType;
  ULONG NamedPipeConfiguration;
  ULONG MaximumInstances;
  ULONG CurrentInstances;
  ULONG InboundQuota;
  ULONG ReadDataAvailable;
  ULONG OutboundQuota;
  ULONG WriteQuotaAvailable;
  ULONG NamedPipeState;
  ULONG NamedPipeEnd;
};

int QueryPipeLocal(HANDLE file, PipeLocalInfo* info) {
  using Query = LONG(WINAPI*)(HANDLE, PIO_STATUS_BLOCK, void*, ULONG, FILE_INFORMATION_CLASS);
  using Error = ULONG(WINAPI*)(LONG);
  HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
  auto query = ntdll ? reinterpret_cast<Query>(reinterpret_cast<void*>(
      GetProcAddress(ntdll, "NtQueryInformationFile"))) : nullptr;
  auto convert = ntdll ? reinterpret_cast<Error>(reinterpret_cast<void*>(
      GetProcAddress(ntdll, "RtlNtStatusToDosError"))) : nullptr;
  if (!query || !convert) return errno = ENOSYS, -1;
  IO_STATUS_BLOCK status{};
  LONG st = query(file, &status, info, sizeof(*info), static_cast<FILE_INFORMATION_CLASS>(24));
  return st < 0 ? (errno = ErrnoFromWin32(convert(st)), -1) : 0;
}

// --- Overlapped pipe transfer with pthread cancellation support ---

struct FifoOverlappedOp {
  HANDLE file = nullptr;
  HANDLE thread = nullptr;
  OVERLAPPED overlapped{};
  PTP_WAIT cancel_wait = nullptr;
  PTP_WAIT interrupt_wait = nullptr;
  std::atomic<bool> active{true};

  ~FifoOverlappedOp() {
    active.store(false, std::memory_order_release);
    for (PTP_WAIT w : {cancel_wait, interrupt_wait}) {
      if (!w) continue;
      SetThreadpoolWait(w, nullptr, nullptr);
      WaitForThreadpoolWaitCallbacks(w, TRUE);
      CloseThreadpoolWait(w);
    }
    if (thread) CloseHandle(thread);
    if (overlapped.hEvent) CloseHandle(overlapped.hEvent);
  }
};

void CALLBACK CancelFifoIoCallback(PTP_CALLBACK_INSTANCE, void* raw, PTP_WAIT, TP_WAIT_RESULT) {
  auto* op = static_cast<FifoOverlappedOp*>(raw);
  while (op->active.load(std::memory_order_acquire)) {
    CancelIoEx(op->file, &op->overlapped);
    if (op->thread) CancelSynchronousIo(op->thread);
    Sleep(1);
  }
}

int MapPipeTransferResult(BOOL done, DWORD transferred, DWORD error, bool writing) {
  if (done || error == ERROR_MORE_DATA) {
    return static_cast<int>(transferred);
  }
  if (error == ERROR_BROKEN_PIPE || error == ERROR_PIPE_NOT_CONNECTED ||
      error == ERROR_PIPE_LISTENING) {
    return writing ? (errno = EPIPE, -1) : 0;
  }
  if (error == ERROR_NO_DATA) {
    return errno = writing ? EPIPE : EAGAIN, -1;
  }
  if (error == ERROR_OPERATION_ABORTED) {
    return errno = EINTR, -1;
  }
  if (error == ERROR_NOACCESS || error == ERROR_INVALID_USER_BUFFER) {
    return errno = EFAULT, -1;
  }
  return errno = ErrnoFromWin32(error), -1;
}

int NativeFifoOverlappedTransfer(HANDLE file, void* bytes, unsigned count, bool writing,
                                 HANDLE canceled, HANDLE interrupted) {
  if (canceled && WaitForSingleObject(canceled, 0) == WAIT_OBJECT_0) return errno = EINTR, -1;
  if (interrupted && WaitForSingleObject(interrupted, 0) == WAIT_OBJECT_0) return errno = EINTR, -1;
  FifoOverlappedOp op;
  op.file = file;
  op.overlapped.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (!op.overlapped.hEvent) return FailWithLastError();
  if (canceled || interrupted) {
    if (!DuplicateHandle(GetCurrentProcess(), GetCurrentThread(), GetCurrentProcess(),
                         &op.thread, THREAD_TERMINATE, FALSE, 0)) {
      return FailWithLastError();
    }
    if (canceled) {
      op.cancel_wait = CreateThreadpoolWait(CancelFifoIoCallback, &op, nullptr);
      if (!op.cancel_wait) return FailWithLastError();
      SetThreadpoolWait(op.cancel_wait, canceled, nullptr);
    }
    if (interrupted && interrupted != canceled) {
      op.interrupt_wait = CreateThreadpoolWait(CancelFifoIoCallback, &op, nullptr);
      if (!op.interrupt_wait) return FailWithLastError();
      SetThreadpoolWait(op.interrupt_wait, interrupted, nullptr);
    }
  }
  DWORD transferred = 0;
  BOOL done = writing ? WriteFile(file, bytes, count, &transferred, &op.overlapped)
                      : ReadFile(file, bytes, count, &transferred, &op.overlapped);
  DWORD error = done ? ERROR_SUCCESS : GetLastError();
  if (!done && error == ERROR_IO_PENDING) {
    done = GetOverlappedResult(file, &op.overlapped, &transferred, TRUE);
    error = done ? ERROR_SUCCESS : GetLastError();
  }
  op.active.store(false, std::memory_order_release);
  return MapPipeTransferResult(done, transferred, error, writing);
}

// --- Shared-memory registry & synchronization ---

std::wstring FifoPrefix(const FifoKey& key) {
  wchar_t buf[96];
  std::swprintf(buf, sizeof(buf) / sizeof(buf[0]), L"Local\\gesher-fifo-%08lx-%08lx-%08lx",
                static_cast<unsigned long>(key.vol), static_cast<unsigned long>(key.idx_hi),
                static_cast<unsigned long>(key.idx_lo));
  return buf;
}

std::wstring FifoPipeName(const FifoKey& key, uint64_t generation) {
  wchar_t buf[128];
  std::swprintf(buf, sizeof(buf) / sizeof(buf[0]), L"\\\\.\\pipe\\gesher-fifo-%08lx-%08lx-%08lx-%llu",
                static_cast<unsigned long>(key.vol), static_cast<unsigned long>(key.idx_hi),
                static_cast<unsigned long>(key.idx_lo),
                static_cast<unsigned long long>(generation));
  return buf;
}

std::wstring FifoWaiterEventName(DWORD pid, uint64_t seq) {
  wchar_t buf[96];
  std::swprintf(buf, sizeof(buf) / sizeof(buf[0]), L"Local\\gesher-fifo-w-%lu-%llu",
                static_cast<unsigned long>(pid), static_cast<unsigned long long>(seq));
  return buf;
}

bool GenerateGateHex(char gate_out[33]) {
  unsigned char nonce[16];
  if (!BCRYPT_SUCCESS(BCryptGenRandom(nullptr, nonce, sizeof(nonce), BCRYPT_USE_SYSTEM_PREFERRED_RNG))) {
    errno = EIO;
    return false;
  }
  constexpr char hex[] = "0123456789abcdef";
  for (size_t i = 0; i != sizeof(nonce); ++i) {
    gate_out[2 * i] = hex[nonce[i] >> 4];
    gate_out[2 * i + 1] = hex[nonce[i] & 15];
  }
  gate_out[32] = '\0';
  return true;
}

class FifoShmSession {
 public:
  ~FifoShmSession() {
    Unlock();
    if (view_) UnmapViewOfFile(view_);
    if (mapping_) CloseHandle(mapping_);
    if (mutex_) CloseHandle(mutex_);
  }

  bool Open(const FifoKey& key) {
    const std::wstring prefix = FifoPrefix(key);
    mutex_ = CreateMutexW(nullptr, FALSE, (prefix + L"-mtx").c_str());
    if (!mutex_) return FailWithLastError(), false;
    mapping_ = CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE, 0,
                                  sizeof(FifoShm), (prefix + L"-shm").c_str());
    if (!mapping_) {
      DWORD err = GetLastError();
      CloseHandle(mutex_);
      mutex_ = nullptr;
      errno = ErrnoFromWin32(err);
      return false;
    }
    view_ = static_cast<FifoShm*>(MapViewOfFile(mapping_, FILE_MAP_READ | FILE_MAP_WRITE,
                                                0, 0, sizeof(FifoShm)));
    if (!view_) {
      DWORD err = GetLastError();
      CloseHandle(mapping_);
      CloseHandle(mutex_);
      mapping_ = nullptr;
      mutex_ = nullptr;
      errno = ErrnoFromWin32(err);
      return false;
    }
    return true;
  }

  bool Lock() {
    if (locked_) return true;
    DWORD w = WaitForSingleObject(mutex_, INFINITE);
    if (w != WAIT_OBJECT_0 && w != WAIT_ABANDONED) {
      return FailWithLastError(), false;
    }
    locked_ = true;
    if (view_->magic != kFifoShmMagic || view_->version != kFifoShmVersion) {
      std::memset(view_, 0, sizeof(*view_));
      view_->magic = kFifoShmMagic;
      view_->version = kFifoShmVersion;
      view_->pipe_generation = 1;
      if (!GenerateGateHex(view_->pipe_gate)) {
        view_->magic = 0;
        Unlock();
        return false;
      }
    }
    return true;
  }

  void Unlock() {
    if (locked_) {
      locked_ = false;
      ReleaseMutex(mutex_);
    }
  }

  FifoShm* get() const { return view_; }

 private:
  HANDLE mutex_ = nullptr;
  HANDLE mapping_ = nullptr;
  FifoShm* view_ = nullptr;
  bool locked_ = false;
};

struct RetainedShmEntry {
  HANDLE mapping = nullptr;
  size_t refs = 0;
};
std::mutex g_retained_shm_mutex;
std::map<FifoKey, RetainedShmEntry> g_retained_shm;

void RetainFifoShm(const FifoKey& key) {
  std::lock_guard<std::mutex> lock(g_retained_shm_mutex);
  auto& entry = g_retained_shm[key];
  if (!entry.mapping) {
    const std::wstring prefix = FifoPrefix(key);
    entry.mapping = CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE, 0,
                                       sizeof(FifoShm), (prefix + L"-shm").c_str());
  }
  ++entry.refs;
}

void ReleaseFifoShm(const FifoKey& key) {
  std::lock_guard<std::mutex> lock(g_retained_shm_mutex);
  auto it = g_retained_shm.find(key);
  if (it == g_retained_shm.end()) return;
  if (--it->second.refs == 0) {
    if (it->second.mapping) CloseHandle(it->second.mapping);
    g_retained_shm.erase(it);
  }
}

bool IsProcessAlive(DWORD pid) {
  if (pid == 0) return false;
  if (pid == GetCurrentProcessId()) return true;
  HANDLE proc = OpenProcess(SYNCHRONIZE, FALSE, pid);
  if (!proc) return GetLastError() == ERROR_ACCESS_DENIED;
  DWORD w = WaitForSingleObject(proc, 0);
  CloseHandle(proc);
  return w == WAIT_TIMEOUT;
}

bool DuplicateFromHolder(const FifoHolder& holder, DWORD desired_access, HANDLE* out) {
  if (holder.pid == 0 || holder.handle == 0) return false;
  HANDLE src_proc = holder.pid == GetCurrentProcessId()
                        ? GetCurrentProcess()
                        : OpenProcess(PROCESS_DUP_HANDLE | SYNCHRONIZE, FALSE, holder.pid);
  if (!src_proc) return false;
  BOOL alive = holder.pid == GetCurrentProcessId() ||
               WaitForSingleObject(src_proc, 0) == WAIT_TIMEOUT;
  HANDLE dup = nullptr;
  BOOL ok = alive && DuplicateHandle(src_proc, reinterpret_cast<HANDLE>(static_cast<uintptr_t>(holder.handle)),
                                     GetCurrentProcess(), &dup, desired_access, FALSE, 0);
  if (holder.pid != GetCurrentProcessId()) CloseHandle(src_proc);
  if (!ok || !dup) return false;
  *out = dup;
  return true;
}

void PruneHolders(FifoHolder* holders, size_t count) {
  for (size_t i = 0; i < count; ++i) {
    if (holders[i].pid == 0) continue;
    if (!IsProcessAlive(holders[i].pid)) {
      holders[i] = {};
      continue;
    }
    HANDLE probe = nullptr;
    if (!DuplicateFromHolder(holders[i], FILE_READ_ATTRIBUTES, &probe)) {
      holders[i] = {};
    } else {
      CloseHandle(probe);
    }
  }
}

size_t CountLiveHolders(FifoHolder* holders, size_t count) {
  PruneHolders(holders, count);
  size_t live = 0;
  for (size_t i = 0; i < count; ++i) {
    if (holders[i].pid != 0) ++live;
  }
  return live;
}

bool AddHolder(FifoHolder* holders, size_t count, HANDLE h) {
  const DWORD pid = GetCurrentProcessId();
  const uint64_t hv = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(h));
  for (size_t i = 0; i < count; ++i) {
    if (holders[i].pid == 0) {
      holders[i].pid = pid;
      holders[i].handle = hv;
      return true;
    }
  }
  return false;
}

void RemoveHolder(FifoHolder* holders, size_t count, HANDLE h) {
  const DWORD pid = GetCurrentProcessId();
  const uint64_t hv = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(h));
  for (size_t i = 0; i < count; ++i) {
    if (holders[i].pid == pid && holders[i].handle == hv) {
      holders[i] = {};
    }
  }
}

bool AcquireLiveHolderHandle(FifoHolder* holders, size_t count, DWORD desired_access, HANDLE* out) {
  PruneHolders(holders, count);
  for (size_t i = 0; i < count; ++i) {
    if (holders[i].pid == 0) continue;
    if (DuplicateFromHolder(holders[i], desired_access, out)) return true;
    holders[i] = {};
  }
  return false;
}

void WakeWaitersLocked(FifoShm* shm, uint8_t want_writer) {
  for (size_t i = 0; i < kMaxFifoWaiters; ++i) {
    auto& w = shm->waiters[i];
    if (!w.active || w.want_writer != want_writer) continue;
    HANDLE ev = OpenEventW(EVENT_MODIFY_STATE, FALSE, FifoWaiterEventName(w.pid, w.seq).c_str());
    if (ev) {
      SetEvent(ev);
      CloseHandle(ev);
    } else if (!IsProcessAlive(w.pid)) {
      w = {};
    }
  }
}

bool RegisterWaiterLocked(FifoShm* shm, uint8_t want_writer, uint64_t* seq_out, HANDLE* ev_out) {
  const DWORD pid = GetCurrentProcessId();
  const uint64_t seq = g_waiter_seq.fetch_add(1, std::memory_order_relaxed);
  HANDLE ev = CreateEventW(nullptr, TRUE, FALSE, FifoWaiterEventName(pid, seq).c_str());
  if (!ev) return FailWithLastError(), false;
  for (size_t i = 0; i < kMaxFifoWaiters; ++i) {
    if (!shm->waiters[i].active) {
      shm->waiters[i].pid = pid;
      shm->waiters[i].seq = seq;
      shm->waiters[i].want_writer = want_writer;
      shm->waiters[i].active = 1;
      *seq_out = seq;
      *ev_out = ev;
      return true;
    }
  }
  CloseHandle(ev);
  errno = ENOMEM;
  return false;
}

void UnregisterWaiterLocked(FifoShm* shm, uint64_t seq) {
  const DWORD pid = GetCurrentProcessId();
  for (size_t i = 0; i < kMaxFifoWaiters; ++i) {
    if (shm->waiters[i].active && shm->waiters[i].pid == pid && shm->waiters[i].seq == seq) {
      shm->waiters[i] = {};
    }
  }
}

// Reconnects a closing FIFO server pipe for a new writer while preserving any
// unread buffered bytes from earlier writers. Caller holds shm lock.
bool ConnectOrReconnectWriterLocked(FifoShm* shm, const FifoKey& key, HANDLE* write_out) {
  const std::wstring pname = FifoPipeName(key, shm->pipe_generation);
  constexpr DWORD kClientDesired =
      FILE_WRITE_DATA | FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES | SYNCHRONIZE;
  if (AcquireLiveHolderHandle(shm->writers, kMaxFifoHolders, kClientDesired, write_out)) {
    return true;
  }

  HANDLE raw_cli = INVALID_HANDLE_VALUE;
  if (!shm->connected_once) {
    raw_cli = CreateFileW(pname.c_str(),
                          GENERIC_READ | GENERIC_WRITE | FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES,
                          0, nullptr, OPEN_EXISTING, FILE_FLAG_OVERLAPPED, nullptr);
    if (raw_cli != INVALID_HANDLE_VALUE) {
      BOOL ok = DuplicateHandle(GetCurrentProcess(), raw_cli, GetCurrentProcess(), write_out,
                                kClientDesired, FALSE, 0);
      DWORD err = GetLastError();
      CloseHandle(raw_cli);
      if (!ok) {
        errno = ErrnoFromWin32(err);
        return false;
      }
      shm->connected_once = 1;
      return true;
    }
  }

  // Either a prior writer closed (CLOSING_STATE = 4) or pipe needs reconnect.
  HANDLE srv = nullptr;
  if (!AcquireLiveHolderHandle(shm->readers, kMaxFifoHolders,
                               FILE_READ_DATA | FILE_WRITE_DATA | FILE_APPEND_DATA |
                                   FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES | SYNCHRONIZE,
                               &srv)) {
    errno = ENXIO;
    return false;
  }

  std::vector<uint8_t> preserved;
  PipeLocalInfo info{};
  if (QueryPipeLocal(srv, &info) == 0 && info.ReadDataAvailable > 0) {
    preserved.resize(info.ReadDataAvailable);
    OVERLAPPED rov{};
    rov.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    DWORD total_read = 0;
    while (total_read < preserved.size()) {
      DWORD chunk = 0;
      BOOL ok = ReadFile(srv, preserved.data() + total_read,
                         static_cast<DWORD>(preserved.size() - total_read), &chunk, &rov);
      DWORD err = ok ? ERROR_SUCCESS : GetLastError();
      if (!ok && err == ERROR_IO_PENDING) {
        ok = GetOverlappedResult(srv, &rov, &chunk, TRUE);
        err = ok ? ERROR_SUCCESS : GetLastError();
      }
      if (!ok || chunk == 0) break;
      total_read += chunk;
    }
    if (rov.hEvent) CloseHandle(rov.hEvent);
    preserved.resize(total_read);
  }

  // Acquire the pipe_mutex if present so no concurrent PipeAdmission inspection races reconnect.
  std::wstring gate_name = L"Local\\gesher-pipe-";
  for (size_t i = 0; i < 32 && shm->pipe_gate[i]; ++i) {
    gate_name += static_cast<wchar_t>(shm->pipe_gate[i]);
  }
  HANDLE gate = CreateMutexW(nullptr, FALSE, gate_name.c_str());
  bool gate_locked = false;
  if (gate) {
    DWORD gw = WaitForSingleObject(gate, 100);
    gate_locked = (gw == WAIT_OBJECT_0 || gw == WAIT_ABANDONED);
  }

  DisconnectNamedPipe(srv);
  OVERLAPPED cov{};
  cov.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  BOOL c_ok = ConnectNamedPipe(srv, &cov);
  DWORD c_err = c_ok ? ERROR_SUCCESS : GetLastError();
  raw_cli = CreateFileW(pname.c_str(),
                        GENERIC_READ | GENERIC_WRITE | FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES,
                        0, nullptr, OPEN_EXISTING, FILE_FLAG_OVERLAPPED, nullptr);
  DWORD cli_err = GetLastError();
  if (raw_cli != INVALID_HANDLE_VALUE && !c_ok && c_err == ERROR_IO_PENDING) {
    DWORD dummy = 0;
    GetOverlappedResult(srv, &cov, &dummy, TRUE);
  } else if (cov.hEvent) {
    CancelIoEx(srv, &cov);
  }
  if (cov.hEvent) CloseHandle(cov.hEvent);

  bool success = false;
  if (raw_cli != INVALID_HANDLE_VALUE) {
    if (!preserved.empty()) {
      size_t off = 0;
      OVERLAPPED wov{};
      wov.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
      while (off < preserved.size()) {
        DWORD put = 0;
        BOOL wok = WriteFile(raw_cli, preserved.data() + off,
                             static_cast<DWORD>(std::min<size_t>(preserved.size() - off, kPipeBufSize)),
                             &put, &wov);
        DWORD werr = wok ? ERROR_SUCCESS : GetLastError();
        if (!wok && werr == ERROR_IO_PENDING) {
          wok = GetOverlappedResult(raw_cli, &wov, &put, TRUE);
        }
        if (!wok || put == 0) break;
        off += put;
      }
      if (wov.hEvent) CloseHandle(wov.hEvent);
    }
    if (DuplicateHandle(GetCurrentProcess(), raw_cli, GetCurrentProcess(), write_out,
                        kClientDesired, FALSE, 0)) {
      shm->connected_once = 1;
      success = true;
    } else {
      cli_err = GetLastError();
    }
    CloseHandle(raw_cli);
  }

  if (gate_locked) ReleaseMutex(gate);
  if (gate) CloseHandle(gate);
  CloseHandle(srv);
  if (!success) {
    errno = ErrnoFromWin32(cli_err ? cli_err : ERROR_GEN_FAILURE);
    return false;
  }
  return true;
}

bool CreateFreshServerPipe(FifoShm* shm, const FifoKey& key, int accmode, HANDLE* primary_out,
                           HANDLE* holder_out) {
  const std::wstring pname = FifoPipeName(key, shm->pipe_generation);
  HANDLE srv = CreateNamedPipeW(
      pname.c_str(), PIPE_ACCESS_DUPLEX | FILE_FLAG_FIRST_PIPE_INSTANCE | FILE_FLAG_OVERLAPPED,
      PIPE_TYPE_MESSAGE | PIPE_READMODE_BYTE | PIPE_REJECT_REMOTE_CLIENTS, 1, kPipeBufSize,
      kPipeBufSize, 0, nullptr);
  if (srv == INVALID_HANDLE_VALUE) return FailWithLastError(), false;
  const DWORD primary_access =
      (accmode == O_RDWR ? (FILE_READ_DATA | FILE_WRITE_DATA) : FILE_READ_DATA) |
      FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES | SYNCHRONIZE;
  const DWORD holder_access =
      FILE_READ_DATA | FILE_WRITE_DATA | FILE_APPEND_DATA |
      FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES | SYNCHRONIZE;
  HANDLE primary = nullptr, holder = nullptr;
  BOOL ok1 = DuplicateHandle(GetCurrentProcess(), srv, GetCurrentProcess(), &primary,
                             primary_access, FALSE, 0);
  BOOL ok2 = DuplicateHandle(GetCurrentProcess(), srv, GetCurrentProcess(), &holder,
                             holder_access, FALSE, 0);
  DWORD err = GetLastError();
  CloseHandle(srv);
  if (!ok1 || !ok2) {
    if (primary) CloseHandle(primary);
    if (holder) CloseHandle(holder);
    errno = ErrnoFromWin32(err);
    return false;
  }
  *primary_out = primary;
  *holder_out = holder;
  return true;
}

// Hook called by ~OpenFileDescription() to drop process holders before closing handles.
void FifoOfdCleanup(uint32_t vol, uint32_t idx_hi, uint32_t idx_lo,
                    HANDLE read_holder, HANDLE write_holder) {
  const int saved = errno;
  const FifoKey key{vol, idx_hi, idx_lo};
  if (read_holder || write_holder) {
    FifoShmSession shm;
    if (shm.Open(key) && shm.Lock()) {
      if (read_holder) RemoveHolder(shm.get()->readers, kMaxFifoHolders, read_holder);
      if (write_holder) RemoveHolder(shm.get()->writers, kMaxFifoHolders, write_holder);
      shm.Unlock();
    }
  }
  ReleaseFifoShm(key);
  errno = saved;
}

// Hook called by OpenFileDescription::Adopt() in child processes.
void FifoOfdAdopt(OpenFileDescription* description, HANDLE file_handle) {
  if (!description || !file_handle || file_handle == INVALID_HANDLE_VALUE) return;
  auto* view = description->shared.load(std::memory_order_acquire);
  if (!view || (!view->fifo_vol && !view->fifo_idx_hi && !view->fifo_idx_lo)) return;
  const FifoKey key{view->fifo_vol, view->fifo_idx_hi, view->fifo_idx_lo};
  const int acc = description->Flags() & O_ACCMODE;
  const int saved = errno;
  RetainFifoShm(key);
  FifoShmSession shm;
  if (shm.Open(key) && shm.Lock()) {
    if (acc == O_RDONLY || acc == O_RDWR) {
      HANDLE rh = nullptr;
      if (DuplicateHandle(GetCurrentProcess(), file_handle, GetCurrentProcess(), &rh,
                          FILE_READ_DATA | FILE_WRITE_DATA | FILE_APPEND_DATA |
                              FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES | SYNCHRONIZE,
                          FALSE, 0)) {
        if (AddHolder(shm.get()->readers, kMaxFifoHolders, rh)) {
          description->fifo_read_holder = rh;
        } else {
          CloseHandle(rh);
        }
      }
    }
    if (acc == O_WRONLY) {
      HANDLE wh = nullptr;
      if (DuplicateHandle(GetCurrentProcess(), file_handle, GetCurrentProcess(), &wh,
                          FILE_WRITE_DATA | FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES | SYNCHRONIZE,
                          FALSE, 0)) {
        if (AddHolder(shm.get()->writers, kMaxFifoHolders, wh)) {
          description->fifo_write_handle = wh;
        } else {
          CloseHandle(wh);
        }
      }
    } else if (acc == O_RDWR) {
      HANDLE wh = nullptr;
      if (ConnectOrReconnectWriterLocked(shm.get(), key, &wh)) {
        if (AddHolder(shm.get()->writers, kMaxFifoHolders, wh)) {
          description->fifo_write_handle = wh;
        } else {
          CloseHandle(wh);
        }
      }
    }
    shm.Unlock();
  }
  description->fifo_cleanup = FifoOfdCleanup;
  errno = saved;
}

struct FifoStartupRegistration {
  FifoStartupRegistration() {
    RegisterFifoAdoptHook(FifoOfdAdopt, FifoOfdCleanup);
    // In case OFD StartupImport ran before this static initializer, adopt any
    // inherited FIFO descriptions already in the process table.
    const int saved = errno;
    std::vector<std::pair<int, DescriptorSnapshotPtr>> all;
    if (CaptureDescriptors(&all, true) == 0) {
      for (const auto& entry : all) {
        if (entry.second && entry.second->description && entry.second->description->IsFifo() &&
            !entry.second->description->fifo_read_holder &&
            !entry.second->description->fifo_write_handle) {
          FifoOfdAdopt(entry.second->description.get(), entry.second->handle);
        }
      }
    }
    errno = saved;
  }
};
FifoStartupRegistration g_fifo_startup;

HANDLE EnsureOdrwrWriteHandle(const DescriptorSnapshotPtr& snapshot) {
  auto& desc = *snapshot->description;
  std::lock_guard<std::mutex> lock(desc.mutex);
  if (desc.fifo_write_handle && desc.fifo_write_handle != INVALID_HANDLE_VALUE) {
    return desc.fifo_write_handle;
  }
  auto* view = desc.shared.load(std::memory_order_acquire);
  if (!view) return nullptr;
  const FifoKey key{view->fifo_vol, view->fifo_idx_hi, view->fifo_idx_lo};
  FifoShmSession shm;
  if (!shm.Open(key) || !shm.Lock()) return nullptr;
  HANDLE wh = nullptr;
  if (ConnectOrReconnectWriterLocked(shm.get(), key, &wh)) {
    AddHolder(shm.get()->writers, kMaxFifoHolders, wh);
    desc.fifo_write_handle = wh;
    desc.fifo_cleanup = FifoOfdCleanup;
  }
  shm.Unlock();
  return wh;
}

// Waits on `ev` while honoring pthread cancellation. Returns 0 if `ev` fired,
// or -1 with errno=EINTR on cancellation/interrupt.
int WaitEventInterruptible(HANDLE ev, HANDLE canceled) {
  HANDLE handles[2] = {ev, canceled};
  DWORD count = canceled ? 2u : 1u;
  DWORD w = WaitForMultipleObjects(count, handles, FALSE, INFINITE);
  if (w == WAIT_OBJECT_0) return 0;
  if (canceled && w == WAIT_OBJECT_0 + 1) {
    errno = EINTR;
    return -1;
  }
  return FailWithLastError();
}

}  // namespace

bool IsFifoHandle(HANDLE h) {
  if (!h || h == INVALID_HANDLE_VALUE) return false;
  FILE_ATTRIBUTE_TAG_INFO tag{};
  if (!GetFileInformationByHandleEx(h, FileAttributeTagInfo, &tag, sizeof(tag))) return false;
  return (tag.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0 &&
         tag.ReparseTag == kLxFifoReparseTag;
}

bool IsFifoPath(const std::wstring& windows) {
  HANDLE h = CreateFileW(windows.c_str(), FILE_READ_ATTRIBUTES,
                         FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
                         OPEN_EXISTING,
                         FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
  if (h == INVALID_HANDLE_VALUE) return false;
  bool fifo = IsFifoHandle(h);
  CloseHandle(h);
  return fifo;
}

bool ReadFifoMode(HANDLE h, mode_t* mode_out) {
  if (!IsFifoHandle(h)) return false;
  const EaApi& ea = GetEaApi();
  if (ea.query) {
    struct GetEa {
      ULONG next;
      UCHAR name_len;
      char name[kFifoModeEaNameLen + 1];
    } req{0, kFifoModeEaNameLen, {}};
    std::memcpy(req.name, kFifoModeEaName, kFifoModeEaNameLen + 1);
    alignas(8) unsigned char out[64]{};
    IoStatus iosb{};
    if (ea.query(h, &iosb, out, sizeof(out), TRUE, &req, sizeof(req), nullptr, TRUE) >= 0) {
      FullModeEa parsed{};
      std::memcpy(&parsed, out, sizeof(parsed) < sizeof(out) ? sizeof(parsed) : sizeof(out));
      if (parsed.ea_value_length == sizeof(uint32_t)) {
        uint32_t value = 0;
        std::memcpy(&value, out + offsetof(FullModeEa, ea_name) + parsed.ea_name_length + 1,
                    sizeof(value));
        if (value <= 0777u) {
          if (mode_out) *mode_out = static_cast<mode_t>(value);
          return true;
        }
      }
    }
  }
  FILE_BASIC_INFO basic{};
  if (GetFileInformationByHandleEx(h, FileBasicInfo, &basic, sizeof(basic))) {
    const bool ro = (basic.FileAttributes & FILE_ATTRIBUTE_READONLY) != 0;
    if (mode_out) *mode_out = ro ? 0444 : 0644;
  } else if (mode_out) {
    *mode_out = 0644;
  }
  return true;
}

bool WriteFifoMode(HANDLE h, mode_t mode) {
  const EaApi& ea = GetEaApi();
  if (!ea.set) return false;
  alignas(8) unsigned char in[sizeof(FullModeEa) + 8]{};
  FullModeEa full{};
  full.ea_name_length = kFifoModeEaNameLen;
  full.ea_value_length = sizeof(uint32_t);
  std::memcpy(full.ea_name, kFifoModeEaName, kFifoModeEaNameLen + 1);
  const uint32_t val = static_cast<uint32_t>(mode & 0777);
  std::memcpy(in, &full, offsetof(FullModeEa, value));
  std::memcpy(in + offsetof(FullModeEa, ea_name) + kFifoModeEaNameLen + 1, &val, sizeof(val));
  IoStatus iosb{};
  return ea.set(h, &iosb, in, sizeof(in)) >= 0;
}

HANDLE OpenPathMaybeFifo(const std::wstring& windows, DWORD access, bool follow,
                         bool* is_fifo, int depth) {
  if (is_fifo) *is_fifo = false;
  HANDLE h = CreateFileW(windows.c_str(), access,
                         FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
                         OPEN_EXISTING,
                         FILE_FLAG_BACKUP_SEMANTICS | (follow ? 0 : FILE_FLAG_OPEN_REPARSE_POINT),
                         nullptr);
  if (h != INVALID_HANDLE_VALUE) {
    if (is_fifo && !follow) *is_fifo = IsFifoHandle(h);
    return h;
  }
  if (!follow || GetLastError() != ERROR_CANT_ACCESS_FILE) return INVALID_HANDLE_VALUE;
  HANDLE rep = CreateFileW(windows.c_str(), access,
                           FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
                           OPEN_EXISTING,
                           FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
  if (rep == INVALID_HANDLE_VALUE) {
    SetLastError(ERROR_CANT_ACCESS_FILE);
    return INVALID_HANDLE_VALUE;
  }
  if (IsFifoHandle(rep)) {
    if (is_fifo) *is_fifo = true;
    return rep;
  }
  if (IsSymlinkHandle(rep) && depth < 8) {
    std::string target;
    bool got = ReadSymlinkHandle(rep, &target);
    CloseHandle(rep);
    if (!got || target.empty()) {
      SetLastError(ERROR_FILE_NOT_FOUND);
      return INVALID_HANDLE_VALUE;
    }
    std::string next_linux;
    if (target[0] == '/' || target[0] == '\\' ||
        (target.size() >= 2 && target[1] == ':')) {
      next_linux = target;
    } else {
      std::string cur = LinuxPath(windows.c_str());
      size_t slash = cur.find_last_of('/');
      next_linux = (slash == std::string::npos ? "" : cur.substr(0, slash + 1)) + target;
    }
    std::wstring next_win;
    if (MapPath(next_linux.c_str(), &next_win) != PathKind::kFile) {
      SetLastError(ERROR_FILE_NOT_FOUND);
      return INVALID_HANDLE_VALUE;
    }
    return OpenPathMaybeFifo(next_win, access, true, is_fifo, depth + 1);
  }
  CloseHandle(rep);
  SetLastError(ERROR_CANT_ACCESS_FILE);
  return INVALID_HANDLE_VALUE;
}

int OpenFifo(const std::wstring& windows, int flags, bool* handled) {
  *handled = false;
  // A FIFO is a reparse point. A path that exists without that attribute is a regular
  // file or a directory, so the common open skips the extra open and close of a probe handle.
  const DWORD attributes = GetFileAttributesW(windows.c_str());
  if (attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_REPARSE_POINT) == 0) return -1;
  const bool follow = (flags & O_NOFOLLOW) == 0;
  bool is_fifo = false;
  HANDLE h = OpenPathMaybeFifo(windows, FILE_READ_ATTRIBUTES | FILE_READ_EA, follow, &is_fifo);
  if (h == INVALID_HANDLE_VALUE) {
    // Also check without following if O_CREAT|O_EXCL might hit a FIFO directly.
    if ((flags & (O_CREAT | O_EXCL)) == (O_CREAT | O_EXCL) && IsFifoPath(windows)) {
      *handled = true;
      errno = EEXIST;
      return -1;
    }
    return -1;
  }
  if (!is_fifo) {
    CloseHandle(h);
    return -1;
  }
  *handled = true;

  if ((flags & (O_CREAT | O_EXCL)) == (O_CREAT | O_EXCL)) {
    CloseHandle(h);
    return errno = EEXIST, -1;
  }
  if ((flags & O_DIRECTORY) != 0) {
    CloseHandle(h);
    return errno = ENOTDIR, -1;
  }

  BY_HANDLE_FILE_INFORMATION finfo{};
  mode_t fifo_mode = 0644;
  ReadFifoMode(h, &fifo_mode);
  if (!GetFileInformationByHandle(h, &finfo)) {
    int err = ErrnoFromWin32(GetLastError());
    CloseHandle(h);
    return errno = err, -1;
  }

  if ((flags & O_PATH) != 0) {
    // O_PATH returns a non-blocking path descriptor without triggering FIFO rendezvous.
    if ((flags & O_CLOEXEC) != 0) SetHandleInformation(h, HANDLE_FLAG_INHERIT, 0);
    else SetHandleInformation(h, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT);
    record_locks::DescriptorGuard descriptor_guard;
    int fd = CrtResult(_open_osfhandle(reinterpret_cast<intptr_t>(h),
                                       _O_BINARY | ((flags & O_CLOEXEC) != 0 ? _O_NOINHERIT : 0)));
    if (fd < 0) { CloseHandle(h); return -1; }
    if (RegisterOfd(fd, flags) < 0) {
      int saved = errno;
      _close(fd);
      return errno = saved, -1;
    }
    return fd;
  }

  // Release the filesystem reparse-point handle immediately so unlink() works cleanly.
  CloseHandle(h);

  const FifoKey key{finfo.dwVolumeSerialNumber, finfo.nFileIndexHigh, finfo.nFileIndexLow};
  const int acc = flags & O_ACCMODE;
  const bool nonblock = (flags & O_NONBLOCK) != 0;

  FifoShmSession shm;
  if (!shm.Open(key) || !shm.Lock()) return -1;

  HANDLE read_end = nullptr, read_holder = nullptr;
  HANDLE write_end = nullptr, write_holder = nullptr;
  char pipe_gate[33]{};
  uint64_t seen_writer_gen = 0;
  bool shm_retained = false;

  auto cleanup_handles = [&]() {
    if (shm.Lock()) {
      if (read_holder) RemoveHolder(shm.get()->readers, kMaxFifoHolders, read_holder);
      if (write_holder) RemoveHolder(shm.get()->writers, kMaxFifoHolders, write_holder);
      shm.Unlock();
    }
    if (read_holder) CloseHandle(read_holder);
    if (write_holder) CloseHandle(write_holder);
    if (read_end) CloseHandle(read_end);
    if (write_end) CloseHandle(write_end);
    if (shm_retained) {
      ReleaseFifoShm(key);
      shm_retained = false;
    }
  };

  if (acc == O_WRONLY && nonblock) {
    if (CountLiveHolders(shm.get()->readers, kMaxFifoHolders) == 0) {
      shm.Unlock();
      return errno = ENXIO, -1;
    }
  }

  // Reader side setup (O_RDONLY or O_RDWR).
  if (acc == O_RDONLY || acc == O_RDWR) {
    size_t existing_readers = CountLiveHolders(shm.get()->readers, kMaxFifoHolders);
    if (existing_readers > 0) {
      const DWORD primary_access =
          (acc == O_RDWR ? (FILE_READ_DATA | FILE_WRITE_DATA) : FILE_READ_DATA) |
          FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES | SYNCHRONIZE;
      const DWORD holder_access =
          FILE_READ_DATA | FILE_WRITE_DATA | FILE_APPEND_DATA |
          FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES | SYNCHRONIZE;
      if (!AcquireLiveHolderHandle(shm.get()->readers, kMaxFifoHolders, primary_access, &read_end) ||
          !AcquireLiveHolderHandle(shm.get()->readers, kMaxFifoHolders, holder_access, &read_holder)) {
        existing_readers = 0;
        if (read_end) { CloseHandle(read_end); read_end = nullptr; }
        if (read_holder) { CloseHandle(read_holder); read_holder = nullptr; }
      }
    }
    if (existing_readers == 0) {
      // Starting a new server instance; bump generation if previous generation had state.
      if (shm.get()->connected_once || CountLiveHolders(shm.get()->writers, kMaxFifoHolders) > 0) {
        shm.get()->pipe_generation++;
        shm.get()->connected_once = 0;
        if (!GenerateGateHex(shm.get()->pipe_gate)) {
          shm.Unlock();
          return -1;
        }
      }
      if (!CreateFreshServerPipe(shm.get(), key, acc, &read_end, &read_holder)) {
        int saved = errno;
        shm.Unlock();
        return errno = saved, -1;
      }
    }
    std::memcpy(pipe_gate, shm.get()->pipe_gate, 33);
    if (!AddHolder(shm.get()->readers, kMaxFifoHolders, read_holder)) {
      cleanup_handles();
      return errno = ENOMEM, -1;
    }
    const uint64_t start_writer_opens = shm.get()->writer_opens;
    const size_t current_writers = CountLiveHolders(shm.get()->writers, kMaxFifoHolders);
    shm.get()->reader_opens++;
    seen_writer_gen = current_writers > 0 && start_writer_opens > 0
                          ? start_writer_opens - 1
                          : start_writer_opens;
    WakeWaitersLocked(shm.get(), 0);  // wake blocked O_WRONLY openers

    if (acc == O_RDONLY && !nonblock) {
      int previous = PTHREAD_CANCEL_DISABLE;
      pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &previous);
      HANDLE canceled = previous == PTHREAD_CANCEL_ENABLE
                            ? static_cast<HANDLE>(pthread_getevent())
                            : nullptr;
      bool aborted = false;
      while (CountLiveHolders(shm.get()->writers, kMaxFifoHolders) == 0 &&
             shm.get()->writer_opens == start_writer_opens) {
        uint64_t wseq = 0;
        HANDLE wev = nullptr;
        if (!RegisterWaiterLocked(shm.get(), 1, &wseq, &wev)) {
          aborted = true;
          break;
        }
        shm.Unlock();
        int wr = WaitEventInterruptible(wev, canceled);
        int werr = errno;
        CloseHandle(wev);
        if (!shm.Lock()) {
          aborted = true;
          break;
        }
        UnregisterWaiterLocked(shm.get(), wseq);
        if (wr < 0) {
          errno = werr;
          aborted = true;
          break;
        }
      }
      if (aborted) {
        int saved = errno;
        cleanup_handles();
        pthread_setcancelstate(previous, nullptr);
        pthread_testcancel();
        return errno = saved, -1;
      }
      pthread_setcancelstate(previous, nullptr);
      pthread_testcancel();
    }
  }

  // Writer side setup (O_WRONLY or O_RDWR).
  if (acc == O_WRONLY || acc == O_RDWR) {
    if (acc == O_WRONLY && !nonblock) {
      const uint64_t start_reader_opens = shm.get()->reader_opens;
      int previous = PTHREAD_CANCEL_DISABLE;
      pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &previous);
      HANDLE canceled = previous == PTHREAD_CANCEL_ENABLE
                            ? static_cast<HANDLE>(pthread_getevent())
                            : nullptr;
      bool aborted = false;
      while (CountLiveHolders(shm.get()->readers, kMaxFifoHolders) == 0 &&
             shm.get()->reader_opens == start_reader_opens) {
        uint64_t wseq = 0;
        HANDLE wev = nullptr;
        if (!RegisterWaiterLocked(shm.get(), 0, &wseq, &wev)) {
          aborted = true;
          break;
        }
        shm.Unlock();
        int wr = WaitEventInterruptible(wev, canceled);
        int werr = errno;
        CloseHandle(wev);
        if (!shm.Lock()) {
          aborted = true;
          break;
        }
        UnregisterWaiterLocked(shm.get(), wseq);
        if (wr < 0) {
          errno = werr;
          aborted = true;
          break;
        }
      }
      if (aborted) {
        int saved = errno;
        cleanup_handles();
        pthread_setcancelstate(previous, nullptr);
        pthread_testcancel();
        return errno = saved, -1;
      }
      pthread_setcancelstate(previous, nullptr);
      pthread_testcancel();
    }

    if (CountLiveHolders(shm.get()->readers, kMaxFifoHolders) == 0) {
      // A reader rendezvoused briefly and closed before we ran. Give the writer
      // a disconnected pipe endpoint so writes raise EPIPE, matching Linux.
      const std::wstring tmp_name = FifoPipeName(key, ++shm.get()->pipe_generation);
      if (!GenerateGateHex(shm.get()->pipe_gate)) {
        cleanup_handles();
        return -1;
      }
      HANDLE tmp_srv = CreateNamedPipeW(
          tmp_name.c_str(), PIPE_ACCESS_DUPLEX | FILE_FLAG_FIRST_PIPE_INSTANCE | FILE_FLAG_OVERLAPPED,
          PIPE_TYPE_MESSAGE | PIPE_READMODE_BYTE | PIPE_REJECT_REMOTE_CLIENTS, 1,
          kPipeBufSize, kPipeBufSize, 0, nullptr);
      HANDLE tmp_cli = tmp_srv != INVALID_HANDLE_VALUE
                           ? CreateFileW(tmp_name.c_str(),
                                         GENERIC_READ | GENERIC_WRITE | FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES,
                                         0, nullptr, OPEN_EXISTING, FILE_FLAG_OVERLAPPED, nullptr)
                           : INVALID_HANDLE_VALUE;
      if (tmp_cli != INVALID_HANDLE_VALUE) {
        DuplicateHandle(GetCurrentProcess(), tmp_cli, GetCurrentProcess(), &write_end,
                        FILE_WRITE_DATA | FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES | SYNCHRONIZE,
                        FALSE, 0);
        CloseHandle(tmp_cli);
      }
      if (tmp_srv != INVALID_HANDLE_VALUE) CloseHandle(tmp_srv);
      if (!write_end) {
        cleanup_handles();
        return errno = EPIPE, -1;
      }
    } else {
      if (!ConnectOrReconnectWriterLocked(shm.get(), key, &write_end)) {
        int saved = errno;
        cleanup_handles();
        return errno = saved, -1;
      }
    }
    std::memcpy(pipe_gate, shm.get()->pipe_gate, 33);
    if (!DuplicateHandle(GetCurrentProcess(), write_end, GetCurrentProcess(), &write_holder,
                         FILE_WRITE_DATA | FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES | SYNCHRONIZE,
                         FALSE, 0) ||
        !AddHolder(shm.get()->writers, kMaxFifoHolders, write_holder)) {
      cleanup_handles();
      return errno = ENOMEM, -1;
    }
    shm.get()->writer_opens++;
    WakeWaitersLocked(shm.get(), 1);  // wake blocked O_RDONLY openers
  }

  RetainFifoShm(key);
  shm_retained = true;
  shm.Unlock();

  HANDLE primary = (acc == O_WRONLY) ? write_end : read_end;
  HANDLE holder_for_write = (acc == O_RDWR) ? write_end : write_holder;
  if (acc == O_RDWR && write_holder) {
    // write_end itself is writable and held as fifo_write_handle, so we don't need a duplicate holder.
    if (shm.Lock()) {
      RemoveHolder(shm.get()->writers, kMaxFifoHolders, write_holder);
      AddHolder(shm.get()->writers, kMaxFifoHolders, write_end);
      shm.Unlock();
    }
    CloseHandle(write_holder);
    write_holder = nullptr;
  }
  SetHandleInformation(primary, HANDLE_FLAG_INHERIT,
                       (flags & O_CLOEXEC) != 0 ? 0 : HANDLE_FLAG_INHERIT);

  record_locks::DescriptorGuard descriptor_guard;
  int crt_flags = _O_BINARY |
                  (acc == O_RDONLY ? _O_RDONLY : acc == O_WRONLY ? _O_WRONLY : _O_RDWR) |
                  ((flags & O_CLOEXEC) != 0 ? _O_NOINHERIT : 0);
  int fd = CrtResult(_open_osfhandle(reinterpret_cast<intptr_t>(primary), crt_flags));
  if (fd < 0) {
    int saved = errno;
    if (acc == O_RDWR) write_end = nullptr;
    cleanup_handles();
    return errno = saved, -1;
  }
  if (acc == O_WRONLY) write_end = nullptr;
  else read_end = nullptr;

  if (RegisterOfd(fd, flags) < 0) {
    int saved = errno;
    _close(fd);
    if (acc == O_RDWR && write_end) {
      if (shm.Lock()) { RemoveHolder(shm.get()->writers, kMaxFifoHolders, write_end); shm.Unlock(); }
      CloseHandle(write_end);
    }
    cleanup_handles();
    return errno = saved, -1;
  }
  auto snapshot = CaptureDescriptor(fd);
  if (!snapshot ||
      InitializeFifoDescription(snapshot, flags, key.vol, key.idx_hi, key.idx_lo,
                                static_cast<uint32_t>(fifo_mode), seen_writer_gen,
                                pipe_gate, holder_for_write) < 0) {
    int saved = errno;
    _close(fd);
    ForgetOfd(fd);
    if (acc == O_RDWR && write_end) {
      if (shm.Lock()) { RemoveHolder(shm.get()->writers, kMaxFifoHolders, write_end); shm.Unlock(); }
      CloseHandle(write_end);
    }
    cleanup_handles();
    return errno = saved, -1;
  }
  snapshot->description->fifo_read_holder = read_holder;
  read_holder = nullptr;
  write_holder = nullptr;
  holder_for_write = nullptr;
  shm_retained = false;
  return fd;
}

bool StatFifoDescription(const DescriptorSnapshotPtr& snapshot, mode_t* mode_out,
                         unsigned long long* dev_out, unsigned long long* ino_out) {
  if (!snapshot || !snapshot->description || !snapshot->description->IsFifo()) return false;
  auto* view = snapshot->description->shared.load(std::memory_order_acquire);
  if (!view) return false;
  if (mode_out) *mode_out = static_cast<mode_t>(view->fifo_mode & 0777);
  if (dev_out) *dev_out = view->fifo_vol;
  if (ino_out) {
    *ino_out = (static_cast<unsigned long long>(view->fifo_idx_hi) << 32) | view->fifo_idx_lo;
  }
  return true;
}

int TransferFifo(const DescriptorSnapshotPtr& snapshot, void* bytes, unsigned count,
                 bool writing, HANDLE canceled, HANDLE interrupted) {
  if (!count) return 0;
  if (!bytes) return errno = EFAULT, -1;
  auto& desc = *snapshot->description;
  const int flags = desc.Flags();
  const int acc = flags & O_ACCMODE;
  const bool nonblocking = (flags & O_NONBLOCK) != 0;

  HANDLE target = snapshot->handle;
  if (writing && acc == O_RDWR) {
    target = desc.fifo_write_handle;
    if (!target || target == INVALID_HANDLE_VALUE) {
      target = EnsureOdrwrWriteHandle(snapshot);
      if (!target) return errno = EPIPE, -1;
    }
  }

  PipeLocalInfo info{};
  if (QueryPipeLocal(target, &info) < 0) return -1;

  if (!writing) {
    if (info.ReadDataAvailable == 0) {
      if (info.NamedPipeState == FILE_PIPE_LISTENING_STATE ||
          info.NamedPipeState == FILE_PIPE_DISCONNECTED_STATE ||
          info.NamedPipeState == FILE_PIPE_CLOSING_STATE) {
        // On Linux, read() on a FIFO with 0 writers always returns 0 (EOF),
        // whether or not a writer has ever opened.
        return 0;
      }
      if (nonblocking) return errno = EAGAIN, -1;
    } else if (nonblocking) {
      count = std::min<unsigned>(count, info.ReadDataAvailable);
    }
    return NativeFifoOverlappedTransfer(target, bytes, count, false, canceled, interrupted);
  }

  // Writing:
  if (info.NamedPipeState != FILE_PIPE_CONNECTED_STATE) {
    return errno = EPIPE, -1;
  }
  if (nonblocking) {
    if (count <= kAtomicPipeBuf) {
      if (info.WriteQuotaAvailable < count) return errno = EAGAIN, -1;
    } else {
      if (info.WriteQuotaAvailable == 0) return errno = EAGAIN, -1;
      count = std::min<unsigned>(count, info.WriteQuotaAvailable);
    }
  }
  return NativeFifoOverlappedTransfer(target, bytes, count, true, canceled, interrupted);
}

int PollFifoHandle(const DescriptorSnapshotPtr& snapshot, short events, short* ready) {
  *ready = 0;
  auto& desc = *snapshot->description;
  const int flags = desc.Flags();
  const int acc = flags & O_ACCMODE;
  auto* view = desc.shared.load(std::memory_order_acquire);
  if (!view) return errno = EBADF, -1;

  short result = 0;
  if (acc != O_WRONLY) {
    PipeLocalInfo info{};
    if (QueryPipeLocal(snapshot->handle, &info) < 0) return -1;
    if (info.ReadDataAvailable > 0) {
      result |= events & (POLLIN | POLLRDNORM);
    }
    if (info.NamedPipeState == FILE_PIPE_CLOSING_STATE) {
      // Only report POLLHUP if a writer was present during or after this open.
      bool had_writer_since_open = true;
      FifoShmSession shm;
      if (shm.Open({view->fifo_vol, view->fifo_idx_hi, view->fifo_idx_lo}) && shm.Lock()) {
        had_writer_since_open = (shm.get()->writer_opens != view->fifo_writer_gen);
        shm.Unlock();
      }
      if (had_writer_since_open) result |= POLLHUP;
    }
  }
  if (acc != O_RDONLY) {
    HANDLE wh = (acc == O_RDWR) ? desc.fifo_write_handle : snapshot->handle;
    if (acc == O_RDWR && (!wh || wh == INVALID_HANDLE_VALUE)) {
      wh = EnsureOdrwrWriteHandle(snapshot);
    }
    if (!wh || wh == INVALID_HANDLE_VALUE) {
      result |= POLLERR;
    } else {
      PipeLocalInfo info{};
      if (QueryPipeLocal(wh, &info) < 0) return -1;
      if (info.NamedPipeState != FILE_PIPE_CONNECTED_STATE) {
        result |= POLLERR;
      } else if (info.WriteQuotaAvailable >= kAtomicPipeBuf) {
        result |= events & (POLLOUT | POLLWRNORM);
      }
    }
  }
  *ready = result;
  return 0;
}

int FifoBytesAvailable(const DescriptorSnapshotPtr& snapshot, int* bytes) {
  if (!bytes) return errno = EFAULT, -1;
  if ((snapshot->description->Flags() & O_ACCMODE) == O_WRONLY) return errno = EOPNOTSUPP, -1;
  PipeLocalInfo info{};
  if (QueryPipeLocal(snapshot->handle, &info) < 0) return -1;
  *bytes = static_cast<int>(std::min<ULONG>(info.ReadDataAvailable, 0x7fffffffu));
  return 0;
}

}  // namespace gesher

extern "C" {

int mkfifo(const char* path, mode_t mode) {
  if (path == nullptr) return errno = EFAULT, -1;
  if (path[0] == '\0') return errno = ENOENT, -1;
  size_t len = strlen(path);
  if (path[len - 1] == '/' || path[len - 1] == '\\') {
    std::wstring existing;
    if (gesher::MapPath(path, &existing) == gesher::PathKind::kFile &&
        GetFileAttributesW(existing.c_str()) != INVALID_FILE_ATTRIBUTES) {
      return errno = EEXIST, -1;
    }
    return errno = ENOENT, -1;
  }

  std::wstring windows;
  if (!gesher::DiskPath(path, &windows, EEXIST)) return -1;

  const mode_t effective_mode = (mode & 0777) & ~gesher::ReadCurrentUmask();
  const DWORD attrs =
      ((effective_mode & 0200) == 0 ? FILE_ATTRIBUTE_READONLY : FILE_ATTRIBUTE_NORMAL) |
      FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_BACKUP_SEMANTICS;
  HANDLE h = CreateFileW(windows.c_str(), GENERIC_READ | GENERIC_WRITE | DELETE,
                         FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
                         CREATE_NEW, attrs, nullptr);
  if (h == INVALID_HANDLE_VALUE) {
    DWORD err = GetLastError();
    if (err == ERROR_PATH_NOT_FOUND) {
      size_t sep = windows.find_last_of(L"\\/");
      if (sep != std::wstring::npos && sep > 0) {
        DWORD pattr = GetFileAttributesW(windows.substr(0, sep).c_str());
        if (pattr != INVALID_FILE_ATTRIBUTES && (pattr & FILE_ATTRIBUTE_DIRECTORY) == 0) {
          return errno = ENOTDIR, -1;
        }
      }
    }
    SetLastError(err);
    return gesher::FailWithLastError();
  }

  gesher::WriteFifoMode(h, effective_mode);

  struct {
    DWORD tag;
    WORD data_len;
    WORD reserved;
  } reparse{gesher::kLxFifoReparseTag, 0, 0};
  DWORD bytes = 0;
  BOOL ok = DeviceIoControl(h, FSCTL_SET_REPARSE_POINT, &reparse, sizeof(reparse),
                            nullptr, 0, &bytes, nullptr);
  DWORD err = GetLastError();
  if (!ok) {
    FILE_DISPOSITION_INFO disp{TRUE};
    SetFileInformationByHandle(h, FileDispositionInfo, &disp, sizeof(disp));
    CloseHandle(h);
    SetLastError(err);
    return gesher::FailWithLastError();
  }
  CloseHandle(h);
  return 0;
}

int mkfifoat(int dirfd, const char* path, mode_t mode) {
  std::string resolved;
  if (!gesher::ResolveAt(dirfd, path, &resolved)) return -1;
  return mkfifo(resolved.c_str(), mode);
}

}  // extern "C"
