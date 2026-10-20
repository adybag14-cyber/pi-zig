# Native whole backing-store allocation and ArrayBuffer adoption

Status: source authored and peer reviewed as recorded in the finite receipts.
No native build, runtime execution, Node run, formatter, or generator is claimed.

## Implemented operation

This unit creates a fixed, non-shared native allocation before a JavaScript
ArrayBuffer exists. The caller owns a `JSPiArrayBufferBackingStore` record with
one actual storage entitlement, its immutable byte length, and a copy of the
installed native provider callbacks and allocation-domain pointer. There is no
JS value, context, Engine, or runtime pointer in the record.

`JS_PiTryNewArrayBufferBackingStore` performs exactly one native allocation
attempt. It returns 1 for success, 0 when no provider is installed, and -1 when
that attempt fails. The destination must start empty and remains empty on
failure. The operation creates no JS wrapper, runs no collection, and changes
neither pending exceptions nor the actual VM OOM occurrence counter.

The separate native uninitialized flag selects `malloc` in the existing fixed
provider. Existing JS-created buffers still select `calloc`; resizable/shared
storage cannot request the new mode. Both modes retain the existing charged
native owner, atomic references, prefix, rollback, and final release.

Native Data and ByteLength read the whole store. Zero-length storage has a real
non-null owner and a null logical Data. The provider's private empty-buffer
sentinel remains internal to QuickJS. Duplicate adds one native reference;
Release clears the complete caller record before releasing that reference.
Distinct records may be used by native workers after the original runtime and
the caller's allocator reference have retired. Concurrent mutation of one record
is outside the contract.

`JS_PiAdoptArrayBufferBackingStore` consumes and clears the caller's record on
every result. Existing actual pending prevents any wrapper allocation and is
preserved. Adoption requires the same installed callbacks and native allocation
domain. It then transfers the existing entitlement to the unchanged
`js_array_buffer_constructor4` owner. That constructor creates the intrinsic
ArrayBuffer, copies no bytes, and releases the entitlement on failure. The
resulting wrapper supports the existing native view lease, detach, and transfer
operations.

## Original source and scope

The exact source packet preserves Node v24.13.0 at
`def0bdf8abee441cfcbf793a8dc24a6f3b899573`:

- Environment creates an uninitialized native BackingStore before publishing the
  UV buffer and moves the owner out of its native map on completion.
- A short read allocates its smaller store, copies the real read extent, and
  destroys the old store before the later ArrayBuffer wrapper construction.
- V8 has a genuine zero-length native BackingStore with null logical Data.
- `ArrayBuffer::New` consumes the native store at the later wrapper step.

`source-proof.json` verifies ten full original files and all eighteen exact
excerpts in the copied SDK proposal. The separately copied retry/fatal proof
retains the complete V8 external-allocation retry operation and the distinct
process-OOM site.

**This primitive does not implement that retry or terminal policy.** The actual
conditional young collection, two old-space collection/retry attempts, final
all-available collection, and default fatal site
`v8::ArrayBuffer::NewBackingStore` remain the embedding's separately required
owners. They are not replaced by one `JS_RunGC`, a heap-OOM handler, or an
ordinary JavaScript error.

The selected StreamBase caller allocates and adopts in one Environment. This
unit explicitly rejects cross-domain adoption. The linked VM's existing
ArrayBuffer size bound remains unchanged. Windows and Linux install the
admitted managed provider; other platforms retain their existing provider
availability. No StreamBase map, onread callback, public API, bootstrap,
reporter, or full FileHandle qualification is claimed.

## Controls and build seam

The twenty declarations in
`src/native_vm_backing_store_adoption_test.zig` use the actual linked VM and
native storage provider. They cover:

| Declarations | Causal observation |
| --- | --- |
| 1–4 | Allocation before a context, no JS heap allocation, actual byte identity, initialized mode, and owned zero length |
| 5–6 | Independent native references/charge retirement and intrinsic adoption despite a poisoned public constructor |
| 7–10 | Actual wrapper heap failure and preserved ordinary, generic-fatal, and private-termination pending outcomes |
| 11–14 | Native quota/overflow rollback, unavailable provider, mismatched allocation domain, and absent versus zero-length owner |
| 15–16 | Two joined native workers after runtime retirement and old short-read allocation retirement before adoption |
| 17–20 | View leases/detach, two wrappers from explicit duplication, equal/changed transfer, and unchanged JS/RAB/GSAB zero initialization |

Every raw JS outcome and extracted reason is owned before assertions. Heap
limits are restored before checks; native budgets are released before later
work. Worker failure cleanup joins the exact started threads before releasing
their storage records. The native memory owner survives until its last backing
reference retires.

The build packet adds exactly eight lines under the existing Windows/Linux
platform selection, reuses the shared QuickJS linkage, and adds installation
only:

- Root: `src/native_vm_backing_store_adoption_test.zig`
- Filter: `VM native backing store`
- Target: `build-native-vm-backing-store-adoption`
- Declarations: 20

## Intake

Apply the exact five steps in `production-delta.json` to the selected Main
union: one QuickJS C insertion, two header additions, and two native-provider
edits. The preserved complete bases and inverse checks are evidence; they are
not replacements for Main files. Apply the separate eight-line build insertion
from `build-intake.json`, and add the control root and this evidence directory.
This preserves Main's separate private-property and lazy-prototype additions.

All five production steps and the build insertion have exact reverse checks.
The final manifest identifies the actual current bytes and finite peer scopes.
