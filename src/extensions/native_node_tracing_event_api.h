// Copyright 2015 the V8 project authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the retained V8-LICENSE.txt.
// Proposed additive event boundary; this file is not installed or compiled.
#ifndef PI_NATIVE_NODE_TRACING_EVENT_API_H
#define PI_NATIVE_NODE_TRACING_EVENT_API_H
#include "native_node_tracing_api.h"
#ifdef __cplusplus
#define PI_TRACING_EVENT_NOEXCEPT noexcept
extern "C" {
#else
#define PI_TRACING_EVENT_NOEXCEPT
#endif

/* Direct original TraceEventHelper / AddTraceEventImpl admissions.
 *
 * context is nullable and borrowed only during the immediate call. Every entry
 * declares DiagnosticContextScope first and AllocationScope second; neither
 * context nor either scope is retained by an event, observer, or worker.
 *
 * memory_owner is the live native allocation owner of the selected controller
 * and its Agent. It is nonnull and remains valid through this call. Publication,
 * category pointers and all producers obey the original process lifetime.
 *
 * These raw insertion entries do not replace the original call-site category
 * gate/cache or evaluate guest values. Selected native callers supply 0..2
 * arguments using original trace tags and 64-bit payload representation.
 * For each of the first two CONVERTABLE arguments, the payload is an actual
 * native ConvertableToTraceFormat*; ownership transfers exactly once on entry,
 * before looking up the global controller/Agent. A missing global owner still
 * destroys those values synchronously. No guest callback or JSON proxy is an
 * admitted convertible.
 *
 * Input arrays are borrowed until return. Name, scope, argument names and
 * ordinary STRING payloads retain the original long-lived-pointer contract.
 * FLAG_COPY and COPY_STRING retain their distinct native copy semantics.
 * Convertible formatting may occur later on the native writer; its concrete
 * implementation must own only its required native data.
 *
 * The disabled pointer returned without a global controller is a separate
 * static zero byte. It is not an index in the process category-name registry.
 */
const uint8_t* pi_node_tracing_event_category_enabled(
    struct JSContext* context, void* memory_owner, const char* group)
    PI_TRACING_EVENT_NOEXCEPT;

uint64_t pi_node_tracing_event_add(
    struct JSContext* context, void* memory_owner,
    char phase, const uint8_t* category_group_enabled, const char* name,
    const char* scope, uint64_t id, uint64_t bind_id, int32_t num_args,
    const char** arg_names, const uint8_t* arg_types,
    const uint64_t* arg_values, unsigned int flags)
    PI_TRACING_EVENT_NOEXCEPT;

uint64_t pi_node_tracing_event_add_with_timestamp(
    struct JSContext* context, void* memory_owner,
    char phase, const uint8_t* category_group_enabled, const char* name,
    const char* scope, uint64_t id, uint64_t bind_id, int32_t num_args,
    const char** arg_names, const uint8_t* arg_types,
    const uint64_t* arg_values, unsigned int flags, int64_t timestamp)
    PI_TRACING_EVENT_NOEXCEPT;

void pi_node_tracing_event_add_metadata(
    struct JSContext* context, void* memory_owner,
    const uint8_t* category_group_enabled, const char* name, int32_t num_args,
    const char** arg_names, const uint8_t* arg_types,
    const uint64_t* arg_values, unsigned int flags)
    PI_TRACING_EVENT_NOEXCEPT;

/* The caller preserves the original ScopedTracer lifetime/category guard.
 * This entry preserves only the original nullable-global-controller dispatch. */
void pi_node_tracing_event_update_duration(
    struct JSContext* context, void* memory_owner,
    const uint8_t* category_group_enabled, const char* name, uint64_t handle)
    PI_TRACING_EVENT_NOEXCEPT;

#ifdef __cplusplus
}
#endif
#undef PI_TRACING_EVENT_NOEXCEPT
#endif
