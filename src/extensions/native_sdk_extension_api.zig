//! Actual transactional loader ExtensionAPI. Source registrations, closures,
//! pending flags/runtime changes and subscription cleanup retain live identities.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const f = @import("native_node_function.zig");
pub const Inputs = struct { exec_command: c.JSValue, mcp: c.JSValue };
const Method = enum(c_int) { on, registerTool, registerCommand, registerShortcut, registerFlag, registerMessageRenderer, registerMarkdownTransformer, registerEntryRenderer, registerToolRenderer, getFlag, sendMessage, sendUserMessage, appendEntry, setSessionName, getSessionName, setLabel, exec, getActiveTools, getAllTools, getSettings, setActiveTools, getCommands, setModel, getThinkingLevel, setThinkingLevel, registerProvider, unregisterProvider, registerMcpServer, unregisterMcpServer, getMcpServers, registerVirtualModel, unregisterVirtualModel, emit, event_on, commit, discard };
const Closure = enum(c_int) { registered_handler, unsubscribe_handler, runtime_change, mcp_clash, virtual_route };
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn nullObject(scope: *Scope) !c.JSValue { return scope.own(try scope.engine.checked(c.JS_NewObjectProto(scope.engine.context, c.pi_js_null()))); }
pub fn create(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    if (!c.JS_IsFunction(engine.context, inputs.exec_command)) return error.RequiredActualExtensionExecCommand;
    const imports = try nullObject(&scope);
    try scope.put(imports, "execCommand", inputs.exec_command);
    inline for (.{ "validateMcpServerConfig", "mcpNamespace" }) |name| {
        const value = try scope.get(inputs.mcp, name);
        if (!c.JS_IsFunction(engine.context, value)) return error.RequiredActualExtensionMcpImport;
        try scope.put(imports, name, value);
    }
    return f.create(engine, "createExtensionAPI", 4, createApi, &.{imports});
}
fn createApi(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    const owner = try nullObject(&scope);
    inline for (.{ "extension", "runtime", "cwd", "eventBus" }, 0..) |name, index| try scope.put(owner, name, arg(args, index));
    try scope.put(owner, "imports", roots[0]);
    try scope.put(owner, "pendingFlagValues", try scope.own(try v.js.builtin(engine, "Map", &.{})));
    try scope.put(owner, "pendingRuntimeChanges", try scope.array());
    try scope.put(owner, "loadingUnsubscribers", try scope.array());
    try scope.put(owner, "state", try scope.text("loading"));
    const api = try scope.object();
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        const kind: Method = @enumFromInt(field.value);
        if (comptime field.value < @intFromEnum(Method.emit)) try scope.put(api, field.name, try methodFunction(&scope, owner, kind, field.name));
    }
    const events = try scope.object();
    try scope.put(events, "emit", try methodFunction(&scope, owner, .emit, "emit"));
    try scope.put(events, "on", try methodFunction(&scope, owner, .event_on, "on"));
    try scope.put(api, "events", events);
    const result = try scope.object();
    try scope.put(result, "api", api);
    try scope.put(result, "commit", try scope.own(try f.createArrow(engine, "commit", 0, method, &.{ owner, c.JS_NewInt32(engine.context, @intFromEnum(Method.commit)) })));
    try scope.put(result, "discard", try scope.own(try f.createArrow(engine, "discard", 0, method, &.{ owner, c.JS_NewInt32(engine.context, @intFromEnum(Method.discard)) })));
    return c.JS_DupValue(engine.context, result);
}
fn methodFunction(scope: *Scope, owner: c.JSValue, kind: Method, name: [*:0]const u8) !c.JSValue {
    const length: c_int = switch (kind) {
        .getSessionName, .getActiveTools, .getAllTools, .getSettings, .getCommands, .getThinkingLevel, .getMcpServers => 0,
        .registerTool, .registerMarkdownTransformer, .registerToolRenderer, .getFlag, .setSessionName, .setActiveTools, .setModel, .setThinkingLevel, .unregisterProvider, .unregisterMcpServer, .registerVirtualModel => 1,
        .exec => 3,
        else => 2,
    };
    return scope.own(try f.createMethod(scope.engine, name, length, method, &.{ owner, c.JS_NewInt32(scope.engine.context, @intFromEnum(kind)) }));
}
fn raise(scope: *Scope, message: c.JSValue) !c.JSValue {
    return scope.engine.checked(c.JS_Throw(scope.engine.context, try v.js.builtin(scope.engine, "Error", &.{message})));
}
fn typeName(scope: *Scope, value: c.JSValue) !c.JSValue {
    return scope.text(if (c.JS_IsUndefined(value)) "undefined" else if (c.JS_IsBool(value)) "boolean" else if (c.JS_IsNumber(value)) "number" else if (c.JS_IsBigInt(value)) "bigint" else if (c.JS_IsString(value)) "string" else if (c.JS_IsSymbol(value)) "symbol" else if (c.JS_IsFunction(scope.engine.context, value)) "function" else "object");
}
fn assertActive(scope: *Scope, owner: c.JSValue) !void {
    if (try v.eq(scope, try scope.get(owner, "state"), "failed")) {
        const path = try scope.get(try scope.get(owner, "extension"), "path");
        _ = try raise(scope, try scope.concat(try scope.concat(try scope.text("Extension \""), try scope.stringify(path)), try scope.text("\" failed to load and its API is no longer active.")));
    }
    _ = try scope.invoke(try scope.get(owner, "runtime"), "assertActive", &.{});
}
fn callback(scope: *Scope, kind: Closure, roots: []const c.JSValue, length: c_int) !c.JSValue {
    const values = try scope.engine.gpa.alloc(c.JSValue, roots.len + 1);
    defer scope.engine.gpa.free(values);
    values[0] = c.JS_NewInt32(scope.engine.context, @intFromEnum(kind));
    @memcpy(values[1..], roots);
    return scope.own(try f.createArrow(scope.engine, switch (kind) { .registered_handler => "registeredHandler", .virtual_route => "route", else => "" }, length, closure, values));
}
fn map(scope: *Scope, extension: c.JSValue, name: [*:0]const u8) !c.JSValue { return scope.get(extension, name); }
fn clearPending(scope: *Scope, owner: c.JSValue) !void {
    _ = try scope.invoke(try scope.get(owner, "pendingFlagValues"), "clear", &.{});
    try scope.set(try scope.get(owner, "pendingRuntimeChanges"), "length", c.JS_NewInt32(scope.engine.context, 0));
    try scope.set(try scope.get(owner, "loadingUnsubscribers"), "length", c.JS_NewInt32(scope.engine.context, 0));
}
fn apply(scope: *Scope, owner: c.JSValue, kind: Method, args: []const c.JSValue) !void {
    const values = try nullObject(scope);
    try scope.index(values, 0, arg(args, 0));
    try scope.index(values, 1, arg(args, 1));
    const change = try callback(scope, .runtime_change, &.{ owner, c.JS_NewInt32(scope.engine.context, @intFromEnum(kind)), values }, 0);
    if (try v.eq(scope, try scope.get(owner, "state"), "loading")) _ = try scope.invoke(try scope.get(owner, "pendingRuntimeChanges"), "push", &.{change}) else _ = try scope.call(change, c.pi_js_undefined(), &.{});
}
fn lifecycle(scope: *Scope, owner: c.JSValue, kind: Method) !void {
    if (!try v.eq(scope, try scope.get(owner, "state"), "loading")) return;
    if (kind == .commit) {
        const runtime = try scope.get(owner, "runtime");
        _ = try scope.invoke(runtime, "assertActive", &.{});
        var iterator = try v.iterator(scope, try scope.get(owner, "pendingFlagValues"));
        defer iterator.deinit(); errdefer iterator.closePreserving();
        while (try iterator.next()) |entry| {
            defer scope.engine.freeValue(entry);
            const pair = try v.js.pair(scope.engine, entry, try scope.own(try scope.engine.checked(c.JS_GetIteratorSymbol(scope.engine.context))));
            defer scope.engine.freeValue(pair[0]); defer scope.engine.freeValue(pair[1]);
            if (!scope.truthy(try scope.invoke(try scope.get(runtime, "flagValues"), "has", &.{pair[0]}))) _ = try scope.invoke(try scope.get(runtime, "flagValues"), "set", &.{ pair[0], pair[1] });
        }
        try callEach(scope, try scope.get(owner, "pendingRuntimeChanges"));
        try scope.set(owner, "state", try scope.text("active"));
    } else {
        try scope.set(owner, "state", try scope.text("failed"));
        try callEach(scope, try scope.get(owner, "loadingUnsubscribers"));
    }
    try clearPending(scope, owner);
}
fn callEach(scope: *Scope, values: c.JSValue) !void {
    var iterator = try v.iterator(scope, values); defer iterator.deinit(); errdefer iterator.closePreserving();
    while (try iterator.next()) |value| { defer scope.engine.freeValue(value); _ = try scope.call(value, c.pi_js_undefined(), &.{}); }
}
fn method(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    var raw: i32 = 0; if (c.JS_ToInt32(engine.context, &raw, roots[1]) < 0) return v.js.capture(engine);
    const kind: Method = @enumFromInt(raw); const owner = roots[0];
    if (kind == .commit or kind == .discard) { try lifecycle(&scope, owner, kind); return c.pi_js_undefined(); }
    try assertActive(&scope, owner);
    const extension = try scope.get(owner, "extension"); const runtime = try scope.get(owner, "runtime");
    const first = arg(args, 0); const second = arg(args, 1);
    switch (kind) {
        .on => {
            const wrapped = try callback(&scope, .registered_handler, &.{second}, 0);
            const handlers = try map(&scope, extension, "handlers");
            const supplied = try scope.invoke(handlers, "get", &.{first});
            const list = if (v.nullish(supplied)) try scope.array() else supplied;
            _ = try scope.invoke(list, "push", &.{wrapped});
            _ = try scope.invoke(try map(&scope, extension, "handlers"), "set", &.{ first, list });
            return c.JS_DupValue(engine.context, try callback(&scope, .unsubscribe_handler, &.{ extension, first, wrapped }, 0));
        },
        .registerTool => {
            const schema = try scope.get(first, "parameters");
            if (!(c.JS_IsObject(schema) or c.JS_IsNull(schema)) or c.JS_IsFunction(engine.context, schema) or c.JS_IsNull(try scope.get(first, "parameters")) or try v.array(&scope, try scope.get(first, "parameters"))) {
                const name = try scope.get(first, "name"); const path = try scope.get(extension, "path");
                return raise(&scope, try scope.concat(try scope.concat(try scope.concat(try scope.concat(try scope.text("Tool \""), try scope.stringify(name)), try scope.text("\" registered by extension \"")), try scope.stringify(path)), try scope.text("\" must define an object parameter schema.")));
            }
            const tools = try map(&scope, extension, "tools"); const setter = try scope.get(tools, "set"); const name = try scope.get(first, "name");
            const value = try scope.object(); try scope.put(value, "definition", first); try scope.put(value, "sourceInfo", try scope.get(extension, "sourceInfo"));
            _ = try scope.call(setter, tools, &.{ name, value }); _ = try scope.invoke(runtime, "refreshTools", &.{});
        },
        .registerCommand => {
            if (!c.JS_IsString(first) or !scope.truthy(try scope.get(first, "length"))) {
                const path = try scope.get(extension, "path");
                return raise(&scope, try scope.concat(try scope.concat(try scope.text("Command registered by extension \""), try scope.stringify(path)), try scope.text("\" must have a non-empty string name. Use pi.registerCommand(\"name\", { description, handler }).")));
            }
            if (v.nullish(second) or !c.JS_IsFunction(engine.context, try scope.get(second, "handler"))) return raise(&scope, try scope.concat(try scope.concat(try scope.concat(try scope.concat(try scope.text("Command \"/"), first), try scope.text("\" registered by extension \"")), try scope.stringify(try scope.get(extension, "path"))), try scope.text("\" must define handler().")));
            const commands = try map(&scope, extension, "commands"); const setter = try scope.get(commands, "set");
            const value = try scope.object(); try scope.put(value, "name", first); try scope.put(value, "sourceInfo", try scope.get(extension, "sourceInfo")); try v.js.spreadInto(engine, value, second);
            _ = try scope.call(setter, commands, &.{ first, value });
        },
        .registerShortcut, .registerFlag => {
            if (kind == .registerFlag and !c.JS_IsUndefined(try scope.get(second, "default"))) {
                const supplied = try scope.get(second, "default");
                const actual_type = try typeName(&scope, supplied);
                if (!scope.equal(actual_type, try scope.get(second, "type"))) {
                    const expected = try scope.get(second, "type"); const received = try typeName(&scope, try scope.get(second, "default"));
                    return raise(&scope, try scope.concat(try scope.concat(try scope.concat(try scope.concat(try scope.text("Invalid default for flag \""), try scope.stringify(first)), try scope.text("\": expected ")), try scope.stringify(expected)), try scope.concat(try scope.text(", got "), received)));
                }
            }
            const target = try map(&scope, extension, if (kind == .registerFlag) "flags" else "shortcuts"); const setter = try scope.get(target, "set");
            const value = try scope.object(); try scope.put(value, if (kind == .registerFlag) "name" else "shortcut", first); try scope.put(value, "extensionPath", try scope.get(extension, "path")); try v.js.spreadInto(engine, value, second);
            _ = try scope.call(setter, target, &.{ first, value });
            if (kind == .registerFlag and !c.JS_IsUndefined(try scope.get(second, "default")) and !scope.truthy(try scope.invoke(try scope.get(runtime, "flagValues"), "has", &.{first}))) {
                const pending = try scope.get(owner, "pendingFlagValues");
                if (try v.eq(&scope, try scope.get(owner, "state"), "loading")) {
                    if (!scope.truthy(try scope.invoke(pending, "has", &.{first}))) _ = try scope.invoke(pending, "set", &.{ first, try scope.get(second, "default") });
                } else _ = try scope.invoke(try scope.get(runtime, "flagValues"), "set", &.{ first, try scope.get(second, "default") });
            }
        },
        .registerMessageRenderer, .registerEntryRenderer => {
            const name = if (kind == .registerMessageRenderer) "messageRenderers" else "entryRenderers";
            if (kind == .registerEntryRenderer and v.nullish(try scope.get(extension, name))) try scope.set(extension, name, try scope.own(try v.js.builtin(engine, "Map", &.{})));
            _ = try scope.invoke(try map(&scope, extension, name), "set", &.{ first, second });
        },
        .registerMarkdownTransformer => try scope.set(extension, "markdownTransformer", first),
        .registerToolRenderer => {
            if (v.nullish(try scope.get(extension, "toolRenderers"))) try scope.set(extension, "toolRenderers", try scope.array());
            _ = try scope.invoke(try scope.get(extension, "toolRenderers"), "push", &.{first});
        },
        .getFlag => {
            if (!scope.truthy(try scope.invoke(try map(&scope, extension, "flags"), "has", &.{first}))) return c.pi_js_undefined();
            return c.JS_DupValue(engine.context, if (scope.truthy(try scope.invoke(try scope.get(runtime, "flagValues"), "has", &.{first}))) try scope.invoke(try scope.get(runtime, "flagValues"), "get", &.{first}) else try scope.invoke(try scope.get(owner, "pendingFlagValues"), "get", &.{first}));
        },
        .exec => {
            const options = arg(args, 2); const supplied = if (v.nullish(options)) c.pi_js_undefined() else try scope.get(options, "cwd");
            return v.js.call(engine, try scope.get(try scope.get(owner, "imports"), "execCommand"), c.pi_js_undefined(), &.{ first, second, if (v.nullish(supplied)) try scope.get(owner, "cwd") else supplied, options });
        },
        .registerProvider => {
            if (c.JS_IsString(first) and !scope.truthy(second)) return raise(&scope, try scope.text("Provider config is required when registering by name"));
            try apply(&scope, owner, kind, &.{ first, second });
        },
        .unregisterProvider, .unregisterMcpServer, .unregisterVirtualModel => try apply(&scope, owner, kind, &.{ first, second }),
        .registerMcpServer => try registerMcp(&scope, owner, first, second),
        .getMcpServers => return c.JS_DupValue(engine.context, try scope.invoke(try scope.get(runtime, "mcpServers"), "list", &.{})),
        .registerVirtualModel => {
            const definition = try v.spread(&scope, first); try scope.put(definition, "route", try callback(&scope, .virtual_route, &.{ first, runtime }, 1));
            try apply(&scope, owner, kind, &.{definition});
        },
        .emit => { _ = try scope.invoke(try scope.get(owner, "eventBus"), "emit", &.{ first, second }); },
        .event_on => {
            const track = try scope.get(runtime, "trackEventBusSubscription");
            const unsubscribe = try scope.call(track, runtime, &.{try scope.invoke(try scope.get(owner, "eventBus"), "on", &.{ first, second })});
            if (try v.eq(&scope, try scope.get(owner, "state"), "loading")) _ = try scope.invoke(try scope.get(owner, "loadingUnsubscribers"), "push", &.{unsubscribe});
            return c.JS_DupValue(engine.context, unsubscribe);
        },
        .commit, .discard => unreachable,
        else => {
            const forwarded: []const c.JSValue = switch (kind) { .sendMessage, .sendUserMessage, .appendEntry, .setLabel => &.{ first, second }, .setSessionName, .setActiveTools, .setModel, .setThinkingLevel => &.{first}, else => &.{} };
            const result = try scope.invoke(runtime, @tagName(kind), forwarded);
            return switch (kind) { .getSessionName, .getActiveTools, .getAllTools, .getSettings, .getCommands, .setModel, .getThinkingLevel => c.JS_DupValue(engine.context, result), else => c.pi_js_undefined() };
        },
    }
    return c.pi_js_undefined();
}
fn registerMcp(scope: *Scope, owner: c.JSValue, name: c.JSValue, config: c.JSValue) !void {
    const imports = try scope.get(owner, "imports"); const extension = try scope.get(owner, "extension"); const runtime = try scope.get(owner, "runtime");
    const validated = try scope.call(try scope.get(imports, "validateMcpServerConfig"), c.pi_js_undefined(), &.{ name, config });
    if (c.JS_IsString(validated)) { _ = try raise(scope, try scope.concat(try scope.concat(try scope.concat(try scope.text("Invalid MCP server registered by extension \""), try scope.stringify(try scope.get(extension, "path"))), try scope.text("\": ")), validated)); }
    const previous = try scope.invoke(try scope.get(runtime, "mcpServers"), "get", &.{name});
    const path = if (v.nullish(previous)) c.pi_js_undefined() else try scope.get(previous, "extensionPath");
    if (!c.JS_IsUndefined(path) and !scope.equal(path, try scope.get(extension, "path"))) { _ = try raise(scope, try scope.concat(try scope.concat(try scope.concat(try scope.concat(try scope.text("MCP server \""), try scope.stringify(name)), try scope.text("\" is already registered by extension \"")), try scope.stringify(path)), try scope.text("\""))); }
    const clash = try scope.invoke(try scope.invoke(try scope.get(runtime, "mcpServers"), "list", &.{}), "find", &.{try callback(scope, .mcp_clash, &.{ name, imports }, 1)});
    if (scope.truthy(clash)) { _ = try raise(scope, try scope.concat(try scope.concat(try scope.concat(try scope.concat(try scope.text("MCP server \""), try scope.stringify(name)), try scope.text("\" conflicts with registered server \"")), try scope.stringify(try scope.get(clash, "name"))), try scope.text("\""))); }
    const server = try scope.object(); try scope.put(server, "name", name); try scope.put(server, "config", try scope.call(try scope.global("structuredClone"), c.pi_js_undefined(), &.{validated})); try scope.put(server, "extensionPath", try scope.get(extension, "path"));
    try apply(scope, owner, .registerMcpServer, &.{server});
}
fn closure(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    var raw: i32 = 0; if (c.JS_ToInt32(engine.context, &raw, roots[0]) < 0) return v.js.capture(engine);
    switch (@as(Closure, @enumFromInt(raw))) {
        .registered_handler => return v.js.call(engine, roots[1], c.pi_js_undefined(), args),
        .unsubscribe_handler => {
            const supplied = try scope.invoke(try map(&scope, roots[1], "handlers"), "get", &.{roots[2]}); if (!scope.truthy(supplied)) return c.pi_js_undefined();
            const index = try scope.invoke(supplied, "indexOf", &.{roots[3]}); if (scope.equal(index, c.JS_NewInt32(engine.context, -1))) return c.pi_js_undefined();
            _ = try scope.invoke(supplied, "splice", &.{ index, c.JS_NewInt32(engine.context, 1) });
            if (scope.equal(try scope.get(supplied, "length"), c.JS_NewInt32(engine.context, 0))) _ = try scope.invoke(try map(&scope, roots[1], "handlers"), "delete", &.{roots[2]});
        },
        .virtual_route => return v.js.call(engine, try scope.get(roots[1], "route"), roots[1], &.{ arg(args, 0), try scope.invoke(roots[2], "createContext", &.{}) }),
        .mcp_clash => {
            const server = arg(args, 0); if (scope.equal(try scope.get(server, "name"), roots[1])) return c.pi_js_bool(engine.context, 0);
            const namespace = try scope.get(roots[2], "mcpNamespace");
            return c.pi_js_bool(engine.context, @intFromBool(scope.equal(try scope.call(namespace, c.pi_js_undefined(), &.{try scope.get(server, "name")}), try scope.call(try scope.get(roots[2], "mcpNamespace"), c.pi_js_undefined(), &.{roots[1]}))));
        },
        .runtime_change => {
            const owner = roots[1]; var operation: i32 = 0; if (c.JS_ToInt32(engine.context, &operation, roots[2]) < 0) return v.js.capture(engine);
            const kind: Method = @enumFromInt(operation); const values = roots[3]; const first = try v.at(&scope, values, 0); const second = try v.at(&scope, values, 1);
            const runtime = try scope.get(owner, "runtime"); const extension = try scope.get(owner, "extension");
            switch (kind) {
                .registerProvider => {
                    const function = try scope.get(runtime, if (c.JS_IsString(first)) "registerProvider" else "registerNativeProvider");
                    _ = if (c.JS_IsString(first)) try scope.call(function, runtime, &.{ first, second, try scope.get(extension, "path") }) else try scope.call(function, runtime, &.{ first, try scope.get(extension, "path") });
                },
                .unregisterProvider => { const function = try scope.get(runtime, "unregisterProvider"); _ = try scope.call(function, runtime, &.{ first, try scope.get(extension, "path") }); },
                .registerMcpServer => { _ = try scope.invoke(try scope.get(runtime, "mcpServers"), "register", &.{first}); },
                .unregisterMcpServer => { const registry = try scope.get(runtime, "mcpServers"); const function = try scope.get(registry, "unregister"); _ = try scope.call(function, registry, &.{ first, try scope.get(extension, "path") }); },
                .registerVirtualModel => { const function = try scope.get(runtime, "registerVirtualModel"); _ = try scope.call(function, runtime, &.{ first, try scope.get(extension, "path") }); },
                .unregisterVirtualModel => { _ = try scope.invoke(runtime, "unregisterVirtualModel", &.{ first, second }); },
                else => return error.InvalidExtensionRuntimeChange,
            }
        },
    }
    return c.pi_js_undefined();
}
