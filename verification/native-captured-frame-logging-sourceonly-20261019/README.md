# Captured-frame logging origin

## Purpose and contract

Node v24.13's default native stack formatter branches on the actual V8 `StackFrame::IsEval()` and whether `GetScriptId()` is the no-script sentinel. Its existing filename and function-name projections do not establish either fact. This unit retains a private origin at the actual compiler entry, carries it into real captured frames, and exposes only those two primitive predicates.

`JS_ReadCapturedStackFrameLoggingInfo(ctx, borrowed_frame, is_eval, has_script_id)` returns zero and writes both outputs for a genuine captured frame. Invalid frame brand or a missing output pointer returns minus one with output storage unchanged. It performs no allocation, guest property lookup, proxy trap, pending-entry check, or pending-state mutation. The caller retains its original frame ownership.

| Actual origin | is_eval | has_script_id |
| --- | --- | --- |
| Host script, module, or genuine CommonJS wrapper | 0 | 1 |
| Direct/indirect eval and dynamic Function compilation | 1 | 1 |
| Native function or filename-only synthetic frame | 0 | 0 |

## Actual compiler and captured-frame ownership

Every parser root begins with HOST. Direct/indirect eval overrides that field at its actual entry before nested parsing; children inherit their parent's origin. The same actual path covers the four dynamic Function constructors. The included genuine CJS compiler creates its own null-parent bookkeeping root, which now also begins HOST. Native AF bytecode is separately zero-initialized and remains NONE.

Bytecode publication copies the primitive field. Normal capture, actual bytecode frames without a program counter, native capture and filename-only synthetic construction initialize it before publication. Existing complete-struct cloning retains it. No JS root, marking edge, receiver reference or retirement operation is added by the metadata.

Bytecode version 30 stores two origin bits independently of source/debug stripping. Version 29 payloads fail the existing version check. Origin 3 fails with the new precise syntax error before a bytecode object is allocated. Consumers must rebuild serialized artifacts from the current compiler.

## Original-source evidence

The selected V8 sources are the unchanged files from Node v24.13 commit `def0bdf8abee441cfcbf793a8dc24a6f3b899573`. [The operation proof](authority/source-operation-proof.json) includes sixteen exact slices, full-file hashes and offsets. It covers actual StackFrame operations, Script creation and nonzero IDs, child Script ownership, eval versus wrapped-host compilation, dynamic Function compilation, and Node's formatter branch. [The acquisition record](authority/source-acquisition.json) distinguishes raw full-body hashes from truncated web extraction metadata; the unchanged licenses are retained.

The original full `api.cc` is reused from the already committed existing-Promise settlement authority. The actual included CJS compiler is referenced by exact hash. The Node formatter excerpt is retained in the operation proof with its original full-body hash and immutable URL.

[The reversible production packet](production-delta.json) contains precisely sixteen C/H edits. [The source verification](source-verification.json) confirms complete parent/current reversal, every selected authority slice and constant, the included CJS source, and the six-line build reversal.

## Nineteen authored controls

The actual root is `src/native_vm_captured_frame_logging_test.zig`, filtered by `VM logging origin`. [The manifest](manifest.json) retains all nineteen exact names.

The controls cover host/module and eval origins despite misleading names, escaped children, four dynamic constructors, class constructors/field initializers, a real foreign context, native/synthetic frames, clones after original frame release, poisoned public fields/proxies, invalid output storage, prior ordinary and actually thrown uncatchable reasons under heap limit 1, and a sole native receiver holder. Serializer controls use real compiled host and module bytecode in fresh runtimes with each strip combination, the actual old-version gate, and the precise invalid-origin path. The final control invokes the genuine CJS compiler and its returned wrapper.

The linked VM keeps the native indirect-eval call between its compiled eval body and host caller; the control checks that frame explicitly. Every raw failure result has an owner before assertions, including unexpected-success paths. Native probe storage outlives runtime teardown.

EVAL encoding/decoding is source-reviewed. The serializer controls exercise the real public compile-only host/module entry points; this unit adds no EVAL bytecode exposure just to create a test.

## Review and validation status

Both assigned peers are closed on the exact production and test pins in [the peer receipt](peer-review.json). The install-only target is `build-native-vm-captured-frame-logging`; [the six-line build packet](build-intake.json) reuses the existing shared QuickJS library.

This is a source-only unit. No compile, metadata query, runtime, Node, formatter or generator action was performed. The default Node CHECK formatter, its process-terminal behavior, debugger/Wasm features and V8 numeric Script IDs remain outside this claim. Fresh validation of the resulting combined source revision is still required.

The generic staged whitespace check reports only the original trailing blank line in `authority/NODE-MIT-LICENSE.txt`. That license section is preserved byte-for-byte. The separate source/document check excludes only that unchanged license artifact.
