// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
// Node v24.13 native Environment/GetCwd/GetExecPath/PathResolve/SafeGetenv.
// Native input materialization and the later State embedding are explicit
// boundaries; this file does not install process.env or a permission policy.
#include "native_node_environment_paths_internal.hpp"
#include "native_node_options_environment.h"
#include "native_node_check_failure.h"
#include "uv.h"
#include <climits>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <iterator>
#include <locale>
#include <new>
#include <utility>
#if !defined(_WIN32) && !defined(__linux__)
#error "the selected native Environment path owner is admitted on Windows/Linux"
#endif
namespace {
using String = pi_node::EnvironmentString;
using Strings = std::vector<String, pi_node::Allocator<String>>;
#ifdef _WIN32
constexpr size_t kPathMaxBytes = MAX_PATH * 4;
#else
constexpr size_t kPathMaxBytes = PATH_MAX;
#endif
constexpr char kPathSeparator = std::filesystem::path::preferred_separator;

String GetExecPath(const Strings& argv) {
  char exec_path_buf[2 * PATH_MAX];
  size_t exec_path_len = sizeof(exec_path_buf);
  String exec_path;
  if (uv_exepath(exec_path_buf, &exec_path_len) == 0) {
    exec_path = String(exec_path_buf, exec_path_len);
  } else if (!argv.empty()) {
    exec_path = argv[0];
  }
  // The original OpenBSD-only realpath tail is outside the admitted platforms.
  return exec_path;
}
class RetainedMap {
 public:
  explicit RetainedMap(PiNodeEnvironmentMap* map) noexcept : map_(map) {
    pi_node_environment_map_retain(map_);
  }
  ~RetainedMap() noexcept { pi_node_environment_map_release(map_); }
  RetainedMap(const RetainedMap&) = delete;
  RetainedMap& operator=(const RetainedMap&) = delete;
 private:
  PiNodeEnvironmentMap* map_;
};
void TraceEnvVar(const pi_node::EnvironmentPathAccess* env,
                 const char* message, const char* key) {
  const PiNodeEnvironmentTrace options = *env->trace;
  if (options.print_message)
    std::fprintf(stderr, "[--trace-env] %s \"%s\"\n", message, key);
  if (options.print_native_stack) options.native_stack(options.user);
  if (options.print_js_stack) options.js_stack(options.user, env->context);
}
}  // namespace

struct PiNodeEnvironmentPaths {
  // Original Environment member order: argv_ is copied before GetExecPath.
  // This single placement object belongs to the later native State allocation.
  const Strings argv;
  const String exec_path;
  explicit PiNodeEnvironmentPaths(const Strings& args)
      : argv(args), exec_path(GetExecPath(args)) {}
};

namespace pi_node {
const EnvironmentString& EnvironmentPathAccess::exec_path() const noexcept {
  return paths->exec_path;
}
EnvironmentString EnvironmentPathAccess::GetCwd(
    const EnvironmentString& exec_path) const {
  char cwd[kPathMaxBytes];
  size_t size = kPathMaxBytes;
  if (uv_cwd(cwd, &size) == 0) {
    if (!(size > 0)) {
      const PiNodeAssertionInfo info = {
          "../src/env.cc:716", "(size) > (0)", "node::Environment::GetCwd"};
      pi_node_assert_failure(context, &info);
      std::abort();
    }
    return cwd;
  }
  return exec_path.substr(0, exec_path.find_last_of(kPathSeparator));
}
bool SafeGetenv(const char* key, EnvironmentString* text,
                const EnvironmentPathAccess* env) {
  if (!pi_node_options_environment_allowed()) return false;
  // The original local shared_ptr is acquired after credential admission and
  // stays alive through the actual optional, assignment, and TraceEnvVar.
  RetainedMap env_vars(env->map);
  std::optional<EnvironmentString> value = environmentMapGet(env->map, key);
  bool has_env = value.has_value();
  if (has_env) *text = value.value();
  TraceEnvVar(env, "get", key);
  return has_env;
}
#ifdef _WIN32
constexpr bool IsWindowsDeviceRoot(char c) noexcept;
char ToLower(char c) { return std::tolower(c, std::locale::classic()); }
template<typename T>
EnvironmentString ToLower(const T& in) {
  auto it = std::cbegin(in);
  auto end = std::cend(in);
  EnvironmentString out(std::distance(it, end), 0);
  size_t i;
  for (i = 0; it != end; ++it, ++i) out[i] = ToLower(*it);
  return out;
}
#endif

#ifdef _WIN32
constexpr bool IsPathSeparator(const char c) noexcept {
  return c == '\\' || c == '/';
}
#else   // POSIX
constexpr bool IsPathSeparator(const char c) noexcept {
  return c == '/';
}
#endif  // _WIN32

EnvironmentString NormalizeString(const std::string_view path,
                            bool allowAboveRoot,
                            const std::string_view separator) {
  EnvironmentString res;
  int lastSegmentLength = 0;
  int lastSlash = -1;
  int dots = 0;
  char code = 0;
  for (size_t i = 0; i <= path.size(); ++i) {
    if (i < path.size()) {
      code = path[i];
    } else if (IsPathSeparator(code)) {
      break;
    } else {
      code = '/';
    }

    if (IsPathSeparator(code)) {
      if (lastSlash == static_cast<int>(i - 1) || dots == 1) {
        // NOOP
      } else if (dots == 2) {
        int len = res.length();
        if (len < 2 || lastSegmentLength != 2 || res[len - 1] != '.' ||
            res[len - 2] != '.') {
          if (len > 2) {
            auto lastSlashIndex = res.find_last_of(separator);
            if (lastSlashIndex == EnvironmentString::npos) {
              res = "";
              lastSegmentLength = 0;
            } else {
              res = res.substr(0, lastSlashIndex);
              len = res.length();
              lastSegmentLength = len - 1 - res.find_last_of(separator);
            }
            lastSlash = i;
            dots = 0;
            continue;
          } else if (len != 0) {
            res = "";
            lastSegmentLength = 0;
            lastSlash = i;
            dots = 0;
            continue;
          }
        }

        if (allowAboveRoot) {
          res += res.length() > 0 ? EnvironmentString(separator) + ".." : "..";
          lastSegmentLength = 2;
        }
      } else {
        if (!res.empty()) {
          res += EnvironmentString(separator) +
                 EnvironmentString(path.substr(lastSlash + 1, i - (lastSlash + 1)));
        } else {
          res = path.substr(lastSlash + 1, i - (lastSlash + 1));
        }
        lastSegmentLength = i - lastSlash - 1;
      }
      lastSlash = i;
      dots = 0;
    } else if (code == '.' && dots != -1) {
      ++dots;
    } else {
      dots = -1;
    }
  }

  return res;
}

#ifdef _WIN32
constexpr bool IsWindowsDriveLetter(const std::string_view path) noexcept {
  return path.size() > 2 && IsWindowsDeviceRoot(path[0]) &&
         (path[1] == ':' && (path[2] == '/' || path[2] == '\\'));
}
constexpr bool IsWindowsDeviceRoot(const char c) noexcept {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

EnvironmentString PathResolve(const EnvironmentPathAccess* env,
                        const EnvironmentPathViews& paths) {
  EnvironmentString resolvedDevice = "";
  EnvironmentString resolvedTail = "";
  bool resolvedAbsolute = false;
  const size_t numArgs = paths.size();
  auto cwd = env->GetCwd(env->exec_path());

  for (int i = numArgs - 1; i >= -1; i--) {
    EnvironmentString path;
    if (i >= 0) {
      path = EnvironmentString(paths[i]);
    } else if (resolvedDevice.empty()) {
      path = cwd;
    } else {
      // Windows has the concept of drive-specific current working
      // directories. If we've resolved a drive letter but not yet an
      // absolute path, get cwd for that drive, or the process cwd if
      // the drive cwd is not available. We're sure the device is not
      // a UNC path at this points, because UNC paths are always absolute.
      EnvironmentString resolvedDevicePath;
      const EnvironmentString envvar = "=" + resolvedDevice;
      SafeGetenv(envvar.c_str(), &resolvedDevicePath, env);
      path = resolvedDevicePath.empty() ? cwd : resolvedDevicePath;

      // Verify that a cwd was found and that it actually points
      // to our drive. If not, default to the drive's root.
      if (path.empty() ||
          (ToLower(path.substr(0, 2)) != ToLower(resolvedDevice) &&
           path[2] == '/')) {
        path = resolvedDevice + "\\";
      }
    }

    const size_t len = path.length();
    int rootEnd = 0;
    EnvironmentString device = "";
    bool isAbsolute = false;
    const char code = path[0];

    // Try to match a root
    if (len == 1) {
      if (IsPathSeparator(code)) {
        // `path` contains just a path separator
        rootEnd = 1;
        isAbsolute = true;
      }
    } else if (IsPathSeparator(code)) {
      // Possible UNC root

      // If we started with a separator, we know we at least have an
      // absolute path of some kind (UNC or otherwise)
      isAbsolute = true;

      if (IsPathSeparator(path[1])) {
        // Matched double path separator at beginning
        size_t j = 2;
        size_t last = j;
        // Match 1 or more non-path separators
        while (j < len && !IsPathSeparator(path[j])) {
          j++;
        }
        if (j < len && j != last) {
          const EnvironmentString firstPart = path.substr(last, j - last);
          // Matched!
          last = j;
          // Match 1 or more path separators
          while (j < len && IsPathSeparator(path[j])) {
            j++;
          }
          if (j < len && j != last) {
            // Matched!
            last = j;
            // Match 1 or more non-path separators
            while (j < len && !IsPathSeparator(path[j])) {
              j++;
            }
            if (j == len || j != last) {
              if (firstPart != "." && firstPart != "?") {
                // We matched a UNC root
                device =
                    "\\\\" + firstPart + "\\" + path.substr(last, j - last);
                rootEnd = j;
              } else {
                // We matched a device root (e.g. \\\\.\\PHYSICALDRIVE0)
                device = "\\\\" + firstPart;
                rootEnd = 4;
              }
            }
          }
        }
      }
    } else if (IsWindowsDeviceRoot(code) && path[1] == ':') {
      // Possible device root
      device = path.substr(0, 2);
      rootEnd = 2;
      if (len > 2 && IsPathSeparator(path[2])) {
        // Treat separator following drive name as an absolute path
        // indicator
        isAbsolute = true;
        rootEnd = 3;
      }
    }

    if (!device.empty()) {
      if (!resolvedDevice.empty()) {
        if (ToLower(device) != ToLower(resolvedDevice)) {
          // This path points to another device so it is not applicable
          continue;
        }
      } else {
        resolvedDevice = device;
      }
    }

    if (resolvedAbsolute) {
      if (!resolvedDevice.empty()) {
        break;
      }
    } else {
      resolvedTail = path.substr(rootEnd) + "\\" + resolvedTail;
      resolvedAbsolute = isAbsolute;
      if (isAbsolute && !resolvedDevice.empty()) {
        break;
      }
    }
  }

  // At this point the path should be resolved to a full absolute path,
  // but handle relative paths to be safe (might happen when process.cwd()
  // fails)

  // Normalize the tail path
  resolvedTail = NormalizeString(resolvedTail, !resolvedAbsolute, "\\");

  if (resolvedAbsolute) {
    return resolvedDevice + "\\" + resolvedTail;
  }

  if (!resolvedDevice.empty() || !resolvedTail.empty()) {
    return resolvedDevice + resolvedTail;
  }

  return ".";
}
#else   // _WIN32
EnvironmentString PathResolve(const EnvironmentPathAccess* env,
                        const EnvironmentPathViews& paths) {
  EnvironmentString resolvedPath;
  bool resolvedAbsolute = false;
  auto cwd = env->GetCwd(env->exec_path());
  const size_t numArgs = paths.size();

  for (int i = numArgs - 1; i >= -1 && !resolvedAbsolute; i--) {
    const EnvironmentString& path = (i >= 0) ? EnvironmentString(paths[i]) : cwd;

    if (!path.empty()) {
      resolvedPath = EnvironmentString(path) + "/" + resolvedPath;

      if (path.front() == '/') {
        resolvedAbsolute = true;
        break;
      }
    }
  }

  // Normalize the path
  auto normalizedPath = NormalizeString(resolvedPath, !resolvedAbsolute, "/");

  if (resolvedAbsolute) {
    return "/" + normalizedPath;
  }

  if (normalizedPath.empty()) {
    return ".";
  }

  return normalizedPath;
}
#endif  // _WIN32

}  // namespace pi_node

extern "C" size_t pi_node_environment_paths_storage_size() noexcept {
  return sizeof(PiNodeEnvironmentPaths);
}
extern "C" size_t pi_node_environment_paths_storage_alignment() noexcept {
  return alignof(PiNodeEnvironmentPaths);
}
extern "C" PiNodeEnvironmentPaths* pi_node_environment_paths_construct(
    void* storage, void* memory_owner,
    const PiNodeEnvironmentPathSpan* args, size_t count) noexcept {
  pi_node::AllocationScope allocation(memory_owner);
  Strings input;
  input.reserve(count);
  for (size_t i = 0; i < count; ++i)
    input.emplace_back(args[i].data, args[i].length);
  return ::new (storage) PiNodeEnvironmentPaths(input);
}
extern "C" void pi_node_environment_paths_destroy(
    PiNodeEnvironmentPaths* paths) noexcept {
  paths->~PiNodeEnvironmentPaths();
}
extern "C" void pi_node_environment_paths_exec_path(
    const PiNodeEnvironmentPaths* paths,
    PiNodeEnvironmentValueVisitor visitor, void* user) noexcept {
  visitor(user, paths->exec_path.data(), paths->exec_path.size());
}
extern "C" void pi_node_environment_paths_cwd(
    const PiNodeEnvironmentPaths* paths, void* memory_owner, JSContext* context,
    PiNodeEnvironmentValueVisitor visitor, void* user) noexcept {
  pi_node::AllocationScope allocation(memory_owner);
  const pi_node::EnvironmentPathAccess access{paths, nullptr, context, nullptr};
  String result = access.GetCwd(access.exec_path());
  visitor(user, result.data(), result.size());
}
extern "C" void pi_node_environment_path_resolve(
    const PiNodeEnvironmentPaths* paths, void* memory_owner, JSContext* context,
    PiNodeEnvironmentMap* map, const PiNodeEnvironmentTrace* trace,
    const PiNodeEnvironmentPathSpan* parts, size_t count,
    PiNodeEnvironmentValueVisitor visitor, void* user) noexcept {
  pi_node::AllocationScope allocation(memory_owner);
  const pi_node::EnvironmentPathAccess access{paths, map, context, trace};
  String result;
  {
    pi_node::EnvironmentPathViews inputs;
    inputs.reserve(count);
    for (size_t i = 0; i < count; ++i)
      inputs.emplace_back(parts[i].data, parts[i].length);
    result = pi_node::PathResolve(&access, inputs);
  }
  visitor(user, result.data(), result.size());
}
// path.cc:282-327. Native String storage replaces BufferValue's owned byte
// buffer; every original ToNamespacedPath branch uses the actual PathResolve.
extern "C" void pi_node_environment_path_to_namespaced(
    const PiNodeEnvironmentPaths* paths, void* memory_owner, JSContext* context,
    PiNodeEnvironmentMap* map, const PiNodeEnvironmentTrace* trace,
    const PiNodeEnvironmentPathSpan* input,
    PiNodeEnvironmentValueVisitor visitor, void* user) noexcept {
  pi_node::AllocationScope allocation(memory_owner);
  String path(input->data, input->length);
#ifdef _WIN32
  if (!path.empty()) {
    const pi_node::EnvironmentPathAccess access{paths, map, context, trace};
    pi_node::EnvironmentPathViews parts;
    parts.emplace_back(path.data(), path.size());
    String resolved_path = pi_node::PathResolve(&access, parts);
    if (resolved_path.size() > 2) {
      if (resolved_path[0] == '\\' && resolved_path[1] == '\\' &&
          resolved_path[2] != '?' && resolved_path[2] != '.') {
        path.assign(R"(\\?\UNC\)");
        path.append(resolved_path.data() + 2, resolved_path.size() - 2);
      } else if (pi_node::IsWindowsDeviceRoot(resolved_path[0]) &&
                 resolved_path[1] == ':' && resolved_path[2] == '\\') {
        path.assign(R"(\\?\)");
        path.append(resolved_path.data(), resolved_path.size());
      } else {
        path = std::move(resolved_path);
      }
    }
  }
#else
  (void)paths;
  (void)context;
  (void)map;
  (void)trace;
#endif
  visitor(user, path.data(), path.size());
}
extern "C" int pi_node_environment_safe_getenv(
    void* memory_owner, JSContext* context, PiNodeEnvironmentMap* map,
    const PiNodeEnvironmentTrace* trace, const char* key,
    PiNodeEnvironmentValueVisitor visitor, void* user) noexcept {
  pi_node::AllocationScope allocation(memory_owner);
  const pi_node::EnvironmentPathAccess access{nullptr, map, context, trace};
  String text;
  const bool found = pi_node::SafeGetenv(key, &text, &access);
  if (found) visitor(user, text.data(), text.size());
  return found ? 1 : 0;
}
