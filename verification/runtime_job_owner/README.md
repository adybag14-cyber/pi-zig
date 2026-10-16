# Verification-only runtime Job Object owner: controller source draft

This leaf is isolated from product/build.zig. It now contains a standalone
build.zig and main.zig with explicit supervisor/worker modes, plus the actual
supervisor, worker, transport and read-only final-sealer composition. The source
has not been compiled, parsed through Zig, run or qualified. The input/control
packet and native-only fixture implementations remain unfinished.
Early review of61c15f31 found the create-then-assign suspended-worker orphan
window. That preserved worker API is inadmissible for execution. Peer closed exact
v3 design41C8E303ABF6A85471EEAF8BFDB7345C0A89BE6B8DCFA869EF7F444C2BD85711;
this successor implements creation-time JOB_LIST with no two-step fallback.
The complete successor requires independent implementation review.
Do not compile, format through Zig, run controls, invoke Node/npm or perform a
reproduction without Root's separate grants. It is uncompiled source and does
not establish runtime authority. Original preparation controls12BA, design643CEE
and their negative/review receipts remain immutable.

Authority for source authoring: Root conditional instruction after peer confirmed
DESIGN-v3 SHA41C8E303ABF6A85471EEAF8BFDB7345C0A89BE6B8DCFA869EF7F444C2BD85711.
The source branch starts at ignore7d9d7c224dc9d560a5e46541bf8df67e4b93b114.
No product C/Engine/shared owner is modified or imported as a safety shortcut.

Implemented source modules:

- win32.zig: direct Windows x86_64 ABI declarations and static layout assertions;
  no OpenJobObject, taskkill, TerminateThread or breakaway declaration/use.
- deadline.zig: monotonic D900/C890/worker650 boundaries, full300-second Node
  budget, final240 beginning at early retirement (including its10seconds),
  fresh16GiB and4GiB-pressure checks. Every completion remains deadline-bound.
- job.zig: fresh unnamed noninheritable job, queried8/4GiB/64 limits, owned port,
  full kernel membership/accounting, confined termination and explicit zero.
- command.zig: typed argv serialization/roundtrip and explicit sorted Unicode
  environment block; no inherited environment construction.
- process.zig: preallocated PROCESS_INFORMATION retention, atomic JOB_LIST
  suspended worker creation, authenticated inherited-Node role, supervisor-pull
  Node handle, acknowledgement guard and exit-record-before-reference-release.
  No AssignProcessToJobObject or TerminateProcess worker fallback exists.
- security.zig: current-user/System restricted ACL and OS nonce for local pipes.
- overlapped.zig: persistent operation state, checked64KiB buffers,8MiB caps,
  output hash/counters and cancellation that requires actual completion.
- metadata.zig: native COM/WMI thread with bounded result storage, local exact-PID
  query and exact parent/live command/UTC/image binding; timed-out thread state
  must remain alive and has no job-control authority. Requests are one-shot;
  completion after the2-second budget stays a timeout even if already finished.
- files.zig / manifest.zig: physical-path/open-file identity, streaming SHA256/
  SHA512, bounded inventory input and complete file/missing/extra/reparse records.
- PROSPECTIVE-TOOLS.md: explicit1774 historical scope and an unreviewed restricted
  PATH/npm shim closure proposal. No wrapper/copy was installed.
- pipes.zig / persistence.zig / protocol.zig: private restricted overlapped
  endpoints, single-producer bounded receipt queue on a separate flush thread,
  and fixed nonce/sequence-bound lifecycle frames. Zero-byte successful pipe
  reads rearm; they do not establish EOF.
- grant.zig / admission.zig: new exact native-owner scope, grant/control/lease
  hashes and read-only native inventory. Own-attempt exclusions require exact
  supervisor identity or exact owned-job membership.
- cache.zig / absence.zig / junctions.zig:365pins/281required/initial558 cache
  checks, contained workspace junction operations and84absences resolved only
  through the checked16alias plan. Broken unknown links are never called absent.
- tools.zig: original1774 scope split into pinned Node plus full1773 npm subtree,
  separately released original1838 full inventory, prospective restricted
  two-file PATH inventory and separately reviewed cmd. All tooling checks remain
  unexecuted source; additional Node authority is not runtime restoration.

The concrete controller additions are:

- common/transport: pending-operation-only OS wait sets, bounded120-byte frames,
  authenticated ACK/abort reception, atomic independently running hard watchdog.
- supervisor: atomic JOB_LIST suspended worker creation, independent worker and
  Node WMI/kernel/argv/parent/UTC binding, supervisor-pull Node handle, fresh
  admission before launch/resume, independent300-second Node deadline, bounded
  kernel member/accounting snapshots and honest advisory/partial metadata.
- worker/phase: full preflight, exact offline CI/build invocation and sanitized
  environment, suspended Node handoff/ACK before resume, exact28250 CI output
  comparison before hidden-lock transfer, and separate16-link preparation.
- storage/receipts/inputs/seal_set: fixed256MiB storage with separately reclaimed
  scratch; eleven independent full source/tool/cache/output/link/absence checks,
  complete physical namespace/hash/difference evidence and mandatory positive
  assertions. Both phase roots are attempted after a readable first-tree failure.
- Dedicated supervisor final thread after job retirement, with its240-second
  allowance measured from early retirement. Unfinished final coverage stays
  unknown. Positive publication also requires pipe/metadata retirement, output
  flushes and closed handles, a flushed/stopped/closed ledger and owned job close.
- Fresh atomic terminal publication has a separate bounded quota. Errors before
  a complete final seal can produce a negative/unknown-coverage receipt; blocked
  startup/persistence/publication ultimately exits at the hard watchdog without
  fabricating a terminal receipt or kernel zero.

Concrete completion gates remaining:

1. Independent review of this whole controller composition and its negative
   paths, including API/ABI and shared-deadline/I/O lifetime checks. No compiler
   acceptance or working executable is currently claimed.
2. Prepare a fresh exact phase-input/control manifest and the separately reviewed
   private tool closure. No source shim was installed. An external Root receipt
   must bind launch/terminal or timeout/absence and cannot infer a missing owner
   receipt as success.
3. Author native-only fixture executables for CONTROLS.md, then receive distinct
   Root compilation and execution grants. The control table is a specification,
   not implemented controls or test results.
4. Execute those controls on the exact compiled owner and subsequently obtain a
   separate original19cb CI/build reproduction grant. Preserve every negative.

HOSTED-REPRODUCTION-ASSESSMENT.md records a separately reviewed hosted Windows
option. It does not install or publish a workflow and does not replace this work.

No launchable stub will be supplied as a completed owner. Complete source review,
an explicit compilation grant, owned native controls and a later reproduction
grant are distinct requirements. Runtime remains recovery_pending.
