/* A non-reaping POSIX exit probe keeps the owned child's PID reserved until
 * its Zig owner finishes draining pipes and performs wait(). */
#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <stdint.h>
#include <string.h>
#include <sys/wait.h>
#include <sys/stat.h>

int pi_durable_peek_child(int pid, int64_t *exit_code) {
    siginfo_t info;
    memset(&info, 0, sizeof(info));
    if (waitid(P_PID, (id_t)pid, &info, WEXITED | WNOHANG | WNOWAIT) < 0)
        return -errno;
    if (info.si_pid == 0)
        return 0;
    *exit_code = info.si_code == CLD_EXITED ? info.si_status : 128 + info.si_status;
    return 1;
}

int pi_durable_make_test_fifo(const char *path) {
    return mkfifo(path, 0600) == 0 ? 0 : -errno;
}
#endif
