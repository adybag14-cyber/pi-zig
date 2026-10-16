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
