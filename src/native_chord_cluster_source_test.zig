const std = @import("std");
const latest = @import("native_chord_latest_source_test.zig");
test "native latest Chord1692 Cluster compiled inventory" {
    try latest.inventory("CHORD_CLUSTER_COMPILED_INVENTORY");
}
test "native latest Chord1692 Cluster actual Source4 prepare commit retained roots failed vote removal reconciliation" {
    const engine = try latest.setup(std.testing.allocator);
    defer engine.deinit();
    try latest.replay(engine, "chord-cluster-original-1692", "chordClusterCases");
    @import("extensions/engine.zig").c.JS_RunGC(engine.runtime);
}
