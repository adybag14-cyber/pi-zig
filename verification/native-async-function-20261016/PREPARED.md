# Native qualification preparation: held for Root admission

Root statically approved exact Source checkpoint `8f97c86ec8aeb7aa37f1de1b9743505fcedb470e`. It is public at `checkpoint/native-async-function-source42-review-20261016`; exact remote-ref and SHA-addressed public raw-byte readback passed for all 13 checkpoint files. The readback receipt is retained at `C:\Users\adyba\pi-zig-update-evidence-20261003\native-async-function-source42-8f97c86e-public-readback-20261016.json`, SHA256 `932D131CD6E758798C541E897FDFCF99959AA7F7A9DFB8A65A0FD29039BF1C26`. Native execution and native qualification remain false. Main and releases were not changed.

This successor adds qualification-only composition and a caller. Approved QuickJS C/H, native AsyncFunction adapter, the ten authored AsyncFunction tests, Source caller, expected JSON and Source drivers remain unchanged.

## Cohort and process bounds

`build-native-async-function-qualification` installs one test artifact containing a statically declared 25-entry cohort:

- Ten native AsyncFunction tests, including genuine Source42 replay, class identity, receiver/return semantics, host allocation failures, raw and resumed uncatchable OOM, stack frames, bound/proxy source, and genuine C allocation pressure.
- Eight inherited functional native async-generator tests.
- Six inherited JSON tests covering actual request construction, decoder, genuine helpers/delegates, scoped hooks and ordinary no-hook parsing.
- One direct borrowed ArrayBufferView span regression covering owned backing retention, typed/DataView offsets, live resizable-buffer lengths, out-of-bounds and detached rejection, and proxy brand checks without traps.

`expected-tests25.json` seals the complete declared metadata names; `expected-async-tests10.json` seals the exact AsyncFunction subset. Actual metadata must be read from the newly built binary through Zig0.16's query/exit-only protocol and must match both lists before any unit test runs. No actual metadata or semantic compile result is claimed yet.

The build uses pinned Zig0.16.0, LLVM, one build job, and a 1,320-second external deadline. Runtime invokes the matching cached `zig build test-native-async-function-qualification -Doptimize=Debug -Duse-llvm=true -j1 --test-timeout 120s --summary all` target under a 300-second owner deadline, so the 120-second per-test deadline is enforced by Zig's test protocol. Metadata uses the retained-handle CI metadata owner with a 30-second deadline; no `run_test` protocol command is sent during this phase. The installed binary and exactly one hash-matching cached binary are both frozen; metadata is read from that cached binary and artifact hashes are checked around the runtime.

## Admission and ownership

The caller requires an exact clean candidate head, a Root execution-grant identifier, an owner path and an independently approved owner SHA256. No accepted owner hash is baked in. The two historical held owner hashes `7ADAED73...F122` and `9B5A40C1...E4FD` are explicitly rejected. Their monitor failures do not qualify them for reuse.

Default admission preserves the original 16 GiB floor and requires zero other native processes. Lowering the caller to 12 GiB requires the explicit `RevisedSerial12GiB` parameter and a Root12GiB release identifier. Admission is sampled freshly before compile, metadata and runtime. Passing a parameter is not a substitute for an actual Root grant in the conversation. Body owns the earlier serial slot, and no heavy command is authorized by this preparation document.

The external reviewed owner must support `Executable`, `WorkingDirectory`, `Arguments`, `ReceiptBase` and `TimeoutSeconds` parameters, retain exact process identities, bound cancellation/pipe settlement, and independently establish original-identity absence. The caller does not modify or silently substitute an owner. Root currently holds the failed serial supervisor and is qualifying Body with the original proven 16 GiB owner; this caller remains unexecuted pending the reviewed owner and next explicit slot release.

## Frozen evidence

Before, between build/metadata, between metadata/runtime and after execution, the caller checks complete candidate and vendor path inventories/hashes, all 19,546 compiler files, the complete 1,838-file Node directory, control identities, Source42 authority and artifact hashes. The canonical 1,774-file executable/npm Source authority remains checked separately. Vendor contains exactly 1,316 files. Candidate traversal includes hidden input files and rejects undeclared directory links, excluding only `.git`, `.zig-cache` and `zig-out` output roots.

Attempt `admitted1` stopped before any native launch because the caller incorrectly equated the canonical executable/npm manifest with the whole Node installation directory. Exact inspection found 64 additional Corepack/root-shim files, with all 1,774 canonical hashes unchanged. The preserved preflight negative lists those paths/hashes at `native-async-function-qualification-Debug-admitted1-20261016-preflight-negative.json` in the evidence directory. The corrected caller freezes all 1,838 files and retains the original canonical checks; no file is omitted and no product, planned test or C-quota assertion changes.

`source42-authority-pins.json` seals 21 exact historical/reference files: both genuine Source outputs and their terminal/posthash/validation/control/module records, original raw input, current shared input and expected JSON, exact reviewed C/H patch and public readback. Both captures must remain successful with zero historical drift; their outputs must still equal the immutable expected JSON. Negative or partial native results are retained with full posthash; a failed compile, metadata mismatch, identity/resource failure or drift prohibits runtime continuation.

Root released the next serial slot with grant `ROOT-ASYNC25-16GiB-SERIAL-20261016`, selecting the original proven Body owner `run-owner.ps1`, SHA256 `B91945EF77F91388BB8792959AB29C3A49505B5381BA0994723AC0FC6E0502AB`, after the preceding native lane reached a terminal negative and its owned identities were absent. Fresh 16 GiB/zero-other-native admission remains mandatory; the failed revised supervisor is not reused. This document records authorization and prepared controls, not a runtime outcome. At sealing, only PowerShell parsing, static cohort enumeration and implementation whitespace checks had run; no Zig command, changed C execution or native test had run yet.
