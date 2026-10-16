# Actual package-manager cloud-sync dependency, source only

The actual `native_sdk_package_assembly.create` requires
`path_utilities.markPathIgnoredByCloudSync` for managed npm/Git storage setup.
The existing native path namespace omitted this public function, so actual
construction could not satisfy that import. This successor supplies the real
function and an explicit `createWithPlatform(engine, filesystem, process,
spawnProcessSync)` path-namespace assembly seam. The captured process and
spawn binding must come from the actual application graph. Existing `create`
callers are unchanged; this does not select or qualify a default SDK graph.

Authority is the complete official `packages/coding-agent/src/utils/paths.ts`
at pinned `4dd2b149d155d7369de16ea4dc77c84e9f5ffb24`, file SHA256
`64C3EBEF724FA21ED0042E127908B4323A5D2F1B8AAA91EEE550442332FE8502`.
The subject is its original exported function at lines 125–139. Original
upstream, Git/PackageManager captures, inputs, manifests and goldens remain
unchanged. No dependency snapshot is reconstructed here.

The native leaf preserves the conditional platform reads, the actual attribute
array's live iterator, a fresh platform read for each loop body, literal argv
and options property order, uncoerced path identity, undefined import receiver,
immediate discarded-return release and synchronous error propagation. It uses
the existing actual `spawnProcessSync` binding. Ordinary IteratorClose keeps the
original body throw; private fatal/native allocation errors retain the existing
package catch contract and bypass guest cleanup. No Engine, shared helper, C or
transport implementation is changed.

`src/extensions/fixtures/path-cloud-sync-4dd.input.mjs` prepares seven genuine
subject observations: Darwin, Linux, Windows, changing platform getter,
replaced attribute-array iterator, thrown spawn reason, and an iterator return
which throws while closing the original spawn failure. It contains no expected
answers. A future reference harness must load the **full original module** and
supply `PathsAPI` with its actual exported function, an explicit process object,
a captured spawn observer (`spawnCalls.observe`) and an explicit case ID. The
native harness must supply the same seams to this leaf. These input controls
must never invoke real xattr/setfattr during comparison. Neither harness nor any
expected JSON is claimed complete in this checkpoint.

The remaining real assembly boundaries are explicit:

- `node:crypto.createHash` is required by storage for SHA256 Git marker paths;
  no native createHash namespace implementation was found in current Root.
- `node:fs.globSync` is required by discovery's package-glob expansion; no
  native globSync implementation was found in current Root's node_fs module.
- Semver/ignore/minimatch/Git leaves have separate source-only ownership and
  qualification. Their real namespaces must be created once at module assembly
  and supplied to PackageManager, rather than replaced with fallback functions.
- Real process/stdio/child-process readiness, actual namespace construction and
  application selection remain separate integration and qualification work.
- The SDK assembly owner retains jiti, aliases and virtual-module imports.

Validation is limited to source inspection, file hashes and Git whitespace
checks. No formatter, AST, Node, Source capture, compiler or native job ran.
Runtime recovery, genuine reference outputs, native behavioral qualification
and default SDK/application activation remain pending.
