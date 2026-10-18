/* Test-only actual QuickJS allocator/Module API controls. No ModuleDef casts,
   synthetic module fields, product fault hooks, or candidate implementation. */
#include "quickjs.h"
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef union LinkAllocation {
    max_align_t alignment;
    struct { size_t size; } data;
} LinkAllocation;

typedef struct LinkFixture {
    size_t calls, fail_at, live;
    int induced, initialized, capture_calls, loads;
    JSValue captured_error;
} LinkFixture;

static int allocation_fails(LinkFixture *fixture, size_t size)
{
    if (!size)
        return 0;
    if (fixture->calls++ == fixture->fail_at) {
        fixture->induced++;
        return 1; /* Exactly one actual native allocation event fails. */
    }
    return 0;
}

static void *fixture_malloc(void *opaque, size_t size)
{
    LinkFixture *fixture = opaque;
    LinkAllocation *allocation;
    if (size > SIZE_MAX - sizeof(*allocation) || allocation_fails(fixture, size))
        return NULL;
    allocation = malloc(sizeof(*allocation) + size);
    if (!allocation)
        return NULL;
    allocation->data.size = size;
    fixture->live++;
    return allocation + 1;
}

static void *fixture_calloc(void *opaque, size_t count, size_t size)
{
    void *result;
    if (size && count > SIZE_MAX / size)
        return NULL;
    result = fixture_malloc(opaque, count * size);
    if (result)
        memset(result, 0, count * size);
    return result;
}

static void fixture_free(void *opaque, void *pointer)
{
    LinkFixture *fixture = opaque;
    if (pointer) {
        fixture->live--;
        free((LinkAllocation *)pointer - 1);
    }
}

static void *fixture_realloc(void *opaque, void *pointer, size_t size)
{
    LinkFixture *fixture = opaque;
    LinkAllocation *resized;
    if (!pointer)
        return fixture_malloc(opaque, size);
    if (!size) {
        fixture_free(opaque, pointer);
        return NULL;
    }
    if (size > SIZE_MAX - sizeof(*resized) || allocation_fails(fixture, size))
        return NULL;
    resized = realloc((LinkAllocation *)pointer - 1, sizeof(*resized) + size);
    if (!resized)
        return NULL;
    resized->data.size = size;
    return resized + 1;
}

static size_t fixture_usable(const void *pointer)
{
    return pointer ? ((const LinkAllocation *)pointer - 1)->data.size : 0;
}

static int fixture_capture(JSContext *context, JSValueConst error, int phase,
                           JSValueConst filter, const char *filename, int line,
                           int column, int flags, void *opaque)
{
    LinkFixture *fixture = opaque;
    (void)filter; (void)filename; (void)line; (void)column; (void)flags;
    if (phase == JS_ERROR_STACK_CAPTURE && JS_IsUndefined(fixture->captured_error)) {
        fixture->captured_error = JS_DupValue(context, error);
        fixture->capture_calls++;
    }
    return 0; /* Native capture-only control; no guest lookup or formatting. */
}

static int fixture_native_init(JSContext *context, JSModuleDef *module)
{
    LinkFixture *fixture = JS_GetContextOpaque(context);
    int i;
    fixture->initialized++;
    for (i = 0; i < 192; i++) {
        char name[16];
        snprintf(name, sizeof(name), "e%d", i);
        if (JS_SetModuleExport(context, module, name, JS_NewInt32(context, i)) < 0)
            return -1;
    }
    return 0;
}

static int fixture_true(JSContext *context, const char *source)
{
    JSValue result = JS_Eval(context, source, strlen(source), "C:/link/check.js",
                             JS_EVAL_TYPE_GLOBAL);
    int status = !JS_IsException(result) && !JS_HasException(context) &&
                 JS_ToBool(context, result) == 1;
    JS_FreeValue(context, result);
    return status;
}

static JSModuleDef *fixture_loader(JSContext *context, const char *name, void *opaque)
{
    LinkFixture *fixture = opaque;
    const char *source;
    JSValue compiled;
    JSModuleDef *module;
    fixture->loads++;
    if (!strcmp(name, "fixture:a"))
        source = "import * as b from'fixture:b';export function f(){return b.g()};globalThis.aBody=1;";
    else if (!strcmp(name, "fixture:b"))
        source = "import * as a from'fixture:a';export function g(){return 9};export{a};globalThis.bBody=1;";
    else {
        JS_ThrowReferenceError(context, "unknown owned fixture module");
        return NULL;
    }
    compiled = JS_Eval(context, source, strlen(source), name,
                       JS_EVAL_TYPE_MODULE | JS_EVAL_FLAG_COMPILE_ONLY);
    if (JS_IsException(compiled))
        return NULL;
    module = JS_VALUE_GET_PTR(compiled); /* actual returned token, no field casts */
    JS_FreeValue(context, compiled);
    return module;
}

/* mode 0: partial native export cells + native namespace.
   mode 1: parent creation before a later script child, declaration closures.
   mode 2: numeric/empty/Unicode namespace-key materialization and properties.
   mode 3: genuine cyclic namespaces cached before the containing SCC commits.
   Returns a diagnostic code, never hides an unexpected result's ownership. */
static int allocation_attempt(int mode, int default_retry, size_t offset, size_t *measured)
{
    static const JSMallocFunctions functions = {
        fixture_calloc, fixture_malloc, fixture_free, fixture_realloc, fixture_usable
    };
    LinkFixture fixture = {0};
    JSRuntime *runtime = NULL;
    JSContext *context = NULL;
    JSValue root = JS_UNDEFINED, child = JS_UNDEFINED, result = JS_UNDEFINED;
    JSValue reason = JS_UNDEFINED;
    JSModuleDef *native;
    const char *root_source;
    char child_source[12000];
    size_t start;
    int status = 1, linked, i, original_loads;
    fixture.fail_at = SIZE_MAX;
    fixture.captured_error = JS_UNDEFINED;
    runtime = JS_NewRuntime2(&functions, &fixture);
    if (!runtime)
        goto cleanup;
    context = JS_NewContext(runtime);
    if (!context) { status = 2; goto cleanup; }
    JS_SetContextOpaque(context, &fixture);
    JS_SetNativeErrorStackHook(runtime, fixture_capture, &fixture);
    if (mode == 0) {
        native = JS_NewCModule(context, "fixture:native", fixture_native_init);
        if (!native) { status = 3; goto cleanup; }
        for (i = 0; i < 192; i++) {
            char name[16];
            snprintf(name, sizeof(name), "e%d", i);
            if (JS_AddModuleExport(context, native, name) < 0) { status = 4; goto cleanup; }
        }
        root_source = "import * as ns from 'fixture:native';globalThis.ran=1;globalThis.ns=ns;";
    } else if (mode == 3) {
        JS_SetModuleLoaderFunc(runtime, NULL, fixture_loader, &fixture);
        root_source = "import * as a from'fixture:a';globalThis.ran=1;globalThis.ns=a;";
    } else {
        const char *source = mode == 1
            ? "export let x=2;export function f(){return x};globalThis.childRan=1;"
            : "let a=3;export{a as '10',a as '2',a as '',a as '\\u{10000}',a as '\\ue000',a as z};globalThis.childRan=1;";
        if (mode == 1 || mode == 2) {
            size_t length = strlen(source);
            memcpy(child_source, source, length + 1);
            /* Force actual backing allocator events in both fixture families.
               Six namespace keys alone can reuse already populated arenas. */
            for (i = 0; i < (mode == 1 ? 128 : 192); i++) {
                int written;
                if (mode == 1)
                    written = snprintf(child_source + length, sizeof(child_source) - length,
                                       "export function f%d(){return %d};", i, i);
                else
                    written = snprintf(child_source + length, sizeof(child_source) - length,
                                       "export{a as pad%d};", i);
                if (written < 0 || (size_t)written >= sizeof(child_source) - length) {
                    status = 19; goto cleanup;
                }
                length += (size_t)written;
            }
            source = child_source;
        }
        child = JS_Eval(context, source, strlen(source), "fixture:child",
                         JS_EVAL_TYPE_MODULE | JS_EVAL_FLAG_COMPILE_ONLY);
        if (JS_IsException(child)) { status = 5; goto cleanup; }
        root_source = mode == 1
            ? "import{x,f}from'fixture:child';export function g(){return f()+x};globalThis.ran=g();"
            : "import * as ns from'fixture:child';globalThis.ran=1;globalThis.ns=ns;";
    }
    root = JS_Eval(context, root_source, strlen(root_source), "C:/link/root.mjs",
                    JS_EVAL_TYPE_MODULE | JS_EVAL_FLAG_COMPILE_ONLY);
    if (JS_IsException(root)) { status = 6; goto cleanup; }
    original_loads = fixture.loads;
    JS_RunGC(runtime);
    start = fixture.calls;
    if (offset != SIZE_MAX) {
        if (offset > SIZE_MAX - start) { status = 7; goto cleanup; }
        fixture.fail_at = start + offset;
    }
    linked = JS_PiLinkModuleGraph(context, root);
    fixture.fail_at = SIZE_MAX; /* Recovery and checks never inject a second event. */
    if (measured)
        *measured = fixture.calls - start;
    if (offset == SIZE_MAX) {
        if (linked || JS_HasException(context)) { status = 8; goto cleanup; }
    } else {
        if (fixture.induced != 1 || linked != -1 || !JS_HasException(context)) {
            status = 9; goto cleanup;
        }
        reason = JS_GetException(context);
        if (JS_IsUndefined(fixture.captured_error) ||
            !JS_IsStrictEqual(context, reason, fixture.captured_error)) {
            status = 10; goto cleanup;
        }
        if (fixture.initialized || fixture.loads != original_loads || !fixture_true(context,
                "globalThis.ran===undefined&&globalThis.childRan===undefined&&globalThis.aBody===undefined&&globalThis.bBody===undefined")) {
            status = 11; goto cleanup;
        }
        /* GC while the exact reason is retained must not invalidate its private
           frame roots or the restored module/environment. */
        JS_RunGC(runtime);
        if (default_retry) {
            result = JS_EvalFunction(context, JS_DupValue(context, root));
            if (JS_IsException(result) || JS_HasException(context)) {
                status = 21; goto cleanup;
            }
            goto evaluated;
        }
        if (JS_PiLinkModuleGraph(context, root) || JS_HasException(context)) {
            status = 12; goto cleanup;
        }
    }
    if (fixture.initialized || fixture.loads != original_loads || !fixture_true(context,
            "globalThis.ran===undefined&&globalThis.childRan===undefined&&globalThis.aBody===undefined&&globalThis.bBody===undefined") ||
        JS_IsJobPending(runtime)) { status = 13; goto cleanup; }
    result = JS_EvalFunction(context, JS_DupValue(context, root));
    if (JS_IsException(result) || JS_HasException(context)) { status = 14; goto cleanup; }
evaluated:
    if (fixture.loads != original_loads) { status = 22; goto cleanup; }
    if (mode == 0) {
        if (fixture.initialized != 1 || !fixture_true(context,
                "ran===1&&ns.e0===0&&ns.e191===191")) { status = 15; goto cleanup; }
    } else if (mode == 1) {
        if (!fixture_true(context, "ran===4&&childRan===1")) { status = 16; goto cleanup; }
    } else if (mode == 3) {
        if (!fixture_true(context, "ran===1&&aBody===1&&bBody===1&&ns.f()===9")) {
            status = 20; goto cleanup;
        }
    } else if (!fixture_true(context,
            "ran===1&&childRan===1&&ns['10']===3&&ns['2']===3&&ns['']===3&&ns['\\u{10000}']===3&&ns['\\ue000']===3&&ns.z===3&&Object.keys(ns).length===198&&Array.from({length:192},(_,i)=>ns['pad'+i]).every(value=>value===3)")) {
        status = 17; goto cleanup;
    }
    status = 0;
cleanup:
    fixture.fail_at = SIZE_MAX;
    if (context) {
        JS_FreeValue(context, JS_GetException(context));
        JS_FreeValue(context, reason);
        JS_FreeValue(context, result);
        JS_FreeValue(context, child);
        JS_FreeValue(context, root);
        JS_FreeValue(context, fixture.captured_error);
        JS_SetNativeErrorStackHook(runtime, NULL, NULL);
        JS_FreeContext(context);
    }
    if (runtime)
        JS_FreeRuntime(runtime);
    if (fixture.live)
        return status ? status : 18;
    return status;
}

int pi_test_module_link_allocation_positions(int mode)
{
    size_t measured = 0, offset;
    int status;
    int default_retry;
    if (mode < 0 || mode > 7)
        return 99;
    default_retry = mode >= 4;
    mode &= 3;
    status = allocation_attempt(mode, default_retry, SIZE_MAX, &measured);
    if (status)
        return status;
    /* Bounded actual measurement, not a guessed success count. Every measured
       link allocation is tested in a fresh VM, with exact one-shot failure. */
    if (!measured || measured > 512) {
        fprintf(stderr, "module link allocation sweep invalid host event count: mode=%d default_retry=%d measured=%zu\n",
                mode, default_retry, measured);
        return 100;
    }
    for (offset = 0; offset < measured; offset++) {
        status = allocation_attempt(mode, default_retry, offset, NULL);
        if (status)
            return (int)(1000 + offset * 100 + (size_t)status);
    }
    return 0;
}
