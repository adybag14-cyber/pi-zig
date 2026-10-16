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
    const namespace = try s.get(modules, "value/convert/try/try_number.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/convert/try/try_number.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/convert/try/try_number.mjs", bindings);
    const v27917 = try s.own(try ordinary.create(e, "FromBigInt", 1, body27897, &.{ graph, frame }));
    try o.assign(&s, frame, "binding27893", v27917);
    const v27926 = try s.own(try ordinary.create(e, "FromBoolean", 1, body27918, &.{ graph, frame }));
    try o.assign(&s, frame, "binding27894", v27926);
    const v27997 = try s.own(try ordinary.create(e, "FromString", 1, body27927, &.{ graph, frame }));
    try o.assign(&s, frame, "binding27895", v27997);
    const v28061 = try s.own(try ordinary.create(e, "TryNumber", 1, body27998, &.{ graph, frame }));
    try o.assign(&s, frame, "binding27896", v28061);
    const v28062 = try o.lookup(&s, frame, "binding27896");
    try s.put(namespace, "TryNumber", v28062);
    const v28063 = try s.global("BigInt");
    const v28064 = try s.global("Number");
    const v28065 = try s.text("MAX_SAFE_INTEGER");
    const v28066 = try s.own(try js.getKey(e, v28064, v28065));
    const v28067 = try s.call(v28063, c.pi_js_undefined(), &.{v28066});
    try o.assign(&s, frame, "binding27891", v28067);
    const v28068 = try s.global("BigInt");
    const v28069 = try s.global("Number");
    const v28070 = try s.text("MIN_SAFE_INTEGER");
    const v28071 = try s.own(try js.getKey(e, v28069, v28070));
    const v28072 = try s.call(v28068, c.pi_js_undefined(), &.{v28071});
    try o.assign(&s, frame, "binding27892", v28072);
    const v28073 = try o.lookup(&s, frame, "binding27896");
    try s.put(namespace, "TryNumber", v28073);
    try s.put(bindings, "TryNumber", try s.text("binding27896"));
}
fn body27897(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v27899 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27898", v27899);
    const v27900 = try o.lookup(&s, frame, "binding27898");
    const v27901 = try o.lookup(&s, frame, "binding27891");
    const v27902 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 5, v27900, v27901)));
    const v27904 = logical27903: {
        if (!s.truthy(v27902)) break :logical27903 v27902;
        const v27905 = try o.lookup(&s, frame, "binding27898");
        const v27906 = try o.lookup(&s, frame, "binding27892");
        const v27907 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 7, v27905, v27906)));
        break :logical27903 v27907;
    };
    const v27909 = conditional27908: {
        if (s.truthy(v27904)) {
            const v27910 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
            const v27911 = try s.global("Number");
            const v27912 = try o.lookup(&s, frame, "binding27898");
            const v27913 = try s.call(v27911, c.pi_js_undefined(), &.{v27912});
            const v27914 = try s.call(v27910, c.pi_js_undefined(), &.{v27913});
            break :conditional27908 v27914;
        } else {
            const v27915 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Fail");
            const v27916 = try s.call(v27915, c.pi_js_undefined(), &.{});
            break :conditional27908 v27916;
        }
    };
    return c.JS_DupValue(e.context, v27909);
}
fn body27918(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v27920 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27919", v27920);
    const v27921 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
    const v27922 = try o.lookup(&s, frame, "binding27919");
    const v27924 = conditional27923: {
        if (s.truthy(v27922)) {
            break :conditional27923 c.JS_NewFloat64(e.context, 1);
        } else {
            break :conditional27923 c.JS_NewFloat64(e.context, 0);
        }
    };
    const v27925 = try s.call(v27921, c.pi_js_undefined(), &.{v27924});
    return c.JS_DupValue(e.context, v27925);
}
fn body27927(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v27932 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27928", v27932);
    const v27936 = try o.lookup(&s, frame, "binding27928");
    const v27937 = try o.toNumber(&s, v27936);
    try o.assign(&s, frame, "binding27933", v27937);
    const v27938 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v27939 = try s.text("IsNumber");
    const v27940 = try s.own(try js.getKey(e, v27938, v27939));
    const v27941 = try o.lookup(&s, frame, "binding27933");
    const v27942 = try s.call(v27940, v27938, &.{v27941});
    if (s.truthy(v27942)) {
        const v27943 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
        const v27944 = try o.lookup(&s, frame, "binding27933");
        const v27945 = try s.call(v27943, c.pi_js_undefined(), &.{v27944});
        return c.JS_DupValue(e.context, v27945);
    }
    const v27946 = try o.lookup(&s, frame, "binding27928");
    const v27947 = try s.text("toLowerCase");
    const v27948 = try s.own(try js.getKey(e, v27946, v27947));
    const v27949 = try s.call(v27948, v27946, &.{});
    try o.assign(&s, frame, "binding27934", v27949);
    const v27950 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v27951 = try s.text("IsEqual");
    const v27952 = try s.own(try js.getKey(e, v27950, v27951));
    const v27953 = try o.lookup(&s, frame, "binding27934");
    const v27954 = try s.text("false");
    const v27955 = try s.call(v27952, v27950, &.{ v27953, v27954 });
    if (s.truthy(v27955)) {
        const v27956 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
        const v27957 = try s.call(v27956, c.pi_js_undefined(), &.{c.JS_NewFloat64(e.context, 0)});
        return c.JS_DupValue(e.context, v27957);
    }
    const v27958 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v27959 = try s.text("IsEqual");
    const v27960 = try s.own(try js.getKey(e, v27958, v27959));
    const v27961 = try o.lookup(&s, frame, "binding27934");
    const v27962 = try s.text("true");
    const v27963 = try s.call(v27960, v27958, &.{ v27961, v27962 });
    if (s.truthy(v27963)) {
        const v27964 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
        const v27965 = try s.call(v27964, c.pi_js_undefined(), &.{c.JS_NewFloat64(e.context, 1)});
        return c.JS_DupValue(e.context, v27965);
    }
    const v27966 = try o.importValue(&s, graph, "value/convert/try/try_bigint.mjs", "TryBigInt");
    const v27967 = try o.lookup(&s, frame, "binding27928");
    const v27968 = try s.call(v27966, c.pi_js_undefined(), &.{v27967});
    try o.assign(&s, frame, "binding27935", v27968);
    const v27969 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "IsOk");
    const v27970 = try o.lookup(&s, frame, "binding27935");
    const v27971 = try s.call(v27969, c.pi_js_undefined(), &.{v27970});
    if (s.truthy(v27971)) {
        const v27972 = try o.lookup(&s, frame, "binding27935");
        const v27973 = try s.text("value");
        const v27974 = try s.own(try js.getKey(e, v27972, v27973));
        const v27975 = try o.lookup(&s, frame, "binding27891");
        const v27976 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 5, v27974, v27975)));
        const v27978 = logical27977: {
            if (!s.truthy(v27976)) break :logical27977 v27976;
            const v27979 = try o.lookup(&s, frame, "binding27935");
            const v27980 = try s.text("value");
            const v27981 = try s.own(try js.getKey(e, v27979, v27980));
            const v27982 = try o.lookup(&s, frame, "binding27892");
            const v27983 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 7, v27981, v27982)));
            break :logical27977 v27983;
        };
        const v27985 = conditional27984: {
            if (s.truthy(v27978)) {
                const v27986 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
                const v27987 = try s.global("Number");
                const v27988 = try o.lookup(&s, frame, "binding27935");
                const v27989 = try s.text("value");
                const v27990 = try s.own(try js.getKey(e, v27988, v27989));
                const v27991 = try s.call(v27987, c.pi_js_undefined(), &.{v27990});
                const v27992 = try s.call(v27986, c.pi_js_undefined(), &.{v27991});
                break :conditional27984 v27992;
            } else {
                const v27993 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Fail");
                const v27994 = try s.call(v27993, c.pi_js_undefined(), &.{});
                break :conditional27984 v27994;
            }
        };
        return c.JS_DupValue(e.context, v27985);
    }
    const v27995 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Fail");
    const v27996 = try s.call(v27995, c.pi_js_undefined(), &.{});
    return c.JS_DupValue(e.context, v27996);
}
fn body27998(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v28000 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27999", v28000);
    const v28001 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v28002 = try s.text("IsBigInt");
    const v28003 = try s.own(try js.getKey(e, v28001, v28002));
    const v28004 = try o.lookup(&s, frame, "binding27999");
    const v28005 = try s.call(v28003, v28001, &.{v28004});
    const v28007 = conditional28006: {
        if (s.truthy(v28005)) {
            const v28008 = try o.lookup(&s, frame, "binding27893");
            const v28009 = try o.lookup(&s, frame, "binding27999");
            const v28010 = try s.call(v28008, c.pi_js_undefined(), &.{v28009});
            break :conditional28006 v28010;
        } else {
            const v28011 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
            const v28012 = try s.text("IsBoolean");
            const v28013 = try s.own(try js.getKey(e, v28011, v28012));
            const v28014 = try o.lookup(&s, frame, "binding27999");
            const v28015 = try s.call(v28013, v28011, &.{v28014});
            const v28017 = conditional28016: {
                if (s.truthy(v28015)) {
                    const v28018 = try o.lookup(&s, frame, "binding27894");
                    const v28019 = try o.lookup(&s, frame, "binding27999");
                    const v28020 = try s.call(v28018, c.pi_js_undefined(), &.{v28019});
                    break :conditional28016 v28020;
                } else {
                    const v28021 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                    const v28022 = try s.text("IsNumber");
                    const v28023 = try s.own(try js.getKey(e, v28021, v28022));
                    const v28024 = try o.lookup(&s, frame, "binding27999");
                    const v28025 = try s.call(v28023, v28021, &.{v28024});
                    const v28027 = conditional28026: {
                        if (s.truthy(v28025)) {
                            const v28028 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
                            const v28029 = try o.lookup(&s, frame, "binding27999");
                            const v28030 = try s.call(v28028, c.pi_js_undefined(), &.{v28029});
                            break :conditional28026 v28030;
                        } else {
                            const v28031 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                            const v28032 = try s.text("IsNull");
                            const v28033 = try s.own(try js.getKey(e, v28031, v28032));
                            const v28034 = try o.lookup(&s, frame, "binding27999");
                            const v28035 = try s.call(v28033, v28031, &.{v28034});
                            const v28037 = conditional28036: {
                                if (s.truthy(v28035)) {
                                    const v28038 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
                                    const v28039 = try s.call(v28038, c.pi_js_undefined(), &.{c.JS_NewFloat64(e.context, 0)});
                                    break :conditional28036 v28039;
                                } else {
                                    const v28040 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                    const v28041 = try s.text("IsString");
                                    const v28042 = try s.own(try js.getKey(e, v28040, v28041));
                                    const v28043 = try o.lookup(&s, frame, "binding27999");
                                    const v28044 = try s.call(v28042, v28040, &.{v28043});
                                    const v28046 = conditional28045: {
                                        if (s.truthy(v28044)) {
                                            const v28047 = try o.lookup(&s, frame, "binding27895");
                                            const v28048 = try o.lookup(&s, frame, "binding27999");
                                            const v28049 = try s.call(v28047, c.pi_js_undefined(), &.{v28048});
                                            break :conditional28045 v28049;
                                        } else {
                                            const v28050 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                            const v28051 = try s.text("IsUndefined");
                                            const v28052 = try s.own(try js.getKey(e, v28050, v28051));
                                            const v28053 = try o.lookup(&s, frame, "binding27999");
                                            const v28054 = try s.call(v28052, v28050, &.{v28053});
                                            const v28056 = conditional28055: {
                                                if (s.truthy(v28054)) {
                                                    const v28057 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
                                                    const v28058 = try s.call(v28057, c.pi_js_undefined(), &.{c.JS_NewFloat64(e.context, 0)});
                                                    break :conditional28055 v28058;
                                                } else {
                                                    const v28059 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Fail");
                                                    const v28060 = try s.call(v28059, c.pi_js_undefined(), &.{});
                                                    break :conditional28055 v28060;
                                                }
                                            };
                                            break :conditional28045 v28056;
                                        }
                                    };
                                    break :conditional28036 v28046;
                                }
                            };
                            break :conditional28026 v28037;
                        }
                    };
                    break :conditional28016 v28027;
                }
            };
            break :conditional28006 v28017;
        }
    };
    return c.JS_DupValue(e.context, v28007);
}
