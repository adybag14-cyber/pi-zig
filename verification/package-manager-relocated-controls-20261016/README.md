# Relocated prospective LRU controls

This source-only packet resumes clean checkpoint
50bb35864b442aa85d27cb644732108079af39ac in the assigned container worktree.
Container AGENTS.md, .pi-zig-workspace.json and path-relocations.json were read.
No Node, Zig fmt/AST/compiler, native/C job or source generator was executed.
The local checked data-definition helper remains intact; Root's shared SDK fix
9939d010 is an ancestor of the current main checkout, not a reason to remove
that already reviewed local boundary before qualified intake.

## New targeted controls

The separate git-host-map-key-order-4dd.input.mjs uses only the actual public
GitHost and live Map.get hooks. Raw object indices return real Symbol keys on
property conversion and numeric values on typed-array value conversion. Its
three case IDs each require a fresh process/context:

- set_tail reenters through the fourth insertion key conversion to change the
  tail before the RHS read of prev[index] = tail.
- remove_previous retains a raw object in prev[index], exposing its LHS key
  conversion before the RHS next[index] conversion in middle deletion.
- remove_next retains a raw object in next[index], exposing its LHS key
  conversion before the RHS prev[index] conversion in middle deletion.

git-host-map-return-retirement-4dd.input.mjs prepares two observational rows.
Its subjects/WeakRefs are created in an earlier real job. An actual Map.clear
hook and the first Array.fill hook return otherwise discarded subjects; later
fill callbacks run actual GC and observe their weak references. The first
fill deliberately does not dereference the still-owned fill subject, avoiding
an artificial live-job keep that would invalidate the second probe. Finalizer
callback timing is recorded without an assertion. The harness must provide a
real next-job operation and collector; the input does not simulate either.

native_hosted_git_lru_test.zig separately prepares one native ownership invariant
over the actual helper, retained VM Map and arrays. It checks ignored clear/fill
retirement before later callbacks, using a real C-runtime collector and an
explicit preparation-job weak-kept boundary. It is unregistered and unexecuted.
No fake public LRUCache class or replacement cache implementation is supplied.

The prior five Map cases remain byte-identical in their original input. These
new three raw-key cases and two weak/finalizer rows are a separate supplement,
with no expected JSON. Exact Source observations are still required; source
authoring/static review alone does not establish those observations.

## Prospective path migration

Historical manifests, original runner bytes and old observations are unchanged.
The new capture-git-source.mjs and reference-gate.mjs target official
upstream/pi at 4dd2b149d155d7369de16ea4dc77c84e9f5ffb24. Read-only checks confirmed
that Git utility SHA256 BFF4590AEFA988BA625026769AC5AD02F02558D59BD7D566F4728E1EE4DA1DA9
and PackageManager SHA256 61BB2F0B434B0F5C48AB6BFACD9DFF1D99084320EECF695755CD32BD88099310
are unchanged from the prior body authority. This explicitly changes the
prospective source target; it does not relabel historical 0fb observations.

The gate resolves old manifest paths through the longest explicit relocation
mapping and hashes their relocated bytes without rewriting the manifests.
The original 31064-file runtime manifest is pinned to
38223DB79BE24C7F9F5833A662D3C73FF2531F78489699DBF87F9F52A9B4BFBA.
It requires complete recovery receipt metrics and independently verifies all
31064 runtime entries, all 1774 original Node tool entries, the fresh current
Source manifest, all controls/candidates and 84 actual absences before importing
the original utility/dependency. An unknown import or historical workspace
implementation fails. Control/candidate overlap retains both sealed roles.

This observer is deliberately Git-only. It maps the original hosted-git-info
import to the recovered dependency and rejects unexpected workspace imports.
It does not claim to replace the separately required full SDK workspace map or
to migrate the historical package/physical/npm runners. Those older programs
remain historical and must not be run with rewritten receipts.

The prospective gate fails while runtime_status is recovery_pending or the
container jobs-held flag remains true. Root must supply a fresh bounded-process
grant, complete pre/post seals, independent absence close and a plan in evidence.
The runner itself creates only fresh evidence paths and marks any raw result
pending independent post-close; it cannot certify its own successful capture.

## Required future plan

PI_ZIG_REFERENCE_PLAN points to a new plan JSON under evidence; the controller
also supplies its exact digest as PI_ZIG_REFERENCE_PLAN_SHA256. No plan/seal or
positive recovery receipt is fabricated in this packet. Required fields are:

- schema: 1; sourceHead: the exact 4dd commit above; nodeVersion: v24.14.0.
- workspaceSha256 and relocationsSha256: the admitted container metadata bytes.
- recoveryReceipt: a sealed descriptor with originalManifestSha256,
  originalRecords: 31064, matchedRecords: 31064, missingRecords: 0 and
  mismatchedRecords: 0. If recovery emits a different schema, Root must supply a
  separately reviewed adapter/close rather than rewriting that original receipt.
- sourceManifest, originalRuntimeManifest, originalNodeManifest, controlManifest
  and candidateManifest descriptors. Each descriptor has path, sha256 and records;
  manifests are arrays of original path/sha256 rows. Runtime and Node counts are
  fixed to 31064/1774; original source/Node authorities must remain original.
- absenceManifest: a sealed fresh array of exactly 84 absent path records.
- tracePath: a fresh file under evidence. Output is a distinct fresh evidence
  path supplied as argv[2], input as argv[3], and optional case ID as argv[4].

Use a separate fresh process/context for every Map/raw-key case. The retirement
input additionally needs the real pinned Node --expose-gc capability; its runner
provides real setImmediate job advancement and the actual collector. No newer
Node version or different tool tree is selected merely because it is available.

Current metadata still reports recovery pending. The mapped retained archive's
LRU node_modules file was also absent on this task's read-only check. Body's
accepted static review used the previously inspected exact A1B0 contents; no
current/full dependency-authority claim follows. Recovery belongs to the assigned
owner. Native runtime, allocator, application/default and whole-Pi qualification
all remain false/pending.
