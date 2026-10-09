/* Portable ABI for QuickJS value-construction macros that translate-c cannot
 * represent for both the 32-bit NaN box and 64-bit tagged-union layouts. */
#ifndef PI_EXTENSION_ENGINE_ABI_H
#define PI_EXTENSION_ENGINE_ABI_H
#include "quickjs.h"
JSValue pi_js_undefined(void);
JSValue pi_js_null(void);
JSValue pi_js_bool(JSContext *context, int value);
JSValue pi_js_int32(JSContext *context, int32_t value);
JSModuleDef *pi_js_module(JSValue value);
void *pi_js_object_identity(JSValue value);
JSValue pi_js_module_value(JSContext *context, JSModuleDef *module);
JSValue pi_js_function_magic(JSContext *context, JSCFunctionMagic *function, const char *name, int length, int magic);
JSRuntime *pi_js_new_runtime(size_t memory_limit, void **memory_owner);
void pi_js_release_memory_owner(void *memory_owner);
size_t pi_js_shared_buffer_allocations(void);
size_t pi_js_native_memory_owners(void);
size_t pi_js_native_memory_used(void *memory_owner);
#endif
