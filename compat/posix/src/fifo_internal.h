// gesher-base: POSIX FIFO internals (mkfifo, S_IFIFO reparse points, and
// cross-process named-pipe rendezvous built on pipe_io / OFD).
#pragma once

#include <gesher/file_description.h>
#include <sys/types.h>
#include <windows.h>

#include <string>

namespace gesher {

inline constexpr ULONG kLxFifoReparseTag = 0x80000024UL;

// True when `h` (opened with FILE_FLAG_OPEN_REPARSE_POINT) is a POSIX FIFO.
bool IsFifoHandle(HANDLE h);

// True when `windows` resolves (without following) to a POSIX FIFO reparse point.
bool IsFifoPath(const std::wstring& windows);

// Reads the POSIX permission bits (0..0777) persisted on a FIFO handle.
// Returns false if `h` is not a FIFO reparse point.
bool ReadFifoMode(HANDLE h, mode_t* mode_out);

// Persists POSIX permission bits (0..0777) on a FIFO handle.
bool WriteFifoMode(HANDLE h, mode_t mode);

// Opens `windows`, transparently handling ERROR_CANT_ACCESS_FILE on
// IO_REPARSE_TAG_LX_FIFO reparse points (and symlinks targeting a FIFO when
// `follow` is true). Sets `*is_fifo` if non-null.
HANDLE OpenPathMaybeFifo(const std::wstring& windows, DWORD access, bool follow,
                         bool* is_fifo = nullptr, int depth = 0);

// Opens an existing POSIX FIFO at `windows` (with `O_TRUNC` already ignored by
// the caller) and returns a new CRT/OFD descriptor, or -1 with errno set.
int OpenFifo(const std::wstring& windows, int flags, bool* handled);

// Updates `buf` for `fstat` on an open FIFO file description.
bool StatFifoDescription(const DescriptorSnapshotPtr& snapshot, mode_t* mode_out,
                         unsigned long long* dev_out, unsigned long long* ino_out);

// pipe_io.cc hooks for FIFO descriptions.
int TransferFifo(const DescriptorSnapshotPtr& snapshot, void* bytes, unsigned count,
                 bool writing, HANDLE canceled, HANDLE interrupted);
int PollFifoHandle(const DescriptorSnapshotPtr& snapshot, short events, short* ready);
int FifoBytesAvailable(const DescriptorSnapshotPtr& snapshot, int* bytes);

}  // namespace gesher
