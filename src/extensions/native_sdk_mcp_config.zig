//! Genuine Source MCP configuration validation and namespace helpers. Records,
//! aliases, getters, URL/Number callbacks and iterator boundaries stay live.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
pub fn create(engine: *em.Engine) !c.JSValue {
    const module_name = "pi-native:mcp-config";
    if (engine.native_module_values.get(module_name)) |exports| return c.JS_DupValue(engine.context, exports);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const exposures = try scope.array();
    inline for (.{ "codemode", "deferred", "direct", "hidden" }, 0..) |name, index| try scope.index(exposures, index, try scope.text(name));
    const aliases = try scope.object();
    try scope.put(aliases, "codemode-deferred", try scope.text("codemode"));
    const hosts = try scope.array();
    inline for (.{ "localhost", "127.0.0.1", "[::1]" }, 0..) |name, index| try scope.index(hosts, index, try scope.text(name));
    const names = try regex(&scope, "^[A-Za-z0-9_-]+$", "");
    const exports = try scope.object();
    try scope.put(exports, "mcpNamespace", try scope.own(try @import("native_node_function.zig").create(engine, "mcpNamespace", 1, namespace, &.{})));
    try scope.put(exports, "isLoopbackRedirectUri", try scope.own(try @import("native_node_function.zig").create(engine, "isLoopbackRedirectUri", 1, redirect, &.{hosts})));
    try scope.put(exports, "validateMcpServerConfig", try scope.own(try @import("native_node_function.zig").create(engine, "validateMcpServerConfig", 2, validate, &.{ exposures, aliases, hosts, names })));
    try engine.registerValueModule(module_name, exports);
    return c.JS_DupValue(engine.context, exports);
}
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (args.len > index) args[index] else c.pi_js_undefined();
}
fn regex(scope: *Scope, pattern: []const u8, flags: []const u8) !c.JSValue {
    var args = [_]c.JSValue{ try scope.text(pattern), try scope.text(flags) };
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, args.len, &args)));
}
fn namespace(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const name = argument(args, 0);
    const replace = try scope.get(name, "replace");
    const value = try scope.call(replace, name, &.{ try regex(&scope, "-", "g"), try scope.text("_") });
    return c.JS_DupValue(engine.context, try scope.concat(try scope.text("mcp__"), try scope.stringify(value)));
}
fn array(scope: *Scope, value: c.JSValue) !bool {
    return scope.truthy(try scope.invoke(try scope.global("Array"), "isArray", &.{value}));
}
fn record(scope: *Scope, value: c.JSValue) !bool {
    return c.JS_IsObject(value) and !c.JS_IsFunction(scope.engine.context, value) and !try array(scope, value);
}
fn alias(scope: *Scope, aliases: c.JSValue, value: c.JSValue) !c.JSValue {
    if (!c.JS_IsString(value)) return value;
    const resolved_alias = try scope.own(try js.getKey(scope.engine, aliases, value));
    return if (temp.nullish(resolved_alias)) value else resolved_alias;
}
fn url(scope: *Scope, value: c.JSValue) !c.JSValue {
    const constructor = try scope.global("URL");
    var args = [_]c.JSValue{value};
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, args.len, &args)));
}
fn urlField(scope: *Scope, value: c.JSValue, key: [*:0]const u8) !c.JSValue {
    const constructor = try scope.global("URL");
    var args = [_]c.JSValue{try scope.get(value, key)};
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, args.len, &args)));
}
fn canParse(scope: *Scope, value: c.JSValue) !bool {
    return scope.truthy(try scope.invoke(try scope.global("URL"), "canParse", &.{value}));
}
fn canParseField(scope: *Scope, value: c.JSValue, key: [*:0]const u8) !bool {
    const constructor = try scope.global("URL");
    const parse = try scope.get(constructor, "canParse");
    return scope.truthy(try scope.call(parse, constructor, &.{try scope.get(value, key)}));
}
fn loopbackValue(scope: *Scope, hosts: c.JSValue, value: c.JSValue) !c.JSValue {
    if (!try canParse(scope, value)) return c.pi_js_bool(scope.engine.context, 0);
    const parsed = try url(scope, value);
    if (!scope.equal(try scope.get(parsed, "protocol"), try scope.text("http:"))) return c.pi_js_bool(scope.engine.context, 0);
    const includes = try scope.get(hosts, "includes");
    const matched = try scope.call(includes, hosts, &.{try scope.get(parsed, "hostname")});
    if (!scope.truthy(matched)) return matched;
    if (!scope.equal(try scope.get(parsed, "search"), try scope.text(""))) return c.pi_js_bool(scope.engine.context, 0);
    return c.pi_js_bool(scope.engine.context, @intFromBool(scope.equal(try scope.get(parsed, "hash"), try scope.text(""))));
}
fn loopback(scope: *Scope, hosts: c.JSValue, value: c.JSValue) !bool {
    return scope.truthy(try loopbackValue(scope, hosts, value));
}
fn redirect(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return c.JS_DupValue(engine.context, try loopbackValue(&scope, roots[0], argument(args, 0)));
}
const Callback = enum(c_int) { exposure_pair, exposure_text, string };
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return mapped(engine, @enumFromInt(magic), if (argc > 0) argv[0] else c.pi_js_undefined(), roots) catch |err| sdk.fail(engine, err);
}
fn mapped(engine: *em.Engine, kind: Callback, value: c.JSValue, roots: [*c]c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (kind == .string) return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsString(value)));
    if (kind == .exposure_text) return c.JS_DupValue(engine.context, try scope.concat(try scope.concat(try scope.text("\""), try scope.stringify(value)), try scope.text("\"")));
    const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
    const pair = try js.pair(engine, value, symbol);
    defer engine.freeValue(pair[0]);
    defer engine.freeValue(pair[1]);
    const result = try scope.array();
    try scope.index(result, 0, pair[0]);
    try scope.index(result, 1, try alias(&scope, roots[0], pair[1]));
    return c.JS_DupValue(engine.context, result);
}
fn collection(scope: *Scope, values: c.JSValue, name: [*:0]const u8, kind: Callback, roots: []c.JSValue) !c.JSValue {
    const method = try scope.get(values, name);
    const function = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, callback, "", 1, @intFromEnum(kind), @intCast(roots.len), roots.ptr)));
    return scope.call(method, values, &.{function});
}
fn aliasesResolved(scope: *Scope, aliases: c.JSValue, value: c.JSValue) !c.JSValue {
    const exposure = try scope.get(value, "exposure");
    const tool_exposure = try scope.get(value, "toolExposure");
    const result = try scope.own(try js.spread(scope.engine, value));
    if (!c.JS_IsUndefined(exposure)) try scope.set(result, "exposure", try alias(scope, aliases, exposure));
    if (try record(scope, tool_exposure)) {
        const object = try scope.global("Object");
        const from = try scope.get(object, "fromEntries");
        const entries = try scope.invoke(try scope.global("Object"), "entries", &.{tool_exposure});
        var roots = [_]c.JSValue{aliases};
        const mapped_entries = try collection(scope, entries, "map", .exposure_pair, &roots);
        try scope.set(result, "toolExposure", try scope.call(from, object, &.{mapped_entries}));
    }
    return result;
}
fn isExposure(scope: *Scope, exposures: c.JSValue, value: c.JSValue) !bool {
    return c.JS_IsString(value) and scope.truthy(try scope.invoke(exposures, "includes", &.{value}));
}
fn stringRecord(scope: *Scope, value: c.JSValue) !bool {
    if (!try record(scope, value)) return false;
    return scope.truthy(try collection(scope, try scope.invoke(try scope.global("Object"), "values", &.{value}), "every", .string, &.{}));
}
fn oauth(scope: *Scope, hosts: c.JSValue, value: c.JSValue) !c.JSValue {
    if (c.JS_IsUndefined(value)) return c.pi_js_undefined();
    if (!try record(scope, value)) return scope.text("oauth must be an object");
    if (!c.JS_IsUndefined(try scope.get(value, "clientId")) and !c.JS_IsString(try scope.get(value, "clientId"))) return scope.text("oauth.clientId must be a string");
    if (!c.JS_IsUndefined(try scope.get(value, "clientSecret")) and !c.JS_IsString(try scope.get(value, "clientSecret"))) return scope.text("oauth.clientSecret must be a string");
    const port = try scope.get(value, "callbackPort");
    if (!c.JS_IsUndefined(port)) {
        if (!c.JS_IsNumber(port)) return scope.text("oauth.callbackPort must be a port number");
        if (!scope.truthy(try scope.invoke(try scope.global("Number"), "isInteger", &.{port}))) return scope.text("oauth.callbackPort must be a port number");
        if (scope.truthy(try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 4, port, c.JS_NewInt32(scope.engine.context, 1))))) or scope.truthy(try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 6, port, c.JS_NewInt32(scope.engine.context, 65535)))))) return scope.text("oauth.callbackPort must be a port number");
    }
    if (!c.JS_IsUndefined(try scope.get(value, "callbackUrl"))) {
        if (!c.JS_IsString(try scope.get(value, "callbackUrl")) or !try loopback(scope, hosts, try scope.get(value, "callbackUrl"))) return scope.text("oauth.callbackUrl must be an http URI on localhost, 127.0.0.1, or [::1] without query or fragment");
        const url_port = try scope.get(try urlField(scope, value, "callbackUrl"), "port");
        if (scope.truthy(url_port) and !c.JS_IsUndefined(port)) {
            const converted = try scope.call(try scope.global("Number"), c.pi_js_undefined(), &.{url_port});
            if (!scope.equal(converted, port)) return scope.text("oauth.callbackUrl and oauth.callbackPort name different ports");
        }
    }
    if (!c.JS_IsUndefined(try scope.get(value, "scope")) and !c.JS_IsString(try scope.get(value, "scope"))) return scope.text("oauth.scope must be a string");
    if (!c.JS_IsUndefined(try scope.get(value, "clientName"))) {
        if (!c.JS_IsString(try scope.get(value, "clientName")) or !scope.truthy(try scope.invoke(try scope.get(value, "clientName"), "trim", &.{}))) return scope.text("oauth.clientName must be a non-empty string");
    }
    if (!c.JS_IsUndefined(try scope.get(value, "clientRegistration")) and !scope.equal(try scope.get(value, "clientRegistration"), try scope.text("dcr"))) {
        if (!scope.equal(try scope.get(value, "clientRegistration"), try scope.text("cimd"))) return scope.text("oauth.clientRegistration must be \"dcr\" or \"cimd\"");
        if (!c.JS_IsUndefined(try scope.get(value, "clientId")) or !c.JS_IsUndefined(try scope.get(value, "clientName"))) return scope.text("oauth.clientRegistration \"cimd\" cannot be combined with oauth.clientId or oauth.clientName");
        const callback_url = if (c.JS_IsString(try scope.get(value, "callbackUrl"))) try urlField(scope, value, "callbackUrl") else c.pi_js_undefined();
        if (scope.truthy(callback_url) and (scope.equal(try scope.get(callback_url, "hostname"), try scope.text("[::1]")) or !scope.equal(try scope.get(callback_url, "pathname"), try scope.text("/callback")))) return scope.text("oauth.clientRegistration \"cimd\" requires oauth.callbackUrl on localhost or 127.0.0.1 with path /callback");
    }
    const metadata_url = try scope.get(value, "authServerMetadataUrl");
    if (!c.JS_IsUndefined(metadata_url)) {
        const parsed = if (c.JS_IsString(metadata_url) and try canParse(scope, metadata_url)) try url(scope, metadata_url) else c.pi_js_undefined();
        if (!scope.truthy(parsed)) return scope.text("oauth.authServerMetadataUrl must be an https URL, or http on localhost, 127.0.0.1, or [::1]");
        if (!scope.equal(try scope.get(parsed, "protocol"), try scope.text("https:"))) {
            if (!scope.equal(try scope.get(parsed, "protocol"), try scope.text("http:"))) return scope.text("oauth.authServerMetadataUrl must be an https URL, or http on localhost, 127.0.0.1, or [::1]");
            const includes = try scope.get(hosts, "includes");
            if (!scope.truthy(try scope.call(includes, hosts, &.{try scope.get(parsed, "hostname")}))) return scope.text("oauth.authServerMetadataUrl must be an https URL, or http on localhost, 127.0.0.1, or [::1]");
        }
    }
    return c.pi_js_undefined();
}
fn message(scope: *Scope, name: c.JSValue, suffix: []const u8) !c.JSValue {
    return scope.concat(try scope.concat(try scope.text("server \""), try scope.stringify(name)), try scope.text(suffix));
}
fn validate(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const name = argument(args, 0);
    const raw = argument(args, 1);
    const result = try validateBody(&scope, name, raw, roots);
    return c.JS_DupValue(engine.context, result);
}
fn validateBody(scope: *Scope, name: c.JSValue, raw: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    if (!scope.truthy(try scope.invoke(roots[3], "test", &.{name}))) return scope.concat(try scope.concat(try scope.text("invalid server name \""), try scope.stringify(name)), try scope.text("\" (use letters, digits, \"_\" and \"-\")"));
    if (!try record(scope, raw)) return message(scope, name, "\" must be an object");
    const value = try aliasesResolved(scope, roots[1], raw);
    const transport = try scope.get(value, "type");
    const exposure = try scope.get(value, "exposure");
    const enabled = try scope.get(value, "enabled");
    const timeout = try scope.get(value, "timeout");
    const tool_exposure = try scope.get(value, "toolExposure");
    const description = try scope.get(value, "description");
    const exposures = try scope.invoke(try collection(scope, roots[0], "map", .exposure_text, &.{}), "join", &.{try scope.text(", ")});
    if (!c.JS_IsUndefined(exposure) and !try isExposure(scope, roots[0], exposure)) return scope.concat(try message(scope, name, "\": exposure must be one of "), try scope.stringify(exposures));
    if (!c.JS_IsUndefined(tool_exposure)) {
        if (!try record(scope, tool_exposure)) return message(scope, name, "\": toolExposure must map tool names to exposures");
        const entries = try scope.invoke(try scope.global("Object"), "entries", &.{tool_exposure});
        const symbol = try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context)));
        var iterator = try js.Iterator.init(scope.engine, entries, symbol);
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |entry| {
            defer scope.engine.freeValue(entry);
            const pair = try js.pair(scope.engine, entry, symbol);
            defer scope.engine.freeValue(pair[0]);
            defer scope.engine.freeValue(pair[1]);
            if (!try isExposure(scope, roots[0], pair[1])) {
                const prefix = try scope.concat(try scope.concat(try message(scope, name, "\": toolExposure \""), try scope.stringify(pair[0])), try scope.text("\" must be one of "));
                const text = try scope.concat(prefix, try scope.stringify(exposures));
                try iterator.close();
                return text;
            }
        }
    }
    if (!c.JS_IsUndefined(enabled) and !c.JS_IsBool(enabled)) return message(scope, name, "\": enabled must be a boolean");
    if (!c.JS_IsUndefined(description) and !c.JS_IsString(description)) return message(scope, name, "\": description must be a string");
    if (!c.JS_IsUndefined(timeout) and (!c.JS_IsNumber(timeout) or !try scope.positive(timeout))) return message(scope, name, "\": timeout must be a positive number of seconds");
    if (scope.equal(transport, try scope.text("sse"))) return message(scope, name, "\": legacy SSE transport is not supported; use the streamable HTTP URL");
    if (c.JS_IsString(try scope.get(value, "url")) and (c.JS_IsUndefined(transport) or scope.equal(transport, try scope.text("http")) or scope.equal(transport, try scope.text("streamable-http")))) {
        if (!try canParseField(scope, value, "url")) return message(scope, name, "\": url must be an http or https URL");
        const protocol_pattern = try regex(scope, "^https?:$", "");
        const test_function = try scope.get(protocol_pattern, "test");
        if (!scope.truthy(try scope.call(test_function, protocol_pattern, &.{try scope.get(try urlField(scope, value, "url"), "protocol")}))) return message(scope, name, "\": url must be an http or https URL");
        if (!c.JS_IsUndefined(try scope.get(value, "headers")) and !try stringRecord(scope, try scope.get(value, "headers"))) return message(scope, name, "\": headers must map names to strings");
        const oauth_error = try oauth(scope, roots[2], try scope.get(value, "oauth"));
        if (scope.truthy(oauth_error)) return scope.concat(try message(scope, name, "\": "), try scope.stringify(oauth_error));
        if (!c.JS_IsUndefined(try scope.get(value, "auth"))) {
            if (!try record(scope, try scope.get(value, "auth")) or !c.JS_IsString(try scope.get(try scope.get(value, "auth"), "provider")) or !scope.truthy(try scope.get(try scope.get(value, "auth"), "provider"))) return message(scope, name, "\": auth.provider must be a provider name");
            const parsed = try urlField(scope, value, "url");
            if (!scope.equal(try scope.get(parsed, "protocol"), try scope.text("https:"))) {
                const includes = try scope.get(roots[2], "includes");
                if (!scope.truthy(try scope.call(includes, roots[2], &.{try scope.get(parsed, "hostname")}))) return message(scope, name, "\": auth requires an https URL, or http on localhost, 127.0.0.1, or [::1]");
            }
        }
        return value;
    }
    if (c.JS_IsString(try scope.get(value, "command")) and (c.JS_IsUndefined(transport) or scope.equal(transport, try scope.text("stdio")))) {
        if (!c.JS_IsUndefined(try scope.get(value, "args"))) {
            if (!try array(scope, try scope.get(value, "args")) or !scope.truthy(try collection(scope, try scope.get(value, "args"), "every", .string, &.{}))) return message(scope, name, "\": args must be an array of strings");
        }
        if (!c.JS_IsUndefined(try scope.get(value, "env")) and !try stringRecord(scope, try scope.get(value, "env"))) return message(scope, name, "\": env must map names to strings");
        if (!c.JS_IsUndefined(try scope.get(value, "cwd")) and !c.JS_IsString(try scope.get(value, "cwd"))) return message(scope, name, "\": cwd must be a string");
        return value;
    }
    return message(scope, name, "\" needs either \"command\" (stdio) or \"url\" (streamable HTTP)");
}
