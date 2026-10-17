# C3, readonly query, async iterator and CallSite source composition

This isolated source composition starts at Root Main
`c43d2e150d568e2769f87fc590e709eebaaa49e0`. It is uncompiled and unrun.
No Main, Engine, default module selection, limits, fixtures or original proof is
changed. No compiler, formatter, AST/parser, Node or native job is authorized.

The starting C/H blobs are the accepted C3 `DA14DFBB...01614` /
`A79E75A4...18346`. Three retained patches are applied in order:

1. C4 readonly `JS_PiModuleGraphHasTLA`, from C3 `c83c8b13` to the exact
   `b814eac6` fixture successor. The C/H product is unchanged from its original
   reviewed query implementation; the real unresolved/partial graph fixture is
   the corrected one Root reports passed in the separate fifteen-entry run.
2. C5 `JS_PiGetAsyncIterator`, from actual C3 `d19e0d20` to `b3e4bb5c`.
   This includes the owned pending-reason cleanup and actual Error fixtures.
3. CallSite visibility, from the same C3 `c83c8b13` to `328eab6e`.
   Strict/top-level visibility and every real stack-frame initializer use the
   reviewed correction; no name-based or guessed frame identity is introduced.

Each product patch contains only the original C/H delta, not an old complete
file. All three apply checks and applications succeeded without conflicts.
Their union adds the query, iterator wrapper and CallSite changes. Header
overlap is two independent additive declarations. The query and iterator code
do not create stack frames; the CallSite patch initializes its new private
frame fields at the existing producers. No EventStream generator-function API,
producer-exit change, module-link transaction or CJS compiler is included in
this first checkpoint. Root may authorize a separate successor for linking.

Component packet files retain their original names and bytes. Their recorded
candidate C/H hashes describe those historical standalone units, not this
composition. `prepared.json` in this directory binds the actual composed bytes.
No old manifest, source input, negative or qualification is relabeled.

## Install-only controls

`build-native-vm-c4-c5-callsite-controls` installs four distinct artifacts:
individual query, iterator and CallSite roots, plus a combined root importing
the same original tests. The individual targets end in `-query`, `-iterator`,
`-callsite` and `-combined`. The static named census is 14 + 13 + 9 = 36;
compiled metadata, imported anonymous entries and runtime results remain unknown.
No new build step invokes a test runner or attaches to a default step.

`build-native-vm-c3-retained150` installs the fifteen original selected Compile
objects under distinct `vm-c3-retained-*` names. Existing roots, filters and
assertions are reused. The byte-exact `c3-selection150.original.json` was read
from the accepted current-C3 proof archive; it is the original ordered metadata
authority, not newly authored expected output. The original scope is 150
execution entries across 98 unique full names, not 150 unique tests.

`build-native-vm-c3-current11` separately installs the accepted queued-import and
actual-binding roots. Their three original control files are restored verbatim
from `c83c8b13`; the production binding already exists unchanged in Root Main.
The two `.original.json` metadata files are byte-exact archived observations.
This eleven-entry addendum is separate from the 150-entry selection.

The inherited public proof capsules under
`verification/graph0-c3-retained150-proof-20261017` and
`verification/graph0-c3-current11-proof-20261017` remain unchanged. They include
the original compile and runtime negatives. Their accepted C3 passes do not
qualify the new C/H union. Actual metadata and every ordered result must be
checked afresh under separate Root grants, with the complete original selected
names and assertions retained.

## Boundaries

The readonly query does not link, load or evaluate a graph and does not implement
Node synchronous require(esm). The iterator API delegates the real existing VM
iterator operation; it does not infer a fatal event from marked rejection DATA.
CallSite metadata reflects actual strict/top-level flags, with no guest exposure
of strict functions or receivers. Runtime, ABI, C allocator and whole SDK/Pi
qualification remain separate. The original callback-contract limitations and
host allocator frontiers in each component packet remain in force.
