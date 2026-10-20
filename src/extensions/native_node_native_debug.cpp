// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
// Native Debug state and the actual selected Permission formatting/output.
// No guest property, process.env wrapper or category-tracing substitute.
#include "native_node_native_debug_internal.hpp"
#include "uv.h"
#if defined(_WIN32)
#include <windows.h>
#include <io.h>
#elif !defined(__linux__)
#error "the selected native Debug owner is admitted on Windows/Linux"
#endif
namespace pi_node::debug {
void FWrite(FILE* file, const EnvironmentString& str) {
  auto simple_fwrite = [&]() {
    // The return value is ignored because there's no good way to handle it.
    fwrite(str.data(), str.size(), 1, file);
  };

  if (file != stderr && file != stdout) {
    simple_fwrite();
    return;
  }
#ifdef _WIN32
  HANDLE handle =
      GetStdHandle(file == stdout ? STD_OUTPUT_HANDLE : STD_ERROR_HANDLE);

  // Check if stderr is something other than a tty/console
  if (handle == INVALID_HANDLE_VALUE || handle == nullptr ||
      uv_guess_handle(_fileno(file)) != UV_TTY) {
    simple_fwrite();
    return;
  }

  // Get required wide buffer size
  int n = MultiByteToWideChar(CP_UTF8, 0, str.data(), str.size(), nullptr, 0);

  std::vector<wchar_t, Allocator<wchar_t>> wbuf(n);
  MultiByteToWideChar(CP_UTF8, 0, str.data(), str.size(), wbuf.data(), n);

  WriteConsoleW(handle, wbuf.data(), n, nullptr, nullptr);
  return;
#elif defined(__ANDROID__)
  if (file == stderr) {
    __android_log_print(ANDROID_LOG_ERROR, "nodejs", "%s", str.data());
    return;
  }
#endif
  simple_fwrite();
}

}  // namespace pi_node::debug

struct PiNodeNativeDebugList {
  using Plain = pi_node::debug::EnabledDebugList<false>;
  using Crypto = pi_node::debug::EnabledDebugList<true>;
  bool have_openssl;
  union Contents {
    Plain plain;
    Crypto crypto;
    Contents() {}
    ~Contents() {}
  } contents;
  explicit PiNodeNativeDebugList(bool crypto) : have_openssl(crypto) {
    if (have_openssl) ::new (&contents.crypto) Crypto();
    else ::new (&contents.plain) Plain();
  }
  ~PiNodeNativeDebugList() {
    if (have_openssl) contents.crypto.~Crypto();
    else contents.plain.~Plain();
  }
  size_t count() const noexcept {
    return have_openssl ? Crypto::category_count : Plain::category_count;
  }
  bool enabled(size_t category) const noexcept {
    return have_openssl ? contents.crypto.enabled(category)
                        : contents.plain.enabled(category);
  }
  bool permission_enabled() const noexcept {
    return enabled(have_openssl ? Crypto::permission_category
                               : Plain::permission_category);
  }
  template<typename T>
  void parse(const T& value) {
    if (have_openssl) contents.crypto.Parse(value);
    else contents.plain.Parse(value);
  }
};
namespace {
alignas(PiNodeNativeDebugList)
unsigned char process_debug_storage[sizeof(PiNodeNativeDebugList)];
PiNodeNativeDebugList* process_debug_list = nullptr;

int PermissionEnabled(void* user) {
  auto* call = static_cast<PiNodeNativeDebugCall*>(user);
  return call->list->permission_enabled();
}
void PermissionInsert(void* user, const char* bytes, size_t length) {
  auto* call = static_cast<PiNodeNativeDebugCall*>(user);
  pi_node::AllocationScope scope(call->memory_owner);
  pi_node::debug::FPrintF(call->context, stderr, "Inserting %s\n",
                        pi_node::debug::SizedString{bytes, length});
}
void PermissionTreeLine(void* user, const char* indent, const char* prefix) {
  auto* call = static_cast<PiNodeNativeDebugCall*>(user);
  pi_node::AllocationScope scope(call->memory_owner);
  pi_node::debug::FPrintF(call->context, stderr, "%s%s\n", indent, prefix);
}
}  // namespace
extern "C" size_t pi_node_native_debug_storage_size(void) noexcept {
  return sizeof(PiNodeNativeDebugList);
}
extern "C" size_t pi_node_native_debug_storage_alignment(void) noexcept {
  return alignof(PiNodeNativeDebugList);
}
extern "C" PiNodeNativeDebugList* pi_node_native_debug_construct(
    void* storage, int have_openssl) noexcept {
  return ::new (storage) PiNodeNativeDebugList(have_openssl != 0);
}
extern "C" void pi_node_native_debug_destroy(
    PiNodeNativeDebugList* list) noexcept {
  list->~PiNodeNativeDebugList();
}
extern "C" size_t pi_node_native_debug_category_count(
    const PiNodeNativeDebugList* list) noexcept {
  return list->count();
}
extern "C" const char* pi_node_native_debug_category_name(
    const PiNodeNativeDebugList* list, size_t category) noexcept {
#define V(name) #name,
  static constexpr const char* non_crypto[] = {
    PI_NODE_DEBUG_NON_CRYPTO(V)
  };
  static constexpr const char* crypto[] = { PI_NODE_DEBUG_CRYPTO(V) };
  static constexpr const char* extra[] = { PI_NODE_DEBUG_EXTRA(V) };
#undef V
  if (category < pi_node::debug::non_crypto_count) return non_crypto[category];
  category -= pi_node::debug::non_crypto_count;
  if (list->have_openssl) {
    if (category < pi_node::debug::crypto_count) return crypto[category];
    category -= pi_node::debug::crypto_count;
  }
  return extra[category];
}
extern "C" int pi_node_native_debug_enabled(
    const PiNodeNativeDebugList* list, size_t category) noexcept {
  return list->enabled(category);
}
extern "C" int pi_node_native_debug_permission_enabled(
    const PiNodeNativeDebugList* list) noexcept {
  return list->permission_enabled();
}
extern "C" void pi_node_native_debug_parse_text(
    PiNodeNativeDebugList* list, void* memory_owner,
    const char* cats, size_t length) noexcept {
  pi_node::AllocationScope scope(memory_owner);
  pi_node::EnvironmentString input(cats, length);
  list->parse(input);
}
extern "C" void pi_node_native_debug_parse_environment(
    PiNodeNativeDebugList* list, void* memory_owner,
    const PiNodePermissionEnvironment* environment) noexcept {
  pi_node::AllocationScope scope(memory_owner);
  const pi_node::EnvironmentPathAccess env{
      environment->paths, environment->map,
      environment->context, environment->trace};
  list->parse(&env);
}
extern "C" PiNodeNativeDebugList* pi_node_process_debug_select(
    int have_openssl, JSContext* context) noexcept {
  const bool feature = have_openssl != 0;
  if (process_debug_list == nullptr) {
    process_debug_list =
        ::new (process_debug_storage) PiNodeNativeDebugList(feature);
  } else {
    pi_node::debug::Check(
        context, process_debug_list->have_openssl == feature,
        "process_debug_list->have_openssl == feature",
        "native_node_native_debug.cpp", "pi_node_process_debug_select");
  }
  return process_debug_list;
}
extern "C" void pi_node_native_debug_bind_permission(
    PiNodeNativeDebugCall* call, PiNodePermissionDebug* operations,
    PiNodeNativeDebugList* list, void* memory_owner,
    JSContext* context) noexcept {
  *call = {list, memory_owner, context};
  *operations = {PermissionEnabled, PermissionInsert, PermissionTreeLine, call};
}
