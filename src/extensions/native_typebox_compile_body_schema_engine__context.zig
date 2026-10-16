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
    const namespace = try s.get(modules, "schema/engine/_context.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/engine/_context.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/engine/_context.mjs", bindings);
    const v3761 = try s.own(try ordinary.create(e, "HasUnevaluatedFromObject", 1, body3724, &.{ graph, frame }));
    try o.assign(&s, frame, "binding3717", v3761);
    const v3778 = try s.own(try ordinary.create(e, "HasUnevaluatedFromArray", 1, body3762, &.{ graph, frame }));
    try o.assign(&s, frame, "binding3718", v3778);
    const v3802 = try s.own(try ordinary.create(e, "HasUnevaluatedFromUnknown", 1, body3779, &.{ graph, frame }));
    try o.assign(&s, frame, "binding3719", v3802);
    const v3833 = try s.own(try ordinary.create(e, "HasUnevaluated", 2, body3803, &.{ graph, frame }));
    try o.assign(&s, frame, "binding3720", v3833);
    const v3834 = try o.lookup(&s, frame, "binding3720");
    try s.put(namespace, "HasUnevaluated", v3834);
    const v3835 = try s.object();
    const v3841 = try s.own(try class.constructor(e, "BuildContext", 1, v3835, constructor3836, &.{ graph, frame, c.pi_js_undefined() }));
    const v3845 = try o.arrow(&s, "UseUnevaluated", 0, body3842C, &.{ graph, frame });
    try o.method(&s, v3835, "UseUnevaluated", v3845);
    const v3858 = try o.arrow(&s, "Push", 0, body3846C, &.{ graph, frame });
    try o.method(&s, v3835, "Push", v3858);
    const v3871 = try o.arrow(&s, "Pop", 0, body3859C, &.{ graph, frame });
    try o.method(&s, v3835, "Pop", v3871);
    const v3887 = try o.arrow(&s, "AddIndex", 1, body3872C, &.{ graph, frame });
    try o.method(&s, v3835, "AddIndex", v3887);
    const v3903 = try o.arrow(&s, "AddKey", 1, body3888C, &.{ graph, frame });
    try o.method(&s, v3835, "AddKey", v3903);
    const v3919 = try o.arrow(&s, "Merge", 1, body3904C, &.{ graph, frame });
    try o.method(&s, v3835, "Merge", v3919);
    try o.assign(&s, frame, "binding3721", v3841);
    const v3920 = try s.object();
    const v3937 = try s.own(try class.constructor(e, "CheckContext", 0, v3920, constructor3921, &.{ graph, frame, c.pi_js_undefined() }));
    const v3957 = try o.arrow(&s, "Push", 0, body3938C, &.{ graph, frame });
    try o.method(&s, v3920, "Push", v3957);
    const v3964 = try o.arrow(&s, "Pop", 0, body3958C, &.{ graph, frame });
    try o.method(&s, v3920, "Pop", v3964);
    const v3975 = try o.arrow(&s, "AddIndex", 1, body3965C, &.{ graph, frame });
    try o.method(&s, v3920, "AddIndex", v3975);
    const v3986 = try o.arrow(&s, "AddKey", 1, body3976C, &.{ graph, frame });
    try o.method(&s, v3920, "AddKey", v3986);
    const v4002 = try o.arrow(&s, "GetIndices", 0, body3987C, &.{ graph, frame });
    try o.method(&s, v3920, "GetIndices", v4002);
    const v4018 = try o.arrow(&s, "GetKeys", 0, body4003C, &.{ graph, frame });
    try o.method(&s, v3920, "GetKeys", v4018);
    const v4066 = try o.arrow(&s, "Merge", 1, body4019C, &.{ graph, frame });
    try o.method(&s, v3920, "Merge", v4066);
    try o.assign(&s, frame, "binding3722", v3937);
    const v4067 = try o.lookup(&s, frame, "binding3722");
    const v4068 = try o.derivedPrototype(&s, v4067);
    const v4072 = try s.own(try class.constructor(e, "ErrorContext", 0, v4068, constructor4069, &.{ graph, frame, v4067 }));
    try o.setPrototype(&s, v4072, v4067);
    const v4085 = try o.arrow(&s, "AtCapacity", 0, body4073C, &.{ graph, frame });
    try o.method(&s, v4068, "AtCapacity", v4085);
    const v4098 = try o.arrow(&s, "AddError", 1, body4086C, &.{ graph, frame });
    try o.method(&s, v4068, "AddError", v4098);
    const v4102 = try o.arrow(&s, "GetErrors", 0, body4099C, &.{ graph, frame });
    try o.method(&s, v4068, "GetErrors", v4102);
    try o.assign(&s, frame, "binding3723", v4072);
    const v4103 = try o.lookup(&s, frame, "binding3720");
    try s.put(namespace, "HasUnevaluated", v4103);
    const v4104 = try o.lookup(&s, frame, "binding3721");
    try s.put(namespace, "BuildContext", v4104);
    const v4105 = try o.lookup(&s, frame, "binding3722");
    try s.put(namespace, "CheckContext", v4105);
    const v4106 = try o.lookup(&s, frame, "binding3723");
    try s.put(namespace, "ErrorContext", v4106);
    try s.put(bindings, "HasUnevaluated", try s.text("binding3720"));
    try s.put(bindings, "BuildContext", try s.text("binding3721"));
    try s.put(bindings, "CheckContext", try s.text("binding3722"));
    try s.put(bindings, "ErrorContext", try s.text("binding3723"));
}
fn body3749(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v3752 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3751", v3752);
    const v3753 = try o.lookup(&s, frame, "binding3719");
    const v3754 = try o.lookup(&s, frame, "binding3725");
    const v3755 = try o.lookup(&s, frame, "binding3751");
    const v3756 = try o.propertyKey(&s, v3755);
    const v3757 = try s.own(try js.getKey(e, v3754, v3756));
    const v3758 = try s.call(v3753, c.pi_js_undefined(), &.{v3757});
    return c.JS_DupValue(e.context, v3758);
}
fn body3749C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3749(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body3724(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3726 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3725", v3726);
    const v3727 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v3728 = try s.text("IsUnevaluatedItems");
    const v3729 = try s.own(try js.getKey(e, v3727, v3728));
    const v3730 = try o.lookup(&s, frame, "binding3725");
    const v3731 = try s.call(v3729, v3727, &.{v3730});
    const v3733 = logical3732: {
        if (s.truthy(v3731)) break :logical3732 v3731;
        const v3734 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
        const v3735 = try s.text("IsUnevaluatedProperties");
        const v3736 = try s.own(try js.getKey(e, v3734, v3735));
        const v3737 = try o.lookup(&s, frame, "binding3725");
        const v3738 = try s.call(v3736, v3734, &.{v3737});
        break :logical3732 v3738;
    };
    const v3740 = logical3739: {
        if (s.truthy(v3733)) break :logical3739 v3733;
        const v3741 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v3742 = try s.text("Some");
        const v3743 = try s.own(try js.getKey(e, v3741, v3742));
        const v3744 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v3745 = try s.text("Keys");
        const v3746 = try s.own(try js.getKey(e, v3744, v3745));
        const v3747 = try o.lookup(&s, frame, "binding3725");
        const v3748 = try s.call(v3746, v3744, &.{v3747});
        const v3759 = try o.arrow(&s, "", 1, body3749C, &.{ graph, frame });
        const v3760 = try s.call(v3743, v3741, &.{ v3748, v3759 });
        break :logical3739 v3760;
    };
    return c.JS_DupValue(e.context, v3740);
}
fn body3769(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v3772 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3771", v3772);
    const v3773 = try o.lookup(&s, frame, "binding3719");
    const v3774 = try o.lookup(&s, frame, "binding3771");
    const v3775 = try s.call(v3773, c.pi_js_undefined(), &.{v3774});
    return c.JS_DupValue(e.context, v3775);
}
fn body3769C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3769(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body3762(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3764 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3763", v3764);
    const v3765 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v3766 = try s.text("Some");
    const v3767 = try s.own(try js.getKey(e, v3765, v3766));
    const v3768 = try o.lookup(&s, frame, "binding3763");
    const v3776 = try o.arrow(&s, "", 1, body3769C, &.{ graph, frame });
    const v3777 = try s.call(v3767, v3765, &.{ v3768, v3776 });
    return c.JS_DupValue(e.context, v3777);
}
fn body3779(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3781 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3780", v3781);
    const v3782 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v3783 = try s.text("IsArray");
    const v3784 = try s.own(try js.getKey(e, v3782, v3783));
    const v3785 = try o.lookup(&s, frame, "binding3780");
    const v3786 = try s.call(v3784, v3782, &.{v3785});
    const v3788 = conditional3787: {
        if (s.truthy(v3786)) {
            const v3789 = try o.lookup(&s, frame, "binding3718");
            const v3790 = try o.lookup(&s, frame, "binding3780");
            const v3791 = try s.call(v3789, c.pi_js_undefined(), &.{v3790});
            break :conditional3787 v3791;
        } else {
            const v3792 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
            const v3793 = try s.text("IsObject");
            const v3794 = try s.own(try js.getKey(e, v3792, v3793));
            const v3795 = try o.lookup(&s, frame, "binding3780");
            const v3796 = try s.call(v3794, v3792, &.{v3795});
            const v3798 = conditional3797: {
                if (s.truthy(v3796)) {
                    const v3799 = try o.lookup(&s, frame, "binding3717");
                    const v3800 = try o.lookup(&s, frame, "binding3780");
                    const v3801 = try s.call(v3799, c.pi_js_undefined(), &.{v3800});
                    break :conditional3797 v3801;
                } else {
                    break :conditional3797 o.boolean(&s, false);
                }
            };
            break :conditional3787 v3798;
        }
    };
    return c.JS_DupValue(e.context, v3788);
}
fn body3821(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v3824 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3823", v3824);
    const v3825 = try o.lookup(&s, frame, "binding3719");
    const v3826 = try o.lookup(&s, frame, "binding3804");
    const v3827 = try o.lookup(&s, frame, "binding3823");
    const v3828 = try o.propertyKey(&s, v3827);
    const v3829 = try s.own(try js.getKey(e, v3826, v3828));
    const v3830 = try s.call(v3825, c.pi_js_undefined(), &.{v3829});
    return c.JS_DupValue(e.context, v3830);
}
fn body3821C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3821(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body3803(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3806 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3804", v3806);
    const v3807 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3805", v3807);
    const v3808 = try o.lookup(&s, frame, "binding3719");
    const v3809 = try o.lookup(&s, frame, "binding3805");
    const v3810 = try s.call(v3808, c.pi_js_undefined(), &.{v3809});
    const v3812 = logical3811: {
        if (s.truthy(v3810)) break :logical3811 v3810;
        const v3813 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v3814 = try s.text("Some");
        const v3815 = try s.own(try js.getKey(e, v3813, v3814));
        const v3816 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v3817 = try s.text("Keys");
        const v3818 = try s.own(try js.getKey(e, v3816, v3817));
        const v3819 = try o.lookup(&s, frame, "binding3804");
        const v3820 = try s.call(v3818, v3816, &.{v3819});
        const v3831 = try o.arrow(&s, "", 1, body3821C, &.{ graph, frame });
        const v3832 = try s.call(v3815, v3813, &.{ v3820, v3831 });
        break :logical3811 v3832;
    };
    return c.JS_DupValue(e.context, v3812);
}
fn constructor3836(e: *Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    const v3838 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3837", v3838);
    const receiver = try s.own(try class.object(e, target));
    try s.put(frame, "@this", receiver);
    const v3839 = try s.text("hasUnevaluated");
    const v3840 = try o.lookup(&s, frame, "binding3837");
    try js.setKey(e, receiver, v3839, v3840);
    return c.JS_DupValue(e.context, receiver);
}
fn body3842(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3843 = try s.text("hasUnevaluated");
    const v3844 = try s.own(try js.getKey(e, receiver, v3843));
    return c.JS_DupValue(e.context, v3844);
}
fn body3842C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3842(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body3846(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3847 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v3848 = try s.text("Call");
    const v3849 = try s.own(try js.getKey(e, v3847, v3848));
    const v3850 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v3851 = try s.text("Member");
    const v3852 = try s.own(try js.getKey(e, v3850, v3851));
    const v3853 = try s.text("context");
    const v3854 = try s.text("Push");
    const v3855 = try s.call(v3852, v3850, &.{ v3853, v3854 });
    const v3856 = try s.array();
    const v3857 = try s.call(v3849, v3847, &.{ v3855, v3856 });
    return c.JS_DupValue(e.context, v3857);
}
fn body3846C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3846(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body3859(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3860 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v3861 = try s.text("Call");
    const v3862 = try s.own(try js.getKey(e, v3860, v3861));
    const v3863 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v3864 = try s.text("Member");
    const v3865 = try s.own(try js.getKey(e, v3863, v3864));
    const v3866 = try s.text("context");
    const v3867 = try s.text("Pop");
    const v3868 = try s.call(v3865, v3863, &.{ v3866, v3867 });
    const v3869 = try s.array();
    const v3870 = try s.call(v3862, v3860, &.{ v3868, v3869 });
    return c.JS_DupValue(e.context, v3870);
}
fn body3859C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3859(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body3872(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3874 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3873", v3874);
    const v3875 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v3876 = try s.text("Call");
    const v3877 = try s.own(try js.getKey(e, v3875, v3876));
    const v3878 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v3879 = try s.text("Member");
    const v3880 = try s.own(try js.getKey(e, v3878, v3879));
    const v3881 = try s.text("context");
    const v3882 = try s.text("AddIndex");
    const v3883 = try s.call(v3880, v3878, &.{ v3881, v3882 });
    const v3884 = try s.array();
    const v3885 = try o.lookup(&s, frame, "binding3873");
    try o.append(&s, v3884, v3885);
    const v3886 = try s.call(v3877, v3875, &.{ v3883, v3884 });
    return c.JS_DupValue(e.context, v3886);
}
fn body3872C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3872(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body3888(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3890 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3889", v3890);
    const v3891 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v3892 = try s.text("Call");
    const v3893 = try s.own(try js.getKey(e, v3891, v3892));
    const v3894 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v3895 = try s.text("Member");
    const v3896 = try s.own(try js.getKey(e, v3894, v3895));
    const v3897 = try s.text("context");
    const v3898 = try s.text("AddKey");
    const v3899 = try s.call(v3896, v3894, &.{ v3897, v3898 });
    const v3900 = try s.array();
    const v3901 = try o.lookup(&s, frame, "binding3889");
    try o.append(&s, v3900, v3901);
    const v3902 = try s.call(v3893, v3891, &.{ v3899, v3900 });
    return c.JS_DupValue(e.context, v3902);
}
fn body3888C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3888(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body3904(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3906 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3905", v3906);
    const v3907 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v3908 = try s.text("Call");
    const v3909 = try s.own(try js.getKey(e, v3907, v3908));
    const v3910 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v3911 = try s.text("Member");
    const v3912 = try s.own(try js.getKey(e, v3910, v3911));
    const v3913 = try s.text("context");
    const v3914 = try s.text("Merge");
    const v3915 = try s.call(v3912, v3910, &.{ v3913, v3914 });
    const v3916 = try s.array();
    const v3917 = try o.lookup(&s, frame, "binding3905");
    try o.append(&s, v3916, v3917);
    const v3918 = try s.call(v3909, v3907, &.{ v3915, v3916 });
    return c.JS_DupValue(e.context, v3918);
}
fn body3904C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3904(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn constructor3921(e: *Engine, target: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    const receiver = try s.own(try class.object(e, target));
    try s.put(frame, "@this", receiver);
    const v3926 = try s.global("Set");
    const v3927 = try o.construct(&s, v3926, &.{});
    try o.assign(&s, frame, "binding3924", v3927);
    const v3928 = try s.global("Set");
    const v3929 = try o.construct(&s, v3928, &.{});
    try o.assign(&s, frame, "binding3925", v3929);
    const v3930 = try s.text("stack");
    const v3931 = try s.array();
    const v3932 = try s.object();
    const v3933 = try s.text("indices");
    const v3934 = try o.lookup(&s, frame, "binding3924");
    try o.defineKey(&s, v3932, v3933, v3934);
    const v3935 = try s.text("keys");
    const v3936 = try o.lookup(&s, frame, "binding3925");
    try o.defineKey(&s, v3932, v3935, v3936);
    try o.append(&s, v3931, v3932);
    try js.setKey(e, receiver, v3930, v3931);
    return c.JS_DupValue(e.context, receiver);
}
fn body3938(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3943 = try s.global("Set");
    const v3944 = try o.construct(&s, v3943, &.{});
    try o.assign(&s, frame, "binding3941", v3944);
    const v3945 = try s.global("Set");
    const v3946 = try o.construct(&s, v3945, &.{});
    try o.assign(&s, frame, "binding3942", v3946);
    const v3947 = try s.text("stack");
    const v3948 = try s.own(try js.getKey(e, receiver, v3947));
    const v3949 = try s.text("push");
    const v3950 = try s.own(try js.getKey(e, v3948, v3949));
    const v3951 = try s.object();
    const v3952 = try s.text("indices");
    const v3953 = try o.lookup(&s, frame, "binding3941");
    try o.defineKey(&s, v3951, v3952, v3953);
    const v3954 = try s.text("keys");
    const v3955 = try o.lookup(&s, frame, "binding3942");
    try o.defineKey(&s, v3951, v3954, v3955);
    const v3956 = try s.call(v3950, v3948, &.{v3951});
    _ = v3956;
    return c.JS_DupValue(e.context, o.boolean(&s, true));
}
fn body3938C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3938(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body3958(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3959 = try s.text("stack");
    const v3960 = try s.own(try js.getKey(e, receiver, v3959));
    const v3961 = try s.text("pop");
    const v3962 = try s.own(try js.getKey(e, v3960, v3961));
    const v3963 = try s.call(v3962, v3960, &.{});
    _ = v3963;
    return c.JS_DupValue(e.context, o.boolean(&s, true));
}
fn body3958C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3958(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body3965(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3967 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3966", v3967);
    const v3968 = try s.text("GetIndices");
    const v3969 = try s.own(try js.getKey(e, receiver, v3968));
    const v3970 = try s.call(v3969, receiver, &.{});
    const v3971 = try s.text("add");
    const v3972 = try s.own(try js.getKey(e, v3970, v3971));
    const v3973 = try o.lookup(&s, frame, "binding3966");
    const v3974 = try s.call(v3972, v3970, &.{v3973});
    _ = v3974;
    return c.JS_DupValue(e.context, o.boolean(&s, true));
}
fn body3965C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3965(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body3976(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3978 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3977", v3978);
    const v3979 = try s.text("GetKeys");
    const v3980 = try s.own(try js.getKey(e, receiver, v3979));
    const v3981 = try s.call(v3980, receiver, &.{});
    const v3982 = try s.text("add");
    const v3983 = try s.own(try js.getKey(e, v3981, v3982));
    const v3984 = try o.lookup(&s, frame, "binding3977");
    const v3985 = try s.call(v3983, v3981, &.{v3984});
    _ = v3985;
    return c.JS_DupValue(e.context, o.boolean(&s, true));
}
fn body3976C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3976(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body3987(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3990 = try s.text("stack");
    const v3991 = try s.own(try js.getKey(e, receiver, v3990));
    const v3992 = try s.text("stack");
    const v3993 = try s.own(try js.getKey(e, receiver, v3992));
    const v3994 = try s.text("length");
    const v3995 = try s.own(try js.getKey(e, v3993, v3994));
    const v3996 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 1, v3995, c.JS_NewFloat64(e.context, 1))));
    const v3997 = try o.propertyKey(&s, v3996);
    const v3998 = try s.own(try js.getKey(e, v3991, v3997));
    try o.assign(&s, frame, "binding3989", v3998);
    const v3999 = try o.lookup(&s, frame, "binding3989");
    const v4000 = try s.text("indices");
    const v4001 = try s.own(try js.getKey(e, v3999, v4000));
    return c.JS_DupValue(e.context, v4001);
}
fn body3987C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3987(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body4003(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v4006 = try s.text("stack");
    const v4007 = try s.own(try js.getKey(e, receiver, v4006));
    const v4008 = try s.text("stack");
    const v4009 = try s.own(try js.getKey(e, receiver, v4008));
    const v4010 = try s.text("length");
    const v4011 = try s.own(try js.getKey(e, v4009, v4010));
    const v4012 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 1, v4011, c.JS_NewFloat64(e.context, 1))));
    const v4013 = try o.propertyKey(&s, v4012);
    const v4014 = try s.own(try js.getKey(e, v4007, v4013));
    try o.assign(&s, frame, "binding4005", v4014);
    const v4015 = try o.lookup(&s, frame, "binding4005");
    const v4016 = try s.text("keys");
    const v4017 = try s.own(try js.getKey(e, v4015, v4016));
    return c.JS_DupValue(e.context, v4017);
}
fn body4003C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body4003(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body4034(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    const v4035 = try o.lookup(&s, frame, "@this");
    const v4037 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding4036", v4037);
    const v4038 = try s.text("GetIndices");
    const v4039 = try s.own(try js.getKey(e, v4035, v4038));
    const v4040 = try s.call(v4039, v4035, &.{});
    const v4041 = try s.text("add");
    const v4042 = try s.own(try js.getKey(e, v4040, v4041));
    const v4043 = try o.lookup(&s, frame, "binding4036");
    const v4044 = try s.call(v4042, v4040, &.{v4043});
    return c.JS_DupValue(e.context, v4044);
}
fn body4034C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body4034(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body4053(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    const v4054 = try o.lookup(&s, frame, "@this");
    const v4056 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding4055", v4056);
    const v4057 = try s.text("GetKeys");
    const v4058 = try s.own(try js.getKey(e, v4054, v4057));
    const v4059 = try s.call(v4058, v4054, &.{});
    const v4060 = try s.text("add");
    const v4061 = try s.own(try js.getKey(e, v4059, v4060));
    const v4062 = try o.lookup(&s, frame, "binding4055");
    const v4063 = try s.call(v4061, v4059, &.{v4062});
    return c.JS_DupValue(e.context, v4063);
}
fn body4053C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body4053(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body4019(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v4021 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding4020", v4021);
    const v4022 = try o.lookup(&s, frame, "binding4020");
    var iterator4023 = try o.iterator(e, v4022);
    defer iterator4023.deinit();
    errdefer iterator4023.closePreserving();
    while (try iterator4023.next()) |next4024| {
        defer e.freeValue(next4024);
        const iteration4026 = try o.frame(&s, frame);
        try o.assign(&s, iteration4026, "binding4027", next4024);
        const v4028 = try o.lookup(&s, iteration4026, "binding4027");
        const v4029 = try s.text("GetIndices");
        const v4030 = try s.own(try js.getKey(e, v4028, v4029));
        const v4031 = try s.call(v4030, v4028, &.{});
        const v4032 = try s.text("forEach");
        const v4033 = try s.own(try js.getKey(e, v4031, v4032));
        const v4045 = try o.arrow(&s, "", 1, body4034C, &.{ graph, iteration4026 });
        const v4046 = try s.call(v4033, v4031, &.{v4045});
        _ = v4046;
        const v4047 = try o.lookup(&s, iteration4026, "binding4027");
        const v4048 = try s.text("GetKeys");
        const v4049 = try s.own(try js.getKey(e, v4047, v4048));
        const v4050 = try s.call(v4049, v4047, &.{});
        const v4051 = try s.text("forEach");
        const v4052 = try s.own(try js.getKey(e, v4050, v4051));
        const v4064 = try o.arrow(&s, "", 1, body4053C, &.{ graph, iteration4026 });
        const v4065 = try s.call(v4052, v4050, &.{v4064});
        _ = v4065;
    }
    try iterator4023.close();
    return c.JS_DupValue(e.context, o.boolean(&s, true));
}
fn body4019C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body4019(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn constructor4069(e: *Engine, target: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    const receiver = try o.constructWithTarget(&s, roots[2], target, &.{});
    try s.put(frame, "@this", receiver);
    const v4070 = try s.text("errors");
    const v4071 = try s.array();
    try js.setKey(e, receiver, v4070, v4071);
    return c.JS_DupValue(e.context, receiver);
}
fn body4073(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v4074 = try s.text("errors");
    const v4075 = try s.own(try js.getKey(e, receiver, v4074));
    const v4076 = try s.text("length");
    const v4077 = try s.own(try js.getKey(e, v4075, v4076));
    const v4078 = try o.importValue(&s, graph, "system/settings/index.mjs", "Settings");
    const v4079 = try s.text("Get");
    const v4080 = try s.own(try js.getKey(e, v4078, v4079));
    const v4081 = try s.call(v4080, v4078, &.{});
    const v4082 = try s.text("maxErrors");
    const v4083 = try s.own(try js.getKey(e, v4081, v4082));
    const v4084 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 7, v4077, v4083)));
    return c.JS_DupValue(e.context, v4084);
}
fn body4073C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body4073(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body4086(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v4088 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding4087", v4088);
    const v4089 = try s.text("AtCapacity");
    const v4090 = try s.own(try js.getKey(e, receiver, v4089));
    const v4091 = try s.call(v4090, receiver, &.{});
    if (s.truthy(o.boolean(&s, !s.truthy(v4091)))) {
        const v4092 = try s.text("errors");
        const v4093 = try s.own(try js.getKey(e, receiver, v4092));
        const v4094 = try s.text("push");
        const v4095 = try s.own(try js.getKey(e, v4093, v4094));
        const v4096 = try o.lookup(&s, frame, "binding4087");
        const v4097 = try s.call(v4095, v4093, &.{v4096});
        _ = v4097;
    }
    return c.JS_DupValue(e.context, o.boolean(&s, false));
}
fn body4086C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body4086(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body4099(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v4100 = try s.text("errors");
    const v4101 = try s.own(try js.getKey(e, receiver, v4100));
    return c.JS_DupValue(e.context, v4101);
}
fn body4099C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body4099(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
