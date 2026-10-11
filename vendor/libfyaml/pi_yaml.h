#ifndef PI_YAML_H
#define PI_YAML_H
#include <stddef.h>
#include <stdint.h>
typedef struct pi_yaml_document pi_yaml_document;
typedef struct pi_yaml_node pi_yaml_node;
typedef struct { const char *bytes; size_t length; } pi_yaml_text;
typedef struct { const char *message; size_t offset; int line; int column; } pi_yaml_error;
pi_yaml_document *pi_yaml_parse(const char *, size_t);
void pi_yaml_destroy(pi_yaml_document *);
pi_yaml_node *pi_yaml_root(pi_yaml_document *);
int pi_yaml_error_get(pi_yaml_document *, pi_yaml_error *);
int pi_yaml_kind(pi_yaml_node *); /* scalar0, sequence1, mapping2, alias3 */
int pi_yaml_plain(pi_yaml_node *);
int pi_yaml_double_quoted(pi_yaml_node *);
int pi_yaml_single_quoted(pi_yaml_node *);
int pi_yaml_flow(pi_yaml_node *);
int pi_yaml_commented(pi_yaml_node *);
pi_yaml_text pi_yaml_scalar(pi_yaml_node *);
pi_yaml_text pi_yaml_tag(pi_yaml_node *);
pi_yaml_text pi_yaml_anchor(pi_yaml_node *);
size_t pi_yaml_offset(pi_yaml_node *);
size_t pi_yaml_end(pi_yaml_node *);
size_t pi_yaml_tag_offset(pi_yaml_node *);
size_t pi_yaml_tag_end(pi_yaml_node *);
pi_yaml_node *pi_yaml_sequence_next(pi_yaml_node *, void **);
int pi_yaml_mapping_next(pi_yaml_node *, void **, pi_yaml_node **, pi_yaml_node **);
#endif
