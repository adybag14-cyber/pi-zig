/* Test adapters: actual std::new_handler and unmodified standard-map oracle. */
#ifndef PI_NATIVE_NODE_ENVIRONMENT_MAP_TEST_SUPPORT_H
#define PI_NATIVE_NODE_ENVIRONMENT_MAP_TEST_SUPPORT_H
#include "native_node_environment_map.h"
#ifdef __cplusplus
extern "C" {
#endif
typedef struct PiEnvironmentRetryObservation {
    size_t calls;
    size_t first_used;
    size_t reserved;
} PiEnvironmentRetryObservation;
typedef void (*PiEnvironmentTestOperation)(void* user);
/* Reserves the remaining real native budget. The first actual standard
 * allocation failure invokes a genuine temporary new_handler which releases
 * that reservation. The former handler and any unspent reservation are restored
 * before return. This adapter is confined to serial native test processes. */
int pi_environment_test_retry(void* memory_owner, size_t limit,
    PiEnvironmentTestOperation operation, void* user,
    PiEnvironmentRetryObservation* observation);
typedef struct PiEnvironmentReferenceAction {
    unsigned kind; /* 0: original full-span Set; 1: original full-span Delete */
    const char* key;
    size_t key_length;
    const char* value;
    size_t value_length;
} PiEnvironmentReferenceAction;
/* The oracle uses actual std::unordered_map<std::string,std::string> and the
 * original expressions; it does not call the production map or sort keys. */
void pi_environment_test_reference_keys(
    const PiEnvironmentReferenceAction* actions, size_t count,
    PiNodeEnvironmentValueVisitor visitor, void* user);
#ifdef __cplusplus
}
#endif
#endif
