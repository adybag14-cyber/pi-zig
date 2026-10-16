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
    const namespace = try s.get(modules, "value/create/from_object.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/create/from_object.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/create/from_object.mjs", bindings);
    const v28798 = try s.own(try ordinary.create(e, "FromObject", 2, body28753, &.{ graph, frame }));
    try o.assign(&s, frame, "binding28752", v28798);
    const v28799 = try o.lookup(&s, frame, "binding28752");
    try s.put(namespace, "FromObject", v28799);
    const v28800 = try o.lookup(&s, frame, "binding28752");
    try s.put(namespace, "FromObject", v28800);
    try s.put(bindings, "FromObject", try s.text("binding28752"));
}
fn body28776(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v28780 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28778", v28780);
    const v28781 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28779", v28781);
    const v28782 = try s.object();
    const v28783 = try o.lookup(&s, frame, "binding28778");
    try js.spreadInto(e, v28782, v28783);
    const v28784 = try o.lookup(&s, frame, "binding28779");
    const v28785 = try o.propertyKey(&s, v28784);
    const v28786 = try o.importValue(&s, graph, "value/create/from_type.mjs", "FromType");
    const v28787 = try o.lookup(&s, frame, "binding28754");
    const v28788 = try o.lookup(&s, frame, "binding28755");
    const v28789 = try s.text("properties");
    const v28790 = try s.own(try js.getKey(e, v28788, v28789));
    const v28791 = try o.lookup(&s, frame, "binding28779");
    const v28792 = try o.propertyKey(&s, v28791);
    const v28793 = try s.own(try js.getKey(e, v28790, v28792));
    const v28794 = try o.call(&s, @src(), v28786, c.pi_js_undefined(), &.{ v28787, v28793 });
    try o.defineKey(&s, v28782, v28785, v28794);
    return c.JS_DupValue(e.context, v28782);
}
fn body28776C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body28776(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body28753(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v28757 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28754", v28757);
    const v28758 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28755", v28758);
    const v28760 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v28761 = try s.text("IsUndefined");
    const v28762 = try s.own(try js.getKey(e, v28760, v28761));
    const v28763 = try o.lookup(&s, frame, "binding28755");
    const v28764 = try s.text("required");
    const v28765 = try s.own(try js.getKey(e, v28763, v28764));
    const v28766 = try o.call(&s, @src(), v28762, v28760, &.{v28765});
    const v28768 = conditional28767: {
        if (s.truthy(v28766)) {
            const v28769 = try s.array();
            break :conditional28767 v28769;
        } else {
            const v28770 = try o.lookup(&s, frame, "binding28755");
            const v28771 = try s.text("required");
            const v28772 = try s.own(try js.getKey(e, v28770, v28771));
            break :conditional28767 v28772;
        }
    };
    try o.assign(&s, frame, "binding28759", v28768);
    const v28773 = try o.lookup(&s, frame, "binding28759");
    const v28774 = try s.text("reduce");
    const v28775 = try s.own(try js.getKey(e, v28773, v28774));
    const v28795 = try o.arrow(&s, "", 2, body28776C, &.{ graph, frame });
    const v28796 = try s.object();
    const v28797 = try o.call(&s, @src(), v28775, v28773, &.{ v28795, v28796 });
    return c.JS_DupValue(e.context, v28797);
}
