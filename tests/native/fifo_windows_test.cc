// Cross-process POSIX FIFO contracts on Windows through gesher-base and
// gesher_exec_spawn: reparse points, O_TRUNC preservation, PIPE_BUF atomicity,
// multi-process rendezvous, writer reconnect, O_RDWR, and descriptor spawn inheritance.
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include "exec_spawn.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <io.h>
#include <poll.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/uio.h>
#include <unistd.h>
#include <windows.h>

#include <atomic>
#include <cstdio>
#include <string>
#include <thread>
#include <vector>

namespace {

int g_assertions = 0;
int g_failures = 0;

void Check(const char* name, bool ok) {
  ++g_assertions;
  if (!ok) {
    ++g_failures;
    std::fprintf(stderr, "fifo-host: FAIL %s (errno=%d win32=%lu)\n", name, errno, GetLastError());
  } else {
    std::printf("fifo-host: PASS %s\n", name);
  }
}

std::string MakeTempDir() {
  wchar_t temp[MAX_PATH];
  DWORD n = GetTempPathW(MAX_PATH, temp);
  if (n == 0 || n >= MAX_PATH) return {};
  std::wstring dir = std::wstring(temp, n) + L"gesher-fifo-test-" +
                     std::to_wstring(GetCurrentProcessId());
  CreateDirectoryW(dir.c_str(), nullptr);
  int utf8_len = WideCharToMultiByte(CP_UTF8, 0, dir.c_str(), -1, nullptr, 0, nullptr, nullptr);
  if (utf8_len <= 1) return {};
  std::string out(static_cast<size_t>(utf8_len - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, dir.c_str(), -1, out.data(), utf8_len, nullptr, nullptr);
  return out;
}

void RemoveTempDir(const std::string& utf8) {
  int wlen = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
  if (wlen <= 1) return;
  std::wstring dir(static_cast<size_t>(wlen - 1), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, dir.data(), wlen);
  RemoveDirectoryW(dir.c_str());
}

std::wstring SelfExe() {
  wchar_t buf[4096];
  DWORD n = GetModuleFileNameW(nullptr, buf, 4096);
  return (n > 0 && n < 4096) ? std::wstring(buf, n) : std::wstring();
}

std::wstring Utf8ToWide(const std::string& s) {
  int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, nullptr, 0);
  if (n <= 1) return {};
  std::wstring w(static_cast<size_t>(n - 1), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, w.data(), n);
  return w;
}

HANDLE StartChildProcess(const std::wstring& exe, const std::wstring& args) {
  std::wstring cmd = L"\"" + exe + L"\" " + args;
  STARTUPINFOW si{};
  si.cb = sizeof(si);
  PROCESS_INFORMATION pi{};
  if (!CreateProcessW(exe.c_str(), cmd.data(), nullptr, nullptr, FALSE, 0,
                      nullptr, nullptr, &si, &pi)) {
    return nullptr;
  }
  CloseHandle(pi.hThread);
  return pi.hProcess;
}

DWORD WaitChildProcess(HANDLE proc) {
  if (!proc) return 255;
  DWORD w = WaitForSingleObject(proc, 10000);
  DWORD code = 255;
  if (w == WAIT_OBJECT_0) {
    GetExitCodeProcess(proc, &code);
  } else {
    TerminateProcess(proc, 255);
    WaitForSingleObject(proc, 2000);
  }
  CloseHandle(proc);
  return code;
}

int RunChildMode(const char* mode, const char* path) {
  if (std::strcmp(mode, "--child-write-blocking") == 0) {
    Sleep(40);
    int wfd = open(path, O_WRONLY);
    if (wfd < 0) return 2;
    const char payload[] = "xproc-sync";
    ssize_t n = write(wfd, payload, sizeof(payload) - 1);
    close(wfd);
    return n == static_cast<ssize_t>(sizeof(payload) - 1) ? 0 : 3;
  }
  if (std::strcmp(mode, "--child-read-blocking") == 0) {
    Sleep(40);
    int rfd = open(path, O_RDONLY);
    if (rfd < 0) return 2;
    char buf[32]{};
    ssize_t n = read(rfd, buf, sizeof(buf));
    close(rfd);
    return (n == 8 && std::memcmp(buf, "w2r-sync", 8) == 0) ? 0 : 3;
  }
  if (std::strcmp(mode, "--child-write-nonblock") == 0) {
    int wfd = open(path, O_WRONLY | O_NONBLOCK);
    if (wfd < 0) return 2;
    const char payload[] = "nb-xproc";
    ssize_t n = write(wfd, payload, sizeof(payload) - 1);
    close(wfd);
    return n == static_cast<ssize_t>(sizeof(payload) - 1) ? 0 : 3;
  }
  if (std::strcmp(mode, "--child-write-2nd") == 0) {
    int wfd = open(path, O_WRONLY | O_NONBLOCK);
    if (wfd < 0) return 2;
    const char payload[] = "second";
    ssize_t n = write(wfd, payload, sizeof(payload) - 1);
    close(wfd);
    return n == static_cast<ssize_t>(sizeof(payload) - 1) ? 0 : 3;
  }
  if (std::strcmp(mode, "--child-inherited") == 0) {
    // Expects fd 37 open as FIFO writer (O_WRONLY), fd 38 closed (CLOEXEC).
    if (fcntl(38, F_GETFD) != -1 || errno != EBADF) return 2;
    const char payload[] = "inherited-ok";
    ssize_t n = write(37, payload, sizeof(payload) - 1);
    close(37);
    return n == static_cast<ssize_t>(sizeof(payload) - 1) ? 0 : 3;
  }
  return 99;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc >= 2 && std::strcmp(argv[1], "--child-inherited") == 0) {
    return RunChildMode(argv[1], "");
  }
  if (argc >= 3) {
    return RunChildMode(argv[1], argv[2]);
  }

  const std::string dir = MakeTempDir();
  Check("create temp dir", !dir.empty());
  if (dir.empty()) return 1;

  const std::string fifo_path = dir + "/realm.cv";
  const std::string mknod_path = dir + "/mknod.fifo";
  const std::string umask_path = dir + "/umask.fifo";
  const std::string reg16_path = dir + "/ordinary16.txt";

  // 1. mkfifo creation, EEXIST, ENOENT, umask, mknod(S_IFIFO), stat/lstat/fstat agreement, readdir DT_FIFO.
  errno = 0;
  Check("mkfifo nullptr -> EFAULT", mkfifo(nullptr, 0600) == -1 && errno == EFAULT);
  errno = 0;
  Check("mkfifo empty -> ENOENT", mkfifo("", 0600) == -1 && errno == ENOENT);
  errno = 0;
  Check("mkfifo missing parent -> ENOENT",
        mkfifo((dir + "/no-such-dir/a.fifo").c_str(), 0600) == -1 && errno == ENOENT);

  // Win32 UCRT _umask tracks owner read/write bits (0400/0200).
  int old_mask = _umask(0200);
  Check("mkfifo honors umask", mkfifo(umask_path.c_str(), 0600) == 0);
  _umask(old_mask);
  struct stat ust{};
  Check("stat umask-filtered mode == 0400",
        stat(umask_path.c_str(), &ust) == 0 && S_ISFIFO(ust.st_mode) && (ust.st_mode & 0777) == 0400);
  chmod(umask_path.c_str(), 0600);
  Check("unlink umask fifo", unlink(umask_path.c_str()) == 0);

  Check("mkfifo creates fifo", mkfifo(fifo_path.c_str(), 0600) == 0);
  errno = 0;
  Check("mkfifo duplicate -> EEXIST", mkfifo(fifo_path.c_str(), 0600) == -1 && errno == EEXIST);
  Check("mknod S_IFIFO creates fifo", mknod(mknod_path.c_str(), S_IFIFO | 0600, 0) == 0);

  struct stat st = {};
  Check("stat reports S_ISFIFO mode 0600 size 0",
        stat(fifo_path.c_str(), &st) == 0 && S_ISFIFO(st.st_mode) &&
            (st.st_mode & 0777) == 0600 && st.st_size == 0);
  std::memset(&st, 0, sizeof(st));
  Check("lstat reports S_ISFIFO mode 0600 size 0",
        lstat(mknod_path.c_str(), &st) == 0 && S_ISFIFO(st.st_mode) &&
            (st.st_mode & 0777) == 0600 && st.st_size == 0);

  // readdir reports DT_FIFO.
  {
    DIR* d = opendir(dir.c_str());
    Check("opendir temp dir", d != nullptr);
    bool saw_fifo = false;
    if (d) {
      while (struct dirent* ent = readdir(d)) {
        if (std::strcmp(ent->d_name, "realm.cv") == 0) {
          saw_fifo = (ent->d_type == DT_FIFO);
        }
      }
      closedir(d);
    }
    Check("readdir reports DT_FIFO for fifo", saw_fifo);
  }

  // Ordinary 16-byte file stays S_ISREG.
  {
    int reg = open(reg16_path.c_str(), O_CREAT | O_EXCL | O_RDWR, 0600);
    Check("create ordinary 16-byte file", reg >= 0);
    if (reg >= 0) {
      const char payload[17] = "0123456789abcdef";
      Check("write 16 bytes to regular file", write(reg, payload, 16) == 16);
      close(reg);
      std::memset(&st, 0, sizeof(st));
      Check("stat ordinary 16-byte file -> S_ISREG",
            stat(reg16_path.c_str(), &st) == 0 && S_ISREG(st.st_mode) && st.st_size == 16);
      reg = open(reg16_path.c_str(), O_RDONLY);
      char readback[17] = {};
      Check("read ordinary 16-byte file",
            reg >= 0 && read(reg, readback, 16) == 16 && std::memcmp(readback, payload, 16) == 0);
      if (reg >= 0) close(reg);
    }
    unlink(reg16_path.c_str());
  }

  // 2. O_WRONLY | O_NONBLOCK with no reader -> ENXIO; fresh O_RDONLY | O_NONBLOCK -> no POLLHUP.
  errno = 0;
  Check("O_WRONLY|O_NONBLOCK without reader -> ENXIO",
        open(fifo_path.c_str(), O_WRONLY | O_NONBLOCK) == -1 && errno == ENXIO);

  {
    int rfd = open(fifo_path.c_str(), O_RDONLY | O_NONBLOCK);
    Check("fresh O_RDONLY|O_NONBLOCK opens", rfd >= 0);
    if (rfd >= 0) {
      struct stat fst{};
      Check("fstat agrees with stat mode & S_ISFIFO",
            fstat(rfd, &fst) == 0 && S_ISFIFO(fst.st_mode) && (fst.st_mode & 0777) == 0600);
      struct pollfd pfd{rfd, POLLIN, 0};
      Check("fresh O_RDONLY|O_NONBLOCK poll does NOT report POLLHUP",
            poll(&pfd, 1, 0) == 0 && pfd.revents == 0);
      char tmp = 0;
      Check("read on O_RDONLY|O_NONBLOCK with 0 writers returns 0 (EOF)",
            read(rfd, &tmp, 1) == 0);
      Check("lseek on fifo -> ESPIPE", lseek(rfd, 0, SEEK_CUR) == -1 && errno == ESPIPE);
      Check("ftruncate on fifo -> EINVAL", gesher_ftruncate(rfd, 0) == -1 && errno == EINVAL);
      close(rfd);
    }
  }

  // 3. O_TRUNC does NOT destroy the FIFO and subsequent reader/writer exchange works.
  {
    int rfd = open(fifo_path.c_str(), O_RDONLY | O_NONBLOCK);
    int wfd = open(fifo_path.c_str(), O_WRONLY | O_TRUNC | O_NONBLOCK);
    Check("open O_WRONLY|O_TRUNC on fifo succeeds", rfd >= 0 && wfd >= 0);
    Check("ftruncate on writable fifo -> EINVAL", wfd >= 0 && gesher_ftruncate(wfd, 0) == -1 && errno == EINVAL);
    struct stat after_trunc{};
    Check("fifo stays S_ISFIFO after O_TRUNC",
          stat(fifo_path.c_str(), &after_trunc) == 0 && S_ISFIFO(after_trunc.st_mode));
    if (rfd >= 0 && wfd >= 0) {
      char buf[8]{};
      Check("read/write works after O_TRUNC open",
            write(wfd, "trunc", 5) == 5 && read(rfd, buf, 8) == 5 && std::memcmp(buf, "trunc", 5) == 0);
    }
    if (wfd >= 0) close(wfd);
    if (rfd >= 0) close(rfd);

    int cw = open(fifo_path.c_str(), O_RDWR | O_CREAT | O_TRUNC | O_NONBLOCK, 0600);
    Check("open O_CREAT|O_TRUNC|O_RDWR does not destroy fifo", cw >= 0);
    if (cw >= 0) {
      char c = 0;
      Check("O_RDWR after O_CREAT|O_TRUNC works",
            write(cw, "k", 1) == 1 && read(cw, &c, 1) == 1 && c == 'k');
      close(cw);
    }
  }

  // 4. Realm InterprocessCondVar flow: O_RDWR | O_NONBLOCK + poll + epoll + 1-byte notify.
  {
    int fd = open(fifo_path.c_str(), O_RDWR | O_NONBLOCK | O_CLOEXEC);
    Check("open O_RDWR|O_NONBLOCK", fd >= 0);
    if (fd >= 0) {
      Check("O_CLOEXEC honored on fifo", (fcntl(fd, F_GETFD) & FD_CLOEXEC) != 0);
      Check("F_GETFL on O_RDWR|O_NONBLOCK",
            (fcntl(fd, F_GETFL) & (O_ACCMODE | O_NONBLOCK)) == (O_RDWR | O_NONBLOCK));

      char byte = 0;
      errno = 0;
      Check("empty nonblocking read -> EAGAIN", read(fd, &byte, 1) == -1 && errno == EAGAIN);

      struct pollfd pfd = {fd, POLLIN, 0};
      Check("poll empty O_RDWR fifo -> 0", poll(&pfd, 1, 0) == 0 && pfd.revents == 0);

      int ep = epoll_create1(0);
      struct epoll_event ev = {};
      ev.events = EPOLLIN;
      ev.data.fd = fd;
      Check("epoll_ctl add fifo", ep >= 0 && epoll_ctl(ep, EPOLL_CTL_ADD, fd, &ev) == 0);

      const char ping = 'P';
      Check("write 1 byte to fifo", write(fd, &ping, 1) == 1);

      int avail = -1;
      Check("ioctl FIONREAD == 1", ioctl(fd, FIONREAD, &avail) == 0 && avail == 1);

      pfd = {fd, POLLIN, 0};
      Check("poll readable fifo -> POLLIN", poll(&pfd, 1, 0) == 1 && (pfd.revents & POLLIN) != 0);

      struct epoll_event out_ev = {};
      Check("epoll_wait readable fifo -> EPOLLIN",
            ep >= 0 && epoll_wait(ep, &out_ev, 1, 100) == 1 && (out_ev.events & EPOLLIN) != 0);

      Check("read 1 byte from fifo", read(fd, &byte, 1) == 1 && byte == 'P');
      errno = 0;
      Check("drained nonblocking read -> EAGAIN", read(fd, &byte, 1) == -1 && errno == EAGAIN);

      errno = 0;
      Check("pread on fifo -> ESPIPE", pread(fd, &byte, 1, 0) == -1 && errno == ESPIPE);
      errno = 0;
      Check("pwrite on fifo -> ESPIPE", pwrite(fd, &ping, 1, 0) == -1 && errno == ESPIPE);

      if (ep >= 0) close(ep);
      close(fd);
    }
  }

  // 5. Atomic PIPE_BUF (4096-byte) non-blocking write semantics + EPIPE.
  {
    int rfd = open(fifo_path.c_str(), O_RDONLY | O_NONBLOCK);
    int wfd = open(fifo_path.c_str(), O_WRONLY | O_NONBLOCK);
    Check("open reader/writer for PIPE_BUF test", rfd >= 0 && wfd >= 0);
    if (rfd >= 0 && wfd >= 0) {
      std::vector<char> chunk(4096, 'A');
      int written_chunks = 0;
      while (write(wfd, chunk.data(), chunk.size()) == 4096 && written_chunks < 64) {
        ++written_chunks;
      }
      Check("fill fifo to capacity", written_chunks > 0 && errno == EAGAIN);
      // Drain 2048 bytes so < 4096 bytes free remain.
      std::vector<char> drain(2048);
      Check("drain 2048 bytes", read(rfd, drain.data(), drain.size()) == 2048);
      int before_avail = 0;
      Check("FIONREAD before atomic failure", ioctl(rfd, FIONREAD, &before_avail) == 0);
      errno = 0;
      Check("4096-byte write with only 2048 free -> EAGAIN (all-or-nothing)",
            write(wfd, chunk.data(), 4096) == -1 && errno == EAGAIN);
      int after_avail = 0;
      Check("failed atomic 4096 write left queue untouched",
            ioctl(rfd, FIONREAD, &after_avail) == 0 && after_avail == before_avail);
      close(rfd);
      rfd = -1;
      errno = 0;
      Check("write after all readers closed -> EPIPE", write(wfd, "x", 1) == -1 && errno == EPIPE);
    }
    if (wfd >= 0) close(wfd);
    if (rfd >= 0) close(rfd);
  }

  // 6. Real cross-process rendezvous, data transfer, EOF, and sequential writer reconnect.
  const std::wstring exe = SelfExe();
  const std::wstring wpath = Utf8ToWide(fifo_path);
  Check("resolve self executable", !exe.empty());
  if (!exe.empty()) {
    // 6a. Blocking O_RDONLY in parent unblocked by O_WRONLY in separate child process.
    HANDLE wchild = StartChildProcess(exe, L"--child-write-blocking \"" + wpath + L"\"");
    int rfd = open(fifo_path.c_str(), O_RDONLY);
    Check("parent blocking O_RDONLY unblocked by child process", rfd >= 0);
    char buf[32]{};
    ssize_t n = rfd >= 0 ? read(rfd, buf, sizeof(buf)) : -1;
    Check("parent received cross-process payload", n == 10 && std::memcmp(buf, "xproc-sync", 10) == 0);
    Check("parent sees EOF after child closes writer", rfd >= 0 && read(rfd, buf, sizeof(buf)) == 0);
    struct pollfd hpfd{rfd, POLLIN, 0};
    Check("parent sees POLLHUP after child writer closed",
          rfd >= 0 && poll(&hpfd, 1, 0) == 1 && (hpfd.revents & POLLHUP) != 0);
    Check("child-write-blocking exited 0", WaitChildProcess(wchild) == 0);

    // 6b. New non-blocking child writer opens & writes to the STILL-OPEN parent reader (reconnect!).
    HANDLE wchild2 = StartChildProcess(exe, L"--child-write-2nd \"" + wpath + L"\"");
    Check("child-write-2nd exited 0 against existing parent reader", WaitChildProcess(wchild2) == 0);
    std::memset(buf, 0, sizeof(buf));
    n = rfd >= 0 ? read(rfd, buf, sizeof(buf)) : -1;
    Check("parent received 2nd cross-process writer payload on same fd",
          n == 6 && std::memcmp(buf, "second", 6) == 0);
    if (rfd >= 0) close(rfd);

    // 6c. Blocking O_WRONLY in parent unblocked by O_RDONLY in separate child process.
    HANDLE rchild = StartChildProcess(exe, L"--child-read-blocking \"" + wpath + L"\"");
    int wfd = open(fifo_path.c_str(), O_WRONLY);
    Check("parent blocking O_WRONLY unblocked by child process", wfd >= 0);
    Check("parent wrote cross-process payload to child reader",
          wfd >= 0 && write(wfd, "w2r-sync", 8) == 8);
    if (wfd >= 0) close(wfd);
    Check("child-read-blocking exited 0", WaitChildProcess(rchild) == 0);

    // 6d. Non-blocking child writer sees parent non-blocking reader across processes.
    int nrfd = open(fifo_path.c_str(), O_RDONLY | O_NONBLOCK);
    Check("parent O_RDONLY|O_NONBLOCK open", nrfd >= 0);
    HANDLE nbwchild = StartChildProcess(exe, L"--child-write-nonblock \"" + wpath + L"\"");
    Check("child O_WRONLY|O_NONBLOCK saw parent reader (no ENXIO)", WaitChildProcess(nbwchild) == 0);
    std::memset(buf, 0, sizeof(buf));
    n = nrfd >= 0 ? read(nrfd, buf, sizeof(buf)) : -1;
    Check("parent read nonblocking child payload", n == 8 && std::memcmp(buf, "nb-xproc", 8) == 0);
    if (nrfd >= 0) close(nrfd);

    // 6e. Descriptor inheritance via SpawnWithFds + O_CLOEXEC exclusion + EOF on child exit.
    int inh_rfd = open(fifo_path.c_str(), O_RDONLY | O_NONBLOCK);
    int inh_wfd = open(fifo_path.c_str(), O_WRONLY);
    int clo_wfd = open(fifo_path.c_str(), O_WRONLY | O_CLOEXEC);
    Check("open descriptors for SpawnWithFds inheritance", inh_rfd >= 0 && inh_wfd >= 0 && clo_wfd >= 0);
    if (inh_rfd >= 0 && inh_wfd >= 0 && clo_wfd >= 0) {
      auto cap_w = gesher::CaptureDescriptor(inh_wfd);
      Check("capture inheritable writer snapshot", static_cast<bool>(cap_w));
      std::vector<gesher::exec::ChildFd> child_fds{{37, cap_w->handle, cap_w}};
      gesher::exec::Launch launch;
      launch.application = exe;
      gesher::exec::AppendQuoted(&launch.command_line, exe);
      launch.command_line += L" --child-inherited";
      launch.kind = "exe";
      PROCESS_INFORMATION pi{};
      DWORD serr = gesher::exec::SpawnWithFds(launch, nullptr, L"", child_fds, &pi);
      Check("SpawnWithFds launched child with FIFO fd", serr == 0);
      child_fds.clear();
      cap_w.reset();
      // Parent drops its own writer fds so child owns the sole remaining writer endpoint.
      close(inh_wfd); inh_wfd = -1;
      close(clo_wfd); clo_wfd = -1;
      if (serr == 0) {
        Check("inherited FIFO child exited 0", WaitChildProcess(pi.hProcess) == 0);
        CloseHandle(pi.hThread);
        std::memset(buf, 0, sizeof(buf));
        n = read(inh_rfd, buf, sizeof(buf));
        Check("parent read payload written by SpawnWithFds child",
              n == 12 && std::memcmp(buf, "inherited-ok", 12) == 0);
        Check("parent observed EOF after child exited", read(inh_rfd, buf, sizeof(buf)) == 0);
      }
    }
    if (inh_rfd >= 0) close(inh_rfd);
    if (inh_wfd >= 0) close(inh_wfd);
    if (clo_wfd >= 0) close(clo_wfd);
  }

  // 7. unlink() while open keeps active descriptors working and removes path.
  {
    int fd = open(mknod_path.c_str(), O_RDWR | O_NONBLOCK);
    Check("open mknod fifo before unlink", fd >= 0);
    Check("unlink open fifo succeeds", unlink(mknod_path.c_str()) == 0);
    errno = 0;
    Check("stat unlinked fifo -> ENOENT", stat(mknod_path.c_str(), &st) == -1 && errno == ENOENT);
    if (fd >= 0) {
      const char ch = 'U';
      char out = 0;
      Check("unlinked open fifo still transfers data",
            write(fd, &ch, 1) == 1 && read(fd, &out, 1) == 1 && out == 'U');
      close(fd);
    }
  }

  Check("unlink fifo_path", unlink(fifo_path.c_str()) == 0);
  RemoveTempDir(dir);

  std::printf("fifo-host: %d assertions, %d failures\n", g_assertions, g_failures);
  return g_failures ? 1 : 0;
}
