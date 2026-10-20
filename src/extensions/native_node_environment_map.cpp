// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
// Selected Node v24.13 MapKVStore expressions, using the actual pinned native
// C++ string/hash-table implementation and independently charged allocations.
#include "native_node_environment_map.h"
#include "native_node_environment_map_internal.hpp"
#include "native_node_check_failure.h"
#include "uv.h"
#include <atomic>
#include <cstdlib>
#include <optional>
#include <string>
#include <unordered_map>
#include <utility>

namespace {
using String = pi_node::EnvironmentString;
using Entry = std::pair<const String, String>;
using Entries = std::unordered_map<String, String, std::hash<String>,
    std::equal_to<String>, pi_node::Allocator<Entry>>;
static_assert(sizeof(String) == sizeof(std::string));
static_assert(alignof(String) == alignof(std::string));
static_assert(sizeof(Entries) ==
              sizeof(std::unordered_map<std::string, std::string>));
static_assert(alignof(Entries) ==
              alignof(std::unordered_map<std::string, std::string>));

#define PI_ENV_STRINGIFY_INNER(value) #value
#define PI_ENV_STRINGIFY(value) PI_ENV_STRINGIFY_INNER(value)
class Mutex {
 public:
  explicit Mutex(JSContext* context) noexcept {
    if (uv_mutex_init(&value_) != 0) {
      const PiNodeAssertionInfo info = {
          __FILE__ ":" PI_ENV_STRINGIFY(__LINE__),
          "0 == uv_mutex_init(&value_)", "PiNodeEnvironmentMap::Mutex"};
      pi_node_assert_failure(context, &info);
      std::abort();  // the actual native CHECK is terminal
    }
  }
  ~Mutex() noexcept { uv_mutex_destroy(&value_); }
  void lock() const noexcept { uv_mutex_lock(&value_); }
  void unlock() const noexcept { uv_mutex_unlock(&value_); }
  Mutex(const Mutex&) = delete;
  Mutex& operator=(const Mutex&) = delete;
 private:
  mutable uv_mutex_t value_;
};
class Lock {
 public:
  explicit Lock(const Mutex& mutex) noexcept : mutex_(mutex) { mutex_.lock(); }
  ~Lock() noexcept { mutex_.unlock(); }
  Lock(const Lock&) = delete;
  Lock& operator=(const Lock&) = delete;
 private:
  const Mutex& mutex_;
};
}  // namespace

struct PiNodeEnvironmentMap {
  // The stable block prefix already retains memory_owner. It remains valid
  // through member destruction; every separately allocated table/string block
  // has its own independent owner entitlement.
  std::atomic<std::size_t> references{1};
  void* const memory_owner;
  Mutex mutex;
  Entries entries;

  PiNodeEnvironmentMap(void* owner, JSContext* context) noexcept
      : memory_owner(owner), mutex(context) {}
  PiNodeEnvironmentMap(const PiNodeEnvironmentMap& other, void* owner,
                       JSContext* context)
      : memory_owner(owner), mutex(context), entries(other.entries) {}

  std::optional<String> get(const char* key) const {
    Lock lock(mutex);
    auto it = entries.find(key);
    return it == entries.end() ? std::nullopt : std::make_optional(it->second);
  }
};
std::optional<pi_node::EnvironmentString> pi_node::environmentMapGet(
    PiNodeEnvironmentMap* map, const char* key) {
  AllocationScope scope(map->memory_owner);
  return map->get(key);
}
namespace {
class Retained {
 public:
  explicit Retained(PiNodeEnvironmentMap* map) noexcept : map_(map) {
    pi_node_environment_map_retain(map_);
  }
  ~Retained() noexcept { pi_node_environment_map_release(map_); }
  Retained(const Retained&) = delete;
  Retained& operator=(const Retained&) = delete;
 private:
  PiNodeEnvironmentMap* map_;
};
}  // namespace

struct PiNodeEnvironmentKeys {
  const PiNodeEnvironmentMap* map;
  bool begun = false;
  Entries::const_iterator next;
  Entries::const_iterator end;
};

extern "C" PiNodeEnvironmentMap* pi_node_environment_map_create(
    void* memory_owner, JSContext* context) noexcept {
  pi_node::AllocationScope scope(memory_owner);
  auto* storage = pi_node::Allocator<PiNodeEnvironmentMap>{}.allocate(1);
  return ::new (static_cast<void*>(storage))
      PiNodeEnvironmentMap(memory_owner, context);
}
extern "C" PiNodeEnvironmentMap* pi_node_environment_map_clone(
    PiNodeEnvironmentMap* source, void* memory_owner, JSContext* context) noexcept {
  Retained selected(source);
  pi_node::AllocationScope scope(memory_owner);
  auto* storage = pi_node::Allocator<PiNodeEnvironmentMap>{}.allocate(1);
  // The original specialized Clone copies map_ without an added mutex scope.
  // Its caller must exclude concurrent mutation, as for that original body.
  return ::new (static_cast<void*>(storage))
      PiNodeEnvironmentMap(*source, memory_owner, context);
}
extern "C" void pi_node_environment_map_retain(PiNodeEnvironmentMap* map) noexcept {
  const auto old = map->references.fetch_add(1, std::memory_order_relaxed);
  if (old == 0 || old == std::numeric_limits<std::size_t>::max()) std::abort();
}
extern "C" void pi_node_environment_map_release(PiNodeEnvironmentMap* map) noexcept {
  if (!map) return;
  const auto old = map->references.fetch_sub(1, std::memory_order_acq_rel);
  if (old == 0) std::abort();
  if (old != 1) return;
  // Native entries retire in the real container order, then its mutex, before
  // the stable block and its final native memory entitlement are released.
  map->~PiNodeEnvironmentMap();
  pi_node::Allocator<PiNodeEnvironmentMap>{}.deallocate(map, 1);
}
extern "C" int pi_node_environment_map_get(PiNodeEnvironmentMap* map,
    const char* key, PiNodeEnvironmentValueVisitor visitor, void* user) noexcept {
  Retained selected(map);
  pi_node::AllocationScope scope(map->memory_owner);
  std::optional<String> value = map->get(key);
  if (!value.has_value()) return 0;
  visitor(user, value->data(), value->size());
  return 1;
}
extern "C" int pi_node_environment_map_get_js(PiNodeEnvironmentMap* map,
    const char* key, PiNodeEnvironmentValueVisitor visitor, void* user) noexcept {
  Retained selected(map);
  pi_node::AllocationScope scope(map->memory_owner);
  std::optional<String> value = map->get(key);
  if (!value.has_value()) return 0;
  String val = value.value();
  visitor(user, val.data(), val.size());
  return 1;
}
extern "C" int32_t pi_node_environment_map_query(
    PiNodeEnvironmentMap* map, const char* key) noexcept {
  Retained selected(map);
  pi_node::AllocationScope scope(map->memory_owner);
  Lock lock(map->mutex);
  return map->entries.contains(key) ? 0 : -1;
}
extern "C" void pi_node_environment_map_lock(PiNodeEnvironmentMap* map) noexcept {
  pi_node_environment_map_retain(map);
  map->mutex.lock();
}
extern "C" void pi_node_environment_map_unlock(PiNodeEnvironmentMap* map) noexcept {
  map->mutex.unlock();
  pi_node_environment_map_release(map);
}
extern "C" void pi_node_environment_map_set_locked(PiNodeEnvironmentMap* map,
    const char* key, std::size_t key_length,
    const char* value, std::size_t value_length) noexcept {
  pi_node::AllocationScope scope(map->memory_owner);
  if (key != nullptr && key_length > 0 && value != nullptr) {
    // C++17 assignment sequencing preserves original RHS value construction
    // before the temporary key, including replacement of an existing entry.
    map->entries[String(key, key_length)] = String(value, value_length);
  }
}
extern "C" void pi_node_environment_map_delete_locked(PiNodeEnvironmentMap* map,
    const char* key, std::size_t key_length) noexcept {
  pi_node::AllocationScope scope(map->memory_owner);
  map->entries.erase(String(key, key_length));
}
extern "C" void pi_node_environment_map_with_keys(PiNodeEnvironmentMap* map,
    PiNodeEnvironmentKeysVisitor visitor, void* user) noexcept {
  Retained selected(map);
  pi_node::AllocationScope scope(map->memory_owner);
  Lock lock(map->mutex);
  PiNodeEnvironmentKeys keys{map};
  visitor(user, &keys);
}
extern "C" std::size_t pi_node_environment_keys_count(
    PiNodeEnvironmentKeys* keys) noexcept {
  return keys->map->entries.size();
}
extern "C" int pi_node_environment_keys_next(PiNodeEnvironmentKeys* keys,
    const char** bytes, std::size_t* length) noexcept {
  // The caller reserves its original LocalVector before the range-for starts.
  if (!keys->begun) {
    keys->next = keys->map->entries.cbegin();
    keys->end = keys->map->entries.cend();
    keys->begun = true;
  }
  if (keys->next == keys->end) return 0;
  const auto& pair = *keys->next++;
  *bytes = pair.first.data();
  *length = pair.first.size();
  return 1;
}
