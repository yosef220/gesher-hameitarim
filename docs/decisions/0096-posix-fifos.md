# 0096: Cross-process POSIX FIFOs (`mkfifo`, `S_IFIFO`)

Status: accepted, 2026-11-24.

## Context

Android native libraries such as Realm (`InterprocessCondVar`) create named FIFOs
via `mkfifo(path, mode)` and open them across processes using `O_RDONLY`,
`O_WRONLY`, `O_RDWR`, `O_NONBLOCK`, `poll`/`epoll`, and descriptor inheritance.
Win32 has no kernel FIFO filesystem node: `mkfifo` previously returned `ENOSYS`
(host POSIX) / `EPERM` (Bionic).

## Decision

1. **On-disk representation (`IO_REPARSE_TAG_LX_FIFO`):**
   - `mkfifo` / `mkfifoat` create an NTFS file with reparse tag
     `IO_REPARSE_TAG_LX_FIFO` (`0x80000024`), zero-byte reparse data (supported
     on NTFS without elevation), and `FILE_ATTRIBUTE_READONLY` when `(mode & ~umask & 0200) == 0`.
   - Effective POSIX permission bits (`0..0777`) are persisted in the
     `GESHER.FIFOMODE` NTFS extended attribute so `stat`, `lstat`, `fstat`, and
     `chmod` report consistent modes, and `readdir` reports `DT_FIFO`.
   - Regular files suffer zero extra opens on `stat` or `open`.
   - Paths opened without `FILE_FLAG_OPEN_REPARSE_POINT` fail on `IO_REPARSE_TAG_LX_FIFO`
     with `ERROR_CANT_ACCESS_FILE`; `OpenPathMaybeFifo` retries with
     `FILE_FLAG_OPEN_REPARSE_POINT` (and resolves symlinks when `follow` is true),
     while `OpenFile` classifies FIFOs before applying `O_TRUNC`/`CREATE_ALWAYS`.

2. **Cross-process transport (`pipe_io` + `ofd`):**
   - Each FIFO filesystem object `(volume_serial, file_index_high, file_index_low)`
     maps to session-local rendezvous state (`Local\gesher-fifo-*` mutex and
     shared memory, per-waiter events) coordinating `reader_opens`, `writer_opens`,
     and active holder handles across processes.
   - Data transfer runs over `FILE_FLAG_OVERLAPPED` Windows message-type named
     pipes (`PIPE_TYPE_MESSAGE | PIPE_READMODE_BYTE`, 64 KiB buffer) integrated
     with `OpenFileDescription` and `pipe_io`, preserving `PIPE_BUF` (4096-byte)
     atomic writes, per-OFD `O_NONBLOCK` flags, per-open `POLLHUP` epoch checks,
     sequential writer reconnects without losing unread bytes, `O_RDWR` loopback
     over paired server/client handles, `EINTR`/`pthread_cancel`, and
     `posix_spawn`/`SpawnWithFds` descriptor inheritance.
