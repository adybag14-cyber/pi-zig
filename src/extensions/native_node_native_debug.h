/* Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
 * Actual native EnabledDebugList and selected PERMISSION_MODEL formatting.
 * Feature selection is explicit and fixed before process publication. */
#ifndef PI_NATIVE_NODE_DEBUG_H
#define PI_NATIVE_NODE_DEBUG_H
#include "native_node_permission.h"
#include <stddef.h>
#ifdef __cplusplus
#define PI_DEBUG_NOEXCEPT noexcept
extern "C" {
#else
#define PI_DEBUG_NOEXCEPT
#endif
typedef struct PiNodeNativeDebugList PiNodeNativeDebugList;
/* Local Environment/fixture lists use stable caller-owned aligned storage.
 * The selected HAVE_OPENSSL feature chooses the complete original category
 * table. Construction sets every original enabled field false; Parse only
 * enables fields. Static native category strings retain their original
 * allocation domains until native process destruction. */
size_t pi_node_native_debug_storage_size(void) PI_DEBUG_NOEXCEPT;
size_t pi_node_native_debug_storage_alignment(void) PI_DEBUG_NOEXCEPT;
PiNodeNativeDebugList* pi_node_native_debug_construct(void* storage,
    int have_openssl) PI_DEBUG_NOEXCEPT;
void pi_node_native_debug_destroy(PiNodeNativeDebugList* list) PI_DEBUG_NOEXCEPT;
size_t pi_node_native_debug_category_count(const PiNodeNativeDebugList* list)
    PI_DEBUG_NOEXCEPT;
const char* pi_node_native_debug_category_name(
    const PiNodeNativeDebugList* list, size_t category) PI_DEBUG_NOEXCEPT;
int pi_node_native_debug_enabled(const PiNodeNativeDebugList* list,
    size_t category) PI_DEBUG_NOEXCEPT;
int pi_node_native_debug_permission_enabled(const PiNodeNativeDebugList* list)
    PI_DEBUG_NOEXCEPT;
/* Explicit embedding materialization precedes Parse(cats); this prefix is
 * separate from the original Parse(Environment*) native input ownership. */
void pi_node_native_debug_parse_text(PiNodeNativeDebugList* list,
    void* memory_owner, const char* cats, size_t length) PI_DEBUG_NOEXCEPT;
/* Genuine Parse(Environment*) for the selected supplied-Map environment:
 * actual native SafeGetenv("NODE_DEBUG_NATIVE") then Parse(cats).
 * Environment/map/trace/context are borrowed; no RealEnvStore fallback. */
void pi_node_native_debug_parse_environment(PiNodeNativeDebugList* list,
    void* memory_owner, const PiNodePermissionEnvironment* environment)
    PI_DEBUG_NOEXCEPT;
/* One actual process-wide list. The embedding selects its fixed compile
 * feature before publishing any Environment. First selection performs only
 * placement construction; a later different feature is a native invariant
 * failure. Selection does not parse or invent a process environment.
 * This process list must never be passed to the local destroy operation.
 * Startup selection and Parse obey original single-owner initialization. */
PiNodeNativeDebugList* pi_node_process_debug_select(int have_openssl,
    struct JSContext* context) PI_DEBUG_NOEXCEPT;
/* Required borrowed call view: all fields remain alive until the bound
 * Permission call returns. No Engine, context, Map or JS value is retained. */
typedef struct PiNodeNativeDebugCall {
  PiNodeNativeDebugList* list;
  void* memory_owner;
  struct JSContext* context;
} PiNodeNativeDebugCall;
void pi_node_native_debug_bind_permission(PiNodeNativeDebugCall* call,
    PiNodePermissionDebug* operations, PiNodeNativeDebugList* list,
    void* memory_owner, struct JSContext* context) PI_DEBUG_NOEXCEPT;
#ifdef __cplusplus
}
#endif
#undef PI_DEBUG_NOEXCEPT
#endif
