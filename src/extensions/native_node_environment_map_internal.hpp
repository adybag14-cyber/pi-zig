// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
// Internal C++ view of the real supplied MapKVStore result. The caller retains
// the map through use of the returned optional; its String owns its own blocks.
#ifndef PI_NATIVE_NODE_ENVIRONMENT_MAP_INTERNAL_HPP
#define PI_NATIVE_NODE_ENVIRONMENT_MAP_INTERNAL_HPP
#include "native_node_environment_map.h"
#include "native_node_standard_allocator.hpp"
#include <optional>
#include <string>
namespace pi_node {
using EnvironmentString =
    std::basic_string<char, std::char_traits<char>, Allocator<char>>;
// Performs the original locked C-string Get and returns its actual optional
// by value. No extra String is created and no JavaScript value is touched.
std::optional<EnvironmentString> environmentMapGet(
    PiNodeEnvironmentMap* map, const char* key);
}  // namespace pi_node
#endif
