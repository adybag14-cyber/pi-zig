# Original Node builtin authority, source-only checkpoint

`native_node_builtin_node24_data.zig` copies the ordered 72 strings and the three
extension handler metadata records from the independently accepted original C8
capture. It does not use the candidate's module registry, sort the strings, add
aliases, or claim that those APIs have native implementations. The raw original
output is 22201 bytes, SHA-256
`F982B6E1D49128FFE78478DCD6F2FA04D298F7CBDE79BC9EE8288E40864AE967`.
The independent original authority acceptance is
`F6CE98842E87213326F7E46032F9ED011B721F2580290AFF2A8CD7EFD96D8FA1`.
Both remain in the container evidence directories named in the provenance JSON.

`native_node_builtin_catalog.createOriginalNode24` builds an owned frozen array
and an ordinary nonconstructible `isBuiltin` function with the observed name and
length. Its callback roots the frozen list through the existing traced, charged
Module callable. One actual Module bootstrap must retain this catalog and share
its array; repeated factory calls are not a replacement for Module identity.
The generic authority-list constructor keeps its previous private anonymous
function declaration. Neither constructor selects a default Node namespace.

The original ordered list includes four prefix-only spellings. `node:test` is a
builtin while `test` and `node:node:test` are not. This policy is separate from
whether an implementation or native addon loader exists.

The authority target is exactly Node v24.14.0, executable SHA-256
`63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088`,
source `f657bb8ed86365ff3fdbe32e27563e778b41486a`.
`requireOriginalNodeVersion` is an explicit future admission check: another
version requires a new independently accepted original capture. It does not
change the candidate's `process.version` or claim an actual Node host bridge.

Three prepared native controls cover frozen publication/callable shape,
prefix-only classification and version admission. They have not been compiled,
queried or run. The original C8 caller and raw observations are unchanged; no
expected output was synthesized. Full CommonJS loading, sync ESM, hooks, FS and
NAPI remain separate genuine implementation dependencies.
