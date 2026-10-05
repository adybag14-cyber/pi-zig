#ifndef PI_TYPESCRIPT_SCANNER_ABI_H
#define PI_TYPESCRIPT_SCANNER_ABI_H

/* The pinned scanner uses a C11 old-style create() definition, while its
 * generated parser calls create(void). A preceding prototype makes the
 * definition inherit that exact ABI and Clang function-sanitizer type. */
void *tree_sitter_typescript_external_scanner_create(void);

#endif
