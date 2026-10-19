/* Portable ABI for QuickJS value-construction macros that translate-c cannot
 * represent for both the 32-bit NaN box and 64-bit tagged-union layouts. */
#ifndef PI_EXTENSION_ENGINE_ABI_H
#define PI_EXTENSION_ENGINE_ABI_H
#include "quickjs.h"
JSValue pi_js_undefined(void);
JSValue pi_js_exception(void);
JSValue pi_js_null(void);
JSValue pi_js_bool(JSContext *context, int value);
JSValue pi_js_int32(JSContext *context, int32_t value);
JSModuleDef *pi_js_module(JSValue value);
void *pi_js_object_identity(JSValue value);
/* Allocation-free, host-private tags on genuine native allocator errors. */
void pi_js_mark_native_allocation_error(JSValueConst value, uint64_t generation);
uint64_t pi_js_native_allocation_error_generation(JSValueConst value);
JSValue pi_js_module_value(JSContext *context, JSModuleDef *module);
JSValue pi_js_function_magic(JSContext *context, JSCFunctionMagic *function, const char *name, int length, int magic);
JSRuntime *pi_js_new_runtime(size_t memory_limit, void **memory_owner);
void pi_js_release_memory_owner(void *memory_owner);
size_t pi_js_shared_buffer_allocations(void);
/* Only for trusted same-process serializer tables from pi_js_new_runtime. */
void pi_js_retain_shared_buffer(void *buffer);
void pi_js_release_shared_buffer(void *buffer);
size_t pi_js_native_memory_owners(void);
size_t pi_js_native_memory_used(void *memory_owner);
void pi_js_retain_memory_owner(void *memory_owner);
int pi_js_native_memory_reserve(void *memory_owner, size_t bytes);
void pi_js_native_memory_release(void *memory_owner, size_t bytes);

/* Live native backing-owner diagnostics. owner must come from an owned lease. */
size_t pi_js_array_buffer_backing_allocations(void);
size_t pi_js_array_buffer_backing_references(void *owner);
size_t pi_js_array_buffer_backing_byte_length(void *owner);
size_t pi_js_array_buffer_backing_committed(void *owner);
size_t pi_js_array_buffer_backing_reserved(void *owner);
size_t pi_js_array_buffer_backing_page_size(void *owner);
#endif
