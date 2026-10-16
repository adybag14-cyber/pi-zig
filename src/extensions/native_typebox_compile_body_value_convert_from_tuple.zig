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
    const namespace = try s.get(modules, "value/convert/from_tuple.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/convert/from_tuple.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/convert/from_tuple.mjs", bindings);
    const v26933 = try s.own(try ordinary.create(e, "FromTuple", 3, body26884, &.{ graph, frame }));
    try o.assign(&s, frame, "binding26883", v26933);
    const v26934 = try o.lookup(&s, frame, "binding26883");
    try s.put(namespace, "FromTuple", v26934);
    const v26935 = try o.lookup(&s, frame, "binding26883");
    try s.put(namespace, "FromTuple", v26935);
    try s.put(bindings, "FromTuple", try s.text("binding26883"));
}
fn body26884(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v26888 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26885", v26888);
    const v26889 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26886", v26889);
    const v26890 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26887", v26890);
    const v26891 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v26892 = try s.text("IsArray");
    const v26893 = try s.own(try js.getKey(e, v26891, v26892));
    const v26894 = try o.lookup(&s, frame, "binding26887");
    const v26895 = try o.call(&s, @src(), v26893, v26891, &.{v26894});
    if (s.truthy(o.boolean(&s, !s.truthy(v26895)))) {
        const v26896 = try o.lookup(&s, frame, "binding26887");
        return c.JS_DupValue(e.context, v26896);
    }
    try o.assign(&s, frame, "binding26897", c.JS_NewFloat64(e.context, 0));
    loop26898: while (true) {
        const v26900 = try o.lookup(&s, frame, "binding26897");
        const v26901 = try s.global("Math");
        const v26902 = try s.text("min");
        const v26903 = try s.own(try js.getKey(e, v26901, v26902));
        const v26904 = try o.lookup(&s, frame, "binding26886");
        const v26905 = try s.text("items");
        const v26906 = try s.own(try js.getKey(e, v26904, v26905));
        const v26907 = try s.text("length");
        const v26908 = try s.own(try js.getKey(e, v26906, v26907));
        const v26909 = try o.lookup(&s, frame, "binding26887");
        const v26910 = try s.text("length");
        const v26911 = try s.own(try js.getKey(e, v26909, v26910));
        const v26912 = try o.call(&s, @src(), v26903, v26901, &.{ v26908, v26911 });
        const v26913 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 4, v26900, v26912)));
        if (!s.truthy(v26913)) break :loop26898;
        {
            const v26914 = try o.lookup(&s, frame, "binding26887");
            const v26915 = try o.lookup(&s, frame, "binding26897");
            const v26916 = try o.propertyKey(&s, v26915);
            const v26917 = try o.importValue(&s, graph, "value/convert/from_type.mjs", "FromType");
            const v26918 = try o.lookup(&s, frame, "binding26885");
            const v26919 = try o.lookup(&s, frame, "binding26886");
            const v26920 = try s.text("items");
            const v26921 = try s.own(try js.getKey(e, v26919, v26920));
            const v26922 = try o.lookup(&s, frame, "binding26897");
            const v26923 = try o.propertyKey(&s, v26922);
            const v26924 = try s.own(try js.getKey(e, v26921, v26923));
            const v26925 = try o.lookup(&s, frame, "binding26887");
            const v26926 = try o.lookup(&s, frame, "binding26897");
            const v26927 = try o.propertyKey(&s, v26926);
            const v26928 = try s.own(try js.getKey(e, v26925, v26927));
            const v26929 = try o.call(&s, @src(), v26917, c.pi_js_undefined(), &.{ v26918, v26924, v26928 });
            try js.setKey(e, v26914, v26916, v26929);
        }
        const v26930 = try o.lookup(&s, frame, "binding26897");
        const v26931 = try s.own(try e.checked(c.JS_PiIncrement(e.context, v26930)));
        try o.assign(&s, frame, "binding26897", v26931);
    }
    const v26932 = try o.lookup(&s, frame, "binding26887");
    return c.JS_DupValue(e.context, v26932);
}
