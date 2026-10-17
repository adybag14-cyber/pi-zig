This is a source-only Node24.14.0 CommonJS seam checkpoint, based on Root
8b36501abcc98563e7ba78c7c417fb024d672361. It is not selected by commonjs.install,
node:module, the worker, the SDK assembler or the default extension factory.
No compiler, Zig AST/formatter, Node, native job or generator has run here.

The authority is official Node commit f657bb8ed86365ff3fdbe32e27563e778b41486a.
The original loader.js/helpers.js and provenance are already retained under
verification/node-module-constructor-sourceonly-20261016/authority. Their exact
hashes are inventoried in prepared.json. Node's MIT license is retained there.

The new Zig bodies implement:

- makeRequireFunction's real ordinary require/resolve/paths functions over a
  genuine Module parent. resolve forwards its actual second options argument
  to Module._resolveFilename, and require ignores additional arguments.
- _resolveLookupPaths, including builtin null, private global-path identity,
  parent-path copying and relative lookup; options.paths validation, repeated
  reads, real new Module('', null), live Module methods and ordered deduplication.
- _initPaths with its private modulePaths replacement and distinct public
  globalPaths clone, real platform rules and explicitly supplied safeGetenv.
- _resolveFilename, _findPath, tryFile/tryExtensions/tryPackage and self/exports
  wrappers, preserving raw return values, cache/error paths and live ordering.
- the actual .js/.json/.node handler bodies. Registry creation requires real
  loader/format/package/error inputs and genuine process.dlopen; a missing NAPI
  dependency is not represented by a published handler that always fails.
- builtin classification and construction of the actual frozen builtinModules
  array from a REQUIRED original ordered Node id table. No id table is present
  yet, no registry of implemented modules is substituted, and nothing publishes
  this as an already-complete node:module namespace.

All ordinary functions use the existing real native_node_module_callable, with
VM-traced function-data roots and raw completion. No AsyncFunction or additional
Promise adoption is introduced. Native loops check the existing interruption
budget, retain their values and release temporary per-iteration roots. Source
ordinary catches retain the first raw reason; actually pending uncatchable and
current-boundary private allocation failures bypass ordinary catch conversion.
Rejected data flags are not classified as an active pending fatal.

The following are required actual composition dependencies, not completed by
these bodies: the original builtin id table, private CJS initialization owner,
Node ERR_INVALID_ARG_TYPE/ERR_INVALID_ARG_VALUE constructors, Node24 package JSON
reader and ESM package imports/exports/finalization helpers, private filesystem
stat/realpath with their real caches, Module._load/require/_compile and private
first-parent access, and actual native-addon loading. The existing real path/fs,
Module constructor, VM callable and CommonJS cache are the intended authorities.
The Module constructor's private firstParents map needs a narrow read-only Zig
accessor for the final requireStack walk; no new Engine field is necessary.

The existing module_resolver and SourceLoader.normalizeRequire are not treated
as Node24 options-aware resolution. Their typed-extension/default-condition
policy and signatures differ. The separately owned import-meta-resolve4.2.0
port is not automatically declared equivalent to Node24's package helpers.
No Engine/C/H/commonjs/default-module file is changed by this checkpoint.

reference-input.mjs is an original Node caller prepared for Root's separate
bounded capture. It has no expected/observed output. It creates only original
owned fixture files. Every observable lookup list is collected only after this
dedicated child replaces HOME/USERPROFILE with contained synthetic paths,
deletes NODE_PATH and calls genuine Module._initPaths. Further NODE_PATH values
are contained synthetic paths. Prior values are held solely for child-local
restoration and never serialized. Actual Node version and execPath are the only
host metadata requested here. A controller/grant/actual source capture is absent.

This checkpoint does not establish compilation, metadata counts, native replay,
full Node/CommonJS behavior, Node addon compatibility, jiti factory behavior,
Graph2 behavior or default selection. Complete those actual dependency bodies,
obtain source review, capture the original controls under Root's grant, then
qualify the exact composition. Preserve existing authority packets and failures.
