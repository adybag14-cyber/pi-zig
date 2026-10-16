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
    const namespace = try s.get(modules, "schema/engine/allOf.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/engine/allOf.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/engine/allOf.mjs", bindings);
    const v6814 = try s.own(try ordinary.create(e, "BuildAllOfStandard", 4, body6778, &.{ graph, frame }));
    try o.assign(&s, frame, "binding6773", v6814);
    const v6845 = try s.own(try ordinary.create(e, "BuildAllOfFast", 4, body6815, &.{ graph, frame }));
    try o.assign(&s, frame, "binding6774", v6845);
    const v6873 = try s.own(try ordinary.create(e, "BuildAllOf", 4, body6846, &.{ graph, frame }));
    try o.assign(&s, frame, "binding6775", v6873);
    const v6934 = try s.own(try ordinary.create(e, "CheckAllOf", 4, body6874, &.{ graph, frame }));
    try o.assign(&s, frame, "binding6776", v6934);
    const v7058 = try s.own(try ordinary.create(e, "ErrorAllOf", 6, body6935, &.{ graph, frame }));
    try o.assign(&s, frame, "binding6777", v7058);
    const v7059 = try o.lookup(&s, frame, "binding6775");
    try s.put(namespace, "BuildAllOf", v7059);
    const v7060 = try o.lookup(&s, frame, "binding6776");
    try s.put(namespace, "CheckAllOf", v7060);
    const v7061 = try o.lookup(&s, frame, "binding6777");
    try s.put(namespace, "ErrorAllOf", v7061);
    const v7062 = try o.lookup(&s, frame, "binding6775");
    try s.put(namespace, "BuildAllOf", v7062);
    const v7063 = try o.lookup(&s, frame, "binding6776");
    try s.put(namespace, "CheckAllOf", v7063);
    const v7064 = try o.lookup(&s, frame, "binding6777");
    try s.put(namespace, "ErrorAllOf", v7064);
    try s.put(bindings, "BuildAllOf", try s.text("binding6775"));
    try s.put(bindings, "CheckAllOf", try s.text("binding6776"));
    try s.put(bindings, "ErrorAllOf", try s.text("binding6777"));
}
fn body6778(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v6783 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding6779", v6783);
    const v6784 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding6780", v6784);
    const v6785 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding6781", v6785);
    const v6786 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding6782", v6786);
    const v6787 = try o.importValue(&s, graph, "schema/engine/_reducer.mjs", "Reducer");
    const v6788 = try o.lookup(&s, frame, "binding6779");
    const v6789 = try o.lookup(&s, frame, "binding6780");
    const v6790 = try o.lookup(&s, frame, "binding6781");
    const v6791 = try s.text("allOf");
    const v6792 = try s.own(try js.getKey(e, v6790, v6791));
    const v6793 = try o.lookup(&s, frame, "binding6782");
    const v6794 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v6795 = try s.text("IsEqual");
    const v6796 = try s.own(try js.getKey(e, v6794, v6795));
    const v6797 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v6798 = try s.text("Member");
    const v6799 = try s.own(try js.getKey(e, v6797, v6798));
    const v6800 = try s.text("results");
    const v6801 = try s.text("length");
    const v6802 = try s.call(v6799, v6797, &.{ v6800, v6801 });
    const v6803 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v6804 = try s.text("Constant");
    const v6805 = try s.own(try js.getKey(e, v6803, v6804));
    const v6806 = try o.lookup(&s, frame, "binding6781");
    const v6807 = try s.text("allOf");
    const v6808 = try s.own(try js.getKey(e, v6806, v6807));
    const v6809 = try s.text("length");
    const v6810 = try s.own(try js.getKey(e, v6808, v6809));
    const v6811 = try s.call(v6805, v6803, &.{v6810});
    const v6812 = try s.call(v6796, v6794, &.{ v6802, v6811 });
    const v6813 = try s.call(v6787, c.pi_js_undefined(), &.{ v6788, v6789, v6792, v6793, v6812 });
    return c.JS_DupValue(e.context, v6813);
}
fn body6832(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v6835 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding6834", v6835);
    const v6836 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "BuildSchema");
    const v6837 = try o.lookup(&s, frame, "binding6816");
    const v6838 = try o.lookup(&s, frame, "binding6817");
    const v6839 = try o.lookup(&s, frame, "binding6834");
    const v6840 = try o.lookup(&s, frame, "binding6819");
    const v6841 = try s.call(v6836, c.pi_js_undefined(), &.{ v6837, v6838, v6839, v6840 });
    return c.JS_DupValue(e.context, v6841);
}
fn body6832C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body6832(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body6815(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v6820 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding6816", v6820);
    const v6821 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding6817", v6821);
    const v6822 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding6818", v6822);
    const v6823 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding6819", v6823);
    const v6824 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v6825 = try s.text("ReduceAnd");
    const v6826 = try s.own(try js.getKey(e, v6824, v6825));
    const v6827 = try o.lookup(&s, frame, "binding6818");
    const v6828 = try s.text("allOf");
    const v6829 = try s.own(try js.getKey(e, v6827, v6828));
    const v6830 = try s.text("map");
    const v6831 = try s.own(try js.getKey(e, v6829, v6830));
    const v6842 = try o.arrow(&s, "", 1, body6832C, &.{ graph, frame });
    const v6843 = try s.call(v6831, v6829, &.{v6842});
    const v6844 = try s.call(v6826, v6824, &.{v6843});
    return c.JS_DupValue(e.context, v6844);
}
fn body6846(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v6851 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding6847", v6851);
    const v6852 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding6848", v6852);
    const v6853 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding6849", v6853);
    const v6854 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding6850", v6854);
    const v6855 = try o.lookup(&s, frame, "binding6848");
    const v6856 = try s.text("UseUnevaluated");
    const v6857 = try s.own(try js.getKey(e, v6855, v6856));
    const v6858 = try s.call(v6857, v6855, &.{});
    const v6860 = conditional6859: {
        if (s.truthy(v6858)) {
            const v6861 = try o.lookup(&s, frame, "binding6773");
            const v6862 = try o.lookup(&s, frame, "binding6847");
            const v6863 = try o.lookup(&s, frame, "binding6848");
            const v6864 = try o.lookup(&s, frame, "binding6849");
            const v6865 = try o.lookup(&s, frame, "binding6850");
            const v6866 = try s.call(v6861, c.pi_js_undefined(), &.{ v6862, v6863, v6864, v6865 });
            break :conditional6859 v6866;
        } else {
            const v6867 = try o.lookup(&s, frame, "binding6774");
            const v6868 = try o.lookup(&s, frame, "binding6847");
            const v6869 = try o.lookup(&s, frame, "binding6848");
            const v6870 = try o.lookup(&s, frame, "binding6849");
            const v6871 = try o.lookup(&s, frame, "binding6850");
            const v6872 = try s.call(v6867, c.pi_js_undefined(), &.{ v6868, v6869, v6870, v6871 });
            break :conditional6859 v6872;
        }
    };
    return c.JS_DupValue(e.context, v6860);
}
fn body6890(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v6895 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding6892", v6895);
    const v6896 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding6893", v6896);
    const v6898 = try o.importValue(&s, graph, "schema/engine/_context.mjs", "CheckContext");
    const v6899 = try o.construct(&s, v6898, &.{});
    try o.assign(&s, frame, "binding6897", v6899);
    const v6900 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "CheckSchema");
    const v6901 = try o.lookup(&s, frame, "binding6875");
    const v6902 = try o.lookup(&s, frame, "binding6897");
    const v6903 = try o.lookup(&s, frame, "binding6893");
    const v6904 = try o.lookup(&s, frame, "binding6878");
    const v6905 = try s.call(v6900, c.pi_js_undefined(), &.{ v6901, v6902, v6903, v6904 });
    const v6907 = conditional6906: {
        if (s.truthy(v6905)) {
            const v6908 = try s.array();
            const v6909 = try o.lookup(&s, frame, "binding6892");
            try o.spreadArray(&s, v6908, v6909);
            const v6910 = try o.lookup(&s, frame, "binding6897");
            try o.append(&s, v6908, v6910);
            break :conditional6906 v6908;
        } else {
            const v6911 = try o.lookup(&s, frame, "binding6892");
            break :conditional6906 v6911;
        }
    };
    return c.JS_DupValue(e.context, v6907);
}
fn body6890C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body6890(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body6874(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v6880 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding6875", v6880);
    const v6881 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding6876", v6881);
    const v6882 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding6877", v6882);
    const v6883 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding6878", v6883);
    const v6885 = try o.lookup(&s, frame, "binding6877");
    const v6886 = try s.text("allOf");
    const v6887 = try s.own(try js.getKey(e, v6885, v6886));
    const v6888 = try s.text("reduce");
    const v6889 = try s.own(try js.getKey(e, v6887, v6888));
    const v6912 = try o.arrow(&s, "", 2, body6890C, &.{ graph, frame });
    const v6913 = try s.array();
    const v6914 = try s.call(v6889, v6887, &.{ v6912, v6913 });
    try o.assign(&s, frame, "binding6884", v6914);
    const v6915 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v6916 = try s.text("IsEqual");
    const v6917 = try s.own(try js.getKey(e, v6915, v6916));
    const v6918 = try o.lookup(&s, frame, "binding6884");
    const v6919 = try s.text("length");
    const v6920 = try s.own(try js.getKey(e, v6918, v6919));
    const v6921 = try o.lookup(&s, frame, "binding6877");
    const v6922 = try s.text("allOf");
    const v6923 = try s.own(try js.getKey(e, v6921, v6922));
    const v6924 = try s.text("length");
    const v6925 = try s.own(try js.getKey(e, v6923, v6924));
    const v6926 = try s.call(v6917, v6915, &.{ v6920, v6925 });
    const v6928 = logical6927: {
        if (!s.truthy(v6926)) break :logical6927 v6926;
        const v6929 = try o.lookup(&s, frame, "binding6876");
        const v6930 = try s.text("Merge");
        const v6931 = try s.own(try js.getKey(e, v6929, v6930));
        const v6932 = try o.lookup(&s, frame, "binding6884");
        const v6933 = try s.call(v6931, v6929, &.{v6932});
        break :logical6927 v6933;
    };
    return c.JS_DupValue(e.context, v6928);
}
fn body6960(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v6968 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding6962", v6968);
    const v6969 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding6963", v6969);
    const v6970 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding6964", v6970);
    const v6974 = try s.text("");
    const v6975 = try o.lookup(&s, frame, "binding6938");
    const v6976 = try s.stringify(v6975);
    const v6977 = try s.concat(v6974, v6976);
    const v6978 = try s.text("/allOf/");
    const v6979 = try s.concat(v6977, v6978);
    const v6980 = try o.lookup(&s, frame, "binding6964");
    const v6981 = try s.stringify(v6980);
    const v6982 = try s.concat(v6979, v6981);
    const v6983 = try s.text("");
    const v6984 = try s.concat(v6982, v6983);
    try o.assign(&s, frame, "binding6971", v6984);
    const v6985 = try o.importValue(&s, graph, "schema/engine/_context.mjs", "ErrorContext");
    const v6986 = try o.construct(&s, v6985, &.{});
    try o.assign(&s, frame, "binding6972", v6986);
    const v6987 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "ErrorSchema");
    const v6988 = try o.lookup(&s, frame, "binding6936");
    const v6989 = try o.lookup(&s, frame, "binding6972");
    const v6990 = try o.lookup(&s, frame, "binding6971");
    const v6991 = try o.lookup(&s, frame, "binding6939");
    const v6992 = try o.lookup(&s, frame, "binding6963");
    const v6993 = try o.lookup(&s, frame, "binding6941");
    const v6994 = try s.call(v6987, c.pi_js_undefined(), &.{ v6988, v6989, v6990, v6991, v6992, v6993 });
    try o.assign(&s, frame, "binding6973", v6994);
    const v6995 = try o.lookup(&s, frame, "binding6973");
    if (s.truthy(o.boolean(&s, !s.truthy(v6995)))) {
        const v6996 = try o.lookup(&s, frame, "binding6951");
        const v6997 = try s.text("push");
        const v6998 = try s.own(try js.getKey(e, v6996, v6997));
        const v6999 = try o.lookup(&s, frame, "binding6972");
        const v7000 = try s.call(v6998, v6996, &.{v6999});
        _ = v7000;
    }
    const v7001 = try o.lookup(&s, frame, "binding6973");
    const v7003 = conditional7002: {
        if (s.truthy(v7001)) {
            const v7004 = try s.array();
            const v7005 = try o.lookup(&s, frame, "binding6962");
            try o.spreadArray(&s, v7004, v7005);
            const v7006 = try o.lookup(&s, frame, "binding6972");
            try o.append(&s, v7004, v7006);
            break :conditional7002 v7004;
        } else {
            const v7007 = try o.lookup(&s, frame, "binding6962");
            break :conditional7002 v7007;
        }
    };
    return c.JS_DupValue(e.context, v7003);
}
fn body6960C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body6960(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body7044(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v7047 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7046", v7047);
    const v7048 = try o.lookup(&s, frame, "binding6937");
    const v7049 = try s.text("AddError");
    const v7050 = try s.own(try js.getKey(e, v7048, v7049));
    const v7051 = try o.lookup(&s, frame, "binding7046");
    const v7052 = try s.call(v7050, v7048, &.{v7051});
    return c.JS_DupValue(e.context, v7052);
}
fn body7044C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body7044(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body7034(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v7037 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7036", v7037);
    const v7038 = try o.lookup(&s, frame, "binding7036");
    const v7039 = try s.text("GetErrors");
    const v7040 = try s.own(try js.getKey(e, v7038, v7039));
    const v7041 = try s.call(v7040, v7038, &.{});
    const v7042 = try s.text("forEach");
    const v7043 = try s.own(try js.getKey(e, v7041, v7042));
    const v7053 = try o.arrow(&s, "", 1, body7044C, &.{ graph, frame });
    const v7054 = try s.call(v7043, v7041, &.{v7053});
    return c.JS_DupValue(e.context, v7054);
}
fn body7034C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body7034(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body6935(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v6945 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding6936", v6945);
    const v6946 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding6937", v6946);
    const v6947 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding6938", v6947);
    const v6948 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding6939", v6948);
    const v6949 = if (args.len > 4) args[4] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding6940", v6949);
    const v6950 = if (args.len > 5) args[5] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding6941", v6950);
    const v6954 = try s.array();
    try o.assign(&s, frame, "binding6951", v6954);
    const v6955 = try o.lookup(&s, frame, "binding6940");
    const v6956 = try s.text("allOf");
    const v6957 = try s.own(try js.getKey(e, v6955, v6956));
    const v6958 = try s.text("reduce");
    const v6959 = try s.own(try js.getKey(e, v6957, v6958));
    const v7008 = try o.arrow(&s, "", 3, body6960C, &.{ graph, frame });
    const v7009 = try s.array();
    const v7010 = try s.call(v6959, v6957, &.{ v7008, v7009 });
    try o.assign(&s, frame, "binding6952", v7010);
    const v7011 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v7012 = try s.text("IsEqual");
    const v7013 = try s.own(try js.getKey(e, v7011, v7012));
    const v7014 = try o.lookup(&s, frame, "binding6952");
    const v7015 = try s.text("length");
    const v7016 = try s.own(try js.getKey(e, v7014, v7015));
    const v7017 = try o.lookup(&s, frame, "binding6940");
    const v7018 = try s.text("allOf");
    const v7019 = try s.own(try js.getKey(e, v7017, v7018));
    const v7020 = try s.text("length");
    const v7021 = try s.own(try js.getKey(e, v7019, v7020));
    const v7022 = try s.call(v7013, v7011, &.{ v7016, v7021 });
    const v7024 = logical7023: {
        if (!s.truthy(v7022)) break :logical7023 v7022;
        const v7025 = try o.lookup(&s, frame, "binding6937");
        const v7026 = try s.text("Merge");
        const v7027 = try s.own(try js.getKey(e, v7025, v7026));
        const v7028 = try o.lookup(&s, frame, "binding6952");
        const v7029 = try s.call(v7027, v7025, &.{v7028});
        break :logical7023 v7029;
    };
    try o.assign(&s, frame, "binding6953", v7024);
    const v7030 = try o.lookup(&s, frame, "binding6953");
    if (s.truthy(o.boolean(&s, !s.truthy(v7030)))) {
        const v7031 = try o.lookup(&s, frame, "binding6951");
        const v7032 = try s.text("forEach");
        const v7033 = try s.own(try js.getKey(e, v7031, v7032));
        const v7055 = try o.arrow(&s, "", 1, body7034C, &.{ graph, frame });
        const v7056 = try s.call(v7033, v7031, &.{v7055});
        _ = v7056;
    }
    const v7057 = try o.lookup(&s, frame, "binding6953");
    return c.JS_DupValue(e.context, v7057);
}
