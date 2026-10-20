// Copyright 2006-2008, 2012, 2023 the V8 project authors.
// BSD-style license retained with the pinned Node/V8 source authority.
// Native V8 base fatal owner. No Node assertion or VM error substitution.
#include "native_v8_base_fatal.h"

#include <cstdarg>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#if defined(_WIN32) && !defined(__CYGWIN__)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#ifdef V8_FUZZILLI
#include <process.h>
#endif
#else
#include <unistd.h>
#if defined(ANDROID) && !defined(V8_ANDROID_LOG_STDOUT)
#include <android/log.h>
#endif
#endif

extern "C" {
pi_v8_base_abort_mode pi_v8_base_g_abort_mode = PI_V8_BASE_DEFAULT_ABORT_MODE;
}

namespace {

void DefaultDcheckHandler(const char* file, int line, const char* message);

pi_v8_base_print_stack_trace_function g_print_stack_trace = nullptr;
pi_v8_base_dcheck_function g_dcheck_function = DefaultDcheckHandler;
pi_v8_base_fatal_function g_fatal_function = nullptr;

bool ControlledCrashesAreHarmless() {
  return pi_v8_base_g_abort_mode ==
             PI_V8_BASE_EXIT_WITH_SUCCESS_AND_IGNORE_DCHECK_FAILURES ||
         pi_v8_base_g_abort_mode ==
             PI_V8_BASE_EXIT_WITH_FAILURE_AND_IGNORE_DCHECK_FAILURES;
}

bool DcheckFailuresAreIgnored() {
  return pi_v8_base_g_abort_mode ==
             PI_V8_BASE_EXIT_WITH_SUCCESS_AND_IGNORE_DCHECK_FAILURES ||
         pi_v8_base_g_abort_mode ==
             PI_V8_BASE_EXIT_WITH_FAILURE_AND_IGNORE_DCHECK_FAILURES;
}

int VSNPrintF(char* str, int length, const char* format, va_list args) {
#if defined(_WIN32) && !defined(__CYGWIN__)
  int n = _vsnprintf_s(str, length, _TRUNCATE, format, args);
#else
  int n = vsnprintf(str, length, format, args);
#endif
  if (n < 0 || n >= length) {
    if (length > 0) str[length - 1] = '\0';
    return -1;
  } else {
    return n;
  }
}

#if defined(_WIN32) && !defined(__CYGWIN__)
enum OutputMode { UNKNOWN, CONSOLE, ODS };
static OutputMode output_mode = UNKNOWN;

static bool HasConsole() {
  // Preserve the original first-observation cache and its native race policy.
  if (output_mode == UNKNOWN) {
    if (GetStdHandle(STD_OUTPUT_HANDLE) != INVALID_HANDLE_VALUE &&
        GetFileType(GetStdHandle(STD_OUTPUT_HANDLE)) != FILE_TYPE_UNKNOWN)
      output_mode = CONSOLE;
    else
      output_mode = ODS;
  }
  return output_mode == CONSOLE;
}

static void VPrintHelper(FILE* stream, const char* format, va_list args) {
  if ((stream == stdout || stream == stderr) && !HasConsole()) {
    char buffer[4096];
    VSNPrintF(buffer, sizeof(buffer), format, args);
    OutputDebugStringA(buffer);
  } else {
    vfprintf(stream, format, args);
  }
}

void DebugBreakNative() {
#if defined(_MSC_VER)
  __debugbreak();
#else
  ::DebugBreak();
#endif
}
#endif

void VPrintError(const char* format, va_list args) {
#if defined(_WIN32) && !defined(__CYGWIN__)
  VPrintHelper(stderr, format, args);
#elif defined(ANDROID) && !defined(V8_ANDROID_LOG_STDOUT)
  __android_log_vprint(ANDROID_LOG_ERROR, "v8", format, args);
#else
  vfprintf(stderr, format, args);
#endif
}

void PrintError(const char* format, ...) {
  va_list args;
  va_start(args, format);
  VPrintError(format, args);
  va_end(args);
  fflush(stderr);
}

void DefaultDcheckHandler(const char* file, int line, const char* message) {
#ifdef DEBUG
  pi_v8_base_fatal(file, line, "Debug check failed: %s.", message);
#else
  // The original release entry exists for unit tests, including official mode.
  pi_v8_base_fatal("Debug check failed: %s.", message);
#endif
}

// The markers enclose the actual 512-byte stack message. Its address is printed
// below, as in logging.cc, to force stack allocation for the crash processor.
class FailureMessage {
 public:
  explicit FailureMessage(const char* format, va_list arguments) {
    memset(&message_, 0, sizeof(message_));
    VSNPrintF(&message_[0], sizeof(message_), format, arguments);
  }

  static const uintptr_t kStartMarker = 0xdecade10;
  static const uintptr_t kEndMarker = 0xdecade11;
  static const int kMessageBufferSize = 512;

  uintptr_t start_marker_ = kStartMarker;
  char message_[kMessageBufferSize];
  uintptr_t end_marker_ = kEndMarker;
};

static_assert(offsetof(FailureMessage, start_marker_) == 0);
static_assert(offsetof(FailureMessage, message_) == sizeof(uintptr_t));
static_assert(offsetof(FailureMessage, end_marker_) == sizeof(uintptr_t) + 512);
static_assert(sizeof(FailureMessage) == 2 * sizeof(uintptr_t) + 512);

}  // namespace

extern "C" void pi_v8_base_set_print_stack_trace(
    pi_v8_base_print_stack_trace_function print_stack_trace) {
  g_print_stack_trace = print_stack_trace;
}

extern "C" void pi_v8_base_set_dcheck_function(
    pi_v8_base_dcheck_function dcheck_function) {
  g_dcheck_function = dcheck_function ? dcheck_function : &DefaultDcheckHandler;
}

extern "C" void pi_v8_base_set_fatal_function(
    pi_v8_base_fatal_function fatal_function) {
  g_fatal_function = fatal_function;
}

extern "C" void pi_v8_base_abort(void) {
#if defined(_WIN32) && !defined(__CYGWIN__)
  if (IsDebuggerPresent()) {
    DebugBreakNative();
  }
  fflush(stdout);
  fflush(stderr);

  switch (pi_v8_base_g_abort_mode) {
    case PI_V8_BASE_EXIT_WITH_SUCCESS_AND_IGNORE_DCHECK_FAILURES:
      ExitProcess(0);
    case PI_V8_BASE_EXIT_WITH_FAILURE_AND_IGNORE_DCHECK_FAILURES:
      ExitProcess(-1);
    case PI_V8_BASE_IMMEDIATE_CRASH_MODE:
      PI_V8_BASE_IMMEDIATE_CRASH();
    case PI_V8_BASE_DEFAULT_ABORT_MODE:
      break;
  }
  ExitProcess(3);
#else
  switch (pi_v8_base_g_abort_mode) {
    case PI_V8_BASE_EXIT_WITH_SUCCESS_AND_IGNORE_DCHECK_FAILURES:
      _exit(0);
    case PI_V8_BASE_EXIT_WITH_FAILURE_AND_IGNORE_DCHECK_FAILURES:
      _exit(-1);
    case PI_V8_BASE_IMMEDIATE_CRASH_MODE:
      PI_V8_BASE_IMMEDIATE_CRASH();
    case PI_V8_BASE_DEFAULT_ABORT_MODE:
      break;
  }
  abort();
#endif
}

extern "C" void pi_v8_base_fatal_oom(
    pi_v8_base_oom_type type, const char* msg) {
  const char* type_str =
      type == PI_V8_BASE_OOM_PROCESS ? "process" : "JavaScript";
  PrintError("\n\n#\n# Fatal %s out of memory: %s\n#", type_str, msg);

  if (g_print_stack_trace) g_print_stack_trace();
  fflush(stderr);

#ifdef V8_FUZZILLI
  _exit(1);
#else
  pi_v8_base_abort();
#endif
}

#ifdef DEBUG
extern "C" void pi_v8_base_fatal(
    const char* file, int line, const char* format, ...) {
#else
extern "C" void pi_v8_base_fatal(const char* format, ...) {
  const char* file = "";
  int line = 0;
#endif
  va_list arguments;
  va_start(arguments, format);
  FailureMessage message(format, arguments);
  va_end(arguments);

  if (g_fatal_function != nullptr) {
    g_fatal_function(file, line, message.message_);
  }

  fflush(stdout);
  fflush(stderr);

  if (ControlledCrashesAreHarmless()) {
    PrintError(
        "\n\n#\n# Safely terminating process due to error in %s, line %d\n# ",
        file, line);
    PrintError("The following harmless error was encountered: ");
  } else {
    PrintError("\n\n#\n# Fatal error in %s, line %d\n# ", file, line);
  }

  // Start a fresh va_list for the complete native output path; the callback
  // receives only the separately formatted stack buffer above.
  va_start(arguments, format);
  VPrintError(format, arguments);
  va_end(arguments);

  PrintError("\n#\n#\n#\n#FailureMessage Object: %p", &message);

  if (g_print_stack_trace) g_print_stack_trace();

  fflush(stderr);
  pi_v8_base_abort();
}

extern "C" void pi_v8_base_dcheck(
    const char* file, int line, const char* message) {
  if (DcheckFailuresAreIgnored()) {
    PrintError("# Ignoring debug check failure in %s, line %d: %s\n",
               file, line, message);
    return;
  }

  g_dcheck_function(file, line, message);
}
