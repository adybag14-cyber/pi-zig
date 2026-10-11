/* Narrow POSIX ABI for the Zig terminal owner. All allocation, protocol,
 * queuing and lifecycle decisions belong to Zig. */
#ifndef _WIN32
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <util.h>
#include <libproc.h>
#else
#include <pty.h>
#endif

static int cloexec(int fd) {
    int flags = fcntl(fd, F_GETFD);
    return flags < 0 ? -1 : fcntl(fd, F_SETFD, flags | FD_CLOEXEC);
}

int pi_env_pty_resize(int master, uint16_t cols, uint16_t rows) {
    struct winsize size = { .ws_row = rows, .ws_col = cols };
    return ioctl(master, TIOCSWINSZ, &size) < 0 ? -errno : 0;
}

/* argv, env and the resolved executable are prepared before fork. Only
 * async-signal-safe operations run in the child before execve. */
int pi_env_pty_spawn(const char *program, char *const argv[],
                     char *const env[], const char *cwd,
                     uint16_t cols, uint16_t rows, int *master_out, int *pid_out) {
    int master = -1, slave = -1, status_pipe[2] = {-1, -1};
    struct winsize size = { .ws_row = rows, .ws_col = cols };
    if (openpty(&master, &slave, NULL, NULL, &size) < 0) return -errno;
    if (cloexec(master) < 0 || cloexec(slave) < 0 || pipe(status_pipe) < 0 ||
        cloexec(status_pipe[0]) < 0 || cloexec(status_pipe[1]) < 0) {
        int saved = errno;
        close(master); close(slave);
        if (status_pipe[0] >= 0) close(status_pipe[0]);
        if (status_pipe[1] >= 0) close(status_pipe[1]);
        return -saved;
    }
    pid_t pid = fork();
    if (pid < 0) {
        int saved = errno;
        close(master); close(slave); close(status_pipe[0]); close(status_pipe[1]);
        return -saved;
    }
    if (pid == 0) {
        close(status_pipe[0]); close(master);
        if (setsid() < 0 || dup2(slave, 0) < 0 || dup2(slave, 1) < 0 ||
            dup2(slave, 2) < 0 || ioctl(0, TIOCSCTTY, 0) < 0) goto child_error;
        close(slave);
        for (int sig = 1; sig < 32; ++sig) {
            if (sig == SIGKILL || sig == SIGSTOP) continue;
            struct sigaction action;
            memset(&action, 0, sizeof(action));
            action.sa_handler = SIG_DFL;
            sigemptyset(&action.sa_mask);
            sigaction(sig, &action, NULL);
        }
        sigset_t mask;
        sigemptyset(&mask);
        if (sigprocmask(SIG_SETMASK, &mask, NULL) < 0 || chdir(cwd) < 0) goto child_error;
        execve(program, argv, env);
child_error: {
            int saved = errno;
            const char *bytes = (const char *)&saved;
            size_t offset = 0;
            while (offset < sizeof(saved)) {
                ssize_t count = write(status_pipe[1], bytes + offset, sizeof(saved) - offset);
                if (count < 0 && errno == EINTR) continue;
                if (count <= 0) break;
                offset += (size_t)count;
            }
            _exit(127);
        }
    }
    close(slave); close(status_pipe[1]);
    int child_error = 0;
    size_t offset = 0;
    while (offset < sizeof(child_error)) {
        ssize_t count = read(status_pipe[0], (char *)&child_error + offset, sizeof(child_error) - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count < 0) { child_error = errno; offset = sizeof(child_error); break; }
        if (count == 0) break;
        offset += (size_t)count;
    }
    close(status_pipe[0]);
    int flags = fcntl(master, F_GETFL);
    if (offset || flags < 0 || fcntl(master, F_SETFL, flags | O_NONBLOCK) < 0) {
        int saved = offset ? (offset == sizeof(child_error) ? child_error : EIO) : errno;
        kill(-pid, SIGKILL); kill(pid, SIGKILL);
        while (waitpid(pid, NULL, 0) < 0 && errno == EINTR) {}
        close(master);
        return -saved;
    }
    *master_out = master;
    *pid_out = pid;
    return 0;
}

/* Nonblocking operations distinguish temporary unavailability from EOF.
 * The owner retains the unreaped PID throughout polling and cancellation. */
intptr_t pi_env_pty_read(int master, void *bytes, size_t length) {
    ssize_t count = read(master, bytes, length);
    if (count >= 0) return count;
    if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) return -1;
    if (errno == EIO) return 0; /* Linux reports EIO when the slave closes. */
    return -(intptr_t)errno - 1;
}
intptr_t pi_env_pty_write(int master, const void *bytes, size_t length) {
    ssize_t count = write(master, bytes, length);
    if (count >= 0) return count;
    if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) return -1;
    return -(intptr_t)errno - 1;
}
int pi_env_pty_wait(int master, int writing, int timeout_ms) {
    struct pollfd descriptor = { .fd = master, .events = writing ? POLLOUT : POLLIN };
    int ready = poll(&descriptor, 1, timeout_ms);
    if (ready < 0) return errno == EINTR ? 0 : -errno;
    if (descriptor.revents & POLLNVAL) return -EBADF;
    return ready > 0;
}
int pi_env_pty_peek(int pid, int64_t *exit_code) {
    siginfo_t info;
    memset(&info, 0, sizeof(info));
    if (waitid(P_PID, (id_t)pid, &info, WEXITED | WNOHANG | WNOWAIT) < 0) return -errno;
    if (info.si_pid == 0) return 0;
    *exit_code = info.si_code == CLD_EXITED ? info.si_status : 128 + info.si_status;
    return 1;
}
int pi_env_pty_foreground(int master) {
    pid_t group = tcgetpgrp(master);
    return group < 0 ? -errno : group;
}
int pi_env_pty_process_name(int pid, char *bytes, size_t capacity) {
#if defined(__APPLE__)
    return proc_name(pid, bytes, (uint32_t)capacity);
#else
    (void)pid; (void)bytes; (void)capacity;
    return 0; /* Zig reads /proc/<pid>/comm on Linux and Android. */
#endif
}
int pi_env_pty_kill(int pid) {
    if (kill(-pid, SIGKILL) == 0 || kill(pid, SIGKILL) == 0) return 0;
    return -errno;
}
int pi_env_pty_reap(int pid) {
    while (waitpid(pid, NULL, 0) < 0) if (errno != EINTR) return -errno;
    return 0;
}
void pi_env_pty_close(int master) { close(master); }
int pi_env_pty_error(int code, char *bytes, size_t capacity) {
    return snprintf(bytes, capacity, "%s (os error %d)", strerror(code), code);
}
const char *pi_env_pty_error_code(int code) {
#define PI_ERRNO_NAME(name) case name: return #name;
    switch (code) {
        PI_ERRNO_NAME(EPERM) PI_ERRNO_NAME(ENOENT) PI_ERRNO_NAME(EIO)
        PI_ERRNO_NAME(EBADF) PI_ERRNO_NAME(EAGAIN) PI_ERRNO_NAME(ENOMEM)
        PI_ERRNO_NAME(EACCES) PI_ERRNO_NAME(EBUSY) PI_ERRNO_NAME(EEXIST)
        PI_ERRNO_NAME(EXDEV) PI_ERRNO_NAME(ENOTDIR) PI_ERRNO_NAME(EISDIR)
        PI_ERRNO_NAME(EINVAL) PI_ERRNO_NAME(ENFILE) PI_ERRNO_NAME(EMFILE)
        PI_ERRNO_NAME(ETXTBSY) PI_ERRNO_NAME(EFBIG) PI_ERRNO_NAME(ENOSPC)
        PI_ERRNO_NAME(EROFS) PI_ERRNO_NAME(EMLINK) PI_ERRNO_NAME(ENAMETOOLONG)
        PI_ERRNO_NAME(ENOTEMPTY) PI_ERRNO_NAME(ELOOP) PI_ERRNO_NAME(ENOSYS)
        PI_ERRNO_NAME(ENOTSUP)
        default: return "UNKNOWN";
    }
#undef PI_ERRNO_NAME
}
#else
typedef int pi_env_pty_windows_has_no_posix_abi;
#endif
