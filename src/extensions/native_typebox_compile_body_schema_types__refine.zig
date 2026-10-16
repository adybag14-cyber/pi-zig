//! Direct native bodies from pinned typebox@1.3.27. Source-only pending qualification.
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const o = @import("native_typebox_compile_ops.zig");
const ordinary = @import("native_node_function.zig");
const class = @import("native_class.zig");
const sdk = @import("native_sdk.zig");
const c = js.c;
const Engine = js.Engine;
pub fn prepare(e: *Engine, graph: c.JSValue) !void {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const modules = try s.get(graph, "modules");
    const namespace = try s.get(modules, "schema/types/_refine.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/_refine.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/_refine.mjs", bindings);
    const v21043 = try s.own(try ordinary.create(e, "IsRefine", 1, body20970, &.{ graph, frame }));
    try o.assign(&s, frame, "binding20969", v21043);
    const v21044 = try o.lookup(&s, frame, "binding20969");
    try s.put(namespace, "IsRefine", v21044);
    const v21045 = try o.lookup(&s, frame, "binding20969");
    try s.put(namespace, "IsRefine", v21045);
    try s.put(bindings, "IsRefine", try s.text("binding20969"));
}
fn body20998(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v21001 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21000", v21001);
    const v21002 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21003 = try s.text("IsObject");
    const v21004 = try s.own(try js.getKey(e, v21002, v21003));
    const v21005 = try o.lookup(&s, frame, "binding21000");
    const v21006 = try o.call(&s, @src(), v21004, v21002, &.{v21005});
    const v21008 = logical21007: {
        if (!s.truthy(v21006)) break :logical21007 v21006;
        const v21009 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21010 = try s.text("HasPropertyKey");
        const v21011 = try s.own(try js.getKey(e, v21009, v21010));
        const v21012 = try o.lookup(&s, frame, "binding21000");
        const v21013 = try s.text("check");
        const v21014 = try o.call(&s, @src(), v21011, v21009, &.{ v21012, v21013 });
        break :logical21007 v21014;
    };
    const v21016 = logical21015: {
        if (!s.truthy(v21008)) break :logical21015 v21008;
        const v21017 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21018 = try s.text("HasPropertyKey");
        const v21019 = try s.own(try js.getKey(e, v21017, v21018));
        const v21020 = try o.lookup(&s, frame, "binding21000");
        const v21021 = try s.text("error");
        const v21022 = try o.call(&s, @src(), v21019, v21017, &.{ v21020, v21021 });
        break :logical21015 v21022;
    };
    const v21024 = logical21023: {
        if (!s.truthy(v21016)) break :logical21023 v21016;
        const v21025 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21026 = try s.text("IsFunction");
        const v21027 = try s.own(try js.getKey(e, v21025, v21026));
        const v21028 = try o.lookup(&s, frame, "binding21000");
        const v21029 = try s.text("check");
        const v21030 = try s.own(try js.getKey(e, v21028, v21029));
        const v21031 = try o.call(&s, @src(), v21027, v21025, &.{v21030});
        break :logical21023 v21031;
    };
    const v21033 = logical21032: {
        if (!s.truthy(v21024)) break :logical21032 v21024;
        const v21034 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21035 = try s.text("IsFunction");
        const v21036 = try s.own(try js.getKey(e, v21034, v21035));
        const v21037 = try o.lookup(&s, frame, "binding21000");
        const v21038 = try s.text("error");
        const v21039 = try s.own(try js.getKey(e, v21037, v21038));
        const v21040 = try o.call(&s, @src(), v21036, v21034, &.{v21039});
        break :logical21032 v21040;
    };
    return c.JS_DupValue(e.context, v21033);
}
fn body20998C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body20998(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body20970(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v20972 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20971", v20972);
    const v20973 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v20974 = try s.text("HasPropertyKey");
    const v20975 = try s.own(try js.getKey(e, v20973, v20974));
    const v20976 = try o.lookup(&s, frame, "binding20971");
    const v20977 = try s.text("~refine");
    const v20978 = try o.call(&s, @src(), v20975, v20973, &.{ v20976, v20977 });
    const v20980 = logical20979: {
        if (!s.truthy(v20978)) break :logical20979 v20978;
        const v20981 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v20982 = try s.text("IsArray");
        const v20983 = try s.own(try js.getKey(e, v20981, v20982));
        const v20984 = try o.lookup(&s, frame, "binding20971");
        const v20985 = try s.text("~refine");
        const v20986 = try o.propertyKey(&s, v20985);
        const v20987 = try s.own(try js.getKey(e, v20984, v20986));
        const v20988 = try o.call(&s, @src(), v20983, v20981, &.{v20987});
        break :logical20979 v20988;
    };
    const v20990 = logical20989: {
        if (!s.truthy(v20980)) break :logical20989 v20980;
        const v20991 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v20992 = try s.text("Every");
        const v20993 = try s.own(try js.getKey(e, v20991, v20992));
        const v20994 = try o.lookup(&s, frame, "binding20971");
        const v20995 = try s.text("~refine");
        const v20996 = try o.propertyKey(&s, v20995);
        const v20997 = try s.own(try js.getKey(e, v20994, v20996));
        const v21041 = try o.arrow(&s, "", 1, body20998C, &.{ graph, frame });
        const v21042 = try o.call(&s, @src(), v20993, v20991, &.{ v20997, c.JS_NewFloat64(e.context, 0), v21041 });
        break :logical20989 v21042;
    };
    return c.JS_DupValue(e.context, v20990);
}
