// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
// Selected original node_credentials.cc SafeGetenv admission. This read-only
// helper never changes credentials, capabilities, environment, or privileges.
#include "native_node_options_environment.h"

#if !defined(__CloudABI__) && !defined(_WIN32)
#include <unistd.h>
#endif
#if defined(__linux__)
#include <linux/capability.h>
#include <stdatomic.h>
#include <sys/auxv.h>
#include <sys/syscall.h>

static int pi_node_linux_at_secure(void) {
    /* Node's function-local const captures AT_SECURE once. The auxiliary vector
     * is immutable; release/acquire publication retains that same lifetime. */
    static _Atomic int cached = -1;
    int value = atomic_load_explicit(&cached, memory_order_acquire);
    if (value == -1) {
        int expected = -1;
        value = getauxval(AT_SECURE) != 0;
        if (!atomic_compare_exchange_strong_explicit(&cached, &expected, value,
                memory_order_acq_rel, memory_order_acquire))
            value = expected;
    }
    return value;
}
static int pi_node_has_only_bind_service(void) {
    struct __user_cap_data_struct data[_LINUX_CAPABILITY_U32S_3];
    struct __user_cap_header_struct header = {
        _LINUX_CAPABILITY_VERSION_3, getpid()
    };
    if (syscall(SYS_capget, &header, &data) != 0) return 0;
    _Static_assert(_LINUX_CAPABILITY_U32S_3 == 2, "actual Linux capability ABI");
    return data[CAP_TO_INDEX(CAP_NET_BIND_SERVICE)].permitted ==
               (unsigned int)CAP_TO_MASK(CAP_NET_BIND_SERVICE) &&
           data[1 - CAP_TO_INDEX(CAP_NET_BIND_SERVICE)].permitted == 0;
}
#endif

int pi_node_options_environment_allowed(void) {
#if !defined(__CloudABI__) && !defined(_WIN32)
#if defined(__linux__)
    if ((!pi_node_has_only_bind_service() && pi_node_linux_at_secure()) ||
        getuid() != geteuid() || getgid() != getegid())
#else
    if (getuid() != geteuid() || getgid() != getegid())
#endif
        return 0;
#endif
    return 1;
}
