#include "native_node_environment_map_test_support.h"
#include <cstdlib>
#include <new>
#include <string>
#include <unordered_map>
extern "C" {
size_t pi_js_native_memory_used(void*);
int pi_js_native_memory_reserve(void*, size_t);
void pi_js_native_memory_release(void*, size_t);
}
namespace {
struct Retry {
    void* memory;
    size_t reserved;
    PiEnvironmentRetryObservation* observation;
    Retry* previous;
    std::new_handler former;
    static thread_local Retry* current;
    static void handler() {
        Retry* self = current;
        if (!self || self->reserved == 0) std::abort();
        ++self->observation->calls;
        if (self->observation->calls == 1)
            self->observation->first_used = pi_js_native_memory_used(self->memory);
        const size_t bytes = self->reserved;
        self->reserved = 0;
        pi_js_native_memory_release(self->memory, bytes);
    }
    Retry(void* owner, size_t bytes, PiEnvironmentRetryObservation* result)
        : memory(owner), reserved(bytes), observation(result),
          previous(current), former(std::get_new_handler()) {
        current = this;
        std::set_new_handler(handler);
    }
    ~Retry() {
        std::set_new_handler(former);
        current = previous;
        if (reserved) pi_js_native_memory_release(memory, reserved);
    }
};
thread_local Retry* Retry::current = nullptr;
}
extern "C" int pi_environment_test_retry(void* memory_owner, size_t limit,
    PiEnvironmentTestOperation operation, void* user,
    PiEnvironmentRetryObservation* observation) {
    *observation = {};
    const size_t used = pi_js_native_memory_used(memory_owner);
    if (used > limit) return -1;
    const size_t bytes = limit - used;
    if (!pi_js_native_memory_reserve(memory_owner, bytes)) return -1;
    observation->reserved = bytes;
    Retry selected(memory_owner, bytes, observation);
    operation(user);
    return 0;
}
extern "C" void pi_environment_test_reference_keys(
    const PiEnvironmentReferenceAction* actions, size_t count,
    PiNodeEnvironmentValueVisitor visitor, void* user) {
    std::unordered_map<std::string, std::string> original;
    for (size_t i = 0; i < count; ++i) {
        const auto& action = actions[i];
        if (action.kind == 0) {
            if (action.key && action.key_length > 0 && action.value) {
                original[std::string(action.key, action.key_length)] =
                    std::string(action.value, action.value_length);
            }
        } else if (action.kind == 1) {
            original.erase(std::string(action.key, action.key_length));
        } else {
            std::abort();
        }
    }
    for (const auto& pair : original)
        visitor(user, pair.first.data(), pair.first.size());
}
