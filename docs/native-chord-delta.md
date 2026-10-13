# Private native Chord delta candidate

The implementation at `3a7145ef55064f4bf43d12b1af43849f23b141c9` ports the actual Chord revision diff and tracker graph. It remains a private component until the complete Chord Host/Cell/Derived composition is qualified.

The public Zig entry points are `native_chord_delta_tracker.track(engine, initial)` and `native_chord_delta_diff.diffRevisions(engine, before, after)`, both returning owned `JSValue` results. Their `function(engine)` helpers create ordinary native functions for a privately assembled module. The tracker bindings are retained once per engine in `Engine.native_chord_delta_tracker_bindings`; engine teardown releases that value while its JS context is valid. These modules do not install a public package or register a hidden global/module namespace.

`track` returns the real native TrackerImpl, ChangeImpl and PreparedImpl graph. It preserves the Source `value`/`revision`, `beginChange`, `prepareReplace`, `adopt`, draft `state`, `prepare`, `abort`, `base`, `ops` and `baseRevision` behavior. Its shared prototypes, weak context registration, prepared ownership and consumed/aborted/stale states use GC-marked native private storage. Native callback leases retain contexts and nodes across guest callbacks and retire cleared allocations after active calls finish.

The overlay implements all eleven Source proxy traps. Strict placement copies preserve the Source rejection of symbols, holes, cycles, exotic containers and unsupported descriptors. Array mutation retains base and inserted-entry identities through the seeded piece tree; sorting captures public values and overrides, restores comparator writes as Source specifies, and detaches duplicate entries caused by structural comparator mutation. Emission preserves dirty-node depth/order, delete/readd order, string overlap, structural plans, reserved-segment folds, dense regions and the operation limit. The existing native persistent delta applier materializes prepared revisions before adoption. Initial values follow the upstream immutable, alias-free strict-JSON ownership contract; `track` does not add a new validation pass.

Source identities and retained oracles:

| Item | Identity or coverage |
| --- | --- |
| Original source | `19cb534c3b6e3871458a8fa59e98f0312c50e995` |
| Latest contract source | `e6220e1316f86af818a0ccbfe1c09d7e918b41cf` |
| Original archive SHA256 | `5da1185d5c3bd4ba55618c38ee0524defd5cb0797c9aaa0ead7507387472f2f0` |
| `tracker.ts` SHA256 | `68bd2d7b9c0538366b079004ddd5dc9180cedd67d129f5c8de6c9ef6380e2c54` |
| `diff.ts` SHA256 | `928696add33868b9655f856c2d52f596a220249db3ee907c8b8c5b497bf7ccde` |
| Original diff replay | 108 cases, including 3 negative cases and raw exception identity assertions |
| Original tracker replay | 60 cases, including all 23 negative cases |
| Structural projection | Seven original tracker batches; bound to the full tracker oracle SHA256 |
| Diff caller input SHA256 | `0b1d45f613e4948342b90b7570b24c9c36b0be3ea61d6eeab0ee1b8f540cac5c` |
| Tracker caller input SHA256 | `253929158f91b490f8e639ef6c657311eb971609998a55cfaa7e9477d73c78f1` |

Every dependency row recorded in the two oracle files hashes identically between the original and latest Source. The original export recapture checked 31,064 runtime files, 1,774 tool files and four driver/input files before and afterward with zero drift. The full tracker oracle retains lone UTF16 surrogates. The pure Zig structural-plan test uses a captured projection because `std.json` rejects those strings; the VM replay consumes the unchanged complete oracle.

The implementation commit's local Windows qualification is recorded under `verification/chord-delta-20261013`:

| Mode | Terminal result | Owned Zig PID / creation UTC | Completion UTC |
| --- | --- | --- | --- |
| Debug | 9/9 passed | 32140 / 2026-10-13T13:46:13.8169634Z | 2026-10-13T13:46:29.0792034Z |
| ReleaseSafe | 9/9 passed | 38104 / 2026-10-13T13:47:46.9246207Z | 2026-10-13T13:52:16.9521413Z |

Both runs exercised `test-native-chord-delta-diff-source` and `test-native-chord-delta-tracker-source`, including full original replay, actual GC across open/prepared/adopt states, and exhaustive native allocation failures. Each retained 4,376 source and 19,546 compiler input hashes with zero post-run drift. The compiler remained Zig 0.16.0, default LLVM, `-j1`, a 120-second per-test guard and a 300-second outer deadline. A binary `git cat-file` comparison subsequently checked all 4,376 committed blobs against the successful ReleaseSafe manifest and found zero byte drift.

The separate candidate wrapper imports the unchanged diff, tracker and structural-plan suites and emits the actual compiler-selected test inventory. The `native-chord-delta-candidate.yml` workflow runs on pushes to the single owned candidate branch and supports manual dispatch with an exact reviewed SHA. The scoped push provides first-run registration without merging private Chord code; GitHub requires manual workflows on the default branch before initial dispatch. It runs Windows, Linux and macOS in Debug and ReleaseSafe, freezes source and the complete compiler distribution, verifies original positive/negative inventories and fixture hashes, separates cold compilation from the unchanged 120-second test / 300-second runtime guards, checks every named compiled test executed, and verifies hashes and inventories afterward. Its final job requires all six platform/mode results. Hosted qualification is separate from the local results above.

To integrate, retain the engine cache field and cleanup from `6a76339`, use the actual `track`/`diffRevisions` functions from the native Cell/Derived implementations, and qualify the complete Chord lifecycle and listener graph. The candidate does not certify complete Pi parity, a release, public Chord activation, physical-device behavior, or a deployment.

## Hosted allocation-failure correction

The first candidate run38414917806 passed five platform/mode jobs. Linux Debug
crashed in the whole tracker allocation sweep when GC inspected array storage
after an induced failure during optional aggregate initialization. Commit
b7ac507c736668842174bcf2c270d1699a79c6ac completes every fallible tree
initialization before publishing the optional payload. A targeted regression
fails both initial tree allocations, checks that array storage stays absent,
and runs GC. The corrected local Debug gate passed10/10; the full candidate
now requires eleven named tests plus its original anonymous declaration test.
All original108diff/60tracker/23negative cases and the exhaustive sweep remain.
Corrected hosted qualification is pending.
