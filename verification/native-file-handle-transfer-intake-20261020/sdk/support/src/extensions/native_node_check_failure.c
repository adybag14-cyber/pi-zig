/* Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
 * Selected Node fatal, CHECK, corrupted async-stack and native trace paths.
 * Source authority is recorded under native-node-check-failure-sourceonly.
 * This is direct C platform termination, outside guest exception dispatch. */
#include "native_node_check_failure.h"
#include <uv.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdatomic.h>
#ifdef _WIN32
#include <windows.h>
#include <dbghelp.h>
#include <process.h>
#else
#include <execinfo.h>
#include <dlfcn.h>
#include <unistd.h>
#endif

/* This projection is the VM's actual captured-frame logging metadata owner.
 * It reads native provenance; filenames and guest properties do not establish
 * whether a frame is an eval or has a ScriptId. */
extern int JS_ReadCapturedStackFrameLoggingInfo(JSContext *context,
    JSValueConst frame, int *is_eval, int *has_script_id);

static _Thread_local int pi_node_retrieving_js_stacktrace;
static _Atomic int pi_node_in_oom;

static void pi_node_abort_no_backtrace(void) {
#ifdef _WIN32
    _exit(134);
#else
    abort();
#endif
}

/* Native title lookup follows the actual 16-byte/doubling/1MiB source loop.
 * The returned title is native storage; no guest process.title is read. */
static char *pi_node_process_title(void) {
    size_t capacity = 16;
    char *buffer = calloc(capacity, 1);
    if (!buffer) pi_node_abort_no_backtrace();
    for (;;) {
        int rc = uv_get_process_title(buffer, capacity);
        if (rc == 0) return buffer;
        if (rc != UV_ENOBUFS || capacity >= 1024 * 1024) {
            free(buffer);
            buffer = malloc(sizeof("Node.js"));
            if (!buffer) pi_node_abort_no_backtrace();
            memcpy(buffer, "Node.js", sizeof("Node.js"));
            return buffer;
        }
        size_t previous = capacity;
        capacity *= 2;
        char *next = realloc(buffer, capacity);
        if (!next) {
            free(buffer);
            pi_node_abort_no_backtrace();
        }
        buffer = next;
        memset(buffer + previous, 0, capacity - previous);
    }
}

/* Keep capture as a real native call, as in Source's GetStackTrace method. */
#ifdef _WIN32
__declspec(noinline)
#else
__attribute__((noinline))
#endif
static int pi_node_capture_native_stack(void **frames, int capacity) {
#ifdef _WIN32
    return (int)CaptureStackBackTrace(0, (DWORD)capacity, frames, NULL);
#else
    return backtrace(frames, capacity);
#endif
}

#ifdef _WIN32
static char *pi_node_copy_symbol_filename(const char *filename) {
    if (!filename) return NULL;
    size_t bytes = strlen(filename) + 1;
    char *result = malloc(bytes);
    if (!result) pi_node_abort_no_backtrace();
    memcpy(result, filename, bytes);
    return result;
}
#else
/* __cxa_demangle has a C ABI. The active image may be pure C/Zig and therefore
 * have no C++ runtime; in that case retain the actual dladdr symbol unchanged. */
static char *pi_node_demangle_native_symbol(const char *name) {
    typedef char *(*Demangle)(const char *, char *, size_t *, int *);
    void *address = dlsym(RTLD_DEFAULT, "__cxa_demangle");
    Demangle demangle = NULL;
    _Static_assert(sizeof(demangle) == sizeof(address), "POSIX dlsym ABI");
    memcpy(&demangle, &address, sizeof(demangle));
    return demangle ? demangle(name, NULL, NULL, NULL) : NULL;
}
#endif

static void pi_node_dump_native_backtrace(FILE *stream) {
    void *frames[256];
    int count;
    fprintf(stream, "----- Native stack trace -----\n\n");
#ifdef _WIN32
    HANDLE process = GetCurrentProcess();
    /* Source keeps the native symbol context even when initialization reports
     * false. It performs and consumes each lookup, then always cleans up. */
    (void)SymInitialize(process, NULL, TRUE);
    count = pi_node_capture_native_stack(frames, 256);
    for (int i = 1; i < count; ++i) {
        DWORD64 address = (DWORD64)(uintptr_t)frames[i];
        DWORD line_offset = 0;
        IMAGEHLP_LINE64 line;
        memset(&line, 0, sizeof(line));
        line.SizeOfStruct = sizeof(line);
        SymSetOptions(SYMOPT_LOAD_LINES);
        BOOL have_line = SymGetLineFromAddr64(process, address, &line_offset, &line);
        char *filename = NULL;
        DWORD line_number = 0;
        if (have_line) {
            /* Source copies the filename before the following symbol lookup. */
            filename = pi_node_copy_symbol_filename(line.FileName);
            line_number = line.LineNumber;
        } else {
            DWORD error = GetLastError();
#ifdef DEBUG
            fprintf(stderr, "SymGetLineFromAddr64 returned error : %lu\n", (unsigned long)error);
#else
            (void)error;
#endif
        }
        union {
            SYMBOL_INFO alignment;
            unsigned char bytes[sizeof(SYMBOL_INFO) + MAX_SYM_NAME];
        } storage;
        memset(&storage, 0, sizeof(storage));
        SYMBOL_INFO *symbol = (SYMBOL_INFO *)storage.bytes;
        symbol->SizeOfStruct = sizeof(SYMBOL_INFO);
        symbol->MaxNameLen = MAX_SYM_NAME;
        DWORD64 displacement = 0;
        BOOL have_symbol = SymFromAddr(process, address, &displacement, symbol);
        char undecorated[MAX_SYM_NAME];
        const char *name = "";
        if (have_symbol && symbol->Name[0]) {
            if (UnDecorateSymbolName(symbol->Name, undecorated,
                                    sizeof(undecorated), UNDNAME_COMPLETE)) {
                name = undecorated;
            } else {
                DWORD error = GetLastError();
#ifdef DEBUG
                fprintf(stderr, "UnDecorateSymbolName returned error %lu\n", (unsigned long)error);
#else
                (void)error;
#endif
            }
        } else if (!have_symbol) {
            DWORD error = GetLastError();
            displacement = 0;
#ifdef DEBUG
            fprintf(stderr, "SymFromAddr returned error : %lu\n", (unsigned long)error);
#else
            (void)error;
#endif
        }
        fprintf(stream, "%2d: %p %s", i, frames[i], name);
        if (displacement) fprintf(stream, "+%llu", (unsigned long long)displacement);
        if (filename && *filename) fprintf(stream, " [%s]", filename);
        if (line_number) fprintf(stream, ":L%lu", (unsigned long)line_number);
        fputc('\n', stream);
        free(filename);
    }
    (void)SymCleanup(process);
#else
    count = pi_node_capture_native_stack(frames, 256);
    for (int i = 1; i < count; ++i) {
        Dl_info info;
        memset(&info, 0, sizeof(info));
        fprintf(stream, "%2d: %p ", i, frames[i]);
        if (dladdr(frames[i], &info)) {
            if (info.dli_sname) {
                char *demangled = pi_node_demangle_native_symbol(info.dli_sname);
                fprintf(stream, "%s", demangled ? demangled : info.dli_sname);
                free(demangled);
            }
            /* Original POSIX SymbolInfo leaves displacement and line at zero. */
            if (info.dli_fname && *info.dli_fname)
                fprintf(stream, " [%s]", info.dli_fname);
        }
        fputc('\n', stream);
    }
#endif
}

/* TraceEnvVar's nonterminal native operation writes to stderr without an
 * additional flush. The native symbol/capture owner is shared unchanged. */
void pi_node_trace_native_stack(void *opaque) {
    (void)opaque;
    pi_node_dump_native_backtrace(stderr);
}

static void pi_node_restore_diagnostic_exception(JSContext *context,
                                                int had_exception,
                                                JSValue saved) {
    if (!had_exception) return;
    /* A diagnostic allocation/retirement cannot replace the actual reason
     * that was already pending when this terminal native path was entered. */
    if (JS_HasException(context)) {
        JSValue diagnostic = JS_GetException(context);
        JS_FreeValue(context, diagnostic);
    }
    JS_Throw(context, saved);
}

static void pi_node_dump_javascript_backtrace(JSContext *context, FILE *stream) {
    if (!context || pi_node_retrieving_js_stacktrace ||
        atomic_load(&pi_node_in_oom)) return;
    int had_exception = JS_HasException(context);
    JSValue saved = had_exception ? JS_GetException(context) : JS_UNDEFINED;
    pi_node_retrieving_js_stacktrace = 1;
    JSValue stack = JS_CaptureCurrentStackFrames(
        context, 10, JS_UNDEFINED, NULL, 0, 0, 0);
    pi_node_retrieving_js_stacktrace = 0;
    int64_t count = 0;
    if (JS_IsException(stack) || JS_HasException(context) ||
        JS_GetLength(context, stack, &count) < 0 || count <= 0) {
        JS_FreeValue(context, stack);
        pi_node_restore_diagnostic_exception(context, had_exception, saved);
        return;
    }
    fprintf(stream, "\n----- JavaScript stack trace -----\n\n");
    for (int64_t i = 0; i < count; ++i) {
        /* CaptureCurrentStackFrames owns a fresh native-produced array whose
         * indices are real own data properties, never guest accessors. */
        JSValue frame = JS_GetPropertyUint32(context, stack, (uint32_t)i);
        JSValue filename = JS_UNDEFINED, function = JS_UNDEFINED;
        int line = 0, column = 0, native = 0, constructor = 0;
        int is_eval = 0, has_script_id = 0;
        if (JS_IsException(frame) ||
            JS_ReadCapturedStackFrame(context, frame, &filename, &function,
                &line, &column, &native, &constructor) < 0 ||
            JS_ReadCapturedStackFrameLoggingInfo(context, frame,
                &is_eval, &has_script_id) < 0) {
            JS_FreeValue(context, filename);
            JS_FreeValue(context, function);
            JS_FreeValue(context, frame);
            break;
        }
        /* The metadata owners only supply intrinsic strings or absent names.
         * No Error.name/message, CallSite method, or coercion hook is invoked. */
        const char *script_name = JS_IsString(filename)
            ? JS_ToCString(context, filename) : NULL;
        const char *function_name = JS_IsString(function)
            ? JS_ToCString(context, function) : NULL;
        if (JS_HasException(context)) {
            if (script_name) JS_FreeCString(context, script_name);
            if (function_name) JS_FreeCString(context, function_name);
            JS_FreeValue(context, filename);
            JS_FreeValue(context, function);
            JS_FreeValue(context, frame);
            break;
        }
        const char *script_text = script_name ? script_name : "";
        const char *function_text = function_name ? function_name : "";
        if (is_eval) {
            if (!has_script_id)
                fprintf(stream, "%lld: [eval]:%i:%i\n",
                        (long long)i + 1, line, column);
            else
                fprintf(stream, "%lld: [eval] (%s:%i:%i)\n",
                        (long long)i + 1, script_text, line, column);
        } else if (*function_text == '\0') {
            fprintf(stream, "%lld: %s:%i:%i\n",
                    (long long)i + 1, script_text, line, column);
        } else {
            fprintf(stream, "%lld: %s (%s:%i:%i)\n",
                    (long long)i + 1, function_text, script_text, line, column);
        }
        if (script_name) JS_FreeCString(context, script_name);
        if (function_name) JS_FreeCString(context, function_name);
        JS_FreeValue(context, filename);
        JS_FreeValue(context, function);
        JS_FreeValue(context, frame);
        if (is_eval) break;
    }
    /* PrintStackTrace adds one newline, then DumpJavaScriptBacktrace adds one. */
    fputc('\n', stream);
    fflush(stream);
    fputc('\n', stream);
    JS_FreeValue(context, stack);
    pi_node_restore_diagnostic_exception(context, had_exception, saved);
}

static void pi_node_abort(JSContext *context) {
    pi_node_dump_native_backtrace(stderr);
    pi_node_dump_javascript_backtrace(context, stderr);
    fflush(stderr);
    pi_node_abort_no_backtrace();
}

void pi_node_default_fatal_error(JSContext *context, const char *location,
                                 const char *message,
                                 const PiNodeFatalDiagnostics *diagnostics) {
    if (location)
        fprintf(stderr, "FATAL ERROR: %s %s\n", location, message);
    else
        fprintf(stderr, "FATAL ERROR: %s\n", message);
    if (diagnostics && diagnostics->report)
        diagnostics->report(diagnostics->report_opaque, context,
                            message, "FatalError", "");
    fflush(stderr);
    pi_node_abort(context);
}

/* Selected V8 kRetryOrFail heap failure: the original fixed location and
 * kHeapOOM detail reach Node's OOMErrorHandler before any local rollback.
 * The header and report selection require no VM allocation or guest value. */
void pi_node_heap_out_of_memory(JSContext *context,
                                const PiNodeFatalDiagnostics *diagnostics) {
    static const char message[] =
        "Allocation failed - JavaScript heap out of memory";
    atomic_store(&pi_node_in_oom, 1);
    fprintf(stderr, "FATAL ERROR: CALL_AND_RETRY_LAST %s\n", message);
    if (diagnostics && diagnostics->report)
        diagnostics->report(diagnostics->report_opaque, context,
                            message, "OOMError", "");
    fflush(stderr);
    pi_node_abort(context);
}

/* Selected ArrayBuffer::NewBackingStore process OOM terminal callback.
 * The caller completes its actual native allocation/retry policy first.
 * kNoOOMDetails selects process memory and has no optional Reason string. */
void pi_node_backing_store_out_of_memory(JSContext *context,
                                         const PiNodeFatalDiagnostics *diagnostics) {
    static const char message[] =
        "Allocation failed - process out of memory";
    atomic_store(&pi_node_in_oom, 1);
    fprintf(stderr, "FATAL ERROR: v8::ArrayBuffer::NewBackingStore %s\n", message);
    if (diagnostics && diagnostics->report)
        diagnostics->report(diagnostics->report_opaque, context,
                            message, "OOMError", "");
    fflush(stderr);
    pi_node_abort(context);
}

void pi_node_maybe_check_failure(JSContext *context,
                                 const PiNodeFatalDiagnostics *diagnostics) {
    pi_node_default_fatal_error(context, "v8::FromJust",
                                "Maybe value is Nothing", diagnostics);
}

void pi_node_assert_failure(JSContext *context, const PiNodeAssertionInfo *info) {
    char *title = pi_node_process_title();
    fprintf(stderr,
            "\n"
            "  #  %s[%d]: %s at %s\n"
            "  #  Assertion failed: %s\n\n",
            title, (int)uv_os_getpid(),
            info->function ? info->function : "(unknown function)",
            info->file_line ? info->file_line : "(unknown source location)",
            info->message);
    free(title);
    fflush(stderr);
    pi_node_abort(context);
}

void pi_node_corrupted_async_stack(JSContext *context, double actual,
                                   double expected, int abort_on_uncaught) {
    fprintf(stderr,
            "Error: async hook stack has become corrupted ("
            "actual: %.f, expected: %.f)\n", actual, expected);
    pi_node_dump_native_backtrace(stderr);
    pi_node_dump_javascript_backtrace(context, stderr);
    fflush(stderr);
    /* Node's unqualified node::Exit is direct C exit(), not Environment::Exit
     * and not _exit(). This branch does not invoke a guest exit handler. */
    if (!abort_on_uncaught) exit(1);
    fprintf(stderr, "\n");
    fflush(stderr);
    pi_node_abort_no_backtrace();
}
