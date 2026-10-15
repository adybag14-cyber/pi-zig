This is a source-only production AgentSessionRuntime checkpoint based on Root
`4e128e2c8f33f5ef7aa299475adfe4b1e8e84f2b`. The authority is the intact upstream
`4954d760504c11df9b2cbdc040346107b6a8153d`, specifically
`packages/coding-agent/src/core/agent-session-runtime.ts`, `session-cwd.ts`, and
the actual `emitSessionShutdownEvent` helper in `extensions/runner.ts`.

The new native module creates a real ordinary constructor, its five getters and
twelve methods, its two actual error classes, and the working-directory and
shutdown helpers. The seven own fields and prototype descriptors follow Source
order. Replacement retains the original abort/shutdown/invalidation/disposal,
factory, apply, setup, rebind and withSession ordering. Raw caller reasons are
preserved. Each pending operation retains the ordinary receiver and explicit
imports through the existing native asynchronous owner mechanism.

`create(engine, actualImports)` returns a namespace including AgentSessionRuntime
and assertSessionCwdExists, directly suitable for the actual production factory's
import slots. Its explicit function dependencies are SessionManager, resolvePath,
existsSync, mkdirSync, copyFileSync, basename, join, parse and resolve; it also
retains constants.COPYFILE_EXCL. Validating that these values are callable does
not establish their production identity. The caller must supply the actual
shared application collaborators.

`importFileCopyBindings(engine)` supplies the narrow actual native dependency
needed by importFromJsonl: copying resolved string paths with exclusive flag1,
using Zig-owned filesystem I/O, with Node-style filesystem error properties. It
does not advertise complete node:fs copyFileSync compatibility. This keeps the
class's dependency explicit without modifying shared filesystem modules.

The shared fixture prepares34 observations against full real Source factory,
services, AgentSession, SessionManager, SettingsManager, ModelRuntime and
extension-runner objects. Caller extension handlers, credentials and a native
provider are legitimate explicit factory inputs. No session class body, service
factory or runtime lifecycle body is replaced. Provider completion must not be
requested. Cases exercise descriptors and field order, strict cancellation,
callback failures and raw identity, shutdown/invalidation order, captured apply
and callback getters, replacement setup, persisted/in-memory forks, cwd checks,
exclusive imports and collision suffixes, and final disposal.

The capture driver direct-imports original4954. The owner script requires a Root
LIGHT slot, fresh2GiB admission, a256MiB Node heap, a300s process deadline, exact
PID/executable/start/argv ownership, full candidate/vendor, Source1970,
dependencies31064, Node1774, Zig compiler19546 and controls pre/post hashes,
declared84 package absences, path-inventory checks, and independent child absence.
It accepts a golden only after the genuine run passes and its full posthash is
unchanged. No expected runtime observations have been fabricated.

The native replay entry point requires the actual ordinary production session
constructor and actual factory imports supplied by the production assembler. It
installs the new class into the actual production factory and compares every
captured Source row. No fake default collaborator graph or legacy SDK runtime is
provided. No standalone executable test or build target is claimed here.

Genuine Source34 passed at unchanged published candidate
`fb97f56d340a031c0e28d0b59a83c57d9d552897` under Root LIGHT6. NodePID76072
completed with exit0; fullpost completed2026-10-15T23:19:53.1245868Z with
candidate7259/Source1970/runtime31064/Node1774/compiler19546/controls11 hashes
unchanged. Candidate, Source, runtime, Node and compiler pathsets,84 declared
absences and caller identities also had zero drift. The exact owned child was
independently absent at23:19:53.5145466Z, then the genuine fixture was accepted.
Its SHA256 is
`B0E79FC2D40DA6CF2E8CC6B39558C394ABB969E080E169E02B75E4F5914C59CE`.

The published owner script originally allowed slot IDs1..4. A separately sealed
external control wrapper permitted LIGHT6 and added all runtime/Node/compiler
pathset checks. The original published input, capture driver, native class and
candidate were unchanged during the run. That wrapper, original caller bytes,
strict input seals, exact owner/stdout/stderr, fullprehash/posthash, observed
module log, actual metadata audit and original owned sandbox files are retained
in source34-qualified-evidence.zip. All46 archive entries were independently
checked by size and SHA. Verify-Source34.ps1 verifies the portable retained proof.

PI_PACKAGE_DIR was actually unset. The intact original config resolved
`packages/coding-agent/package.json` from Source4954, SHA256
`83C3BB7619F590C213CC96A24216EB29A819A3EF6DC548607CC037ED276E8DC5`;
both its package version and the cached actual config.VERSION were1.3.0. This is
ordinary frozen metadata scope, not default production runtime or application
qualification; no controlled historical1.1 package root was supplied.

The fixture's oldActive boolean probes whether runner.createContext() constructs
a context. Original Source permits that construction after invalidation and
checks stale ownership through lazy context access and actions. The exact
observed true values are retained. They do not prove stale contexts remain
usable, and the Source34 proof does not claim a complete stale-context gate.

Current state: genuine Source34 captured and retained; native class and replay
remain uncompiled and unexecuted. There is no native qualification, default
application wiring, full Pi standalone claim, hosted six-profile result, or
public activation in this checkpoint.
