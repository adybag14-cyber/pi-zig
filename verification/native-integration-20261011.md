# Native integration evidence, 11 October 2026

This records component qualification. The native implementation is incomplete;
retain the Node bridge and do not infer a release or native-default qualification.

The durable outcome-hook fix delegates VM work onto the actual owner thread
while its original transaction stays sealed. The worker's Session line and epoch
remain unchanged. Owner roots remain until that line is released; restoration
happens before acknowledgement, including failure and reentrant close.
The native Harness.open also retains the original scheduler-open await boundary.

At `40d5c797648393a5d65c4c966e86bab1dff95159`, Windows Debug passed
200/200 tests in 170 steps. This includes the unchanged compaction failure case,
the new sealed assembly regression, the complete retained Source55 UI corpus,
and the original command/live allocation ranges. Independent compiled coverage
verified 121 named cases, 130 actual compiled cases and complete execution.
All 3,969 source and 19,546 Zig tool inputs were unchanged after execution.
The private candidate separately passed the original Linux compaction case.

The SDK factory intake at `52a6a8147a519edc78b936483bd3d43497f19d98`
passed 133/133 composed tests and a separate 92/92 retained UI, input, owner,
and pure-helper job. Both ran the same 3,982 source inputs, with zero source or
tool drift. Independent coverage verified 124 named cases and 133 compiled
cases. All 55 retained Source UI cases and all original SDK UI/input allocation
checks passed. The preceding eight-target combined job hit its 300-second outer
deadline and is retained as incomplete evidence; no test deadline, assertion,
fixture, or allocation index was weakened for the subsequent bounded jobs.
The private SDK candidate's broader 265 executions and full lease/registry
allocation ranges remain separate evidence; they are not a full SDK claim.

The guarded-storage intake passed 140/140 Windows Debug tests in 158 steps:
134 in the shared artifact and six in the focused original storage guard gate.
Independent coverage verified 125 named cases and 134 compiled cases, with
complete command and live allocation ranges. All 3,985 source and 19,546 tool
inputs were unchanged. The unchanged original guard program retains backend
error identity, exempts StorageRequestError from Session failure, closes/reports
a fatal failure once, and discards a successful underway read after Session
failure. Private lifecycle/public-allocation, retention-pin and inflight suites
also passed; Root/platform qualification outside these counts remains separate.

Latest observed upstream is `04566631c2b51fb688486bc1f040f60d1518c126`.
Its immutable structural manifest records all 2,023 tracked paths. It adds
durable CodeMode replay, nested-call result details, and finished-outcome fencing
when the sandbox closes. The official reference offline build passed against
its own lockfile after official model hydration from the pinned catalog. All
2,023 original files, 22,218 dependencies, 43 hydrated files and 1,774 npm tool
files were unchanged; 2,865 generated dist files were pinned separately.
This reference build and tree capture do not qualify the native implementation
of those new features. Earlier immutable upstream manifests remain available.

Still required: complete Agent/AgentSession and SDK prompt/lifecycle behavior,
general fatal-rejection handling through Main, full terminal/editor parity,
native deterministic CodeMode start/replay and durable integration, exact-head
cross-platform/ReleaseSafe qualification, packaging and final release checks.

The subsequent three-path auth connection passed 190/190 Windows Debug tests:
135 shared cases and the 55 unchanged retained UI cases. The real public runner
lookup/call and intrinsic await preserve all eleven latest-Source auth traces;
the preceding 39 SDK queue cases remain intact. Independent coverage verified
126 named cases and 135 compiled cases, with complete command/live allocation
ranges. All 3,988 source and 19,546 tool inputs were unchanged. This qualifies
that prompt boundary only; complete before-agent results, loadout, message/image
ingestion, input, streaming and AgentLoop behavior remain open.

The first Linux Debug hosted job at `b556de2` passed 133/134 cases. The single
factory comparison differs from its Windows Source capture in ten cwd values
and identity observations: Windows resolves the supplied `/sdk-owned-factory-566`
to a drive-qualified path; POSIX retains the supplied absolute path. All other
captured records match. A genuine POSIX upstream capture and native qualification
are required before platform-specific expected records can be accepted. This
negative is preserved; no cross-platform pass is inferred from the Windows gate.

The optional per-runtime CodeMode clock subsequently passed 198/198 Windows
Debug integration tests, including all 48 captured clock/seed observations,
runtime isolation, invalid-input and late-reseeding controls, exhaustive owner
allocation cleanup, 135 composed cases and the 55 retained UI cases. Independent
compiled coverage passed with 126 named / 135 compiled composed cases. All
3,992 source and 19,546 tool inputs were unchanged. The previous job was
interrupted during the pause and produced no terminal output; it is not counted.
This context component does not implement public start or durable replay.
The controlled owner-thread CodeMode run and additive SDK platform fixtures
passed the combined Windows Debug graph: 209/209 tests, including 135 shared,
4 controlled-run, 8 clock, 55 retained UI, and 7 ordinary inline CodeMode cases.
All 4,002 source and 19,546 tool inputs were unchanged during execution; the
owned process exited successfully and was gone. Independent composed coverage
also passed. The controlled-run test retains all sixteen actual original Source
records and validates wall durations against measured elapsed time before
comparing deterministic observations; full owner allocation cleanup passed.

The SDK platform fixtures retain original Windows captures and add seven genuine
POSIX captures. Their isolated SDK validation passed all 40 queue cases on
Windows C, same binary on D, and Linux. This combined Root check is Windows
Debug qualification; it does not claim new exact-head hosted matrix success.

The latest official upstream reference now builds at
`ee409a85f6ad92bf8c6ab8ed735c6cd24f2e749e`: all 2,034 original files, 22,218
dependencies, 43 hydrated inputs, 1,774 npm tool files and 19 workspace junctions
were unchanged, and 2,893 generated dist files were pinned. This supersedes the
previous observed reference for ongoing implementation, not native parity.

The controlled run remains a private owner-thread core. Public worker transport,
JS-facing sandbox API, original declared tool identifiers, complete delivery and
abort edge cases, and a source-complete VM fingerprint still require work.
Latest upstream AgentSession hook signature and deferred tools also require
implementation and actual reference tests. No native-default or release claim.
The owner wakeup and newer nested schema-tool behavior passed the full Windows
Debug graph: 230/230 tests across 179 successful build steps. This includes the
previous 209, original compaction eight, seven owner wakeup regressions, and six
schema-tool tests (eighteen actual Source scenarios plus strict measurement
comparison controls). All 4,008 source and 19,546 tool inputs were unchanged;
independent composed coverage passed. The original ten-second compaction bound
and program remain intact. Failure diagnostics read worker-owned last_count and
driver_failure only after an acquire observation of completed worker state.
Latest ee409 reference captures reproduced all eighteen prior243 schema records
exactly; this does not imply full current upstream durable parity. Focused macOS
Debug remains under diagnosis; Windows success is not macOS qualification.
The canonical private Error-stack/rejection foundation, controlled-run edge fixes,
and private Agent foundations now compose with the earlier native graph.
Windows Debug passed 262/262 tests across 188 successful build steps, with
4,047 source and 19,546 tool inputs unchanged. Independent composed coverage
passed. The 30 Error-stack/rejection tests retain actual Node42 own-stack,
constructor13, caller1, rejection19 and async-context8 observations plus GPA/GC
checks. These hooks remain opt-in; the production fatal pipeline is still open.

Controlled runs now preserve all eleven actual latest ee409 reply/abort/host
callback observations and all ten actual alias/admission cases, alongside the
original sixteen deterministic cases and full owner allocation failure sweep.
Accepted host replies record status before sequence gaps drain; serialized error
properties use actual VM boxing/enumeration and length-preserving atoms; null
properties fail as a sandbox error. Declared script aliases remain stable,
including empty, dotted and embedded-null names. The controlled default has no
wall deadline, matching upstream start. These are private native owner APIs;
public worker transport and source-complete persisted fingerprint remain open.

The integrated private Agent foundations passed all eight allocation ranges on
the same 4,047-file source, covering failure indices 0 through 1,229 exactly
once with explicit BEGIN/COMPLETE and balanced allocations. Each range passed
13 compiled tests and all 44 genuine Agent Source rows. The 104 executions
repeat the same 13 cases, not 104 distinct tests. Public pi-agent-core activation
remains disabled until native AgentLoop and the default stream are complete.
The immutable whole-tree ee409 contract contains all 2,034 original paths and
passed its native capture/verify gate. This is drift detection, not parity proof.
The next integrated Windows Debug graph passed 329 of 334 tests, with five
unchanged backend platform skips, across 203 successful build steps. All 4,065
source and 19,546 tool inputs remained unchanged. Independent composed coverage
passed with 127 named / 136 compiled shared cases and complete original command
allocation ranges. The latest session trigger uses the original two-argument
API and CopyDataProperties event ordering; its isolated Windows C, same binary
D, and Linux gates each passed all 41 SDK queue tests with genuine platform
captures, not native-generated expectations.

A fresh native thread now owns each controlled CodeMode VM from creation through
teardown. Owned JSON event/reply queues and atomic cancellation keep all C values
on that thread. The sixteen original deterministic runs, computing-script abort,
abandoned pending-call shutdown and every owner allocation failure passed. The
JavaScript-facing controlled-run owner preserves all eleven actual latest reply,
callback and abort traces, including output fencing, original callback errors,
accepted-reply status and result settlement after worker teardown. Its own full
allocation sweep also passed. Incremental output events preserve message order.
The new C JSON parsing boundaries now satisfy QuickJS's explicit zero-terminated
buffer precondition; the first parser failure is retained as evidence.

These are real worker and run-handle components, not a completed public sandbox
package. The sandbox constructor/ordinary execute/portable/remote exports, all
store/deadline edge behavior, source-complete replay fingerprint and durable
CodeMode journal integration remain open. This checkpoint does not install a
partial public package or change the native-default certification boundary.

The latest formatter matches all 46 actual output cases, including 4,096 adjacent
parts, and uses linear part accumulation. Native Node base64 preserves 72 actual
scalar/coercion cases plus metadata and constructors. The JSON finite-float leaf
uses the official bounded stack buffer and identical formatting, eliminating a
temporary allocation per value. All eight private Agent allocation ranges passed
on this same source with a measured universe of 1,205 rather than the earlier
1,230; every index was explicitly begun/completed once, with balanced allocations.
The repeated 104 executions are 13 distinct compiled tests and 44 Source rows.

Hosted qualification at preceding exact head9699132 is terminal: eleven of twelve
matrix jobs passed. macOS Debug passed 134/135 VM cases; the sole failure remains
the original ten-second compaction scenario. Its process checks, ReleaseSafe VM,
and both Windows/Linux modes passed. The separate Main/editor run failed two
assertions and remains open; no hosted pass is inferred for this newer checkpoint.

Fresh upstream HEAD observed at10:52UTC is148622bc6f8d0ffd64e33cbc0e1e66754f45d32c.
Its 2,034-path native whole-tree capture/verify passed. Compared with ee409 it adds
wait-cycle rejection in durable scheduling and clarifies MCP login timeout text.
The latest immutable reference build and native wait-cycle port remain pending.
The original certified baseline fields in config.zig do not certify these newer
features; the target API version and structural captures are separate evidence.
