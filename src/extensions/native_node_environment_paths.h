/* Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
 * Native Environment argv/exec-path storage and selected physical path methods.
 * The embedding supplies a MapKVStore explicitly; no process-global store or
 * guest process property is substituted. All callback spans are synchronous. */
#ifndef PI_NATIVE_NODE_ENVIRONMENT_PATHS_H
#define PI_NATIVE_NODE_ENVIRONMENT_PATHS_H
#include "native_node_environment_map.h"
#include <stddef.h>
#ifdef __cplusplus
#define PI_PATH_NOEXCEPT noexcept
extern "C" {
#else
#define PI_PATH_NOEXCEPT
#endif
typedef struct PiNodeEnvironmentPaths PiNodeEnvironmentPaths;
typedef struct PiNodeEnvironmentPathSpan {
  const char* data;
  size_t length;
} PiNodeEnvironmentPathSpan;
typedef void (*PiNodeEnvironmentNativeTrace)(void* user);
typedef void (*PiNodeEnvironmentJsTrace)(void* user, struct JSContext* context);
typedef struct PiNodeEnvironmentTrace {
  int print_message;
  int print_native_stack;
  int print_js_stack;
  /* Borrowed actual native diagnostic operations. A selected stack flag
   * requires its nonnull genuine operation; no default noop is supplied. */
  PiNodeEnvironmentNativeTrace native_stack;
  PiNodeEnvironmentJsTrace js_stack;
  void* user;
} PiNodeEnvironmentTrace;

/* The later single native Environment allocation supplies this stable tail.
 * The adapter materializes its incoming native argument vector before calling
 * the original argv-copy then GetExecPath constructor sequence. That explicit
 * embedding-input materialization is separate from Node startup admission.
 * Each supplied argument data pointer is nonnull, including an empty string. */
size_t pi_node_environment_paths_storage_size(void) PI_PATH_NOEXCEPT;
size_t pi_node_environment_paths_storage_alignment(void) PI_PATH_NOEXCEPT;
PiNodeEnvironmentPaths* pi_node_environment_paths_construct(void* storage,
    void* memory_owner, const PiNodeEnvironmentPathSpan* args, size_t count)
    PI_PATH_NOEXCEPT;
void pi_node_environment_paths_destroy(PiNodeEnvironmentPaths* paths)
    PI_PATH_NOEXCEPT;
void pi_node_environment_paths_exec_path(const PiNodeEnvironmentPaths* paths,
    PiNodeEnvironmentValueVisitor visitor, void* user) PI_PATH_NOEXCEPT;

/* memory_owner is the caller's actual native allocation domain. paths, map,
 * trace, context and every input span remain borrowed through return. Outputs
 * are actual native Strings owned through visitor return, not JS values.
 * A visitor may produce its actual intrinsic JS value but must not throw C++. */
void pi_node_environment_paths_cwd(const PiNodeEnvironmentPaths* paths,
    void* memory_owner, struct JSContext* context,
    PiNodeEnvironmentValueVisitor visitor, void* user) PI_PATH_NOEXCEPT;
void pi_node_environment_path_resolve(const PiNodeEnvironmentPaths* paths,
    void* memory_owner, struct JSContext* context, PiNodeEnvironmentMap* map,
    const PiNodeEnvironmentTrace* trace,
    const PiNodeEnvironmentPathSpan* parts, size_t count,
    PiNodeEnvironmentValueVisitor visitor, void* user) PI_PATH_NOEXCEPT;
/* Native path.cc ToNamespacedPath over this actual Environment's PathResolve,
 * MapKVStore and diagnostics. The full input span includes embedded NUL.
 * The output is borrowed through exactly one synchronous visitor call. */
void pi_node_environment_path_to_namespaced(
    const PiNodeEnvironmentPaths* paths, void* memory_owner,
    struct JSContext* context, PiNodeEnvironmentMap* map,
    const PiNodeEnvironmentTrace* trace,
    const PiNodeEnvironmentPathSpan* input,
    PiNodeEnvironmentValueVisitor visitor, void* user) PI_PATH_NOEXCEPT;
int pi_node_environment_safe_getenv(void* memory_owner,
    struct JSContext* context, PiNodeEnvironmentMap* map,
    const PiNodeEnvironmentTrace* trace, const char* key,
    PiNodeEnvironmentValueVisitor visitor, void* user) PI_PATH_NOEXCEPT;
#ifdef __cplusplus
}
#endif
#undef PI_PATH_NOEXCEPT
#endif
