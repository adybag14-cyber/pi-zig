/* Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
 * Selected native MapKVStore for an explicitly supplied embedding environment.
 * No Engine, JS value, or process-global environment is stored by this owner. */
#ifndef PI_NATIVE_NODE_ENVIRONMENT_MAP_H
#define PI_NATIVE_NODE_ENVIRONMENT_MAP_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#define PI_ENV_NOEXCEPT noexcept
#else
#define PI_ENV_NOEXCEPT
#endif
struct JSContext;
typedef struct PiNodeEnvironmentMap PiNodeEnvironmentMap;
typedef struct PiNodeEnvironmentKeys PiNodeEnvironmentKeys;

/* All callbacks are synchronous. Value/key spans are borrowed until callback
 * return; neither a span nor a Keys pointer may escape. Callbacks must not throw
 * a C++ exception. The enumeration callback must not invoke guest code or
 * mutate/reenter this locked map. Native intrinsic allocation is permitted. */
typedef void (*PiNodeEnvironmentValueVisitor)(void* user,
                                             const char* bytes, size_t length);
typedef void (*PiNodeEnvironmentKeysVisitor)(void* user,
                                            PiNodeEnvironmentKeys* keys);

/* memory_owner is a live actual native memory domain. context is borrowed only
 * for an actual uv_mutex_init CHECK failure. Standard C++ allocation failures
 * take the real native new_handler/bad_alloc path; these calls never return a
 * fabricated nullable owner or JavaScript allocation reason. */
PiNodeEnvironmentMap* pi_node_environment_map_create(
    void* memory_owner, struct JSContext* context) PI_ENV_NOEXCEPT;
PiNodeEnvironmentMap* pi_node_environment_map_clone(
    PiNodeEnvironmentMap* source, void* memory_owner,
    struct JSContext* context) PI_ENV_NOEXCEPT;
void pi_node_environment_map_retain(PiNodeEnvironmentMap* map) PI_ENV_NOEXCEPT;
void pi_node_environment_map_release(PiNodeEnvironmentMap* map) PI_ENV_NOEXCEPT;

/* key is an actual NUL-terminated C string. Get and Query intentionally use
 * that C-string prefix. get invokes visitor only when found, after unlocking
 * and while the original optional<string> copy is still alive. get_js adds
 * the original second local string copy before invoking the intrinsic result
 * producer. Return 0 means absent; 1 means the visitor ran, not that it succeeded. */
int pi_node_environment_map_get(PiNodeEnvironmentMap* map, const char* key,
    PiNodeEnvironmentValueVisitor visitor, void* user) PI_ENV_NOEXCEPT;
int pi_node_environment_map_get_js(PiNodeEnvironmentMap* map, const char* key,
    PiNodeEnvironmentValueVisitor visitor, void* user) PI_ENV_NOEXCEPT;
int32_t pi_node_environment_map_query(
    PiNodeEnvironmentMap* map, const char* key) PI_ENV_NOEXCEPT;

/* A mutation guard retains the map before locking. The JS adapter obtains it
 * AFTER actual guest ToString and BEFORE both native Utf8Value conversions.
 * set_locked/delete_locked require that guard and use full byte spans. Their
 * string/key/table allocations complete and retire while the guard is held. */
void pi_node_environment_map_lock(PiNodeEnvironmentMap* map) PI_ENV_NOEXCEPT;
void pi_node_environment_map_unlock(PiNodeEnvironmentMap* map) PI_ENV_NOEXCEPT;
void pi_node_environment_map_set_locked(PiNodeEnvironmentMap* map,
    const char* key, size_t key_length,
    const char* value, size_t value_length) PI_ENV_NOEXCEPT;
void pi_node_environment_map_delete_locked(PiNodeEnvironmentMap* map,
    const char* key, size_t key_length) PI_ENV_NOEXCEPT;

/* The native lock covers the entire callback, including its intrinsic vector,
 * string, and final array producers and their retirement. No key snapshot or
 * sorted order is introduced. Iteration is the actual native unordered_map's. */
void pi_node_environment_map_with_keys(PiNodeEnvironmentMap* map,
    PiNodeEnvironmentKeysVisitor visitor, void* user) PI_ENV_NOEXCEPT;
size_t pi_node_environment_keys_count(PiNodeEnvironmentKeys* keys) PI_ENV_NOEXCEPT;
int pi_node_environment_keys_next(PiNodeEnvironmentKeys* keys,
    const char** bytes, size_t* length) PI_ENV_NOEXCEPT;

#ifdef __cplusplus
}
#endif
#undef PI_ENV_NOEXCEPT
#endif
