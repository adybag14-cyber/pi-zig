const std = @import("std");
const latest = @import("native_chord_latest_source_test.zig");
const js = @import("extensions/native_js_values.zig");
const em = @import("extensions/engine.zig");
fn setup(gpa: std.mem.Allocator) !*em.Engine {
    const engine = try latest.setup(gpa);
    errdefer engine.deinit();
    const bindings = try js.global(engine, "nativeLatestChordBindings");
    defer engine.freeValue(bindings);
    const api = try js.global(engine, "nativeLatestChordApi");
    defer engine.freeValue(api);
    const manager = try @import("extensions/native_chord_manager_api.zig").exports(engine, bindings);
    defer engine.freeValue(manager);
    try js.spreadInto(engine, api, manager);
    return engine;
}
test "native latest Chord1692 Manager actual Source9 serialized driver ready fatal timeouts liveness replacement child control" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    try latest.replay(engine, "chord-manager-original-1692", "chordManagerCases");
    js.c.JS_RunGC(engine.runtime);
}
test "native latest Chord1692 Manager actual Source3 kernel exclusive process lock independent names and release" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    try latest.replay(engine, "chord-process-lock-original-1692", "chordProcessLockCases");
    js.c.JS_RunGC(engine.runtime);
}
