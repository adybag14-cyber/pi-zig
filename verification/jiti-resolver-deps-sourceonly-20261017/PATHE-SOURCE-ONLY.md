# Jiti dependency source-only checkpoint — pathe2.0.3

Production leaf src/extensions/native_pathe.zig implements the eight actual
pathe2.0.3 operations consumed by jiti2.7: normalize/join/dirname/basename/extname/
isAbsolute and normalizeAliases/resolveAlias. create(engine) returns a carrier of
these real function bindings. Composition must retain one instance and select
its actual named functions for pathe and pathe/utils; this does not register or
pretend to expose the full public package namespace. Other pathe exports are not
implemented or advertised. No SourceLoader, identity resolver or always-failing
namespace is introduced.

The live VM port retains private regexp/Set/Symbol module constants, Source
string method calls, receiver/coercion order, alias specificity sort, Symbol.for
marker identity/descriptors, entry getter reads, ordinary function construction,
real iterator binding/closing, raw reasons and native allocation bypass. Private
captures are GC visible. Partial root/atom retention failures release owned
values. Abrupt IteratorClose runs entered cleanup, suppresses ordinary cleanup
throws for ordinary throw completions, lets cleanup native allocation bypass an
ordinary primary, and preserves an already-fatal primary's exact reason. Capture
slot ownership is cleared before freeing/replacing its previous strong value.

The initial standalone UTF16 typed path port is preserved as an authored inert
reference, not selected production: authored-typed-path-reference.zig.txt.
The live port is necessary because pure normalization would bypass observable
String/RegExp methods. The typed reference is not an original answer authority.

Prepared subject input jiti-pathe-2.0.3.input.mjs defines313 ordered observations
from36 path strings,14 join groups, alias mappings/markers/getters and callback
ordering/metadata. This313 count is an input census, not an executed result.
No expected JSON exists. Five native controls are authored and unrun: full
original comparison, function GC retention, fatal-primary iterator cleanup,
cleanup-fatal overriding ordinary primary, and complete Zig-allocation cleanup.
No build target, package default or registry selection is changed by this
checkpoint. No formatter/AST/compiler/Node/eval/generator/native job ran.

This checkpoint is not runtime-qualified or a full pathe/jiti claim. Realm-wide
replacement of builtins/proxies, for-in deletion/prototype mutation corner cases,
generic nonstandard basename extension values and VM-specific error formatting
remain unqualified until genuine controls exercise them. The prepared input
already observes live String/Object/sort calls and raw getter reasons; no output
normalization or authored expected answers hides differences.

Pinned primaries are retained as inert sources and complete SHA512-verified npm
archives with all files copied byte-for-byte to .txt names. Pathe2.0.3 published
shared bundle/utils confirm the ported Source operations. mlly1.8.2 published
dist inlines import-meta-resolve4.2.0 but imports pathe/ufo at runtime. Therefore
jiti's own lock selects ufo1.6.4. The inspected ufo1.6.3 build-lock archive is
explicitly unselected and preserved; no implementation uses that authority.
Archive/member manifests retain original paths, integrity and SHA256 identities.
No dependency code is executed or used as a production host implementation.

The remaining assigned leaf is real mlly1.8.2 fileURL/path/resolvePathSync policy
with import-meta-resolve4.2 exports/imports/conditions/fallback/physical resolution.
It is work in progress, not substituted by CommonJS normalizeRequire. Root's
other owners supply actual builtinModules/CommonJS paths and lstatSync seams;
operators separately own hasESMSyntax/frontend utility dependencies. Existing
Node URL/FS bindings may be reused only through their actual semantics.
