# Prepared native API controls - all unrun specifications

1. Genuine compiled async-generator function class ID versus proposed native factory; nonconstructor, name/length, caller/arguments strictness, function/instance prototypes and descriptors.
2. Calling factory with null/primitive/object receiver does not enter body; errors occur at first next. No forwarding yield*/extra Await or eager getter work.
3. Live own prototype object replacement and nonobject fallback use creation realm, including a call from a second context in the same runtime.
4. Borrowed captured arguments/receiver/roots survive forced GC before first next and during yield/Await; all owned storage freed on never-started finalization.
5. Source return/throw before start, next/return queued while waiting, yield thenable/rejection and completed-return semantics remain existing C3 behavior.
6. Factory pending entry ordinary/fatal preserves exact reason and avoids callback invocation; ordinary C callback contracts and deliberately violating success+pending inputs are separate observations.
7. Callback state/native result finalizer produces fatal B while ordinary pending A exists; displaced A finalizer produces ordinary C/D; first fatal identity survives and pending exit is exact. No claims for nonterminating hostile finalizers.
8. Real callback direct GPA OOM during state creation, C allocation/property initialization failure at each stage, creation-realm/constant-pool GC/finalizer and capture/root cleanup.
9. Serialization rejects native pointer metadata; truthful native toString; structured callsite/stack filters report native frames with no fabricated source PC; ordinary compiled functions unchanged.
10. Actual EventStream waiting executor native enqueue failure followed by Promise-subclass ordinary throw, diagnostic overwrite or second native OOM. First exact callback event wins at constructor boundary.
11. Historical private reason / marked real Error lookalike / flagged rejection DATA with no current pending do not create new events; generation u64 wrapping follows the existing Engine private-tag span.
12. FIRST-FATAL DELIVERY NEGATIVE: current C3 generator drive rejects the marked callback reason as DATA. Record initial-next and native Await-reaction exact behavior separately; do not claim a positive producer-exit fix from leaf retention.
13. Eventual reviewed producer-exit correction must demonstrate actual fatal escape at next/job boundary, preserve queued request/owner cleanup, and repeat all retained ordinary C3 generator/AF/TLA/iterator/prototype regression gates on the exact composed C/H.
