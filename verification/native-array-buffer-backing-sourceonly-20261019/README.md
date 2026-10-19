# Native ArrayBuffer allocation ownership

Status: source-only, all assigned production and control peers closed. No build, metadata query or execution was performed for this unit. Root must qualify a fresh combined revision after intake because both QuickJS and the native allocation shim change.

Base: `2b7b761ecdbe7f3b7cfd23768257fd7f9325bc6e` in the existing public-modes worktree. Exact final source hashes, all 24 declaration names, peer scopes and evidence hashes are in [status.json](status.json). The eight added build lines register `build-native-vm-array-buffer-backing`, filter `VM backing`, for Windows and Linux. The target installs the real test artifact and does not run it.

## Why this allocation owner is needed

The existing VM can detach an ArrayBuffer even while a JavaScript Buffer or view is rooted. A retained JSValue therefore does not give a native asynchronous request a storage entitlement. This unit separates the allocation lifetime from the JavaScript wrapper and exposes a native lease over the actual intrinsic view span. No guest pointer, Engine pointer or runtime pointer is needed by the native worker.

The implementation uses the actual Node v24.13.0 vendored V8 storage behavior as its authority. The selected V8 sources and official URLs are retained in [authority/v8-selected-sources.json](authority/v8-selected-sources.json), with full remote-body hashes and explicit excerpt offsets. The packet is a selected-source record, not a complete V8 checkout. In particular, the original Node filesystem request's raw Buffer::Data/Length path is not evidence that that request explicitly retains a V8 BackingStore; no such claim is made here.

## Native allocation and accounting

`PiArrayBufferBacking` owns a stable data base, current byte length, maximum length, allocation reservation, committed-page count, atomic reference count and an independent `PiMemoryOwner` entitlement. Fixed buffers use a separate native allocation. Resizable buffers reserve a stable maximum address range and initially commit only the current data pages, plus the private owner prefix.

Windows uses VirtualAlloc/VirtualFree reserve, commit, decommit and final release. Linux uses mmap/mprotect/madvise/munmap. Charges cover the native owner, prefix and committed pages; uncommitted virtual capacity is not reported as committed memory. Allocation, reservation and permission failures unwind their actual charges. The native owner can outlive the originating runtime and the caller's memory-owner entitlement.

Shrink clears exactly the truncated bytes before decommitting whole pages. Regrowth changes permissions and length without overwriting an already committed partial page, so a native write to that still-committed storage after shrink is preserved. GSAB growth uses the shared native current length, monotonic growth and an atomic resize boundary. A smaller concurrent growth can report the existing invalid/race outcome; it does not reduce the current length.

The native hook is installed only on Windows and Linux. The Darwin path remains on its previous storage implementation because the retained V8 Darwin permission sequence includes behavior not implemented by this native owner.

## Borrowed input and native lease contract

`JS_PiAcquireArrayBufferView(ctx, view, out)` accepts a borrowed genuine TypedArray or DataView. It uses actual intrinsic brand, offset and length operations, not guest `buffer`, `byteOffset` or `byteLength` getters.

| Result | Meaning | Output |
| --- | --- | --- |
| 1 | Managed native allocation acquired | One owned native entitlement and the captured view span |
| 0 | Genuine external or otherwise unmanaged storage | Empty |
| -1 | Actual pending exception | Empty |

`JS_PiDupArrayBufferLease` creates one additional native entitlement in an empty destination. `JS_PiReleaseArrayBufferLease` clears its fields before releasing its entitlement. Retain/release operate on the independent native owner and can be used by a worker after both JavaScript wrapper and originating runtime are gone.

The captured span is an intrinsic snapshot. It does not lock detach or resize, and it does not promise that pages truncated by a later RAB shrink remain writable. Callers must respect the actual native operation's range and page-lifetime contract. This unit introduces no delayed copyback, no JS wrapper root masquerading as storage ownership and no blanket exclusion of RAB/GSAB inputs.

## Transfer, shared views and serialization

Managed fixed buffers of equal target length transfer the actual allocation: retain native entitlement, detach source, then construct the target wrapper. Zero-length transfer also detaches before creating the target. Changed fixed lengths and resizable transfers allocate and copy successfully before detaching the source. The retained V8 TransferArrayBuffer body supplies this ordering, including allocation failure behavior and the RAB maximum RangeError.

Current shared native length is observed across runtime wrappers. This unit refreshes the actual JSObject typed-array count reads and the relevant DataView/current-buffer seams; the three unrelated JSONParseRecord array-count reads remain unchanged. The cache-change packet lists all 130 JSObject-only replacements. Tracking DataView at offset equal to current length becomes a zero span, preserving its zero-span range failure.

Foreign public C storage is a separate ownership path. `JS_NewArrayBuffer(..., is_shared=true)` never supplies the trusted-reader discriminator, and an arbitrary external pointer is never inspected for a Pi prefix. Its original callback is retained and released exactly once; lease acquisition returns 0. A separate flag distinguishes actual legacy SAB allocator/clone entitlements from that foreign callback.

Only the actual same-process SAB reader supplies the trusted discriminator. Its tables are still trusted input; this unit does not validate arbitrary serialized native pointers. Managed runtimes reject serialization of a foreign SAB before its tag or table entry is emitted, with the ordinary error `external SharedArrayBuffer storage is not serializable`. Managed SAB roundtrip remains supported. This is an explicit foreign-serialization limit, not a full arbitrary C-reader guarantee.

The new rejection route can occur after a prior managed entry has already allocated the writer's SAB table. The failure label now frees that table before resetting output, preserving the original ordinary error. Control 12 retains the real allocator across full runtime teardown and requires used memory to return to zero, so the leak cannot be hidden by runtime destruction.

## Source review and controls

SDK reviewed the managed constructor/transfer/resize/view-lease paths, the JSObject-only cache replacements, the external-SAB correction, the partial-table release, declarations 1–12 and 19–23, and the eight-line build registration. Modules reviewed the Windows/Linux allocation/accounting/permissions owner and platform guard, declarations 13–18, the final exception/charge assertions in 14/16, and the wrapper-lifetime probe in 24. Root independently reviewed the full production, the 24-control predecessor, both corrective serialization deltas, and the bounded final 14/16 assertion readback.

The controls exercise actual linked-VM ArrayBuffer/SharedArrayBuffer behavior and real native entitlements. They cover view brands and pending entry, external callbacks, detach/GC, transfer identity and failure order, partial serialization cleanup, resize/page state/accounting, post-runtime native worker use, fresh runtime pairs for each shared-cache operation, and two independent runtime workers for concurrent growth. The final wrapper marker distinguishes allocation ownership from retaining the actual JavaScript buffer object.

Each concurrency fixture retains only the explicitly required native owners across its worker boundary and joins on failure. The Windows page control uses actual VirtualQuery. The quota controls use the real native memory owner. Current metadata counts and runtime outcomes remain unknown until Root's separately authorized build and execution.

## Evidence files

- [quickjs-backing.diff](quickjs-backing.diff): complete final QuickJS C/H delta against the stated base.
- [native-storage.diff](native-storage.diff): complete final native allocation-shim delta.
- [selected-production-and-cache-reads.json](selected-production-and-cache-reads.json): exact current selected bodies, prior bodies and all 130 cache-read changes.
- [external-sab-provenance-delta.json](external-sab-provenance-delta.json): exact thirteen-edit provenance correction and its causal external-buffer control.
- [partial-table-cleanup-delta.json](partial-table-cleanup-delta.json): the single failure-label table release and mixed-buffer teardown control.
- [control-assertion-successor.json](control-assertion-successor.json): exact declaration 14/16 replacements, with pending-exception and memory-accounting assertions strengthened.
- [build-intake.patch](build-intake.patch): eight additive install-only build lines.

The existing QuickJS 2 GiB buffer limit and bytecode version are unchanged. Broader preexisting TypedArray/DataView semantics, actual FileHandle scheduling, and complete net/HTTP publication remain separately qualified work.
