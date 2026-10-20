// Copyright 2016 the V8 project authors. All rights reserved.
// BSD-style license retained with the original trace-writer.h/.cc authority.
#include "native_node_tracing_recorder.hpp"

namespace pi_node::tracing {

SystemInstrumentationTraceWriter::SystemInstrumentationTraceWriter() {
  recorder_ = std::make_unique<Recorder>();
}

SystemInstrumentationTraceWriter::~SystemInstrumentationTraceWriter() {
  recorder_.reset(nullptr);
}

void SystemInstrumentationTraceWriter::AppendTraceEvent(
    TraceObject* trace_event) {
  if (recorder_->IsEnabled()) {
    recorder_->AddEvent(trace_event);
  }
}

void SystemInstrumentationTraceWriter::Flush() {}

TraceWriter* TraceWriter::CreateSystemInstrumentationTraceWriter() {
  return new SystemInstrumentationTraceWriter();
}

}  // namespace pi_node::tracing
