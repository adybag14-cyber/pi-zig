# Simple Error stack source foundation (Message unit 2a)

This source unit gives the existing simple Error stack owner an intrinsic, non-adopting Script/location read. It preserves the selected original simple-stack representation: a captured raw frame array, disabled capture, or formatted DATA occupies one state. A successful formatter writes the selected holder's current record; a failed formatter leaves any reentrant setter or recapture state intact.

The raw C operations share the real WeakMap lookup, distinguish an actual recursive native capture from an untouched Error, transfer the fallback entitlement only after successful map publication, and project an independently owned Script with the actual UTF-16 position. They do not call guest getters, allocate a replacement Error record, clear pending state, or retain a CallSite receiver/function graph in the returned Script.

## Exact source composition

The parent is `ce28434cf977b75ed5e1fd1a26468e84c27189a5`, which contains the independent V27 constant declaration-order correction. The original nine-edit C/H packet was reviewed against Script32; its bodies are unchanged and commute exactly with that two-definition relocation.

Apply these packets in order using their exact before/after text:

1. `production-c-delta.json`: nine C/H edits.
2. `production-owner-delta.json`: nineteen edits in the existing `native_error_stack.zig`.
3. Add `src/native_vm_simple_stack_source_test.zig`.
4. `build-intake.json`: seven install-only lines using the shared QuickJS target and existing catalog import.

`integration-replay.json` independently reproduces the complete donor files and reverses every edit. It also records a read-only Main projection, preserving Main's private-property setter, lazy function prototype and other shared C/H additions. Main must receive the finite edits, never a whole donor C/H/build replacement.

## Controls and review

The real root has 33 declarations with filter `VM simple stack source` and target `build-native-vm-simple-stack-source`. The controls exercise intrinsic WeakMap read, raw Script ownership, explicit fallback presence and transfer, failed adoption, simple-state retirement, selected-holder and reentrant formatting, ordinary/fatal/private actual pending, and cancelled native unwind.

SDK independently closed the C/H slice and controls 1–20. Modules independently closed the existing owner, Fixture/formatter controls 21–33, and the seven-line build insertion. Their complete pinned receipts are retained unchanged in `peers/`.

The owner uses the actual Main Engine, Completion, Boundary, operation Scope and Frame dependencies recorded in the manifest. Older versions of those shared owners in this isolated donor were not overwritten.

## Limits

No compiler, native test, Node, generator or formatter was run for this unit. Source closure does not establish runtime qualification. The existing explicit fixture/worker stack-owner installation remains the only claimed installation scope.

This unit does not construct Message objects, add detailed stack storage, implement ThrowAt locations, report exceptions, install a Node message listener, change ordinary Engine bootstrap, or provide the separately required nonterminal diagnostic snapshot.
