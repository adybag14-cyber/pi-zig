The pinned DefaultPackageManager has 97 class declarations, including its
constructor and private methods. package-manager-method-inventory.json records
their source order and the existing scoped native helpers. The actual Source
module is byte-identical in the inspected 0fb source tree. Existing helpers do
not constitute a complete constructor: discovery, filtering, installation and
update bodies remain required before any assembly can select this class.

native_sdk_package_transport adds the original five command transport bodies
and getEnv. Its install function requires actual process, readFileSync,
spawnProcess, spawnProcessSync and isStdoutTakenOver functions. The methods
construct actual Source explicit Promises, register child/stream listeners,
retain raw event errors, collect actual output, clear actual timeout handles
and preserve code/signal/timeout error messages. No process is launched during
assembly. These methods are source-only and remain unselected.

The filesystem lane owns node:child_process and the cross-spawn utility
namespace. Its remaining real stream and inherited-stdio dependencies stay
explicit. Package transport must consume genuine stream objects and route
inherited stdio to the frontend rather than a worker protocol channel. It must
not substitute a fake Readable or a success result.

The next closure consists of source parsing/package-manager command selection,
manifest/default/autoload discovery with real ignore/minimatch/semver/Git URL
helpers, then installation/update orchestration. Existing accumulator, identity,
path and resolver modules are reusable after their own exact native gates and
genuine async migration; the current resolver's prototype tag is insufficient.

For extension loading, the existing GC-owned cwd/generation factory cache,
ordinary runtime, MCP registry/config, source-info and event-bus bodies can be
reused. Missing pieces are the complete transactional createExtensionAPI,
createExtension/initializeExtension, loadExtension/loadExtensionsInternal and
the native guest-module importer. Importing must use the native worker's
resolver and extension-input transpiler, with cache invalidation and Source
default-export rules. The standalone core must not call the legacy Node bridge
or install jiti as its host implementation. Scoped chalk yellow rendering and
execCommand require actual dependencies and source behavior as well.

Source53, Source44 and Source15 retained packets and physical fixtures remain
unchanged. No formatter, AST, compiler, native runtime or new Source capture
has run for this transport checkpoint during Root's TypeBox lease. Default
selection remains uncalled.
