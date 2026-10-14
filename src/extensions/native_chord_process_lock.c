/* Kernel primitives for Chord's native Zig processLock. No guest implementation. */
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdio.h>
#include <wchar.h>
#include <errno.h>
struct pi_chord_lock { intptr_t handle; int file; char path[104]; };
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
int pi_chord_lock_acquire(struct pi_chord_lock *lock, const char *key, const char *temporary, unsigned long *system_error) {
    wchar_t address[64];
    (void)temporary;
    swprintf(address, 64, L"\\\\.\\pipe\\chord2-%hs", key);
    HANDLE handle = CreateNamedPipeW(address, PIPE_ACCESS_DUPLEX | FILE_FLAG_FIRST_PIPE_INSTANCE,
        PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT, 1, 1024, 1024, 0, NULL);
    if (handle == INVALID_HANDLE_VALUE) {
        *system_error = GetLastError();
        return *system_error == ERROR_ACCESS_DENIED || *system_error == ERROR_PIPE_BUSY ? 1 : 3;
    }
    lock->handle = (intptr_t)handle; lock->file = 0; lock->path[0] = 0;
    return 0;
}
int pi_chord_lock_release(struct pi_chord_lock *lock) { return CloseHandle((HANDLE)lock->handle) ? 0 : (int)GetLastError(); }
#else
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
static int accepting(const struct sockaddr_un *address, socklen_t length) {
    int probe = socket(AF_UNIX, SOCK_STREAM, 0);
    if (probe < 0) return 1;
    int flags = fcntl(probe, F_GETFL, 0);
    if (flags >= 0) (void)fcntl(probe, F_SETFL, flags | O_NONBLOCK);
    int result = connect(probe, (const struct sockaddr *)address, length), saved = errno;
    close(probe);
    return result == 0 || (saved != ECONNREFUSED && saved != ENOENT);
}
int pi_chord_lock_acquire(struct pi_chord_lock *lock, const char *key, const char *temporary, unsigned long *system_error) {
    struct sockaddr_un address; memset(&address, 0, sizeof(address)); address.sun_family = AF_UNIX;
    socklen_t length;
#if defined(__linux__) || defined(__ANDROID__)
    address.sun_path[0] = 0;
    snprintf(address.sun_path + 1, sizeof(address.sun_path) - 1, "chord2-%s", key);
    length = (socklen_t)(offsetof(struct sockaddr_un, sun_path) + 1 + strlen(address.sun_path + 1));
    lock->file = 0; lock->path[0] = 0; (void)temporary;
#else
    char preferred[4096];
    int count = snprintf(preferred, sizeof(preferred), "%s/chord2-%s.sock", temporary, key);
    if (count < 0) { *system_error = EINVAL; return 3; }
    if (count > 103) {
        char directory[64]; struct stat stat;
        snprintf(directory, sizeof(directory), "/tmp/chord2-%lu", (unsigned long)getuid());
        if (mkdir(directory, 0700) != 0 && errno != EEXIST) { *system_error = errno; return 3; }
        if (lstat(directory, &stat) != 0) { *system_error = errno; return 3; }
        if (!S_ISDIR(stat.st_mode) || stat.st_uid != getuid() || (stat.st_mode & 0077) != 0) { memcpy(lock->path, directory, strlen(directory) + 1); *system_error = 0; return 2; }
        snprintf(preferred, sizeof(preferred), "%s/chord2-%s.sock", directory, key);
    }
    memcpy(address.sun_path, preferred, strlen(preferred) + 1);
    length = (socklen_t)(offsetof(struct sockaddr_un, sun_path) + strlen(address.sun_path) + 1);
    lock->file = 1; memcpy(lock->path, address.sun_path, strlen(address.sun_path) + 1);
#endif
    int descriptor = socket(AF_UNIX, SOCK_STREAM, 0);
    if (descriptor < 0) { *system_error = errno; return 3; }
    (void)fcntl(descriptor, F_SETFD, FD_CLOEXEC);
    for (;;) {
        if (bind(descriptor, (const struct sockaddr *)&address, length) == 0) break;
        int saved = errno;
        if (saved != EADDRINUSE) { close(descriptor); *system_error = saved; return 3; }
        if (!lock->file || accepting(&address, length)) { close(descriptor); *system_error = saved; return 1; }
        if (unlink(address.sun_path) != 0 && errno != ENOENT) { saved = errno; close(descriptor); *system_error = saved; return 3; }
    }
    if (listen(descriptor, 511) != 0) { int saved = errno; close(descriptor); if (lock->file) unlink(lock->path); *system_error = saved; return 3; }
    lock->handle = descriptor;
    return 0;
}
int pi_chord_lock_release(struct pi_chord_lock *lock) {
    int result = close((int)lock->handle), saved = errno;
    if (lock->file) (void)unlink(lock->path);
    return result == 0 ? 0 : saved;
}
#endif
