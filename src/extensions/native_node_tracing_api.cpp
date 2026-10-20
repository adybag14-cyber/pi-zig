// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
// Native value admission for the pinned Agent/StartTracingAgent operations.
// This translation unit requires the separately reviewed diagnostic TLS owner.
#include "native_node_tracing_api.h"
#include "native_node_tracing_agent.hpp"
#include "native_node_tracing_writer.hpp"
#include "native_node_diagnostic_context.hpp"
#include <new>
#include <ranges>
#include <string_view>
#include <utility>

namespace {
using pi::node::DiagnosticContextScope;
using pi_node::AllocationScope;
using pi_node::tracing::Agent;
using pi_node::tracing::AgentWriterHandle;
using pi_node::tracing::AsyncTraceWriter;
using pi_node::tracing::CategorySet;
using pi_node::tracing::NodeTraceWriter;
using pi_node::tracing::String;
using pi_node::tracing::TraceEventHelper;
using pi_node::tracing::TracingController;

Agent* Native(PiNodeTracingAgent* value) noexcept {
  return reinterpret_cast<Agent*>(value);
}
AgentWriterHandle* Native(PiNodeTracingWriterHandle* value) noexcept {
  return reinterpret_cast<AgentWriterHandle*>(value);
}
const AgentWriterHandle* Native(const PiNodeTracingWriterHandle* value) noexcept {
  return reinterpret_cast<const AgentWriterHandle*>(value);
}
CategorySet* Native(PiNodeTracingCategorySet* value) noexcept {
  return reinterpret_cast<CategorySet*>(value);
}
const CategorySet* Native(const PiNodeTracingCategorySet* value) noexcept {
  return reinterpret_cast<const CategorySet*>(value);
}
String* Native(PiNodeTracingString* value) noexcept {
  return reinterpret_cast<String*>(value);
}
const String* Native(const PiNodeTracingString* value) noexcept {
  return reinterpret_cast<const String*>(value);
}
TracingController* Native(PiNodeTracingController* value) noexcept {
  return reinterpret_cast<TracingController*>(value);
}
}  // namespace

extern "C" PiNodeTracingLayout pi_node_tracing_layout(void) noexcept {
  DiagnosticContextScope diagnostic(nullptr);
  return {sizeof(Agent), alignof(Agent),
          sizeof(AgentWriterHandle), alignof(AgentWriterHandle),
          sizeof(CategorySet), alignof(CategorySet),
          sizeof(String), alignof(String)};
}

extern "C" PiNodeTracingString* pi_node_tracing_string_construct(
    JSContext* context, void* memory_owner, void* storage,
    const char* bytes, size_t length) noexcept {
  DiagnosticContextScope diagnostic(context);
  AllocationScope allocation(memory_owner);
  return reinterpret_cast<PiNodeTracingString*>(
      ::new (storage) String(bytes, length));
}

extern "C" void pi_node_tracing_string_destroy(
    JSContext* context, void* memory_owner,
    PiNodeTracingString* value) noexcept {
  DiagnosticContextScope diagnostic(context);
  AllocationScope allocation(memory_owner);
  Native(value)->~String();
}

extern "C" PiNodeTracingText pi_node_tracing_string_view(
    JSContext* context, const PiNodeTracingString* value) noexcept {
  DiagnosticContextScope diagnostic(context);
  return {Native(value)->data(), Native(value)->size()};
}

extern "C" PiNodeTracingCategorySet* pi_node_tracing_categories_construct(
    JSContext* context, void* memory_owner, void* storage) noexcept {
  DiagnosticContextScope diagnostic(context);
  AllocationScope allocation(memory_owner);
  return reinterpret_cast<PiNodeTracingCategorySet*>(
      ::new (storage) CategorySet());
}

extern "C" void pi_node_tracing_categories_insert_c_string(
    JSContext* context, void* memory_owner,
    PiNodeTracingCategorySet* categories, const char* category) noexcept {
  DiagnosticContextScope diagnostic(context);
  AllocationScope allocation(memory_owner);
  Native(categories)->emplace(category);
}

extern "C" void pi_node_tracing_categories_destroy(
    JSContext* context, void* memory_owner,
    PiNodeTracingCategorySet* categories) noexcept {
  DiagnosticContextScope diagnostic(context);
  AllocationScope allocation(memory_owner);
  Native(categories)->~CategorySet();
}

extern "C" size_t pi_node_tracing_categories_size(
    JSContext* context, const PiNodeTracingCategorySet* categories) noexcept {
  DiagnosticContextScope diagnostic(context);
  return Native(categories)->size();
}

extern "C" PiNodeTracingAgent* pi_node_tracing_agent_construct(
    JSContext* context, void* memory_owner, void* storage) noexcept {
  DiagnosticContextScope diagnostic(context);
  AllocationScope allocation(memory_owner);
  return reinterpret_cast<PiNodeTracingAgent*>(
      ::new (storage) Agent(memory_owner));
}

extern "C" void pi_node_tracing_agent_destroy(
    JSContext* context, PiNodeTracingAgent* agent) noexcept {
  DiagnosticContextScope diagnostic(context);
  AllocationScope allocation(Native(agent)->memory_owner());
  Native(agent)->~Agent();
}

extern "C" PiNodeTracingController* pi_node_tracing_agent_controller(
    JSContext* context, PiNodeTracingAgent* agent) noexcept {
  DiagnosticContextScope diagnostic(context);
  return reinterpret_cast<PiNodeTracingController*>(
      Native(agent)->GetTracingController());
}

extern "C" PiNodeTracingString* pi_node_tracing_agent_enabled_categories(
    JSContext* context, PiNodeTracingAgent* agent, void* string_storage) noexcept {
  DiagnosticContextScope diagnostic(context);
  AllocationScope allocation(Native(agent)->memory_owner());
  return reinterpret_cast<PiNodeTracingString*>(
      ::new (string_storage) String(Native(agent)->GetEnabledCategories()));
}

extern "C" void pi_node_tracing_agent_flush(
    JSContext* context, PiNodeTracingAgent* agent, int blocking) noexcept {
  DiagnosticContextScope diagnostic(context);
  AllocationScope allocation(Native(agent)->memory_owner());
  Native(agent)->Flush(blocking != 0);
}

extern "C" PiNodeTracingWriterHandle* pi_node_tracing_writer_construct(
    JSContext* context, void* memory_owner, void* storage) noexcept {
  DiagnosticContextScope diagnostic(context);
  AllocationScope allocation(memory_owner);
  return reinterpret_cast<PiNodeTracingWriterHandle*>(
      ::new (storage) AgentWriterHandle());
}

extern "C" void pi_node_tracing_writer_assign_default(
    JSContext* context, PiNodeTracingAgent* agent,
    PiNodeTracingWriterHandle* writer) noexcept {
  DiagnosticContextScope diagnostic(context);
  AllocationScope allocation(Native(agent)->memory_owner());
  *Native(writer) = Native(agent)->DefaultHandle();
}

extern "C" void pi_node_tracing_writer_start_file(
    JSContext* context, PiNodeTracingAgent* agent,
    PiNodeTracingWriterHandle* writer, const PiNodeTracingString* cli_categories,
    const PiNodeTracingString* file_pattern) noexcept {
  DiagnosticContextScope diagnostic(context);
  AllocationScope allocation(Native(agent)->memory_owner());
  constexpr auto convert_to_set = [](auto& categories) -> CategorySet {
    CategorySet out;
    for (const auto& s : categories) {
      out.emplace(String(s.data(), s.size()));
    }
    return out;
  };
  if (Native(writer)->IsDefaultHandle()) {
    using std::operator""sv;
    auto categories = std::views::split(*Native(cli_categories), ","sv);
    *Native(writer) = Native(agent)->AddClient(
        convert_to_set(categories),
        std::unique_ptr<AsyncTraceWriter>(
            new NodeTraceWriter(*Native(file_pattern))),
        Agent::kUseDefaultCategories);
  }
}

extern "C" void pi_node_tracing_writer_enable(
    JSContext* context, void* memory_owner,
    PiNodeTracingWriterHandle* writer,
    const PiNodeTracingCategorySet* categories) noexcept {
  DiagnosticContextScope diagnostic(context);
  AllocationScope allocation(memory_owner);
  Native(writer)->Enable(*Native(categories));
}

extern "C" void pi_node_tracing_writer_disable(
    JSContext* context, void* memory_owner,
    PiNodeTracingWriterHandle* writer,
    const PiNodeTracingCategorySet* categories) noexcept {
  DiagnosticContextScope diagnostic(context);
  AllocationScope allocation(memory_owner);
  Native(writer)->Disable(*Native(categories));
}

extern "C" void pi_node_tracing_writer_reset(
    JSContext* context, void* memory_owner,
    PiNodeTracingWriterHandle* writer) noexcept {
  DiagnosticContextScope diagnostic(context);
  AllocationScope allocation(memory_owner);
  Native(writer)->reset();
}

extern "C" void pi_node_tracing_writer_destroy(
    JSContext* context, void* memory_owner,
    PiNodeTracingWriterHandle* writer) noexcept {
  DiagnosticContextScope diagnostic(context);
  AllocationScope allocation(memory_owner);
  Native(writer)->~AgentWriterHandle();
}

extern "C" int pi_node_tracing_writer_empty(
    JSContext* context, const PiNodeTracingWriterHandle* writer) noexcept {
  DiagnosticContextScope diagnostic(context);
  return Native(writer)->empty();
}

extern "C" int pi_node_tracing_writer_is_default(
    JSContext* context, PiNodeTracingWriterHandle* writer) noexcept {
  DiagnosticContextScope diagnostic(context);
  return Native(writer)->IsDefaultHandle();
}

extern "C" PiNodeTracingAgent* pi_node_tracing_writer_agent(
    JSContext* context, PiNodeTracingWriterHandle* writer) noexcept {
  DiagnosticContextScope diagnostic(context);
  return reinterpret_cast<PiNodeTracingAgent*>(Native(writer)->agent());
}

extern "C" PiNodeTracingController* pi_node_tracing_writer_controller(
    JSContext* context, PiNodeTracingWriterHandle* writer) noexcept {
  DiagnosticContextScope diagnostic(context);
  return reinterpret_cast<PiNodeTracingController*>(
      Native(writer)->GetTracingController());
}

extern "C" void pi_node_tracing_set_agent(
    JSContext* context, PiNodeTracingAgent* agent) noexcept {
  DiagnosticContextScope diagnostic(context);
  TraceEventHelper::SetAgent(Native(agent));
}

extern "C" PiNodeTracingAgent* pi_node_tracing_get_agent(
    JSContext* context) noexcept {
  DiagnosticContextScope diagnostic(context);
  return reinterpret_cast<PiNodeTracingAgent*>(TraceEventHelper::GetAgent());
}

extern "C" PiNodeTracingController* pi_node_tracing_get_controller(
    JSContext* context) noexcept {
  DiagnosticContextScope diagnostic(context);
  return reinterpret_cast<PiNodeTracingController*>(
      TraceEventHelper::GetTracingController());
}

extern "C" const uint8_t* pi_node_tracing_category_enabled(
    JSContext* context, void* memory_owner,
    PiNodeTracingController* controller, const char* category) noexcept {
  DiagnosticContextScope diagnostic(context);
  AllocationScope allocation(memory_owner);
  return Native(controller)->GetCategoryGroupEnabled(category);
}

extern "C" const char* pi_node_tracing_category_name(
    JSContext* context, const uint8_t* enabled_flag) noexcept {
  DiagnosticContextScope diagnostic(context);
  return TracingController::GetCategoryGroupName(enabled_flag);
}
