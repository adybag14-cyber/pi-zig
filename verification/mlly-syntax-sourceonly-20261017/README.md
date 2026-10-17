# Exact mlly1.8.2 hasESMSyntax export — source only

`native_mlly_syntax.zig` implements the actual consumed export in original
mlly1.8.2 `dist/index.mjs` lines2644–2653. It creates the real module-scope
ESM_RE and COMMENT_RE objects and a real ordinary constructible function named
hasESMSyntax, length1. Its algorithm conditionally calls the live code.replace
method, then returns the exact raw result of the live ESM_RE.test call. It does
not parse code, filter false positives, fix the original `[nr]` comment pattern,
cast replaced test results to bool, or invoke a host TypeScript/Node bridge.

Primary authority is npm mlly1.8.2, gitHead
c5ce4e5596761b9d2b063bcf82a5160d76e8c2cf. The inert original archive SHA512
matches its pinned registry integrity. Exact archive, full original mjs,
package/license and receipt are retained. The archive/full module reference
contains other exports/dependencies that this narrow leaf does not implement.
Acorn is imported by the full mlly module for other location helpers; the
consumed hasESMSyntax body is exactly the original regex algorithm.

The actual mlly namespace owner must create this declaration **once per real
Source module lifetime**, retain it and share the same function/regex identities
with every jiti/resolver consumer. It is not a factory-per-jiti substitution.
Namespace wiring/module-cache integration is still pending. The function owns
its real captured constants through the reviewed charged/marked ordinary
callable; all creating-scope roots unwind on failure. Direct host entry has
balanced diagnostic suppression and current-generation fresh-fatal propagation.
No new Engine field, module cache, C/H delta or global registration is added.

The unchanged original user input records26 ordinary observations, including
regex false positives, optional stripping, original comment grammar, null/symbol
arguments, exact throwing getter identity, raw live test return, regex constant
identity, raw replace result/coercion, inherited default-options getter and
ordinary callable shape. Native controls run that same input using the actual
export and exercise capture marking across genuine GC. Source reference must
bind the genuine unchanged package export with its actual manifested dependencies;
no extracted function or cloned JS body is an acceptable reference subject.

Three native entrypoints are prepared. No formatter/AST/compiler/native/Node
job has run. No observed/expected data exists. The full jiti/SDK factory remains
unselected; this leaf does not complete mlly, SourceLoader, public createJiti,
the private canonical require/eval cycle, Graph2 or graph reclamation. All65c
core/frontend products and prior protected proof bytes remain unchanged.
