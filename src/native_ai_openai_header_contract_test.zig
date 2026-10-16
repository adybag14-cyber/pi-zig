const std = @import("std");
const builtin = @import("builtin");
const v = @import("extensions/native_ai_provider_values.zig");
const sdk_headers = @import("extensions/native_ai_openai_sdk_headers.zig");
const c = v.c;
pub fn expectedNativeIdentity(gpa: std.mem.Allocator) ![]u8 {
    // Expectations come from the pinned compiler and independently read C
    // version macros/runtime, never from the observed wire/header formatter.
    try std.testing.expectEqualStrings("0.16.0", builtin.zig_version_string);
    try std.testing.expectEqual(@as(c_int, 0), c.QJS_VERSION_MAJOR);
    try std.testing.expectEqual(@as(c_int, 17), c.QJS_VERSION_MINOR);
    try std.testing.expectEqual(@as(c_int, 0), c.QJS_VERSION_PATCH);
    try std.testing.expectEqualStrings("0.17.0", std.mem.span(c.JS_GetVersion()));
    return std.fmt.allocPrint(gpa, "pi-zig/Zig-0.16.0 QuickJS-0.17.0 ({s}; {s})", .{ @tagName(builtin.os.tag), @tagName(builtin.cpu.arch) });
}
fn build(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    var sources: std.ArrayList(c.JSValue) = .empty;
    defer sources.deinit(engine.gpa);
    var iterator = try v.iterator(&scope, args[0]);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |source| try sources.append(engine.gpa, try scope.own(source));
    const built = try sdk_headers.build(engine, sources.items);
    defer engine.freeValue(built.values);
    defer engine.freeValue(built.nulls);
    const result = try scope.object();
    try scope.put(result, "values", built.values);
    try scope.put(result, "nulls", built.nulls);
    return c.JS_DupValue(engine.context, result);
}
test "native OpenAI header contract identity comes from pinned Zig target and actual QuickJS runtime" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    const expected = try expectedNativeIdentity(engine.gpa);
    defer engine.gpa.free(expected);
    const actual = try scope.own(try @import("extensions/native_ai_user_agent.zig").runtime(&scope));
    const bytes = try engine.toString(actual);
    defer engine.gpa.free(bytes);
    try std.testing.expectEqualStrings(expected, bytes);
    const spoof = try engine.evalModule("globalThis.process={version:'v24.14.0',versions:{node:'24.14.0'},platform:'win32',arch:'x64'};export const done=true;", "native-header-runtime-identity-spoof.mjs");
    engine.freeValue(spoof);
    const after = try scope.own(try @import("extensions/native_ai_user_agent.zig").runtime(&scope));
    const after_bytes = try engine.toString(after);
    defer engine.gpa.free(after_bytes);
    try std.testing.expectEqualStrings(expected, after_bytes);
}
test "native OpenAI header contract SDK merge preserves undefined null append body precedence and raw getters" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("extensions/native_headers.zig").install(engine);
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "nativeSdkHeaderBuild", try scope.own(try @import("extensions/native_node_function.zig").create(engine, "buildHeaders", 1, build, &.{})));
    const module = try engine.evalModule(@embedFile("extensions/fixtures/ai-openai-sdk-headers-primary.input.txt") ++
        \\const rows=observeHeaderCases(nativeSdkHeaderBuild),cases=Object.fromEntries(rows.map(row=>[row.name,row]));
        \\if(rows.length!==18)throw Error('All original authored SDK header controls required');
        \\const header=(name,key)=>cases[name].headers.find(([k])=>k===key)?.[1];
        \\if(header('undefined preserves earlier default','accept')!=='application/json'||header('undefined preserves earlier default','authorization')!=='Bearer placeholder')throw Error('undefined erased previous header');
        \\if(cases['null removes earlier default'].headers.length||cases['null removes earlier default'].nulls.join(',')!=='accept,authorization')throw Error('null tombstones');
        \\if(header('case distinct object keys overwrite','x-test')!=='last'||header('tuple repeated name appends','x-test')!=='first, last'||header('record array undefined null and values','x-test')!=='last'||header('empty and undefined arrays preserve default','x-test')!=='base')throw Error('SDK record versus tuple append semantics');
        \\if(header('header value trims HTTP whitespace','x-test')!=='value'||header('JSON body header follows defaults','content-type')!=='application/json'||header('request header follows JSON body','content-type')!=='request-level')throw Error('normalization and body order');
        \\if(header('retry and timeout caller precedence','x-stainless-retry-count')!=='caller'||header('retry and timeout caller precedence','x-stainless-timeout')!==undefined||!cases['retry and timeout caller precedence'].nulls.includes('x-stainless-timeout'))throw Error('caller protocol precedence');
        \\if(header('client default spread preserves case key order','user-agent')!=='model-lower')throw Error('Client Object.assign casing order');
        \\if(header('explicit identity headers stay caller owned','user-agent')!=='caller-owned'||header('explicit identity headers stay caller owned','x-stainless-runtime')!=='caller-runtime'||cases['explicit identity headers stay caller owned'].headers.length!==7)throw Error('Caller identity header ownership');
        \\if(header('real Headers source appends normalized entries','x-test')!=='first, last')throw Error('real Headers input');
        \\for(const name of ['invalid header name','invalid header value','tuple nonstring header name'])if(cases[name].error?.name!=='TypeError')throw Error(name);
        \\if(!cases['raw record getter identity'].same||cases['raw record getter identity'].trace.join(',')!=='value getter'||header('live value coercion','x-test')!=='first'||cases['live value coercion'].trace.join(',')!=='toString')throw Error('raw getter and value coercion');
        \\export const observations=rows;
    , "native-openai-sdk-header-primary-controls.mjs");
    defer engine.freeValue(module);
}
test "native OpenAI header contract allocation failure never becomes a successful partial header merge" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try v.em.Engine.init(gpa, .{});
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            exercise(engine) catch |err| return engine.nativeAllocationError(err, generation);
        }
        fn exercise(engine: *v.em.Engine) !void {
            try @import("extensions/native_headers.zig").install(engine);
            var scope: v.Scope = .{ .engine = engine };
            defer scope.deinit();
            const defaults = try scope.object();
            try scope.put(defaults, "Authorization", try scope.text("Bearer placeholder"));
            try scope.put(defaults, "X-Test", try scope.text("base"));
            const changed = try scope.object();
            const values = try scope.array();
            try scope.index(values, 0, c.pi_js_undefined());
            try scope.index(values, 1, try scope.text("first"));
            try scope.index(values, 2, c.pi_js_null());
            try scope.index(values, 3, try scope.text("last"));
            try scope.put(changed, "x-test", values);
            try scope.put(changed, "authorization", c.pi_js_null());
            const built = try sdk_headers.build(engine, &.{ defaults, changed });
            defer engine.freeValue(built.values);
            defer engine.freeValue(built.nulls);
            const result = try scope.invoke(built.values, "get", &.{try scope.text("x-test")});
            if (!try v.eq(&scope, result, "last") or !scope.truthy(try scope.invoke(built.nulls, "has", &.{try scope.text("authorization")}))) return error.PartialHeaderMergeEscapedAllocationFailure;
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
