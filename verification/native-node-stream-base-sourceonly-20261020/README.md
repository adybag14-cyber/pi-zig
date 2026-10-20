# Actual native StreamResource lifetime

This source-only unit implements the selected Node v24.13 StreamResource and StreamListener linked-list lifetime. It includes the real push/remove order, native assertion sites, listener unlinking, and destruction that permits a callback to unlink and free its own native record or modify the remaining chain.

The implementation requires records at stable native addresses and an Engine diagnostic context that remains alive through destruction. Callback data and JavaScript roots are not retained by this owner. StreamBase must destroy its embedded default_listener_ member before the StreamResource base. The eight controls include the corresponding native call sequence, while actual StreamBase composition remains separate.

## Exact boundaries

Production is `src/extensions/native_node_stream_resource.zig` (97D16E84). The root is `src/native_node_stream_resource_test.zig` (9FFEC85C), with eight actual native controls. Source authority is the complete immutable Node revision def0bdf8abee441cfcbf793a8dc24a6f3b899573 stream_base.cc, stream_base.h and stream_base-inl.h. The adjacent node_file.h is retained original context for the forthcoming consumer, with no FileHandle production in this unit.

`stream-resource-source.json` preserves six exact selected source ranges and their complete-file pins. Its original draft status is retained. `source-closure.json` is the final finite source receipt.

Modules independently closed production and controls 5–8, including actual charged native self-deletion and reentrant list mutation. Root independently closed Fixture and controls 1–4, plus the thirteen-line install-only build proposal DFB07288. All control names and assertions are retained.

## Intake and limits

Apply the unique insertion in `stream-resource-build-intake.json` to build.zig after reviewing the current anchor. It reuses the existing guarded Engine/QuickJS/TypeScript/sqlite/catalog graph and Windows libraries. It installs `native-node-stream-resource` through `build-native-node-stream-resource`; it has no run edge or second UV library.

No build.zig mutation, compiler, native test, Node, generator, formatter or AST execution was performed for this unit. Native CHECK failure paths still need separate terminating-process qualification; the source records exact assertion expressions and source sites, without claiming compiler-specific PRETTY_FUNCTION_NAME text. StreamBase virtual I/O, default read/write callbacks, public prototype, FileHandle class, Environment bootstrap and complete shutdown composition are outside this unit.
