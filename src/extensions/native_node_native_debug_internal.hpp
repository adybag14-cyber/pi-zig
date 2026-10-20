// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
// Exact selected EnabledDebugList parsing and SPrintF instantiations.
// This internal formatter is instantiated only with the two original
// Permission format literals and string/string-view operands.
#ifndef PI_NATIVE_NODE_DEBUG_INTERNAL_HPP
#define PI_NATIVE_NODE_DEBUG_INTERNAL_HPP
#include "native_node_native_debug.h"
#include "native_node_environment_paths_internal.hpp"
#include "native_node_check_failure.h"
#include <cstdio>
#include <cstdlib>
#include <iterator>
#include <locale>
#include <new>
#include <string_view>
#include <type_traits>
#include <utility>
#include <vector>

#define PI_NODE_DEBUG_NON_CRYPTO(V)                                \
  V(NONE)                                                                      \
  V(DIRHANDLE)                                                                 \
  V(DNSCHANNEL)                                                                \
  V(ELDHISTOGRAM)                                                              \
  V(FILEHANDLE)                                                                \
  V(FILEHANDLECLOSEREQ)                                                        \
  V(BLOBREADER)                                                                \
  V(FSEVENTWRAP)                                                               \
  V(FSREQCALLBACK)                                                             \
  V(FSREQPROMISE)                                                              \
  V(GETADDRINFOREQWRAP)                                                        \
  V(GETNAMEINFOREQWRAP)                                                        \
  V(HEAPSNAPSHOT)                                                              \
  V(HTTP2SESSION)                                                              \
  V(HTTP2STREAM)                                                               \
  V(HTTP2PING)                                                                 \
  V(HTTP2SETTINGS)                                                             \
  V(HTTPINCOMINGMESSAGE)                                                       \
  V(HTTPCLIENTREQUEST)                                                         \
  V(LOCKS)                                                                     \
  V(JSSTREAM)                                                                  \
  V(JSUDPWRAP)                                                                 \
  V(MESSAGEPORT)                                                               \
  V(PIPECONNECTWRAP)                                                           \
  V(PIPESERVERWRAP)                                                            \
  V(PIPEWRAP)                                                                  \
  V(PROCESSWRAP)                                                               \
  V(PROMISE)                                                                   \
  V(QUERYWRAP)                                                                 \
  V(QUIC_ENDPOINT)                                                             \
  V(QUIC_LOGSTREAM)                                                            \
  V(QUIC_PACKET)                                                               \
  V(QUIC_SESSION)                                                              \
  V(QUIC_STREAM)                                                               \
  V(QUIC_UDP)                                                                  \
  V(SHUTDOWNWRAP)                                                              \
  V(SIGNALWRAP)                                                                \
  V(STATWATCHER)                                                               \
  V(STREAMPIPE)                                                                \
  V(TCPCONNECTWRAP)                                                            \
  V(TCPSERVERWRAP)                                                             \
  V(TCPWRAP)                                                                   \
  V(TTYWRAP)                                                                   \
  V(UDPSENDWRAP)                                                               \
  V(UDPWRAP)                                                                   \
  V(SIGINTWATCHDOG)                                                            \
  V(WORKER)                                                                    \
  V(WORKERCPUPROFILE)                                                          \
  V(WORKERCPUUSAGE)                                                            \
  V(WORKERHEAPPROFILE)                                                         \
  V(WORKERHEAPSNAPSHOT)                                                        \
  V(WORKERHEAPSTATISTICS)                                                      \
  V(WRITEWRAP)                                                                 \
  V(ZLIB)

#define PI_NODE_DEBUG_CRYPTO(V)                                    \
  V(CHECKPRIMEREQUEST)                                                         \
  V(PBKDF2REQUEST)                                                             \
  V(KEYPAIRGENREQUEST)                                                         \
  V(KEYGENREQUEST)                                                             \
  V(KEYEXPORTREQUEST)                                                          \
  V(ARGON2REQUEST)                                                             \
  V(CIPHERREQUEST)                                                             \
  V(DERIVEBITSREQUEST)                                                         \
  V(HASHREQUEST)                                                               \
  V(RANDOMBYTESREQUEST)                                                        \
  V(RANDOMPRIMEREQUEST)                                                        \
  V(SCRYPTREQUEST)                                                             \
  V(SIGNREQUEST)                                                               \
  V(TLSWRAP)                                                                   \
  V(VERIFYREQUEST)

#define PI_NODE_DEBUG_EXTRA(V) \
  V(CRYPTO)                                                                    \
  V(COMPILE_CACHE)                                                             \
  V(DIAGNOSTICS)                                                               \
  V(HUGEPAGES)                                                                 \
  V(INSPECTOR_SERVER)                                                          \
  V(INSPECTOR_CLIENT)                                                          \
  V(INSPECTOR_PROFILER)                                                        \
  V(CODE_CACHE)                                                                \
  V(NGTCP2_DEBUG)                                                              \
  V(SEA)                                                                       \
  V(WASI)                                                                      \
  V(MODULE)                                                                    \
  V(MKSNAPSHOT)                                                                \
  V(SNAPSHOT_SERDES)                                                           \
  V(PERMISSION_MODEL)                                                          \
  V(PLATFORM_MINIMAL)                                                          \
  V(PLATFORM_VERBOSE)                                                          \
  V(QUIC)

namespace pi_node::debug {
#define V(name) +1
inline constexpr size_t non_crypto_count = 0 PI_NODE_DEBUG_NON_CRYPTO(V);
inline constexpr size_t crypto_count = 0 PI_NODE_DEBUG_CRYPTO(V);
inline constexpr size_t extra_count = 0 PI_NODE_DEBUG_EXTRA(V);
#undef V
enum class ExtraCategory : size_t {
#define V(name) name,
  PI_NODE_DEBUG_EXTRA(V)
#undef V
};
inline char ToLower(char c) {
  return std::tolower(c, std::locale::classic());
}
inline char ToUpper(char c) {
  return std::toupper(c, std::locale::classic());
}
template<typename T>
EnvironmentString ToLower(const T& in) {
  auto it = std::cbegin(in);
  auto end = std::cend(in);
  EnvironmentString out(std::distance(it, end), 0);
  size_t i;
  for (i = 0; it != end; ++it, ++i) out[i] = ToLower(*it);
  return out;
}
template<typename T>
EnvironmentString ToUpper(const T& in) {
  auto it = std::cbegin(in);
  auto end = std::cend(in);
  EnvironmentString out(std::distance(it, end), 0);
  size_t i;
  for (i = 0; it != end; ++it, ++i) out[i] = ToUpper(*it);
  return out;
}
inline void Check(JSContext* context, bool condition, const char* expression,
                  const char* location, const char* function) {
  if (condition) return;
  const PiNodeAssertionInfo info = {location, expression, function};
  pi_node_assert_failure(context, &info);
  std::abort();
}

template<bool HaveOpenSSL>
class EnabledDebugList {
 public:
  static constexpr size_t category_count =
      non_crypto_count + (HaveOpenSSL ? crypto_count : 0) + extra_count;
  static constexpr size_t permission_category =
      non_crypto_count + (HaveOpenSSL ? crypto_count : 0) +
      static_cast<size_t>(ExtraCategory::PERMISSION_MODEL);
  bool enabled(size_t category) const { return enabled_[category]; }
  void Parse(const EnvironmentPathAccess* env) {
    EnvironmentString cats;
    SafeGetenv("NODE_DEBUG_NATIVE", &cats, env);
    Parse(cats);
  }
  void Parse(const EnvironmentString& cats) {
    EnvironmentString debug_categories = cats;
    while (!debug_categories.empty()) {
      EnvironmentString::size_type comma_pos = debug_categories.find(',');
      EnvironmentString wanted = ToLower(debug_categories.substr(0, comma_pos));
      size_t category = 0;
#define V(name)                                                               \
      {                                                                       \
        static const EnvironmentString available_category = ToLower(#name);    \
        if (available_category.find(wanted) != EnvironmentString::npos)        \
          enabled_[category] = true;                                          \
        ++category;                                                           \
      }
      PI_NODE_DEBUG_NON_CRYPTO(V)
      if constexpr (HaveOpenSSL) { PI_NODE_DEBUG_CRYPTO(V) }
      PI_NODE_DEBUG_EXTRA(V)
#undef V
      if (comma_pos == EnvironmentString::npos) break;
      debug_categories = debug_categories.substr(comma_pos + 1);
    }
  }
 private:
  bool enabled_[category_count] = {false};
};

// The C call view borrows the existing original String span. Its sole
// conversion below performs the original ToStringHelper String copy, without
// manufacturing an extra owning input String before SPrintF's ret local.
struct SizedString {
  const char* data;
  size_t length;
};
struct ToStringHelper {
  static EnvironmentString Convert(const SizedString& value) {
    return EnvironmentString(value.data, value.length);
  }
  static EnvironmentString Convert(const EnvironmentString& value) {
    return value;
  }
  static std::string_view Convert(const char* value) {
    return value != nullptr ? value : "(null)";
  }
  static std::string_view Convert(std::string_view value) { return value; }
  template<unsigned BASE_BITS, typename T>
  static auto BaseConvert(T&& value) {
    return Convert(std::forward<T>(value));
  }
};
template<typename T>
auto ToStringOrStringView(const T& value) {
  return ToStringHelper::Convert(value);
}
template<unsigned BASE_BITS, typename T>
auto ToBaseString(const T& value) {
  return ToStringHelper::BaseConvert<BASE_BITS>(value);
}

inline EnvironmentString SPrintFImpl(JSContext* context,
                                    std::string_view format) {
  auto offset = format.find('%');
  if (offset == std::string_view::npos) return EnvironmentString(format);
  Check(context, offset + 1 < format.size(), "(offset + 1) < (format.size())",
        "../src/debug_utils-inl.h:106", "node::SPrintFImpl");
  Check(context, format[offset + 1] == '%', "(format[offset + 1]) == ('%')",
        "../src/debug_utils-inl.h:107", "node::SPrintFImpl");
  return EnvironmentString(format.substr(0, offset + 1)) +
         SPrintFImpl(context, format.substr(offset + 2));
}
template<typename Arg, typename... Args>
EnvironmentString SPrintFImpl(JSContext* context, std::string_view format,
                             Arg&& arg, Args&&... args) {
  auto offset = format.find('%');
  Check(context, offset != std::string_view::npos,
        "(offset) != (std::string_view::npos)",
        "../src/debug_utils-inl.h:120", "node::SPrintFImpl");
  EnvironmentString ret(format.substr(0, offset));
  while (++offset < format.size() &&
         (format[offset] == 'l' || format[offset] == 'z')) {
  }
  switch (offset == format.size() ? '\0' : format[offset]) {
    case '%': {
      return ret + '%' +
             SPrintFImpl(context, format.substr(offset + 1),
                         std::forward<Arg>(arg),
                         std::forward<Args>(args)...);
    }
    default: {
      return ret + '%' +
             SPrintFImpl(context, format.substr(offset),
                         std::forward<Arg>(arg),
                         std::forward<Args>(args)...);
    }
    case 'd':
    case 'i':
    case 'u':
    case 's':
      ret += ToStringOrStringView(arg);
      break;
    case 'o':
      ret += ToBaseString<3>(arg);
      break;
    case 'x':
      ret += ToBaseString<4>(arg);
      break;
    case 'X':
      ret += ToUpper(ToBaseString<4>(arg));
      break;
    case 'p': {
      Check(context,
            std::is_pointer_v<typename std::remove_reference_t<Arg>>,
            "std::is_pointer_v<typename std::remove_reference_t<Arg>>",
            "../src/debug_utils-inl.h:156", "node::SPrintFImpl");
      char out[20];
      int n = snprintf(
          out, sizeof(out), "%p", *reinterpret_cast<const void* const*>(&arg));
      Check(context, n >= 0, "(n) >= (0)", "../src/debug_utils-inl.h:160",
            "node::SPrintFImpl");
      ret += out;
      break;
    }
  }
  return ret +
         SPrintFImpl(context, format.substr(offset + 1),
                     std::forward<Args>(args)...);
}
template<typename... Args>
EnvironmentString SPrintF(JSContext* context, std::string_view format,
                         Args&&... args) {
  return SPrintFImpl(context, format, std::forward<Args>(args)...);
}
void FWrite(FILE* file, const EnvironmentString& str);
template<typename... Args>
void FPrintF(JSContext* context, FILE* file, std::string_view format,
             Args&&... args) {
  FWrite(file, SPrintF(context, format, std::forward<Args>(args)...));
}
}  // namespace pi_node::debug
#endif
