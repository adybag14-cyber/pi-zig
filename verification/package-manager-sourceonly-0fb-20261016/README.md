# DefaultPackageManager source-only closure

Base `07609651754f498de1713389f720711fdad93033`; source authority remains
`0fbdbd3f8ab1876ac260c0f08226a400759323b8`. The complete 2,766-line original
package-manager.ts was read. Its SHA256 is
`61BB2F0B434B0F5C48AB6BFACD9DFF1D99084320EECF695755CD32BD88099310`.

The historical inventory remains unchanged. It lists 97 declarations but its
pattern omitted generic `private async runWithConcurrency<T>`. The supplemental
declaration-order98.json and native_sdk_package_declaration_order.zig preserve
all 98 actual declarations, including constructor and the generic method in
its original position after runGitRemoteCommand.

This first source-only cluster adds 40 concrete class methods:

- package_commands: five ordinary command-selection/argument methods and four
  genuine async npm orchestration methods. Actual command execution remains on
  the unchanged real transport methods owned by the extension-loader lane.
- package_settings: eleven ordinary settings/matching/listing/progress methods
  and genuine async withProgress. Start is outside its catch boundary; complete
  failure enters error progress; errors retain original rejection identity.
- package_storage: sixteen storage/layout/cache/manifest setup methods requiring
  real filesystem, paths, SHA256, cloud-sync path and text imports.
- package_source: parseSource and parseNpmSpec, with actual semver, path and Git
  parser imports required. No approximate semver/Git parser is substituted.
- package_concurrency: the actual generic async method, shared private cursor,
  genuine worker Await boundaries, live Array.from/Promise.all, ordered sparse
  results, raw failfast rejection and live remaining workers. tasks[index]() has
  the tasks array as its call receiver. No substitute Promise batch is used.

Combined with existing construction/progress/accumulator/identity/path/resolve/
extension-source/transport bodies, the static declaration coverage is 61/98.
readiness.json explicitly lists the 37 remaining declarations. This is not a
complete assembled class and no default namespace is selected.

Required concrete pure collaborators remain ignore/add/ignores, minimatch,
semver valid/validRange/satisfies/gt/maxSatisfying/rcompare, and hosted-git-info
plus the complete parseGitUrl wrapper. Actual filesystem glob/Dirent/stat,
crypto/path/environment and child-stream/frontend stdio identity remain
explicit platform dependencies. Caller-shape validation is not provenance.

The new prepared inputs describe 34 leaf and nine concurrency controls. Their
observer imports the actual original class and SettingsManager and the actual
Node util async-brand authority. No original fixture or source file changed;
no source run occurred and no expected output exists. The concurrency controls
use caller-provided task gates, including reversed settlement and continued
inflight work after outer rejection. They invoke no package commands.

No Zig formatter, AST checker, compiler, native runtime, Node/source capture or
C build has run for this task. Root source files and the extension lane's five
command transport/API/initializer/cache/import modules remain untouched.
Whitespace checks only were performed. All qualification flags remain false.

Independent static review found an invented empty-spec guard in the first
installNpmBatch draft. The successor removes it: the actual Source always
resolves storage, ensures the npm project and awaits the real command. A
separate prepared physical/offline-npm supplement requires actual execution,
retains the original method identities through transparent getter probes,
and supplies no successful command callback. It is unrun and adds one control
to the prepared 43, without changing their original bytes.

The successor also preserves exact fresh private OOM reasons before native
error classification in synchronous withProgress catches and the storage
catch boundaries. Completion progress now takes its own fresh generation;
ordinary/stale-tag/lookalike reasons retain Source catch behavior. These are
source-only corrections; they have no inherited native qualification.

Further Source-order review corrections retain the outer class-method lookup
before evaluating nested arguments, preserve uninstallNpm's explicit live
Array.prototype.push, and separate two different JSON.parse/readFile orders.
getInstalledNpmVersion reads content before resolving JSON.parse;
hasMissingGitDependencies resolves JSON.parse before its nested readFileSync.
Four prepared transparent getter/real-file controls and a real uninstall push
control supplement the empty batch. There are now 43 original plus six new
prepared controls, with no expected output. The physical supplement requires
actual frozen offline npm execution and a fresh owned directory; no command
success result or filesystem callback is fabricated.

The next source-only cluster supplies the original twelve free pattern-helper
bodies over required real minimatch/path imports, plus ten class resource/
filter/manifest callers over required real discovery/manifest helpers. It does
not implement minimatch/ignore by approximation and does not select a partial
class. Native discovery helpers and addAutoDiscoveredResources are still
required, along with install/update orchestration and full assembly.

The subsequent source-only cluster now authors those discovery and class
orchestration bodies as well: fifteen filesystem discovery/ignore-rule/ancestor/
glob helpers, addAutoDiscoveredResources, public install/remove/persist, npm/Git
version checks, configured batching/availability, clone/ref/dependency repair,
and resolvePackageSources with a retained real iterator and genuine async
per-entry missing callback. Existing resolve and resolveExtensionSources reuse
their actual bodies but replace the old native Promise owner/prototype tag
with genuine native AsyncFunction entry/Await/return.

Static coverage now includes all 98 actual class declarations. The new assembly
installs them privately, copies their descriptors in exact supplemental source
order and rejects missing functions or a wrong intrinsic async brand. Actual
Source has 33 async class methods. The assembly exports only its completed
ordinary constructor and the actual getExtensionTempFolder function; it
performs no application/default selection. This count is source-body coverage,
not semantic/runtime qualification.

Concrete native ignore, minimatch, semver and hosted-git-info/complete Git URL
implementations are still required external collaborators. Real filesystem
glob/Dirent/crypto/path/child-process/frontend-stdio interfaces need their own
qualification. No empty matcher, parser, transport or resource result is
provided to construct the graph. Function-shape checks do not prove provenance.

A full class descriptor/field/async-brand control is prepared separately,
bringing the prepared case count to 50 (43 original, six physical/getter,
one complete-class case). No expected rows or successful execution exist.
No formatter, AST, compiler, native, Source or C jobs were run. The package
constructor, collaborators, ownership and complete application remain unqualified.
