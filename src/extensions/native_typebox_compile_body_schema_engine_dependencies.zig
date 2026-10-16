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
    const namespace = try s.get(modules, "schema/engine/dependencies.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/engine/dependencies.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/engine/dependencies.mjs", bindings);
    const v7978 = try s.own(try ordinary.create(e, "BuildDependencies", 4, body7848, &.{ graph, frame }));
    try o.assign(&s, frame, "binding7845", v7978);
    const v8063 = try s.own(try ordinary.create(e, "CheckDependencies", 4, body7979, &.{ graph, frame }));
    try o.assign(&s, frame, "binding7846", v8063);
    const v8186 = try s.own(try ordinary.create(e, "ErrorDependencies", 6, body8064, &.{ graph, frame }));
    try o.assign(&s, frame, "binding7847", v8186);
    const v8187 = try o.lookup(&s, frame, "binding7845");
    try s.put(namespace, "BuildDependencies", v8187);
    const v8188 = try o.lookup(&s, frame, "binding7846");
    try s.put(namespace, "CheckDependencies", v8188);
    const v8189 = try o.lookup(&s, frame, "binding7847");
    try s.put(namespace, "ErrorDependencies", v8189);
    const v8190 = try o.lookup(&s, frame, "binding7845");
    try s.put(namespace, "BuildDependencies", v8190);
    const v8191 = try o.lookup(&s, frame, "binding7846");
    try s.put(namespace, "CheckDependencies", v8191);
    const v8192 = try o.lookup(&s, frame, "binding7847");
    try s.put(namespace, "ErrorDependencies", v8192);
    try s.put(bindings, "BuildDependencies", try s.text("binding7845"));
    try s.put(bindings, "CheckDependencies", try s.text("binding7846"));
    try s.put(bindings, "ErrorDependencies", try s.text("binding7847"));
}
fn body7935(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v7938 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7937", v7938);
    const v7939 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v7940 = try s.text("HasPropertyKey");
    const v7941 = try s.own(try js.getKey(e, v7939, v7940));
    const v7942 = try o.lookup(&s, frame, "binding7852");
    const v7943 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v7944 = try s.text("Constant");
    const v7945 = try s.own(try js.getKey(e, v7943, v7944));
    const v7946 = try o.lookup(&s, frame, "binding7937");
    const v7947 = try s.call(v7945, v7943, &.{v7946});
    const v7948 = try s.call(v7941, v7939, &.{ v7942, v7947 });
    return c.JS_DupValue(e.context, v7948);
}
fn body7935C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body7935(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body7925(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v7928 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7927", v7928);
    const v7929 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v7930 = try s.text("ReduceAnd");
    const v7931 = try s.own(try js.getKey(e, v7929, v7930));
    const v7932 = try o.lookup(&s, frame, "binding7927");
    const v7933 = try s.text("map");
    const v7934 = try s.own(try js.getKey(e, v7932, v7933));
    const v7949 = try o.arrow(&s, "", 1, body7935C, &.{ graph, frame });
    const v7950 = try s.call(v7934, v7932, &.{v7949});
    const v7951 = try s.call(v7931, v7929, &.{v7950});
    return c.JS_DupValue(e.context, v7951);
}
fn body7925C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body7925(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body7891(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v7898 = if (args.len > 0) args[0] else c.pi_js_undefined();
    var destructure7899 = try o.iterator(e, v7898);
    defer destructure7899.deinit();
    errdefer destructure7899.closePreserving();
    const v7900 = try s.own(if (destructure7899.closed) c.pi_js_undefined() else (try destructure7899.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding7893", v7900);
    const v7901 = try s.own(if (destructure7899.closed) c.pi_js_undefined() else (try destructure7899.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding7894", v7901);
    try destructure7899.close();
    const v7905 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v7906 = try s.text("Not");
    const v7907 = try s.own(try js.getKey(e, v7905, v7906));
    const v7908 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v7909 = try s.text("HasPropertyKey");
    const v7910 = try s.own(try js.getKey(e, v7908, v7909));
    const v7911 = try o.lookup(&s, frame, "binding7852");
    const v7912 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v7913 = try s.text("Constant");
    const v7914 = try s.own(try js.getKey(e, v7912, v7913));
    const v7915 = try o.lookup(&s, frame, "binding7893");
    const v7916 = try s.call(v7914, v7912, &.{v7915});
    const v7917 = try s.call(v7910, v7908, &.{ v7911, v7916 });
    const v7918 = try s.call(v7907, v7905, &.{v7917});
    try o.assign(&s, frame, "binding7902", v7918);
    const v7919 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "BuildSchema");
    const v7920 = try o.lookup(&s, frame, "binding7849");
    const v7921 = try o.lookup(&s, frame, "binding7850");
    const v7922 = try o.lookup(&s, frame, "binding7894");
    const v7923 = try o.lookup(&s, frame, "binding7852");
    const v7924 = try s.call(v7919, c.pi_js_undefined(), &.{ v7920, v7921, v7922, v7923 });
    try o.assign(&s, frame, "binding7903", v7924);
    const v7952 = try o.arrow(&s, "isEveryKey", 1, body7925C, &.{ graph, frame });
    try o.assign(&s, frame, "binding7904", v7952);
    const v7953 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v7954 = try s.text("Or");
    const v7955 = try s.own(try js.getKey(e, v7953, v7954));
    const v7956 = try o.lookup(&s, frame, "binding7902");
    const v7957 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v7958 = try s.text("IsArray");
    const v7959 = try s.own(try js.getKey(e, v7957, v7958));
    const v7960 = try o.lookup(&s, frame, "binding7894");
    const v7961 = try s.call(v7959, v7957, &.{v7960});
    const v7963 = conditional7962: {
        if (s.truthy(v7961)) {
            const v7964 = try o.lookup(&s, frame, "binding7904");
            const v7965 = try o.lookup(&s, frame, "binding7894");
            const v7966 = try s.call(v7964, c.pi_js_undefined(), &.{v7965});
            break :conditional7962 v7966;
        } else {
            const v7967 = try o.lookup(&s, frame, "binding7903");
            break :conditional7962 v7967;
        }
    };
    const v7968 = try s.call(v7955, v7953, &.{ v7956, v7963 });
    return c.JS_DupValue(e.context, v7968);
}
fn body7891C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body7891(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body7848(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v7855 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7849", v7855);
    const v7856 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7850", v7856);
    const v7857 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7851", v7857);
    const v7858 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7852", v7858);
    const v7861 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v7862 = try s.text("IsEqual");
    const v7863 = try s.own(try js.getKey(e, v7861, v7862));
    const v7864 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v7865 = try s.text("Member");
    const v7866 = try s.own(try js.getKey(e, v7864, v7865));
    const v7867 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v7868 = try s.text("Keys");
    const v7869 = try s.own(try js.getKey(e, v7867, v7868));
    const v7870 = try o.lookup(&s, frame, "binding7852");
    const v7871 = try s.call(v7869, v7867, &.{v7870});
    const v7872 = try s.text("length");
    const v7873 = try s.call(v7866, v7864, &.{ v7871, v7872 });
    const v7874 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v7875 = try s.text("Constant");
    const v7876 = try s.own(try js.getKey(e, v7874, v7875));
    const v7877 = try s.call(v7876, v7874, &.{c.JS_NewFloat64(e.context, 0)});
    const v7878 = try s.call(v7863, v7861, &.{ v7873, v7877 });
    try o.assign(&s, frame, "binding7859", v7878);
    const v7879 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v7880 = try s.text("ReduceAnd");
    const v7881 = try s.own(try js.getKey(e, v7879, v7880));
    const v7882 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v7883 = try s.text("Entries");
    const v7884 = try s.own(try js.getKey(e, v7882, v7883));
    const v7885 = try o.lookup(&s, frame, "binding7851");
    const v7886 = try s.text("dependencies");
    const v7887 = try s.own(try js.getKey(e, v7885, v7886));
    const v7888 = try s.call(v7884, v7882, &.{v7887});
    const v7889 = try s.text("map");
    const v7890 = try s.own(try js.getKey(e, v7888, v7889));
    const v7969 = try o.arrow(&s, "", 1, body7891C, &.{ graph, frame });
    const v7970 = try s.call(v7890, v7888, &.{v7969});
    const v7971 = try s.call(v7881, v7879, &.{v7970});
    try o.assign(&s, frame, "binding7860", v7971);
    const v7972 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v7973 = try s.text("Or");
    const v7974 = try s.own(try js.getKey(e, v7972, v7973));
    const v7975 = try o.lookup(&s, frame, "binding7859");
    const v7976 = try o.lookup(&s, frame, "binding7860");
    const v7977 = try s.call(v7974, v7972, &.{ v7975, v7976 });
    return c.JS_DupValue(e.context, v7977);
}
fn body8039(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v8042 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding8041", v8042);
    const v8043 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v8044 = try s.text("HasPropertyKey");
    const v8045 = try s.own(try js.getKey(e, v8043, v8044));
    const v8046 = try o.lookup(&s, frame, "binding7983");
    const v8047 = try o.lookup(&s, frame, "binding8041");
    const v8048 = try s.call(v8045, v8043, &.{ v8046, v8047 });
    return c.JS_DupValue(e.context, v8048);
}
fn body8039C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body8039(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body8013(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v8017 = if (args.len > 0) args[0] else c.pi_js_undefined();
    var destructure8018 = try o.iterator(e, v8017);
    defer destructure8018.deinit();
    errdefer destructure8018.closePreserving();
    const v8019 = try s.own(if (destructure8018.closed) c.pi_js_undefined() else (try destructure8018.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding8015", v8019);
    const v8020 = try s.own(if (destructure8018.closed) c.pi_js_undefined() else (try destructure8018.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding8016", v8020);
    try destructure8018.close();
    const v8021 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v8022 = try s.text("HasPropertyKey");
    const v8023 = try s.own(try js.getKey(e, v8021, v8022));
    const v8024 = try o.lookup(&s, frame, "binding7983");
    const v8025 = try o.lookup(&s, frame, "binding8015");
    const v8026 = try s.call(v8023, v8021, &.{ v8024, v8025 });
    const v8028 = logical8027: {
        if (s.truthy(o.boolean(&s, !s.truthy(v8026)))) break :logical8027 o.boolean(&s, !s.truthy(v8026));
        const v8029 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v8030 = try s.text("IsArray");
        const v8031 = try s.own(try js.getKey(e, v8029, v8030));
        const v8032 = try o.lookup(&s, frame, "binding8016");
        const v8033 = try s.call(v8031, v8029, &.{v8032});
        const v8035 = conditional8034: {
            if (s.truthy(v8033)) {
                const v8036 = try o.lookup(&s, frame, "binding8016");
                const v8037 = try s.text("every");
                const v8038 = try s.own(try js.getKey(e, v8036, v8037));
                const v8049 = try o.arrow(&s, "", 1, body8039C, &.{ graph, frame });
                const v8050 = try s.call(v8038, v8036, &.{v8049});
                break :conditional8034 v8050;
            } else {
                const v8051 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "CheckSchema");
                const v8052 = try o.lookup(&s, frame, "binding7980");
                const v8053 = try o.lookup(&s, frame, "binding7981");
                const v8054 = try o.lookup(&s, frame, "binding8016");
                const v8055 = try o.lookup(&s, frame, "binding7983");
                const v8056 = try s.call(v8051, c.pi_js_undefined(), &.{ v8052, v8053, v8054, v8055 });
                break :conditional8034 v8056;
            }
        };
        break :logical8027 v8035;
    };
    return c.JS_DupValue(e.context, v8028);
}
fn body8013C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body8013(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body7979(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v7986 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7980", v7986);
    const v7987 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7981", v7987);
    const v7988 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7982", v7988);
    const v7989 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7983", v7989);
    const v7992 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v7993 = try s.text("IsEqual");
    const v7994 = try s.own(try js.getKey(e, v7992, v7993));
    const v7995 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v7996 = try s.text("Keys");
    const v7997 = try s.own(try js.getKey(e, v7995, v7996));
    const v7998 = try o.lookup(&s, frame, "binding7983");
    const v7999 = try s.call(v7997, v7995, &.{v7998});
    const v8000 = try s.text("length");
    const v8001 = try s.own(try js.getKey(e, v7999, v8000));
    const v8002 = try s.call(v7994, v7992, &.{ v8001, c.JS_NewFloat64(e.context, 0) });
    try o.assign(&s, frame, "binding7990", v8002);
    const v8003 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v8004 = try s.text("Every");
    const v8005 = try s.own(try js.getKey(e, v8003, v8004));
    const v8006 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v8007 = try s.text("Entries");
    const v8008 = try s.own(try js.getKey(e, v8006, v8007));
    const v8009 = try o.lookup(&s, frame, "binding7982");
    const v8010 = try s.text("dependencies");
    const v8011 = try s.own(try js.getKey(e, v8009, v8010));
    const v8012 = try s.call(v8008, v8006, &.{v8011});
    const v8057 = try o.arrow(&s, "", 1, body8013C, &.{ graph, frame });
    const v8058 = try s.call(v8005, v8003, &.{ v8012, c.JS_NewFloat64(e.context, 0), v8057 });
    try o.assign(&s, frame, "binding7991", v8058);
    const v8059 = try o.lookup(&s, frame, "binding7990");
    const v8061 = logical8060: {
        if (s.truthy(v8059)) break :logical8060 v8059;
        const v8062 = try o.lookup(&s, frame, "binding7991");
        break :logical8060 v8062;
    };
    return c.JS_DupValue(e.context, v8061);
}
fn body8141(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v8144 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding8143", v8144);
    const v8145 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v8146 = try s.text("HasPropertyKey");
    const v8147 = try s.own(try js.getKey(e, v8145, v8146));
    const v8148 = try o.lookup(&s, frame, "binding8070");
    const v8149 = try o.lookup(&s, frame, "binding8143");
    const v8150 = try s.call(v8147, v8145, &.{ v8148, v8149 });
    const v8152 = logical8151: {
        if (s.truthy(v8150)) break :logical8151 v8150;
        const v8153 = try o.lookup(&s, frame, "binding8066");
        const v8154 = try s.text("AddError");
        const v8155 = try s.own(try js.getKey(e, v8153, v8154));
        const v8156 = try s.object();
        const v8157 = try s.text("keyword");
        const v8158 = try s.text("dependencies");
        try o.defineKey(&s, v8156, v8157, v8158);
        const v8159 = try s.text("schemaPath");
        const v8160 = try o.lookup(&s, frame, "binding8067");
        try o.defineKey(&s, v8156, v8159, v8160);
        const v8161 = try s.text("instancePath");
        const v8162 = try o.lookup(&s, frame, "binding8068");
        try o.defineKey(&s, v8156, v8161, v8162);
        const v8163 = try s.text("params");
        const v8164 = try s.object();
        const v8165 = try s.text("property");
        const v8166 = try o.lookup(&s, frame, "binding8104");
        try o.defineKey(&s, v8164, v8165, v8166);
        const v8167 = try s.text("dependencies");
        const v8168 = try o.lookup(&s, frame, "binding8105");
        try o.defineKey(&s, v8164, v8167, v8168);
        try o.defineKey(&s, v8156, v8163, v8164);
        const v8169 = try s.call(v8155, v8153, &.{v8156});
        break :logical8151 v8169;
    };
    return c.JS_DupValue(e.context, v8152);
}
fn body8141C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body8141(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body8102(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v8107 = if (args.len > 0) args[0] else c.pi_js_undefined();
    var destructure8108 = try o.iterator(e, v8107);
    defer destructure8108.deinit();
    errdefer destructure8108.closePreserving();
    const v8109 = try s.own(if (destructure8108.closed) c.pi_js_undefined() else (try destructure8108.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding8104", v8109);
    const v8110 = try s.own(if (destructure8108.closed) c.pi_js_undefined() else (try destructure8108.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding8105", v8110);
    try destructure8108.close();
    const v8112 = try s.text("");
    const v8113 = try o.lookup(&s, frame, "binding8067");
    const v8114 = try s.stringify(v8113);
    const v8115 = try s.concat(v8112, v8114);
    const v8116 = try s.text("/dependencies/");
    const v8117 = try s.concat(v8115, v8116);
    const v8118 = try o.lookup(&s, frame, "binding8104");
    const v8119 = try s.stringify(v8118);
    const v8120 = try s.concat(v8117, v8119);
    const v8121 = try s.text("");
    const v8122 = try s.concat(v8120, v8121);
    try o.assign(&s, frame, "binding8111", v8122);
    const v8123 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v8124 = try s.text("HasPropertyKey");
    const v8125 = try s.own(try js.getKey(e, v8123, v8124));
    const v8126 = try o.lookup(&s, frame, "binding8070");
    const v8127 = try o.lookup(&s, frame, "binding8104");
    const v8128 = try s.call(v8125, v8123, &.{ v8126, v8127 });
    const v8130 = logical8129: {
        if (s.truthy(o.boolean(&s, !s.truthy(v8128)))) break :logical8129 o.boolean(&s, !s.truthy(v8128));
        const v8131 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v8132 = try s.text("IsArray");
        const v8133 = try s.own(try js.getKey(e, v8131, v8132));
        const v8134 = try o.lookup(&s, frame, "binding8105");
        const v8135 = try s.call(v8133, v8131, &.{v8134});
        const v8137 = conditional8136: {
            if (s.truthy(v8135)) {
                const v8138 = try o.lookup(&s, frame, "binding8105");
                const v8139 = try s.text("every");
                const v8140 = try s.own(try js.getKey(e, v8138, v8139));
                const v8170 = try o.arrow(&s, "", 1, body8141C, &.{ graph, frame });
                const v8171 = try s.call(v8140, v8138, &.{v8170});
                break :conditional8136 v8171;
            } else {
                const v8172 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "ErrorSchema");
                const v8173 = try o.lookup(&s, frame, "binding8065");
                const v8174 = try o.lookup(&s, frame, "binding8066");
                const v8175 = try o.lookup(&s, frame, "binding8111");
                const v8176 = try o.lookup(&s, frame, "binding8068");
                const v8177 = try o.lookup(&s, frame, "binding8105");
                const v8178 = try o.lookup(&s, frame, "binding8070");
                const v8179 = try s.call(v8172, c.pi_js_undefined(), &.{ v8173, v8174, v8175, v8176, v8177, v8178 });
                break :conditional8136 v8179;
            }
        };
        break :logical8129 v8137;
    };
    return c.JS_DupValue(e.context, v8130);
}
fn body8102C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body8102(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body8064(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v8073 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding8065", v8073);
    const v8074 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding8066", v8074);
    const v8075 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding8067", v8075);
    const v8076 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding8068", v8076);
    const v8077 = if (args.len > 4) args[4] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding8069", v8077);
    const v8078 = if (args.len > 5) args[5] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding8070", v8078);
    const v8081 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v8082 = try s.text("IsEqual");
    const v8083 = try s.own(try js.getKey(e, v8081, v8082));
    const v8084 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v8085 = try s.text("Keys");
    const v8086 = try s.own(try js.getKey(e, v8084, v8085));
    const v8087 = try o.lookup(&s, frame, "binding8070");
    const v8088 = try s.call(v8086, v8084, &.{v8087});
    const v8089 = try s.text("length");
    const v8090 = try s.own(try js.getKey(e, v8088, v8089));
    const v8091 = try s.call(v8083, v8081, &.{ v8090, c.JS_NewFloat64(e.context, 0) });
    try o.assign(&s, frame, "binding8079", v8091);
    const v8092 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v8093 = try s.text("EveryAll");
    const v8094 = try s.own(try js.getKey(e, v8092, v8093));
    const v8095 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v8096 = try s.text("Entries");
    const v8097 = try s.own(try js.getKey(e, v8095, v8096));
    const v8098 = try o.lookup(&s, frame, "binding8069");
    const v8099 = try s.text("dependencies");
    const v8100 = try s.own(try js.getKey(e, v8098, v8099));
    const v8101 = try s.call(v8097, v8095, &.{v8100});
    const v8180 = try o.arrow(&s, "", 1, body8102C, &.{ graph, frame });
    const v8181 = try s.call(v8094, v8092, &.{ v8101, c.JS_NewFloat64(e.context, 0), v8180 });
    try o.assign(&s, frame, "binding8080", v8181);
    const v8182 = try o.lookup(&s, frame, "binding8079");
    const v8184 = logical8183: {
        if (s.truthy(v8182)) break :logical8183 v8182;
        const v8185 = try o.lookup(&s, frame, "binding8080");
        break :logical8183 v8185;
    };
    return c.JS_DupValue(e.context, v8184);
}
