//! Owner VM registry publication. Extension code, schema symbols and callbacks retain identity.
const std = @import("std");
const engine_mod = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const durable = @import("native_durable.zig");
const Engine = engine_mod.Engine;
const c = engine_mod.c;
const Registry = struct { engine: *Engine, current: c.JSValue, builtins: c.JSValue, listeners: std.ArrayList(c.JSValue) = .empty };
const Snapshot = struct { engine: *Engine, extensions: c.JSValue, tasks: c.JSValue, by_name: c.JSValue, by_task: c.JSValue };
const Operation = enum(c_int) { snapshot, subscribe, install, uninstall, installed, extension, tools, sections, tasks, task };
fn registry(engine: *Engine, value: c.JSValue) !*Registry {
    return @ptrCast(@alignCast(c.JS_GetOpaque2(engine.context, value, engine.native_durable_registry_class) orelse return error.InvalidNativeRegistry));
}
fn snapshot(engine: *Engine, value: c.JSValue) !*Snapshot {
    return @ptrCast(@alignCast(c.JS_GetOpaque2(engine.context, value, engine.native_durable_registry_snapshot_class) orelse return error.InvalidRegistrySnapshot));
}
fn registryFinalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const engine: *Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const self: *Registry = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_durable_registry_class) orelse return));
    c.JS_FreeValueRT(runtime, self.current);
    c.JS_FreeValueRT(runtime, self.builtins);
    for (self.listeners.items) |listener| c.JS_FreeValueRT(runtime, listener);
    self.listeners.deinit(engine.gpa);
    engine.gpa.destroy(self);
}
fn registryMark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const engine: *Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const self: *Registry = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_durable_registry_class) orelse return));
    c.JS_MarkValue(runtime, self.current, marker);
    c.JS_MarkValue(runtime, self.builtins, marker);
    for (self.listeners.items) |listener| c.JS_MarkValue(runtime, listener, marker);
}
fn snapshotFinalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const engine: *Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const self: *Snapshot = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_durable_registry_snapshot_class) orelse return));
    c.JS_FreeValueRT(runtime, self.extensions);
    c.JS_FreeValueRT(runtime, self.tasks);
    c.JS_FreeValueRT(runtime, self.by_name);
    c.JS_FreeValueRT(runtime, self.by_task);
    engine.gpa.destroy(self);
}
fn snapshotMark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const engine: *Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const self: *Snapshot = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_durable_registry_snapshot_class) orelse return));
    c.JS_MarkValue(runtime, self.extensions, marker);
    c.JS_MarkValue(runtime, self.tasks, marker);
    c.JS_MarkValue(runtime, self.by_name, marker);
    c.JS_MarkValue(runtime, self.by_task, marker);
}
fn classes(engine: *Engine) !void {
    if (engine.native_durable_registry_class == 0) _ = c.JS_NewClassID(engine.runtime, &engine.native_durable_registry_class);
    if (engine.native_durable_registry_snapshot_class == 0) _ = c.JS_NewClassID(engine.runtime, &engine.native_durable_registry_snapshot_class);
    const registry_definition: c.JSClassDef = .{ .class_name = "Native durable Registry", .finalizer = registryFinalizer, .gc_mark = registryMark, .call = null, .exotic = null };
    const snapshot_definition: c.JSClassDef = .{ .class_name = "Native Registry snapshot", .finalizer = snapshotFinalizer, .gc_mark = snapshotMark, .call = null, .exotic = null };
    if (!c.JS_IsRegisteredClass(engine.runtime, engine.native_durable_registry_class) and c.JS_NewClass(engine.runtime, engine.native_durable_registry_class, &registry_definition) < 0) return error.OutOfMemory;
    if (!c.JS_IsRegisteredClass(engine.runtime, engine.native_durable_registry_snapshot_class) and c.JS_NewClass(engine.runtime, engine.native_durable_registry_snapshot_class, &snapshot_definition) < 0) return error.OutOfMemory;
}
fn methods(engine: *Engine, object: c.JSValue, operations: []const Operation) !void {
    for (operations) |operation| {
        const name = try engine.gpa.dupeZ(u8, @tagName(operation));
        defer engine.gpa.free(name);
        const callback = try engine.checked(c.pi_js_function_magic(engine.context, method, name.ptr, 1, @intFromEnum(operation)));
        if (c.JS_DefinePropertyValueStr(engine.context, object, name.ptr, callback, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
    }
}
/// Builtin task tokens must be supplied by the native builtin port, never synthesized metadata.
pub fn create(engine: *Engine, builtins: c.JSValue) !c.JSValue {
    try classes(engine);
    const extensions = try sdk.array(engine);
    defer engine.freeValue(extensions);
    const initial = try makeSnapshot(engine, builtins, extensions);
    errdefer engine.freeValue(initial);
    const object = try engine.checked(c.JS_NewObjectClass(engine.context, engine.native_durable_registry_class));
    errdefer engine.freeValue(object);
    try methods(engine, object, &.{ .snapshot, .subscribe, .install, .uninstall });
    const self = try engine.gpa.create(Registry);
    self.* = .{ .engine = engine, .current = initial, .builtins = c.JS_DupValue(engine.context, builtins) };
    _ = c.JS_SetOpaque(object, self);
    return object;
}
pub fn install(engine: *Engine, exports: c.JSValue, builtins: c.JSValue) !void {
    var data = [_]c.JSValue{builtins};
    try sdk.put(engine, exports, "createRegistry", try engine.checked(c.JS_NewCFunctionData(engine.context, factory, 0, 0, 1, &data)));
}
fn factory(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return create(engine, data[0]) catch |err| durable.reject(engine, err);
}
pub fn installHelpers(engine: *Engine, exports: c.JSValue) !void {
    inline for (.{ "defineExtension", "defineTool", "section", "hook", "wrapTool", "wrapSection" }, 0..) |name, operation| try sdk.put(engine, exports, name, try engine.checked(c.pi_js_function_magic(engine.context, helper, name, 3, @intCast(operation))));
}
fn helper(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return helperOwned(engine, argv[0..@intCast(argc)], operation) catch |err| durable.reject(engine, err);
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn helperOwned(engine: *Engine, args: []const c.JSValue, operation: c_int) !c.JSValue {
    if (operation < 2) return c.JS_DupValue(engine.context, arg(args, 0));
    const object = try sdk.object(engine);
    errdefer engine.freeValue(object);
    if (operation == 2) {
        try sdk.put(engine, object, "key", c.JS_DupValue(engine.context, arg(args, 0)));
        try sdk.put(engine, object, "render", c.JS_DupValue(engine.context, arg(args, 1)));
        if (!c.JS_IsUndefined(arg(args, 2)) and !c.JS_IsNull(arg(args, 2))) {
            const tag = try sdk.get(engine, args[2], "tag");
            defer engine.freeValue(tag);
            if (!c.JS_IsUndefined(tag)) try sdk.put(engine, object, "tag", c.JS_DupValue(engine.context, tag));
        }
    } else if (operation == 3) {
        const name = try taskName(engine, arg(args, 0));
        try sdk.put(engine, object, "task", name);
        try sdk.put(engine, object, "handlers", c.JS_DupValue(engine.context, arg(args, 1)));
    } else {
        const name = if (operation == 4) try sdk.get(engine, arg(args, 0), "name") else c.JS_DupValue(engine.context, arg(args, 0));
        try sdk.put(engine, object, if (operation == 4) "tool" else "section", name);
        try sdk.put(engine, object, "wrap", c.JS_DupValue(engine.context, arg(args, 1)));
    }
    return object;
}
fn makeSnapshot(engine: *Engine, builtins: c.JSValue, extensions: c.JSValue) !c.JSValue {
    const by_name = try map(engine);
    defer engine.freeValue(by_name);
    const by_task = try map(engine);
    defer engine.freeValue(by_task);
    const tasks = try sdk.array(engine);
    defer engine.freeValue(tasks);
    for (0..try sdk.length(engine, builtins)) |index| {
        const task = try engine.checked(c.JS_GetPropertyUint32(engine.context, builtins, @intCast(index)));
        defer engine.freeValue(task);
        const name = try taskName(engine, task);
        defer engine.freeValue(name);
        const inserted = try sdk.invoke(engine, by_task, "set", &.{ name, task });
        engine.freeValue(inserted);
        try sdk.append(engine, tasks, c.JS_DupValue(engine.context, task));
    }
    for (0..try sdk.length(engine, extensions)) |index| {
        const extension = try engine.checked(c.JS_GetPropertyUint32(engine.context, extensions, @intCast(index)));
        defer engine.freeValue(extension);
        const extension_name = try sdk.get(engine, extension, "name");
        defer engine.freeValue(extension_name);
        const inserted_extension = try sdk.invoke(engine, by_name, "set", &.{ extension_name, extension });
        engine.freeValue(inserted_extension);
        const declared = try sdk.get(engine, extension, "tasks");
        defer engine.freeValue(declared);
        if (c.JS_IsUndefined(declared)) continue;
        for (0..try sdk.length(engine, declared)) |at| {
            const task = try engine.checked(c.JS_GetPropertyUint32(engine.context, declared, @intCast(at)));
            defer engine.freeValue(task);
            const name = try taskName(engine, task);
            defer engine.freeValue(name);
            for (0..try sdk.length(engine, tasks)) |prior_index| {
                const prior = try engine.checked(c.JS_GetPropertyUint32(engine.context, tasks, @intCast(prior_index)));
                defer engine.freeValue(prior);
                const prior_name = try taskName(engine, prior);
                defer engine.freeValue(prior_name);
                if (c.JS_IsStrictEqual(engine.context, name, prior_name)) {
                    const task_text = try engine.toString(name);
                    defer engine.gpa.free(task_text);
                    const extension_text = try engine.toString(extension_name);
                    defer engine.gpa.free(extension_text);
                    try message(engine, false, "Task {s} of extension {s} is already installed", .{ task_text, extension_text });
                }
            }
            try sdk.append(engine, tasks, c.JS_DupValue(engine.context, task));
            const inserted = try sdk.invoke(engine, by_task, "set", &.{ name, task });
            engine.freeValue(inserted);
        }
    }
    const object = try engine.checked(c.JS_NewObjectClass(engine.context, engine.native_durable_registry_snapshot_class));
    errdefer engine.freeValue(object);
    try methods(engine, object, &.{ .installed, .extension, .tools, .sections, .tasks, .task });
    const self = try engine.gpa.create(Snapshot);
    self.* = .{ .engine = engine, .extensions = c.JS_DupValue(engine.context, extensions), .tasks = c.JS_DupValue(engine.context, tasks), .by_name = c.JS_DupValue(engine.context, by_name), .by_task = c.JS_DupValue(engine.context, by_task) };
    _ = c.JS_SetOpaque(object, self);
    return object;
}
fn map(engine: *Engine) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const constructor = try sdk.get(engine, global, "Map");
    defer engine.freeValue(constructor);
    return engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null));
}
fn taskName(engine: *Engine, task: c.JSValue) !c.JSValue {
    const definition = try sdk.get(engine, task, "definition");
    defer engine.freeValue(definition);
    return sdk.get(engine, definition, "name");
}
fn method(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return dispatch(engine, receiver, @enumFromInt(operation), if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| durable.reject(engine, err);
}
fn dispatch(engine: *Engine, receiver: c.JSValue, operation: Operation, argument: c.JSValue) !c.JSValue {
    if (operation == .snapshot or operation == .subscribe or operation == .install or operation == .uninstall) {
        const self = try registry(engine, receiver);
        if (operation == .snapshot) return c.JS_DupValue(engine.context, self.current);
        if (operation == .subscribe) {
            var data = [_]c.JSValue{ receiver, argument };
            const cancel = try engine.checked(c.JS_NewCFunctionData(engine.context, unsubscribe, 0, 0, 2, &data));
            errdefer engine.freeValue(cancel);
            for (self.listeners.items) |previous| if (c.JS_IsStrictEqual(engine.context, previous, argument)) return cancel;
            try self.listeners.ensureUnusedCapacity(engine.gpa, 1);
            self.listeners.appendAssumeCapacity(c.JS_DupValue(engine.context, argument));
            return cancel;
        }
        if (operation == .install) try validate(engine, argument);
        const current = try snapshot(engine, self.current);
        const name = try sdk.get(engine, argument, "name");
        defer engine.freeValue(name);
        const next = try sdk.array(engine);
        defer engine.freeValue(next);
        var found = false;
        for (0..try sdk.length(engine, current.extensions)) |index| {
            const item = try engine.checked(c.JS_GetPropertyUint32(engine.context, current.extensions, @intCast(index)));
            defer engine.freeValue(item);
            const item_name = try sdk.get(engine, item, "name");
            defer engine.freeValue(item_name);
            if (c.JS_IsStrictEqual(engine.context, name, item_name)) {
                found = true;
                if (operation == .install) try sdk.append(engine, next, c.JS_DupValue(engine.context, argument));
            } else try sdk.append(engine, next, c.JS_DupValue(engine.context, item));
        }
        if (operation == .uninstall and !found) return c.pi_js_undefined();
        if (operation == .install and !found) try sdk.append(engine, next, c.JS_DupValue(engine.context, argument));
        const published = try makeSnapshot(engine, self.builtins, next);
        var adopted = false;
        errdefer if (!adopted) engine.freeValue(published);
        const listeners = try engine.gpa.dupe(c.JSValue, self.listeners.items);
        defer engine.gpa.free(listeners);
        for (listeners) |*value| value.* = c.JS_DupValue(engine.context, value.*);
        defer for (listeners) |value| engine.freeValue(value);
        engine.freeValue(self.current);
        self.current = published;
        adopted = true;
        for (listeners) |listener| {
            const returned = try engine.checked(c.JS_Call(engine.context, listener, c.pi_js_undefined(), 0, null));
            engine.freeValue(returned);
        }
        return c.pi_js_undefined();
    }
    const self = try snapshot(engine, receiver);
    if (operation == .installed) return c.JS_DupValue(engine.context, self.extensions);
    if (operation == .extension) return sdk.invoke(engine, self.by_name, "get", &.{argument});
    if (operation == .task) return sdk.invoke(engine, self.by_task, "get", &.{argument});
    const result = try sdk.array(engine);
    errdefer engine.freeValue(result);
    if (operation == .tasks or operation == .task) {
        for (0..try sdk.length(engine, self.tasks)) |index| {
            const task = try engine.checked(c.JS_GetPropertyUint32(engine.context, self.tasks, @intCast(index)));
            defer engine.freeValue(task);
            if (operation == .tasks) try sdk.append(engine, result, c.JS_DupValue(engine.context, task)) else {
                const name = try taskName(engine, task);
                defer engine.freeValue(name);
                if (c.JS_IsStrictEqual(engine.context, name, argument)) {
                    engine.freeValue(result);
                    return c.JS_DupValue(engine.context, task);
                }
            }
        }
        if (operation == .tasks) return result;
    } else for (0..try sdk.length(engine, self.extensions)) |index| {
        const extension = try engine.checked(c.JS_GetPropertyUint32(engine.context, self.extensions, @intCast(index)));
        defer engine.freeValue(extension);
        if (operation == .extension) {
            const name = try sdk.get(engine, extension, "name");
            defer engine.freeValue(name);
            if (c.JS_IsStrictEqual(engine.context, name, argument)) {
                engine.freeValue(result);
                return c.JS_DupValue(engine.context, extension);
            }
            continue;
        }
        const items = try sdk.get(engine, extension, if (operation == .tools) "tools" else "sections");
        defer engine.freeValue(items);
        if (c.JS_IsUndefined(items)) continue;
        for (0..try sdk.length(engine, items)) |at| {
            const item = try engine.checked(c.JS_GetPropertyUint32(engine.context, items, @intCast(at)));
            defer engine.freeValue(item);
            const pair = try sdk.object(engine);
            errdefer engine.freeValue(pair);
            try sdk.put(engine, pair, "extension", c.JS_DupValue(engine.context, extension));
            try sdk.put(engine, pair, if (operation == .tools) "tool" else "section", c.JS_DupValue(engine.context, item));
            try sdk.append(engine, result, pair);
        }
    }
    if (operation == .tools or operation == .sections) return result;
    engine.freeValue(result);
    return c.pi_js_undefined();
}
fn unsubscribe(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const self = registry(engine, data[0]) catch |err| return durable.reject(engine, err);
    for (self.listeners.items, 0..) |value, index| if (c.JS_IsStrictEqual(engine.context, value, data[1])) {
        engine.freeValue(self.listeners.orderedRemove(index));
        return c.pi_js_bool(context, 1);
    };
    return c.pi_js_bool(context, 0);
}
fn validate(engine: *Engine, extension: c.JSValue) !void {
    inline for (.{ "tools", "sections" }, 0..) |property, section| {
        const items = try sdk.get(engine, extension, property);
        defer engine.freeValue(items);
        const count = if (c.JS_IsUndefined(items)) 0 else try sdk.length(engine, items);
        for (0..count) |index| {
            const item = try engine.checked(c.JS_GetPropertyUint32(engine.context, items, @intCast(index)));
            defer engine.freeValue(item);
            const name = try sdk.get(engine, item, if (section == 0) "name" else "key");
            defer engine.freeValue(name);
            const text = try engine.toString(name);
            defer engine.gpa.free(text);
            if (section == 1) {
                var valid = text.len > 0 and text[0] >= 'a' and text[0] <= 'z';
                for (text) |byte| if (!(byte >= 'a' and byte <= 'z') and !(byte >= '0' and byte <= '9') and byte != '_' and byte != '-') {
                    valid = false;
                };
                if (!valid) {
                    const encoded_value = try engine.stringify(name);
                    defer engine.gpa.free(encoded_value);
                    try message(engine, true, "Section key {s} must match /^[a-z][a-z0-9_-]*$/", .{encoded_value});
                }
                if (std.mem.eql(u8, text, "instructions")) try message(engine, false, "Section key {s} is reserved for the agent's instructions", .{text});
            }
            for (0..index) |prior_index| {
                const prior = try engine.checked(c.JS_GetPropertyUint32(engine.context, items, @intCast(prior_index)));
                defer engine.freeValue(prior);
                const prior_name = try sdk.get(engine, prior, if (section == 0) "name" else "key");
                defer engine.freeValue(prior_name);
                if (c.JS_IsStrictEqual(engine.context, name, prior_name)) {
                    const extension_name = try sdk.get(engine, extension, "name");
                    defer engine.freeValue(extension_name);
                    const owner = try engine.toString(extension_name);
                    defer engine.gpa.free(owner);
                    try message(engine, false, if (section == 0) "Extension {s} has two tools named {s}" else "Extension {s} has two sections with key {s}", .{ owner, text });
                }
            }
        }
    }
}
fn message(engine: *Engine, type_error: bool, comptime format: []const u8, args: anytype) !void {
    const text = try std.fmt.allocPrint(engine.gpa, format, args);
    defer engine.gpa.free(text);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const constructor = try sdk.get(engine, global, if (type_error) "TypeError" else "Error");
    defer engine.freeValue(constructor);
    const value = try sdk.text(engine, text);
    defer engine.freeValue(value);
    var values = [_]c.JSValue{value};
    const failure = try engine.checked(c.JS_CallConstructor(engine.context, constructor, 1, &values));
    _ = try engine.checked(c.JS_Throw(engine.context, failure));
}

fn allocationExercise(gpa: std.mem.Allocator) !void {
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    const builtins = try sdk.array(engine);
    defer engine.freeValue(builtins);
    const object = try create(engine, builtins);
    defer engine.freeValue(object);
    const extension = try engine.eval("({name:'fixture',tools:[{name:'tool',parameters:{type:'object'},execute(){}}],sections:[{key:'section',render(){}}],tasks:[{definition:{name:'fixture-task',version:1,initial(){return{phase:'go'}},phases:{go(){}},abort(){}}}]})", "registry-user-extension-fixture", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(extension);
    const installed = try dispatch(engine, object, .install, extension);
    engine.freeValue(installed);
    const published = try dispatch(engine, object, .snapshot, c.pi_js_undefined());
    defer engine.freeValue(published);
    const tools = try dispatch(engine, published, .tools, c.pi_js_undefined());
    defer engine.freeValue(tools);
    const sections = try dispatch(engine, published, .sections, c.pi_js_undefined());
    defer engine.freeValue(sections);
    const removed = try dispatch(engine, object, .uninstall, extension);
    engine.freeValue(removed);
}
test "native durable VM registry snapshots callback resources and candidate admission unwind every GPA failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationExercise, .{});
}
