const std = @import("std");
const builtin = @import("builtin");
const latest = @import("native_chord_latest_source_test.zig");
const js = @import("extensions/native_js_values.zig");
test "native latest Chord1692 NodeLoader actual Source7 roots imports generations TypeScript defaults and Host teardown" {
    const engine = try latest.setup(std.testing.allocator);
    defer engine.deinit();
    const root = js.c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const api = try js.get(engine, root, "nativeLatestChordApi");
    defer engine.freeValue(api);
    try js.define(engine, api, "nodeLoader", try @import("extensions/native_chord_node_loader.zig").create(engine));
    const physical = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, "src/extensions/fixtures/chord-node-loader-1692", std.testing.allocator);
    defer std.testing.allocator.free(physical);
    const url = try @import("extensions/file_urls.zig").fromPath(std.testing.allocator, physical, builtin.os.tag == .windows);
    defer std.testing.allocator.free(url);
    const directory = try std.fmt.allocPrint(std.testing.allocator, "{s}/", .{url});
    defer std.testing.allocator.free(directory);
    try js.define(engine, root, "chordLoaderFixtureRoot", try engine.checked(js.c.JS_NewStringLen(engine.context, directory.ptr, directory.len)));
    try latest.replay(engine, "chord-node-loader-original-1692", "chordNodeLoaderCases");
    js.c.JS_RunGC(engine.runtime);
}
