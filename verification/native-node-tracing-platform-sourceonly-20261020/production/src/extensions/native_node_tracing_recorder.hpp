// Copyright 2020 the V8 project authors. All rights reserved.
// BSD-style license retained with the pinned recorder and trace-writer sources.
#ifndef PI_NATIVE_NODE_TRACING_RECORDER_HPP
#define PI_NATIVE_NODE_TRACING_RECORDER_HPP
#include "native_node_tracing_core.hpp"
#include <cstdint>
#include <memory>

#if defined(__APPLE__)
#include <os/signpost.h>
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability"
#endif

#if !defined(V8_ENABLE_SYSTEM_INSTRUMENTATION)
#error "only include this file if V8_ENABLE_SYSTEM_INSTRUMENTATION"
#endif
#if !defined(_WIN32) && !defined(__APPLE__)
#error "the original Recorder has only Windows and Darwin implementations"
#endif
#if defined(V8_USE_PERFETTO)
#error "the selected native tracing owner is the original non-Perfetto path"
#endif

namespace pi_node::tracing {

class Recorder : public NativeAllocated {
 public:
  Recorder();
  ~Recorder();

  bool IsEnabled();
  bool IsEnabled(const uint8_t level);
  void AddEvent(TraceObject* trace_event);

 private:
#if defined(__APPLE__)
  os_log_t v8Provider;
#endif
};

class SystemInstrumentationTraceWriter : public TraceWriter {
 public:
  SystemInstrumentationTraceWriter();
  ~SystemInstrumentationTraceWriter() override;
  void AppendTraceEvent(TraceObject* trace_event) override;
  void Flush() override;

 private:
  std::unique_ptr<Recorder> recorder_;
};

}  // namespace pi_node::tracing

#if defined(__APPLE__)
#pragma clang diagnostic pop
#endif
#endif
