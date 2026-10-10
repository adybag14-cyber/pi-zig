/* Thin native ABI: public callers never import libfyaml's private CRT headers. */
#include "pi_yaml.h"
#include <libfyaml.h>
#include <stdlib.h>
#include <string.h>
struct pi_yaml_document { struct fy_document *document; struct fy_diag *diag; struct fy_parser *parser; size_t extra_document; char *fallback; size_t fallback_length; int fallback_failed; };
static void capture_diagnostic(struct fy_diag *diag, void *user, const char *bytes, size_t length) {
    (void)diag;
    pi_yaml_document *document = user;
    if (document->fallback_failed || length > SIZE_MAX - document->fallback_length - 1) { document->fallback_failed = 1; return; }
    char *next = realloc(document->fallback, document->fallback_length + length + 1);
    if (!next) { document->fallback_failed = 1; return; }
    document->fallback = next;
    memcpy(next + document->fallback_length, bytes, length);
    document->fallback_length += length;
    next[document->fallback_length] = 0;
}
pi_yaml_document *pi_yaml_parse(const char *bytes, size_t length) {
    pi_yaml_document *result = calloc(1, sizeof(*result));
    if (!result) return NULL;
    struct fy_diag_cfg diagnostic_config;
    fy_diag_cfg_default(&diagnostic_config);
    diagnostic_config.fp = NULL;
    diagnostic_config.output_fn = capture_diagnostic;
    diagnostic_config.user = result;
    diagnostic_config.level = FYET_ERROR;
    diagnostic_config.colorize = false;
    diagnostic_config.show_source = false;
    diagnostic_config.show_position = false;
    diagnostic_config.show_type = false;
    diagnostic_config.show_module = false;
    result->diag = fy_diag_create(&diagnostic_config);
    if (!result->diag) { free(result); return NULL; }
    fy_diag_set_collect_errors(result->diag, true);
    struct fy_parse_cfg config = {0};
    config.flags = FYPCF_QUIET | FYPCF_COLLECT_DIAG | FYPCF_DEFAULT_VERSION_1_2 |
        FYPCF_JSON_NONE | FYPCF_ALLOW_DUPLICATE_KEYS | FYPCF_DISABLE_MMAP_OPT;
    config.diag = result->diag;
    /* Zig applies yaml2.9.0 core-schema duplicate/alias rules to the complete
       unresolved graph. Resolving here would discard aliases/cyclic identity. */
    result->parser = fy_parser_create(&config);
    if (!result->parser || fy_parser_set_string(result->parser, bytes, length)) return result;
    result->document = fy_parse_load_document(result->parser);
    struct fy_document *extra = fy_parse_load_document(result->parser);
    if (extra) {
        struct fy_node *root = fy_document_root(extra);
        struct fy_token *token = root ? fy_node_get_start_token(root) : NULL;
        const struct fy_mark *mark = token ? fy_token_start_mark(token) : NULL;
        result->extra_document = (mark ? mark->input_pos : 0) + 1;
        fy_parse_document_destroy(result->parser, extra);
    }
    return result;
}
void pi_yaml_destroy(pi_yaml_document *document) {
    if (!document) return;
    if (document->document) fy_parse_document_destroy(document->parser, document->document);
    if (document->parser) fy_parser_destroy(document->parser);
    fy_diag_destroy(document->diag);
    free(document->fallback);
    free(document);
}
pi_yaml_node *pi_yaml_root(pi_yaml_document *document) {
    return (pi_yaml_node *)(document && document->document ? fy_document_root(document->document) : NULL);
}
int pi_yaml_error_get(pi_yaml_document *document, pi_yaml_error *out) {
    void *iterator = NULL;
    struct fy_diag_error *error;
    if (!document) return -1;
    if (document->extra_document) {
        out->message = "Source contains multiple documents; please use YAML.parseAllDocuments()";
        out->offset = document->extra_document - 1; out->line = 0; out->column = 0; return 2;
    }
    while ((error = fy_diag_errors_iterate(document->diag, &iterator))) {
        if (error->type < FYET_ERROR) continue;
        const struct fy_mark *mark = error->fyt ? fy_token_start_mark(error->fyt) : NULL;
        out->message = error->msg;
        out->line = error->line;
        out->column = error->column;
        out->offset = mark ? mark->input_pos : 0;
        return 1;
    }
    if (document->fallback_failed) return -1;
    if (document->fallback_length) {
        while (document->fallback_length && (document->fallback[document->fallback_length-1] == '\n' || document->fallback[document->fallback_length-1] == '\r')) document->fallback[--document->fallback_length] = 0;
        out->message = document->fallback; out->offset = 0; out->line = 0; out->column = 0; return 1;
    }
    return document->document || (document->parser && !fy_parser_get_stream_error(document->parser)) ? 0 : -1;
}
int pi_yaml_kind(pi_yaml_node *node) {
    return fy_node_is_alias((struct fy_node *)node) ? 3 : (int)fy_node_get_type((struct fy_node *)node);
}
int pi_yaml_plain(pi_yaml_node *node) { return fy_node_get_style((struct fy_node *)node) == FYNS_PLAIN; }
int pi_yaml_double_quoted(pi_yaml_node *node) { return fy_node_get_style((struct fy_node *)node) == FYNS_DOUBLE_QUOTED; }
pi_yaml_text pi_yaml_scalar(pi_yaml_node *node) {
    pi_yaml_text result = {0}; result.bytes = fy_node_get_scalar((struct fy_node *)node, &result.length); return result;
}
pi_yaml_text pi_yaml_tag(pi_yaml_node *node) {
    pi_yaml_text result = {0}; result.bytes = fy_node_get_tag((struct fy_node *)node, &result.length); return result;
}
pi_yaml_text pi_yaml_anchor(pi_yaml_node *node) {
    pi_yaml_text result = {0}; struct fy_anchor *anchor = fy_node_get_anchor((struct fy_node *)node);
    if (anchor) result.bytes = fy_anchor_get_text(anchor, &result.length); return result;
}
size_t pi_yaml_offset(pi_yaml_node *node) {
    struct fy_token *token = fy_node_get_start_token((struct fy_node *)node);
    /* Scalar atom marks exclude quote delimiters; Source duplicate-key
       positions include the complete scalar token's style prefix. */
    const struct fy_mark *mark = token ? fy_token_style_start_mark(token) : NULL;
    return mark ? mark->input_pos : 0;
}
size_t pi_yaml_end(pi_yaml_node *node) {
    struct fy_token *token = fy_node_get_end_token((struct fy_node *)node);
    const struct fy_mark *mark = token ? fy_token_style_end_mark(token) : NULL;
    return mark ? mark->input_pos : 0;
}
size_t pi_yaml_tag_offset(pi_yaml_node *node) {
    struct fy_token *token = fy_node_get_tag_token((struct fy_node *)node);
    const struct fy_mark *mark = token ? fy_token_style_start_mark(token) : NULL;
    return mark ? mark->input_pos : 0;
}
size_t pi_yaml_tag_end(pi_yaml_node *node) {
    struct fy_token *token = fy_node_get_tag_token((struct fy_node *)node);
    const struct fy_mark *mark = token ? fy_token_style_end_mark(token) : NULL;
    return mark ? mark->input_pos : 0;
}
pi_yaml_node *pi_yaml_sequence_next(pi_yaml_node *node, void **iterator) {
    return (pi_yaml_node *)fy_node_sequence_iterate((struct fy_node *)node, iterator);
}
int pi_yaml_mapping_next(pi_yaml_node *node, void **iterator, pi_yaml_node **key, pi_yaml_node **value) {
    struct fy_node_pair *pair = fy_node_mapping_iterate((struct fy_node *)node, iterator);
    if (!pair) return 0;
    *key = (pi_yaml_node *)fy_node_pair_key(pair); *value = (pi_yaml_node *)fy_node_pair_value(pair); return 1;
}
