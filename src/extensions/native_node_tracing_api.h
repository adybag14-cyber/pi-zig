/* Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
 * Direct native Agent/container operation admission. Storage is caller owned;
 * every opaque object has the exact underlying native value representation. */
#ifndef PI_NATIVE_NODE_TRACING_API_H
#define PI_NATIVE_NODE_TRACING_API_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
#define PI_TRACING_NOEXCEPT noexcept
extern "C" {
#else
#define PI_TRACING_NOEXCEPT
#endif
struct JSContext;
typedef struct PiNodeTracingAgent PiNodeTracingAgent;
typedef struct PiNodeTracingWriterHandle PiNodeTracingWriterHandle;
typedef struct PiNodeTracingCategorySet PiNodeTracingCategorySet;
typedef struct PiNodeTracingString PiNodeTracingString;
typedef struct PiNodeTracingController PiNodeTracingController;

typedef struct PiNodeTracingLayout {
  size_t agent_size;
  size_t agent_alignment;
  size_t writer_handle_size;
  size_t writer_handle_alignment;
  size_t category_set_size;
  size_t category_set_alignment;
  size_t string_size;
  size_t string_alignment;
} PiNodeTracingLayout;
typedef struct PiNodeTracingText {
  const char* data;
  size_t length;
} PiNodeTracingText;
PiNodeTracingLayout pi_node_tracing_layout(void) PI_TRACING_NOEXCEPT;

/* All contexts are nullable, borrowed only until this call returns. Each entry
 * establishes its diagnostic scope before any allocation scope or native local.
 * A null context masks an outer scope. No context is stored or sent to a worker.
 * Native memory owners are nonnull; each allocation retains its own owner.
 * Storage must be stable, vacant and aligned to the queried native layout.
 * Destroy an object exactly once, then release its storage in the caller.
 *
 * Strings materialize the original native byte-length inputs before operations
 * such as StartTracingAgent. text_view borrows bytes until that String dies.
 * Category insertion takes the original NodeCategorySet::New NUL-terminated
 * UTF-8 result; it uses emplace(c_string), including the original NUL boundary.
 * No guest coercion, property access or exception is performed by this ABI. */
PiNodeTracingString* pi_node_tracing_string_construct(
    struct JSContext* context, void* memory_owner, void* storage,
    const char* bytes, size_t length) PI_TRACING_NOEXCEPT;
void pi_node_tracing_string_destroy(
    struct JSContext* context, void* memory_owner,
    PiNodeTracingString* value) PI_TRACING_NOEXCEPT;
PiNodeTracingText pi_node_tracing_string_view(
    struct JSContext* context, const PiNodeTracingString* value)
    PI_TRACING_NOEXCEPT;
PiNodeTracingCategorySet* pi_node_tracing_categories_construct(
    struct JSContext* context, void* memory_owner, void* storage)
    PI_TRACING_NOEXCEPT;
void pi_node_tracing_categories_insert_c_string(
    struct JSContext* context, void* memory_owner,
    PiNodeTracingCategorySet* categories, const char* category)
    PI_TRACING_NOEXCEPT;
void pi_node_tracing_categories_destroy(
    struct JSContext* context, void* memory_owner,
    PiNodeTracingCategorySet* categories) PI_TRACING_NOEXCEPT;
size_t pi_node_tracing_categories_size(
    struct JSContext* context, const PiNodeTracingCategorySet* categories)
    PI_TRACING_NOEXCEPT;

/* An Agent retains only its native memory owner, then retires that owner after
 * every member and joined worker. All handles, publishers, observers and event
 * producers obey the original Agent/process lifetimes; this ABI adds no lease.
 * Process startup supplies the actual observer and platform ordering before
 * publication. It clears publication and stops producers before Agent teardown. */
PiNodeTracingAgent* pi_node_tracing_agent_construct(
    struct JSContext* context, void* memory_owner, void* storage)
    PI_TRACING_NOEXCEPT;
void pi_node_tracing_agent_destroy(
    struct JSContext* context, PiNodeTracingAgent* agent) PI_TRACING_NOEXCEPT;
PiNodeTracingController* pi_node_tracing_agent_controller(
    struct JSContext* context, PiNodeTracingAgent* agent) PI_TRACING_NOEXCEPT;
PiNodeTracingString* pi_node_tracing_agent_enabled_categories(
    struct JSContext* context, PiNodeTracingAgent* agent, void* string_storage)
    PI_TRACING_NOEXCEPT;
void pi_node_tracing_agent_flush(
    struct JSContext* context, PiNodeTracingAgent* agent, int blocking)
    PI_TRACING_NOEXCEPT;

/* The live native handle is a value that borrows its Agent. Initialization
 * constructs the empty member and then assigns DefaultHandle, as upstream.
 * writer_start_file is the exact selected V8Platform::StartTracingAgent body:
 * guard IsDefaultHandle, split CLI categories with std::views::split, construct
 * NodeTraceWriter, AddClient(kUseDefaultCategories), and move-assign the handle.
 * Empty, duplicate and trailing-empty CLI tokens keep native range semantics.
 * It does not install the process observer or initialize a VM platform.
 * All writer handles must be reset/destroyed before their Agent. Supplied memory
 * owners must be the native owner of that Agent throughout these calls. */
PiNodeTracingWriterHandle* pi_node_tracing_writer_construct(
    struct JSContext* context, void* memory_owner, void* storage)
    PI_TRACING_NOEXCEPT;
void pi_node_tracing_writer_assign_default(
    struct JSContext* context, PiNodeTracingAgent* agent,
    PiNodeTracingWriterHandle* writer) PI_TRACING_NOEXCEPT;
void pi_node_tracing_writer_start_file(
    struct JSContext* context, PiNodeTracingAgent* agent,
    PiNodeTracingWriterHandle* writer, const PiNodeTracingString* cli_categories,
    const PiNodeTracingString* file_pattern) PI_TRACING_NOEXCEPT;
void pi_node_tracing_writer_enable(
    struct JSContext* context, void* memory_owner,
    PiNodeTracingWriterHandle* writer,
    const PiNodeTracingCategorySet* categories) PI_TRACING_NOEXCEPT;
void pi_node_tracing_writer_disable(
    struct JSContext* context, void* memory_owner,
    PiNodeTracingWriterHandle* writer,
    const PiNodeTracingCategorySet* categories) PI_TRACING_NOEXCEPT;
void pi_node_tracing_writer_reset(
    struct JSContext* context, void* memory_owner,
    PiNodeTracingWriterHandle* writer) PI_TRACING_NOEXCEPT;
void pi_node_tracing_writer_destroy(
    struct JSContext* context, void* memory_owner,
    PiNodeTracingWriterHandle* writer) PI_TRACING_NOEXCEPT;
int pi_node_tracing_writer_empty(
    struct JSContext* context, const PiNodeTracingWriterHandle* writer)
    PI_TRACING_NOEXCEPT;
int pi_node_tracing_writer_is_default(
    struct JSContext* context, PiNodeTracingWriterHandle* writer)
    PI_TRACING_NOEXCEPT;
PiNodeTracingAgent* pi_node_tracing_writer_agent(
    struct JSContext* context, PiNodeTracingWriterHandle* writer)
    PI_TRACING_NOEXCEPT;
PiNodeTracingController* pi_node_tracing_writer_controller(
    struct JSContext* context, PiNodeTracingWriterHandle* writer)
    PI_TRACING_NOEXCEPT;

/* Exact process-global TraceEventHelper publication. Passing null clears both
 * Agent and controller. Returned pointers are borrowed; no reference is added.
 * Category lookup uses the actual process registry, including disabled interning.
 * The enabled byte is the real native byte used by the original external
 * ArrayBuffer binding. Its VM backing-store admission remains with that binding. */
void pi_node_tracing_set_agent(
    struct JSContext* context, PiNodeTracingAgent* agent) PI_TRACING_NOEXCEPT;
PiNodeTracingAgent* pi_node_tracing_get_agent(struct JSContext* context)
    PI_TRACING_NOEXCEPT;
PiNodeTracingController* pi_node_tracing_get_controller(
    struct JSContext* context) PI_TRACING_NOEXCEPT;
const uint8_t* pi_node_tracing_category_enabled(
    struct JSContext* context, void* memory_owner,
    PiNodeTracingController* controller, const char* category)
    PI_TRACING_NOEXCEPT;
const char* pi_node_tracing_category_name(
    struct JSContext* context, const uint8_t* enabled_flag)
    PI_TRACING_NOEXCEPT;
#ifdef __cplusplus
}
#endif
#undef PI_TRACING_NOEXCEPT
#endif
