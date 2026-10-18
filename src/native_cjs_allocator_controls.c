/* Test-only genuine VM allocation-event controls, not a compiler model. */
#include "quickjs.h"
#include "libregexp.h"
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef union CompilerBlock {
    max_align_t alignment;
    struct { size_t size; } data;
} CompilerBlock;
typedef struct CompilerFixture {
    size_t events, fail_at, live;
    int induced, loads;
    JSValue first_error;
    JSContext *context;
    JSValue interrupt_reason;
    size_t interrupt_calls, interrupt_stop;
    int legacy_prepare_calls, legacy_failure_prepare_calls, legacy_entered;
    JSValue legacy_prototype, legacy_target, legacy_error_ctor;
    int legacy_finalizer_mode, legacy_finalizer_armed, legacy_finalizer_calls;
} CompilerFixture;

static int compiler_work_interrupt(JSRuntime *runtime, void *opaque)
{
    CompilerFixture *state = opaque;
    (void)runtime;
    if (state->interrupt_calls++ == state->interrupt_stop) {
        if (JS_IsUndefined(state->first_error))
            state->first_error = JS_DupValue(state->context, state->interrupt_reason);
        JS_Throw(state->context, JS_DupValue(state->context, state->interrupt_reason));
    }
    return 0; /* The actual compiler boundary must observe success + pending. */
}
static int compiler_fail(CompilerFixture *state, size_t size)
{
    if (size && state->events++ == state->fail_at) {
        state->induced++;
        return 1;
    }
    return 0;
}
static void *compiler_malloc(void *opaque, size_t size)
{
    CompilerFixture *state = opaque;
    CompilerBlock *block;
    if (size > SIZE_MAX - sizeof(*block) || compiler_fail(state, size))
        return NULL;
    block = malloc(sizeof(*block) + size);
    if (!block)
        return NULL;
    block->data.size = size;
    state->live++;
    return block + 1;
}
static void *compiler_calloc(void *opaque, size_t count, size_t size)
{
    void *result;
    if (size && count > SIZE_MAX / size)
        return NULL;
    result = compiler_malloc(opaque, count * size);
    if (result)
        memset(result, 0, count * size);
    return result;
}
static void compiler_free(void *opaque, void *pointer)
{
    CompilerFixture *state = opaque;
    if (pointer) {
        state->live--;
        free((CompilerBlock *)pointer - 1);
    }
}
static void *compiler_realloc(void *opaque, void *pointer, size_t size)
{
    CompilerFixture *state = opaque;
    CompilerBlock *resized;
    if (!pointer)
        return compiler_malloc(opaque, size);
    if (!size) {
        compiler_free(opaque, pointer);
        return NULL;
    }
    if (size > SIZE_MAX - sizeof(*resized) || compiler_fail(state, size))
        return NULL;
    resized = realloc((CompilerBlock *)pointer - 1, sizeof(*resized) + size);
    if (!resized)
        return NULL;
    resized->data.size = size;
    return resized + 1;
}
static size_t compiler_usable(const void *pointer)
{
    return pointer ? ((const CompilerBlock *)pointer - 1)->data.size : 0;
}
static int compiler_capture(JSContext *context, JSValueConst error, int phase,
                            JSValueConst filter, const char *filename, int line,
                            int column, int flags, void *opaque)
{
    CompilerFixture *state = opaque;
    (void)filter; (void)filename; (void)line; (void)column; (void)flags;
    if (phase == JS_ERROR_STACK_CAPTURE && JS_IsUndefined(state->first_error))
        state->first_error = JS_DupValue(context, error);
    return 0;
}
static JSModuleDef *compiler_forbidden_load(JSContext *context, const char *name,
                                            void *opaque)
{
    CompilerFixture *state = opaque;
    (void)name;
    state->loads++;
    JS_ThrowReferenceError(context, "syntax probe must not load a module");
    return NULL;
}
static int compiler_observer(JSContext *context, const char *body)
{
    JSValue value = JS_Eval(context, body, strlen(body), "C:/compiler/observer.js",
                            JS_EVAL_TYPE_GLOBAL);
    int good = !JS_IsException(value) && !JS_HasException(context) &&
        JS_ToBool(context, value) == 1;
    JS_FreeValue(context, value);
    return good;
}

/* 0 valid CJS with nested semantic compilation and literal regexp; 1 ordinary
   CJS syntax construction; 2 regexp grammar failure; 3 valid detached probe;
   4 detached semantic undefined-export failure. Fresh runtime per event. */
static int compiler_attempt(int mode, size_t offset, size_t *measured,
                             size_t interrupt_stop, size_t *interrupt_measured)
{
    static const JSMallocFunctions allocator = {
        compiler_calloc, compiler_malloc, compiler_free, compiler_realloc, compiler_usable
    };
    CompilerFixture state = {0};
    JSRuntime *runtime = NULL;
    JSContext *context = NULL;
    JSValue source = JS_UNDEFINED, filename = JS_UNDEFINED;
    JSValue result = JS_UNDEFINED, reason = JS_UNDEFINED, healthy = JS_UNDEFINED;
    JSValue syntax_prototype = JS_UNDEFINED;
    JSValue meta_url = JS_NewInt32(NULL, 99), meta_map = JS_NewInt32(NULL, 77);
    const char *body;
    char large_body[65536];
    size_t length, begin;
    JSPiCJSParseCategory category = JS_PI_CJS_NO_SYNTAX_CATEGORY;
    JSPiModuleParseDiagnostic diagnostic = JS_PI_MODULE_NO_SYNTAX_DIAGNOSTIC;
    unsigned flags = 99;
    int status = 1, outcome = -1, i;
    int cjs = mode < 3 || mode == 5 || mode == 6 || mode == 7;
    int valid_cjs = mode == 0 || mode == 5 || mode == 6 || mode == 7;
    JSMemoryUsage before_atoms, after_atoms;
    state.fail_at = SIZE_MAX;
    state.first_error = JS_UNDEFINED;
    state.interrupt_reason = JS_UNDEFINED;
    state.interrupt_stop = interrupt_stop;
    runtime = JS_NewRuntime2(&allocator, &state);
    if (!runtime)
        goto cleanup;
    context = JS_NewContext(runtime);
    if (!context) { status = 2; goto cleanup; }
    state.context = context;
    JS_SetNativeErrorStackHook(runtime, compiler_capture, &state);
    JS_SetModuleLoaderFunc(runtime, NULL, compiler_forbidden_load, &state);
    {
        JSValue global = JS_GetGlobalObject(context);
        JSValue constructor = JS_GetPropertyStr(context, global, "SyntaxError");
        syntax_prototype = JS_GetPropertyStr(context, constructor, "prototype");
        JS_FreeValue(context, constructor);
        JS_FreeValue(context, global);
        if (JS_IsException(syntax_prototype)) { status = 16; goto cleanup; }
    }
    if (mode == 0 || mode == 7) {
        length = 0;
        for (i = 0; i < 128; i++) {
            int count = snprintf(large_body + length, sizeof(large_body) - length,
                                  "function f%d(){return %d};", i, i);
            if (count < 0 || (size_t)count >= sizeof(large_body) - length) { status = 3; goto cleanup; }
            length += (size_t)count;
        }
        if (mode == 7)
            memcpy(large_body + length, "globalThis.executed=1;return 42;\n//# sourceURL=allocation-url.js\n//# sourceMappingURL=allocation.map",
                    sizeof("globalThis.executed=1;return 42;\n//# sourceURL=allocation-url.js\n//# sourceMappingURL=allocation.map"));
        else
            memcpy(large_body + length, "globalThis.executed=1;return /(?:ab|cd|ef|gh|ij|kl|mn|op)+/u.test('ab')?42:0;",
                    sizeof("globalThis.executed=1;return /(?:ab|cd|ef|gh|ij|kl|mn|op)+/u.test('ab')?42:0;"));
        body = large_body;
    } else if (mode == 6) {
        length = 0;
        {
            static const char prefix[] = "var total=0;const dynamic_read_only_name=1;function* delegate(){yield* []}class Base{}class Derived extends Base{method(){delete super.unusedName;}}if(exports){dynamic_read_only_name=2;}";
            memcpy(large_body, prefix, sizeof(prefix) - 1);
            length = sizeof(prefix) - 1;
        }
        for (i = 0; i < 512; i++) {
            int count = snprintf(large_body + length, sizeof(large_body) - length,
                                  "if(false){globalThis.dead_%d;'literal_%d';}else{total+=0;}", i, i);
            if (count < 0 || (size_t)count >= sizeof(large_body) - length) { status = 3; goto cleanup; }
            length += (size_t)count;
        }
        memcpy(large_body + length,
                "for(var i=0;i<2;i++){if(i)total+=3;else total+=4;}try{total+=5;}finally{total+=6;}globalThis.executed=1;return total===18?42:0;",
                sizeof("for(var i=0;i<2;i++){if(i)total+=3;else total+=4;}try{total+=5;}finally{total+=6;}globalThis.executed=1;return total===18?42:0;"));
        body = large_body;
    } else if (mode == 5) {
        body = "globalThis.executed=1;return /[\\q{ab|abc|abcd|abce|ac|acb|acc|acd|ad|adb|adc|add|ae|aeb|aec|aed|af|afb}]/v.test('abc')?42:0;";
    } else if (mode == 1) {
        body = "return )";
    } else if (mode == 2) {
        body = "return /((?:a|b|c|d|e|f)+[z-a])/u";
    } else if (mode == 3) {
        body = "import 'fixture:absent';export const x=1;if(false)await 0;globalThis.executed=1";
    } else {
        body = "export{notDeclared}";
    }
    source = JS_NewString(context, body);
    filename = JS_NewString(context, "fixture:allocation-compiler");
    if (JS_IsException(source) || JS_IsException(filename)) { status = 4; goto cleanup; }
    JS_RunGC(runtime);
    if (mode == 6 || mode == 7) {
        if (mode == 6 || interrupt_measured || interrupt_stop != SIZE_MAX) {
            state.interrupt_reason = JS_NewObject(context);
            if (JS_IsException(state.interrupt_reason)) { status = 19; goto cleanup; }
        }
        JS_ComputeMemoryUsage(runtime, &before_atoms);
        if (mode == 6 || interrupt_measured || interrupt_stop != SIZE_MAX)
            JS_SetInterruptHandler(runtime, compiler_work_interrupt, &state);
    }
    begin = state.events;
    if (offset != SIZE_MAX) {
        if (offset > SIZE_MAX - begin) { status = 5; goto cleanup; }
        state.fail_at = begin + offset;
    }
    if (cjs) {
        result = mode == 7 ?
            JS_PiCompileCJSFunctionInfo(context, source, filename, &category, &meta_url, &meta_map) :
            JS_PiCompileCJSFunction(context, source, filename, &category);
        outcome = JS_IsException(result) ? -1 : 0;
    } else {
        outcome = JS_PiParseModuleSyntax(context, source, filename, &flags, &diagnostic);
    }
    if (mode == 6 || mode == 7)
        JS_SetInterruptHandler(runtime, NULL, NULL);
    if (interrupt_measured)
        *interrupt_measured = state.interrupt_calls;
    state.fail_at = SIZE_MAX;
    if (measured)
        *measured = state.events - begin;
    if (interrupt_stop != SIZE_MAX) {
        if ((mode != 6 && mode != 7) || state.interrupt_calls != interrupt_stop + 1 || outcome != -1 ||
            category != JS_PI_CJS_NO_SYNTAX_CATEGORY || !JS_HasException(context)) {
            status = 20; goto cleanup;
        }
    } else if (offset == SIZE_MAX) {
        if (valid_cjs || mode == 3) {
            if (outcome || JS_HasException(context)) { status = 6; goto cleanup; }
            if ((valid_cjs && category != JS_PI_CJS_NO_SYNTAX_CATEGORY) ||
                (mode == 3 && flags != (JS_PI_MODULE_STATIC_IMPORT_EXPORT | JS_PI_MODULE_TOP_LEVEL_AWAIT))) {
                status = 7; goto cleanup;
            }
        } else if ((cjs && (outcome != -1 || category == JS_PI_CJS_NO_SYNTAX_CATEGORY)) ||
                   (mode == 4 && (outcome != 1 || diagnostic != JS_PI_MODULE_ORDINARY_SYNTAX || flags != 99))) {
            status = 8; goto cleanup;
        }
    } else {
        int operational = outcome == -1 && JS_HasException(context) &&
            (cjs ? category == JS_PI_CJS_NO_SYNTAX_CATEGORY :
             diagnostic == JS_PI_MODULE_NO_SYNTAX_DIAGNOSTIC && flags == 99);
        int recovered = (valid_cjs && outcome == 0 &&
                           category == JS_PI_CJS_NO_SYNTAX_CATEGORY && !JS_HasException(context)) ||
            (mode == 3 && outcome == 0 && !JS_HasException(context) &&
             diagnostic == JS_PI_MODULE_NO_SYNTAX_DIAGNOSTIC &&
             flags == (JS_PI_MODULE_STATIC_IMPORT_EXPORT | JS_PI_MODULE_TOP_LEVEL_AWAIT)) ||
            (cjs && !valid_cjs && outcome == -1 &&
             category != JS_PI_CJS_NO_SYNTAX_CATEGORY && JS_HasException(context)) ||
            (mode == 4 && outcome == 1 && diagnostic == JS_PI_MODULE_ORDINARY_SYNTAX && flags == 99 && JS_HasException(context));
        /* Existing VM optional allocation attempts (for example string-buffer
           shrink and atom-hash growth) can recover without ever producing an
           exception. Do not invent a fatal from allocator NULL alone. Genuine
           VM failure must remain operational; recovery must preserve exact
           baseline semantics and must not have discarded a captured error. */
        if (state.induced != 1 || (!operational && !recovered) ||
            (recovered && (valid_cjs || mode == 3) && !JS_IsUndefined(state.first_error))) {
            status = 9; goto cleanup;
        }
    }
    if (mode == 7 && outcome != 0 &&
        (!JS_IsStrictEqual(context, meta_url, JS_NewInt32(context, 99)) ||
         !JS_IsStrictEqual(context, meta_map, JS_NewInt32(context, 77)))) {
        status = 22; goto cleanup;
    }
    if (JS_HasException(context)) {
        reason = JS_GetException(context);
        if (JS_IsUndefined(state.first_error) ||
            !JS_IsStrictEqual(context, reason, state.first_error)) { status = 10; goto cleanup; }
        if ((cjs && category != JS_PI_CJS_NO_SYNTAX_CATEGORY) || outcome == 1) {
            JSValue prototype = JS_GetPrototype(context, reason);
            int syntax = !JS_IsException(prototype) &&
                JS_IsStrictEqual(context, prototype, syntax_prototype);
            JS_FreeValue(context, prototype);
            if (!syntax) { status = 17; goto cleanup; }
        }
    }
    if (state.loads || JS_IsJobPending(runtime) ||
        !compiler_observer(context, "globalThis.executed===undefined")) { status = 11; goto cleanup; }
    if (mode == 7 && outcome == 0) {
        JSValue url = JS_NewString(context, "allocation-url.js");
        JSValue map = JS_NewString(context, "allocation.map");
        int correct = !JS_HasException(context) &&
            JS_IsStrictEqual(context, meta_url, url) && JS_IsStrictEqual(context, meta_map, map);
        JS_FreeValue(context, url);
        JS_FreeValue(context, map);
        if (!correct) { status = 23; goto cleanup; }
    }
    JS_RunGC(runtime); /* exact retained reason + cleaned parser/FD/module roots */
    if (mode == 6 || mode == 7) {
        JS_FreeValue(context, reason); reason = JS_UNDEFINED;
        JS_FreeValue(context, result); result = JS_UNDEFINED;
        JS_FreeValue(context, state.first_error); state.first_error = JS_UNDEFINED;
        JS_FreeValue(context, meta_url); meta_url = JS_UNDEFINED;
        JS_FreeValue(context, meta_map); meta_map = JS_UNDEFINED;
        JS_RunGC(runtime);
        JS_ComputeMemoryUsage(runtime, &after_atoms);
        if (before_atoms.atom_count != after_atoms.atom_count) { status = 21; goto cleanup; }
    }
    if ((mode == 0 || mode == 5) && outcome == 0) {
        JSValue actual = JS_Call(context, result, JS_UNDEFINED, 0, NULL);
        int correct = !JS_IsException(actual) && !JS_HasException(context) &&
            JS_IsStrictEqual(context, actual, JS_NewInt32(context, 42));
        JS_FreeValue(context, actual);
        if (!correct || !compiler_observer(context, "executed===1&&delete globalThis.executed")) {
            status = 18; goto cleanup;
        }
    }
    {
        JSValue recovery_source = JS_NewString(context, mode == 6 ? body : "globalThis.executed=1;return 42");
        if (JS_IsException(recovery_source)) { status = 12; goto cleanup; }
        healthy = JS_PiCompileCJSFunction(context, recovery_source, filename, &category);
        JS_FreeValue(context, recovery_source);
    }
    if (JS_IsException(healthy) || JS_HasException(context) || category != JS_PI_CJS_NO_SYNTAX_CATEGORY) {
        status = 13; goto cleanup;
    }
    JS_FreeValue(context, result);
    result = JS_Call(context, healthy, JS_UNDEFINED, 0, NULL);
    if (JS_IsException(result) || JS_HasException(context) ||
        !JS_IsStrictEqual(context, result, JS_NewInt32(context, 42)) ||
        !compiler_observer(context, "executed===1")) { status = 14; goto cleanup; }
    status = 0;
cleanup:
    state.fail_at = SIZE_MAX;
    if (runtime)
        JS_SetInterruptHandler(runtime, NULL, NULL);
    if (context) {
        JS_FreeValue(context, JS_GetException(context));
        JS_FreeValue(context, reason);
        JS_FreeValue(context, result);
        JS_FreeValue(context, healthy);
        JS_FreeValue(context, source);
        JS_FreeValue(context, filename);
        JS_FreeValue(context, state.first_error);
        JS_FreeValue(context, state.interrupt_reason);
        JS_FreeValue(context, syntax_prototype);
        JS_FreeValue(context, meta_url);
        JS_FreeValue(context, meta_map);
        JS_SetNativeErrorStackHook(runtime, NULL, NULL);
        JS_FreeContext(context);
    }
    if (runtime)
        JS_FreeRuntime(runtime);
    return state.live ? (status ? status : 15) : status;
}

int pi_test_cjs_compiler_allocations(int mode)
{
    size_t count = 0, index;
    int status;
    if (mode < 0 || mode > 7)
        return 99;
    status = compiler_attempt(mode, SIZE_MAX, &count, SIZE_MAX, NULL);
    if (status)
        return status;
    if (!count || count > 512)
        return 100;
    for (index = 0; index < count; index++) {
        status = compiler_attempt(mode, index, NULL, SIZE_MAX, NULL);
        if (status)
            return (int)(1000 + index * 100 + (size_t)status);
    }
    return 0;
}

static int compiler_work_positions(int mode)
{
    size_t count = 0, index;
    int status = compiler_attempt(mode, SIZE_MAX, NULL, SIZE_MAX, &count);
    if (status)
        return status;
    if (!count || count > 128)
        return 100;
    for (index = 0; index < count; index++) {
        status = compiler_attempt(mode, SIZE_MAX, NULL, index, NULL);
        if (status)
            return (int)(1000 + index * 100 + (size_t)status);
    }
    return 0;
}
int pi_test_cjs_semantic_work(void) { return compiler_work_positions(6); }
int pi_test_cjs_metadata_work(void) { return compiler_work_positions(7); }

static JSValue metadata_legacy_prepare(JSContext *ctx, JSValueConst receiver,
                                       int argc, JSValueConst *argv)
{
    CompilerFixture *state = JS_GetContextOpaque(ctx);
    (void)receiver;
    state->legacy_prepare_calls++;
    return JS_DupValue(ctx, argc > 1 ? argv[1] : JS_UNDEFINED);
}
static void metadata_prototype_finalize(JSRuntime *runtime, JSValue value)
{
    CompilerFixture *state = JS_GetOpaque(value, JS_GetClassID(value));
    (void)runtime;
    if (state && state->legacy_finalizer_armed) {
        state->legacy_finalizer_calls++;
        JS_SetUncatchableError(state->context, state->interrupt_reason);
        JS_Throw(state->context, JS_DupValue(state->context, state->interrupt_reason));
    }
}
static JSValue metadata_prototype_getter(JSContext *ctx, JSValueConst receiver,
                                         int argc, JSValueConst *argv)
{
    CompilerFixture *state = JS_GetContextOpaque(ctx);
    JSValue value = state->legacy_prototype;
    (void)receiver; (void)argc; (void)argv;
    state->legacy_prototype = JS_UNDEFINED; /* Sole ownership passes to Error. */
    return value;
}
static JSValue metadata_unused_target(JSContext *ctx, JSValueConst target,
                                       int argc, JSValueConst *argv)
{
    (void)target; (void)argc; (void)argv;
    return JS_ThrowInternalError(ctx, "newTarget body must not execute");
}
static JSValue metadata_new_error(JSContext *ctx, JSValueConst receiver,
                                   int argc, JSValueConst *argv)
{
    CompilerFixture *state = JS_GetContextOpaque(ctx);
    JSValue result;
    (void)receiver; (void)argc; (void)argv;
    state->legacy_entered++;
    result = state->legacy_finalizer_mode ?
        JS_CallConstructor2(ctx, state->legacy_error_ctor, state->legacy_target, 0, NULL) :
        JS_NewError(ctx); /* Eager actual legacy capture, not a model. */
    if (JS_IsException(result) && JS_HasException(ctx)) {
        JSValue reason = JS_GetException(ctx);
        state->legacy_failure_prepare_calls = state->legacy_prepare_calls;
        state->first_error = JS_DupValue(ctx, reason);
        JS_Throw(ctx, reason); /* Preserve the exact live slot before unwind. */
    }
    return result;
}
static int metadata_legacy_attempt(int finalizer_mode, size_t offset, size_t *measured, int *observed)
{
    static const JSMallocFunctions allocator = {
        compiler_calloc, compiler_malloc, compiler_free, compiler_realloc, compiler_usable
    };
    static const char body[] = "function recurse(n){if(n)return recurse(n-1);return metadataNewError()};return recurse(70);\n//# sourceURL=123";
    CompilerFixture state = {0};
    JSRuntime *runtime = NULL;
    JSContext *context = NULL;
    JSValue source = JS_UNDEFINED, filename = JS_UNDEFINED, function = JS_UNDEFINED;
    JSValue url = JS_UNDEFINED, map = JS_UNDEFINED, global = JS_UNDEFINED;
    JSValue error_constructor = JS_UNDEFINED, result = JS_UNDEFINED, reason = JS_UNDEFINED;
    JSPiCJSParseCategory category = JS_PI_CJS_NO_SYNTAX_CATEGORY;
    size_t begin;
    int status = 1;
    state.fail_at = SIZE_MAX;
    state.first_error = JS_UNDEFINED;
    state.interrupt_reason = state.legacy_prototype = state.legacy_target = state.legacy_error_ctor = JS_UNDEFINED;
    state.legacy_finalizer_mode = finalizer_mode;
    runtime = JS_NewRuntime2(&allocator, &state);
    if (!runtime) goto done;
    context = JS_NewContext(runtime);
    if (!context) { status = 2; goto done; }
    state.context = context;
    JS_SetContextOpaque(context, &state);
    JS_SetNativeErrorStackHook(runtime, compiler_capture, &state);
    source = JS_NewString(context, body);
    filename = JS_NewString(context, "C:/metadata/legacy.cjs");
    function = JS_PiCompileCJSFunctionInfo(context, source, filename, &category, &url, &map);
    if (JS_IsException(function) || JS_HasException(context)) { status = 3; goto done; }
    global = JS_GetGlobalObject(context);
    error_constructor = JS_GetPropertyStr(context, global, "Error");
    if (JS_IsException(global) || JS_IsException(error_constructor) ||
        JS_SetPropertyStr(context, global, "metadataNewError", JS_NewCFunction(context, metadata_new_error, "metadataNewError", 0)) < 0 ||
        JS_SetPropertyStr(context, error_constructor, "prepareStackTrace", JS_NewCFunction(context, metadata_legacy_prepare, "metadataLegacyPrepare", 2)) < 0 ||
        JS_SetPropertyStr(context, error_constructor, "stackTraceLimit", JS_NewInt32(context, 64)) < 0 ||
        JS_HasException(context)) { status = 4; goto done; }
    if (finalizer_mode) {
        JSClassID id = 0;
        JSClassDef definition = { .class_name = "Owned metadata finalizer prototype", .finalizer = metadata_prototype_finalize };
        JSValue getter;
        JSAtom prototype;
        if (!JS_NewClassID(runtime, &id) || JS_NewClass(runtime, id, &definition) < 0) { status = 12; goto done; }
        state.legacy_prototype = JS_NewObjectProtoClass(context, JS_NULL, id);
        if (JS_IsException(state.legacy_prototype)) { status = 13; goto done; }
        JS_SetOpaque(state.legacy_prototype, &state);
        state.legacy_error_ctor = JS_DupValue(context, error_constructor);
        state.legacy_target = JS_NewCFunction2(context, metadata_unused_target, "OwnedMetadataTarget", 0, JS_CFUNC_constructor, 0);
        state.interrupt_reason = JS_NewError(context); /* Preallocated native-owned B. */
        if (JS_IsException(state.legacy_target) || JS_IsException(state.interrupt_reason)) { status = 14; goto done; }
        getter = JS_NewCFunction(context, metadata_prototype_getter, "ownedPrototype", 0);
        prototype = JS_NewAtom(context, "prototype");
        if (prototype == JS_ATOM_NULL) { JS_FreeValue(context, getter); status = 15; goto done; }
        int defined = JS_DefinePropertyGetSet(context, state.legacy_target, prototype, getter, JS_UNDEFINED, 0);
        JS_FreeAtom(context, prototype);
        if (defined < 0 || JS_HasException(context)) { status = 16; goto done; }
    }
    JS_FreeValue(context, state.first_error);
    state.first_error = JS_UNDEFINED;
    JS_SetNativeErrorStackHook(runtime, NULL, NULL); /* Exercise real legacy code. */
    JS_RunGC(runtime);
    begin = state.events;
    state.legacy_finalizer_armed = finalizer_mode;
    if (offset != SIZE_MAX) {
        if (offset > SIZE_MAX - begin) { status = 5; goto done; }
        state.fail_at = begin + offset;
    }
    result = JS_Call(context, function, JS_UNDEFINED, 0, NULL);
    state.fail_at = SIZE_MAX;
    if (measured) *measured = state.events - begin;
    if (offset == SIZE_MAX) {
        if (JS_IsException(result) || JS_HasException(context) || state.legacy_prepare_calls != 1 || state.legacy_entered != 1) { status = 6; goto done; }
    } else {
        if (state.induced != 1) { status = 7; goto done; }
        if (!JS_IsUndefined(state.first_error)) {
            if (!JS_IsException(result) || !JS_HasException(context)) { status = 8; goto done; }
            reason = JS_GetException(context);
            if (!JS_IsStrictEqual(context, reason, state.first_error) || state.legacy_failure_prepare_calls != 0) { status = 9; goto done; }
            if (state.legacy_finalizer_calls &&
                (!JS_IsStrictEqual(context, reason, state.interrupt_reason) || !JS_IsUncatchableError(reason))) { status = 17; goto done; }
            if (observed && (!finalizer_mode || state.legacy_finalizer_calls)) (*observed)++;
            JS_RunGC(runtime); /* Retained exact cause and any real frame roots. */
        }
        /* Other old legacy array/prepare retirement policy is outside this
           metadata-field guard. No captured reason is allowed to disappear. */
    }
    if (JS_IsJobPending(runtime)) { status = 10; goto done; }
    status = 0;
done:
    state.fail_at = SIZE_MAX;
    state.legacy_finalizer_armed = false;
    if (context) {
        JS_FreeValue(context, JS_GetException(context));
        JS_FreeValue(context, reason); JS_FreeValue(context, result);
        JS_FreeValue(context, function); JS_FreeValue(context, source); JS_FreeValue(context, filename);
        JS_FreeValue(context, url); JS_FreeValue(context, map); JS_FreeValue(context, global); JS_FreeValue(context, error_constructor);
        JS_FreeValue(context, state.first_error);
        JS_ClearUncatchableError(context, state.interrupt_reason);
        JS_FreeValue(context, state.interrupt_reason);
        JS_FreeValue(context, state.legacy_prototype);
        JS_FreeValue(context, state.legacy_target);
        JS_FreeValue(context, state.legacy_error_ctor);
        JS_SetNativeErrorStackHook(runtime, NULL, NULL);
        JS_FreeContext(context);
    }
    if (runtime) JS_FreeRuntime(runtime);
    return state.live ? (status ? status : 11) : status;
}
static int metadata_legacy_positions(int finalizer_mode)
{
    size_t measured = 0, index;
    int observed = 0;
    int status = metadata_legacy_attempt(finalizer_mode, SIZE_MAX, &measured, NULL);
    if (status) return status;
    if (!measured || measured > 512) return 100;
    for (index = 0; index < measured; index++) {
        status = metadata_legacy_attempt(finalizer_mode, index, NULL, &observed);
        if (status) return (int)(1000 + index * 100 + (size_t)status);
    }
    return observed ? 0 : 101;
}
int pi_test_cjs_metadata_legacy_allocations(void) { return metadata_legacy_positions(0); }
int pi_test_cjs_metadata_finalizer_allocations(void) { return metadata_legacy_positions(1); }

/* Genuine libregexp opt-in controls. These callbacks are the API's actual
   compile-work/capacity producers, not a clock, parser model or VM field edit. */
typedef struct RegexpCompileFixture {
    size_t polls, stop_at;
    unsigned capacity[7];
    int stopped, repeated;
    JSValue reason;
} RegexpCompileFixture;
static int regexp_compile_poll(void *opaque)
{
    JSContext *context = opaque;
    RegexpCompileFixture *state = JS_GetContextOpaque(context);
    if (state->stopped) {
        state->repeated++;
        return -1;
    }
    if (state->polls++ == state->stop_at || JS_HasException(context)) {
        state->stopped = 1;
        if (!JS_HasException(context))
            JS_Throw(context, JS_DupValue(context, state->reason));
        return -1;
    }
    return 0;
}
static void regexp_compile_capacity(void *opaque, LRECompileLimit limit)
{
    RegexpCompileFixture *state = JS_GetContextOpaque(opaque);
    if ((unsigned)limit >= 7) {
        state->repeated++;
        return;
    }
    state->capacity[limit]++;
}
static int regexp_compile_no_capacities(RegexpCompileFixture *state)
{
    unsigned index;
    for (index = 0; index < 7; index++)
        if (state->capacity[index])
            return 0;
    return 1;
}

/* 0 legacy/NULL equivalence; 1 captures; 2 measured Unicode-set work sweep;
   3 already-pending reason; 4 register ceiling; 5 group scopes; 6 group name. */
int pi_test_cjs_regexp_controls(int mode)
{
    static const LRECompileOptions options = {
        regexp_compile_poll, regexp_compile_capacity,
    };
    JSRuntime *runtime = NULL;
    JSContext *context = NULL;
    RegexpCompileFixture state = {0};
    JSValue observed = JS_UNDEFINED;
    uint8_t *bytecode = NULL, *legacy = NULL, *explicit_null = NULL;
    uint8_t *captures[2];
    char pattern[8192], message[128];
    const uint8_t subject[] = "aAA";
    size_t length = 0, baseline, index;
    int flags = 0, size = 0, legacy_size = 0, null_size = 0;
    int status = 1, expected_limit = -1;
    if (mode < 0 || mode > 6)
        return 99;
    state.reason = JS_UNDEFINED;
    runtime = JS_NewRuntime();
    if (!runtime)
        goto done;
    context = JS_NewContext(runtime);
    if (!context)
        goto done;
    state.stop_at = SIZE_MAX;
    state.reason = JS_NewObject(context);
    if (JS_IsException(state.reason))
        goto done;
    JS_SetContextOpaque(context, &state);
    if (mode == 0 || mode == 3) {
        strcpy(pattern, "(?<word>a+)(?:b|c){2,5}\\k<word>");
        length = strlen(pattern);
        flags = LRE_FLAG_UNICODE;
    } else if (mode == 1) {
        for (index = 0; index < 255; index++) {
            pattern[length++] = '(';
            pattern[length++] = ')';
        }
        expected_limit = LRE_LIMIT_CAPTURES;
    } else if (mode == 2) {
        memcpy(pattern, "[\\q{", 4); length = 4;
        for (index = 0; index < 32; index++) {
            size_t j;
            if (index)
                pattern[length++] = '|';
            pattern[length++] = 'a';
            pattern[length++] = 'A' + index / 26;
            pattern[length++] = 'A' + index % 26;
            for (j = 0; j < index % 7; j++)
                pattern[length++] = 'b';
        }
        memcpy(pattern + length, "}]", 2); length += 2;
        flags = LRE_FLAG_UNICODE_SETS | LRE_FLAG_STICKY;
    } else if (mode == 4) {
        for (index = 0; index < 260; index++) {
            memcpy(pattern + length, "(?:", 3); length += 3;
        }
        pattern[length++] = 'a';
        for (index = 0; index < 260; index++) {
            memcpy(pattern + length, "){2}", 4); length += 4;
        }
        expected_limit = LRE_LIMIT_REGISTERS;
    } else if (mode == 5) {
        strcpy(pattern, "(?<x>a)"); length = strlen(pattern);
        for (index = 0; index < 256; index++) {
            memcpy(pattern + length, "|a", 2); length += 2;
        }
        expected_limit = LRE_LIMIT_GROUP_SCOPES;
    } else {
        memcpy(pattern, "(?<", 3); length = 3;
        for (index = 0; index < 128; index++)
            pattern[length++] = 'a';
        memcpy(pattern + length, ">a)", 3); length += 3;
        expected_limit = LRE_LIMIT_GROUP_NAME;
    }
    pattern[length] = 0;
    if (mode == 3)
        JS_Throw(context, JS_DupValue(context, state.reason));
    bytecode = lre_compile_with_options(&size, message, sizeof(message),
                                        pattern, length, flags, context, &options);
    if (expected_limit >= 0) {
        unsigned limit;
        if (bytecode || size || JS_HasException(context) || state.stopped || state.repeated)
            goto done;
        for (limit = 0; limit < 7; limit++)
            if (state.capacity[limit] != (unsigned)(limit == (unsigned)expected_limit))
                goto done;
    } else if (mode == 3) {
        observed = JS_GetException(context);
        if (bytecode || size || !state.stopped || state.polls != 1 ||
            !JS_IsStrictEqual(context, observed, state.reason) ||
            state.repeated || !regexp_compile_no_capacities(&state))
            goto done;
    } else {
        if (!bytecode || size <= 0 || JS_HasException(context) ||
            !state.polls || state.stopped || state.repeated || !regexp_compile_no_capacities(&state))
            goto done;
        if (mode == 0) {
            size_t saved_polls = state.polls;
            legacy = lre_compile(&legacy_size, message, sizeof(message),
                                  pattern, length, flags, context);
            explicit_null = lre_compile_with_options(&null_size, message,
                                sizeof(message), pattern, length, flags, context, NULL);
            if (!legacy || !explicit_null || legacy_size != size || null_size != size ||
                memcmp(legacy, bytecode, size) || memcmp(explicit_null, legacy, size) ||
                state.polls != saved_polls || JS_HasException(context))
                goto done;
        } else {
            if (lre_get_capture_count(bytecode) != 1 ||
                lre_exec(captures, bytecode, subject, 0, 3, 0, context) != 1 ||
                captures[0] != subject || captures[1] - captures[0] != 3)
                goto done;
            baseline = state.polls;
            if (baseline < 100 || baseline > 16384)
                goto done; /* Bounded measured sweep, never unbounded search. */
            lre_realloc(context, bytecode, 0); bytecode = NULL;
            for (index = 0; index < baseline; index++) {
                state.polls = 0; state.stop_at = index; state.stopped = 0;
                bytecode = lre_compile_with_options(&size, message, sizeof(message),
                                                    pattern, length, flags, context, &options);
                observed = JS_GetException(context);
                if (bytecode || size || !state.stopped || state.polls != index + 1 ||
                    !JS_IsStrictEqual(context, observed, state.reason) ||
                    state.repeated || !regexp_compile_no_capacities(&state))
                    goto done;
                JS_FreeValue(context, observed); observed = JS_UNDEFINED;
                JS_RunGC(runtime);
            }
        }
    }
    /* Recovery proves that borrowed options/list state did not escape. */
    state.polls = 0; state.stop_at = SIZE_MAX; state.stopped = 0;
    JS_FreeValue(context, observed); observed = JS_UNDEFINED;
    lre_realloc(context, bytecode, 0); bytecode = NULL;
    bytecode = lre_compile_with_options(&size, message, sizeof(message),
                                        "a+", 2, 0, context, &options);
    if (!bytecode || size <= 0 || JS_HasException(context) || JS_IsJobPending(runtime))
        goto done;
    status = 0;
 done:
    if (context) {
        lre_realloc(context, bytecode, 0);
        lre_realloc(context, legacy, 0);
        lre_realloc(context, explicit_null, 0);
        JS_FreeValue(context, JS_GetException(context));
        JS_FreeValue(context, observed);
        JS_FreeValue(context, state.reason);
        JS_SetContextOpaque(context, NULL);
        JS_FreeContext(context);
    }
    if (runtime)
        JS_FreeRuntime(runtime);
    return status;
}

typedef struct CompilerInterruptFixture {
    JSContext *context;
    JSValue reason;
    int calls;
} CompilerInterruptFixture;
static int compiler_pending_interrupt(JSRuntime *runtime, void *opaque)
{
    CompilerInterruptFixture *state = opaque;
    (void)runtime;
    state->calls++;
    JS_Throw(state->context, JS_DupValue(state->context, state->reason));
    return 0; /* Actual successful native callback with an actual pending reason. */
}

/* Actual 10000-cadence interrupts inside escaped string/identifier/template/
   private-name work, or the actual shebang loop; no counter/PC/state mutation. */
int pi_test_cjs_lexer_poll(int mode)
{
    JSRuntime *runtime = NULL;
    JSContext *context = NULL;
    CompilerInterruptFixture interrupt_state = {0};
    CompilerFixture capture_state = {0};
    JSValue source = JS_UNDEFINED, filename = JS_UNDEFINED, result = JS_UNDEFINED;
    JSValue observed = JS_UNDEFINED;
    JSPiCJSParseCategory category = JS_PI_CJS_ORDINARY_SYNTAX;
    JSPiModuleParseDiagnostic diagnostic = JS_PI_MODULE_ORDINARY_SYNTAX;
    unsigned flags = 99;
    const char *prefix, *suffix;
    char *body = NULL;
    size_t prefix_length, suffix_length;
    int probe = mode == 5 || mode == 6, status = 1;
    if (mode < 0 || mode > 10)
        return 99;
    interrupt_state.reason = JS_UNDEFINED;
    capture_state.first_error = JS_UNDEFINED;
    if (mode == 0 || mode == 5) { prefix = "void '\\u{"; suffix = "41}';"; }
    else if (mode == 1) { prefix = "var \\u{"; suffix = "61}=1;"; }
    else if (mode == 2) { prefix = "void `\\u{"; suffix = "41}`;"; }
    else if (mode == 3) { prefix = "class C{#\\u{"; suffix = "61}=1;}"; }
    else if (mode == 7) { prefix = "async /*"; suffix = "*/ function f(){};"; }
    else if (mode == 8) { prefix = "async "; suffix = "function f(){};"; }
    else if (mode == 9) { prefix = "const f=x /*"; suffix = "*/=>x;"; }
    else if (mode == 10) { prefix = "ownedLabel //"; suffix = "\n: while(false){};"; }
    else { prefix = "#!"; suffix = "\nvoid 1;"; }
    prefix_length = strlen(prefix); suffix_length = strlen(suffix);
    body = malloc(prefix_length + 50000 + suffix_length + 1);
    if (!body)
        goto done;
    memcpy(body, prefix, prefix_length);
    memset(body + prefix_length, mode == 8 ? ' ' : '0', 50000);
    memcpy(body + prefix_length + 50000, suffix, suffix_length + 1);
    runtime = JS_NewRuntime();
    if (!runtime)
        goto done;
    context = JS_NewContext(runtime);
    if (!context)
        goto done;
    JS_SetNativeErrorStackHook(runtime, compiler_capture, &capture_state);
    interrupt_state.context = context;
    interrupt_state.reason = JS_NewObject(context);
    source = JS_NewString(context, body);
    filename = JS_NewString(context, "fixture:actual-lexer-work-poll");
    if (JS_IsException(interrupt_state.reason) || JS_IsException(source) || JS_IsException(filename))
        goto done;
    JS_SetInterruptHandler(runtime, compiler_pending_interrupt, &interrupt_state);
    if (probe) {
        int outcome = JS_PiParseModuleSyntax(context, source, filename, &flags, &diagnostic);
        if (outcome != -1 || flags != 99 || diagnostic != JS_PI_MODULE_NO_SYNTAX_DIAGNOSTIC)
            goto done;
    } else {
        result = JS_PiCompileCJSFunction(context, source, filename, &category);
        if (!JS_IsException(result) || category != JS_PI_CJS_NO_SYNTAX_CATEGORY)
            goto done;
    }
    JS_SetInterruptHandler(runtime, NULL, NULL);
    if (!interrupt_state.calls || !JS_HasException(context))
        goto done;
    observed = JS_GetException(context);
    if (!JS_IsStrictEqual(context, observed, interrupt_state.reason) ||
        !JS_IsUndefined(capture_state.first_error) || JS_IsJobPending(runtime))
        goto done; /* No diagnostic producer may replace or coerce this reason. */
    JS_RunGC(runtime);
    JS_FreeValue(context, source);
    source = JS_NewString(context, "return 42");
    JS_FreeValue(context, result);
    result = JS_PiCompileCJSFunction(context, source, filename, &category);
    if (JS_IsException(result) || JS_HasException(context) || category != JS_PI_CJS_NO_SYNTAX_CATEGORY)
        goto done;
    {
        JSValue actual = JS_Call(context, result, JS_UNDEFINED, 0, NULL);
        int good = !JS_IsException(actual) && !JS_HasException(context) &&
            JS_IsStrictEqual(context, actual, JS_NewInt32(context, 42));
        JS_FreeValue(context, actual);
        if (!good)
            goto done;
    }
    status = 0;
 done:
    if (runtime)
        JS_SetInterruptHandler(runtime, NULL, NULL);
    if (context) {
        JS_FreeValue(context, JS_GetException(context));
        JS_FreeValue(context, observed);
        JS_FreeValue(context, interrupt_state.reason);
        JS_FreeValue(context, capture_state.first_error);
        JS_FreeValue(context, source);
        JS_FreeValue(context, filename);
        JS_FreeValue(context, result);
        JS_SetNativeErrorStackHook(runtime, NULL, NULL);
        JS_FreeContext(context);
    }
    if (runtime)
        JS_FreeRuntime(runtime);
    free(body);
    return status;
}
