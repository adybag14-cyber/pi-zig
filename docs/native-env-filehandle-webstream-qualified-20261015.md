The private native FileHandle/readableWebStream assembly now matches eight
genuine Node24 packets over actual C/libuv files. The selected native target
contains inventory plus those eight cases; one imported storage discovery test
brings the actual inventory to ten. All ten passed with zero skips. Compile
completed231/231 steps; matching runtime completed232/232 steps.

Both successful phases froze the same complete candidate5523, latest Source1967,
dependencies31064, compiler19546, Node tools1774, pinned libuv416, reference43,
control7, environment and source-path inventories. Their common SHA256 is
2EA7F4FA19F2E95A458ED287720EB5B5F87DEAC8CA83F47F91B4F035F61AC119.
All post checks reported zero drift. Owned compile PID57900 and runtime66116
were retained by exact executable/start-time/argv identities and independently
absent afterward. Runtime ended2026-10-15T19:14:49.5091379Z; full post completed
2026-10-15T19:15:23.3168530Z. The native validation slot was released.

The exact code, test, actual input and actual expected packet leaves are listed
in qualified-leaves.json. qualified-tracked-delta.patch contains only the new
build target, the FileHandle Symbol.asyncDispose capture correction, and the
native Env Hub microtask checkpoint change. Apply all three new implementation
modules, test and fixtures together with that delta over the published972d base.
The Hub change prevents a completed native I/O worker from overtaking queued
Promise continuations and yields after a callback queues new jobs. This was
necessary for genuine autoClose final-state ordering; expected output was not
altered to accept the former mismatch.

qualification-audit.json preserves every failed/successful phase and SHA.
immutable-receipts.zip preserves125 hash-verified members: all six native phase
freezes/receipts/logs, all eight corrected Source case freezes/receipts/packets,
reference/control manifests and the previous negative FileHandle BYOB-offset
probe. Its SHA256 is
1288D88C2F390F776774348E8D6D5077D970E2C6E9320AB43E6DB158657CBB96.
The archive is40439325 bytes; archive-verification.json records verification.
The original cached-symbol observer incorrectly serialized locked:false;
its prior packets remain preserved outside the accepted expected fixture.
The nonzero-offset FileHandle reference exited1 with the actual uncaught
ERR_OUT_OF_RANGE read-length error. No success packet was manufactured for it.

Qualification covers only the actual paths exercised by these eight cases.
The complete public ReadableStream and FileHandle class graphs remain
unqualified and uninstalled. Shared standard prototypes, tee/pipe/iteration,
full method coverage and transfer/async-resource disposal still need work.
The private brand/disturbed/errored/controller-close hooks have not yet passed
their own consumer gate. No exhaustive allocation sweep or non-Windows runtime
gate has run for this change. Native exec/watch remain separate unqualified
drafts; the Hub checkpoint leaf has not been qualified through those bridges.
The Source ByteStream12 batch completed12/12 passing cases with full post0
after this private FileHandle snapshot was taken. Its separate byte-core
successor remains uncompiled and is excluded from this checkpoint. This scoped
checkpoint preserves the eight implementation/test/fixture leaves exactly as
qualified in the original5523-file candidate, while excluding unused reference
inputs and subsequent source-only work. This new commit as a whole has not had
a fresh matching compile/runtime pair. Integration or publication requires that
exact candidate gate; no public class export is enabled here.
