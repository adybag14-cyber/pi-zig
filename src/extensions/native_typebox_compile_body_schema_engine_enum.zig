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
    const namespace = try s.get(modules, "schema/engine/enum.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/engine/enum.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/engine/enum.mjs", bindings);
    const v8884 = try s.own(try ordinary.create(e, "BuildEnum", 4, body8832, &.{ graph, frame }));
    try o.assign(&s, frame, "binding8829", v8884);
    const v8925 = try s.own(try ordinary.create(e, "CheckEnum", 4, body8885, &.{ graph, frame }));
    try o.assign(&s, frame, "binding8830", v8925);
    const v8964 = try s.own(try ordinary.create(e, "ErrorEnum", 6, body8926, &.{ graph, frame }));
    try o.assign(&s, frame, "binding8831", v8964);
    const v8965 = try o.lookup(&s, frame, "binding8829");
    try s.put(namespace, "BuildEnum", v8965);
    const v8966 = try o.lookup(&s, frame, "binding8830");
    try s.put(namespace, "CheckEnum", v8966);
    const v8967 = try o.lookup(&s, frame, "binding8831");
    try s.put(namespace, "ErrorEnum", v8967);
    const v8968 = try o.lookup(&s, frame, "binding8829");
    try s.put(namespace, "BuildEnum", v8968);
    const v8969 = try o.lookup(&s, frame, "binding8830");
    try s.put(namespace, "CheckEnum", v8969);
    const v8970 = try o.lookup(&s, frame, "binding8831");
    try s.put(namespace, "ErrorEnum", v8970);
    try s.put(bindings, "BuildEnum", try s.text("binding8829"));
    try s.put(bindings, "CheckEnum", try s.text("binding8830"));
    try s.put(bindings, "ErrorEnum", try s.text("binding8831"));
}
fn body8849(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v8853 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding8851", v8853);
    const v8855 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v8856 = try s.text("IsValueLike");
    const v8857 = try s.own(try js.getKey(e, v8855, v8856));
    const v8858 = try o.lookup(&s, frame, "binding8851");
    const v8859 = try s.call(v8857, v8855, &.{v8858});
    if (s.truthy(v8859)) {
        const v8860 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
        const v8861 = try s.text("IsEqual");
        const v8862 = try s.own(try js.getKey(e, v8860, v8861));
        const v8863 = try o.lookup(&s, frame, "binding8836");
        const v8864 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
        const v8865 = try s.text("Constant");
        const v8866 = try s.own(try js.getKey(e, v8864, v8865));
        const v8867 = try o.lookup(&s, frame, "binding8851");
        const v8868 = try s.call(v8866, v8864, &.{v8867});
        const v8869 = try s.call(v8862, v8860, &.{ v8863, v8868 });
        return c.JS_DupValue(e.context, v8869);
    }
    const v8870 = try o.importValue(&s, graph, "schema/engine/_externals.mjs", "*");
    const v8871 = try s.text("CreateVariable");
    const v8872 = try s.own(try js.getKey(e, v8870, v8871));
    const v8873 = try o.lookup(&s, frame, "binding8851");
    const v8874 = try s.call(v8872, v8870, &.{v8873});
    try o.assign(&s, frame, "binding8854", v8874);
    const v8875 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v8876 = try s.text("IsDeepEqual");
    const v8877 = try s.own(try js.getKey(e, v8875, v8876));
    const v8878 = try o.lookup(&s, frame, "binding8836");
    const v8879 = try o.lookup(&s, frame, "binding8854");
    const v8880 = try s.call(v8877, v8875, &.{ v8878, v8879 });
    return c.JS_DupValue(e.context, v8880);
}
fn body8849C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body8849(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body8832(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v8837 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding8833", v8837);
    const v8838 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding8834", v8838);
    const v8839 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding8835", v8839);
    const v8840 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding8836", v8840);
    const v8841 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v8842 = try s.text("ReduceOr");
    const v8843 = try s.own(try js.getKey(e, v8841, v8842));
    const v8844 = try o.lookup(&s, frame, "binding8835");
    const v8845 = try s.text("enum");
    const v8846 = try s.own(try js.getKey(e, v8844, v8845));
    const v8847 = try s.text("map");
    const v8848 = try s.own(try js.getKey(e, v8846, v8847));
    const v8881 = try o.arrow(&s, "", 1, body8849C, &.{ graph, frame });
    const v8882 = try s.call(v8848, v8846, &.{v8881});
    const v8883 = try s.call(v8843, v8841, &.{v8882});
    return c.JS_DupValue(e.context, v8883);
}
fn body8900(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v8903 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding8902", v8903);
    const v8904 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v8905 = try s.text("IsValueLike");
    const v8906 = try s.own(try js.getKey(e, v8904, v8905));
    const v8907 = try o.lookup(&s, frame, "binding8902");
    const v8908 = try s.call(v8906, v8904, &.{v8907});
    const v8910 = conditional8909: {
        if (s.truthy(v8908)) {
            const v8911 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
            const v8912 = try s.text("IsEqual");
            const v8913 = try s.own(try js.getKey(e, v8911, v8912));
            const v8914 = try o.lookup(&s, frame, "binding8889");
            const v8915 = try o.lookup(&s, frame, "binding8902");
            const v8916 = try s.call(v8913, v8911, &.{ v8914, v8915 });
            break :conditional8909 v8916;
        } else {
            const v8917 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
            const v8918 = try s.text("IsDeepEqual");
            const v8919 = try s.own(try js.getKey(e, v8917, v8918));
            const v8920 = try o.lookup(&s, frame, "binding8889");
            const v8921 = try o.lookup(&s, frame, "binding8902");
            const v8922 = try s.call(v8919, v8917, &.{ v8920, v8921 });
            break :conditional8909 v8922;
        }
    };
    return c.JS_DupValue(e.context, v8910);
}
fn body8900C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body8900(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body8885(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v8890 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding8886", v8890);
    const v8891 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding8887", v8891);
    const v8892 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding8888", v8892);
    const v8893 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding8889", v8893);
    const v8894 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v8895 = try s.text("Some");
    const v8896 = try s.own(try js.getKey(e, v8894, v8895));
    const v8897 = try o.lookup(&s, frame, "binding8888");
    const v8898 = try s.text("enum");
    const v8899 = try s.own(try js.getKey(e, v8897, v8898));
    const v8923 = try o.arrow(&s, "", 1, body8900C, &.{ graph, frame });
    const v8924 = try s.call(v8896, v8894, &.{ v8899, v8923 });
    return c.JS_DupValue(e.context, v8924);
}
fn body8926(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v8933 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding8927", v8933);
    const v8934 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding8928", v8934);
    const v8935 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding8929", v8935);
    const v8936 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding8930", v8936);
    const v8937 = if (args.len > 4) args[4] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding8931", v8937);
    const v8938 = if (args.len > 5) args[5] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding8932", v8938);
    const v8939 = try o.lookup(&s, frame, "binding8830");
    const v8940 = try o.lookup(&s, frame, "binding8927");
    const v8941 = try o.lookup(&s, frame, "binding8928");
    const v8942 = try o.lookup(&s, frame, "binding8931");
    const v8943 = try o.lookup(&s, frame, "binding8932");
    const v8944 = try s.call(v8939, c.pi_js_undefined(), &.{ v8940, v8941, v8942, v8943 });
    const v8946 = logical8945: {
        if (s.truthy(v8944)) break :logical8945 v8944;
        const v8947 = try o.lookup(&s, frame, "binding8928");
        const v8948 = try s.text("AddError");
        const v8949 = try s.own(try js.getKey(e, v8947, v8948));
        const v8950 = try s.object();
        const v8951 = try s.text("keyword");
        const v8952 = try s.text("enum");
        try o.defineKey(&s, v8950, v8951, v8952);
        const v8953 = try s.text("schemaPath");
        const v8954 = try o.lookup(&s, frame, "binding8929");
        try o.defineKey(&s, v8950, v8953, v8954);
        const v8955 = try s.text("instancePath");
        const v8956 = try o.lookup(&s, frame, "binding8930");
        try o.defineKey(&s, v8950, v8955, v8956);
        const v8957 = try s.text("params");
        const v8958 = try s.object();
        const v8959 = try s.text("allowedValues");
        const v8960 = try o.lookup(&s, frame, "binding8931");
        const v8961 = try s.text("enum");
        const v8962 = try s.own(try js.getKey(e, v8960, v8961));
        try o.defineKey(&s, v8958, v8959, v8962);
        try o.defineKey(&s, v8950, v8957, v8958);
        const v8963 = try s.call(v8949, v8947, &.{v8950});
        break :logical8945 v8963;
    };
    return c.JS_DupValue(e.context, v8946);
}
