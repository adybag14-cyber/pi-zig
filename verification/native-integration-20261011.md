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
