# Verification-only runtime Job Object owner: source implementation in progress

This leaf is isolated from product/build.zig and has no executable entry point.
Do not compile, format through Zig, run controls, invoke Node/npm or perform a
reproduction without Root's separate grants. It is uncompiled source and does
not establish runtime authority. Original preparation controls12BA, design643CEE
and their negative/review receipts remain immutable.

Authority for source authoring: Root conditional instruction after peer confirmed
DESIGN-v2 SHA5ECF771825223272540DD62BD5205C38EA425F62B61A5F7B87C3E203DBAEDC20.
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
- process.zig: preallocated PROCESS_INFORMATION retention, suspended worker
  assignment, supervisor-pull Node handle, acknowledgement guard, direct-handle
  unassigned cleanup and exit-record-before-reference-release primitives.
- security.zig: current-user/System restricted ACL and OS nonce for local pipes.
- overlapped.zig: persistent operation state, checked64KiB buffers,8MiB caps,
  output hash/counters and cancellation that requires actual completion.
- metadata.zig: native COM/WMI thread with bounded result storage, local exact-PID
  query and exact parent/live command/UTC/image binding; timed-out thread state
  must remain alive and has no job-control authority.
- files.zig / manifest.zig: physical-path/open-file identity, streaming SHA256/
  SHA512, bounded inventory input and complete file/missing/extra/reparse records.
- PROSPECTIVE-TOOLS.md: explicit1774 historical scope and an unreviewed restricted
  PATH/npm shim closure proposal. No wrapper/copy was installed.

Remaining implementation, not substituted by the old PowerShell owners:

1. Private overlapped pipe construction and nonce/sequence protocol, bounded
   persistence worker and external-watchdog receipt contract.
2. Native grant/control checks; exact source/cache/tools/link/absence sealing and
   prospective control-tool closure; 16 native junction operations and receipts.
3. Supervisor timing loop and worker CI/build state machines, with every failure
   retained and all independent final comparisons asserted.
4. Native-only failure fixtures and source review of the complete composition.

No launchable stub will be supplied as a completed owner. Complete source review,
an explicit compilation grant, owned native controls and a later reproduction
grant are distinct requirements. Runtime remains recovery_pending.
