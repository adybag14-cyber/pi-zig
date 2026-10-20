// Copyright Joyent, Inc. and other Node contributors.
// Node's MIT license and complete debug_utils.h/.cc originals are retained in
// verification/native-node-tracing-platform-sourceonly-20261020/authority/.
// Selected CheckedUvLoopClose, handle-walk and native symbol-context owners.
// This unit uses the shared Node assertion/TLS owner; it defines no fatal hook.
#include "native_node_tracing_support.hpp"
#include "native_node_tracing_core.hpp"

#include <cstdio>
#include <memory>
#include <tuple>
#include <utility>

#ifndef _WIN32
#if defined(__linux__)
#include <features.h>
#endif
#if defined(__linux__) && !defined(__GLIBC__) || \
    defined(__UCLIBC__) || defined(_AIX)
#define PI_TRACE_HAVE_EXECINFO_H 0
#else
#define PI_TRACE_HAVE_EXECINFO_H 1
#endif
#if PI_TRACE_HAVE_EXECINFO_H
#include <cxxabi.h>
#include <dlfcn.h>
#include <execinfo.h>
#include <unistd.h>
#include <sys/mman.h>
#endif
#else
#include <Windows.h>
#include <dbghelp.h>
#include <tchar.h>
#endif

namespace pi_node::tracing {
namespace {

// NativeAllocated and String retain the admitted native allocation owner.
// No engine pointer or JS value belongs to this temporary native context.
class NativeSymbolDebuggingContext : public NativeAllocated {
 public:
  static std::unique_ptr<NativeSymbolDebuggingContext> New();

  class SymbolInfo {
   public:
    String name;
    String filename;
    size_t line = 0;
    size_t dis = 0;

    String Display() const;
  };

  NativeSymbolDebuggingContext() = default;
  virtual ~NativeSymbolDebuggingContext() = default;
  virtual SymbolInfo LookupSymbol(void* address) { return {}; }
  virtual bool IsMapped(void* address) { return false; }
  virtual int GetStackTrace(void** frames, int count) { return 0; }

  NativeSymbolDebuggingContext(const NativeSymbolDebuggingContext&) = delete;
  NativeSymbolDebuggingContext(NativeSymbolDebuggingContext&&) = delete;
  NativeSymbolDebuggingContext operator=(NativeSymbolDebuggingContext&) = delete;
  NativeSymbolDebuggingContext operator=(NativeSymbolDebuggingContext&&) = delete;
};

#ifndef _WIN32
#if PI_TRACE_HAVE_EXECINFO_H
class PosixSymbolDebuggingContext final : public NativeSymbolDebuggingContext {
 public:
  PosixSymbolDebuggingContext() : pagesize_(getpagesize()) {}

  SymbolInfo LookupSymbol(void* address) override {
    Dl_info info;
    const bool have_info = dladdr(address, &info);
    SymbolInfo ret;
    if (!have_info) return ret;

    if (info.dli_sname != nullptr) {
      if (char* demangled =
              abi::__cxa_demangle(info.dli_sname, nullptr, nullptr, nullptr)) {
        ret.name = demangled;
        free(demangled);
      } else {
        ret.name = info.dli_sname;
      }
    }
    if (info.dli_fname != nullptr) {
      ret.filename = info.dli_fname;
    }
    return ret;
  }

  bool IsMapped(void* address) override {
    void* page_aligned = reinterpret_cast<void*>(
        reinterpret_cast<uintptr_t>(address) & ~(pagesize_ - 1));
    return msync(page_aligned, pagesize_, MS_ASYNC) == 0;
  }

  int GetStackTrace(void** frames, int count) override {
    return backtrace(frames, count);
  }

 private:
  uintptr_t pagesize_;
};

std::unique_ptr<NativeSymbolDebuggingContext>
NativeSymbolDebuggingContext::New() {
  return std::make_unique<PosixSymbolDebuggingContext>();
}
#else
std::unique_ptr<NativeSymbolDebuggingContext>
NativeSymbolDebuggingContext::New() {
  return std::make_unique<NativeSymbolDebuggingContext>();
}
#endif
#else
class Win32SymbolDebuggingContext final : public NativeSymbolDebuggingContext {
 public:
  Win32SymbolDebuggingContext() {
    current_process_ = GetCurrentProcess();
    static_cast<void>(SymInitialize(current_process_, nullptr, true));
  }

  ~Win32SymbolDebuggingContext() override {
    static_cast<void>(SymCleanup(current_process_));
  }

  using NameAndDisplacement = std::pair<String, DWORD64>;
  NameAndDisplacement WrappedSymFromAddr(DWORD64 dwAddress) const {
    DWORD64 dwDisplacement = 0;
    char buffer[sizeof(SYMBOL_INFO) + MAX_SYM_NAME * sizeof(TCHAR)];
    const auto pSymbol = reinterpret_cast<PSYMBOL_INFO>(buffer);
    pSymbol->SizeOfStruct = sizeof(SYMBOL_INFO);
    pSymbol->MaxNameLen = MAX_SYM_NAME;

    if (SymFromAddr(current_process_, dwAddress, &dwDisplacement, pSymbol)) {
      return NameAndDisplacement(pSymbol->Name, dwDisplacement);
    } else {
#ifdef DEBUG
      const DWORD error = GetLastError();
      fprintf(stderr, "SymFromAddr returned error : %lu\n", error);
#else
      static_cast<void>(GetLastError());
#endif
    }
    return NameAndDisplacement();
  }

  SymbolInfo WrappedGetLine(DWORD64 dwAddress) const {
    SymbolInfo sym{};
    DWORD dwDisplacement;
    IMAGEHLP_LINE64 line;
    SymSetOptions(SYMOPT_LOAD_LINES);
    line.SizeOfStruct = sizeof(IMAGEHLP_LINE64);

    if (SymGetLineFromAddr64(current_process_, dwAddress,
                             &dwDisplacement, &line)) {
      sym.filename = line.FileName;
      sym.line = line.LineNumber;
    } else {
#ifdef DEBUG
      const DWORD error = GetLastError();
      fprintf(stderr, "SymGetLineFromAddr64 returned error : %lu\n", error);
#else
      static_cast<void>(GetLastError());
#endif
    }
    return sym;
  }

  String WrappedUnDecorateSymbolName(const char* name) const {
    char szUndName[MAX_SYM_NAME];
    if (UnDecorateSymbolName(name, szUndName, sizeof(szUndName),
                             UNDNAME_COMPLETE)) {
      return szUndName;
    } else {
#ifdef DEBUG
      const DWORD error = GetLastError();
      fprintf(stderr, "UnDecorateSymbolName returned error %lu\n", error);
#else
      static_cast<void>(GetLastError());
#endif
    }
    return {};
  }

  SymbolInfo LookupSymbol(void* address) override {
    const DWORD64 dw_address = reinterpret_cast<DWORD64>(address);
    SymbolInfo ret = WrappedGetLine(dw_address);
    std::tie(ret.name, ret.dis) = WrappedSymFromAddr(dw_address);
    if (!ret.name.empty()) {
      ret.name = WrappedUnDecorateSymbolName(ret.name.c_str());
    }
    return ret;
  }

  bool IsMapped(void* address) override {
    MEMORY_BASIC_INFORMATION info;
    if (VirtualQuery(address, &info, sizeof(info)) != sizeof(info)) return false;
    return info.State == MEM_COMMIT && info.Protect != 0;
  }

  int GetStackTrace(void** frames, int count) override {
    return CaptureStackBackTrace(0, count, frames, nullptr);
  }

  Win32SymbolDebuggingContext(const Win32SymbolDebuggingContext&) = delete;
  Win32SymbolDebuggingContext(Win32SymbolDebuggingContext&&) = delete;
  Win32SymbolDebuggingContext operator=(const Win32SymbolDebuggingContext&) = delete;
  Win32SymbolDebuggingContext operator=(Win32SymbolDebuggingContext&&) = delete;

 private:
  HANDLE current_process_;
};

std::unique_ptr<NativeSymbolDebuggingContext>
NativeSymbolDebuggingContext::New() {
  return std::unique_ptr<NativeSymbolDebuggingContext>(
      new Win32SymbolDebuggingContext());
}
#endif

String NativeSymbolDebuggingContext::SymbolInfo::Display() const {
  OutputStringStream oss;
  oss << name;
  if (dis != 0) {
    oss << "+" << dis;
  }
  if (!filename.empty()) {
    oss << " [" << filename << ']';
  }
  if (line != 0) {
    oss << ":L" << line;
  }
  return oss.str();
}

void PrintLibuvHandleInformation(uv_loop_t* loop, FILE* stream) {
  struct Info {
    std::unique_ptr<NativeSymbolDebuggingContext> ctx;
    FILE* stream;
    size_t num_handles;
  };

  Info info{NativeSymbolDebuggingContext::New(), stream, 0};
  fprintf(stream, "uv loop at [%p] has open handles:\n", loop);

  uv_walk(loop, [](uv_handle_t* handle, void* arg) {
    Info* info = static_cast<Info*>(arg);
    NativeSymbolDebuggingContext* sym_ctx = info->ctx.get();
    FILE* stream = info->stream;
    info->num_handles++;

    fprintf(stream, "[%p] %s%s\n", handle, uv_handle_type_name(handle->type),
            uv_is_active(handle) ? " (active)" : "");
    void* close_cb = reinterpret_cast<void*>(handle->close_cb);
    fprintf(stream, "\tClose callback: %p %s\n",
            close_cb, sym_ctx->LookupSymbol(close_cb).Display().c_str());
    fprintf(stream, "\tData: %p %s\n",
            handle->data, sym_ctx->LookupSymbol(handle->data).Display().c_str());

    void* first_field = nullptr;
    if (sym_ctx->IsMapped(handle->data))
      first_field = *reinterpret_cast<void**>(handle->data);
    if (first_field != nullptr) {
      fprintf(stream, "\t(First field): %p %s\n",
              first_field, sym_ctx->LookupSymbol(first_field).Display().c_str());
    }
  }, &info);

  fprintf(stream, "uv loop at [%p] has %zu open handles in total\n",
          loop, info.num_handles);
}

}  // namespace

void CheckedUvLoopClose(uv_loop_t* loop) {
  if (uv_loop_close(loop) == 0) return;
  PrintLibuvHandleInformation(loop, stderr);
  fflush(stderr);
  PI_NODE_TRACE_ERROR_AND_ABORT(
      "Unreachable code reached" ": " "uv_loop_close() while having open handles");
}

}  // namespace pi_node::tracing
#undef PI_TRACE_HAVE_EXECINFO_H
