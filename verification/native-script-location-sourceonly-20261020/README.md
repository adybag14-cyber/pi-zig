# Native Script and source-location foundation

This source unit gives compiled bytecode and genuine captured frames a native owner for the complete compiler input and its primitive origin metadata. It is the first concrete Script/location prerequisite for later Message construction and Node reporting.

The implementation and all controls are source-only. This unit adds one install target; fresh build, metadata and runtime acceptance remain Root-owned.

## Concrete behavior

Each compilation creates one reference-counted `JSNativeScript`. The root function definition owns its construction reference, child definitions acquire that same Script, and successful bytecode publication transfers the corresponding references. A Script retains the actual input bytes, a primitive JavaScript source string, the admitted resource name, actual lexer sourceURL/sourceMappingURL metadata, HOST/EVAL origin, module status, and the input's initial line.

The native owner contains primitive values and native storage. It does not retain a function, receiver or arbitrary object graph. Bytecode, captured frames, frame clones, serializer tables and explicit native callers each hold their own entitlements. Every partial construction and retirement path releases its actual entitlements. External Script references must be released before their originating runtime is freed.

The default compiler and the existing private diagnostic/CJS compiler both retain their actual complete input. The CJS owner uses the original body, before presentation wrapping. Direct/indirect eval and the four dynamic function constructors retain their actual generated evaluation input with EVAL origin.

Actual lexer comment events supply sourceURL and sourceMappingURL. Strings, templates and block comments are not searched for lookalike text. The last recognized event, including an empty event that clears an earlier value, determines the primitive metadata. ResourceName returns the actual sourceURL when present, otherwise the admitted compiler filename.

## Source positions

The compiler records token byte offsets from the actual parser input. These offsets travel beside the existing line/column metadata through delayed emissions, both compiler passes, matchers, dead-code removal and final jump-width rewriting. A separate final PC/byte-offset table survives either strip mode.

Captured bytecode frames select the actual table entry for their PC. Only then does the native owner convert the retained UTF-8 prefix to a UTF-16 position; supplementary scalar values contribute two UTF-16 units. Displayed columns and function names do not supply offsets.

The native line projection implements the initialized line-end operation retained in the pinned V8 authority: LF, lone CR, U+2028/U+2029, CRLF recorded at LF, and the source-length EOF sentinel. Negative positions clamp to zero, EOF is valid, and positions beyond EOF leave outputs untouched. Lines and columns are zero-based. The admitted initial line affects the optional origin offset; the current compiler entry has a zero column offset. Source-line bounds remain indices into the complete UTF-16 source.

The pinned V8 implementation also has a distinct uninitialized LF-only slow path. This API explicitly selects the initialized behavior. Its PCs are the linked QuickJS compiler's actual instruction positions; this unit does not assert universal V8 instruction-position parity.

## Public native ABI

| Operation | Ownership and result |
| --- | --- |
| `JS_PiGetCompiledScript(value)` | Borrowed genuine bytecode/function to owned Script or NULL. |
| `JS_PiGetCapturedStackFrameScript(frame, &position)` | Borrowed actual frame to owned Script. Failure leaves the position unchanged; a genuine no-PC bytecode frame reports -1. |
| `JS_PiDupScript` / `JS_PiFreeScript` | Explicit native entitlement management on the runtime owner thread. |
| `JS_PiScriptReadInfo` | Allocation-free complete-source lengths and admitted origin metadata. |
| `JS_PiScriptGetSource` / `GetResourceName` / `GetSourceMapURL` | Owned primitive values, with no guest lookup or pending-state operation. |
| `JS_PiScriptGetPositionInfo` | Allocation-free initialized line/end projection. |
| `JS_PiScriptGetSourceLine` | Actual intrinsic substring; same-runtime admission and prior-pending preservation, with ordinary allocation failure possible. |

Native, bound and proxy functions are not unwrapped into bytecode provenance. Native and filename-only synthetic frames have no compiled Script. The raw frame API does not read guest properties or call traps. Genuine frame clones acquire their own Script entitlement independently of display metadata.

## Serialization

The bytecode format is version **31**. Its native Script identity table is independent of object-reference serialization and appears before recursive function constants. Sibling functions and captured nested functions therefore share the restored Script when they shared it in the writer.

Both strip-source and strip-debug retain the native Script and PC table. Their existing function-presentation/debug behavior remains separate. The reader validates tags, table references, origin/module bits, lengths, monotonic PCs and source offsets before successful publication, and retires partial owners on any error.

The existing private logical-URL serialization restriction is preserved. Two existing test roots receive only their three expected-version literal updates; their deliberate obsolete-version inputs and every declaration name remain unchanged.

## Controls and build

- Root: `src/native_vm_script_location_test.zig`
- Filter: `VM Script`
- Target: `build-native-vm-script-location`
- Declarations: **32**
- Build delta: exactly **six** additive lines using the existing shared `linkQuickJs` helper and an install artifact.

The controls cover complete input and UTF-16 length, shared versus separate Script identity, explicit native lifetime, genuine module/eval/dynamic/CJS entry, actual lexer events, line-ending/EOF behavior, both compiler position paths, frame cloning and receiver independence, raw pending-preserving projections, every strip combination in fresh runtimes, malformed and truncated reader cleanup, real heap failures, existing version/restriction gates, and failed parsing.

The final failed-parse control retains the actual Error and stack produced by the native error-stack hook. It verifies that the real filename-only synthetic frame has no Script and that the output position sentinel is unchanged. Its Error/frame/hook owners retire before the existing complete runtime teardown and native-memory-zero assertion.

## Exact intake sequence

The recorded donor base is backing-store commit `eb4ec1d69c8d21dbd1079f29882654a37b485f24`.

1. Apply the **104** ordered, exact steps in `production-delta.json` to the four specified production paths. `production-inverse.json` preserves the original byte offsets and exact inverse proof.
2. Apply the single accounting edit in `memory-accounting-successor.json`. It counts the input allocation only when that allocation actually exists; OOM/finalizer reentry can observe the earlier partially constructed Script.
3. Add the final 32-control root. `failed-parse-control-successor.json` separately preserves the sole declaration-32 correction and its complete predecessor.
4. Apply `existing-version-controls-successor.json` to the template and logging roots.
5. Insert the six lines from `build-intake.json` at its exact anchor.

Use these finite source edits when composing with Main. Complete donor C/H files must not replace Main's separately owned private setter, lazy function-prototype, or other reviewed additions. The packet contains complete original files for reversal and review.

## Qualification boundary

This unit establishes actual Script ownership and selected source positions. Message creation, failed-parse exception-to-Script attachment, stack-catcher semantics, listener registration, MessageHandler reporting and Node PerIsolateMessageListener remain separate prerequisites. No reporter, error-string heuristic, synthetic source owner or bootstrap stand-in is installed here.

The source authority is `authority/script-position-and-origin-source.json`; both finite production receipts are retained under `peers/`. The manifest records exact final source, control, build and evidence pins.
