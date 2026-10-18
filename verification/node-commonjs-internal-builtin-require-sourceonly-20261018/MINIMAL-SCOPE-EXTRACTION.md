# Minimal intake dependency extraction

Additive source-only successor after reviewed d2ec7707981da76a7a057b3f3d3b6ae642b6711a.
The private producer now imports native_node_internal_builtin_scope.zig rather
than importing its Scope through the full public createRequire module.
The complete `pub const Scope = struct` body is copied verbatim from the
reviewed6be createRequire source. Its operations, order and SAME canonical
native_node_commonjs_owned_boundary.zig policy are unchanged. The old
createRequire file and every shared Scope/Engine/C/helper remain untouched.

This permits a narrow intake into Rootc388 without pulling in the unrelated
public bootstrap, generic error graph, wrapper/compiler or old build.zig.
Only the private producer, its small local Scope, the reviewed6be owned
Boundary, genuine tests and source provenance are needed. Root's existing
Engine/JS/ModuleCallable/constructor/fs/path and C/H files must be preserved.
The actual NativeInvocation API names were verified in immutable c388 source;
this is interface/source inspection, not compiler or runtime qualification.

The original d2ec/b249 manifests and independent receipt5E803 remain historical
finite source closures. prepared-v3.json binds the additive extraction. The
four test names/assertions and exact configured quota restoration do not change.
No jobs, parser, compiler, metadata query, Node or Main mutation occurred.
