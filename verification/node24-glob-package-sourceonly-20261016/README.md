# Native PackageManager glob traversal, source only

The actual Pi `expandPackageGlob(pattern, root)` calls Node's
`globSync(pattern, {cwd: root})`, resolves matches against root, filters hidden
path components and sorts them. That caller already exists in
`native_sdk_package_discovery.zig`; its required real `filesystem.globSync`
binding was missing.

`native_node_glob_sync.create(engine, actual_paths)` now authors that binding
for an explicit simple-pattern contract. `install(engine, actual_filesystem,
actual_paths)` adds it to an explicitly supplied real filesystem namespace.
Neither is selected automatically, and `node_fs.zig` is unchanged. The stream
owner retains its installation-mode/writer work. Root's SDK assembly can install
this function before creating the PackageManager graph, after review and future
qualification. The leaf captures actual `join`/`resolve` once and performs real
native `std.Io` lstat-style metadata queries and directory enumeration.

## Exact references and dependency distinction

Official Node tag `v24.14.0` currently resolves through annotated tag
`a3d5b4bca68d85dcb67d527b05409795f69c66e7` to commit
`f657bb8ed86365ff3fdbe32e27563e778b41486a`. The downloaded original files under
`official-node24/` are source references only; they were never executed:

| Original file | SHA256 |
| --- | --- |
| `lib/internal/fs/glob.js` | `3514AC6A0935EE287E500A20C009CCB6A4A13067A2ABAC5365BF260DD48B4364` |
| `deps/minimatch/package.json` | `42BAB984CF3973FDB0EFD1A9F8E52B3F80161C74239250695B21034E3C1F9EAE` |
| `deps/minimatch/index.js` | `799682EAA0CD88C6016D2AE6D8D0D58FBBA45CEBF5454F682182AE11B854ABF1` |
| `LICENSE` | `4573185D56580DA2B890BA34A85A409257640F1C5632EADE4300137266194D18` |

Node24's internal Glob uses bundled minimatch **10.1.2**, with
`nonegate`, `nocomment`, `windowsPathsNoEscape`, `optimizationLevel:2`,
`nocaseMagicOnly`, and platform case policy. This is distinct from Pi's external
minimatch **10.2.6** dependency. The unchanged native core/AST are reused with
their owner's permission, pinned to `de7f662023acd1f982dab5cfa8f55a766cd23b26`:

- `native_minimatch.zig`: `C9D8FF0221267C505D749E3421CFB84ABF7F4538B92E19B7CD05E46E7274005E`
- `native_minimatch_ast.zig`: `572288D2EA9EC9AB00D4EA8A515C0B7A3D31F961E5229E7062EECA231AC85801`

The existing minimatch namespace remains separate and unqualified. The new
adapter never passes Node options into that restricted public namespace and
never advertises the full versions as interchangeable.

## Authored behavior and admitted scope

The leaf authors Node's synchronous work stack, per-path pattern-position cache,
nullable metadata cache, directory cache, insertion-ordered result deduplication,
literal-component fast path, globstar transitions, terminal directory handling
and symlink-position state. Pattern positions past the end are retained because
they affect the original suffix cache keys and symlink admission. Directory
iteration is ordered like the existing native readdir provider: native Windows
enumeration and sorted raw names on POSIX. The output remains unsorted, as for
the original glob; the actual Pi caller performs its own final sort.

Admission is one string pattern and default string results, with optional string
cwd. Components may be literal text, `*`, `?` or `**`, including ordinary relative
or absolute roots, leading `./`, explicit hidden components and trailing directory
slashes. Backslashes follow Node's windowsPathsNoEscape separator policy on all
platforms. Nonmagic components remain exact strings under nocaseMagicOnly.
Missing metadata and unreadable directories follow the original empty traversal
step; native allocation, cancellation and explicit resource failures propagate.
There is no invented empty-result fallback for unsupported patterns or options.

The adapter explicitly rejects braces, character classes, extglobs, leading
`!`/`#`, UNC special roots, parent/interior-dot components and the optimization2
special `./` form. Full optimization2 normalization, full 10.1.2 matcher closure,
pattern arrays, URL cwd, exclude callbacks/patterns, withFileTypes and async glob
remain missing. Public Dirent/Stats prototype-hook equivalence and exact
invalid-input error descriptors are also outside this leaf: native metadata is
used directly. These are material broader Node glob gaps, not certified aliases.

Resource limits reject rather than truncate: 64KiB encoded pattern bytes,
512 raw components, 100,000 enumerated entries and 1,000,000 traversal steps,
plus the actual Engine interruption budget. These limits are implementation
boundaries and do not claim equivalence to every original Node resource limit.

## Prepared original controls and qualification boundary

`src/extensions/fixtures/node24-glob-package.input.json` supplies an actual
filesystem fixture plan and 25 original subject cases, including nested literal
matches, globstar, hidden paths, absent paths, absolute patterns, platform case,
trailing directories and real symlink/broken-link/loop behavior. The separate
eight broader-reference-only inputs record unsupported grammar without calling
it covered. Symlinks must be genuinely created; a failed fixture setup is a
failed/blocked control, never an omitted or fabricated link observation.

The `.input.mjs` invokes real `fs.globSync` and actual Pi `expandPackageGlob`.
The future harness must load the pinned full original PackageManager module and
expose that private helper, or select it through an actual class caller. It must
also create/freeze the real fixture tree and preserve complete runtime/compiler
authorities and original expected bytes. No runnable harness, expected JSON,
reference pass or native pass is claimed in this checkpoint.

Only source inspection, hashes and Git whitespace checks occurred. No Node,
reference execution, formatter, AST, generator, compile or native job ran. No
Engine/shared Scope/C change, default module registration or activation occurs.
Original package/Git/cloud-sync fixtures, goldens and evidence stay unchanged.
