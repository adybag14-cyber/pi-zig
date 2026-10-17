# Genuine SDK bootstrap/native target — SOURCE preparation

Base65dc640634d6bb1ae3ed4fba8a6b17eb50ab83b7. No job, parser, compiler, Node
capture, runtime execution or Main edit occurred. This packet is not a complete
application, fresh build, runtime or release qualification.

The actual available bootstrap installs existing native timers, process, path,
URL, filesystem/promises, CommonJS, console, text, crypto randomness and Web
fetch/Body leaves, then the new consumed OS module. Nothing invokes a Node/TS
production host. Environment and arguments come from the actual native owner.
The tests own an isolated environment/Engine and only write their real temporary
directory. No host environment is reset, and no command/network transport is run.

managerImports projects the two actual SDK manager constructors from the existing
native manager implementations into a private cached record. It never selects
the legacy AgentSession, ModelRuntime or DefaultResourceLoader exports. The
original install/class body remains unchanged. This projection is a fresh Engine
bootstrap operation: if an older SDK owner already initialized the class without
this cached record, it fails instead of reading mutable prototype.constructor.
Any failed partial bootstrap requires Engine disposal; this unit does not claim
same-Engine retry for existing one-shot SDK installer failures.

The application bootstrap creates the actual Agent namespace, abort functions,
timings and manager imports, then forwards actual registered platform values and
the completed module inputs to native_sdk_application_assembly. It does not
manufacture the missing resource-loader/TypeBox/shell/auth/config/HTTP graphs.
The supplied Completed values must come from those actual module owners.

## Actual OS implementation

Official Node24.14 source/license and libuv source/license are retained in
authority/. The consumed profile supplies homedir, release, type, version,
platform, arch, EOL/devNull, actual platform signal constants and the existing
real tmpdir implementation, with canonical default ESM/CJS objects.
It is not the complete Node os namespace. Other OS exports remain absent rather
than reporting invented host metadata.

homedir binds the actual installed process environment record; own string data
is the admitted native environment representation. Windows entries are matched
case-insensitively; ambiguous duplicate case aliases, accessors/nonstring values
fail closed. Full process.env exotic mutation/proxy/coercion parity is a separate
native-process provider gate, not silently implemented by os. This callback does
not read guest-replaced global process or call an environment getter as libuv.

Windows uses USERPROFILE when present: fewer than three UTF8 bytes is ENOENT,
including empty, and the actual Node Windows260-byte result buffer bound is
preserved. Only missing USERPROFILE enters OpenProcessToken(TOKEN_READ), sized
GetUserProfileDirectoryW and GetUserNameW, with owned token close and buffer free
on every branch. POSIX preserves present empty HOME; absence uses actual
geteuid/getpwuid_r with EINTR retry/ERANGE growth. No fake home directory is used.
Windows native errors use libuv's actual Windows UV errno values; POSIX uses
native errno values. The native error context preserves Node's ordered ordinary
Set calls (including inherited setters and ordinary false returns) before the
actual existing SystemError class constructs its info/accessors/message.

release is captured from actual RtlGetVersion once per module creation on Windows,
formatted major.minor.build as libuv, or from real uname on POSIX. No version
constant is substituted. platform/arch read the live process bindings as Source;
the functions include their real Symbol.toPrimitive behavior. Streams owns TTY
capabilities and can consume this actual os.release function.

Windows version uses the real registry ProductName, native build-based Windows11
label adjustment and actual service-pack text. Missing/invalid/unrepresentable
registry data fails explicitly instead of fabricating metadata; full uncommon
uv_os_uname failure parity remains unqualified. POSIX type/version/release use
real uname. Signal numbers come from official Windows/MSVC/libuv definitions or
the actual POSIX signal.h macros. Each signal property and preventExtensions
implement the consumed frozen signal table; no missing errno/priority/dlopen
constants are invented. Only constants.signals is supplied in this bounded unit.

Direct native externs are Zig declarations only; no C/Engine file changes. The
test target links advapi32/userenv on Windows. The additive fromContext function
reuses the existing genuine SystemError constructor. The same helper's private
cache key now uses its static module constant: the previous allocated key was
not in native_module_names and Engine teardown could not free it.

## Meaningful current tests and strict remaining gates

build-native-sdk-application-bootstrap-artifact compiles/installs the actual test
root using current QuickJS/ICU/Photon/SQLite/catalog and real TreeSitter bindings.
test-native-sdk-application-bootstrap is an explicit separate runtime step; neither
step has run. Root alone may grant resource-admitted supervised execution.

Six new actual behavior tests cover physical sync/promise file IO and path/URL,
real timers/process; canonical AI import identity across real GC; actual manager
tree/settings behavior; native account fallback/cached release; and platform empty
home behavior with genuine SystemError fields; and exact reason propagation from
an inherited native error-context setter. The last control is Windows-specific
and explicitly skipped on POSIX because empty HOME is valid there.
std.testing.allocator checks their
Engine/root teardown. The historical Original64 registry target remains separate:
its original setup supplies model/resource collaborators. It is not counted as a
genuine whole-application positive. Its original assertions/inputs/references and
GC/allocation tests remain unchanged. Replacing that setup with the actual
completed application graph is a required future gate, not a skipped pass.
Actual metadata count has not been queried and is not guessed.

verifyFullApplication performs the unchanged complete Source27 factory comparison
and Source166 prototype comparison over the actual application graph. A typed
unknown-input anchor retains this genuine body for typecheck/link; no replacement
Completed input is constructed. Its runtime invocation is STILL BLOCKED on the
actual completed graph below, and the six available tests are not a full factory
or current-app pass. This missing positive runtime invocation remains required.

- Completed Agent: prompt/continue genuine AF successor belongs to API; the five
  other async methods/run executor remain explicit existing flow/prototype gaps.
- ResourceLoader requires completed PackageManager, chalk, SettingsManager and
  actual loadExtensionFromFactory/loadExtensionsCached, not SDK.Kind fallbacks.
- Package transport needs genuine child_process streams/exec methods; completed
  patterns/semver/Git/ignore inputs and physical transport gates remain required.
- Operators owns actual jiti/queued-import/lazy modules, virtual namespaces and
  loader rejection DATA handling. MCP/exec inputs and nine actual virtual modules
  must be genuine; no empty namespace or fake positive callback is supplied.
- Actual chalk consumed behavior and TypeBox completed graph remain required.
- Configuration can now consume real OS home; shell/config-value/auth/management
  HTTP need their actual child-process/transport namespace composition.

The new Node caller node-os-consumed.input.mjs uses actual builtin os/path/process
and records raw behavior. The same bytes are retained under fixtures for the
native comparator. Missing-account and temporary-directory output retains the
actual raw path with type/absolute/nonempty observations; release is actual host
data. A later capture/comparison must bind matching actual host/environment data,
not fabricate an expected path/version or use a type-only success. The
owner must capture it under a separate bounded dedicated Node grant. Expected
data is ABSENT. Original Source27/Original64/Source166 and all historical goldens
remain unchanged. Pending-event/host-OOM/full-graph GC qualification is not claimed
by these unrun entrypoints or by a later compile-only result.

