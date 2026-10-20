// Private selected Node v24.13 package JSON parser. Native bytes only.
#ifndef PI_NATIVE_NODE_PACKAGE_JSON_PARSER_H
#define PI_NATIVE_NODE_PACKAGE_JSON_PARSER_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct PiNodePackageJsonParser PiNodePackageJsonParser;
typedef struct PiNodePackageJsonConfig PiNodePackageJsonConfig;

enum PiNodePackageJsonStatus {
    PI_NODE_PACKAGE_JSON_OK = 0,
    PI_NODE_PACKAGE_JSON_INVALID = 1,
    PI_NODE_PACKAGE_JSON_MEMORY = 2
};
typedef struct PiNodePackageJsonSpan {
    const char* data;
    size_t length;
    int present;
} PiNodePackageJsonSpan;
typedef struct PiNodePackageJsonViews {
    PiNodePackageJsonSpan name;
    PiNodePackageJsonSpan main;
    PiNodePackageJsonSpan type;
    PiNodePackageJsonSpan imports;
    PiNodePackageJsonSpan exports;
    PiNodePackageJsonSpan scripts;
    PiNodePackageJsonSpan raw_json;
} PiNodePackageJsonViews;

// The nonnull memory owner is borrowed for creation. Every real allocation
// independently retains it. NULL means an actual charged allocation failed.
PiNodePackageJsonParser* pi_node_package_json_parser_create(void* memory_owner);
void pi_node_package_json_parser_destroy(PiNodePackageJsonParser* parser);

// The parser is synchronous and must not be entered concurrently. Input bytes
// are borrowed only during this call. A normal result transfers one independently
// owned config; all other results leave *output NULL. MEMORY requires the caller
// to record its actual native allocation failure and retire this parser; no
// further parse is admitted after that event. No Engine or JS value enters C++.
int pi_node_package_json_parse(PiNodePackageJsonParser* parser,
                              const uint8_t* input, size_t length,
                              PiNodePackageJsonConfig** output);

// The native modules binding must construct/throw its INVALID-package Error
// while the partially parsed Config is still alive. This entry transfers one
// owned Config on OK or INVALID; MEMORY alone leaves *output NULL and poisons
// the parser as above. On INVALID, retain this Config through native Error
// construction and ordered code Set.Check(), then destroy it. This entry does
// not itself allocate a JS Error or publish a cache entry.
int pi_node_package_json_parse_retained(PiNodePackageJsonParser* parser,
                                       const uint8_t* input, size_t length,
                                       PiNodePackageJsonConfig** output);

// Views borrow their config, remain independent of the parser, and include exact
// lengths (embedded NUL is not truncated). Only type/raw_json are always present.
// The raw_json bytes include exactly the original pad() trailing-space suffix.
void pi_node_package_json_config_views(const PiNodePackageJsonConfig* config,
                                      PiNodePackageJsonViews* output);
void pi_node_package_json_config_destroy(PiNodePackageJsonConfig* config);

#ifdef __cplusplus
}
#endif
#endif
