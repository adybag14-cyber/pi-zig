# Native supplied MapKVStore source unit

This unit implements the private native MapKVStore leaf using the pinned libc++ string and unordered_map templates with the shared charged allocator. It preserves the original C-string Get/Query versus full-span Set/Delete selection, real temporary-key allocations, optional and JS-local value copies, locked unsorted iteration, and native clone expression. It contains 22 source-authored controls; none has been executed under this source-only unit.

## Intake

Apply the source commit and then the exact changes in shared-native-memory-build-proposal.json, followed by map-controls-build-intake.json. The new tools/build_native_node_memory.zig file is included in the source commit. Existing build.zig, network helper and parser helper are deliberately not overwritten from this older worktree. The proposals bind their complete Main baselines and exact reversible edits. They compile native_simdjson_memory.cpp once and share that same static-library object between the parser and network/Map consumers.

## Review

The final manifest and four peer receipts record the production, all 22 controls, native allocator/lifetime and build/link source closures. The historical map-native-container-source.json and map-controls-source-draft.json remain byte-identical; their earlier pending-status prose records the draft stage. The final manifest records the present review status.

## Remaining integration

The native Environment State, actual environment-object handlers, Permission, path/cwd/execPath composition and shared Engine/process proposal are separate. This unit does not implement process-wide RealEnvStore, guest interceptors or a complete Node environment. It admits the pinned libc++ implementation; it makes no allocation-layout or iteration-order claim about a foreign Node binary built with another standard library.

Standard allocation failure follows the actual native new_handler and bad_alloc path. The quota controls temporarily install a real process-global handler in their isolated serial test process and restore it before returning. No JavaScript heap OOM or synthetic error substitutes for native container failure.
