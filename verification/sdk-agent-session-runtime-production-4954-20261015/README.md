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

Current state: formatted and statically reviewed; genuine Source34 capture has
not run, and the new native module and replay have not compiled or run. There is
no native qualification, default application wiring, full Pi standalone claim,
hosted six-profile result, or public activation in this checkpoint.
