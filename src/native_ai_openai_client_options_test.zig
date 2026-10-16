const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const client_options = @import("extensions/native_ai_openai_client_options.zig");
const sdk_headers = @import("extensions/native_ai_openai_sdk_headers.zig");
const c = v.c;
fn capture(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    return client_options.capture(engine, .{ .api_key = try scope.get(args[0], "apiKey"), .base_url = try scope.get(args[0], "baseURL"), .fetch = try scope.get(args[0], "fetch"), .default_headers = try scope.get(args[0], "defaultHeaders") });
}
fn merge(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
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
test "native OpenAI constructor options owned env defaults nullable timing raw getters and provider precedence" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("extensions/native_headers.zig").install(engine);
    try client_options.initialize(engine);
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "nativeClientCapture", try scope.own(try @import("extensions/native_node_function.zig").create(engine, "captureClientOptions", 1, capture, &.{})));
    try scope.put(global, "nativeClientHeaderMerge", try scope.own(try @import("extensions/native_node_function.zig").create(engine, "buildHeaders", 1, merge, &.{})));
    const result = try engine.evalModule(@embedFile("extensions/fixtures/ai-openai-client-options-primary.input.txt") ++
        \\const rows=observeClientOptionCases(nativeClientCapture,nativeClientHeaderMerge),cases=Object.fromEntries(rows.map(row=>[row.name,row]));if(rows.length!==32)throw Error('All32 authored constructor controls required');
        \\const header=(name,key)=>cases[name].headers.find(([k])=>k===key)?.[1];
        \\const base=cases['owned dummy env defaults'];if(base.error||base.baseURL!=='http://127.0.0.1:1/fixture-provided'||base.apiKey!=='fixture-provided-key'||base.adminAPIKey!=='fixture-admin-key'||base.organization!=='fixture-org'||base.project!=='fixture-project'||base.webhookSecret!=='fixture-webhook'||!base.loggerIdentity||base.fetchIdentity!=='provided'||base.logLevel!=='warn')throw Error('Owned ctor defaults');
        \\if(cases['env whitespace trimmed'].organization!=='fixture-org'||cases['env whitespace trimmed'].project!=='fixture-project'||cases['undefined and null env'].organization!==null||cases['undefined and null env'].project!==null||cases['null process env'].adminAPIKey!==null)throw Error('Optional env trimming');
        \\if(cases['undefined baseURL uses env'].baseURL!=='http://127.0.0.1:1/fixture-env'||cases['null baseURL uses fixed default'].baseURL!=='https://api.openai.com/v1'||cases['undefined apiKey uses env'].apiKey!=='fixture-env-key'||cases['null apiKey keeps admin ctor credential'].apiKey!==null)throw Error('Undefined versus null defaults');
        \\const missing=cases['missing credentials before body defaults'];if(missing.payload||!missing.error?.message.startsWith('Missing credentials.')||missing.trace.includes('console')||missing.trace.some(row=>Array.isArray(row)&&row[1]==='OPENAI_CUSTOM_HEADERS'))throw Error('Constructor validation boundary');
        \\if(header('custom headers and provider precedence','x-case')!=='fixture-option'||header('undefined header preserves custom env','x-env')!=='fixture-env'||!cases['null header keeps nullable tombstone'].nulls.includes('authorization'))throw Error('Nullable constructor merge');
        \\if(header('default value coerces after payload boundary','x-value')!=='fixture-value-payload'||header('custom env coerces before payload boundary','x-value')!=='fixture-value-constructor')throw Error('onPayload coercion boundary');
        \\for(const name of ['malformed custom header name','malformed custom header value','raw organization env getter','raw project trim getter','raw custom env getter','raw header value before payload','global fetch raw getter before custom env'])if(cases[name].payload||!cases[name].error)throw Error(name);
        \\for(const name of ['raw organization env getter','raw project trim getter','raw custom env getter','raw header value before payload','raw header value after payload','global fetch raw getter before custom env'])if(!cases[name].error.rawSame)throw Error('Raw ctor reason '+name);
        \\if(!cases['raw header value after payload'].payload||cases['explicit fetch precedes default getter'].error||cases['null fetch reads global default twice'].fetchIdentity!=='global'||cases['null fetch reads global default twice'].trace.filter(row=>row==='global fetch').length!==2)throw Error('Fetch capture boundary');
        \\if(cases['invalid log level uses owned logger'].trace.filter(row=>Array.isArray(row)&&row[0]==='logger.warn').length!==1||cases['off log level captured'].logLevel!=='off'||cases['Deno env optional fallback'].organization!=='fixture-org'||cases['nonstring env fails trim'].payload||header('custom duplicate casing and proto assignment','x-env')!=='last'||cases['custom duplicate casing and proto assignment'].headers.some(([key])=>key==='__proto__'))throw Error('Ancillary ctor branches');
        \\const live=cases['live Array.isArray getter during custom merge'];if(live.error||live.trace.filter(row=>row==='Array.isArray getter').length<2||live.trace.filter(row=>row==='Array.isArray getter').length!==live.trace.filter(row=>row==='Array.isArray call').length)throw Error('Retained wrapper must reread live Array.isArray');
        \\if(cases['null process throws before ctor body'].payload||!cases['null process throws before ctor body'].error||cases['truthy nonstring key commits null after validation'].error||cases['truthy nonstring key commits null after validation'].apiKey!==null)throw Error('Raw credential validation and nullable process');
        \\export const observations=rows;
    , "native-openai-client-options-primary-controls.mjs");
    engine.freeValue(result);
}
