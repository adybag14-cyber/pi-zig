/* Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
 * Native Permission policy. No process.env, permission.has or denied Error
 * registration is supplied by this physical/native owner. */
#ifndef PI_NATIVE_NODE_PERMISSION_H
#define PI_NATIVE_NODE_PERMISSION_H
#include "native_node_environment_paths.h"
#include <stddef.h>
#ifdef __cplusplus
#define PI_PERMISSION_NOEXCEPT noexcept
extern "C" {
#else
#define PI_PERMISSION_NOEXCEPT
#endif
typedef struct PiNodePermission PiNodePermission;
enum PiNodePermissionScope {
  PI_NODE_PERMISSION_ROOT = -1,
  PI_NODE_PERMISSION_FS = 0,
  PI_NODE_PERMISSION_FS_READ = 1,
  PI_NODE_PERMISSION_FS_WRITE = 2,
  PI_NODE_PERMISSION_CHILD_PROCESS = 3,
  PI_NODE_PERMISSION_WASI = 4,
  PI_NODE_PERMISSION_WORKER = 5,
  PI_NODE_PERMISSION_INSPECTOR = 6,
  PI_NODE_PERMISSION_ADDON = 7
};
/* Required actual per_process EnabledDebugList and SPrintF/FWrite operations.
 * The native Permission body performs every original live enabled read.
 * format_insert receives the original sized string and must use its original
 * string-copy formatting path. format_tree_line receives original c_str views.
 * Callbacks are synchronous, native, borrowed and must not throw C++.
 * No absent/disabled/noop default is supplied. */
typedef struct PiNodePermissionDebug {
  int (*enabled)(void* user);
  void (*format_insert)(void* user, const char* data, size_t length);
  void (*format_tree_line)(void* user, const char* indent, const char* prefix);
  void* user;
} PiNodePermissionDebug;
typedef struct PiNodePermissionEnvironment {
  const PiNodeEnvironmentPaths* paths;
  PiNodeEnvironmentMap* map;
  struct JSContext* context;
  const PiNodeEnvironmentTrace* trace;
  const PiNodePermissionDebug* process_debug;
} PiNodePermissionEnvironment;
/* The single later native Environment allocation provides stable aligned
 * storage. Its actual six shared policy allocations and eight map insertions
 * use the supplied domain; every block independently retains its owner. */
size_t pi_node_permission_storage_size(void) PI_PERMISSION_NOEXCEPT;
size_t pi_node_permission_storage_alignment(void) PI_PERMISSION_NOEXCEPT;
PiNodePermission* pi_node_permission_construct(void* storage,
    void* memory_owner) PI_PERMISSION_NOEXCEPT;
void pi_node_permission_destroy(PiNodePermission* permission)
    PI_PERMISSION_NOEXCEPT;
int pi_node_permission_enabled(const PiNodePermission* permission)
    PI_PERMISSION_NOEXCEPT;
void pi_node_permission_enable(PiNodePermission* permission)
    PI_PERMISSION_NOEXCEPT;
/* Explicit embedding materialization precedes the original Apply body.
 * All input spans are borrowed and nonnull, including empty strings. This is
 * separate from Node CLI/startup input ownership and does not parse options. */
void pi_node_permission_apply(PiNodePermission* permission, void* memory_owner,
    const PiNodePermissionEnvironment* environment,
    const PiNodeEnvironmentPathSpan* allow, size_t count, int scope)
    PI_PERMISSION_NOEXCEPT;
int pi_node_permission_is_granted(const PiNodePermission* permission,
    void* memory_owner, const PiNodePermissionEnvironment* environment,
    int scope, const char* resource, size_t resource_length)
    PI_PERMISSION_NOEXCEPT;
#ifdef __cplusplus
}
#endif
#undef PI_PERMISSION_NOEXCEPT
#endif
