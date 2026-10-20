# Native managed-buffer table and twelve raw controls

This source unit implements the selected pointer-key managed-buffer table from Node 24.13's Environment. It uses the actual standard `std::unordered_map<char*, ...>` operations and the shared native standard allocator. A move-only mapped value owns the complete VM backing-store token, including its native provider callbacks and allocation domain. It does not reconstruct ownership from a raw data pointer.

Allocation of the native backing precedes this table operation. Adoption constructs the original `uv_buf_t` before `emplace` and consumes the supplied token, including duplicate-key outcomes. Release bypasses lookup for a null base; otherwise it finds the exact base, performs the original native CHECK if absent, moves the token out, and then erases the native map node. The moved-out token can survive table destruction and the originating VM.

## Representation and allocation

The VM token is stored inline in the mapped native node. It is larger than V8's original unique_ptr representation. This unit preserves the selected container operations and ownership order, but makes no claim of identical node size or byte-charge peaks. There is no extra token box or separate empty-map allocation.

The native table reports its actual size/alignment and supports placement construction. The Zig Store adapter clears its native pointer before destruction. The separately proposed Environment delta places this table after the existing Environment fields in one charged native block and retires it before the earlier StreamBase alias. That ten-edit Environment proposal is retained for Root review; it is not applied to the production Environment by this commit.

## Concrete dependencies

- VM backing allocation/adoption: `eb4ec1d69c8d21dbd1079f29882654a37b485f24`, with complete native tokens and consuming intrinsic ArrayBuffer adoption.
- Standard allocator and one shared native-memory implementation: Modules `78b8ddf58c9b101a2afd4948ff2ed8f1ded7de63`, including allocator header `16D82D2C` and the single TLS/Compile owner in build proposal `0427BE86`.
- Existing genuine native assertion owner for the selected missing-entry CHECK. No guest throw substitutes for that condition.

The install-only proposal `managed-buffers-build-intake.json` adds four network-source lines and one twelve-control target after the Map22 proposal. It reuses the same shared memory implementation; it does not compile another copy of native_simdjson_memory.cpp. Root must compose later independent network additions by their exact anchors.

## Review and controls

Both independent production slices are closed: Modules reviewed original container/order semantics, and VM reviewed complete-token native lifetime and move/retirement. The twelve actual raw controls cover native storage before a context, consumption before a wrapper, exhausted-JS-heap nonentry, base-only lookup, null/zero/duplicate semantics, move-out lifetime, later intrinsic adoption, actual-pending preservation, real native new_handler retry and complete retirement after the originating runtime. Raw values/tokens are owned before assertions. Modules also closed the exact build proposal.

The source receipts under `peers/` retain those finite closures. `managed-backing-source-and-abi-proposal.json` is the original source-order record; its historical open-prerequisite list remains unchanged. The current status and concrete dependencies are in `managed-buffers-intake.json`.

This is not the complete NewBackingStore retry/GC/default-fatal owner, a public StreamBase implementation, or an installed Environment/lifecycle graph. The raw controls use the actual single-attempt VM primitive where stated. No compiler, tests, Node process, formatter or generator was executed for this unit.
