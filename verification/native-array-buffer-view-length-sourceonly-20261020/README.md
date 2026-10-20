# Intrinsic ArrayBufferView byte length

Status: source reviewed; not compiled or executed. This unit introduces the narrow VM operation required by the selected Node v24.13 native Read binding. It does not qualify that binding or the whole filesystem graph.

## Contract

`size_t JS_PiArrayBufferViewByteLength(JSValueConst view)` borrows a value on the VM owner thread. It reports the intrinsic current byte length of an actual TypedArray or DataView. Detached or out-of-bounds views, invalid brands and proxies return zero. The caller of the selected native Read checks the genuine view brand before using this result.

The operation performs no allocation, guest operation, pending-exception mutation or backing-owner retention. It takes one current backing-length snapshot. Fixed views use their original bounds, tracking DataViews retain byte precision, and tracking TypedArrays round down to their element width. The existing throwing buffer-view accessor and independent storage lease remain byte-identical.

## Source authority

`source-proof.json` retains the selected Node Buffer::Length and pinned V8 API/GetByteLength bodies, plus the actual QuickJS view and backing layout. The immutable Node revision is def0bdf8abee441cfcbf793a8dc24a6f3b899573. `production-delta.json` records the exact two additions. `isolated-intake.json` proves the production addition against the clean logging19 parent, independently of unfinished constructor metadata in the working tree.

## Controls and build

The manifest lists all 11 declarations. They cover every typed-array element width, DataView precision, getter and proxy nonentry, detach versus the existing throwing lease, RAB bounds and regrowth, shared growth including two fresh foreign-runtime clones, heap-limit operation, exact prior ordinary and uncatchable reasons, borrowed ownership and unmanaged external storage.

The eight-line build addition is guarded to Windows/Linux, uses the existing shared QuickJS library and installs the real test artifact only. Target: `build-native-vm-array-buffer-view-length`. Filter: `VM view byteLength`.

## Finite source reviews

- SDK closed the two production additions against source-proof 54993739, declarations 1-7 and Clone at 7BBCD791, then the exact three const-argv casts at final EB50A3A8.
- Modules closed Fixture/External, declarations 8-11 and the eight-line build at final EB50A3A8 / 11ACD2DA.
- The const-argv successor changes only three pointer casts required by the actual C header; no assertion or operation was changed.

The current source pins and complete declaration names are in `manifest.json`. These receipts are source review only. No build, runtime, scheduling or broad typed-array behavior claim is made.
