//! Pi extension registrations and invocation owned by Zig through the C ABI.
const std = @import("std");
const engine_mod = @import("engine.zig");
const typebox = @import("typebox.zig");
const c = engine_mod.c;
const Method = enum(c_int) { on, registerTool, registerCommand, registerFlag, getFlag, setSessionName, setThinkingLevel, setActiveTools, sendUserMessage, appendEntry, setLabel };
const ContextMethod = enum(c_int) {
    mode,
    hasUI,
    cwd,
    model,
    scopedModels,
    thinkingLevel,
    sessionManager,
    isIdle,
    isProjectTrusted,
    hasPendingMessages,
    getContextUsage,
    getSystemPrompt,
    getCwd,
    getSessionDir,
    getSessionId,
    getSessionFile,
    getSessionName,
    getLeafId,
    getEntries,
    getBranch,
    buildContextEntries,
    getHeader,
};

pub const Bindings = struct {
    gpa: std.mem.Allocator,
    engine: *engine_mod.Engine,
    api: c.JSValue,
    handlers: std.StringHashMapUnmanaged(std.ArrayList(c.JSValue)) = .empty,
    tools: std.StringHashMapUnmanaged(c.JSValue) = .empty,
    commands: std.StringHashMapUnmanaged(c.JSValue) = .empty,
    flags: std.StringHashMapUnmanaged(c.JSValue) = .empty,
    flag_overrides: std.StringHashMapUnmanaged(c.JSValue) = .empty,
    actions: std.ArrayList(c.JSValue) = .empty,
    invocation_active: bool = false,
    invocation_generation: u32 = 0,
    context_snapshot: ?c.JSValue = null,

    pub fn init(gpa: std.mem.Allocator, engine: *engine_mod.Engine) !*Bindings {
        if (engine.host_data != null) return error.EngineHostAlreadyAttached;
        const self = try gpa.create(Bindings);
        errdefer gpa.destroy(self);
        const api = try engine.checked(c.JS_NewObject(engine.context));
        errdefer engine.freeValue(api);
        inline for (std.meta.fields(Method)) |field| {
            const name: [:0]const u8 = field.name;
            const function = try engine.checked(c.pi_js_function_magic(engine.context, invokeRegistration, name.ptr, 2, @intCast(field.value)));
            if (c.JS_DefinePropertyValueStr(engine.context, api, name.ptr, function, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        }
        self.* = .{ .gpa = gpa, .engine = engine, .api = api };
        engine.host_data = self;
        return self;
    }

    pub fn deinit(self: *Bindings) void {
        self.engine.host_data = null;
        var handlers = self.handlers.iterator();
        while (handlers.next()) |entry| {
            for (entry.value_ptr.items) |value| self.engine.freeValue(value);
            entry.value_ptr.deinit(self.gpa);
            self.gpa.free(entry.key_ptr.*);
        }
        self.handlers.deinit(self.gpa);
        self.freeTable(&self.tools);
        self.freeTable(&self.commands);
        self.freeTable(&self.flags);
        self.freeTable(&self.flag_overrides);
        for (self.actions.items) |action| self.engine.freeValue(action);
        self.actions.deinit(self.gpa);
        self.engine.freeValue(self.api);
        if (self.context_snapshot) |snapshot| self.engine.freeValue(snapshot);
        const gpa = self.gpa;
        gpa.destroy(self);
    }

    fn freeTable(self: *Bindings, table: *std.StringHashMapUnmanaged(c.JSValue)) void {
        var entries = table.iterator();
        while (entries.next()) |entry| {
            self.engine.freeValue(entry.value_ptr.*);
            self.gpa.free(entry.key_ptr.*);
        }
        table.deinit(self.gpa);
    }

    fn store(self: *Bindings, table: *std.StringHashMapUnmanaged(c.JSValue), name: []const u8, value: c.JSValue) !void {
        if (table.getPtr(name)) |previous| {
            self.engine.freeValue(previous.*);
            previous.* = c.JS_DupValue(self.engine.context, value);
            return;
        }
        const key = try self.gpa.dupe(u8, name);
        errdefer self.gpa.free(key);
        const owned = c.JS_DupValue(self.engine.context, value);
        errdefer self.engine.freeValue(owned);
        try table.put(self.gpa, key, owned);
    }

    fn registration(self: *Bindings, method: Method, args: []c.JSValue) !c.JSValue {
        if (args.len == 0) return error.MissingExtensionArgument;
        if (@intFromEnum(method) >= @intFromEnum(Method.setSessionName)) {
            if (!self.invocation_active) return error.StaleExtensionActionContext;
            return self.recordAction(method, args);
        }
        if (method == .registerTool) {
            const value = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, args[0], "name"));
            defer self.engine.freeValue(value);
            if (!c.JS_IsString(value)) return error.InvalidExtensionToolName;
            const name = try self.engine.toString(value);
            defer self.gpa.free(name);
            if (name.len == 0) return error.InvalidExtensionToolName;
            try self.store(&self.tools, name, args[0]);
            return c.pi_js_undefined();
        }
        const name = try self.engine.toString(args[0]);
        defer self.gpa.free(name);
        if (name.len == 0) return error.InvalidExtensionRegistrationName;
        if (method == .getFlag) {
            if (self.flag_overrides.get(name)) |override| return c.JS_DupValue(self.engine.context, override);
            const flag = self.flags.get(name) orelse return c.pi_js_undefined();
            return self.engine.checked(c.JS_GetPropertyStr(self.engine.context, flag, "default"));
        }
        if (args.len < 2) return error.MissingExtensionArgument;
        switch (method) {
            .on => {
                if (!c.JS_IsFunction(self.engine.context, args[1])) return error.InvalidExtensionHandler;
                const entry = try self.handlers.getOrPut(self.gpa, name);
                if (!entry.found_existing) {
                    entry.key_ptr.* = self.gpa.dupe(u8, name) catch |err| {
                        _ = self.handlers.remove(name);
                        return err;
                    };
                    entry.value_ptr.* = .empty;
                }
                const handler = c.JS_DupValue(self.engine.context, args[1]);
                errdefer self.engine.freeValue(handler);
                try entry.value_ptr.append(self.gpa, handler);
            },
            .registerCommand => try self.store(&self.commands, name, args[1]),
            .registerFlag => {
                const kind = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, args[1], "type"));
                defer self.engine.freeValue(kind);
                const kind_name = try self.engine.toString(kind);
                defer self.gpa.free(kind_name);
                if (!std.mem.eql(u8, kind_name, "boolean") and !std.mem.eql(u8, kind_name, "string")) return error.InvalidExtensionFlagType;
                const value = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, args[1], "default"));
                defer self.engine.freeValue(value);
                if (!c.JS_IsUndefined(value) and ((std.mem.eql(u8, kind_name, "boolean") and !c.JS_IsBool(value)) or
                    (std.mem.eql(u8, kind_name, "string") and !c.JS_IsString(value)))) return error.InvalidExtensionFlagDefault;
                try self.store(&self.flags, name, args[1]);
            },
            else => unreachable,
        }
        return c.pi_js_undefined();
    }

    fn recordAction(self: *Bindings, method: Method, args: []c.JSValue) !c.JSValue {
        const action = try self.engine.checked(c.JS_NewObject(self.engine.context));
        errdefer self.engine.freeValue(action);
        const kind: [*:0]const u8 = switch (method) {
            .setSessionName => "set_session_name",
            .setThinkingLevel => "set_thinking_level",
            .setActiveTools => "set_active_tools",
            .sendUserMessage => "send_user_message",
            .appendEntry => "append_entry",
            .setLabel => "set_label",
            else => unreachable,
        };
        if (c.JS_DefinePropertyValueStr(self.engine.context, action, "type", c.JS_NewString(self.engine.context, kind), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        const key: [*:0]const u8 = switch (method) {
            .setSessionName => "name",
            .setThinkingLevel => "level",
            .setActiveTools => "names",
            .sendUserMessage => "content",
            .appendEntry => "customType",
            .setLabel => "entryId",
            else => unreachable,
        };
        if (c.JS_DefinePropertyValueStr(self.engine.context, action, key, c.JS_DupValue(self.engine.context, args[0]), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        if (method == .appendEntry and args.len > 1) {
            if (c.JS_DefinePropertyValueStr(self.engine.context, action, "data", c.JS_DupValue(self.engine.context, args[1]), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        } else if (method == .setLabel) {
            if (args.len < 2) return error.MissingExtensionArgument;
            if (c.JS_DefinePropertyValueStr(self.engine.context, action, "label", c.JS_DupValue(self.engine.context, args[1]), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        } else if (method == .sendUserMessage and args.len > 1) {
            if (c.JS_DefinePropertyValueStr(self.engine.context, action, "options", c.JS_DupValue(self.engine.context, args[1]), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        }
        try self.actions.append(self.gpa, action);
        return c.pi_js_undefined();
    }

    fn beginActions(self: *Bindings) !void {
        if (self.invocation_active) return error.ExtensionInvocationBusy;
        if (self.invocation_generation == std.math.maxInt(u32)) return error.ExtensionInvocationGenerationExhausted;
        self.invocation_generation += 1;
        for (self.actions.items) |action| self.engine.freeValue(action);
        self.actions.clearRetainingCapacity();
        self.invocation_active = true;
    }

    fn mergeActions(self: *Bindings, result: c.JSValue) !void {
        if (self.actions.items.len == 0) return;
        const queue = try self.engine.checked(c.JS_NewArray(self.engine.context));
        var consumed = false;
        errdefer if (!consumed) self.engine.freeValue(queue);
        for (self.actions.items, 0..) |action, index| {
            if (c.JS_SetPropertyUint32(self.engine.context, queue, @intCast(index), c.JS_DupValue(self.engine.context, action)) < 0) return error.JavaScriptException;
        }
        // The property setter consumes queue, including on failure.
        const status = c.JS_DefinePropertyValueStr(self.engine.context, result, "actionQueue", queue, c.JS_PROP_C_W_E);
        consumed = true;
        if (status < 0) return error.JavaScriptException;
    }

    fn invokeRegistration(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
        const engine = engine_mod.Engine.fromContext(context.?);
        const self: *Bindings = @ptrCast(@alignCast(engine.host_data orelse return c.JS_ThrowInternalError(context, "Native extension host is detached")));
        return self.registration(@enumFromInt(magic), argv[0..@intCast(argc)]) catch |err| c.JS_ThrowTypeError(context, "Native extension registration failed: %s", @as([*:0]const u8, @errorName(err)));
    }

    pub fn installSchemas(self: *Bindings) !void {
        const types = try typebox.create(self.engine);
        defer self.engine.freeValue(types);
        const exports = try self.engine.checked(c.JS_NewObject(self.engine.context));
        defer self.engine.freeValue(exports);
        if (c.JS_DefinePropertyValueStr(self.engine.context, exports, "Type", c.JS_DupValue(self.engine.context, types), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        try self.engine.registerValueModule("typebox", exports);
        try self.engine.registerValueModule("@sinclair/typebox", exports);
    }

    pub fn loadFactory(self: *Bindings, source: []const u8, filename: [:0]const u8) !void {
        const namespace = try self.engine.evalModule(source, filename);
        defer self.engine.freeValue(namespace);
        try self.loadFactoryValue(namespace);
    }

    pub fn loadFactoryValue(self: *Bindings, namespace: c.JSValue) !void {
        var factory = if (c.JS_IsFunction(self.engine.context, namespace)) c.JS_DupValue(self.engine.context, namespace) else if (c.JS_IsObject(namespace)) try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, namespace, "default")) else c.pi_js_undefined();
        defer self.engine.freeValue(factory);
        if (c.JS_IsObject(factory) and !c.JS_IsFunction(self.engine.context, factory)) {
            const nested = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, factory, "default"));
            if (c.JS_IsFunction(self.engine.context, nested)) {
                self.engine.freeValue(factory);
                factory = nested;
            } else self.engine.freeValue(nested);
        }
        if (c.JS_IsUndefined(factory) or c.JS_IsNull(factory)) {
            const fallback = if (c.JS_IsObject(namespace)) try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, namespace, "extension")) else c.pi_js_undefined();
            self.engine.freeValue(factory);
            factory = fallback;
        }
        if (!c.JS_IsFunction(self.engine.context, factory)) return error.InvalidExtensionFactory;
        var args = [_]c.JSValue{self.api};
        const promise = try self.engine.checked(c.JS_Call(self.engine.context, factory, c.pi_js_undefined(), 1, &args));
        defer self.engine.freeValue(promise);
        const value = try self.engine.awaitValue(promise);
        defer self.engine.freeValue(value);
    }

    fn parseJson(self: *Bindings, source: []const u8, filename: [*:0]const u8) !c.JSValue {
        const terminated = try self.gpa.dupeZ(u8, source);
        defer self.gpa.free(terminated);
        return self.engine.checked(c.JS_ParseJSON(self.engine.context, terminated.ptr, source.len, filename));
    }

    pub fn setContext(self: *Bindings, source: []const u8) !void {
        if (self.invocation_active) return error.ExtensionInvocationBusy;
        const snapshot = try self.parseJson(source, "extension-context");
        errdefer self.engine.freeValue(snapshot);
        if (!c.JS_IsObject(snapshot) or c.JS_IsArray(snapshot)) return error.InvalidExtensionContext;
        inline for (.{ "hasUI", "idle", "projectTrusted", "hasPendingMessages" }) |name| {
            const value = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, snapshot, name));
            defer self.engine.freeValue(value);
            if (!c.JS_IsUndefined(value) and !c.JS_IsBool(value)) return error.InvalidExtensionContext;
        }
        inline for (.{ "mode", "cwd", "thinkingLevel", "systemPrompt", "sessionId" }) |name| {
            const value = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, snapshot, name));
            defer self.engine.freeValue(value);
            if (!c.JS_IsUndefined(value) and !c.JS_IsString(value)) return error.InvalidExtensionContext;
        }
        inline for (.{ "sessionDir", "sessionFile", "sessionName", "sessionLeafId" }) |name| {
            const value = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, snapshot, name));
            defer self.engine.freeValue(value);
            if (!c.JS_IsUndefined(value) and !c.JS_IsNull(value) and !c.JS_IsString(value)) return error.InvalidExtensionContext;
        }
        inline for (.{ "scopedModels", "sessionEntries", "sessionBranch" }) |name| {
            const value = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, snapshot, name));
            defer self.engine.freeValue(value);
            if (!c.JS_IsUndefined(value) and !c.JS_IsArray(value)) return error.InvalidExtensionContext;
        }
        if (self.context_snapshot) |old| self.engine.freeValue(old);
        self.context_snapshot = snapshot;
    }

    fn contextFunction(self: *Bindings, name: [:0]const u8, kind: ContextMethod, snapshot: c.JSValue, generation: u32) !c.JSValue {
        const token = c.JS_NewInt64(self.engine.context, generation);
        defer self.engine.freeValue(token);
        var data = [_]c.JSValue{ token, snapshot };
        return self.engine.checked(c.JS_NewCFunctionData2(self.engine.context, contextCallback, name.ptr, 0, @intFromEnum(kind), data.len, &data));
    }

    fn createContext(self: *Bindings) !c.JSValue {
        const snapshot = if (self.context_snapshot) |value| c.JS_DupValue(self.engine.context, value) else try self.engine.checked(c.JS_NewObject(self.engine.context));
        defer self.engine.freeValue(snapshot);
        const context = try self.engine.checked(c.JS_NewObject(self.engine.context));
        errdefer self.engine.freeValue(context);
        inline for (std.meta.fields(ContextMethod)) |field| {
            const kind: ContextMethod = @enumFromInt(field.value);
            if (@intFromEnum(kind) <= @intFromEnum(ContextMethod.getSystemPrompt)) {
                const name: [:0]const u8 = field.name;
                const function = try self.contextFunction(name, kind, snapshot, self.invocation_generation);
                const status = if (@intFromEnum(kind) <= @intFromEnum(ContextMethod.sessionManager)) property: {
                    const atom = c.JS_NewAtom(self.engine.context, name.ptr);
                    defer c.JS_FreeAtom(self.engine.context, atom);
                    break :property c.JS_DefinePropertyGetSet(self.engine.context, context, atom, function, c.pi_js_undefined(), c.JS_PROP_ENUMERABLE);
                } else c.JS_DefinePropertyValueStr(self.engine.context, context, name.ptr, function, c.JS_PROP_C_W_E);
                if (status < 0) return error.JavaScriptException;
            }
        }
        return context;
    }

    fn contextCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
        const engine = engine_mod.Engine.fromContext(context.?);
        const self: *Bindings = @ptrCast(@alignCast(engine.host_data orelse return c.JS_ThrowTypeError(context, "Native extension context is detached")));
        var generation: i64 = 0;
        if (c.JS_ToInt64(context, &generation, data[0]) < 0) return c.JS_Throw(context, c.JS_GetException(context));
        if (!self.invocation_active or generation != self.invocation_generation) return c.JS_ThrowTypeError(context, "Stale native extension context");
        const arguments: []c.JSValue = if (argc == 0) &.{} else argv[0..@intCast(argc)];
        return self.contextValue(@enumFromInt(magic), data[1], arguments) catch |err| c.JS_ThrowTypeError(context, "Native extension context failed: %s", @as([*:0]const u8, @errorName(err)));
    }

    fn contextValue(self: *Bindings, kind: ContextMethod, snapshot: c.JSValue, _: []c.JSValue) !c.JSValue {
        if (kind == .sessionManager) {
            const manager = try self.engine.checked(c.JS_NewObject(self.engine.context));
            errdefer self.engine.freeValue(manager);
            inline for (std.meta.fields(ContextMethod)) |field| {
                if (field.value >= @intFromEnum(ContextMethod.getCwd)) {
                    const name: [:0]const u8 = field.name;
                    const function = try self.contextFunction(name, @enumFromInt(field.value), snapshot, self.invocation_generation);
                    if (c.JS_DefinePropertyValueStr(self.engine.context, manager, name.ptr, function, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
                }
            }
            return manager;
        }
        const key: [*:0]const u8 = switch (kind) {
            .mode => "mode",
            .hasUI => "hasUI",
            .cwd, .getCwd => "cwd",
            .model => "model",
            .scopedModels => "scopedModels",
            .thinkingLevel => "thinkingLevel",
            .isIdle => "idle",
            .isProjectTrusted => "projectTrusted",
            .hasPendingMessages => "hasPendingMessages",
            .getContextUsage => "contextUsage",
            .getSystemPrompt => "systemPrompt",
            .getSessionDir => "sessionDir",
            .getSessionId => "sessionId",
            .getSessionFile => "sessionFile",
            .getSessionName => "sessionName",
            .getLeafId => "sessionLeafId",
            .getEntries => "sessionEntries",
            .getBranch, .buildContextEntries => "sessionBranch",
            .getHeader => "sessionHeader",
            .sessionManager => unreachable,
        };
        const value = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, snapshot, key));
        defer self.engine.freeValue(value);
        switch (kind) {
            .isIdle => return c.pi_js_bool(self.engine.context, @intFromBool(!c.JS_IsBool(value) or c.JS_ToBool(self.engine.context, value) == 1)),
            .hasUI, .isProjectTrusted, .hasPendingMessages => return c.pi_js_bool(self.engine.context, c.JS_ToBool(self.engine.context, value)),
            .mode => if (c.JS_IsUndefined(value)) return self.engine.checked(c.JS_NewString(self.engine.context, "print")),
            .thinkingLevel => if (c.JS_IsUndefined(value)) return self.engine.checked(c.JS_NewString(self.engine.context, "off")),
            .getSystemPrompt => if (c.JS_IsUndefined(value)) return self.engine.checked(c.JS_NewString(self.engine.context, "")),
            .cwd, .getCwd => if (c.JS_IsUndefined(value)) {
                const io = self.engine.native_io orelse return error.NativeContextCwdUnavailable;
                var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
                const length = try std.Io.Dir.cwd().realPath(io, &buffer);
                return self.engine.checked(c.JS_NewStringLen(self.engine.context, &buffer, length));
            },
            .scopedModels, .getEntries, .getBranch, .buildContextEntries => if (c.JS_IsUndefined(value)) return self.engine.checked(c.JS_NewArray(self.engine.context)),
            .getSessionDir, .getSessionFile, .getSessionName, .getLeafId, .getHeader => if (c.JS_IsNull(value)) return c.pi_js_undefined(),
            else => {},
        }
        if (c.JS_IsObject(value)) {
            const encoded = try self.engine.stringify(value);
            defer self.gpa.free(encoded);
            return self.parseJson(encoded, "extension-context-snapshot");
        }
        return c.JS_DupValue(self.engine.context, value);
    }

    pub fn setFlags(self: *Bindings, source: []const u8) !void {
        const overrides = try self.parseJson(source, "extension-flags");
        defer self.engine.freeValue(overrides);
        if (!c.JS_IsObject(overrides) or c.JS_IsArray(overrides)) return error.InvalidExtensionFlags;
        var names: [*c]c.JSPropertyEnum = null;
        var count: u32 = 0;
        if (c.JS_GetOwnPropertyNames(self.engine.context, &names, &count, overrides, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return error.JavaScriptException;
        defer c.JS_FreePropertyEnum(self.engine.context, names, count);
        self.freeTable(&self.flag_overrides);
        self.flag_overrides = .empty;
        for (0..count) |index| {
            const name = c.JS_AtomToCString(self.engine.context, names[index].atom);
            if (name == null) return error.OutOfMemory;
            defer c.JS_FreeCString(self.engine.context, name);
            const value = try self.engine.checked(c.JS_GetProperty(self.engine.context, overrides, names[index].atom));
            defer self.engine.freeValue(value);
            try self.store(&self.flag_overrides, std.mem.span(name), value);
        }
    }

    fn invokeHandlers(self: *Bindings, name: []const u8, event: c.JSValue, context: c.JSValue, result: c.JSValue) !void {
        const handlers = self.handlers.get(name) orelse return;
        for (handlers.items) |handler| {
            var args = [_]c.JSValue{ event, context };
            const promise = try self.engine.checked(c.JS_Call(self.engine.context, handler, c.pi_js_undefined(), args.len, &args));
            defer self.engine.freeValue(promise);
            const value = try self.engine.awaitValue(promise);
            defer self.engine.freeValue(value);
            if (!c.JS_IsObject(value) or c.JS_IsArray(value)) continue;
            var names: [*c]c.JSPropertyEnum = null;
            var count: u32 = 0;
            if (c.JS_GetOwnPropertyNames(self.engine.context, &names, &count, value, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return error.JavaScriptException;
            defer c.JS_FreePropertyEnum(self.engine.context, names, count);
            for (0..count) |index| {
                const property = try self.engine.checked(c.JS_GetProperty(self.engine.context, value, names[index].atom));
                if (c.JS_DefinePropertyValue(self.engine.context, result, names[index].atom, property, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
            }
        }
    }

    pub fn invokeHook(self: *Bindings, name: []const u8, payload_json: []const u8) ![]u8 {
        try self.beginActions();
        defer self.invocation_active = false;
        const event = try self.parseJson(payload_json, "extension-hook");
        defer self.engine.freeValue(event);
        const context = try self.createContext();
        defer self.engine.freeValue(context);
        const result = try self.engine.checked(c.JS_NewObject(self.engine.context));
        defer self.engine.freeValue(result);
        const type_value = try self.engine.checked(c.JS_NewStringLen(self.engine.context, name.ptr, name.len));
        if (c.JS_DefinePropertyValueStr(self.engine.context, event, "type", type_value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        try self.invokeHandlers(name, event, context, result);
        if (std.mem.eql(u8, name, "before_prompt")) {
            const input = try self.engine.checked(c.JS_NewObject(self.engine.context));
            defer self.engine.freeValue(input);
            const text = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, event, "prompt"));
            if (c.JS_DefinePropertyValueStr(self.engine.context, input, "text", text, c.JS_PROP_C_W_E) < 0 or
                c.JS_DefinePropertyValueStr(self.engine.context, input, "type", c.JS_NewString(self.engine.context, "input"), c.JS_PROP_C_W_E) < 0 or
                c.JS_DefinePropertyValueStr(self.engine.context, input, "source", c.JS_NewString(self.engine.context, "interactive"), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
            const transformed = try self.engine.checked(c.JS_NewObject(self.engine.context));
            defer self.engine.freeValue(transformed);
            try self.invokeHandlers("input", input, context, transformed);
            const action = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, transformed, "action"));
            defer self.engine.freeValue(action);
            const action_name = try self.engine.toString(action);
            defer self.gpa.free(action_name);
            if (std.mem.eql(u8, action_name, "transform")) {
                const replacement = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, transformed, "text"));
                if (c.JS_DefinePropertyValueStr(self.engine.context, result, "prompt", replacement, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
            } else if (std.mem.eql(u8, action_name, "handled")) {
                if (c.JS_DefinePropertyValueStr(self.engine.context, result, "handled", c.pi_js_bool(self.engine.context, 1), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
            }
        }
        try self.mergeActions(result);
        return self.engine.stringify(result);
    }

    pub fn invokeCommand(self: *Bindings, name: []const u8, raw: []const u8) ![]u8 {
        try self.beginActions();
        defer self.invocation_active = false;
        const options = self.commands.get(name) orelse return error.UnknownExtensionCommand;
        const handler = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, options, "handler"));
        defer self.engine.freeValue(handler);
        if (!c.JS_IsFunction(self.engine.context, handler)) return error.InvalidExtensionCommand;
        const arguments = try self.engine.checked(c.JS_NewStringLen(self.engine.context, raw.ptr, raw.len));
        defer self.engine.freeValue(arguments);
        const context = try self.createContext();
        defer self.engine.freeValue(context);
        var args = [_]c.JSValue{ arguments, context };
        const promise = try self.engine.checked(c.JS_Call(self.engine.context, handler, options, args.len, &args));
        defer self.engine.freeValue(promise);
        const result = try self.engine.awaitValue(promise);
        defer self.engine.freeValue(result);
        if (c.JS_IsObject(result)) {
            try self.mergeActions(result);
            return self.engine.stringify(result);
        }
        const empty = try self.engine.checked(c.JS_NewObject(self.engine.context));
        defer self.engine.freeValue(empty);
        try self.mergeActions(empty);
        return self.engine.stringify(empty);
    }

    fn projectValue(self: *Bindings, allocator: std.mem.Allocator, value: c.JSValue) !std.json.Value {
        const encoded = try self.engine.stringify(value);
        defer self.gpa.free(encoded);
        return std.json.parseFromSliceLeaky(std.json.Value, allocator, encoded, .{ .allocate = .alloc_always });
    }

    fn cleanSchema(value: *std.json.Value) void {
        switch (value.*) {
            .object => |*object| {
                _ = object.orderedRemove("__piOptional");
                var fields = object.iterator();
                while (fields.next()) |field| cleanSchema(field.value_ptr);
            },
            .array => |array| for (array.items) |*item| cleanSchema(item),
            else => {},
        }
    }

    fn functionProperty(self: *Bindings, value: c.JSValue, name: [*:0]const u8) !bool {
        const property = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, value, name));
        defer self.engine.freeValue(property);
        return c.JS_IsFunction(self.engine.context, property);
    }

    pub fn manifestJson(self: *Bindings, extension_path: []const u8) ![]u8 {
        var arena: std.heap.ArenaAllocator = .init(self.gpa);
        defer arena.deinit();
        const allocator = arena.allocator();
        var manifest: std.json.ObjectMap = .empty;
        try manifest.put(allocator, "name", .{ .string = std.fs.path.stem(extension_path) });
        try manifest.put(allocator, "version", .{ .string = "legacy-js" });
        try manifest.put(allocator, "entry", .{ .string = "" });
        var hook_names: std.ArrayList(std.json.Value) = .empty;
        var names = self.handlers.keyIterator();
        while (names.next()) |name| {
            const alias = if (std.mem.eql(u8, name.*, "input")) "before_prompt" else if (std.mem.eql(u8, name.*, "tool_call")) "before_tool" else if (std.mem.eql(u8, name.*, "tool_result")) "after_tool" else name.*;
            var duplicate = false;
            for (hook_names.items) |previous| if (std.mem.eql(u8, previous.string, alias)) {
                duplicate = true;
                break;
            };
            if (!duplicate) try hook_names.append(allocator, .{ .string = alias });
        }
        try manifest.put(allocator, "hooks", .{ .array = hook_names.toManaged(allocator) });
        var tools: std.ArrayList(std.json.Value) = .empty;
        var entries = self.tools.iterator();
        while (entries.next()) |entry| {
            const raw = try self.projectValue(allocator, entry.value_ptr.*);
            if (raw != .object) return error.InvalidExtensionTool;
            var tool: std.json.ObjectMap = .empty;
            try tool.put(allocator, "name", .{ .string = entry.key_ptr.* });
            try tool.put(allocator, "description", raw.object.get("description") orelse raw.object.get("label") orelse std.json.Value{ .string = "" });
            var schema = raw.object.get("parameters") orelse raw.object.get("inputSchema") orelse std.json.Value{ .object = .empty };
            cleanSchema(&schema);
            try tool.put(allocator, "parameters", schema);
            const mode = raw.object.get("executionMode") orelse std.json.Value{ .string = "parallel" };
            try tool.put(allocator, "executionMode", if (mode == .string and std.mem.eql(u8, mode.string, "sequential")) mode else std.json.Value{ .string = "parallel" });
            try tool.put(allocator, "hasRenderCall", .{ .bool = try self.functionProperty(entry.value_ptr.*, "renderCall") });
            try tool.put(allocator, "hasRenderResult", .{ .bool = try self.functionProperty(entry.value_ptr.*, "renderResult") });
            try tool.put(allocator, "hasPrepareArguments", .{ .bool = try self.functionProperty(entry.value_ptr.*, "prepareArguments") });
            const shell = raw.object.get("renderShell") orelse std.json.Value{ .string = "default" };
            try tool.put(allocator, "renderShell", if (shell == .string and std.mem.eql(u8, shell.string, "self")) shell else std.json.Value{ .string = "default" });
            try tools.append(allocator, .{ .object = tool });
        }
        try manifest.put(allocator, "tools", .{ .array = tools.toManaged(allocator) });
        var commands: std.ArrayList(std.json.Value) = .empty;
        entries = self.commands.iterator();
        while (entries.next()) |entry| {
            const raw = try self.projectValue(allocator, entry.value_ptr.*);
            if (raw != .object) return error.InvalidExtensionCommand;
            var command: std.json.ObjectMap = .empty;
            try command.put(allocator, "name", .{ .string = entry.key_ptr.* });
            try command.put(allocator, "description", raw.object.get("description") orelse std.json.Value{ .string = "" });
            if (raw.object.get("argumentHint")) |hint| try command.put(allocator, "argumentHint", hint);
            try commands.append(allocator, .{ .object = command });
        }
        try manifest.put(allocator, "commands", .{ .array = commands.toManaged(allocator) });
        var flags: std.ArrayList(std.json.Value) = .empty;
        entries = self.flags.iterator();
        while (entries.next()) |entry| {
            var projected = try self.projectValue(allocator, entry.value_ptr.*);
            if (projected != .object) return error.InvalidExtensionFlag;
            try projected.object.put(allocator, "name", .{ .string = entry.key_ptr.* });
            if (!projected.object.contains("description")) try projected.object.put(allocator, "description", .{ .string = "" });
            try flags.append(allocator, projected);
        }
        try manifest.put(allocator, "flags", .{ .array = flags.toManaged(allocator) });
        var output: std.Io.Writer.Allocating = .init(self.gpa);
        defer output.deinit();
        try std.json.Stringify.value(std.json.Value{ .object = manifest }, .{}, &output.writer);
        return output.toOwnedSlice();
    }

    pub fn invokeTool(self: *Bindings, name: []const u8, call_id: []const u8, args_json: []const u8) ![]u8 {
        try self.beginActions();
        defer self.invocation_active = false;
        const tool = self.tools.get(name) orelse return error.UnknownExtensionTool;
        const execute = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, tool, "execute"));
        defer self.engine.freeValue(execute);
        if (!c.JS_IsFunction(self.engine.context, execute)) return error.InvalidExtensionTool;
        const raw = try self.gpa.dupeZ(u8, args_json);
        defer self.gpa.free(raw);
        const args = try self.engine.checked(c.JS_ParseJSON(self.engine.context, raw.ptr, args_json.len, "tool-arguments"));
        defer self.engine.freeValue(args);
        const call = try self.engine.checked(c.JS_NewStringLen(self.engine.context, call_id.ptr, call_id.len));
        defer self.engine.freeValue(call);
        const context = try self.createContext();
        defer self.engine.freeValue(context);
        var parameters = [_]c.JSValue{ call, args, c.pi_js_undefined(), c.pi_js_undefined(), context };
        const promise = try self.engine.checked(c.JS_Call(self.engine.context, execute, tool, parameters.len, &parameters));
        defer self.engine.freeValue(promise);
        const result = try self.engine.awaitValue(promise);
        defer self.engine.freeValue(result);
        try self.mergeActions(result);
        return self.engine.stringify(result);
    }
};

test "native contexts clone snapshots and reject retained getters across invocation generations" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const bindings = try Bindings.init(std.testing.allocator, engine);
    defer bindings.deinit();
    try bindings.loadFactory("export default pi => { let previous; pi.registerTool({name:'context',execute(id,args,signal,update,ctx) { let stale=false; if(previous) {try { previous.cwd; } catch {stale=true;}} const copy=ctx.sessionManager.getEntries(); copy[0].data.value='mutated'; const pristine=ctx.sessionManager.getEntries()[0].data.value; previous=ctx; globalThis.retainedContext=ctx; return {details:{cwd:ctx.cwd,session:ctx.sessionManager.getSessionId(),model:ctx.model.id,trusted:ctx.isProjectTrusted(),idle:ctx.isIdle(),prompt:ctx.getSystemPrompt(),pristine,stale}}; }}); };", "context-fixture.js");
    try bindings.setContext("{\"cwd\":\"first\",\"sessionId\":\"session-one\",\"model\":{\"id\":\"fixture\"},\"projectTrusted\":true,\"idle\":false,\"systemPrompt\":\"native-prompt\",\"sessionEntries\":[{\"id\":\"entry\",\"data\":{\"value\":\"original\"}}]}");
    const first = try bindings.invokeTool("context", "call-one", "{}");
    defer std.testing.allocator.free(first);
    try std.testing.expect(std.mem.indexOf(u8, first, "\"pristine\":\"original\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, first, "\"trusted\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, first, "\"idle\":false") != null);
    try std.testing.expectError(error.JavaScriptException, engine.eval("retainedContext.cwd", "expired-context.js", c.JS_EVAL_TYPE_GLOBAL));
    engine.beginInvocation();
    try std.testing.expectError(error.InvalidExtensionContext, bindings.setContext("{\"projectTrusted\":\"true\"}"));
    const second = try bindings.invokeTool("context", "call-two", "{}");
    defer std.testing.allocator.free(second);
    try std.testing.expect(std.mem.indexOf(u8, second, "\"stale\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, second, "\"cwd\":\"first\"") != null);
    try std.testing.expectError(error.JavaScriptException, engine.eval("retainedContext.sessionManager.getEntries()", "expired-session.js", c.JS_EVAL_TYPE_GLOBAL));
}

test "native Pi factory registers typed tools commands flags and hooks then executes an async tool" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const bindings = try Bindings.init(std.testing.allocator, engine);
    defer bindings.deinit();
    try bindings.installSchemas();
    try bindings.loadFactory("import { Type } from 'typebox'; export default (pi) => { pi.registerFlag('ready', {type:'boolean', default:true}); pi.on('input', async event => ({action:'transform',text:event.text})); pi.registerCommand('hello', {handler: async () => ({text:'hello'})}); pi.registerTool({name:'echo', parameters:Type.Object({text:Type.String()}), async execute(id,args) { return {content:[{type:'text',text:id+':'+args.text}],details:{ready:pi.getFlag('ready')}}; }}); };", "native-factory.js");
    try std.testing.expectEqual(@as(usize, 1), bindings.tools.count());
    try std.testing.expectEqual(@as(usize, 1), bindings.commands.count());
    try std.testing.expectEqual(@as(usize, 1), bindings.handlers.count());
    const result = try bindings.invokeTool("echo", "call-1", "{\"text\":\"pi\"}");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "call-1:pi") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"ready\":true") != null);
    const manifest = try bindings.manifestJson("fixtures/native-factory.ts");
    defer std.testing.allocator.free(manifest);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, manifest, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("native-factory", parsed.value.object.get("name").?.string);
    try std.testing.expectEqualStrings("before_prompt", parsed.value.object.get("hooks").?.array.items[0].string);
    try std.testing.expectEqual(@as(usize, 1), parsed.value.object.get("tools").?.array.items.len);
}

test "native Pi registration rejects mismatched flag defaults" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const bindings = try Bindings.init(std.testing.allocator, engine);
    defer bindings.deinit();
    try std.testing.expectError(error.JavaScriptException, bindings.loadFactory("export default pi => pi.registerFlag('bad', {type:'boolean',default:'wrong'});", "invalid-flag.js"));
    try std.testing.expectEqual(@as(usize, 0), bindings.flags.count());
}

test "native hook aliases commands and flag overrides preserve extension callbacks" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const bindings = try Bindings.init(std.testing.allocator, engine);
    defer bindings.deinit();
    try bindings.loadFactory("export const extension = pi => { pi.registerFlag('suffix',{type:'string',default:'default'}); pi.on('input', async event => ({action:'transform',text:event.text+':'+pi.getFlag('suffix')})); pi.registerCommand('echo',{handler:async raw=>({messages:[raw]})}); };", "native-hook.js");
    try bindings.setFlags("{\"suffix\":\"override\"}");
    const hook = try bindings.invokeHook("before_prompt", "{\"prompt\":\"hello\"}");
    defer std.testing.allocator.free(hook);
    try std.testing.expect(std.mem.indexOf(u8, hook, "hello:override") != null);
    const command = try bindings.invokeCommand("echo", "literal --raw");
    defer std.testing.allocator.free(command);
    try std.testing.expect(std.mem.indexOf(u8, command, "literal --raw") != null);
}

test "native extension actions are ordered and rejected outside their invocation" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const bindings = try Bindings.init(std.testing.allocator, engine);
    defer bindings.deinit();
    try bindings.loadFactory("export default pi => pi.registerCommand('actions',{handler:()=>{pi.setSessionName('native');pi.appendEntry('marker',{value:42});pi.sendUserMessage('next',{deliverAs:'followUp'});}});", "actions.js");
    const result = try bindings.invokeCommand("actions", "");
    defer std.testing.allocator.free(result);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, result, .{});
    defer parsed.deinit();
    const queue = parsed.value.object.get("actionQueue").?.array;
    try std.testing.expectEqual(@as(usize, 3), queue.items.len);
    try std.testing.expectEqualStrings("set_session_name", queue.items[0].object.get("type").?.string);
    try std.testing.expectEqualStrings("append_entry", queue.items[1].object.get("type").?.string);
    try std.testing.expectEqualStrings("send_user_message", queue.items[2].object.get("type").?.string);
    try std.testing.expectError(error.JavaScriptException, bindings.loadFactory("export default pi=>pi.setSessionName('stale');", "stale.js"));
}
