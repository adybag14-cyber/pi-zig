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
    const namespace = try s.get(modules, "schema/engine/_stack.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/engine/_stack.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/engine/_stack.mjs", bindings);
    const v4813 = logical4812: {
        if (!s.truthy(c.pi_js_undefined())) break :logical4812 c.pi_js_undefined();
        const v4814 = try s.text("__classPrivateFieldGet");
        const v4815 = try s.own(try js.getKey(e, c.pi_js_undefined(), v4814));
        break :logical4812 v4815;
    };
    const v4817 = logical4816: {
        if (s.truthy(v4813)) break :logical4816 v4813;
        const v4878 = try s.own(try ordinary.create(e, "", 4, body4818, &.{ graph, frame }));
        break :logical4816 v4878;
    };
    try o.assign(&s, frame, "binding4795", v4817);
    try o.assign(&s, frame, "binding4796", c.pi_js_undefined());
    try o.assign(&s, frame, "binding4797", c.pi_js_undefined());
    try o.assign(&s, frame, "binding4798", c.pi_js_undefined());
    try o.assign(&s, frame, "binding4799", c.pi_js_undefined());
    try o.assign(&s, frame, "binding4800", c.pi_js_undefined());
    try o.assign(&s, frame, "binding4801", c.pi_js_undefined());
    try o.assign(&s, frame, "binding4802", c.pi_js_undefined());
    try o.assign(&s, frame, "binding4803", c.pi_js_undefined());
    try o.assign(&s, frame, "binding4804", c.pi_js_undefined());
    try o.assign(&s, frame, "binding4805", c.pi_js_undefined());
    try o.assign(&s, frame, "binding4806", c.pi_js_undefined());
    try o.assign(&s, frame, "binding4807", c.pi_js_undefined());
    try o.assign(&s, frame, "binding4808", c.pi_js_undefined());
    try o.assign(&s, frame, "binding4809", c.pi_js_undefined());
    try o.assign(&s, frame, "binding4810", c.pi_js_undefined());
    const v4879 = try s.object();
    const v4912 = try s.own(try class.constructor(e, "Stack", 2, v4879, constructor4880, &.{ graph, frame, c.pi_js_undefined() }));
    const v4924 = try o.arrow(&s, "LexicalBaseURL", 0, body4913C, &.{ graph, frame });
    try o.method(&s, v4879, "LexicalBaseURL", v4924);
    const v5013 = try o.arrow(&s, "Push", 1, body4925C, &.{ graph, frame });
    try o.method(&s, v4879, "Push", v5013);
    const v5086 = try o.arrow(&s, "Pop", 1, body5014C, &.{ graph, frame });
    try o.method(&s, v4879, "Pop", v5086);
    const v5117 = try o.arrow(&s, "Ref", 1, body5087C, &.{ graph, frame });
    try o.method(&s, v4879, "Ref", v5117);
    const v5139 = try o.arrow(&s, "RecursiveRef", 1, body5118C, &.{ graph, frame });
    try o.method(&s, v4879, "RecursiveRef", v5139);
    const v5161 = try o.arrow(&s, "DynamicRef", 1, body5140C, &.{ graph, frame });
    try o.method(&s, v4879, "DynamicRef", v5161);
    try o.assign(&s, frame, "binding4811", v4912);
    const v5162 = try s.global("WeakSet");
    const v5163 = try o.construct(&s, v5162, &.{});
    try o.assign(&s, frame, "binding4796", v5163);
    const v5218 = try s.own(try ordinary.create(e, "_Stack_StackFrame", 0, body5164, &.{ graph, frame }));
    try o.assign(&s, frame, "binding4797", v5218);
    const v5285 = try s.own(try ordinary.create(e, "_Stack_ApplyRefResult", 1, body5219, &.{ graph, frame }));
    try o.assign(&s, frame, "binding4798", v5285);
    const v5348 = try s.own(try ordinary.create(e, "_Stack_BuildBase", 1, body5286, &.{ graph, frame }));
    try o.assign(&s, frame, "binding4799", v5348);
    const v5403 = try s.own(try ordinary.create(e, "_Stack_ResourceBaseURL", 0, body5349, &.{ graph, frame }));
    try o.assign(&s, frame, "binding4800", v5403);
    const v5453 = try s.own(try ordinary.create(e, "_Stack_ReferenceBaseURL", 0, body5404, &.{ graph, frame }));
    try o.assign(&s, frame, "binding4801", v5453);
    const v5507 = try s.own(try ordinary.create(e, "_Stack_LexicalSchema", 0, body5454, &.{ graph, frame }));
    try o.assign(&s, frame, "binding4802", v5507);
    const v5529 = try s.own(try ordinary.create(e, "_Stack_RegisterResourceAnchorArray", 1, body5508, &.{ graph, frame }));
    try o.assign(&s, frame, "binding4803", v5529);
    const v5551 = try s.own(try ordinary.create(e, "_Stack_UnregisterResourceAnchorArray", 1, body5530, &.{ graph, frame }));
    try o.assign(&s, frame, "binding4804", v5551);
    const v5629 = try s.own(try ordinary.create(e, "_Stack_RegisterResourceAnchors", 1, body5552, &.{ graph, frame }));
    try o.assign(&s, frame, "binding4805", v5629);
    const v5706 = try s.own(try ordinary.create(e, "_Stack_UnregisterResourceAnchors", 1, body5630, &.{ graph, frame }));
    try o.assign(&s, frame, "binding4806", v5706);
    const v5737 = try s.own(try ordinary.create(e, "_Stack_RegisterResource", 1, body5707, &.{ graph, frame }));
    try o.assign(&s, frame, "binding4807", v5737);
    const v5784 = try s.own(try ordinary.create(e, "_Stack_UnregisterResource", 1, body5738, &.{ graph, frame }));
    try o.assign(&s, frame, "binding4808", v5784);
    const v5806 = try s.own(try ordinary.create(e, "_Stack_EnterResolvedResource", 2, body5785, &.{ graph, frame }));
    try o.assign(&s, frame, "binding4809", v5806);
    const v5839 = try s.own(try ordinary.create(e, "_Stack_ExitResolvedResource", 1, body5807, &.{ graph, frame }));
    try o.assign(&s, frame, "binding4810", v5839);
    const v5840 = try o.lookup(&s, frame, "binding4811");
    try s.put(namespace, "Stack", v5840);
    try s.put(bindings, "Stack", try s.text("binding4811"));
}
fn body4818(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v4823 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding4819", v4823);
    const v4824 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding4820", v4824);
    const v4825 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding4821", v4825);
    const v4826 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding4822", v4826);
    const v4827 = try o.lookup(&s, frame, "binding4821");
    const v4828 = try s.text("a");
    const v4830 = logical4829: {
        if (!s.truthy(o.boolean(&s, s.equal(v4827, v4828)))) break :logical4829 o.boolean(&s, s.equal(v4827, v4828));
        const v4831 = try o.lookup(&s, frame, "binding4822");
        break :logical4829 o.boolean(&s, !s.truthy(v4831));
    };
    if (s.truthy(v4830)) {
        const v4832 = try s.global("TypeError");
        const v4833 = try s.text("Private accessor was defined without a getter");
        const v4834 = try o.construct(&s, v4832, &.{v4833});
        _ = c.JS_Throw(e.context, c.JS_DupValue(e.context, v4834));
        return js.capture(e);
    }
    const v4835 = try o.lookup(&s, frame, "binding4820");
    const v4836 = try o.typeOf(&s, v4835);
    const v4837 = try s.text("function");
    const v4839 = conditional4838: {
        if (s.truthy(o.boolean(&s, s.equal(v4836, v4837)))) {
            const v4840 = try o.lookup(&s, frame, "binding4819");
            const v4841 = try o.lookup(&s, frame, "binding4820");
            const v4843 = logical4842: {
                if (s.truthy(o.boolean(&s, !s.equal(v4840, v4841)))) break :logical4842 o.boolean(&s, !s.equal(v4840, v4841));
                const v4844 = try o.lookup(&s, frame, "binding4822");
                break :logical4842 o.boolean(&s, !s.truthy(v4844));
            };
            break :conditional4838 v4843;
        } else {
            const v4845 = try o.lookup(&s, frame, "binding4820");
            const v4846 = try s.text("has");
            const v4847 = try s.own(try js.getKey(e, v4845, v4846));
            const v4848 = try o.lookup(&s, frame, "binding4819");
            const v4849 = try s.call(v4847, v4845, &.{v4848});
            break :conditional4838 o.boolean(&s, !s.truthy(v4849));
        }
    };
    if (s.truthy(v4839)) {
        const v4850 = try s.global("TypeError");
        const v4851 = try s.text("Cannot read private member from an object whose class did not declare it");
        const v4852 = try o.construct(&s, v4850, &.{v4851});
        _ = c.JS_Throw(e.context, c.JS_DupValue(e.context, v4852));
        return js.capture(e);
    }
    const v4853 = try o.lookup(&s, frame, "binding4821");
    const v4854 = try s.text("m");
    const v4856 = conditional4855: {
        if (s.truthy(o.boolean(&s, s.equal(v4853, v4854)))) {
            const v4857 = try o.lookup(&s, frame, "binding4822");
            break :conditional4855 v4857;
        } else {
            const v4858 = try o.lookup(&s, frame, "binding4821");
            const v4859 = try s.text("a");
            const v4861 = conditional4860: {
                if (s.truthy(o.boolean(&s, s.equal(v4858, v4859)))) {
                    const v4862 = try o.lookup(&s, frame, "binding4822");
                    const v4863 = try s.text("call");
                    const v4864 = try s.own(try js.getKey(e, v4862, v4863));
                    const v4865 = try o.lookup(&s, frame, "binding4819");
                    const v4866 = try s.call(v4864, v4862, &.{v4865});
                    break :conditional4860 v4866;
                } else {
                    const v4867 = try o.lookup(&s, frame, "binding4822");
                    const v4869 = conditional4868: {
                        if (s.truthy(v4867)) {
                            const v4870 = try o.lookup(&s, frame, "binding4822");
                            const v4871 = try s.text("value");
                            const v4872 = try s.own(try js.getKey(e, v4870, v4871));
                            break :conditional4868 v4872;
                        } else {
                            const v4873 = try o.lookup(&s, frame, "binding4820");
                            const v4874 = try s.text("get");
                            const v4875 = try s.own(try js.getKey(e, v4873, v4874));
                            const v4876 = try o.lookup(&s, frame, "binding4819");
                            const v4877 = try s.call(v4875, v4873, &.{v4876});
                            break :conditional4868 v4877;
                        }
                    };
                    break :conditional4860 v4869;
                }
            };
            break :conditional4855 v4861;
        }
    };
    return c.JS_DupValue(e.context, v4856);
}
fn constructor4880(e: *Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    const v4883 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding4881", v4883);
    const v4884 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding4882", v4884);
    const receiver = try s.own(try class.object(e, target));
    try s.put(frame, "@this", receiver);
    const v4885 = try o.lookup(&s, frame, "binding4796");
    const v4886 = try s.text("add");
    const v4887 = try s.own(try js.getKey(e, v4885, v4886));
    const v4888 = try s.call(v4887, v4885, &.{receiver});
    _ = v4888;
    const v4889 = try s.text("context");
    const v4890 = try o.lookup(&s, frame, "binding4881");
    try js.setKey(e, receiver, v4889, v4890);
    const v4891 = try s.text("schema");
    const v4892 = try o.lookup(&s, frame, "binding4882");
    try js.setKey(e, receiver, v4891, v4892);
    const v4893 = try s.text("ids");
    const v4894 = try s.array();
    try js.setKey(e, receiver, v4893, v4894);
    const v4895 = try s.text("resourceIds");
    const v4896 = try s.array();
    try js.setKey(e, receiver, v4895, v4896);
    const v4897 = try s.text("anchors");
    const v4898 = try s.array();
    try js.setKey(e, receiver, v4897, v4898);
    const v4899 = try s.text("recursiveAnchors");
    const v4900 = try s.array();
    try js.setKey(e, receiver, v4899, v4900);
    const v4901 = try s.text("dynamicAnchors");
    const v4902 = try s.array();
    try js.setKey(e, receiver, v4901, v4902);
    const v4903 = try s.text("retrievedResources");
    const v4904 = try s.global("Map");
    const v4905 = try o.construct(&s, v4904, &.{});
    try js.setKey(e, receiver, v4903, v4905);
    const v4906 = try s.text("retrievedFrames");
    const v4907 = try s.array();
    try js.setKey(e, receiver, v4906, v4907);
    const v4908 = try s.text("resolvedResources");
    const v4909 = try s.global("Map");
    const v4910 = try o.construct(&s, v4909, &.{});
    try js.setKey(e, receiver, v4908, v4910);
    const v4911 = try s.text("pendingResource");
    try js.setKey(e, receiver, v4911, o.boolean(&s, true));
    _ = o.boolean(&s, true);
    return c.JS_DupValue(e.context, receiver);
}
fn body4913(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v4914 = try o.lookup(&s, frame, "binding4795");
    const v4915 = try o.lookup(&s, frame, "binding4796");
    const v4916 = try s.text("m");
    const v4917 = try o.lookup(&s, frame, "binding4799");
    const v4918 = try s.call(v4914, c.pi_js_undefined(), &.{ receiver, v4915, v4916, v4917 });
    const v4919 = try s.text("call");
    const v4920 = try s.own(try js.getKey(e, v4918, v4919));
    const v4921 = try s.text("ids");
    const v4922 = try s.own(try js.getKey(e, receiver, v4921));
    const v4923 = try s.call(v4920, v4918, &.{ receiver, v4922 });
    return c.JS_DupValue(e.context, v4923);
}
fn body4913C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body4913(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body4925(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v4928 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding4926", v4928);
    const v4930 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v4931 = try s.text("IsSchemaObject");
    const v4932 = try s.own(try js.getKey(e, v4930, v4931));
    const v4933 = try o.lookup(&s, frame, "binding4926");
    const v4934 = try s.call(v4932, v4930, &.{v4933});
    if (s.truthy(o.boolean(&s, !s.truthy(v4934)))) {
        return c.JS_DupValue(e.context, c.pi_js_undefined());
    }
    const v4935 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v4936 = try s.text("IsId");
    const v4937 = try s.own(try js.getKey(e, v4935, v4936));
    const v4938 = try o.lookup(&s, frame, "binding4926");
    const v4939 = try s.call(v4937, v4935, &.{v4938});
    if (s.truthy(v4939)) {
        const v4940 = try o.lookup(&s, frame, "binding4795");
        const v4941 = try o.lookup(&s, frame, "binding4796");
        const v4942 = try s.text("m");
        const v4943 = try o.lookup(&s, frame, "binding4807");
        const v4944 = try s.call(v4940, c.pi_js_undefined(), &.{ receiver, v4941, v4942, v4943 });
        const v4945 = try s.text("call");
        const v4946 = try s.own(try js.getKey(e, v4944, v4945));
        const v4947 = try o.lookup(&s, frame, "binding4926");
        const v4948 = try s.call(v4946, v4944, &.{ receiver, v4947 });
        _ = v4948;
    }
    const v4949 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v4950 = try s.text("IsAnchor");
    const v4951 = try s.own(try js.getKey(e, v4949, v4950));
    const v4952 = try o.lookup(&s, frame, "binding4926");
    const v4953 = try s.call(v4951, v4949, &.{v4952});
    if (s.truthy(v4953)) {
        const v4954 = try s.text("anchors");
        const v4955 = try s.own(try js.getKey(e, receiver, v4954));
        const v4956 = try s.text("push");
        const v4957 = try s.own(try js.getKey(e, v4955, v4956));
        const v4958 = try o.lookup(&s, frame, "binding4926");
        const v4959 = try s.call(v4957, v4955, &.{v4958});
        _ = v4959;
    }
    const v4960 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v4961 = try s.text("IsRecursiveAnchorTrue");
    const v4962 = try s.own(try js.getKey(e, v4960, v4961));
    const v4963 = try o.lookup(&s, frame, "binding4926");
    const v4964 = try s.call(v4962, v4960, &.{v4963});
    if (s.truthy(v4964)) {
        const v4965 = try s.text("recursiveAnchors");
        const v4966 = try s.own(try js.getKey(e, receiver, v4965));
        const v4967 = try s.text("push");
        const v4968 = try s.own(try js.getKey(e, v4966, v4967));
        const v4969 = try o.lookup(&s, frame, "binding4926");
        const v4970 = try s.call(v4968, v4966, &.{v4969});
        _ = v4970;
    }
    const v4971 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v4972 = try s.text("IsDynamicAnchor");
    const v4973 = try s.own(try js.getKey(e, v4971, v4972));
    const v4974 = try o.lookup(&s, frame, "binding4926");
    const v4975 = try s.call(v4973, v4971, &.{v4974});
    if (s.truthy(v4975)) {
        const v4976 = try s.text("dynamicAnchors");
        const v4977 = try s.own(try js.getKey(e, receiver, v4976));
        const v4978 = try s.text("push");
        const v4979 = try s.own(try js.getKey(e, v4977, v4978));
        const v4980 = try o.lookup(&s, frame, "binding4926");
        const v4981 = try s.call(v4979, v4977, &.{v4980});
        _ = v4981;
    }
    const v4982 = try s.text("retrievedResources");
    const v4983 = try s.own(try js.getKey(e, receiver, v4982));
    const v4984 = try s.text("get");
    const v4985 = try s.own(try js.getKey(e, v4983, v4984));
    const v4986 = try o.lookup(&s, frame, "binding4926");
    const v4987 = try s.call(v4985, v4983, &.{v4986});
    try o.assign(&s, frame, "binding4929", v4987);
    const v4988 = try o.lookup(&s, frame, "binding4929");
    if (s.truthy(v4988)) {
        const v4989 = try s.text("retrievedFrames");
        const v4990 = try s.own(try js.getKey(e, receiver, v4989));
        const v4991 = try s.text("push");
        const v4992 = try s.own(try js.getKey(e, v4990, v4991));
        const v4993 = try s.object();
        const v4994 = try s.text("schema");
        const v4995 = try o.lookup(&s, frame, "binding4929");
        const v4996 = try s.text("root");
        const v4997 = try s.own(try js.getKey(e, v4995, v4996));
        try o.defineKey(&s, v4993, v4994, v4997);
        const v4998 = try s.text("base");
        const v4999 = try o.lookup(&s, frame, "binding4929");
        const v5000 = try s.text("base");
        const v5001 = try s.own(try js.getKey(e, v4999, v5000));
        try o.defineKey(&s, v4993, v4998, v5001);
        const v5002 = try s.text("idDepth");
        const v5003 = try s.text("ids");
        const v5004 = try s.own(try js.getKey(e, receiver, v5003));
        const v5005 = try s.text("length");
        const v5006 = try s.own(try js.getKey(e, v5004, v5005));
        try o.defineKey(&s, v4993, v5002, v5006);
        const v5007 = try s.text("resourceDepth");
        const v5008 = try s.text("resourceIds");
        const v5009 = try s.own(try js.getKey(e, receiver, v5008));
        const v5010 = try s.text("length");
        const v5011 = try s.own(try js.getKey(e, v5009, v5010));
        try o.defineKey(&s, v4993, v5007, v5011);
        const v5012 = try s.call(v4992, v4990, &.{v4993});
        _ = v5012;
    }
    return c.pi_js_undefined();
}
fn body4925C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body4925(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body5014(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v5016 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding5015", v5016);
    const v5017 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v5018 = try s.text("IsSchemaObject");
    const v5019 = try s.own(try js.getKey(e, v5017, v5018));
    const v5020 = try o.lookup(&s, frame, "binding5015");
    const v5021 = try s.call(v5019, v5017, &.{v5020});
    if (s.truthy(o.boolean(&s, !s.truthy(v5021)))) {
        return c.JS_DupValue(e.context, c.pi_js_undefined());
    }
    const v5022 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v5023 = try s.text("IsId");
    const v5024 = try s.own(try js.getKey(e, v5022, v5023));
    const v5025 = try o.lookup(&s, frame, "binding5015");
    const v5026 = try s.call(v5024, v5022, &.{v5025});
    if (s.truthy(v5026)) {
        const v5027 = try o.lookup(&s, frame, "binding4795");
        const v5028 = try o.lookup(&s, frame, "binding4796");
        const v5029 = try s.text("m");
        const v5030 = try o.lookup(&s, frame, "binding4808");
        const v5031 = try s.call(v5027, c.pi_js_undefined(), &.{ receiver, v5028, v5029, v5030 });
        const v5032 = try s.text("call");
        const v5033 = try s.own(try js.getKey(e, v5031, v5032));
        const v5034 = try o.lookup(&s, frame, "binding5015");
        const v5035 = try s.call(v5033, v5031, &.{ receiver, v5034 });
        _ = v5035;
    }
    const v5036 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v5037 = try s.text("IsAnchor");
    const v5038 = try s.own(try js.getKey(e, v5036, v5037));
    const v5039 = try o.lookup(&s, frame, "binding5015");
    const v5040 = try s.call(v5038, v5036, &.{v5039});
    if (s.truthy(v5040)) {
        const v5041 = try s.text("anchors");
        const v5042 = try s.own(try js.getKey(e, receiver, v5041));
        const v5043 = try s.text("pop");
        const v5044 = try s.own(try js.getKey(e, v5042, v5043));
        const v5045 = try s.call(v5044, v5042, &.{});
        _ = v5045;
    }
    const v5046 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v5047 = try s.text("IsRecursiveAnchorTrue");
    const v5048 = try s.own(try js.getKey(e, v5046, v5047));
    const v5049 = try o.lookup(&s, frame, "binding5015");
    const v5050 = try s.call(v5048, v5046, &.{v5049});
    if (s.truthy(v5050)) {
        const v5051 = try s.text("recursiveAnchors");
        const v5052 = try s.own(try js.getKey(e, receiver, v5051));
        const v5053 = try s.text("pop");
        const v5054 = try s.own(try js.getKey(e, v5052, v5053));
        const v5055 = try s.call(v5054, v5052, &.{});
        _ = v5055;
    }
    const v5056 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v5057 = try s.text("IsDynamicAnchor");
    const v5058 = try s.own(try js.getKey(e, v5056, v5057));
    const v5059 = try o.lookup(&s, frame, "binding5015");
    const v5060 = try s.call(v5058, v5056, &.{v5059});
    if (s.truthy(v5060)) {
        const v5061 = try s.text("dynamicAnchors");
        const v5062 = try s.own(try js.getKey(e, receiver, v5061));
        const v5063 = try s.text("pop");
        const v5064 = try s.own(try js.getKey(e, v5062, v5063));
        const v5065 = try s.call(v5064, v5062, &.{});
        _ = v5065;
    }
    const v5066 = try s.text("retrievedResources");
    const v5067 = try s.own(try js.getKey(e, receiver, v5066));
    const v5068 = try s.text("has");
    const v5069 = try s.own(try js.getKey(e, v5067, v5068));
    const v5070 = try o.lookup(&s, frame, "binding5015");
    const v5071 = try s.call(v5069, v5067, &.{v5070});
    if (s.truthy(v5071)) {
        const v5072 = try s.text("retrievedFrames");
        const v5073 = try s.own(try js.getKey(e, receiver, v5072));
        const v5074 = try s.text("pop");
        const v5075 = try s.own(try js.getKey(e, v5073, v5074));
        const v5076 = try s.call(v5075, v5073, &.{});
        _ = v5076;
    }
    const v5077 = try o.lookup(&s, frame, "binding4795");
    const v5078 = try o.lookup(&s, frame, "binding4796");
    const v5079 = try s.text("m");
    const v5080 = try o.lookup(&s, frame, "binding4810");
    const v5081 = try s.call(v5077, c.pi_js_undefined(), &.{ receiver, v5078, v5079, v5080 });
    const v5082 = try s.text("call");
    const v5083 = try s.own(try js.getKey(e, v5081, v5082));
    const v5084 = try o.lookup(&s, frame, "binding5015");
    const v5085 = try s.call(v5083, v5081, &.{ receiver, v5084 });
    _ = v5085;
    return c.pi_js_undefined();
}
fn body5014C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body5014(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body5087(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v5090 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding5088", v5090);
    const v5092 = try o.importValue(&s, graph, "schema/resolve/index.mjs", "Resolve");
    const v5093 = try s.text("ResolveRef");
    const v5094 = try s.own(try js.getKey(e, v5092, v5093));
    const v5095 = try o.lookup(&s, frame, "binding4795");
    const v5096 = try o.lookup(&s, frame, "binding4796");
    const v5097 = try s.text("m");
    const v5098 = try o.lookup(&s, frame, "binding4797");
    const v5099 = try s.call(v5095, c.pi_js_undefined(), &.{ receiver, v5096, v5097, v5098 });
    const v5100 = try s.text("call");
    const v5101 = try s.own(try js.getKey(e, v5099, v5100));
    const v5102 = try s.call(v5101, v5099, &.{receiver});
    const v5103 = try o.lookup(&s, frame, "binding5088");
    const v5104 = try s.call(v5094, v5092, &.{ v5102, v5103 });
    try o.assign(&s, frame, "binding5091", v5104);
    const v5105 = try o.lookup(&s, frame, "binding4795");
    const v5106 = try o.lookup(&s, frame, "binding4796");
    const v5107 = try s.text("m");
    const v5108 = try o.lookup(&s, frame, "binding4798");
    const v5109 = try s.call(v5105, c.pi_js_undefined(), &.{ receiver, v5106, v5107, v5108 });
    const v5110 = try s.text("call");
    const v5111 = try s.own(try js.getKey(e, v5109, v5110));
    const v5112 = try o.lookup(&s, frame, "binding5091");
    const v5113 = try s.call(v5111, v5109, &.{ receiver, v5112 });
    _ = v5113;
    const v5114 = try o.lookup(&s, frame, "binding5091");
    const v5115 = try s.text("schema");
    const v5116 = try s.own(try js.getKey(e, v5114, v5115));
    return c.JS_DupValue(e.context, v5116);
}
fn body5087C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body5087(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body5118(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v5121 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding5119", v5121);
    const v5123 = try o.importValue(&s, graph, "schema/resolve/index.mjs", "Resolve");
    const v5124 = try s.text("ResolveRecursiveRef");
    const v5125 = try s.own(try js.getKey(e, v5123, v5124));
    const v5126 = try o.lookup(&s, frame, "binding4795");
    const v5127 = try o.lookup(&s, frame, "binding4796");
    const v5128 = try s.text("m");
    const v5129 = try o.lookup(&s, frame, "binding4797");
    const v5130 = try s.call(v5126, c.pi_js_undefined(), &.{ receiver, v5127, v5128, v5129 });
    const v5131 = try s.text("call");
    const v5132 = try s.own(try js.getKey(e, v5130, v5131));
    const v5133 = try s.call(v5132, v5130, &.{receiver});
    const v5134 = try o.lookup(&s, frame, "binding5119");
    const v5135 = try s.call(v5125, v5123, &.{ v5133, v5134 });
    try o.assign(&s, frame, "binding5122", v5135);
    const v5136 = try o.lookup(&s, frame, "binding5122");
    if (s.truthy(v5136)) {
        const v5137 = try s.text("pendingResource");
        try js.setKey(e, receiver, v5137, o.boolean(&s, true));
        _ = o.boolean(&s, true);
    }
    const v5138 = try o.lookup(&s, frame, "binding5122");
    return c.JS_DupValue(e.context, v5138);
}
fn body5118C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body5118(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body5140(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v5143 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding5141", v5143);
    const v5145 = try o.importValue(&s, graph, "schema/resolve/index.mjs", "Resolve");
    const v5146 = try s.text("ResolveDynamicRef");
    const v5147 = try s.own(try js.getKey(e, v5145, v5146));
    const v5148 = try o.lookup(&s, frame, "binding4795");
    const v5149 = try o.lookup(&s, frame, "binding4796");
    const v5150 = try s.text("m");
    const v5151 = try o.lookup(&s, frame, "binding4797");
    const v5152 = try s.call(v5148, c.pi_js_undefined(), &.{ receiver, v5149, v5150, v5151 });
    const v5153 = try s.text("call");
    const v5154 = try s.own(try js.getKey(e, v5152, v5153));
    const v5155 = try s.call(v5154, v5152, &.{receiver});
    const v5156 = try o.lookup(&s, frame, "binding5141");
    const v5157 = try s.call(v5147, v5145, &.{ v5155, v5156 });
    try o.assign(&s, frame, "binding5144", v5157);
    const v5158 = try o.lookup(&s, frame, "binding5144");
    if (s.truthy(v5158)) {
        const v5159 = try s.text("pendingResource");
        try js.setKey(e, receiver, v5159, o.boolean(&s, true));
        _ = o.boolean(&s, true);
    }
    const v5160 = try o.lookup(&s, frame, "binding5144");
    return c.JS_DupValue(e.context, v5160);
}
fn body5140C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body5140(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body5164(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v5165 = try s.object();
    const v5166 = try s.text("context");
    const v5167 = try s.text("context");
    const v5168 = try s.own(try js.getKey(e, receiver, v5167));
    try o.defineKey(&s, v5165, v5166, v5168);
    const v5169 = try s.text("root");
    const v5170 = try s.text("schema");
    const v5171 = try s.own(try js.getKey(e, receiver, v5170));
    try o.defineKey(&s, v5165, v5169, v5171);
    const v5172 = try s.text("ids");
    const v5173 = try s.text("ids");
    const v5174 = try s.own(try js.getKey(e, receiver, v5173));
    try o.defineKey(&s, v5165, v5172, v5174);
    const v5175 = try s.text("lexicalSchema");
    const v5176 = try o.lookup(&s, frame, "binding4795");
    const v5177 = try o.lookup(&s, frame, "binding4796");
    const v5178 = try s.text("m");
    const v5179 = try o.lookup(&s, frame, "binding4802");
    const v5180 = try s.call(v5176, c.pi_js_undefined(), &.{ receiver, v5177, v5178, v5179 });
    const v5181 = try s.text("call");
    const v5182 = try s.own(try js.getKey(e, v5180, v5181));
    const v5183 = try s.call(v5182, v5180, &.{receiver});
    try o.defineKey(&s, v5165, v5175, v5183);
    const v5184 = try s.text("lexicalBase");
    const v5185 = try s.text("LexicalBaseURL");
    const v5186 = try s.own(try js.getKey(e, receiver, v5185));
    const v5187 = try s.call(v5186, receiver, &.{});
    try o.defineKey(&s, v5165, v5184, v5187);
    const v5188 = try s.text("referenceBase");
    const v5189 = try o.lookup(&s, frame, "binding4795");
    const v5190 = try o.lookup(&s, frame, "binding4796");
    const v5191 = try s.text("m");
    const v5192 = try o.lookup(&s, frame, "binding4801");
    const v5193 = try s.call(v5189, c.pi_js_undefined(), &.{ receiver, v5190, v5191, v5192 });
    const v5194 = try s.text("call");
    const v5195 = try s.own(try js.getKey(e, v5193, v5194));
    const v5196 = try s.call(v5195, v5193, &.{receiver});
    try o.defineKey(&s, v5165, v5188, v5196);
    const v5197 = try s.text("resourceBase");
    const v5198 = try o.lookup(&s, frame, "binding4795");
    const v5199 = try o.lookup(&s, frame, "binding4796");
    const v5200 = try s.text("m");
    const v5201 = try o.lookup(&s, frame, "binding4800");
    const v5202 = try s.call(v5198, c.pi_js_undefined(), &.{ receiver, v5199, v5200, v5201 });
    const v5203 = try s.text("call");
    const v5204 = try s.own(try js.getKey(e, v5202, v5203));
    const v5205 = try s.call(v5204, v5202, &.{receiver});
    try o.defineKey(&s, v5165, v5197, v5205);
    const v5206 = try s.text("recursiveAnchors");
    const v5207 = try s.text("recursiveAnchors");
    const v5208 = try s.own(try js.getKey(e, receiver, v5207));
    try o.defineKey(&s, v5165, v5206, v5208);
    const v5209 = try s.text("dynamicAnchors");
    const v5210 = try s.text("dynamicAnchors");
    const v5211 = try s.own(try js.getKey(e, receiver, v5210));
    try o.defineKey(&s, v5165, v5209, v5211);
    const v5212 = try s.text("inRetrievedFrame");
    const v5213 = try s.text("retrievedFrames");
    const v5214 = try s.own(try js.getKey(e, receiver, v5213));
    const v5215 = try s.text("length");
    const v5216 = try s.own(try js.getKey(e, v5214, v5215));
    const v5217 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 6, v5216, c.JS_NewFloat64(e.context, 0))));
    try o.defineKey(&s, v5165, v5212, v5217);
    return c.JS_DupValue(e.context, v5165);
}
fn body5219(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v5221 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding5220", v5221);
    const v5222 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v5223 = try s.text("IsUndefined");
    const v5224 = try s.own(try js.getKey(e, v5222, v5223));
    const v5225 = try o.lookup(&s, frame, "binding5220");
    const v5226 = try s.text("schema");
    const v5227 = try s.own(try js.getKey(e, v5225, v5226));
    const v5228 = try s.call(v5224, v5222, &.{v5227});
    if (s.truthy(o.boolean(&s, !s.truthy(v5228)))) {
        const v5229 = try s.text("pendingResource");
        try js.setKey(e, receiver, v5229, o.boolean(&s, true));
        _ = o.boolean(&s, true);
    }
    const v5230 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v5231 = try s.text("IsUndefined");
    const v5232 = try s.own(try js.getKey(e, v5230, v5231));
    const v5233 = try o.lookup(&s, frame, "binding5220");
    const v5234 = try s.text("resolvedResource");
    const v5235 = try s.own(try js.getKey(e, v5233, v5234));
    const v5236 = try s.call(v5232, v5230, &.{v5235});
    if (s.truthy(o.boolean(&s, !s.truthy(v5236)))) {
        const v5237 = try o.lookup(&s, frame, "binding4795");
        const v5238 = try o.lookup(&s, frame, "binding4796");
        const v5239 = try s.text("m");
        const v5240 = try o.lookup(&s, frame, "binding4809");
        const v5241 = try s.call(v5237, c.pi_js_undefined(), &.{ receiver, v5238, v5239, v5240 });
        const v5242 = try s.text("call");
        const v5243 = try s.own(try js.getKey(e, v5241, v5242));
        const v5244 = try o.lookup(&s, frame, "binding5220");
        const v5245 = try s.text("resolvedResource");
        const v5246 = try s.own(try js.getKey(e, v5244, v5245));
        const v5247 = try s.text("target");
        const v5248 = try s.own(try js.getKey(e, v5246, v5247));
        const v5249 = try o.lookup(&s, frame, "binding5220");
        const v5250 = try s.text("resolvedResource");
        const v5251 = try s.own(try js.getKey(e, v5249, v5250));
        const v5252 = try s.text("resource");
        const v5253 = try s.own(try js.getKey(e, v5251, v5252));
        const v5254 = try s.call(v5243, v5241, &.{ receiver, v5248, v5253 });
        _ = v5254;
    }
    const v5255 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v5256 = try s.text("IsUndefined");
    const v5257 = try s.own(try js.getKey(e, v5255, v5256));
    const v5258 = try o.lookup(&s, frame, "binding5220");
    const v5259 = try s.text("retrievedResource");
    const v5260 = try s.own(try js.getKey(e, v5258, v5259));
    const v5261 = try s.call(v5257, v5255, &.{v5260});
    if (s.truthy(o.boolean(&s, !s.truthy(v5261)))) {
        const v5262 = try s.text("retrievedResources");
        const v5263 = try s.own(try js.getKey(e, receiver, v5262));
        const v5264 = try s.text("set");
        const v5265 = try s.own(try js.getKey(e, v5263, v5264));
        const v5266 = try o.lookup(&s, frame, "binding5220");
        const v5267 = try s.text("retrievedResource");
        const v5268 = try s.own(try js.getKey(e, v5266, v5267));
        const v5269 = try s.text("target");
        const v5270 = try s.own(try js.getKey(e, v5268, v5269));
        const v5271 = try s.object();
        const v5272 = try s.text("base");
        const v5273 = try o.lookup(&s, frame, "binding5220");
        const v5274 = try s.text("retrievedResource");
        const v5275 = try s.own(try js.getKey(e, v5273, v5274));
        const v5276 = try s.text("base");
        const v5277 = try s.own(try js.getKey(e, v5275, v5276));
        try o.defineKey(&s, v5271, v5272, v5277);
        const v5278 = try s.text("root");
        const v5279 = try o.lookup(&s, frame, "binding5220");
        const v5280 = try s.text("retrievedResource");
        const v5281 = try s.own(try js.getKey(e, v5279, v5280));
        const v5282 = try s.text("root");
        const v5283 = try s.own(try js.getKey(e, v5281, v5282));
        try o.defineKey(&s, v5271, v5278, v5283);
        const v5284 = try s.call(v5265, v5263, &.{ v5270, v5271 });
        _ = v5284;
    }
    return c.pi_js_undefined();
}
fn body5331(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v5335 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding5333", v5335);
    const v5336 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding5334", v5336);
    const v5337 = try s.global("URL");
    const v5338 = try o.lookup(&s, frame, "binding5334");
    const v5339 = try s.text("$id");
    const v5340 = try s.own(try js.getKey(e, v5338, v5339));
    const v5341 = try o.lookup(&s, frame, "binding5333");
    const v5342 = try o.construct(&s, v5337, &.{ v5340, v5341 });
    return c.JS_DupValue(e.context, v5342);
}
fn body5331C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body5331(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body5286(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v5291 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding5287", v5291);
    const v5295 = try s.text("retrievedFrames");
    const v5296 = try s.own(try js.getKey(e, receiver, v5295));
    const v5297 = try s.text("retrievedFrames");
    const v5298 = try s.own(try js.getKey(e, receiver, v5297));
    const v5299 = try s.text("length");
    const v5300 = try s.own(try js.getKey(e, v5298, v5299));
    const v5301 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 1, v5300, c.JS_NewFloat64(e.context, 1))));
    const v5302 = try o.propertyKey(&s, v5301);
    const v5303 = try s.own(try js.getKey(e, v5296, v5302));
    try o.assign(&s, frame, "binding5292", v5303);
    const v5304 = try o.lookup(&s, frame, "binding5292");
    const v5306 = conditional5305: {
        if (s.truthy(v5304)) {
            const v5307 = try s.global("URL");
            const v5308 = try o.lookup(&s, frame, "binding5292");
            const v5309 = try s.text("base");
            const v5310 = try s.own(try js.getKey(e, v5308, v5309));
            const v5311 = try o.construct(&s, v5307, &.{v5310});
            break :conditional5305 v5311;
        } else {
            const v5312 = try s.global("URL");
            const v5313 = try o.importValue(&s, graph, "schema/resolve/index.mjs", "Resolve");
            const v5314 = try s.text("DefaultBase");
            const v5315 = try s.own(try js.getKey(e, v5313, v5314));
            const v5316 = try o.construct(&s, v5312, &.{v5315});
            break :conditional5305 v5316;
        }
    };
    try o.assign(&s, frame, "binding5293", v5306);
    const v5317 = try o.lookup(&s, frame, "binding5292");
    const v5319 = conditional5318: {
        if (s.truthy(v5317)) {
            const v5320 = try o.lookup(&s, frame, "binding5287");
            const v5321 = try s.text("slice");
            const v5322 = try s.own(try js.getKey(e, v5320, v5321));
            const v5323 = try o.lookup(&s, frame, "binding5292");
            const v5324 = try s.text("idDepth");
            const v5325 = try s.own(try js.getKey(e, v5323, v5324));
            const v5326 = try s.call(v5322, v5320, &.{v5325});
            break :conditional5318 v5326;
        } else {
            const v5327 = try o.lookup(&s, frame, "binding5287");
            break :conditional5318 v5327;
        }
    };
    try o.assign(&s, frame, "binding5294", v5319);
    const v5328 = try o.lookup(&s, frame, "binding5294");
    const v5329 = try s.text("reduce");
    const v5330 = try s.own(try js.getKey(e, v5328, v5329));
    const v5343 = try o.arrow(&s, "", 2, body5331C, &.{ graph, frame });
    const v5344 = try o.lookup(&s, frame, "binding5293");
    const v5345 = try s.call(v5330, v5328, &.{ v5343, v5344 });
    const v5346 = try s.text("href");
    const v5347 = try s.own(try js.getKey(e, v5345, v5346));
    return c.JS_DupValue(e.context, v5347);
}
fn body5382(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v5386 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding5384", v5386);
    const v5387 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding5385", v5387);
    const v5388 = try s.global("URL");
    const v5389 = try o.lookup(&s, frame, "binding5385");
    const v5390 = try s.text("$id");
    const v5391 = try s.own(try js.getKey(e, v5389, v5390));
    const v5392 = try o.lookup(&s, frame, "binding5384");
    const v5393 = try o.construct(&s, v5388, &.{ v5391, v5392 });
    return c.JS_DupValue(e.context, v5393);
}
fn body5382C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body5382(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body5349(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v5352 = try s.text("retrievedFrames");
    const v5353 = try s.own(try js.getKey(e, receiver, v5352));
    const v5354 = try s.text("retrievedFrames");
    const v5355 = try s.own(try js.getKey(e, receiver, v5354));
    const v5356 = try s.text("length");
    const v5357 = try s.own(try js.getKey(e, v5355, v5356));
    const v5358 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 1, v5357, c.JS_NewFloat64(e.context, 1))));
    const v5359 = try o.propertyKey(&s, v5358);
    const v5360 = try s.own(try js.getKey(e, v5353, v5359));
    try o.assign(&s, frame, "binding5351", v5360);
    const v5361 = try o.lookup(&s, frame, "binding5351");
    if (s.truthy(o.boolean(&s, !s.truthy(v5361)))) {
        const v5362 = try o.lookup(&s, frame, "binding4795");
        const v5363 = try o.lookup(&s, frame, "binding4796");
        const v5364 = try s.text("m");
        const v5365 = try o.lookup(&s, frame, "binding4799");
        const v5366 = try s.call(v5362, c.pi_js_undefined(), &.{ receiver, v5363, v5364, v5365 });
        const v5367 = try s.text("call");
        const v5368 = try s.own(try js.getKey(e, v5366, v5367));
        const v5369 = try s.text("resourceIds");
        const v5370 = try s.own(try js.getKey(e, receiver, v5369));
        const v5371 = try s.call(v5368, v5366, &.{ receiver, v5370 });
        return c.JS_DupValue(e.context, v5371);
    }
    const v5372 = try s.text("resourceIds");
    const v5373 = try s.own(try js.getKey(e, receiver, v5372));
    const v5374 = try s.text("slice");
    const v5375 = try s.own(try js.getKey(e, v5373, v5374));
    const v5376 = try o.lookup(&s, frame, "binding5351");
    const v5377 = try s.text("resourceDepth");
    const v5378 = try s.own(try js.getKey(e, v5376, v5377));
    const v5379 = try s.call(v5375, v5373, &.{v5378});
    const v5380 = try s.text("reduce");
    const v5381 = try s.own(try js.getKey(e, v5379, v5380));
    const v5394 = try o.arrow(&s, "", 2, body5382C, &.{ graph, frame });
    const v5395 = try s.global("URL");
    const v5396 = try o.lookup(&s, frame, "binding5351");
    const v5397 = try s.text("base");
    const v5398 = try s.own(try js.getKey(e, v5396, v5397));
    const v5399 = try o.construct(&s, v5395, &.{v5398});
    const v5400 = try s.call(v5381, v5379, &.{ v5394, v5399 });
    const v5401 = try s.text("href");
    const v5402 = try s.own(try js.getKey(e, v5400, v5401));
    return c.JS_DupValue(e.context, v5402);
}
fn body5404(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v5407 = try s.text("retrievedFrames");
    const v5408 = try s.own(try js.getKey(e, receiver, v5407));
    const v5409 = try s.text("length");
    const v5410 = try s.own(try js.getKey(e, v5408, v5409));
    const v5411 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 6, v5410, c.JS_NewFloat64(e.context, 0))));
    if (s.truthy(v5411)) {
        const v5412 = try o.lookup(&s, frame, "binding4795");
        const v5413 = try o.lookup(&s, frame, "binding4796");
        const v5414 = try s.text("m");
        const v5415 = try o.lookup(&s, frame, "binding4800");
        const v5416 = try s.call(v5412, c.pi_js_undefined(), &.{ receiver, v5413, v5414, v5415 });
        const v5417 = try s.text("call");
        const v5418 = try s.own(try js.getKey(e, v5416, v5417));
        const v5419 = try s.call(v5418, v5416, &.{receiver});
        return c.JS_DupValue(e.context, v5419);
    }
    const v5420 = try s.text("ids");
    const v5421 = try s.own(try js.getKey(e, receiver, v5420));
    const v5422 = try s.text("ids");
    const v5423 = try s.own(try js.getKey(e, receiver, v5422));
    const v5424 = try s.text("length");
    const v5425 = try s.own(try js.getKey(e, v5423, v5424));
    const v5426 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 1, v5425, c.JS_NewFloat64(e.context, 1))));
    const v5427 = try o.propertyKey(&s, v5426);
    const v5428 = try s.own(try js.getKey(e, v5421, v5427));
    try o.assign(&s, frame, "binding5406", v5428);
    const v5429 = try o.lookup(&s, frame, "binding5406");
    const v5431 = logical5430: {
        if (!s.truthy(v5429)) break :logical5430 v5429;
        const v5432 = try s.text("^[A-Za-z][A-Za-z0-9+.-]*:");
        const v5433 = try s.text("");
        const v5434 = try s.global("RegExp");
        const v5435 = try o.construct(&s, v5434, &.{ v5432, v5433 });
        const v5436 = try s.text("test");
        const v5437 = try s.own(try js.getKey(e, v5435, v5436));
        const v5438 = try o.lookup(&s, frame, "binding5406");
        const v5439 = try s.text("$id");
        const v5440 = try s.own(try js.getKey(e, v5438, v5439));
        const v5441 = try s.call(v5437, v5435, &.{v5440});
        break :logical5430 o.boolean(&s, !s.truthy(v5441));
    };
    if (s.truthy(v5431)) {
        const v5442 = try s.text("LexicalBaseURL");
        const v5443 = try s.own(try js.getKey(e, receiver, v5442));
        const v5444 = try s.call(v5443, receiver, &.{});
        return c.JS_DupValue(e.context, v5444);
    }
    const v5445 = try o.lookup(&s, frame, "binding4795");
    const v5446 = try o.lookup(&s, frame, "binding4796");
    const v5447 = try s.text("m");
    const v5448 = try o.lookup(&s, frame, "binding4800");
    const v5449 = try s.call(v5445, c.pi_js_undefined(), &.{ receiver, v5446, v5447, v5448 });
    const v5450 = try s.text("call");
    const v5451 = try s.own(try js.getKey(e, v5449, v5450));
    const v5452 = try s.call(v5451, v5449, &.{receiver});
    return c.JS_DupValue(e.context, v5452);
}
fn body5454(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v5457 = try s.text("retrievedFrames");
    const v5458 = try s.own(try js.getKey(e, receiver, v5457));
    const v5459 = try s.text("retrievedFrames");
    const v5460 = try s.own(try js.getKey(e, receiver, v5459));
    const v5461 = try s.text("length");
    const v5462 = try s.own(try js.getKey(e, v5460, v5461));
    const v5463 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 1, v5462, c.JS_NewFloat64(e.context, 1))));
    const v5464 = try o.propertyKey(&s, v5463);
    const v5465 = try s.own(try js.getKey(e, v5458, v5464));
    try o.assign(&s, frame, "binding5456", v5465);
    const v5466 = try o.lookup(&s, frame, "binding5456");
    if (s.truthy(v5466)) {
        const v5467 = try s.text("ids");
        const v5468 = try s.own(try js.getKey(e, receiver, v5467));
        const v5469 = try s.text("length");
        const v5470 = try s.own(try js.getKey(e, v5468, v5469));
        const v5471 = try o.lookup(&s, frame, "binding5456");
        const v5472 = try s.text("idDepth");
        const v5473 = try s.own(try js.getKey(e, v5471, v5472));
        const v5474 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 6, v5470, v5473)));
        const v5476 = conditional5475: {
            if (s.truthy(v5474)) {
                const v5477 = try s.text("ids");
                const v5478 = try s.own(try js.getKey(e, receiver, v5477));
                const v5479 = try s.text("ids");
                const v5480 = try s.own(try js.getKey(e, receiver, v5479));
                const v5481 = try s.text("length");
                const v5482 = try s.own(try js.getKey(e, v5480, v5481));
                const v5483 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 1, v5482, c.JS_NewFloat64(e.context, 1))));
                const v5484 = try o.propertyKey(&s, v5483);
                const v5485 = try s.own(try js.getKey(e, v5478, v5484));
                break :conditional5475 v5485;
            } else {
                const v5486 = try o.lookup(&s, frame, "binding5456");
                const v5487 = try s.text("schema");
                const v5488 = try s.own(try js.getKey(e, v5486, v5487));
                break :conditional5475 v5488;
            }
        };
        return c.JS_DupValue(e.context, v5476);
    }
    const v5489 = try s.text("ids");
    const v5490 = try s.own(try js.getKey(e, receiver, v5489));
    const v5491 = try s.text("length");
    const v5492 = try s.own(try js.getKey(e, v5490, v5491));
    const v5493 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 6, v5492, c.JS_NewFloat64(e.context, 0))));
    const v5495 = conditional5494: {
        if (s.truthy(v5493)) {
            const v5496 = try s.text("ids");
            const v5497 = try s.own(try js.getKey(e, receiver, v5496));
            const v5498 = try s.text("ids");
            const v5499 = try s.own(try js.getKey(e, receiver, v5498));
            const v5500 = try s.text("length");
            const v5501 = try s.own(try js.getKey(e, v5499, v5500));
            const v5502 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 1, v5501, c.JS_NewFloat64(e.context, 1))));
            const v5503 = try o.propertyKey(&s, v5502);
            const v5504 = try s.own(try js.getKey(e, v5497, v5503));
            break :conditional5494 v5504;
        } else {
            const v5505 = try s.text("schema");
            const v5506 = try s.own(try js.getKey(e, receiver, v5505));
            break :conditional5494 v5506;
        }
    };
    return c.JS_DupValue(e.context, v5495);
}
fn body5514(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    const v5515 = try o.lookup(&s, frame, "@this");
    const v5517 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding5516", v5517);
    const v5518 = try o.lookup(&s, frame, "binding4795");
    const v5519 = try o.lookup(&s, frame, "binding4796");
    const v5520 = try s.text("m");
    const v5521 = try o.lookup(&s, frame, "binding4805");
    const v5522 = try s.call(v5518, c.pi_js_undefined(), &.{ v5515, v5519, v5520, v5521 });
    const v5523 = try s.text("call");
    const v5524 = try s.own(try js.getKey(e, v5522, v5523));
    const v5525 = try o.lookup(&s, frame, "binding5516");
    const v5526 = try s.call(v5524, v5522, &.{ v5515, v5525, o.boolean(&s, false) });
    return c.JS_DupValue(e.context, v5526);
}
fn body5514C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body5514(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body5508(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v5510 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding5509", v5510);
    const v5511 = try o.lookup(&s, frame, "binding5509");
    const v5512 = try s.text("forEach");
    const v5513 = try s.own(try js.getKey(e, v5511, v5512));
    const v5527 = try o.arrow(&s, "", 1, body5514C, &.{ graph, frame });
    const v5528 = try s.call(v5513, v5511, &.{v5527});
    _ = v5528;
    return c.pi_js_undefined();
}
fn body5536(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    const v5537 = try o.lookup(&s, frame, "@this");
    const v5539 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding5538", v5539);
    const v5540 = try o.lookup(&s, frame, "binding4795");
    const v5541 = try o.lookup(&s, frame, "binding4796");
    const v5542 = try s.text("m");
    const v5543 = try o.lookup(&s, frame, "binding4806");
    const v5544 = try s.call(v5540, c.pi_js_undefined(), &.{ v5537, v5541, v5542, v5543 });
    const v5545 = try s.text("call");
    const v5546 = try s.own(try js.getKey(e, v5544, v5545));
    const v5547 = try o.lookup(&s, frame, "binding5538");
    const v5548 = try s.call(v5546, v5544, &.{ v5537, v5547, o.boolean(&s, false) });
    return c.JS_DupValue(e.context, v5548);
}
fn body5536C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body5536(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body5530(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v5532 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding5531", v5532);
    const v5533 = try o.lookup(&s, frame, "binding5531");
    const v5534 = try s.text("forEach");
    const v5535 = try s.own(try js.getKey(e, v5533, v5534));
    const v5549 = try o.arrow(&s, "", 1, body5536C, &.{ graph, frame });
    const v5550 = try s.call(v5535, v5533, &.{v5549});
    _ = v5550;
    return c.pi_js_undefined();
}
fn body5552(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v5556 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding5553", v5556);
    const v5557 = if (args.len > 1) args[1] else c.pi_js_undefined();
    const v5558 = default_value: {
        if (!c.JS_IsUndefined(v5557)) break :default_value v5557;
        break :default_value o.boolean(&s, true);
    };
    try o.assign(&s, frame, "binding5554", v5558);
    const v5560 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v5561 = try s.text("IsSchemaBoolean");
    const v5562 = try s.own(try js.getKey(e, v5560, v5561));
    const v5563 = try o.lookup(&s, frame, "binding5553");
    const v5564 = try s.call(v5562, v5560, &.{v5563});
    if (s.truthy(v5564)) {
        return c.JS_DupValue(e.context, c.pi_js_undefined());
    }
    const v5565 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v5566 = try s.text("IsArray");
    const v5567 = try s.own(try js.getKey(e, v5565, v5566));
    const v5568 = try o.lookup(&s, frame, "binding5553");
    const v5569 = try s.call(v5567, v5565, &.{v5568});
    if (s.truthy(v5569)) {
        const v5570 = try o.lookup(&s, frame, "binding4795");
        const v5571 = try o.lookup(&s, frame, "binding4796");
        const v5572 = try s.text("m");
        const v5573 = try o.lookup(&s, frame, "binding4803");
        const v5574 = try s.call(v5570, c.pi_js_undefined(), &.{ receiver, v5571, v5572, v5573 });
        const v5575 = try s.text("call");
        const v5576 = try s.own(try js.getKey(e, v5574, v5575));
        const v5577 = try o.lookup(&s, frame, "binding5553");
        const v5578 = try s.call(v5576, v5574, &.{ receiver, v5577 });
        return c.JS_DupValue(e.context, v5578);
    }
    const v5579 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v5580 = try s.text("IsSchemaObject");
    const v5581 = try s.own(try js.getKey(e, v5579, v5580));
    const v5582 = try o.lookup(&s, frame, "binding5553");
    const v5583 = try s.call(v5581, v5579, &.{v5582});
    if (s.truthy(o.boolean(&s, !s.truthy(v5583)))) {
        return c.JS_DupValue(e.context, c.pi_js_undefined());
    }
    const v5584 = try o.lookup(&s, frame, "binding5553");
    try o.assign(&s, frame, "binding5559", v5584);
    const v5585 = try o.lookup(&s, frame, "binding5554");
    const v5587 = logical5586: {
        if (!s.truthy(o.boolean(&s, !s.truthy(v5585)))) break :logical5586 o.boolean(&s, !s.truthy(v5585));
        const v5588 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
        const v5589 = try s.text("IsId");
        const v5590 = try s.own(try js.getKey(e, v5588, v5589));
        const v5591 = try o.lookup(&s, frame, "binding5559");
        const v5592 = try s.call(v5590, v5588, &.{v5591});
        break :logical5586 v5592;
    };
    if (s.truthy(v5587)) {
        return c.JS_DupValue(e.context, c.pi_js_undefined());
    }
    const v5593 = try o.lookup(&s, frame, "binding5554");
    const v5595 = logical5594: {
        if (!s.truthy(o.boolean(&s, !s.truthy(v5593)))) break :logical5594 o.boolean(&s, !s.truthy(v5593));
        const v5596 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
        const v5597 = try s.text("IsDynamicAnchor");
        const v5598 = try s.own(try js.getKey(e, v5596, v5597));
        const v5599 = try o.lookup(&s, frame, "binding5559");
        const v5600 = try s.call(v5598, v5596, &.{v5599});
        break :logical5594 v5600;
    };
    if (s.truthy(v5595)) {
        const v5601 = try s.text("dynamicAnchors");
        const v5602 = try s.own(try js.getKey(e, receiver, v5601));
        const v5603 = try s.text("push");
        const v5604 = try s.own(try js.getKey(e, v5602, v5603));
        const v5605 = try o.lookup(&s, frame, "binding5559");
        const v5606 = try s.call(v5604, v5602, &.{v5605});
        _ = v5606;
    }
    const v5607 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v5608 = try s.text("Keys");
    const v5609 = try s.own(try js.getKey(e, v5607, v5608));
    const v5610 = try o.lookup(&s, frame, "binding5559");
    const v5611 = try s.call(v5609, v5607, &.{v5610});
    var iterator5612 = try o.iterator(e, v5611);
    defer iterator5612.deinit();
    errdefer iterator5612.closePreserving();
    while (try iterator5612.next()) |next5613| {
        defer e.freeValue(next5613);
        const iteration5615 = try o.frame(&s, frame);
        try o.assign(&s, iteration5615, "binding5616", next5613);
        const v5617 = try o.lookup(&s, iteration5615, "binding4795");
        const v5618 = try o.lookup(&s, iteration5615, "binding4796");
        const v5619 = try s.text("m");
        const v5620 = try o.lookup(&s, iteration5615, "binding4805");
        const v5621 = try s.call(v5617, c.pi_js_undefined(), &.{ receiver, v5618, v5619, v5620 });
        const v5622 = try s.text("call");
        const v5623 = try s.own(try js.getKey(e, v5621, v5622));
        const v5624 = try o.lookup(&s, iteration5615, "binding5559");
        const v5625 = try o.lookup(&s, iteration5615, "binding5616");
        const v5626 = try o.propertyKey(&s, v5625);
        const v5627 = try s.own(try js.getKey(e, v5624, v5626));
        const v5628 = try s.call(v5623, v5621, &.{ receiver, v5627, o.boolean(&s, false) });
        _ = v5628;
    }
    try iterator5612.close();
    return c.pi_js_undefined();
}
fn body5630(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v5634 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding5631", v5634);
    const v5635 = if (args.len > 1) args[1] else c.pi_js_undefined();
    const v5636 = default_value: {
        if (!c.JS_IsUndefined(v5635)) break :default_value v5635;
        break :default_value o.boolean(&s, true);
    };
    try o.assign(&s, frame, "binding5632", v5636);
    const v5638 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v5639 = try s.text("IsSchemaBoolean");
    const v5640 = try s.own(try js.getKey(e, v5638, v5639));
    const v5641 = try o.lookup(&s, frame, "binding5631");
    const v5642 = try s.call(v5640, v5638, &.{v5641});
    if (s.truthy(v5642)) {
        return c.JS_DupValue(e.context, c.pi_js_undefined());
    }
    const v5643 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v5644 = try s.text("IsArray");
    const v5645 = try s.own(try js.getKey(e, v5643, v5644));
    const v5646 = try o.lookup(&s, frame, "binding5631");
    const v5647 = try s.call(v5645, v5643, &.{v5646});
    if (s.truthy(v5647)) {
        const v5648 = try o.lookup(&s, frame, "binding4795");
        const v5649 = try o.lookup(&s, frame, "binding4796");
        const v5650 = try s.text("m");
        const v5651 = try o.lookup(&s, frame, "binding4804");
        const v5652 = try s.call(v5648, c.pi_js_undefined(), &.{ receiver, v5649, v5650, v5651 });
        const v5653 = try s.text("call");
        const v5654 = try s.own(try js.getKey(e, v5652, v5653));
        const v5655 = try o.lookup(&s, frame, "binding5631");
        const v5656 = try s.call(v5654, v5652, &.{ receiver, v5655 });
        return c.JS_DupValue(e.context, v5656);
    }
    const v5657 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v5658 = try s.text("IsSchemaObject");
    const v5659 = try s.own(try js.getKey(e, v5657, v5658));
    const v5660 = try o.lookup(&s, frame, "binding5631");
    const v5661 = try s.call(v5659, v5657, &.{v5660});
    if (s.truthy(o.boolean(&s, !s.truthy(v5661)))) {
        return c.JS_DupValue(e.context, c.pi_js_undefined());
    }
    const v5662 = try o.lookup(&s, frame, "binding5631");
    try o.assign(&s, frame, "binding5637", v5662);
    const v5663 = try o.lookup(&s, frame, "binding5632");
    const v5665 = logical5664: {
        if (!s.truthy(o.boolean(&s, !s.truthy(v5663)))) break :logical5664 o.boolean(&s, !s.truthy(v5663));
        const v5666 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
        const v5667 = try s.text("IsId");
        const v5668 = try s.own(try js.getKey(e, v5666, v5667));
        const v5669 = try o.lookup(&s, frame, "binding5637");
        const v5670 = try s.call(v5668, v5666, &.{v5669});
        break :logical5664 v5670;
    };
    if (s.truthy(v5665)) {
        return c.JS_DupValue(e.context, c.pi_js_undefined());
    }
    const v5671 = try o.lookup(&s, frame, "binding5632");
    const v5673 = logical5672: {
        if (!s.truthy(o.boolean(&s, !s.truthy(v5671)))) break :logical5672 o.boolean(&s, !s.truthy(v5671));
        const v5674 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
        const v5675 = try s.text("IsDynamicAnchor");
        const v5676 = try s.own(try js.getKey(e, v5674, v5675));
        const v5677 = try o.lookup(&s, frame, "binding5637");
        const v5678 = try s.call(v5676, v5674, &.{v5677});
        break :logical5672 v5678;
    };
    if (s.truthy(v5673)) {
        const v5679 = try s.text("dynamicAnchors");
        const v5680 = try s.own(try js.getKey(e, receiver, v5679));
        const v5681 = try s.text("pop");
        const v5682 = try s.own(try js.getKey(e, v5680, v5681));
        const v5683 = try s.call(v5682, v5680, &.{});
        _ = v5683;
    }
    const v5684 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v5685 = try s.text("Keys");
    const v5686 = try s.own(try js.getKey(e, v5684, v5685));
    const v5687 = try o.lookup(&s, frame, "binding5637");
    const v5688 = try s.call(v5686, v5684, &.{v5687});
    var iterator5689 = try o.iterator(e, v5688);
    defer iterator5689.deinit();
    errdefer iterator5689.closePreserving();
    while (try iterator5689.next()) |next5690| {
        defer e.freeValue(next5690);
        const iteration5692 = try o.frame(&s, frame);
        try o.assign(&s, iteration5692, "binding5693", next5690);
        const v5694 = try o.lookup(&s, iteration5692, "binding4795");
        const v5695 = try o.lookup(&s, iteration5692, "binding4796");
        const v5696 = try s.text("m");
        const v5697 = try o.lookup(&s, iteration5692, "binding4806");
        const v5698 = try s.call(v5694, c.pi_js_undefined(), &.{ receiver, v5695, v5696, v5697 });
        const v5699 = try s.text("call");
        const v5700 = try s.own(try js.getKey(e, v5698, v5699));
        const v5701 = try o.lookup(&s, iteration5692, "binding5637");
        const v5702 = try o.lookup(&s, iteration5692, "binding5693");
        const v5703 = try o.propertyKey(&s, v5702);
        const v5704 = try s.own(try js.getKey(e, v5701, v5703));
        const v5705 = try s.call(v5700, v5698, &.{ receiver, v5704, o.boolean(&s, false) });
        _ = v5705;
    }
    try iterator5689.close();
    return c.pi_js_undefined();
}
fn body5707(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v5710 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding5708", v5710);
    const v5712 = try s.text("ids");
    const v5713 = try s.own(try js.getKey(e, receiver, v5712));
    const v5714 = try s.text("push");
    const v5715 = try s.own(try js.getKey(e, v5713, v5714));
    const v5716 = try o.lookup(&s, frame, "binding5708");
    const v5717 = try s.call(v5715, v5713, &.{v5716});
    _ = v5717;
    const v5718 = try s.text("pendingResource");
    const v5719 = try s.own(try js.getKey(e, receiver, v5718));
    try o.assign(&s, frame, "binding5711", v5719);
    const v5720 = try s.text("pendingResource");
    try js.setKey(e, receiver, v5720, o.boolean(&s, false));
    _ = o.boolean(&s, false);
    const v5721 = try o.lookup(&s, frame, "binding5711");
    if (s.truthy(v5721)) {
        const v5722 = try s.text("resourceIds");
        const v5723 = try s.own(try js.getKey(e, receiver, v5722));
        const v5724 = try s.text("push");
        const v5725 = try s.own(try js.getKey(e, v5723, v5724));
        const v5726 = try o.lookup(&s, frame, "binding5708");
        const v5727 = try s.call(v5725, v5723, &.{v5726});
        _ = v5727;
    }
    const v5728 = try o.lookup(&s, frame, "binding4795");
    const v5729 = try o.lookup(&s, frame, "binding4796");
    const v5730 = try s.text("m");
    const v5731 = try o.lookup(&s, frame, "binding4805");
    const v5732 = try s.call(v5728, c.pi_js_undefined(), &.{ receiver, v5729, v5730, v5731 });
    const v5733 = try s.text("call");
    const v5734 = try s.own(try js.getKey(e, v5732, v5733));
    const v5735 = try o.lookup(&s, frame, "binding5708");
    const v5736 = try s.call(v5734, v5732, &.{ receiver, v5735, o.boolean(&s, true) });
    _ = v5736;
    return c.pi_js_undefined();
}
fn body5738(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v5741 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding5739", v5741);
    const v5743 = try s.text("ids");
    const v5744 = try s.own(try js.getKey(e, receiver, v5743));
    const v5745 = try s.text("pop");
    const v5746 = try s.own(try js.getKey(e, v5744, v5745));
    const v5747 = try s.call(v5746, v5744, &.{});
    _ = v5747;
    const v5748 = try s.text("resourceIds");
    const v5749 = try s.own(try js.getKey(e, receiver, v5748));
    const v5750 = try s.text("length");
    const v5751 = try s.own(try js.getKey(e, v5749, v5750));
    const v5752 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 6, v5751, c.JS_NewFloat64(e.context, 0))));
    const v5754 = logical5753: {
        if (!s.truthy(v5752)) break :logical5753 v5752;
        const v5755 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v5756 = try s.text("IsEqual");
        const v5757 = try s.own(try js.getKey(e, v5755, v5756));
        const v5758 = try s.text("resourceIds");
        const v5759 = try s.own(try js.getKey(e, receiver, v5758));
        const v5760 = try s.text("resourceIds");
        const v5761 = try s.own(try js.getKey(e, receiver, v5760));
        const v5762 = try s.text("length");
        const v5763 = try s.own(try js.getKey(e, v5761, v5762));
        const v5764 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 1, v5763, c.JS_NewFloat64(e.context, 1))));
        const v5765 = try o.propertyKey(&s, v5764);
        const v5766 = try s.own(try js.getKey(e, v5759, v5765));
        const v5767 = try o.lookup(&s, frame, "binding5739");
        const v5768 = try s.call(v5757, v5755, &.{ v5766, v5767 });
        break :logical5753 v5768;
    };
    try o.assign(&s, frame, "binding5742", v5754);
    const v5769 = try o.lookup(&s, frame, "binding5742");
    if (s.truthy(v5769)) {
        const v5770 = try s.text("resourceIds");
        const v5771 = try s.own(try js.getKey(e, receiver, v5770));
        const v5772 = try s.text("pop");
        const v5773 = try s.own(try js.getKey(e, v5771, v5772));
        const v5774 = try s.call(v5773, v5771, &.{});
        _ = v5774;
    }
    const v5775 = try o.lookup(&s, frame, "binding4795");
    const v5776 = try o.lookup(&s, frame, "binding4796");
    const v5777 = try s.text("m");
    const v5778 = try o.lookup(&s, frame, "binding4806");
    const v5779 = try s.call(v5775, c.pi_js_undefined(), &.{ receiver, v5776, v5777, v5778 });
    const v5780 = try s.text("call");
    const v5781 = try s.own(try js.getKey(e, v5779, v5780));
    const v5782 = try o.lookup(&s, frame, "binding5739");
    const v5783 = try s.call(v5781, v5779, &.{ receiver, v5782, o.boolean(&s, true) });
    _ = v5783;
    return c.pi_js_undefined();
}
fn body5785(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v5788 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding5786", v5788);
    const v5789 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding5787", v5789);
    const v5790 = try o.lookup(&s, frame, "binding4795");
    const v5791 = try o.lookup(&s, frame, "binding4796");
    const v5792 = try s.text("m");
    const v5793 = try o.lookup(&s, frame, "binding4807");
    const v5794 = try s.call(v5790, c.pi_js_undefined(), &.{ receiver, v5791, v5792, v5793 });
    const v5795 = try s.text("call");
    const v5796 = try s.own(try js.getKey(e, v5794, v5795));
    const v5797 = try o.lookup(&s, frame, "binding5787");
    const v5798 = try s.call(v5796, v5794, &.{ receiver, v5797 });
    _ = v5798;
    const v5799 = try s.text("resolvedResources");
    const v5800 = try s.own(try js.getKey(e, receiver, v5799));
    const v5801 = try s.text("set");
    const v5802 = try s.own(try js.getKey(e, v5800, v5801));
    const v5803 = try o.lookup(&s, frame, "binding5786");
    const v5804 = try o.lookup(&s, frame, "binding5787");
    const v5805 = try s.call(v5802, v5800, &.{ v5803, v5804 });
    _ = v5805;
    return c.pi_js_undefined();
}
fn body5807(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v5810 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding5808", v5810);
    const v5812 = try s.text("resolvedResources");
    const v5813 = try s.own(try js.getKey(e, receiver, v5812));
    const v5814 = try s.text("has");
    const v5815 = try s.own(try js.getKey(e, v5813, v5814));
    const v5816 = try o.lookup(&s, frame, "binding5808");
    const v5817 = try s.call(v5815, v5813, &.{v5816});
    if (s.truthy(o.boolean(&s, !s.truthy(v5817)))) {
        return c.JS_DupValue(e.context, c.pi_js_undefined());
    }
    const v5818 = try s.text("resolvedResources");
    const v5819 = try s.own(try js.getKey(e, receiver, v5818));
    const v5820 = try s.text("get");
    const v5821 = try s.own(try js.getKey(e, v5819, v5820));
    const v5822 = try o.lookup(&s, frame, "binding5808");
    const v5823 = try s.call(v5821, v5819, &.{v5822});
    try o.assign(&s, frame, "binding5811", v5823);
    const v5824 = try o.lookup(&s, frame, "binding4795");
    const v5825 = try o.lookup(&s, frame, "binding4796");
    const v5826 = try s.text("m");
    const v5827 = try o.lookup(&s, frame, "binding4808");
    const v5828 = try s.call(v5824, c.pi_js_undefined(), &.{ receiver, v5825, v5826, v5827 });
    const v5829 = try s.text("call");
    const v5830 = try s.own(try js.getKey(e, v5828, v5829));
    const v5831 = try o.lookup(&s, frame, "binding5811");
    const v5832 = try s.call(v5830, v5828, &.{ receiver, v5831 });
    _ = v5832;
    const v5833 = try s.text("resolvedResources");
    const v5834 = try s.own(try js.getKey(e, receiver, v5833));
    const v5835 = try s.text("delete");
    const v5836 = try s.own(try js.getKey(e, v5834, v5835));
    const v5837 = try o.lookup(&s, frame, "binding5808");
    const v5838 = try s.call(v5836, v5834, &.{v5837});
    _ = v5838;
    return c.pi_js_undefined();
}
