# Node package reader source composition

This unit ports the consumed Node v24.13.0 `readPackage` and
`getNearestParentPackageJSON` bodies over the actual installed `node:path`
object and the Engine's genuine `std.Io`. The native binding performs its own
Windows namespace conversion and component traversal. It keeps the C++
parsed-file cache in native storage, including cached read failures and
uncached invalid JSON, while the two Source wrapper caches remain real
SafeMaps with shared package-object identity.

The private SafeMap owner follows the retained primordial probe order,
including the second first-iterator call and shared captured next function.
Its local class adapter and cache publication finish ownership cleanup before
publishing the completed value. Shared Node Scope, ModuleCallable, VM, and
SDK completion implementations are prerequisites supplied by the integrated
tree and are not included in this source unit.

## Declared qualification entry point

| Field | Value |
| --- | --- |
| Install-only target | `build-native-node-package-reader` |
| Root | `src/native_node_package_reader_test.zig` |
| Filter | `native package` |
| Installed executable | `native-node-package-reader.exe` on Windows |
| Authored declarations | 10 actual VM/file controls plus 11 imported native path/field/allocation controls |
| Discovered metadata | Not collected by this source unit |
| Runtime | Not executed by this source unit |

The actual controls use Engine, the real Node path module, native SafeMap
construction, and owned temporary files. They do not spawn children.
They cover probe order, failed-owner publication/retry and reentry selection, mutable public path
reads, native read and invalid-JSON caching, permission checks, lazy fields,
and nearest-result identity. Native controls cover namespace spelling,
component boundaries, duplicate JSON fields, raw imports/exports, and
allocation cleanup.

## Retained source

The authority files are copied from Node v24.13.0:
`lib/internal/modules/package_json_reader.js`,
`lib/internal/per_context/primordials.js`,
`src/node_modules.cc`, `src/node_modules.h`, `src/path.cc`,
`src/util.cc`, and `src/util-inl.h`.
Their upstream base is
https://github.com/nodejs/node/tree/v24.13.0 .
The Node MIT license excerpt accompanies them; the full retained Node
license is also present in
`../node-commonjs-internal-builtin-require-sourceonly-20261018/authority/LICENSE.txt`.

The MSVC filesystem and Node environment excerpts include their exact URLs,
response-body hashes, and excerpt offsets in
`authority/package-path-excerpt-provenance.json`.
The MSVC reference is the pinned `vs-2022-17.14` header used to explain native
Windows root, parent, and generic-path spelling.

This unit is a prerequisite for the unfinished actual CommonJS filesystem
assembler and classic realpath work. It makes no claim that the full Module,
ESM/Jiti, public CLI, or complete application graph is qualified.
