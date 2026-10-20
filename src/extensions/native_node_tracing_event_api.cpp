// Copyright 2015 the V8 project authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the retained V8-LICENSE.txt.
// Source-only candidate. Exact original bodies and two admission scopes are
// recorded in the companion body proof; no process bootstrap is installed.
#include "native_node_tracing_event_api.h"
#include "native_node_tracing_agent.hpp"
#include "native_node_diagnostic_context.hpp"
#include <memory>

namespace {
using pi::node::DiagnosticContextScope;
using pi_node::AllocationScope;
using pi_node::tracing::Agent;
using pi_node::tracing::ConvertableToTraceFormat;
using pi_node::tracing::TraceEventHelper;
using pi_node::tracing::TracingController;
using pi_node::tracing::TRACE_VALUE_TYPE_CONVERTABLE;
}  // namespace

extern "C" const uint8_t* pi_node_tracing_event_category_enabled(
    JSContext* context, void* memory_owner, const char* group) noexcept {
  DiagnosticContextScope diagnostic(context);
  AllocationScope allocation(memory_owner);
  TracingController* controller = TraceEventHelper::GetTracingController();
  static const uint8_t disabled = 0;
  if (controller == nullptr) [[unlikely]] {
    return &disabled;
  }
  return controller->GetCategoryGroupEnabled(group);
}

extern "C" uint64_t pi_node_tracing_event_add(
    JSContext* context, void* memory_owner,
    char phase, const uint8_t* category_group_enabled, const char* name,
    const char* scope, uint64_t id, uint64_t bind_id, int32_t num_args,
    const char** arg_names, const uint8_t* arg_types,
    const uint64_t* arg_values, unsigned int flags) noexcept {
  DiagnosticContextScope diagnostic(context);
  AllocationScope allocation(memory_owner);
  std::unique_ptr<ConvertableToTraceFormat> arg_convertibles[2];
  if (num_args > 0 && arg_types[0] == TRACE_VALUE_TYPE_CONVERTABLE) {
    arg_convertibles[0].reset(reinterpret_cast<ConvertableToTraceFormat*>(
        static_cast<intptr_t>(arg_values[0])));
  }
  if (num_args > 1 && arg_types[1] == TRACE_VALUE_TYPE_CONVERTABLE) {
    arg_convertibles[1].reset(reinterpret_cast<ConvertableToTraceFormat*>(
        static_cast<intptr_t>(arg_values[1])));
  }
  // DCHECK(num_args, 2);
  TracingController* controller =
      TraceEventHelper::GetTracingController();
  if (controller == nullptr) return 0;
  return controller->AddTraceEvent(phase, category_group_enabled, name, scope, id,
                                   bind_id, num_args, arg_names, arg_types,
                                   arg_values, arg_convertibles, flags);
}

extern "C" uint64_t pi_node_tracing_event_add_with_timestamp(
    JSContext* context, void* memory_owner,
    char phase, const uint8_t* category_group_enabled, const char* name,
    const char* scope, uint64_t id, uint64_t bind_id, int32_t num_args,
    const char** arg_names, const uint8_t* arg_types,
    const uint64_t* arg_values, unsigned int flags, int64_t timestamp) noexcept {
  DiagnosticContextScope diagnostic(context);
  AllocationScope allocation(memory_owner);
  std::unique_ptr<ConvertableToTraceFormat> arg_convertibles[2];
  if (num_args > 0 && arg_types[0] == TRACE_VALUE_TYPE_CONVERTABLE) {
    arg_convertibles[0].reset(reinterpret_cast<ConvertableToTraceFormat*>(
        static_cast<intptr_t>(arg_values[0])));
  }
  if (num_args > 1 && arg_types[1] == TRACE_VALUE_TYPE_CONVERTABLE) {
    arg_convertibles[1].reset(reinterpret_cast<ConvertableToTraceFormat*>(
        static_cast<intptr_t>(arg_values[1])));
  }
  // DCHECK_LE(num_args, 2);
  TracingController* controller =
      TraceEventHelper::GetTracingController();
  if (controller == nullptr) return 0;
  return controller->AddTraceEventWithTimestamp(
      phase, category_group_enabled, name, scope, id, bind_id, num_args,
      arg_names, arg_types, arg_values, arg_convertibles, flags, timestamp);
}

extern "C" void pi_node_tracing_event_add_metadata(
    JSContext* context, void* memory_owner,
    const uint8_t* category_group_enabled, const char* name, int32_t num_args,
    const char** arg_names, const uint8_t* arg_types,
    const uint64_t* arg_values, unsigned int flags) noexcept {
  DiagnosticContextScope diagnostic(context);
  AllocationScope allocation(memory_owner);
  std::unique_ptr<ConvertableToTraceFormat> arg_convertibles[2];
  if (num_args > 0 && arg_types[0] == TRACE_VALUE_TYPE_CONVERTABLE) {
    arg_convertibles[0].reset(reinterpret_cast<ConvertableToTraceFormat*>(
        static_cast<intptr_t>(arg_values[0])));
  }
  if (num_args > 1 && arg_types[1] == TRACE_VALUE_TYPE_CONVERTABLE) {
    arg_convertibles[1].reset(reinterpret_cast<ConvertableToTraceFormat*>(
        static_cast<intptr_t>(arg_values[1])));
  }
  Agent* agent =
      TraceEventHelper::GetAgent();
  if (agent == nullptr) return;
  return agent->GetTracingController()->AddMetadataEvent(
      category_group_enabled, name, num_args, arg_names, arg_types, arg_values,
      arg_convertibles, flags);
}

extern "C" void pi_node_tracing_event_update_duration(
    JSContext* context, void* memory_owner,
    const uint8_t* category_group_enabled, const char* name,
    uint64_t handle) noexcept {
  DiagnosticContextScope diagnostic(context);
  AllocationScope allocation(memory_owner);
  if (auto controller = TraceEventHelper::GetTracingController())
    controller->UpdateTraceEventDuration(category_group_enabled, name, handle);
}
