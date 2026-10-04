//! Pi extension registrations and invocation owned by Zig through the C ABI.
const std = @import("std");
const engine_mod = @import("engine.zig");
const typebox = @import("typebox.zig");
const session_snapshot = @import("session_snapshot.zig");
const native_providers = @import("native_providers.zig");
const c = engine_mod.c;
const Method = enum(c_int) { on, registerTool, registerCommand, registerFlag, getFlag, registerProvider, unregisterProvider, getActiveTools, getAllTools, getCommands, getSettings, getSessionName, getThinkingLevel, setSessionName, setThinkingLevel, setActiveTools, sendUserMessage, appendEntry, setLabel };
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
    getLeafEntry,
    getEntry,
    getLabel,
    getTree,
    buildSessionProjection,
};

pub const Bindings = struct {
    gpa: std.mem.Allocator,
    engine: *engine_mod.Engine,
    api: c.JSValue,
    providers: native_providers.Providers,
    factory_active: bool = false,
    handlers: std.StringHashMapUnmanaged(std.ArrayList(c.JSValue)) = .empty,
    tools: std.StringHashMapUnmanaged(c.JSValue) = .empty,
    commands: std.StringHashMapUnmanaged(c.JSValue) = .empty,
    flags: std.StringHashMapUnmanaged(c.JSValue) = .empty,
    flag_overrides: std.StringHashMapUnmanaged(c.JSValue) = .empty,
    actions: std.ArrayList(c.JSValue) = .empty,
    invocation_active: bool = false,
    invocation_generation: u32 = 0,
    context_snapshot: ?c.JSValue = null,
    source_path: ?[]u8 = null,

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
        self.* = .{ .gpa = gpa, .engine = engine, .api = api, .providers = native_providers.Providers.init(engine) };
        engine.host_data = self;
        return self;
    }

    pub fn deinit(self: *Bindings) void {
        self.engine.host_data = null;
        self.providers.deinit();
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
        if (self.source_path) |path| self.gpa.free(path);
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
        if (@intFromEnum(method) >= @intFromEnum(Method.getActiveTools) and @intFromEnum(method) <= @intFromEnum(Method.getThinkingLevel)) return self.readonlyApi(method);
        if (args.len == 0) return error.MissingExtensionArgument;
        if (method == .registerProvider or method == .unregisterProvider) return self.providerRegistration(method, args);
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
                var handler_data = [_]c.JSValue{args[1]};
                const wrapper = try self.engine.checked(c.JS_NewCFunctionData(self.engine.context, forwardHandler, 2, 0, handler_data.len, &handler_data));
                defer self.engine.freeValue(wrapper);
                const event_name = try self.engine.checked(c.JS_NewStringLen(self.engine.context, name.ptr, name.len));
                defer self.engine.freeValue(event_name);
                var data = [_]c.JSValue{ event_name, wrapper };
                const unsubscribe = try self.engine.checked(c.JS_NewCFunctionData(self.engine.context, unsubscribeHandler, 0, 0, data.len, &data));
                errdefer self.engine.freeValue(unsubscribe);
                const entry = try self.handlers.getOrPut(self.gpa, name);
                if (!entry.found_existing) {
                    entry.key_ptr.* = self.gpa.dupe(u8, name) catch |err| {
                        _ = self.handlers.remove(name);
                        return err;
                    };
                    entry.value_ptr.* = .empty;
                }
                errdefer if (!entry.found_existing) {
                    const removed = self.handlers.fetchRemove(name).?;
                    var empty = removed.value;
                    empty.deinit(self.gpa);
                    self.gpa.free(removed.key);
                };
                const handler = c.JS_DupValue(self.engine.context, wrapper);
                errdefer self.engine.freeValue(handler);
                try entry.value_ptr.append(self.gpa, handler);
                return unsubscribe;
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

    fn providerRegistration(self: *Bindings, method: Method, args: []c.JSValue) !c.JSValue {
        if (!self.invocation_active and !self.factory_active) return error.StaleExtensionActionContext;
        const named = c.JS_IsString(args[0]);
        const name_value = if (method == .unregisterProvider or named)
            c.JS_DupValue(self.engine.context, args[0])
        else blk: {
            const id = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, args[0], "id"));
            if (!c.JS_IsNull(id) and !c.JS_IsUndefined(id)) break :blk id;
            self.engine.freeValue(id);
            break :blk try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, args[0], "name"));
        };
        defer self.engine.freeValue(name_value);
        if (c.JS_IsNull(name_value) or c.JS_IsUndefined(name_value)) return error.InvalidNativeProviderName;
        const name = try self.engine.toString(name_value);
        defer self.gpa.free(name);
        if (name.len == 0) return error.InvalidNativeProviderName;
        if (method == .registerProvider and named and args.len < 2) return error.MissingExtensionArgument;
        const action = try self.engine.checked(c.JS_NewObject(self.engine.context));
        defer self.engine.freeValue(action);
        const kind = if (method == .registerProvider) "register_provider" else "unregister_provider";
        try self.actionProperty(action, "type", try self.engine.fromJsonValue(.{ .string = kind }));
        try self.actionProperty(action, "name", try self.engine.fromJsonValue(.{ .string = name }));
        // Reserve an owned queue slot before registration can invoke user getters.
        // Remove the placeholder before publishing, preserving nested action order.
        const reservation = if (self.invocation_active) self.actions.items.len else null;
        if (reservation != null) {
            const retained = c.JS_DupValue(self.engine.context, action);
            errdefer self.engine.freeValue(retained);
            try self.actions.append(self.gpa, retained);
        }
        var published = false;
        defer if (!published) if (reservation) |index| self.engine.freeValue(self.actions.orderedRemove(index));
        if (method == .registerProvider) try self.actionProperty(action, "config", c.pi_js_undefined());
        if (method == .registerProvider) {
            const config = if (named) args[1] else args[0];
            const encoded = try self.providers.register(name, config, !named);
            if (c.JS_SetPropertyStr(self.engine.context, action, "config", encoded) < 0) return error.JavaScriptException;
        } else self.providers.unregister(name);
        if (reservation) |index| {
            const retained = self.actions.orderedRemove(index);
            self.actions.appendAssumeCapacity(retained);
        }
        published = true;
        return c.pi_js_undefined();
    }

    fn actionProperty(self: *Bindings, object: c.JSValue, key: [*:0]const u8, value: c.JSValue) !void {
        if (c.JS_DefinePropertyValueStr(self.engine.context, object, key, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }

    fn cloneValue(self: *Bindings, value: c.JSValue) !c.JSValue {
        if (!c.JS_IsObject(value)) return c.JS_DupValue(self.engine.context, value);
        const json = try self.engine.stringify(value);
        defer self.gpa.free(json);
        return self.parseJson(json, "native-extension-copy");
    }

    fn readonlyApi(self: *Bindings, method: Method) !c.JSValue {
        if (method == .getAllTools or method == .getCommands) return self.catalogApi(method);
        const key: [*:0]const u8 = switch (method) {
            .getActiveTools => "activeTools",
            .getSettings => "settings",
            .getSessionName => "sessionName",
            .getThinkingLevel => "thinkingLevel",
            else => unreachable,
        };
        if (self.invocation_active and method != .getSettings) {
            const action_type: []const u8 = switch (method) {
                .getActiveTools => "set_active_tools",
                .getSessionName => "set_session_name",
                .getThinkingLevel => "set_thinking_level",
                else => unreachable,
            };
            var index = self.actions.items.len;
            while (index > 0) {
                index -= 1;
                const action = self.actions.items[index];
                const kind = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, action, "type"));
                defer self.engine.freeValue(kind);
                const name = try self.engine.toString(kind);
                defer self.gpa.free(name);
                if (!std.mem.eql(u8, name, action_type)) continue;
                const field: [*:0]const u8 = switch (method) {
                    .getActiveTools => "names",
                    .getSessionName => "name",
                    .getThinkingLevel => "level",
                    else => unreachable,
                };
                const value = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, action, field));
                defer self.engine.freeValue(value);
                return self.cloneValue(value);
            }
        }
        const value = if (self.context_snapshot) |snapshot| try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, snapshot, key)) else c.pi_js_undefined();
        defer self.engine.freeValue(value);
        if (c.JS_IsUndefined(value) or c.JS_IsNull(value)) return switch (method) {
            .getActiveTools => self.engine.checked(c.JS_NewArray(self.engine.context)),
            .getSettings => self.engine.checked(c.JS_NewObject(self.engine.context)),
            .getThinkingLevel => self.engine.checked(c.JS_NewString(self.engine.context, "off")),
            .getSessionName => c.pi_js_undefined(),
            else => unreachable,
        };
        return self.cloneValue(value);
    }

    fn catalogApi(self: *Bindings, method: Method) !c.JSValue {
        var arena = std.heap.ArenaAllocator.init(self.gpa);
        defer arena.deinit();
        const allocator = arena.allocator();
        var values: std.json.Array = .init(allocator);
        if (self.context_snapshot) |snapshot| {
            const key: [*:0]const u8 = if (method == .getAllTools) "allTools" else "commands";
            const current = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, snapshot, key));
            defer self.engine.freeValue(current);
            if (c.JS_IsArray(current)) {
                const projected = try self.projectValue(allocator, current);
                for (projected.array.items) |item| try values.append(item);
            }
        }
        var entries = (if (method == .getAllTools) &self.tools else &self.commands).iterator();
        while (entries.next()) |entry| {
            const raw = try self.projectValue(allocator, entry.value_ptr.*);
            if (raw != .object) return error.InvalidNativeCatalogRegistration;
            var object: std.json.ObjectMap = .empty;
            try object.put(allocator, "name", .{ .string = entry.key_ptr.* });
            try object.put(allocator, "description", raw.object.get("description") orelse raw.object.get("label") orelse std.json.Value{ .string = "" });
            try object.put(allocator, "source", .{ .string = "extension" });
            var source: std.json.ObjectMap = .empty;
            try source.put(allocator, "path", .{ .string = self.source_path orelse "" });
            try object.put(allocator, "sourceInfo", .{ .object = source });
            if (method == .getAllTools) {
                var schema = raw.object.get("parameters") orelse raw.object.get("inputSchema") orelse std.json.Value{ .object = .empty };
                cleanSchema(&schema);
                try object.put(allocator, "parameters", schema);
                for ([_][]const u8{ "promptSnippet", "promptGuidelines", "exposure", "label" }) |field| if (raw.object.get(field)) |value| try object.put(allocator, field, value);
            } else if (raw.object.get("argumentHint")) |hint| try object.put(allocator, "argumentHint", hint);
            var replaced = false;
            for (values.items) |*item| {
                if (item.* != .object) return error.InvalidNativeCatalogSnapshot;
                const name = item.object.get("name") orelse return error.InvalidNativeCatalogSnapshot;
                if (name != .string) return error.InvalidNativeCatalogSnapshot;
                if (std.mem.eql(u8, name.string, entry.key_ptr.*)) {
                    item.* = .{ .object = object };
                    replaced = true;
                    break;
                }
            }
            if (!replaced) try values.append(.{ .object = object });
        }
        const json = try std.json.Stringify.valueAlloc(allocator, std.json.Value{ .array = values }, .{});
        return self.parseJson(json, "native-extension-catalog");
    }

    fn forwardHandler(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
        return c.JS_Call(context, data[0], c.pi_js_undefined(), argc, argv);
    }

    fn unsubscribeHandler(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
        const engine = engine_mod.Engine.fromContext(context.?);
        const self: *Bindings = @ptrCast(@alignCast(engine.host_data orelse return c.pi_js_undefined()));
        const name = engine.toString(data[0]) catch |err| {
            if (err == error.JavaScriptException) return engine.throwCaptured();
            return c.JS_ThrowOutOfMemory(context);
        };
        defer self.gpa.free(name);
        const handlers = self.handlers.getPtr(name) orelse return c.pi_js_undefined();
        for (handlers.items, 0..) |handler, index| {
            if (c.JS_IsStrictEqual(context, handler, data[1])) {
                engine.freeValue(handlers.orderedRemove(index));
                if (handlers.items.len == 0) {
                    const entry = self.handlers.fetchRemove(name).?;
                    var empty = entry.value;
                    empty.deinit(self.gpa);
                    self.gpa.free(entry.key);
                }
                break;
            }
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
        const args: []c.JSValue = if (argc == 0) &.{} else argv[0..@intCast(argc)];
        return self.registration(@enumFromInt(magic), args) catch |err| {
            if (err == error.JavaScriptException) return engine.throwCaptured();
            return c.JS_ThrowTypeError(context, "Native extension registration failed: %s", @as([*:0]const u8, @errorName(err)));
        };
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
        try self.setSourcePath(filename);
        const namespace = try self.engine.evalModule(source, filename);
        defer self.engine.freeValue(namespace);
        try self.loadFactoryValue(namespace);
    }

    pub fn setSourcePath(self: *Bindings, path: []const u8) !void {
        const owned = try self.gpa.dupe(u8, path);
        if (self.source_path) |previous| self.gpa.free(previous);
        self.source_path = owned;
    }

    pub fn loadFactoryValue(self: *Bindings, namespace: c.JSValue) !void {
        if (self.factory_active) return error.ExtensionInvocationBusy;
        self.factory_active = true;
        defer self.factory_active = false;
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
        inline for (.{ "scopedModels", "sessionEntries", "sessionBranch", "activeTools", "allTools", "commands" }) |name| {
            const value = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, snapshot, name));
            defer self.engine.freeValue(value);
            if (!c.JS_IsUndefined(value) and !c.JS_IsArray(value)) return error.InvalidExtensionContext;
        }
        const settings = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, snapshot, "settings"));
        defer self.engine.freeValue(settings);
        if (!c.JS_IsUndefined(settings) and (!c.JS_IsObject(settings) or c.JS_IsArray(settings))) return error.InvalidExtensionContext;
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
        return self.contextValue(@enumFromInt(magic), data[1], arguments) catch |err| {
            if (err == error.JavaScriptException) return engine.throwCaptured();
            return c.JS_ThrowTypeError(context, "Native extension context failed: %s", @as([*:0]const u8, @errorName(err)));
        };
    }

    fn contextValue(self: *Bindings, kind: ContextMethod, snapshot: c.JSValue, args: []c.JSValue) !c.JSValue {
        if (kind == .getLeafEntry or kind == .getEntry or kind == .getLabel or kind == .getBranch or kind == .buildContextEntries or kind == .getTree or kind == .buildSessionProjection) return self.sessionApi(kind, snapshot, args);
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
            .sessionManager, .getLeafEntry, .getEntry, .getLabel, .getTree, .buildSessionProjection => unreachable,
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
                var directory = try std.Io.Dir.cwd().openDir(io, ".", .{});
                defer directory.close(io);
                var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
                const length = try directory.realPath(io, &buffer);
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

    fn sessionApi(self: *Bindings, kind: ContextMethod, snapshot: c.JSValue, args: []c.JSValue) !c.JSValue {
        var arena = std.heap.ArenaAllocator.init(self.gpa);
        defer arena.deinit();
        const allocator = arena.allocator();
        const root = try self.projectValue(allocator, snapshot);
        const session = try session_snapshot.Snapshot.init(allocator, root);
        if (kind == .getTree) return self.sessionTree(allocator, &session);
        if (kind == .buildSessionProjection) {
            const projection = try session.projection(.{ .context = self, .parse = parseSessionTime });
            return self.engine.fromJsonValue(projection);
        }
        var explicit_id: ?[]u8 = null;
        defer if (explicit_id) |id| self.gpa.free(id);
        if (args.len > 0 and c.JS_IsString(args[0])) explicit_id = try self.engine.toString(args[0]);
        if (kind == .getLabel) {
            const id = explicit_id orelse return c.pi_js_undefined();
            const name = session.label(id) orelse return c.pi_js_undefined();
            return self.engine.checked(c.JS_NewStringLen(self.engine.context, name.ptr, name.len));
        }
        const value = switch (kind) {
            .getLeafEntry => session.entry(session.leaf),
            .getEntry => session.entry(explicit_id),
            .getBranch => branch: {
                const id = if (args.len == 0 or c.JS_IsUndefined(args[0]) or c.JS_IsNull(args[0])) session.leaf else explicit_id;
                break :branch try session.branch(id);
            },
            .buildContextEntries => try session.contextEntries(),
            else => unreachable,
        } orelse return c.pi_js_undefined();
        const json = try std.json.Stringify.valueAlloc(allocator, value, .{});
        return self.parseJson(json, "native-session-snapshot");
    }

    fn parseSessionTime(context: ?*anyopaque, timestamp: []const u8) anyerror!f64 {
        const self: *Bindings = @ptrCast(@alignCast(context.?));
        const global = c.JS_GetGlobalObject(self.engine.context);
        defer self.engine.freeValue(global);
        const date = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, global, "Date"));
        defer self.engine.freeValue(date);
        const parse = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, date, "parse"));
        defer self.engine.freeValue(parse);
        var argument = [_]c.JSValue{try self.engine.checked(c.JS_NewStringLen(self.engine.context, timestamp.ptr, timestamp.len))};
        defer self.engine.freeValue(argument[0]);
        const value = try self.engine.checked(c.JS_Call(self.engine.context, parse, date, 1, &argument));
        defer self.engine.freeValue(value);
        var milliseconds: f64 = 0;
        if (c.JS_ToFloat64(self.engine.context, &milliseconds, value) < 0) return error.JavaScriptException;
        return milliseconds;
    }

    fn sessionTree(self: *Bindings, allocator: std.mem.Allocator, session: *const session_snapshot.Snapshot) !c.JSValue {
        const parents = try session.parents();
        const children = try allocator.alloc(std.ArrayList(usize), session.entries.len);
        for (children) |*list| list.* = .empty;
        for (parents, 0..) |parent, index| if (parent) |position| try children[position].append(allocator, index);
        const times = try allocator.alloc(f64, session.entries.len);
        const global = c.JS_GetGlobalObject(self.engine.context);
        defer self.engine.freeValue(global);
        const date = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, global, "Date"));
        defer self.engine.freeValue(date);
        const parse_date = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, date, "parse"));
        defer self.engine.freeValue(parse_date);
        for (session.entries, times) |entry, *time| {
            const timestamp = session_snapshot.Snapshot.text(entry, "timestamp") orelse "";
            var argument = [_]c.JSValue{try self.engine.checked(c.JS_NewStringLen(self.engine.context, timestamp.ptr, timestamp.len))};
            defer self.engine.freeValue(argument[0]);
            const result = try self.engine.checked(c.JS_Call(self.engine.context, parse_date, date, 1, &argument));
            defer self.engine.freeValue(result);
            if (c.JS_ToFloat64(self.engine.context, time, result) < 0) return error.JavaScriptException;
        }
        for (children) |*list| std.mem.sort(usize, list.items, times, struct {
            fn lessThan(timestamps: []const f64, left: usize, right: usize) bool {
                if (!std.math.isFinite(timestamps[left]) or !std.math.isFinite(timestamps[right])) return false;
                return timestamps[left] < timestamps[right];
            }
        }.lessThan);
        const nodes = try allocator.alloc(c.JSValue, session.entries.len);
        var initialized: usize = 0;
        defer for (nodes[0..initialized]) |node| self.engine.freeValue(node);
        for (session.entries, nodes) |entry, *node| {
            node.* = try self.engine.checked(c.JS_NewObject(self.engine.context));
            initialized += 1;
            const entry_json = try std.json.Stringify.valueAlloc(allocator, entry, .{});
            const entry_copy = try self.parseJson(entry_json, "native-session-tree-entry");
            if (c.JS_DefinePropertyValueStr(self.engine.context, node.*, "entry", entry_copy, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
            const descendants = try self.engine.checked(c.JS_NewArray(self.engine.context));
            if (c.JS_DefinePropertyValueStr(self.engine.context, node.*, "children", descendants, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
            if (c.JS_DefinePropertyValueStr(self.engine.context, node.*, "label", c.pi_js_undefined(), c.JS_PROP_C_W_E) < 0 or c.JS_DefinePropertyValueStr(self.engine.context, node.*, "labelTimestamp", c.pi_js_undefined(), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
            const id = session_snapshot.Snapshot.text(entry, "id").?;
            if (session.label(id)) |label| {
                const text = try self.engine.checked(c.JS_NewStringLen(self.engine.context, label.ptr, label.len));
                if (c.JS_DefinePropertyValueStr(self.engine.context, node.*, "label", text, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
                var timestamp: ?[]const u8 = null;
                for (session.entries) |candidate| {
                    const kind = session_snapshot.Snapshot.text(candidate, "type") orelse continue;
                    const target = session_snapshot.Snapshot.text(candidate, "targetId") orelse continue;
                    if (std.mem.eql(u8, kind, "label") and std.mem.eql(u8, id, target)) timestamp = session_snapshot.Snapshot.text(candidate, "timestamp");
                }
                if (timestamp) |value| {
                    const string = try self.engine.checked(c.JS_NewStringLen(self.engine.context, value.ptr, value.len));
                    if (c.JS_DefinePropertyValueStr(self.engine.context, node.*, "labelTimestamp", string, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
                }
            }
        }
        const roots = try self.engine.checked(c.JS_NewArray(self.engine.context));
        errdefer self.engine.freeValue(roots);
        var root_index: u32 = 0;
        for (nodes, parents, children) |node, parent, descendants| {
            if (parent == null) {
                if (c.JS_SetPropertyUint32(self.engine.context, roots, root_index, c.JS_DupValue(self.engine.context, node)) < 0) return error.JavaScriptException;
                root_index += 1;
            }
            const list = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, node, "children"));
            defer self.engine.freeValue(list);
            for (descendants.items, 0..) |index, child_index| if (c.JS_SetPropertyUint32(self.engine.context, list, @intCast(child_index), c.JS_DupValue(self.engine.context, nodes[index])) < 0) return error.JavaScriptException;
        }
        return roots;
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
        const snapshot = try self.gpa.alloc(c.JSValue, handlers.items.len);
        defer self.gpa.free(snapshot);
        for (snapshot, handlers.items) |*slot, handler| slot.* = c.JS_DupValue(self.engine.context, handler);
        defer for (snapshot) |handler| self.engine.freeValue(handler);
        for (snapshot) |handler| {
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
        const registered_providers = try self.providers.manifest();
        defer self.engine.freeValue(registered_providers);
        try manifest.put(allocator, "providers", try self.projectValue(allocator, registered_providers));
        var output: std.Io.Writer.Allocating = .init(self.gpa);
        defer output.deinit();
        try std.json.Stringify.value(std.json.Value{ .object = manifest }, .{}, &output.writer);
        return output.toOwnedSlice();
    }

    pub fn invokeProviderMethod(self: *Bindings, id: []const u8, args_json: []const u8) ![]u8 {
        try self.beginActions();
        defer self.invocation_active = false;
        const args = try self.parseJson(args_json, "native-provider-arguments");
        defer self.engine.freeValue(args);
        const value = try self.providers.invoke(id, args);
        defer self.engine.freeValue(value);
        const result = try self.engine.checked(c.JS_NewObjectProto(self.engine.context, c.pi_js_null()));
        defer self.engine.freeValue(result);
        try self.actionProperty(result, "value", c.JS_DupValue(self.engine.context, value));
        try self.mergeActions(result);
        return self.engine.stringify(result);
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

test "native subscriptions return independent idempotent removers and dispatch snapshots" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const bindings = try Bindings.init(std.testing.allocator, engine);
    defer bindings.deinit();
    try bindings.loadFactory(
        "export default pi=>{let sharedCalls=0;const shared=()=>({calls:++sharedCalls});const removeOne=pi.on('shared',shared);const removeTwo=pi.on('shared',shared);if(typeof removeOne!=='function')throw Error('unsubscribe');removeOne();removeOne();" ++
            "let calls=[],added=false,removeSecond;pi.on('mutate',()=>{calls=['first'];removeSecond();if(!added){added=true;pi.on('mutate',()=>{calls.push('late');return {order:calls.slice()};});}return {order:calls.slice()};});removeSecond=pi.on('mutate',()=>{calls.push('second');return {order:calls.slice()};});" ++
            "pi.registerCommand('remove',{handler:()=>{removeTwo();removeTwo();return {};}});};",
        "native-subscriptions.mjs",
    );
    const shared = try bindings.invokeHook("shared", "{}");
    defer engine.gpa.free(shared);
    try std.testing.expectEqualStrings("{\"calls\":1}", shared);
    const first = try bindings.invokeHook("mutate", "{}");
    defer engine.gpa.free(first);
    try std.testing.expectEqualStrings("{\"order\":[\"first\",\"second\"]}", first);
    const next = try bindings.invokeHook("mutate", "{}");
    defer engine.gpa.free(next);
    try std.testing.expectEqualStrings("{\"order\":[\"first\",\"late\"]}", next);
    const removed = try bindings.invokeCommand("remove", "");
    defer engine.gpa.free(removed);
    try std.testing.expect(!bindings.handlers.contains("shared"));
}

test "native readonly API catalogs settings and action updates are copied without exposing registrations" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const bindings = try Bindings.init(std.testing.allocator, engine);
    defer bindings.deinit();
    try bindings.loadFactory(
        "export default pi=>{if(pi.getActiveTools().length||pi.getAllTools().length||pi.getCommands().length||pi.getThinkingLevel()!=='off')throw Error('initial API');" ++
            "pi.registerTool({name:'read',description:'extension read',parameters:{type:'object',properties:{value:{type:'string',__piOptional:true}}},execute(){return {content:'read'}}});" ++
            "pi.registerCommand('inspect',{description:'native inspection',handler:()=>{const tools=pi.getAllTools(),settings=pi.getSettings(),commands=pi.getCommands();const own=tools.find(t=>t.name==='read');if(own.description!=='extension read'||own.parameters.properties.value.__piOptional!==undefined||own.source!=='extension')throw Error('tool projection');own.parameters.type='changed';settings.nested.value=9;commands[0].name='changed';if(pi.getAllTools().find(t=>t.name==='read').parameters.type!=='object'||pi.getSettings().nested.value!==1||pi.getCommands().some(c=>c.name==='changed'))throw Error('snapshot mutation');" ++
            "if(pi.getSessionName()!=='initial'||pi.getThinkingLevel()!=='low')throw Error('initial metadata');pi.setSessionName('updated');pi.setThinkingLevel('high');pi.setActiveTools([]);return {name:pi.getSessionName(),level:pi.getThinkingLevel(),active:pi.getActiveTools(),tools:pi.getAllTools().map(t=>t.name),path:pi.getCommands().find(c=>c.name==='inspect').sourceInfo.path};}});};",
        "native-api-catalog.mjs",
    );
    try bindings.setContext("{\"activeTools\":[\"read\"],\"allTools\":[{\"name\":\"read\",\"description\":\"builtin read\"},{\"name\":\"builtin\"}],\"commands\":[{\"name\":\"builtin-command\"}],\"settings\":{\"nested\":{\"value\":1}},\"sessionName\":\"initial\",\"thinkingLevel\":\"low\"}");
    const result = try bindings.invokeCommand("inspect", "");
    defer engine.gpa.free(result);
    var parsed = try std.json.parseFromSlice(std.json.Value, engine.gpa, result, .{});
    defer parsed.deinit();
    const object = parsed.value.object;
    try std.testing.expectEqualStrings("updated", object.get("name").?.string);
    try std.testing.expectEqualStrings("high", object.get("level").?.string);
    try std.testing.expectEqual(@as(usize, 0), object.get("active").?.array.items.len);
    try std.testing.expectEqual(@as(usize, 2), object.get("tools").?.array.items.len);
    try std.testing.expectEqualStrings("native-api-catalog.mjs", object.get("path").?.string);
}

test "native context cwd fallback resolves a real directory and remains invocation guarded" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const bindings = try Bindings.init(std.testing.allocator, engine);
    defer bindings.deinit();
    try bindings.loadFactory("export default pi=>pi.registerTool({name:'cwd',execute(id,args,signal,update,ctx){return {details:{cwd:ctx.cwd,again:ctx.sessionManager.getCwd()}};}});", "native-cwd.mjs");
    const result = try bindings.invokeTool("cwd", "call", "{}");
    defer engine.gpa.free(result);
    var parsed = try std.json.parseFromSlice(std.json.Value, engine.gpa, result, .{});
    defer parsed.deinit();
    const cwd = parsed.value.object.get("details").?.object.get("cwd").?.string;
    const again = parsed.value.object.get("details").?.object.get("again").?.string;
    try std.testing.expect(std.fs.path.isAbsolute(cwd));
    try std.testing.expectEqualStrings(cwd, again);
}

test "native session manager entry lookups explicit branches and compaction views retain context guards" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const bindings = try Bindings.init(std.testing.allocator, engine);
    defer bindings.deinit();
    try bindings.loadFactory(
        "export default pi=>pi.registerTool({name:'session',execute(id,args,signal,update,ctx){const manager=ctx.sessionManager;globalThis.retainedSession=manager;const entry=manager.getEntry('kept');entry.message.content='changed';if(manager.getEntry('kept').message.content!=='original'||manager.getEntry('absent')!==undefined)throw Error('entry lookup/copy');return {details:{leaf:manager.getLeafEntry().id,label:manager.getLabel('tail'),explicit:manager.getBranch('kept').map(e=>e.id),branch:manager.getBranch().map(e=>e.id),context:manager.buildContextEntries().map(e=>e.id)}};}});",
        "native-session-api.mjs",
    );
    try bindings.setContext(
        "{\"sessionLeafId\":\"tail\",\"sessionEntries\":[" ++
            "{\"id\":\"old\",\"parentId\":null,\"type\":\"message\",\"message\":{\"role\":\"user\"}}," ++
            "{\"id\":\"system\",\"parentId\":\"old\",\"type\":\"message\",\"message\":{\"role\":\"system\"}}," ++
            "{\"id\":\"kept\",\"parentId\":\"system\",\"type\":\"message\",\"message\":{\"role\":\"assistant\",\"content\":\"original\"}}," ++
            "{\"id\":\"compacted\",\"parentId\":\"kept\",\"type\":\"compaction\",\"firstKeptEntryId\":\"old\"}," ++
            "{\"id\":\"tail\",\"parentId\":\"compacted\",\"type\":\"message\"}," ++
            "{\"id\":\"label\",\"parentId\":\"tail\",\"type\":\"label\",\"targetId\":\"tail\",\"label\":\"bookmark\"}]}",
    );
    const result = try bindings.invokeTool("session", "call", "{}");
    defer engine.gpa.free(result);
    var parsed = try std.json.parseFromSlice(std.json.Value, engine.gpa, result, .{});
    defer parsed.deinit();
    const details = parsed.value.object.get("details").?.object;
    try std.testing.expectEqualStrings("tail", details.get("leaf").?.string);
    try std.testing.expectEqualStrings("bookmark", details.get("label").?.string);
    try std.testing.expectEqual(@as(usize, 3), details.get("explicit").?.array.items.len);
    try std.testing.expectEqual(@as(usize, 5), details.get("branch").?.array.items.len);
    try std.testing.expectEqual(@as(usize, 4), details.get("context").?.array.items.len);
    try std.testing.expectEqualStrings("compacted", details.get("context").?.array.items[0].string);
    const guarded = try engine.eval("let blocked=false;try{retainedSession.getEntry('old')}catch{blocked=true}if(!blocked)throw Error('stale session manager');", "native-stale-session.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(guarded);
}

test "native session trees retain orphans self roots label timestamps and chronological children" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const bindings = try Bindings.init(std.testing.allocator, engine);
    defer bindings.deinit();
    try bindings.loadFactory(
        "export default pi=>pi.registerTool({name:'tree',execute(id,args,signal,update,ctx){const first=ctx.sessionManager.getTree();if(first.length!==3||first[0].children[0].entry.id!=='early'||first[0].children[1].entry.id!=='late'||first[0].children[1].label!=='bookmark'||first[0].children[1].labelTimestamp!=='2026-01-04T00:00:00Z')throw Error('tree structure/order/labels');first[0].entry.id='changed';if(ctx.sessionManager.getTree()[0].entry.id!=='root')throw Error('tree mutation');return {content:'native-tree'};}});",
        "native-tree.mjs",
    );
    try bindings.setContext(
        "{\"sessionEntries\":[" ++
            "{\"id\":\"root\",\"parentId\":null,\"timestamp\":\"2026-01-01T00:00:00Z\"}," ++
            "{\"id\":\"late\",\"parentId\":\"root\",\"timestamp\":\"2026-01-03T00:00:00Z\"}," ++
            "{\"id\":\"early\",\"parentId\":\"root\",\"timestamp\":\"2026-01-02T00:00:00Z\"}," ++
            "{\"id\":\"label\",\"parentId\":\"root\",\"type\":\"label\",\"targetId\":\"late\",\"label\":\"bookmark\",\"timestamp\":\"2026-01-04T00:00:00Z\"}," ++
            "{\"id\":\"orphan\",\"parentId\":\"absent\"},{\"id\":\"self\",\"parentId\":\"self\"}]}",
    );
    const result = try bindings.invokeTool("tree", "call", "{}");
    defer engine.gpa.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "native-tree") != null);
    try bindings.setContext("{\"sessionEntries\":[{\"id\":\"a\",\"parentId\":\"b\"},{\"id\":\"b\",\"parentId\":\"a\"}]}");
    try std.testing.expectError(error.JavaScriptException, bindings.invokeTool("tree", "call", "{}"));
    try std.testing.expect(std.mem.indexOf(u8, engine.last_error.?, "SessionParentCycle") != null);
}

test "native failed subscription allocations do not leave a hidden event registration" {
    var failed_count: usize = 0;
    for (0..8) |offset| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const engine = try engine_mod.Engine.init(failing.allocator(), .{});
        defer engine.deinit();
        const bindings = try Bindings.init(failing.allocator(), engine);
        defer bindings.deinit();
        const event = try engine.checked(c.JS_NewString(engine.context, "allocation-event"));
        defer engine.freeValue(event);
        const callback = try engine.eval("(event)=>({})", "allocation-callback.js", c.JS_EVAL_TYPE_GLOBAL);
        defer engine.freeValue(callback);
        var args = [_]c.JSValue{ event, callback };
        failing.fail_index = failing.alloc_index + offset;
        const remove = bindings.registration(.on, &args) catch |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            failed_count += 1;
            try std.testing.expect(!bindings.handlers.contains("allocation-event"));
            continue;
        };
        engine.freeValue(remove);
        break;
    }
    try std.testing.expect(failed_count >= 4);
}

test "native session projections retain provenance checkpoints edits metadata and invalid timestamps" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const bindings = try Bindings.init(std.testing.allocator, engine);
    defer bindings.deinit();
    try bindings.loadFactory(
        "export default pi=>pi.registerTool({name:'projection',execute(id,args,signal,update,ctx){const projection=ctx.sessionManager.buildSessionProjection();if(projection.thinkingLevel!=='high'||projection.model.provider!=='p1'||projection.model.modelId!=='a1'||projection.messages.length!==4)throw Error('projection state');const roles=projection.messages.map(m=>m.role);if(roles.join(',')!=='system,compactionSummary,assistant,custom')throw Error('projection messages');const assistant=projection.messages[2];if(assistant.content[0].text!=='edited'||assistant.usage.input!==7||assistant.toolCalls[0].id!=='call')throw Error('metadata/edit');const source=projection.entries.find(e=>e.sourceEntry.id==='assistant').sourceEntry;if(source.message.content[0].text!=='original')throw Error('provenance mutated');if(projection.entries.find(e=>e.sourceEntry.id==='older-compaction').messages.length!==0||projection.entries.find(e=>e.sourceEntry.id==='tool').messages.length!==0)throw Error('old compaction/omission');if(!Number.isNaN(projection.messages[3].timestamp))throw Error('invalid timestamp replaced');assistant.usage.input=99;if(ctx.sessionManager.buildSessionProjection().messages[2].usage.input!==7)throw Error('projection mutable source');return {content:'native-projection'};}});",
        "native-projection.mjs",
    );
    try bindings.setContext(
        "{\"sessionLeafId\":\"edit-tool\",\"sessionEntries\":[" ++
            "{\"id\":\"model\",\"parentId\":null,\"type\":\"model_change\",\"provider\":\"p0\",\"modelId\":\"m0\"}," ++
            "{\"id\":\"thinking\",\"parentId\":\"model\",\"type\":\"thinking_level_change\",\"thinkingLevel\":\"high\"}," ++
            "{\"id\":\"user\",\"parentId\":\"thinking\",\"type\":\"message\",\"message\":{\"role\":\"user\",\"content\":null}}," ++
            "{\"id\":\"older-compaction\",\"parentId\":\"user\",\"type\":\"compaction\",\"firstKeptEntryId\":\"user\",\"summary\":\"old\"}," ++
            "{\"id\":\"assistant\",\"parentId\":\"older-compaction\",\"type\":\"message\",\"message\":{\"role\":\"assistant\",\"provider\":\"p1\",\"model\":\"a1\",\"content\":[{\"type\":\"text\",\"text\":\"original\"}],\"usage\":{\"input\":7},\"toolCalls\":[{\"id\":\"call\"}]}}," ++
            "{\"id\":\"tool\",\"parentId\":\"assistant\",\"type\":\"message\",\"message\":{\"role\":\"toolResult\",\"content\":[{\"type\":\"text\",\"text\":\"tool\"}]}}," ++
            "{\"id\":\"custom\",\"parentId\":\"tool\",\"type\":\"custom_message\",\"customType\":\"fixture\",\"content\":\"custom\",\"display\":true,\"timestamp\":\"invalid\"}," ++
            "{\"id\":\"new-compaction\",\"parentId\":\"custom\",\"type\":\"compaction\",\"firstKeptEntryId\":\"older-compaction\",\"summary\":\"new\",\"tokensBefore\":42,\"timestamp\":\"2026-01-01T00:00:00Z\",\"systemMessage\":{\"role\":\"system\",\"content\":\"checkpoint\"}}," ++
            "{\"id\":\"edit-assistant\",\"parentId\":\"new-compaction\",\"type\":\"context_edit\",\"targetId\":\"assistant\",\"replacement\":{\"content\":\"edited\"}}," ++
            "{\"id\":\"edit-tool\",\"parentId\":\"edit-assistant\",\"type\":\"context_edit\",\"targetId\":\"tool\",\"replacement\":null}]}",
    );
    const result = try bindings.invokeTool("projection", "call", "{}");
    defer engine.gpa.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "native-projection") != null);
}

test "native provider manifest retains callbacks receivers merging and unregister lifecycle" {
    const gpa = std.testing.allocator;
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    const bindings = try Bindings.init(gpa, engine);
    defer bindings.deinit();
    try bindings.loadFactory(
        "export default function(pi){const closure='native-closure';const cfg={name:'Original',baseUrl:'https://provider.invalid/v1',api:'openai-completions',models:[{id:'m',name:'M'}],oauth:{owner:'oauth-owner',async getApiKey(credentials){if(this.owner!=='oauth-owner')throw Error('receiver');return closure+':'+credentials.access}},nested:{methods:[function(value){return this.length+':'+value}]}};pi.registerProvider('demo',cfg);pi.registerProvider('demo',{name:'Renamed',baseUrl:undefined});pi.registerCommand('bad',{handler(){const cycle={};cycle.self=cycle;try{pi.registerProvider('demo',cycle)}catch{} }});pi.registerCommand('retire',{handler(){pi.unregisterProvider('demo')}});}",
        "native-provider-registration.mjs",
    );
    const initial = try bindings.manifestJson("native-provider-registration.mjs");
    defer gpa.free(initial);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, initial, .{});
    defer parsed.deinit();
    const providers = parsed.value.object.get("providers").?.array.items;
    try std.testing.expectEqual(@as(usize, 1), providers.len);
    const config = providers[0].object.get("config").?.object;
    try std.testing.expectEqualStrings("Renamed", config.get("name").?.string);
    try std.testing.expectEqualStrings("https://provider.invalid/v1", config.get("baseUrl").?.string);
    const key_ref = try @import("provider_method_ref.zig").ProviderMethodRef.fromJson(config.get("oauth").?.object.get("getApiKey").?);
    try std.testing.expectEqualStrings("oauth.getApiKey", key_ref.path);
    const result = try bindings.invokeProviderMethod(key_ref.callback_id, "[{\"access\":\"token\"}]");
    defer gpa.free(result);
    try std.testing.expectEqualStrings("{\"value\":\"native-closure:token\"}", result);
    const array_ref = try @import("provider_method_ref.zig").ProviderMethodRef.fromJson(config.get("nested").?.object.get("methods").?.array.items[0]);
    try std.testing.expectEqualStrings("nested.methods.0", array_ref.path);
    const array_result = try bindings.invokeProviderMethod(array_ref.callback_id, "[\"value\"]");
    defer gpa.free(array_result);
    try std.testing.expectEqualStrings("{\"value\":\"1:value\"}", array_result);
    const rejected = try bindings.invokeCommand("bad", "");
    defer gpa.free(rejected);
    const after_bad = try bindings.manifestJson("native-provider-registration.mjs");
    defer gpa.free(after_bad);
    try std.testing.expectEqualStrings(initial, after_bad);
    const retired = try bindings.invokeCommand("retire", "");
    defer gpa.free(retired);
    try std.testing.expect(std.mem.indexOf(u8, retired, "unregister_provider") != null);
    try std.testing.expectError(error.UnknownNativeProviderCallback, bindings.invokeProviderMethod(key_ref.callback_id, "[]"));
    const empty = try bindings.providers.manifest();
    defer engine.freeValue(empty);
    const empty_json = try engine.stringify(empty);
    defer gpa.free(empty_json);
    try std.testing.expectEqualStrings("[]", empty_json);
}

test "native provider callback can unregister itself without invalidating its receiver" {
    const gpa = std.testing.allocator;
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    const bindings = try Bindings.init(gpa, engine);
    defer bindings.deinit();
    try bindings.loadFactory("export default function(pi){pi.registerProvider({id:'self-retire',name:'Self',nested:{owner:'retained',retire(){pi.unregisterProvider('self-retire');return this.owner}}})}", "native-provider-retire.mjs");
    const manifest = try bindings.manifestJson("native-provider-retire.mjs");
    defer gpa.free(manifest);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, manifest, .{});
    defer parsed.deinit();
    const nested = parsed.value.object.get("providers").?.array.items[0].object.get("config").?.object.get("nested").?.object;
    const reference = try @import("provider_method_ref.zig").ProviderMethodRef.fromJson(nested.get("retire").?);
    const result = try bindings.invokeProviderMethod(reference.callback_id, "[]");
    defer gpa.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"value\":\"retained\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "unregister_provider") != null);
    try std.testing.expectError(error.UnknownNativeProviderCallback, bindings.invokeProviderMethod(reference.callback_id, "[]"));
}

test "native provider getters preserve exceptions and nested action order" {
    const gpa = std.testing.allocator;
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    const bindings = try Bindings.init(gpa, engine);
    defer bindings.deinit();
    try bindings.loadFactory("export default function(pi){pi.registerProvider('demo',{name:'Stable'});pi.registerCommand('nested',{handler(){pi.registerProvider('demo',{get name(){pi.setSessionName('nested-first');return 'Changed'}})}});pi.registerCommand('throw',{handler(){const original=new Error('getter');let caught=false;try{pi.registerProvider('demo',{get name(){throw original}})}catch(error){if(error!==original)throw Error('exception replaced');caught=true}if(!caught)throw Error('getter not called')}})}", "native-provider-getters.mjs");
    const result = try bindings.invokeCommand("nested", "");
    defer gpa.free(result);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, result, .{});
    defer parsed.deinit();
    const queue = parsed.value.object.get("actionQueue").?.array.items;
    try std.testing.expectEqual(@as(usize, 2), queue.len);
    try std.testing.expectEqualStrings("set_session_name", queue[0].object.get("type").?.string);
    try std.testing.expectEqualStrings("register_provider", queue[1].object.get("type").?.string);
    const failed = try bindings.invokeCommand("throw", "");
    defer gpa.free(failed);
    try std.testing.expect(std.mem.indexOf(u8, failed, "register_provider") == null);
    const manifest = try bindings.manifestJson("native-provider-getters.mjs");
    defer gpa.free(manifest);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "Changed") != null);
}
