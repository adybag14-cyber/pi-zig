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
    const namespace = try s.get(modules, "guard/string.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "guard/string.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "guard/string.mjs", bindings);
    const v2865 = try s.own(try ordinary.create(e, "IsBetween", 3, body2850, &.{ graph, frame }));
    try o.assign(&s, frame, "binding2835", v2865);
    const v2870 = try s.own(try ordinary.create(e, "IsZeroWidthJoiner", 1, body2866, &.{ graph, frame }));
    try o.assign(&s, frame, "binding2836", v2870);
    const v2877 = try s.own(try ordinary.create(e, "IsHighSurrogate", 1, body2871, &.{ graph, frame }));
    try o.assign(&s, frame, "binding2837", v2877);
    const v2884 = try s.own(try ordinary.create(e, "IsRegionalIndicator", 1, body2878, &.{ graph, frame }));
    try o.assign(&s, frame, "binding2838", v2884);
    const v2891 = try s.own(try ordinary.create(e, "IsVariationSelector", 1, body2885, &.{ graph, frame }));
    try o.assign(&s, frame, "binding2839", v2891);
    const v2913 = try s.own(try ordinary.create(e, "IsCombiningMark", 1, body2892, &.{ graph, frame }));
    try o.assign(&s, frame, "binding2840", v2913);
    const v2921 = try s.own(try ordinary.create(e, "CodePointLength", 1, body2914, &.{ graph, frame }));
    try o.assign(&s, frame, "binding2841", v2921);
    const v2953 = try s.own(try ordinary.create(e, "ConsumeModifiers", 2, body2922, &.{ graph, frame }));
    try o.assign(&s, frame, "binding2842", v2953);
    const v3039 = try s.own(try ordinary.create(e, "NextGraphemeClusterIndex", 2, body2954, &.{ graph, frame }));
    try o.assign(&s, frame, "binding2843", v3039);
    const v3065 = try s.own(try ordinary.create(e, "IsGraphemeCodePoint", 1, body3040, &.{ graph, frame }));
    try o.assign(&s, frame, "binding2844", v3065);
    const v3086 = try s.own(try ordinary.create(e, "GraphemeCount", 1, body3066, &.{ graph, frame }));
    try o.assign(&s, frame, "binding2845", v3086);
    const v3110 = try s.own(try ordinary.create(e, "IsMinLengthSegmented", 2, body3087, &.{ graph, frame }));
    try o.assign(&s, frame, "binding2846", v3110);
    const v3134 = try s.own(try ordinary.create(e, "IsMaxLengthSegmented", 2, body3111, &.{ graph, frame }));
    try o.assign(&s, frame, "binding2847", v3134);
    const v3164 = try s.own(try ordinary.create(e, "IsMinLength", 2, body3135, &.{ graph, frame }));
    try o.assign(&s, frame, "binding2848", v3164);
    const v3193 = try s.own(try ordinary.create(e, "IsMaxLength", 2, body3165, &.{ graph, frame }));
    try o.assign(&s, frame, "binding2849", v3193);
    const v3194 = try o.lookup(&s, frame, "binding2845");
    try s.put(namespace, "GraphemeCount", v3194);
    const v3195 = try o.lookup(&s, frame, "binding2848");
    try s.put(namespace, "IsMinLength", v3195);
    const v3196 = try o.lookup(&s, frame, "binding2849");
    try s.put(namespace, "IsMaxLength", v3196);
    const v3197 = try o.lookup(&s, frame, "binding2845");
    try s.put(namespace, "GraphemeCount", v3197);
    const v3198 = try o.lookup(&s, frame, "binding2848");
    try s.put(namespace, "IsMinLength", v3198);
    const v3199 = try o.lookup(&s, frame, "binding2849");
    try s.put(namespace, "IsMaxLength", v3199);
    try s.put(bindings, "GraphemeCount", try s.text("binding2845"));
    try s.put(bindings, "IsMinLength", try s.text("binding2848"));
    try s.put(bindings, "IsMaxLength", try s.text("binding2849"));
}
fn body2850(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2854 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2851", v2854);
    const v2855 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2852", v2855);
    const v2856 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2853", v2856);
    const v2857 = try o.lookup(&s, frame, "binding2851");
    const v2858 = try o.lookup(&s, frame, "binding2852");
    const v2859 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 7, v2857, v2858)));
    const v2861 = logical2860: {
        if (!s.truthy(v2859)) break :logical2860 v2859;
        const v2862 = try o.lookup(&s, frame, "binding2851");
        const v2863 = try o.lookup(&s, frame, "binding2853");
        const v2864 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 5, v2862, v2863)));
        break :logical2860 v2864;
    };
    return c.JS_DupValue(e.context, v2861);
}
fn body2866(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2868 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2867", v2868);
    const v2869 = try o.lookup(&s, frame, "binding2867");
    return c.JS_DupValue(e.context, o.boolean(&s, s.equal(v2869, c.JS_NewFloat64(e.context, 8205))));
}
fn body2871(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2873 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2872", v2873);
    const v2874 = try o.lookup(&s, frame, "binding2835");
    const v2875 = try o.lookup(&s, frame, "binding2872");
    const v2876 = try o.call(&s, @src(), v2874, c.pi_js_undefined(), &.{ v2875, c.JS_NewFloat64(e.context, 55296), c.JS_NewFloat64(e.context, 56319) });
    return c.JS_DupValue(e.context, v2876);
}
fn body2878(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2880 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2879", v2880);
    const v2881 = try o.lookup(&s, frame, "binding2835");
    const v2882 = try o.lookup(&s, frame, "binding2879");
    const v2883 = try o.call(&s, @src(), v2881, c.pi_js_undefined(), &.{ v2882, c.JS_NewFloat64(e.context, 127462), c.JS_NewFloat64(e.context, 127487) });
    return c.JS_DupValue(e.context, v2883);
}
fn body2885(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2887 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2886", v2887);
    const v2888 = try o.lookup(&s, frame, "binding2835");
    const v2889 = try o.lookup(&s, frame, "binding2886");
    const v2890 = try o.call(&s, @src(), v2888, c.pi_js_undefined(), &.{ v2889, c.JS_NewFloat64(e.context, 65024), c.JS_NewFloat64(e.context, 65039) });
    return c.JS_DupValue(e.context, v2890);
}
fn body2892(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2894 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2893", v2894);
    const v2895 = try o.lookup(&s, frame, "binding2835");
    const v2896 = try o.lookup(&s, frame, "binding2893");
    const v2897 = try o.call(&s, @src(), v2895, c.pi_js_undefined(), &.{ v2896, c.JS_NewFloat64(e.context, 768), c.JS_NewFloat64(e.context, 879) });
    const v2899 = logical2898: {
        if (s.truthy(v2897)) break :logical2898 v2897;
        const v2900 = try o.lookup(&s, frame, "binding2835");
        const v2901 = try o.lookup(&s, frame, "binding2893");
        const v2902 = try o.call(&s, @src(), v2900, c.pi_js_undefined(), &.{ v2901, c.JS_NewFloat64(e.context, 6832), c.JS_NewFloat64(e.context, 6911) });
        break :logical2898 v2902;
    };
    const v2904 = logical2903: {
        if (s.truthy(v2899)) break :logical2903 v2899;
        const v2905 = try o.lookup(&s, frame, "binding2835");
        const v2906 = try o.lookup(&s, frame, "binding2893");
        const v2907 = try o.call(&s, @src(), v2905, c.pi_js_undefined(), &.{ v2906, c.JS_NewFloat64(e.context, 7616), c.JS_NewFloat64(e.context, 7679) });
        break :logical2903 v2907;
    };
    const v2909 = logical2908: {
        if (s.truthy(v2904)) break :logical2908 v2904;
        const v2910 = try o.lookup(&s, frame, "binding2835");
        const v2911 = try o.lookup(&s, frame, "binding2893");
        const v2912 = try o.call(&s, @src(), v2910, c.pi_js_undefined(), &.{ v2911, c.JS_NewFloat64(e.context, 65056), c.JS_NewFloat64(e.context, 65071) });
        break :logical2908 v2912;
    };
    return c.JS_DupValue(e.context, v2909);
}
fn body2914(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2916 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2915", v2916);
    const v2917 = try o.lookup(&s, frame, "binding2915");
    const v2918 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 6, v2917, c.JS_NewFloat64(e.context, 65535))));
    const v2920 = conditional2919: {
        if (s.truthy(v2918)) {
            break :conditional2919 c.JS_NewFloat64(e.context, 2);
        } else {
            break :conditional2919 c.JS_NewFloat64(e.context, 1);
        }
    };
    return c.JS_DupValue(e.context, v2920);
}
fn body2922(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2925 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2923", v2925);
    const v2926 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2924", v2926);
    loop2927: while (true) {
        const v2928 = try o.lookup(&s, frame, "binding2924");
        const v2929 = try o.lookup(&s, frame, "binding2923");
        const v2930 = try s.text("length");
        const v2931 = try s.own(try js.getKey(e, v2929, v2930));
        const v2932 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 4, v2928, v2931)));
        if (!s.truthy(v2932)) break :loop2927;
        const v2934 = try o.lookup(&s, frame, "binding2923");
        const v2935 = try s.text("codePointAt");
        const v2936 = try s.own(try js.getKey(e, v2934, v2935));
        const v2937 = try o.lookup(&s, frame, "binding2924");
        const v2938 = try o.call(&s, @src(), v2936, v2934, &.{v2937});
        try o.assign(&s, frame, "binding2933", v2938);
        const v2939 = try o.lookup(&s, frame, "binding2840");
        const v2940 = try o.lookup(&s, frame, "binding2933");
        const v2941 = try o.call(&s, @src(), v2939, c.pi_js_undefined(), &.{v2940});
        const v2943 = logical2942: {
            if (s.truthy(v2941)) break :logical2942 v2941;
            const v2944 = try o.lookup(&s, frame, "binding2839");
            const v2945 = try o.lookup(&s, frame, "binding2933");
            const v2946 = try o.call(&s, @src(), v2944, c.pi_js_undefined(), &.{v2945});
            break :logical2942 v2946;
        };
        if (s.truthy(v2943)) {
            const v2947 = try o.lookup(&s, frame, "binding2924");
            const v2948 = try o.lookup(&s, frame, "binding2841");
            const v2949 = try o.lookup(&s, frame, "binding2933");
            const v2950 = try o.call(&s, @src(), v2948, c.pi_js_undefined(), &.{v2949});
            const v2951 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 0, v2947, v2950)));
            try o.assign(&s, frame, "binding2924", v2951);
        } else {
            break :loop2927;
        }
    }
    const v2952 = try o.lookup(&s, frame, "binding2924");
    return c.JS_DupValue(e.context, v2952);
}
fn body2954(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2959 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2955", v2959);
    const v2960 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2956", v2960);
    const v2963 = try o.lookup(&s, frame, "binding2955");
    const v2964 = try s.text("codePointAt");
    const v2965 = try s.own(try js.getKey(e, v2963, v2964));
    const v2966 = try o.lookup(&s, frame, "binding2956");
    const v2967 = try o.call(&s, @src(), v2965, v2963, &.{v2966});
    try o.assign(&s, frame, "binding2961", v2967);
    const v2968 = try o.lookup(&s, frame, "binding2956");
    const v2969 = try o.lookup(&s, frame, "binding2841");
    const v2970 = try o.lookup(&s, frame, "binding2961");
    const v2971 = try o.call(&s, @src(), v2969, c.pi_js_undefined(), &.{v2970});
    const v2972 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 0, v2968, v2971)));
    try o.assign(&s, frame, "binding2962", v2972);
    const v2973 = try o.lookup(&s, frame, "binding2842");
    const v2974 = try o.lookup(&s, frame, "binding2955");
    const v2975 = try o.lookup(&s, frame, "binding2962");
    const v2976 = try o.call(&s, @src(), v2973, c.pi_js_undefined(), &.{ v2974, v2975 });
    try o.assign(&s, frame, "binding2962", v2976);
    loop2977: while (true) {
        const v2978 = try o.lookup(&s, frame, "binding2962");
        const v2979 = try o.lookup(&s, frame, "binding2955");
        const v2980 = try s.text("length");
        const v2981 = try s.own(try js.getKey(e, v2979, v2980));
        const v2982 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 1, v2981, c.JS_NewFloat64(e.context, 1))));
        const v2983 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 4, v2978, v2982)));
        const v2985 = logical2984: {
            if (!s.truthy(v2983)) break :logical2984 v2983;
            const v2986 = try o.lookup(&s, frame, "binding2836");
            const v2987 = try o.lookup(&s, frame, "binding2955");
            const v2988 = try s.text("codePointAt");
            const v2989 = try s.own(try js.getKey(e, v2987, v2988));
            const v2990 = try o.lookup(&s, frame, "binding2962");
            const v2991 = try o.call(&s, @src(), v2989, v2987, &.{v2990});
            const v2992 = try o.call(&s, @src(), v2986, c.pi_js_undefined(), &.{v2991});
            break :logical2984 v2992;
        };
        if (!s.truthy(v2985)) break :loop2977;
        const v2994 = try o.lookup(&s, frame, "binding2955");
        const v2995 = try s.text("codePointAt");
        const v2996 = try s.own(try js.getKey(e, v2994, v2995));
        const v2997 = try o.lookup(&s, frame, "binding2962");
        const v2998 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 0, v2997, c.JS_NewFloat64(e.context, 1))));
        const v2999 = try o.call(&s, @src(), v2996, v2994, &.{v2998});
        try o.assign(&s, frame, "binding2993", v2999);
        const v3000 = try o.lookup(&s, frame, "binding2962");
        const v3001 = try o.lookup(&s, frame, "binding2841");
        const v3002 = try o.lookup(&s, frame, "binding2993");
        const v3003 = try o.call(&s, @src(), v3001, c.pi_js_undefined(), &.{v3002});
        const v3004 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 0, c.JS_NewFloat64(e.context, 1), v3003)));
        const v3005 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 0, v3000, v3004)));
        try o.assign(&s, frame, "binding2962", v3005);
        const v3006 = try o.lookup(&s, frame, "binding2842");
        const v3007 = try o.lookup(&s, frame, "binding2955");
        const v3008 = try o.lookup(&s, frame, "binding2962");
        const v3009 = try o.call(&s, @src(), v3006, c.pi_js_undefined(), &.{ v3007, v3008 });
        try o.assign(&s, frame, "binding2962", v3009);
    }
    const v3010 = try o.lookup(&s, frame, "binding2838");
    const v3011 = try o.lookup(&s, frame, "binding2961");
    const v3012 = try o.call(&s, @src(), v3010, c.pi_js_undefined(), &.{v3011});
    const v3014 = logical3013: {
        if (!s.truthy(v3012)) break :logical3013 v3012;
        const v3015 = try o.lookup(&s, frame, "binding2962");
        const v3016 = try o.lookup(&s, frame, "binding2955");
        const v3017 = try s.text("length");
        const v3018 = try s.own(try js.getKey(e, v3016, v3017));
        const v3019 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 4, v3015, v3018)));
        break :logical3013 v3019;
    };
    const v3021 = logical3020: {
        if (!s.truthy(v3014)) break :logical3020 v3014;
        const v3022 = try o.lookup(&s, frame, "binding2838");
        const v3023 = try o.lookup(&s, frame, "binding2955");
        const v3024 = try s.text("codePointAt");
        const v3025 = try s.own(try js.getKey(e, v3023, v3024));
        const v3026 = try o.lookup(&s, frame, "binding2962");
        const v3027 = try o.call(&s, @src(), v3025, v3023, &.{v3026});
        const v3028 = try o.call(&s, @src(), v3022, c.pi_js_undefined(), &.{v3027});
        break :logical3020 v3028;
    };
    if (s.truthy(v3021)) {
        const v3029 = try o.lookup(&s, frame, "binding2962");
        const v3030 = try o.lookup(&s, frame, "binding2841");
        const v3031 = try o.lookup(&s, frame, "binding2955");
        const v3032 = try s.text("codePointAt");
        const v3033 = try s.own(try js.getKey(e, v3031, v3032));
        const v3034 = try o.lookup(&s, frame, "binding2962");
        const v3035 = try o.call(&s, @src(), v3033, v3031, &.{v3034});
        const v3036 = try o.call(&s, @src(), v3030, c.pi_js_undefined(), &.{v3035});
        const v3037 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 0, v3029, v3036)));
        try o.assign(&s, frame, "binding2962", v3037);
    }
    const v3038 = try o.lookup(&s, frame, "binding2962");
    return c.JS_DupValue(e.context, v3038);
}
fn body3040(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3042 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3041", v3042);
    const v3043 = try o.lookup(&s, frame, "binding3041");
    const v3044 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 7, v3043, c.JS_NewFloat64(e.context, 768))));
    const v3046 = logical3045: {
        if (!s.truthy(v3044)) break :logical3045 v3044;
        const v3047 = try o.lookup(&s, frame, "binding2837");
        const v3048 = try o.lookup(&s, frame, "binding3041");
        const v3049 = try o.call(&s, @src(), v3047, c.pi_js_undefined(), &.{v3048});
        const v3051 = logical3050: {
            if (s.truthy(v3049)) break :logical3050 v3049;
            const v3052 = try o.lookup(&s, frame, "binding2840");
            const v3053 = try o.lookup(&s, frame, "binding3041");
            const v3054 = try o.call(&s, @src(), v3052, c.pi_js_undefined(), &.{v3053});
            break :logical3050 v3054;
        };
        const v3056 = logical3055: {
            if (s.truthy(v3051)) break :logical3055 v3051;
            const v3057 = try o.lookup(&s, frame, "binding2839");
            const v3058 = try o.lookup(&s, frame, "binding3041");
            const v3059 = try o.call(&s, @src(), v3057, c.pi_js_undefined(), &.{v3058});
            break :logical3055 v3059;
        };
        const v3061 = logical3060: {
            if (s.truthy(v3056)) break :logical3060 v3056;
            const v3062 = try o.lookup(&s, frame, "binding2836");
            const v3063 = try o.lookup(&s, frame, "binding3041");
            const v3064 = try o.call(&s, @src(), v3062, c.pi_js_undefined(), &.{v3063});
            break :logical3060 v3064;
        };
        break :logical3045 v3061;
    };
    return c.JS_DupValue(e.context, v3046);
}
fn body3066(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3070 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3067", v3070);
    try o.assign(&s, frame, "binding3071", c.JS_NewFloat64(e.context, 0));
    try o.assign(&s, frame, "binding3072", c.JS_NewFloat64(e.context, 0));
    loop3073: while (true) {
        const v3074 = try o.lookup(&s, frame, "binding3072");
        const v3075 = try o.lookup(&s, frame, "binding3067");
        const v3076 = try s.text("length");
        const v3077 = try s.own(try js.getKey(e, v3075, v3076));
        const v3078 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 4, v3074, v3077)));
        if (!s.truthy(v3078)) break :loop3073;
        const v3079 = try o.lookup(&s, frame, "binding2843");
        const v3080 = try o.lookup(&s, frame, "binding3067");
        const v3081 = try o.lookup(&s, frame, "binding3072");
        const v3082 = try o.call(&s, @src(), v3079, c.pi_js_undefined(), &.{ v3080, v3081 });
        try o.assign(&s, frame, "binding3072", v3082);
        const v3083 = try o.lookup(&s, frame, "binding3071");
        const v3084 = try s.own(try e.checked(c.JS_PiIncrement(e.context, v3083)));
        try o.assign(&s, frame, "binding3071", v3084);
    }
    const v3085 = try o.lookup(&s, frame, "binding3071");
    return c.JS_DupValue(e.context, v3085);
}
fn body3087(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3092 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3088", v3092);
    const v3093 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3089", v3093);
    try o.assign(&s, frame, "binding3094", c.JS_NewFloat64(e.context, 0));
    try o.assign(&s, frame, "binding3095", c.JS_NewFloat64(e.context, 0));
    loop3096: while (true) {
        const v3097 = try o.lookup(&s, frame, "binding3095");
        const v3098 = try o.lookup(&s, frame, "binding3088");
        const v3099 = try s.text("length");
        const v3100 = try s.own(try js.getKey(e, v3098, v3099));
        const v3101 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 4, v3097, v3100)));
        if (!s.truthy(v3101)) break :loop3096;
        const v3102 = try o.lookup(&s, frame, "binding2843");
        const v3103 = try o.lookup(&s, frame, "binding3088");
        const v3104 = try o.lookup(&s, frame, "binding3095");
        const v3105 = try o.call(&s, @src(), v3102, c.pi_js_undefined(), &.{ v3103, v3104 });
        try o.assign(&s, frame, "binding3095", v3105);
        const v3106 = try o.lookup(&s, frame, "binding3094");
        const v3107 = try s.own(try e.checked(c.JS_PiIncrement(e.context, v3106)));
        try o.assign(&s, frame, "binding3094", v3107);
        const v3108 = try o.lookup(&s, frame, "binding3089");
        const v3109 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 7, v3107, v3108)));
        if (s.truthy(v3109)) {
            return c.JS_DupValue(e.context, o.boolean(&s, true));
        }
    }
    return c.JS_DupValue(e.context, o.boolean(&s, false));
}
fn body3111(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3116 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3112", v3116);
    const v3117 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3113", v3117);
    try o.assign(&s, frame, "binding3118", c.JS_NewFloat64(e.context, 0));
    try o.assign(&s, frame, "binding3119", c.JS_NewFloat64(e.context, 0));
    loop3120: while (true) {
        const v3121 = try o.lookup(&s, frame, "binding3119");
        const v3122 = try o.lookup(&s, frame, "binding3112");
        const v3123 = try s.text("length");
        const v3124 = try s.own(try js.getKey(e, v3122, v3123));
        const v3125 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 4, v3121, v3124)));
        if (!s.truthy(v3125)) break :loop3120;
        const v3126 = try o.lookup(&s, frame, "binding2843");
        const v3127 = try o.lookup(&s, frame, "binding3112");
        const v3128 = try o.lookup(&s, frame, "binding3119");
        const v3129 = try o.call(&s, @src(), v3126, c.pi_js_undefined(), &.{ v3127, v3128 });
        try o.assign(&s, frame, "binding3119", v3129);
        const v3130 = try o.lookup(&s, frame, "binding3118");
        const v3131 = try s.own(try e.checked(c.JS_PiIncrement(e.context, v3130)));
        try o.assign(&s, frame, "binding3118", v3131);
        const v3132 = try o.lookup(&s, frame, "binding3113");
        const v3133 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 6, v3131, v3132)));
        if (s.truthy(v3133)) {
            return c.JS_DupValue(e.context, o.boolean(&s, false));
        }
    }
    return c.JS_DupValue(e.context, o.boolean(&s, true));
}
fn body3135(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3139 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3136", v3139);
    const v3140 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3137", v3140);
    const v3142 = try o.lookup(&s, frame, "binding3137");
    if (s.truthy(o.boolean(&s, s.equal(v3142, c.JS_NewFloat64(e.context, 0))))) {
        return c.JS_DupValue(e.context, o.boolean(&s, true));
    }
    const v3143 = try o.lookup(&s, frame, "binding3136");
    const v3144 = try s.text("length");
    const v3145 = try s.own(try js.getKey(e, v3143, v3144));
    const v3146 = try o.lookup(&s, frame, "binding3137");
    const v3147 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 4, v3145, v3146)));
    if (s.truthy(v3147)) {
        return c.JS_DupValue(e.context, o.boolean(&s, false));
    }
    try o.assign(&s, frame, "binding3141", c.JS_NewFloat64(e.context, 0));
    loop3148: while (true) {
        if (!s.truthy(o.boolean(&s, true))) break :loop3148;
        const v3149 = try o.lookup(&s, frame, "binding2844");
        const v3150 = try o.lookup(&s, frame, "binding3136");
        const v3151 = try s.text("charCodeAt");
        const v3152 = try s.own(try js.getKey(e, v3150, v3151));
        const v3153 = try o.lookup(&s, frame, "binding3141");
        const v3154 = try o.call(&s, @src(), v3152, v3150, &.{v3153});
        const v3155 = try o.call(&s, @src(), v3149, c.pi_js_undefined(), &.{v3154});
        if (s.truthy(v3155)) {
            const v3156 = try o.lookup(&s, frame, "binding2846");
            const v3157 = try o.lookup(&s, frame, "binding3136");
            const v3158 = try o.lookup(&s, frame, "binding3137");
            const v3159 = try o.call(&s, @src(), v3156, c.pi_js_undefined(), &.{ v3157, v3158 });
            return c.JS_DupValue(e.context, v3159);
        }
        const v3160 = try o.lookup(&s, frame, "binding3141");
        const v3161 = try s.own(try e.checked(c.JS_PiIncrement(e.context, v3160)));
        try o.assign(&s, frame, "binding3141", v3161);
        const v3162 = try o.lookup(&s, frame, "binding3137");
        const v3163 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 7, v3161, v3162)));
        if (s.truthy(v3163)) {
            return c.JS_DupValue(e.context, o.boolean(&s, true));
        }
    }
    return c.pi_js_undefined();
}
fn body3165(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3169 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3166", v3169);
    const v3170 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3167", v3170);
    const v3172 = try o.lookup(&s, frame, "binding3166");
    const v3173 = try s.text("length");
    const v3174 = try s.own(try js.getKey(e, v3172, v3173));
    const v3175 = try o.lookup(&s, frame, "binding3167");
    const v3176 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 5, v3174, v3175)));
    if (s.truthy(v3176)) {
        return c.JS_DupValue(e.context, o.boolean(&s, true));
    }
    try o.assign(&s, frame, "binding3171", c.JS_NewFloat64(e.context, 0));
    loop3177: while (true) {
        if (!s.truthy(o.boolean(&s, true))) break :loop3177;
        const v3178 = try o.lookup(&s, frame, "binding2844");
        const v3179 = try o.lookup(&s, frame, "binding3166");
        const v3180 = try s.text("charCodeAt");
        const v3181 = try s.own(try js.getKey(e, v3179, v3180));
        const v3182 = try o.lookup(&s, frame, "binding3171");
        const v3183 = try o.call(&s, @src(), v3181, v3179, &.{v3182});
        const v3184 = try o.call(&s, @src(), v3178, c.pi_js_undefined(), &.{v3183});
        if (s.truthy(v3184)) {
            const v3185 = try o.lookup(&s, frame, "binding2847");
            const v3186 = try o.lookup(&s, frame, "binding3166");
            const v3187 = try o.lookup(&s, frame, "binding3167");
            const v3188 = try o.call(&s, @src(), v3185, c.pi_js_undefined(), &.{ v3186, v3187 });
            return c.JS_DupValue(e.context, v3188);
        }
        const v3189 = try o.lookup(&s, frame, "binding3171");
        const v3190 = try s.own(try e.checked(c.JS_PiIncrement(e.context, v3189)));
        try o.assign(&s, frame, "binding3171", v3190);
        const v3191 = try o.lookup(&s, frame, "binding3167");
        const v3192 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 6, v3190, v3191)));
        if (s.truthy(v3192)) {
            return c.JS_DupValue(e.context, o.boolean(&s, false));
        }
    }
    return c.pi_js_undefined();
}
