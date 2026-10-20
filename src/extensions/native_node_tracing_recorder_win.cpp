// Copyright 2020 the V8 project authors. All rights reserved.
// BSD-style license retained with the exact recorder-win.cc authority.
// etw-provider-win.h is the byte-exact original V8 provider declaration.
#include "etw-provider-win.h"
#include "native_node_tracing_recorder.hpp"
#include "native_node_tracing_controller.hpp"

#ifndef _WIN32
#error "select the original Windows Recorder only for Windows"
#endif

namespace pi_node::tracing {

V8_DECLARE_TRACELOGGING_PROVIDER(g_v8LibProvider);
V8_DEFINE_TRACELOGGING_PROVIDER(g_v8LibProvider);

Recorder::Recorder() { TraceLoggingRegister(g_v8LibProvider); }

Recorder::~Recorder() {
  if (g_v8LibProvider) {
    TraceLoggingUnregister(g_v8LibProvider);
  }
}

bool Recorder::IsEnabled() {
  return TraceLoggingProviderEnabled(g_v8LibProvider, 0, 0);
}

bool Recorder::IsEnabled(const uint8_t level) {
  return TraceLoggingProviderEnabled(g_v8LibProvider, level, 0);
}

void Recorder::AddEvent(TraceObject* trace_event) {
  wchar_t wName[4096];
  MultiByteToWideChar(CP_ACP, 0, trace_event->name(), -1, wName, 4096);
  wchar_t wCategoryGroupName[4096];
  MultiByteToWideChar(CP_ACP, 0,
                      TracingController::GetCategoryGroupName(
                          trace_event->category_enabled_flag()),
                      -1, wCategoryGroupName, 4096);

  TraceLoggingWrite(g_v8LibProvider, "", TraceLoggingValue(wName, "Event Name"),
                    TraceLoggingValue(trace_event->pid(), "pid"),
                    TraceLoggingValue(trace_event->tid(), "tid"),
                    TraceLoggingValue(trace_event->ts(), "ts"),
                    TraceLoggingValue(trace_event->tts(), "tts"),
                    TraceLoggingValue(trace_event->phase(), "phase"),
                    TraceLoggingValue(wCategoryGroupName, "category"),
                    TraceLoggingValue(trace_event->duration(), "dur"),
                    TraceLoggingValue(trace_event->cpu_duration(), "tdur"));
}

}  // namespace pi_node::tracing
