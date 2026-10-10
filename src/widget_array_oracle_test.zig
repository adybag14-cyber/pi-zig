//! Independent actual-original string-array widget clipping and wrapping oracle.
const std = @import("std");
const engine_mod = @import("extensions/engine.zig");
const widgets = @import("extensions/native_widgets.zig");
const c = engine_mod.c;
fn replay(capture: []const u8) !void {
    const gpa = std.testing.allocator;
    var data = try std.json.parseFromSlice(std.json.Value, gpa, capture, .{});
    defer data.deinit();
    for (data.value.object.get("cases").?.array.items) |item| {
        const engine = try engine_mod.Engine.init(gpa, .{});
        defer engine.deinit();
        var manager = try widgets.Manager.init(engine);
        manager.attach();
        defer manager.deinit();
        try manager.addOwner(1);
        manager.width = @intCast(item.object.get("width").?.integer);
        const theme = try engine.eval("({fg:(_,text)=>text})", "widget-array-theme.js", c.JS_EVAL_TYPE_GLOBAL);
        defer engine.freeValue(theme);
        const array = try engine.fromJsonValue(item.object.get("input").?);
        defer engine.freeValue(array);
        try manager.set(1, "array", array, .aboveEditor, theme);
        const component = manager.entries.items[0].component;
        var args = [_]c.JSValue{c.JS_NewInt64(engine.context, @intCast(manager.width))};
        defer engine.freeValue(args[0]);
        const result = (try @import("extensions/native_components.zig").callMethod(engine, component, "render", &args, false)).?;
        defer engine.freeValue(result);
        const actual = try engine.stringify(result);
        defer gpa.free(actual);
        var expected: std.Io.Writer.Allocating = .init(gpa);
        defer expected.deinit();
        try std.json.Stringify.value(item.object.get("lines").?, .{}, &expected.writer);
        try std.testing.expectEqualStrings(expected.written(), actual);
    }
}
test "widget arrays preserve actual upstream ten input line clipping text margins and narrow wrapping" {
    try replay(@embedFile("extensions/fixtures/widget-array-original-7fb.json"));
}
test "widget arrays preserve actual upstream ANSI state hyperlink terminators Unicode boundaries and literal newlines" {
    try replay(@embedFile("extensions/fixtures/widget-styled-original-7fb.json"));
}
test "native narrow Text primitive matches the original retained empty rows around wide clusters" {
    const gpa = std.testing.allocator;
    var fixture = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("extensions/fixtures/widget-text-primitive-original-7fb.json"), .{});
    defer fixture.deinit();
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    try @import("extensions/native_tui.zig").install(engine);
    const module = try engine.evalModule("import {Text} from 'pi-tui';export const lines=new Text('界😀',0,0).render(1)", "widget-narrow-original.mjs");
    defer engine.freeValue(module);
    const lines = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "lines"));
    defer engine.freeValue(lines);
    const actual = try engine.stringify(lines);
    defer gpa.free(actual);
    var expected: std.Io.Writer.Allocating = .init(gpa);
    defer expected.deinit();
    try std.json.Stringify.value(fixture.value.object.get("lines").?, .{}, &expected.writer);
    try std.testing.expectEqualStrings(expected.written(), actual);
}
