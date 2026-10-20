// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
// Selected native path/permission callers use the same actual String/vector.
// Their caller keeps an AllocationScope and every borrowed input alive.
#ifndef PI_NATIVE_NODE_ENVIRONMENT_PATHS_INTERNAL_HPP
#define PI_NATIVE_NODE_ENVIRONMENT_PATHS_INTERNAL_HPP
#include "native_node_environment_paths.h"
#include "native_node_environment_map_internal.hpp"
#include <string_view>
#include <vector>
namespace pi_node {
using EnvironmentPathViews =
    std::vector<std::string_view, Allocator<std::string_view>>;
struct EnvironmentPathAccess {
  const PiNodeEnvironmentPaths* paths;
  PiNodeEnvironmentMap* map;
  JSContext* context;
  const PiNodeEnvironmentTrace* trace;
  const EnvironmentString& exec_path() const noexcept;
  EnvironmentString GetCwd(const EnvironmentString& path) const;
};
EnvironmentString NormalizeString(std::string_view path, bool allowAboveRoot,
                                  std::string_view separator);
EnvironmentString PathResolve(const EnvironmentPathAccess* env,
                              const EnvironmentPathViews& paths);
bool SafeGetenv(const char* key, EnvironmentString* text,
                const EnvironmentPathAccess* env);
}  // namespace pi_node
#endif
