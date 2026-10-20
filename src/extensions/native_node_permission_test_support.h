/* Native-only serial test observers. No production decision is replaced. */
#ifndef PI_NATIVE_NODE_PERMISSION_TEST_SUPPORT_H
#define PI_NATIVE_NODE_PERMISSION_TEST_SUPPORT_H
#include "native_node_native_debug.h"
#ifdef __cplusplus
extern "C" {
#endif
typedef void (*PiNativePermissionTestAction)(void* user);
typedef struct PiNativeOutputObservation {
  unsigned char bytes[8192];
  size_t length;
  int overflow;
  int io_error;
} PiNativeOutputObservation;
/* Selects only the two production Permission format instantiations. The
 * borrowed result visitor runs while the real native String is alive. */
void pi_native_debug_test_format(void* memory_owner, struct JSContext* context,
    int tree_line, const char* first, size_t first_length, const char* second,
    PiNodeEnvironmentValueVisitor visitor, void* user);
/* Actual FWrite(FILE*) file path, with an explicit test-only final flush. */
int pi_native_debug_test_file_write(void* memory_owner, const char* bytes,
    size_t length, PiNativeOutputObservation* output);
/* Actual stderr descriptor is redirected to a real temporary file for the
 * synchronous action. Windows selects binary CRT mode for exact byte
 * observation. The prior descriptor/mode is restored before output inspection.
 * No terminal/WriteConsoleW claim is supplied by this file-based observer. */
int pi_native_debug_test_capture_stderr(PiNativePermissionTestAction action,
    void* user, PiNativeOutputObservation* output);
typedef struct PiPermissionUvAllocationObservation {
  size_t allocations;
  size_t frees;
  size_t peak_blocks;
  size_t live_blocks_before_observer_cleanup;
  size_t live_bytes_before_observer_cleanup;
  size_t untracked_frees;
  int overflow;
  int warm_status;
} PiPermissionUvAllocationObservation;
/* This adapter is restricted to one real synchronous Permission Apply of an
 * actual absolute directory, in a serial process with libuv's original
 * malloc/realloc/calloc/free policy and no live asynchronous libuv work.
 * A direct stat+cleanup warms platform initialization before observation.
 * The real uv_replace_allocator callbacks still call the same system
 * allocators; no allocation success or cleanup result is fabricated.
 * Snapshot precedes emergency retirement of any leaked tracked path blocks,
 * so the old directory leak remains an asserted negative without leaking the
 * test itself. No surviving handle/request or UV owner is created here. */
int pi_native_permission_test_directory_apply(
    PiNodePermission* permission, void* memory_owner,
    const PiNodePermissionEnvironment* environment,
    const char* absolute_directory, size_t length, int scope,
    PiPermissionUvAllocationObservation* observation);
#ifdef __cplusplus
}
#endif
#endif
