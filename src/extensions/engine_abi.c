#include "engine_abi.h"
JSValue pi_js_undefined(void) { return JS_UNDEFINED; }
JSValue pi_js_null(void) { return JS_NULL; }
JSValue pi_js_bool(JSContext *context, int value) { return JS_NewBool(context, value); }
JSValue pi_js_int32(JSContext *context, int32_t value) { return JS_NewInt32(context, value); }
JSModuleDef *pi_js_module(JSValue value) { return JS_VALUE_GET_PTR(value); }
