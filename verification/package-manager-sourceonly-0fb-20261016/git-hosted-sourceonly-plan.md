# Bounded native Git parser and hosted projection

The catch-lifetime correction at a8e795961410f327fd67945c1883f2e46563199b
passed independent Body static review. No execution was performed.

The new native_sdk_git_source.zig authors Pi's actual parseGitUrl and its five
private helpers over a mandatory concrete hosted dependency. It preserves the
git: prefix gate, separate SCP/URL/shorthand @-ref splitting, two ordered hosted
candidate/filter/iterator passes, generic fallback, URL pathname serialization,
decoded path safety and actual global Boolean for filtering/pinned. It calls
real VM String/RegExp/decoder/URL operations, without a TS/Node implementation.
Its factory takes Inputs.hosted_git_info and returns a parseGitUrl namespace.

native_hosted_git_projection.zig authors the used fromUrl field projection:
GitHub, Bitbucket, GitLab, Gist and SourceHut shortcut/domain/protocol tables,
shorthand/SCP URL correction, host extraction, auth getter observations and
URIError handling. Its factory takes the actual node:url default module object
as Inputs.node_url, retaining that module object and reading its URL property
at each construction as the original require('url') consumer does. Pi's parser
separately reads the live global URL. Existing filesystem/URL owner confirmed
no overlapping constructor/module edits.

The private GC-visible cache preserves successful object identity, 1000-entry
LRU promotion/eviction, reentrant insertion/update and undefined-result deletion.
Pinned lru-cache 11.4.0 #set explicitly deletes undefined values; failed hosted
parses must therefore run again. JSON.stringify(opts || {}) is evaluated before
every lookup, including hits. No fake public LRU namespace is introduced.

This remains an explicitly bounded field projection, not a complete GitHost
class: the original constructor's Object.assign argument shape, full prototype
and host template functions remain outside the authored projection. Arbitrary
global Object.assign/prototype instrumentation can distinguish this boundary;
it is a known open compatibility surface, not a qualified equivalence claim.
The Source bodies of those wider methods have not been replaced with stubs.
No assembly/default/application input is retargeted in this checkpoint.

git-source-hosted-0fb.input.mjs prepares actual original parser and dependency
field observations across host/ref/encoding/traversal families, plus cache
identity, negative-cache absence, JSON lookup on hit, live Boolean and LRU
eviction. capture-git-source-prepared.mjs imports the untouched original files
only after checking their pinned hashes; it requires the existing full Source
observer preload and a control manifest. A new full before/after candidate and
runtime seal and process grant are still required before any capture. Expected
output is absent. No input-derived result is authored as an expected answer.

package-manager-pattern-callers-0fb.input.mjs separately prepares six real
applyPackageFilter cases over fresh physical files and a real package manifest:
relative file, basename file, absolute file, and the corresponding three SKILL
parent forms. These exercise the original six minimatch sites through the
actual class. They do not replace collectManifestFiles or any class method.
This supplements, without rewriting, the historical 50 package controls.

Static review and future admitted Source/native/allocator gates remain required.
There has been no Node/Source/Zig fmt/AST/compiler/native/C execution. No complete
hosted-git-info, default SDK, application, release or full Pi parity is certified.
