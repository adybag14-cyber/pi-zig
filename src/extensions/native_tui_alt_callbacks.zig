//! Real Source array callbacks with GC-rooted lexical captures. Guest code may
//! retain these functions; no callback captures a pointer to a temporary Frame.
const a = @import("native_tui_alt_frame.zig");
const Frame = a.Frame;
const js = a.js;
const c = a.c;
const v = a.v;
pub const Kind = enum(c_int) { empty, unwrap, sum, max, maxWidth, hasCursor, intrinsic, childHeight, stripZones, removeCursor, clampLine, changedRow, imageAnchor, imageCells, isImage, kittyLine, selectionLine, clickedSegment };
pub fn context(f: *Frame) !c.JSValue {
    return f.record();
}
pub fn create(f: *Frame, kind: Kind, capture: c.JSValue) !c.JSValue {
    const length: c_int = switch (kind) {
        .empty => 0,
        .sum, .max, .maxWidth, .childHeight, .changedRow, .imageAnchor, .imageCells, .selectionLine => 2,
        else => 1,
    };
    var data = [_]c.JSValue{ f.object, f.bindings, capture };
    return f.own(try f.engine.checked(c.JS_NewCFunctionData2(f.engine.context, call, "", length, @intFromEnum(kind), 3, &data)));
}
pub fn map(f: *Frame, array: c.JSValue, kind: Kind, capture: c.JSValue) !c.JSValue {
    // Evaluate the member before constructing the argument callback, just as
    // the Source call expression does. A guest getter can replace bindings.
    const function = try f.get(array, "map");
    return f.call(function, array, &.{try create(f, kind, capture)});
}
pub fn reduce(f: *Frame, array: c.JSValue, kind: Kind, capture: c.JSValue) !c.JSValue {
    const function = try f.get(array, "reduce");
    return f.call(function, array, &.{ try create(f, kind, capture), f.num(0) });
}
pub fn some(f: *Frame, array: c.JSValue, kind: Kind, capture: c.JSValue) !c.JSValue {
    const function = try f.get(array, "some");
    return f.call(function, array, &.{try create(f, kind, capture)});
}
fn call(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(ctx.?);
    var f: Frame = .{ .engine = engine, .object = data[0], .bindings = data[1] };
    defer f.deinit();
    const result = body(&f, @enumFromInt(magic), data[2], if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| return a.fail(engine, err);
    return f.result(result);
}
fn body(f: *Frame, kind: Kind, capture: c.JSValue, args: []const c.JSValue) anyerror!c.JSValue {
    const first = v.arg(args, 0);
    const second = v.arg(args, 1);
    switch (kind) {
        .empty => return f.text(""),
        .unwrap => return f.own(try js.getKey(f.engine, first, capture)),
        .sum => return f.add(first, second),
        .max => return f.num(try f.math("max", &.{ first, second })),
        .maxWidth => return f.num(try f.math("max", &.{ first, f.num(try f.width(second)) })),
        .hasCursor => return f.method(first, "includes", &.{try f.get(f.bindings, "CURSOR_MARKER")}),
        .intrinsic => {
            if (c.JS_IsNumber(try f.get(first, "basis"))) return f.get(first, "basis");
            return @import("native_tui_layout.zig").measureValue(f, try f.get(capture, "context"), try f.get(first, "component"), try f.n(capture, "width"), f.truth(try f.get(capture, "horizontal")));
        },
        .childHeight => return @import("native_tui_layout.zig").measureValue(f, try f.get(capture, "context"), try f.get(first, "component"), try f.math("max", &.{ f.num(1), try f.own(try js.getKey(f.engine, try f.get(capture, "sizes"), second)) }), false),
        .stripZones => return f.method(first, "replace", &.{ try f.get(f.bindings, "osc133ZonePrefix"), try f.text("") }),
        .removeCursor => return f.method(first, "replaceAll", &.{ try f.get(f.bindings, "CURSOR_MARKER"), try f.text("") }),
        .clampLine => {
            if (f.truth(try f.imported("isImageLine", &.{first})) or try f.width(first) <= try f.n(capture, "width")) return first;
            return f.imported("sliceByColumn", &.{ first, f.num(0), try f.get(capture, "width"), f.boolean(true) });
        },
        .changedRow => return f.boolean(!f.equal(first, try f.own(try js.getKey(f.engine, try f.field("previousScreen"), second)))),
        .imageAnchor => {
            const changed = try f.own(try js.getKey(f.engine, try f.get(capture, "changedRows"), second));
            if (!f.truth(changed)) return changed;
            const image = try f.imported("isImageLine", &.{first});
            if (f.truth(image)) return image;
            return f.imported("isImageLine", &.{try f.emptyLine(try f.field("previousScreen"), try f.number(second))});
        },
        .imageCells => {
            const rows = try f.imported("getKittyImagePlacementRows", &.{first});
            if (c.JS_IsUndefined(rows)) return f.boolean(false);
            var row = try f.number(second);
            while (row < try f.number(second) + try f.number(rows)) : (row += 1) {
                if (f.truth(try f.at(try f.get(capture, "changedRows"), row))) return f.boolean(true);
            }
            return f.boolean(false);
        },
        .isImage => return f.imported("isImageLine", &.{first}),
        .kittyLine => return @import("native_tui_alt_render.zig").kittyLine(f, first, try f.get(capture, "visibleImageIds")),
        .selectionLine => return @import("native_tui_alt_selection.zig").selectionLine(f, first, second, capture),
        .clickedSegment => return f.boolean(try f.n(capture, "col") >= try f.n(first, "start") and try f.n(capture, "col") < try f.n(first, "end")),
    }
}
