# Actual fdf6 TypeBox EXE/PDB pair and static frames

This standalone data capsule records matching-artifact identity, the actual
bounded LLVM dump, and the accepted read-only V2 interpretation for source
fdf6f25e4ef61321abaa4b9884eeb1cf97be6d18. EXE SHA256 is
CE0572A0D774533F3187972E51EAA0500C3AD2428E93A5DE1E71C3DF43A21A06;
PDB SHA256 is94B50DE6101A9E10FB82D7965C48BB03317E0BCFD5F86271D25E5C0ED9E80935.
No EXE, PDB, cache or executable distribution is included.

pair/ contains a path-labelled derivative of actual pair receipt3848AB78 and
text-hex copies of the exact17 header/directory/info spans,32158bytes, read for
that verification. RSDS and MSF stream1 independently contain GUID
5c2950c8-f252-3f31-4c4c-44205044422e, age1. All span offsets/hashes and artifact
pre/post identities are retained. The33byte RSDS record contains only test.pdb
as its filename, so no personal path bytes need masking in these header spans.
These are small decoded headers represented as text, not an executable/PDB.

raw/llvm.symbols.path-redacted.txt derives from the actual51245883byte dump,
original SHA256 E405D80A4E1770BEAD57DCFFF7EDE70257F090D292EDEAFB1CCCCA78273A23D1.
Only explicit filesystem-path labels change. Streaming roundtrip hashing proves
original UTF8 and line endings were preserved before replacement. All numeric
records, addresses, frame values and line order remain; this is a DERIVATIVE,
not byte-identical raw evidence. capsule-manifest.json preserves every original
raw SHA separately from the published member SHA. Local originals are immutable.

owners/ preserves only actual owned LLVM21444 and outerPowerShell61048 roles,
release/grant, before/after pins, admission and absence. LLVM was bounded60s,
outer300s, settling10s, fresh16GiB/native+LLVM zero admission. Stderr was empty,
terminal0/fullpost/owned absence closed. No unrelated CIM/environment/full
machine inventory is included. ControllerV7AEB49 uses the reviewed78DE LLVM
owner; canonical53 owns the dedicated PowerShell controller. These are not
native runtime-test protocol executions.

analysis/ retains all16985 procedure↔FRAMEPROC associations (12677 LPROC32,
4308 GPROC32), numeric sorting,34 plan/table joins,2022 per-PC joins,14 finite
signature profiles, and old1f9/283 comparisons. The accepted V2 manifest's
original SHA is34F9DED4462E2022B87CF09F3BED2A5645F5EEA11FE683F6CE45DFC01521AC0E.
PDB names are short names, not namespaces. Identity/ambiguity candidate sets and
visible parameter types are retained. Each PC uniquely matches source/table and
PDB record; PC fixed frames range56..392bytes. Legacy1669 f_N bodies remain
compiled; their identity does not prove their bodies executed on a planned call.

source/ contains byte-exact generated22388C87/map186D9248 and exact kernel/Node
source needed for the joins. acceptance/ keeps independent232A,6ACF andBF10
source-proof roles separate. intake/ preserves actual13 checkout source pins,
Main-physical-vs-checkout CRLF provenance, and the raw byte hashes. No machine
inventory or implicit source/qualification transfer is introduced.

negatives/ explicitly retains V6's prelaunch missing-brace parser failure,
its owned outer terminal/absence and source-control identity. LLVM never
launched for that attempt. CorrectedV7 and Min8800 review are separate. The V1
analysis issue is also preserved: frame identities/sizes were correct, while
a second PowerShell regex overwrote parameter metadata. V2 restores types;
all16985 frame identity/size/saved-register values have zero drift. V1 raw
file/parser hashes remain even where large duplicate V1 files are not repacked.

Functional evidence is a separate same-artifact scope: actual original4 flags0
and80/52/396 parity markers establish those replay assertions. This capsule
makes NO ASLR, absolute runtime-address, live stack peak, per-PC execution-count,
frame-sum/depth estimate, allocator-exhaustiveness, later-head or whole-app claim.
Large globally linked frames are not assigned to Source391 by their presence.
Root supplied published-parent context6c07371dc8b452fd96b1729445109553cbcd0116;
this packaging operation did not query/publish a remote or change Main.

Run after extraction: pwsh -NoProfile -File ./Verify-Capsule.ps1 -Root .
The verifier starts no child: it checks every member, header hashes/GUID+age,
streams the public dump to rejoin all16985 frame values, and checks the actual
34/2022 source/map/symbol correspondence. It cannot reconstruct withheld EXE/PDB
files, the original private path strings, old full baseline dumps or unpublished
machine inventories. The ZIP SHA is supplied separately; the manifest excludes
its own hash. Sorted ZIP entries/fixed timestamps enable repeatable packaging.
