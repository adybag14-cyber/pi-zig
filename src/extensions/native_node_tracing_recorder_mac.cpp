// Copyright 2020 the V8 project authors. All rights reserved.
// BSD-style license retained with the exact recorder-mac.cc authority.
#include "native_node_tracing_recorder.hpp"

#ifndef __APPLE__
#error "select the original Darwin Recorder only for Darwin"
#endif
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability"

namespace pi_node::tracing {

Recorder::Recorder() { v8Provider = os_log_create("v8", ""); }
Recorder::~Recorder() {}

bool Recorder::IsEnabled() {
  return os_log_type_enabled(v8Provider, OS_LOG_TYPE_DEFAULT);
}
bool Recorder::IsEnabled(const uint8_t level) {
  if (level == OS_LOG_TYPE_DEFAULT || level == OS_LOG_TYPE_INFO ||
      level == OS_LOG_TYPE_DEBUG || level == OS_LOG_TYPE_ERROR ||
      level == OS_LOG_TYPE_FAULT) {
    return os_log_type_enabled(v8Provider, static_cast<os_log_type_t>(level));
  }
  return false;
}

void Recorder::AddEvent(TraceObject* trace_event) {
  os_signpost_event_emit(v8Provider, OS_SIGNPOST_ID_EXCLUSIVE, "",
                         "%s, cpu_duration: %d", trace_event->name(),
                         static_cast<int>(trace_event->cpu_duration()));
}

}  // namespace pi_node::tracing
#pragma clang diagnostic pop
