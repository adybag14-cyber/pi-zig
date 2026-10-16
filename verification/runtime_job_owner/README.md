# Verification-only runtime Job Object owner: source implementation in progress

This leaf is isolated from product/build.zig and has no executable entry point.
Early review of61c15f31 found the create-then-assign suspended-worker orphan
window. That preserved worker API is inadmissible for execution. Peer closed exact
v3 design41C8E303ABF6A85471EEAF8BFDB7345C0A89BE6B8DCFA869EF7F444C2BD85711;
this successor implements creation-time JOB_LIST with no two-step fallback.
The successor itself still requires implementation review and has no entrypoint.
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
- deadline.zig: monotonic D-10 cutoff, full300-second Node budget and shared
  retirement end bounded by D; fresh16GiB and4GiB-pressure checks.
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

Remaining implementation, not substituted by the old PowerShell owners:

1. Complete protocol transport integration, receipt encoders/atomic terminal
   publication and the external-watchdog receipt contract.
2. Full source/tool/cache/link/absence sealing composition, mutable cache diffs,
   prospective tool closure and reviewed workspace junction/output receipts.
3. Supervisor timing loop and worker CI/build state machines, with every failure
   retained and all independent final comparisons asserted.
4. Native-only failure fixtures and source review of the complete composition.

No launchable stub will be supplied as a completed owner. Complete source review,
an explicit compilation grant, owned native controls and a later reproduction
grant are distinct requirements. Runtime remains recovery_pending.
