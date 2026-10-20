# Selected options intrinsic heap-OOM source successor

This is a source-only correction of the actual selected native serialization tail. It has not been compiled or executed.

## Original negative and source contract

Both complete original roots are retained under `original/`: the actual V24 root CCD1447A and the current Main preimage 5D141424 with its actual Config initialization correction. Reversing Root's single Config-init edit from the latter reproduces the former byte-for-byte. The original V24 runtime stderr and the complete migrated heap test are retained beside them. The former in-process test demanded a new Error carrying a private native allocation generation even after setting the real VM heap limit to one byte. Raw QuickJS intrinsic allocation can fail with an unmarked primitive null and does not create an Engine allocation generation.

The retained Node 24.14 / V8 allocation chain instead selects native termination for exhausted intrinsic heap allocation. V8's real kRetryOrFail path uses location CALL_AND_RETRY_LAST with kHeapOOM; Node's installed OOMErrorHandler sets its permanent native OOM flag, writes the fixed fatal header, selects the OOMError native report trigger if reporting is enabled, flushes, and aborts. The exact source excerpts and immutable acquisition metadata are in the adjacent diagnosis authority packet DB865FBF.

## Production boundary

Only the selected serializer's native strings, primitive name atomization, fresh null-prototype objects, fresh own definitions, and intrinsic ArrayFrom calls use the new local boundary. It takes an occurrence snapshot immediately around the actual non-guest raw producer. It reaches the native terminal handler only when that producer returns failure and the actual JS_ThrowOutOfMemory occurrence changed. The separate VM-owned occurrence ABI is supplied by c2eec1e2875eb0ed6954b154fd22c749e8cf8c6e and was intaken to Main901206a7 before this unit. This unit does not edit QuickJS.

A failed result with no new occurrence follows the existing ordinary boundary, including a genuine string-length RangeError. No Error message, public fatal bit, old allocation tag, diagnostic slot or primitive DATA is used to infer OOM. The native fatal entry runs before caller rollback or reason selection. Its header/report selection does not allocate a VM Error or invoke a guest event.

The successful native-tail operation order, actual flags0 code Set and native Maybe.Check remain unchanged. The independent charged native-vector failure path and its original control are unchanged. Bootstrap Error construction and callable/bootstrap factory allocation continue to use their existing boundaries; this unit does not assert coverage of every native allocation in the broader options graph.

## Control migration

Exactly one old in-process declaration is migrated:

`native actual Node options intrinsic serialization failure supersedes the ordinary bootstrap reason`

The successor retains the other 29 declarations and bodies byte-for-byte, including actual Config initialization and the distinct native-vector allocation control. The removed declaration, original full root and original negative remain immutable evidence.

The standalone probe has two actual heap failures, one for each serializer, and two ordinary successful-tail controls. Each process waits for stdin EOF before setup so the existing retained native process owner can capture it first. A real inherited Error.prototype.code setter checks original state and then changes the real VM heap limit. The selected serializer must reach the native terminal handler on the next failed intrinsic. An unexpected return restores the heap for honest cleanup and fails; it does not manufacture an abort.

Successful controls check the exact original bootstrap reason, serialized flag, unchanged Engine generation and unchanged VM occurrence. The negative cases require the real native heap-OOM diagnostic and native termination. They do not require a newly allocated Error, private tag, guest catch, or JavaScript trace under an exhausted VM heap.

## Build and intake

`build-intake.json` proposes an install-only executable in the existing options/network guard. It reuses the same QuickJS, TypeScript, SQLite, catalog and Windows dependencies. Its cached basename is test, its installed basename is native-node-options-oom-probe, and there is no run edge. `probe-cases.json` is an unexecuted expected-exit proposal, not evidence of success.

The five existing-file edits in `production-delta.json` have exact before/after blocks and full retained originals. Intake must apply those blocks to current Main, preserving unrelated successors. The source occurrence API must be admitted first. Native process controller wiring, expected-exit execution and independent closure remain Root-owned.

## Finite peers

- Modules closed serializer/order on E0944E5D against E1E6B701; all ten binding edits reverse exactly.
- VM closed native handler C1D051F41 / H A618BB6C / Zig CC49A9A4 against Main7F9B/72C3/E4C3 and the original OOM chain.
- Modules closed the complete probe and build, then the silent-success successor00898AAA / cases343990D2 / packet4CDF877F. The unique forward/inverse removes only the final successful print; all causal assertions and negative SITE markers remain. Build6F162D17 is unchanged.
- The separate VM occurrence13 unit c2eec1e2 is source-peer closed and already intaken by Root. Its exact production packet443DF729 and selected original sourceDD1E86FF are copied under dependencies/.

## Final source receipt

closure.json records the final peer boundaries and exact current Main forward/inverse checks. The initial production-delta.json is immutable draft evidence; its initial pending metadata is superseded by this closure. The two positive cases require empty output on exit0. Both negative cases require actual native-frame content; genuine heap exhaustion may prevent JavaScript-frame materialization. All four cases remain unexecuted.

The supplemental authority/selected-intrinsic-allocation-source.json preserves nine exact native API and allocator excerpts, matches the full V8 raw source hashes to the pinned Node24.14 metadata, and retains the ordinary length distinction. The prior successful native continuation proof is copied unchanged under authority/.
