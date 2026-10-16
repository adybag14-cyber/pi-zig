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
    const namespace = try s.get(modules, "value/codec/from_object.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/codec/from_object.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/codec/from_object.mjs", bindings);
    const v24923 = try s.own(try ordinary.create(e, "Decode", 4, body24855, &.{ graph, frame }));
    try o.assign(&s, frame, "binding24852", v24923);
    const v24995 = try s.own(try ordinary.create(e, "Encode", 4, body24924, &.{ graph, frame }));
    try o.assign(&s, frame, "binding24853", v24995);
    const v25025 = try s.own(try ordinary.create(e, "FromObject", 4, body24996, &.{ graph, frame }));
    try o.assign(&s, frame, "binding24854", v25025);
    const v25026 = try o.lookup(&s, frame, "binding24854");
    try s.put(namespace, "FromObject", v25026);
    const v25027 = try o.lookup(&s, frame, "binding24854");
    try s.put(namespace, "FromObject", v25027);
    try s.put(bindings, "FromObject", try s.text("binding24854"));
}
fn body24855(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v24860 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24856", v24860);
    const v24861 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24857", v24861);
    const v24862 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24858", v24862);
    const v24863 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24859", v24863);
    const v24864 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v24865 = try s.text("IsObjectNotArray");
    const v24866 = try s.own(try js.getKey(e, v24864, v24865));
    const v24867 = try o.lookup(&s, frame, "binding24859");
    const v24868 = try s.call(v24866, v24864, &.{v24867});
    if (s.truthy(o.boolean(&s, !s.truthy(v24868)))) {
        const v24869 = try o.lookup(&s, frame, "binding24859");
        return c.JS_DupValue(e.context, v24869);
    }
    const v24870 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v24871 = try s.text("Keys");
    const v24872 = try s.own(try js.getKey(e, v24870, v24871));
    const v24873 = try o.lookup(&s, frame, "binding24858");
    const v24874 = try s.text("properties");
    const v24875 = try s.own(try js.getKey(e, v24873, v24874));
    const v24876 = try s.call(v24872, v24870, &.{v24875});
    var iterator24877 = try o.iterator(e, v24876);
    defer iterator24877.deinit();
    errdefer iterator24877.closePreserving();
    loop24879: while (try iterator24877.next()) |next24878| {
        defer e.freeValue(next24878);
        const iteration24880 = try o.frame(&s, frame);
        try o.assign(&s, iteration24880, "binding24881", next24878);
        const v24882 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v24883 = try s.text("HasPropertyKey");
        const v24884 = try s.own(try js.getKey(e, v24882, v24883));
        const v24885 = try o.lookup(&s, iteration24880, "binding24859");
        const v24886 = try o.lookup(&s, iteration24880, "binding24881");
        const v24887 = try s.call(v24884, v24882, &.{ v24885, v24886 });
        const v24889 = logical24888: {
            if (s.truthy(o.boolean(&s, !s.truthy(v24887)))) break :logical24888 o.boolean(&s, !s.truthy(v24887));
            const v24890 = try o.importValue(&s, graph, "value/shared/optional_undefined.mjs", "IsOptionalUndefined");
            const v24891 = try o.lookup(&s, iteration24880, "binding24858");
            const v24892 = try s.text("properties");
            const v24893 = try s.own(try js.getKey(e, v24891, v24892));
            const v24894 = try o.lookup(&s, iteration24880, "binding24881");
            const v24895 = try o.propertyKey(&s, v24894);
            const v24896 = try s.own(try js.getKey(e, v24893, v24895));
            const v24897 = try o.lookup(&s, iteration24880, "binding24881");
            const v24898 = try o.lookup(&s, iteration24880, "binding24859");
            const v24899 = try s.call(v24890, c.pi_js_undefined(), &.{ v24896, v24897, v24898 });
            break :logical24888 v24899;
        };
        if (s.truthy(v24889)) {
            continue :loop24879;
        }
        const v24900 = try o.lookup(&s, iteration24880, "binding24859");
        const v24901 = try o.lookup(&s, iteration24880, "binding24881");
        const v24902 = try o.propertyKey(&s, v24901);
        const v24903 = try o.importValue(&s, graph, "value/codec/from_type.mjs", "FromType");
        const v24904 = try o.lookup(&s, iteration24880, "binding24856");
        const v24905 = try o.lookup(&s, iteration24880, "binding24857");
        const v24906 = try o.lookup(&s, iteration24880, "binding24858");
        const v24907 = try s.text("properties");
        const v24908 = try s.own(try js.getKey(e, v24906, v24907));
        const v24909 = try o.lookup(&s, iteration24880, "binding24881");
        const v24910 = try o.propertyKey(&s, v24909);
        const v24911 = try s.own(try js.getKey(e, v24908, v24910));
        const v24912 = try o.lookup(&s, iteration24880, "binding24859");
        const v24913 = try o.lookup(&s, iteration24880, "binding24881");
        const v24914 = try o.propertyKey(&s, v24913);
        const v24915 = try s.own(try js.getKey(e, v24912, v24914));
        const v24916 = try s.call(v24903, c.pi_js_undefined(), &.{ v24904, v24905, v24911, v24915 });
        try js.setKey(e, v24900, v24902, v24916);
    }
    try iterator24877.close();
    const v24917 = try o.importValue(&s, graph, "value/codec/callback.mjs", "Callback");
    const v24918 = try o.lookup(&s, frame, "binding24856");
    const v24919 = try o.lookup(&s, frame, "binding24857");
    const v24920 = try o.lookup(&s, frame, "binding24858");
    const v24921 = try o.lookup(&s, frame, "binding24859");
    const v24922 = try s.call(v24917, c.pi_js_undefined(), &.{ v24918, v24919, v24920, v24921 });
    return c.JS_DupValue(e.context, v24922);
}
fn body24924(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v24930 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24925", v24930);
    const v24931 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24926", v24931);
    const v24932 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24927", v24932);
    const v24933 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24928", v24933);
    const v24935 = try o.importValue(&s, graph, "value/codec/callback.mjs", "Callback");
    const v24936 = try o.lookup(&s, frame, "binding24925");
    const v24937 = try o.lookup(&s, frame, "binding24926");
    const v24938 = try o.lookup(&s, frame, "binding24927");
    const v24939 = try o.lookup(&s, frame, "binding24928");
    const v24940 = try s.call(v24935, c.pi_js_undefined(), &.{ v24936, v24937, v24938, v24939 });
    try o.assign(&s, frame, "binding24934", v24940);
    const v24941 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v24942 = try s.text("IsObjectNotArray");
    const v24943 = try s.own(try js.getKey(e, v24941, v24942));
    const v24944 = try o.lookup(&s, frame, "binding24934");
    const v24945 = try s.call(v24943, v24941, &.{v24944});
    if (s.truthy(o.boolean(&s, !s.truthy(v24945)))) {
        const v24946 = try o.lookup(&s, frame, "binding24934");
        return c.JS_DupValue(e.context, v24946);
    }
    const v24947 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v24948 = try s.text("Keys");
    const v24949 = try s.own(try js.getKey(e, v24947, v24948));
    const v24950 = try o.lookup(&s, frame, "binding24927");
    const v24951 = try s.text("properties");
    const v24952 = try s.own(try js.getKey(e, v24950, v24951));
    const v24953 = try s.call(v24949, v24947, &.{v24952});
    var iterator24954 = try o.iterator(e, v24953);
    defer iterator24954.deinit();
    errdefer iterator24954.closePreserving();
    loop24956: while (try iterator24954.next()) |next24955| {
        defer e.freeValue(next24955);
        const iteration24957 = try o.frame(&s, frame);
        try o.assign(&s, iteration24957, "binding24958", next24955);
        const v24959 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v24960 = try s.text("HasPropertyKey");
        const v24961 = try s.own(try js.getKey(e, v24959, v24960));
        const v24962 = try o.lookup(&s, iteration24957, "binding24934");
        const v24963 = try o.lookup(&s, iteration24957, "binding24958");
        const v24964 = try s.call(v24961, v24959, &.{ v24962, v24963 });
        const v24966 = logical24965: {
            if (s.truthy(o.boolean(&s, !s.truthy(v24964)))) break :logical24965 o.boolean(&s, !s.truthy(v24964));
            const v24967 = try o.importValue(&s, graph, "value/shared/optional_undefined.mjs", "IsOptionalUndefined");
            const v24968 = try o.lookup(&s, iteration24957, "binding24927");
            const v24969 = try s.text("properties");
            const v24970 = try s.own(try js.getKey(e, v24968, v24969));
            const v24971 = try o.lookup(&s, iteration24957, "binding24958");
            const v24972 = try o.propertyKey(&s, v24971);
            const v24973 = try s.own(try js.getKey(e, v24970, v24972));
            const v24974 = try o.lookup(&s, iteration24957, "binding24958");
            const v24975 = try o.lookup(&s, iteration24957, "binding24934");
            const v24976 = try s.call(v24967, c.pi_js_undefined(), &.{ v24973, v24974, v24975 });
            break :logical24965 v24976;
        };
        if (s.truthy(v24966)) {
            continue :loop24956;
        }
        const v24977 = try o.lookup(&s, iteration24957, "binding24934");
        const v24978 = try o.lookup(&s, iteration24957, "binding24958");
        const v24979 = try o.propertyKey(&s, v24978);
        const v24980 = try o.importValue(&s, graph, "value/codec/from_type.mjs", "FromType");
        const v24981 = try o.lookup(&s, iteration24957, "binding24925");
        const v24982 = try o.lookup(&s, iteration24957, "binding24926");
        const v24983 = try o.lookup(&s, iteration24957, "binding24927");
        const v24984 = try s.text("properties");
        const v24985 = try s.own(try js.getKey(e, v24983, v24984));
        const v24986 = try o.lookup(&s, iteration24957, "binding24958");
        const v24987 = try o.propertyKey(&s, v24986);
        const v24988 = try s.own(try js.getKey(e, v24985, v24987));
        const v24989 = try o.lookup(&s, iteration24957, "binding24934");
        const v24990 = try o.lookup(&s, iteration24957, "binding24958");
        const v24991 = try o.propertyKey(&s, v24990);
        const v24992 = try s.own(try js.getKey(e, v24989, v24991));
        const v24993 = try s.call(v24980, c.pi_js_undefined(), &.{ v24981, v24982, v24988, v24992 });
        try js.setKey(e, v24977, v24979, v24993);
    }
    try iterator24954.close();
    const v24994 = try o.lookup(&s, frame, "binding24934");
    return c.JS_DupValue(e.context, v24994);
}
fn body24996(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v25001 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24997", v25001);
    const v25002 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24998", v25002);
    const v25003 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24999", v25003);
    const v25004 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25000", v25004);
    const v25005 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v25006 = try s.text("IsEqual");
    const v25007 = try s.own(try js.getKey(e, v25005, v25006));
    const v25008 = try o.lookup(&s, frame, "binding24997");
    const v25009 = try s.text("Decode");
    const v25010 = try s.call(v25007, v25005, &.{ v25008, v25009 });
    const v25012 = conditional25011: {
        if (s.truthy(v25010)) {
            const v25013 = try o.lookup(&s, frame, "binding24852");
            const v25014 = try o.lookup(&s, frame, "binding24997");
            const v25015 = try o.lookup(&s, frame, "binding24998");
            const v25016 = try o.lookup(&s, frame, "binding24999");
            const v25017 = try o.lookup(&s, frame, "binding25000");
            const v25018 = try s.call(v25013, c.pi_js_undefined(), &.{ v25014, v25015, v25016, v25017 });
            break :conditional25011 v25018;
        } else {
            const v25019 = try o.lookup(&s, frame, "binding24853");
            const v25020 = try o.lookup(&s, frame, "binding24997");
            const v25021 = try o.lookup(&s, frame, "binding24998");
            const v25022 = try o.lookup(&s, frame, "binding24999");
            const v25023 = try o.lookup(&s, frame, "binding25000");
            const v25024 = try s.call(v25019, c.pi_js_undefined(), &.{ v25020, v25021, v25022, v25023 });
            break :conditional25011 v25024;
        }
    };
    return c.JS_DupValue(e.context, v25012);
}
