//! Direct native bodies from pinned typebox@1.3.27. Source-only pending qualification.
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const o = @import("native_typebox_compile_ops.zig");
const ordinary = @import("native_legacy_function.zig");
const class = @import("native_class.zig");
const sdk = @import("native_sdk.zig");
const c = js.c;
const Engine = js.Engine;
pub fn prepare(e: *Engine, graph: c.JSValue) !void {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const modules = try s.get(graph, "modules");
    const namespace = try s.get(modules, "value/codec/callback.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/codec/callback.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/codec/callback.mjs", bindings);
    const v23984 = try s.own(try ordinary.create(e, "Decode", 3, body23969, &.{ graph, frame }));
    try o.assign(&s, frame, "binding23966", v23984);
    const v24000 = try s.own(try ordinary.create(e, "Encode", 3, body23985, &.{ graph, frame }));
    try o.assign(&s, frame, "binding23967", v24000);
    const v24032 = try s.own(try ordinary.create(e, "Callback", 4, body24001, &.{ graph, frame }));
    try o.assign(&s, frame, "binding23968", v24032);
    const v24033 = try o.lookup(&s, frame, "binding23968");
    try s.put(namespace, "Callback", v24033);
    const v24034 = try o.lookup(&s, frame, "binding23968");
    try s.put(namespace, "Callback", v24034);
    try s.put(bindings, "Callback", try s.text("binding23968"));
}
fn body23969(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v23973 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23970", v23973);
    const v23974 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23971", v23974);
    const v23975 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23972", v23975);
    const v23976 = try o.lookup(&s, frame, "binding23971");
    const v23977 = try s.text("~codec");
    const v23978 = try o.propertyKey(&s, v23977);
    const v23979 = try s.own(try js.getKey(e, v23976, v23978));
    const v23980 = try s.text("decode");
    const v23981 = try s.own(try js.getKey(e, v23979, v23980));
    const v23982 = try o.lookup(&s, frame, "binding23972");
    const v23983 = try s.call(v23981, v23979, &.{v23982});
    return c.JS_DupValue(e.context, v23983);
}
fn body23985(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v23989 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23986", v23989);
    const v23990 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23987", v23990);
    const v23991 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23988", v23991);
    const v23992 = try o.lookup(&s, frame, "binding23987");
    const v23993 = try s.text("~codec");
    const v23994 = try o.propertyKey(&s, v23993);
    const v23995 = try s.own(try js.getKey(e, v23992, v23994));
    const v23996 = try s.text("encode");
    const v23997 = try s.own(try js.getKey(e, v23995, v23996));
    const v23998 = try o.lookup(&s, frame, "binding23988");
    const v23999 = try s.call(v23997, v23995, &.{v23998});
    return c.JS_DupValue(e.context, v23999);
}
fn body24001(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v24006 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24002", v24006);
    const v24007 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24003", v24007);
    const v24008 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24004", v24008);
    const v24009 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24005", v24009);
    const v24010 = try o.importValue(&s, graph, "type/index.mjs", "IsCodec");
    const v24011 = try o.lookup(&s, frame, "binding24004");
    const v24012 = try s.call(v24010, c.pi_js_undefined(), &.{v24011});
    if (s.truthy(o.boolean(&s, !s.truthy(v24012)))) {
        const v24013 = try o.lookup(&s, frame, "binding24005");
        return c.JS_DupValue(e.context, v24013);
    }
    const v24014 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v24015 = try s.text("IsEqual");
    const v24016 = try s.own(try js.getKey(e, v24014, v24015));
    const v24017 = try o.lookup(&s, frame, "binding24002");
    const v24018 = try s.text("Decode");
    const v24019 = try s.call(v24016, v24014, &.{ v24017, v24018 });
    const v24021 = conditional24020: {
        if (s.truthy(v24019)) {
            const v24022 = try o.lookup(&s, frame, "binding23966");
            const v24023 = try o.lookup(&s, frame, "binding24003");
            const v24024 = try o.lookup(&s, frame, "binding24004");
            const v24025 = try o.lookup(&s, frame, "binding24005");
            const v24026 = try s.call(v24022, c.pi_js_undefined(), &.{ v24023, v24024, v24025 });
            break :conditional24020 v24026;
        } else {
            const v24027 = try o.lookup(&s, frame, "binding23967");
            const v24028 = try o.lookup(&s, frame, "binding24003");
            const v24029 = try o.lookup(&s, frame, "binding24004");
            const v24030 = try o.lookup(&s, frame, "binding24005");
            const v24031 = try s.call(v24027, c.pi_js_undefined(), &.{ v24028, v24029, v24030 });
            break :conditional24020 v24031;
        }
    };
    return c.JS_DupValue(e.context, v24021);
}
