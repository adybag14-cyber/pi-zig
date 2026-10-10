//! Factory-owned builtin execution. Workers carry owned native input and I/O;
//! only the owner VM observes signals, emits updates, and settles promises.
const std = @import("std");
const engine_mod = @import("engine.zig");
const Engine = engine_mod.Engine;
const c = engine_mod.c;
const vm = @import("native_values.zig");
const sdk = @import("native_sdk.zig");
const templates = @import("native_sdk_tools.zig");
const tools = @import("../agent/tools.zig");
const native_tools = @import("../durable/tools.zig");
const native_env = @import("../durable/execution_env.zig");
const native_shell = @import("native_sdk_builtin_shell.zig");
const a = std.heap.page_allocator;
pub const Options = struct { auto_resize: bool = true, shell_path: ?[]const u8 = null, command_prefix: ?[]const u8 = null };
const OwnedOptions = struct {
    shell_path: ?[]u8 = null,
    command_prefix: ?[]u8 = null,
    fn copy(gpa: std.mem.Allocator, options: Options) !OwnedOptions {
        const path = if (options.shell_path) |text| try gpa.dupe(u8, text) else null;
        errdefer if (path) |text| gpa.free(text);
        return .{ .shell_path = path, .command_prefix = if (options.command_prefix) |text| try gpa.dupe(u8, text) else null };
    }
    fn deinit(self: *OwnedOptions, gpa: std.mem.Allocator) void {
        if (self.shell_path) |text| gpa.free(text);
        if (self.command_prefix) |text| gpa.free(text);
    }
};
const Factory = struct { engine: *Engine, cwd: []u8, io: ?std.Io, index: usize, auto_resize: bool, options: OwnedOptions, operations: ?c.JSValue = null };
const Job = struct {
    io: std.Io,
    cwd: []u8,
    input: []u8,
    index: usize,
    auto_resize: bool,
    environment: std.process.Environ.Map,
    options: OwnedOptions,
    structured_json: ?[]u8 = null,
    reject_result: bool = true,
    emit_updates: bool,
    progress_gate: @import("../durable/output_window.zig").ProgressGate = .{ .bytesPerSecond = 0 },
    signal: c.JSValue,
    on_update: c.JSValue,
    resolve: c.JSValue,
    reject: c.JSValue,
    failure: ?c.JSValue = null,
    abort_flag: bool = false,
    finished: std.atomic.Value(bool) = .init(false),
    thread: ?std.Thread = null,
    result: ?tools.ToolResult = null,
    native_error: ?anyerror = null,
    updates: std.ArrayList([]u8) = .empty,
    mutex: std.Io.Mutex = .init,
    notify_context: ?*anyopaque,
    notify: ?*const fn (?*anyopaque) void,

    fn run(self: *Job) void {
        if (@atomicLoad(bool, &self.abort_flag, .acquire)) {
            self.result = .{ .content = a.dupe(u8, if (std.mem.eql(u8, templates.names[self.index], "bash") or std.mem.eql(u8, templates.names[self.index], "powershell")) "Command aborted" else "Operation aborted") catch {
                self.native_error = error.OutOfMemory;
                self.finished.store(true, .release);
                if (self.notify) |notify| notify(self.notify_context);
                return;
            }, .is_error = true };
            self.finished.store(true, .release);
            if (self.notify) |notify| notify(self.notify_context);
            return;
        }
        self.result = self.executeNative() catch |err| blk: {
            self.native_error = err;
            break :blk null;
        };
        self.finished.store(true, .release);
        if (self.notify) |notify| notify(self.notify_context);
    }
    fn executeNative(self: *Job) !tools.ToolResult {
        const name = templates.names[self.index];
        if (std.mem.eql(u8, name, "read")) return @import("native_sdk_builtin_read.zig").execute(.{ .gpa = a, .io = self.io, .cwd = self.cwd, .environ = &self.environment, .auto_resize_images = self.auto_resize, .abort_flag = &self.abort_flag }, self.input);
        if (std.mem.eql(u8, name, "ls")) return @import("native_sdk_builtin_listing.zig").execute(a, self.io, self.cwd, self.input, &self.environment, .{ .abort_flag = @ptrCast(&self.abort_flag) });
        if (std.mem.eql(u8, name, "grep")) return @import("native_sdk_builtin_search.zig").grep(.{ .gpa = a, .io = self.io, .cwd = self.cwd, .environ = &self.environment, .abort_flag = &self.abort_flag }, self.input);
        if (std.mem.eql(u8, name, "find")) return @import("native_sdk_builtin_search.zig").find(.{ .gpa = a, .io = self.io, .cwd = self.cwd, .environ = &self.environment, .abort_flag = &self.abort_flag }, self.input);
        if (std.mem.eql(u8, name, "bash") or std.mem.eql(u8, name, "powershell")) {
            const response = try native_shell.execute(a, self.io, self.cwd, name, self.input, &self.environment, .{ .shell_path = self.options.shell_path, .command_prefix = self.options.command_prefix }, @ptrCast(&self.abort_flag), if (self.emit_updates) progress else null, self);
            self.structured_json = response.structured_json;
            self.reject_result = response.reject_result;
            return response.result;
        }
        if (!std.mem.eql(u8, name, "write") and !std.mem.eql(u8, name, "edit")) return tools.execute(.{ .gpa = a, .io = self.io, .cwd = self.cwd, .environ = &self.environment, .auto_resize_images = self.auto_resize, .abort_flag = &self.abort_flag, .progress_fn = progress, .progress_ctx = self }, name, self.input);
        var parsed = try std.json.parseFromSlice(std.json.Value, a, self.input, .{});
        defer parsed.deinit();
        if (parsed.value != .object) return error.InvalidBuiltinArguments;
        const path = parsed.value.object.get("path") orelse return error.InvalidBuiltinArguments;
        if (path != .string) return error.InvalidBuiltinArguments;
        var env = try native_env.ExecutionEnv.init(a, self.io, .{ .cwd = self.cwd, .environ = &self.environment });
        defer env.deinit();
        var set: native_tools.ToolSet = .{ .gpa = a, .io = self.io };
        const context: @import("../durable/types.zig").Context = .{ .abort_flag = @ptrCast(&self.abort_flag) };
        var result = if (std.mem.eql(u8, name, "write")) blk: {
            const content = parsed.value.object.get("content") orelse return error.InvalidBuiltinArguments;
            if (content != .string) return error.InvalidBuiltinArguments;
            break :blk try set.write(&env, path.string, content.string, context);
        } else blk: {
            const replacements = parsed.value.object.get("edits") orelse return error.InvalidBuiltinArguments;
            if (replacements != .array) return error.InvalidBuiltinArguments;
            const edits = try a.alloc(native_tools.edit_match.Edit, replacements.array.items.len);
            defer a.free(edits);
            for (replacements.array.items, edits) |entry, *edit| {
                if (entry != .object) return error.InvalidBuiltinArguments;
                const old = entry.object.get("oldText") orelse return error.InvalidBuiltinArguments;
                const new = entry.object.get("newText") orelse return error.InvalidBuiltinArguments;
                if (old != .string or new != .string) return error.InvalidBuiltinArguments;
                edit.* = .{ .oldText = old.string, .newText = new.string };
            }
            break :blk try set.edit(&env, path.string, edits, context);
        };
        defer result.deinit(a);
        if (result == .failure) return .{ .content = try a.dupe(u8, result.failure.message), .is_error = true };
        const content = try a.dupe(u8, result.value.text orelse "");
        errdefer a.free(content);
        const details = if (result.value.details) |details| switch (details) {
            .edit => |edit| try std.json.Stringify.valueAlloc(a, .{ .diff = edit.diff, .patch = edit.patch, .firstChangedLine = edit.firstChangedLine }, .{ .emit_null_optional_fields = false }),
            .truncation => |truncation| try std.json.Stringify.valueAlloc(a, truncation, .{}),
        } else null;
        return .{ .content = content, .is_error = false, .details_json = details };
    }
    fn progress(raw: ?*anyopaque, bytes: []const u8) void {
        const self: *Job = @ptrCast(@alignCast(raw.?));
        if (!self.emit_updates) return;
        const owned = a.dupe(u8, bytes) catch return;
        self.mutex.lockUncancelable(self.io);
        if (self.updates.items.len != 0) {
            a.free(self.updates.items[0]);
            self.updates.items[0] = owned;
        } else self.updates.append(a, owned) catch a.free(owned);
        self.mutex.unlock(self.io);
        if (self.notify) |notify| notify(self.notify_context);
    }
    fn destroy(self: *Job, engine: *Engine) void {
        @atomicStore(bool, &self.abort_flag, true, .release);
        if (self.thread) |thread| thread.join();
        if (self.result) |*result| result.deinit(a);
        for (self.updates.items) |bytes| a.free(bytes);
        self.updates.deinit(a);
        a.free(self.cwd);
        a.free(self.input);
        self.environment.deinit();
        self.options.deinit(a);
        if (self.structured_json) |bytes| a.free(bytes);
        for ([_]c.JSValue{ self.signal, self.on_update, self.resolve, self.reject }) |value| engine.freeValue(value);
        if (self.failure) |value| engine.freeValue(value);
        a.destroy(self);
    }
};
const State = struct { jobs: std.ArrayList(*Job) = .empty, pumping: bool = false, edit_prepare: ?c.JSValue = null };
fn stateFor(engine: *Engine) !*State {
    if (engine.native_sdk_builtin_execution_state) |raw| return @ptrCast(@alignCast(raw));
    const state = try engine.gpa.create(State);
    state.* = .{};
    engine.native_sdk_builtin_execution_state = state;
    engine.native_sdk_builtin_execution_cleanup = deinit;
    engine.native_sdk_builtin_execution_pump = pump;
    engine.native_sdk_builtin_execution_pending = pending;
    return state;
}
pub fn pending(engine: *Engine) bool {
    const raw = engine.native_sdk_builtin_execution_state orelse return false;
    const state: *State = @ptrCast(@alignCast(raw));
    return state.jobs.items.len != 0;
}
pub fn deinit(engine: *Engine) void {
    engine.native_sdk_builtin_execution_cleanup = null;
    engine.native_sdk_builtin_execution_pump = null;
    engine.native_sdk_builtin_execution_pending = null;
    const raw = engine.native_sdk_builtin_execution_state orelse return;
    engine.native_sdk_builtin_execution_state = null;
    const state: *State = @ptrCast(@alignCast(raw));
    // Signal every worker before joining any one of them.
    for (state.jobs.items) |job| @atomicStore(bool, &job.abort_flag, true, .release);
    for (state.jobs.items) |job| job.destroy(engine);
    state.jobs.deinit(engine.gpa);
    if (state.edit_prepare) |value| engine.freeValue(value);
    engine.gpa.destroy(state);
}
fn finalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const engine: *Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const factory: *Factory = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_sdk_builtin_execution_class) orelse return));
    engine.gpa.free(factory.cwd);
    factory.options.deinit(engine.gpa);
    if (factory.operations) |operations| c.JS_FreeValueRT(runtime, operations);
    engine.gpa.destroy(factory);
}
fn markFactory(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const engine: *Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const factory: *Factory = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_sdk_builtin_execution_class) orelse return));
    if (factory.operations) |operations| c.JS_MarkValue(runtime, operations, marker);
}
pub fn createDefinition(engine: *Engine, name: []const u8, cwd: []const u8, auto_resize: bool) !c.JSValue {
    return createDefinitionWithOptions(engine, name, cwd, .{ .auto_resize = auto_resize });
}
pub fn createDefinitionWithOptions(engine: *Engine, name: []const u8, cwd: []const u8, options: Options) !c.JSValue {
    return createDefinitionWithOperations(engine, name, cwd, options, c.pi_js_undefined());
}
pub fn createDefinitionWithOperations(engine: *Engine, name: []const u8, cwd: []const u8, options: Options, operations: c.JSValue) !c.JSValue {
    var index: ?usize = null;
    for (templates.names, 0..) |candidate, i| if (std.mem.eql(u8, name, candidate)) {
        index = i;
        break;
    };
    const chosen = index orelse return error.UnknownBuiltinTool;
    if (engine.native_sdk_builtin_execution_class == 0) {
        var id: c.JSClassID = 0;
        _ = c.JS_NewClassID(engine.runtime, &id);
        const definition: c.JSClassDef = .{ .class_name = "Native builtin factory owner", .finalizer = finalizer, .gc_mark = markFactory };
        if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
        engine.native_sdk_builtin_execution_class = id;
    }
    const factory = try engine.gpa.create(Factory);
    var transferred = false;
    errdefer if (!transferred) engine.gpa.destroy(factory);
    const owned_cwd = try engine.gpa.dupe(u8, cwd);
    errdefer if (!transferred) engine.gpa.free(owned_cwd);
    var owned_options = try OwnedOptions.copy(engine.gpa, options);
    errdefer if (!transferred) owned_options.deinit(engine.gpa);
    const owned_operations: ?c.JSValue = if (c.JS_IsUndefined(operations) or c.JS_IsNull(operations)) null else c.JS_DupValue(engine.context, operations);
    errdefer if (!transferred) if (owned_operations) |value| engine.freeValue(value);
    factory.* = .{ .engine = engine, .cwd = owned_cwd, .io = engine.native_io, .index = chosen, .auto_resize = options.auto_resize, .options = owned_options, .operations = owned_operations };
    const owner = try engine.checked(c.JS_NewObjectClass(engine.context, engine.native_sdk_builtin_execution_class));
    defer engine.freeValue(owner);
    _ = c.JS_SetOpaque(owner, factory);
    transferred = true;
    const result = try templates.getTemplate(engine, name);
    errdefer engine.freeValue(result);
    var data = [_]c.JSValue{owner};
    try vm.put(engine, result, "execute", try engine.checked(c.JS_NewCFunctionData2(engine.context, executeCallback, "execute", 5, 0, data.len, &data)));
    if (std.mem.eql(u8, name, "edit")) {
        const state = try stateFor(engine);
        if (state.edit_prepare == null) state.edit_prepare = try @import("native_sdk_edit_arguments.zig").create(engine);
        try vm.put(engine, result, "prepareArguments", c.JS_DupValue(engine.context, state.edit_prepare.?));
    }
    return result;
}
pub fn createDefinitions(engine: *Engine, cwd: []const u8, auto_resize: bool) !c.JSValue {
    return createDefinitionsWithOptions(engine, cwd, .{ .auto_resize = auto_resize });
}
pub fn createDefinitionsWithOptions(engine: *Engine, cwd: []const u8, options: Options) !c.JSValue {
    const result = try vm.array(engine);
    errdefer engine.freeValue(result);
    for (templates.names, 0..) |name, index| if (c.JS_SetPropertyUint32(engine.context, result, @intCast(index), try createDefinitionWithOptions(engine, name, cwd, if (std.mem.eql(u8, name, "bash")) options else .{ .auto_resize = options.auto_resize })) < 0) return error.JavaScriptException;
    return result;
}
fn executeCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const factory: *Factory = @ptrCast(@alignCast(c.JS_GetOpaque(data[0], engine.native_sdk_builtin_execution_class) orelse return c.JS_ThrowTypeError(context, "Invalid builtin factory")));
    if (factory.operations) |operations| {
        const glob = vm.get(engine, operations, "glob") catch |err| return rejectedPromise(engine, err);
        defer engine.freeValue(glob);
        if (c.JS_ToBool(engine.context, glob) == 1 and std.mem.eql(u8, templates.names[factory.index], "find")) return @import("native_sdk_builtin_find_vm.zig").start(engine, data[0], operations, factory.cwd, if (argc > 1) args[1] else c.pi_js_undefined(), if (argc > 2) args[2] else c.pi_js_undefined(), if (argc > 4) args[4] else c.pi_js_undefined()) catch |err| rejectedPromise(engine, err);
    }
    return start(factory, if (argc > 1) args[1] else c.pi_js_undefined(), if (argc > 2) args[2] else c.pi_js_undefined(), if (argc > 3) args[3] else c.pi_js_undefined(), if (argc > 4) args[4] else c.pi_js_undefined()) catch |err| rejectedPromise(engine, err);
}
pub fn installFindFactories(engine: *Engine, exports: c.JSValue) !void {
    inline for (.{ "createFindToolDefinition", "createFindTool" }, 0..) |name, index| try vm.put(engine, exports, name, try engine.checked(c.pi_js_function_magic(engine.context, findFactory, name, 2, @intCast(index))));
}
fn findFactory(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, wrapped: c_int) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return findFactoryOwned(engine, argv[0..@intCast(argc)], wrapped != 0) catch |err| sdk.fail(engine, err);
}
fn findFactoryOwned(engine: *Engine, args: []const c.JSValue, wrapped: bool) !c.JSValue {
    const cwd = try engine.toString(if (args.len > 0) args[0] else c.pi_js_undefined());
    defer engine.gpa.free(cwd);
    const operations = if (args.len > 1 and !c.JS_IsUndefined(args[1]) and !c.JS_IsNull(args[1])) try vm.get(engine, args[1], "operations") else c.pi_js_undefined();
    defer engine.freeValue(operations);
    const definition = try createDefinitionWithOperations(engine, "find", cwd, .{}, operations);
    if (!wrapped) return definition;
    defer engine.freeValue(definition);
    const result = try vm.object(engine);
    errdefer engine.freeValue(result);
    inline for (.{ "name", "label", "description", "parameters", "outputSchema", "constrainedSampling", "prepareArguments", "executionMode" }) |name| try vm.put(engine, result, name, try vm.get(engine, definition, name));
    var data = [_]c.JSValue{definition};
    try vm.put(engine, result, "execute", try engine.checked(c.JS_NewCFunctionData2(engine.context, forwardDefinition, "execute", 5, 0, 1, &data)));
    return result;
}
fn forwardDefinition(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return vm.invoke(engine, data[0], "execute", argv[0..@intCast(argc)]) catch |err| sdk.fail(engine, err);
}
fn rejectedPromise(engine: *Engine, err: anyerror) c.JSValue {
    _ = sdk.fail(engine, err);
    const reason = c.JS_GetException(engine.context);
    defer engine.freeValue(reason);
    var functions: [2]c.JSValue = undefined;
    const promise = c.JS_NewPromiseCapability(engine.context, &functions);
    if (c.JS_IsException(promise)) return promise;
    defer for (functions) |function| engine.freeValue(function);
    var args = [_]c.JSValue{reason};
    const ignored = c.JS_Call(engine.context, functions[1], c.pi_js_undefined(), 1, &args);
    if (c.JS_IsException(ignored)) {
        engine.freeValue(promise);
        return ignored;
    }
    engine.freeValue(ignored);
    return promise;
}
fn start(factory: *Factory, input: c.JSValue, signal: c.JSValue, update: c.JSValue, context: c.JSValue) !c.JSValue {
    const engine = factory.engine;
    const io = factory.io orelse return error.NativeSDKRequiresIO;
    const state = try stateFor(engine);
    try state.jobs.ensureUnusedCapacity(engine.gpa, 1);
    const encoded = try engine.stringify(input);
    defer engine.gpa.free(encoded);
    const context_cwd = if (!c.JS_IsUndefined(context) and !c.JS_IsNull(context)) try vm.get(engine, context, "cwd") else c.pi_js_undefined();
    defer engine.freeValue(context_cwd);
    const override = if (c.JS_ToBool(engine.context, context_cwd) == 1) blk: {
        if (!c.JS_IsString(context_cwd)) return error.InvalidBuiltinContextCwd;
        break :blk try engine.toString(context_cwd);
    } else null;
    defer if (override) |path| engine.gpa.free(path);
    const cwd = try a.dupe(u8, override orelse factory.cwd);
    errdefer a.free(cwd);
    const bytes = try a.dupe(u8, encoded);
    errdefer a.free(bytes);
    const job = try a.create(Job);
    errdefer a.destroy(job);
    var environment = try environmentSnapshot(engine);
    errdefer environment.deinit();
    var options = try OwnedOptions.copy(a, .{ .shell_path = factory.options.shell_path, .command_prefix = factory.options.command_prefix });
    errdefer options.deinit(a);
    var functions: [2]c.JSValue = undefined;
    const promise = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
    errdefer engine.freeValue(promise);
    errdefer for (functions) |function| engine.freeValue(function);
    job.* = .{ .io = io, .cwd = cwd, .input = bytes, .index = factory.index, .auto_resize = factory.auto_resize, .environment = environment, .options = options, .emit_updates = c.JS_ToBool(engine.context, update) == 1, .signal = c.JS_DupValue(engine.context, signal), .on_update = c.JS_DupValue(engine.context, update), .resolve = functions[0], .reject = functions[1], .notify_context = engine.host_owner_notify_context, .notify = engine.host_owner_notify };
    errdefer {
        engine.freeValue(job.signal);
        engine.freeValue(job.on_update);
    }
    try observeAbort(engine, job);
    if (job.emit_updates and (std.mem.eql(u8, templates.names[job.index], "bash") or std.mem.eql(u8, templates.names[job.index], "powershell"))) {
        const initial = try vm.object(engine);
        defer engine.freeValue(initial);
        try vm.put(engine, initial, "content", try vm.array(engine));
        try vm.put(engine, initial, "details", c.pi_js_undefined());
        var initial_args = [_]c.JSValue{initial};
        const ignored = try engine.checked(c.JS_Call(engine.context, update, c.pi_js_undefined(), 1, &initial_args));
        engine.freeValue(ignored);
    }
    try state.jobs.ensureUnusedCapacity(engine.gpa, 1);
    job.thread = try std.Thread.spawn(.{}, Job.run, .{job});
    state.jobs.appendAssumeCapacity(job);
    return promise;
}
fn environmentSnapshot(engine: *Engine) !std.process.Environ.Map {
    var result: std.process.Environ.Map = .init(a);
    errdefer result.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const process = try vm.get(engine, global, "process");
    defer engine.freeValue(process);
    if (!c.JS_IsObject(process)) return result;
    const environment = try vm.get(engine, process, "env");
    defer engine.freeValue(environment);
    if (!c.JS_IsObject(environment)) return result;
    var properties: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &properties, &count, environment, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return error.JavaScriptException;
    defer c.JS_FreePropertyEnum(engine.context, properties, count);
    for (properties[0..count]) |entry| {
        const key = try engine.checked(c.JS_AtomToValue(engine.context, entry.atom));
        defer engine.freeValue(key);
        const value = try engine.checked(c.JS_GetProperty(engine.context, environment, entry.atom));
        defer engine.freeValue(value);
        if (c.JS_IsUndefined(value)) continue;
        const name = try engine.toString(key);
        defer engine.gpa.free(name);
        const text = try engine.toString(value);
        defer engine.gpa.free(text);
        try result.put(name, text);
    }
    return result;
}
fn observeAbort(engine: *Engine, job: *Job) !void {
    if (!c.JS_IsObject(job.signal) or @atomicLoad(bool, &job.abort_flag, .acquire)) return;
    const aborted = try vm.get(engine, job.signal, "aborted");
    defer engine.freeValue(aborted);
    if (c.JS_ToBool(engine.context, aborted) == 1) @atomicStore(bool, &job.abort_flag, true, .release);
}
fn textBlock(engine: *Engine, bytes: []const u8) !c.JSValue {
    const result = try vm.object(engine);
    errdefer engine.freeValue(result);
    try vm.put(engine, result, "type", try sdk.text(engine, "text"));
    try vm.put(engine, result, "text", try @import("native_durable.zig").jsValue(engine, .{ .string = bytes }));
    return result;
}
fn project(engine: *Engine, result: *const tools.ToolResult, index: usize) !c.JSValue {
    const row = try vm.object(engine);
    errdefer engine.freeValue(row);
    const content = try vm.array(engine);
    defer engine.freeValue(content);
    if (c.JS_SetPropertyUint32(engine.context, content, 0, try textBlock(engine, result.content)) < 0) return error.JavaScriptException;
    if (result.image_b64) |bytes| {
        const image = try vm.object(engine);
        defer engine.freeValue(image);
        try vm.put(engine, image, "type", try sdk.text(engine, "image"));
        try vm.put(engine, image, "data", try sdk.text(engine, bytes));
        try vm.put(engine, image, "mimeType", try sdk.text(engine, result.image_mime orelse "image/png"));
        if (c.JS_SetPropertyUint32(engine.context, content, 1, c.JS_DupValue(engine.context, image)) < 0) return error.JavaScriptException;
    }
    try vm.put(engine, row, "content", c.JS_DupValue(engine.context, content));
    const details = if (result.details_json) |bytes| try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "builtin-details")) else c.pi_js_undefined();
    try vm.put(engine, row, "details", details);
    if (std.mem.eql(u8, templates.names[index], "read")) {
        const structured = if (result.image_b64) |bytes| blk: {
            const image = try vm.object(engine);
            errdefer engine.freeValue(image);
            try vm.put(engine, image, "type", try sdk.text(engine, "image"));
            try vm.put(engine, image, "data", try sdk.text(engine, bytes));
            try vm.put(engine, image, "mimeType", try sdk.text(engine, result.image_mime orelse "image/png"));
            try vm.put(engine, image, "note", try sdk.text(engine, result.content));
            break :blk image;
        } else try sdk.text(engine, result.content);
        try vm.put(engine, row, "structuredContent", structured);
    }
    return row;
}
fn deliverUpdates(engine: *Engine, job: *Job, force: bool) !bool {
    job.mutex.lockUncancelable(job.io);
    if (job.updates.items.len == 0) {
        job.mutex.unlock(job.io);
        return false;
    }
    job.progress_gate.mark();
    if (!force and !job.progress_gate.begin(@floatFromInt(std.Io.Clock.awake.now(job.io).toMilliseconds()))) {
        job.mutex.unlock(job.io);
        return false;
    }
    const updates = job.updates;
    job.updates = .empty;
    job.mutex.unlock(job.io);
    defer {
        if (!force and job.progress_gate.in_flight) job.progress_gate.complete(0, job.failure == null);
        for (updates.items) |bytes| a.free(bytes);
        var owned = updates;
        owned.deinit(a);
    }
    if (!c.JS_IsFunction(engine.context, job.on_update) or job.failure != null) return updates.items.len != 0;
    for (updates.items) |bytes| {
        const update_row = try vm.object(engine);
        defer engine.freeValue(update_row);
        const blocks = try vm.array(engine);
        defer engine.freeValue(blocks);
        if (c.JS_SetPropertyUint32(engine.context, blocks, 0, try textBlock(engine, bytes)) < 0) return error.JavaScriptException;
        try vm.put(engine, update_row, "content", c.JS_DupValue(engine.context, blocks));
        const details = try vm.object(engine);
        defer engine.freeValue(details);
        try vm.put(engine, details, "truncation", c.pi_js_undefined());
        try vm.put(engine, details, "fullOutputPath", c.pi_js_undefined());
        try vm.put(engine, update_row, "details", c.JS_DupValue(engine.context, details));
        var update_args = [_]c.JSValue{update_row};
        const ignored = c.JS_Call(engine.context, job.on_update, c.pi_js_undefined(), 1, &update_args);
        if (c.JS_IsException(ignored)) {
            job.failure = c.JS_GetException(engine.context);
            @atomicStore(bool, &job.abort_flag, true, .release);
            break;
        }
        engine.freeValue(ignored);
    }
    return updates.items.len != 0;
}
pub fn pump(engine: *Engine) !bool {
    const raw = engine.native_sdk_builtin_execution_state orelse return false;
    const state: *State = @ptrCast(@alignCast(raw));
    if (state.pumping) return false;
    state.pumping = true;
    defer state.pumping = false;
    var worked = false;
    var index: usize = 0;
    while (index < state.jobs.items.len) {
        const job = state.jobs.items[index];
        try observeAbort(engine, job);
        worked = (try deliverUpdates(engine, job, false)) or worked;
        if (!job.finished.load(.acquire)) {
            index += 1;
            continue;
        }
        worked = (try deliverUpdates(engine, job, true)) or worked;
        // Retire before entering guest continuations; reentry cannot settle a
        // completed job twice or attach a later abort to its settled promise.
        _ = state.jobs.orderedRemove(index);
        defer job.destroy(engine);
        const reject = job.failure != null or job.native_error != null or (if (job.result) |result| result.is_error and job.reject_result else true);
        const value = if (job.result) |*result| if (result.is_error and job.reject_result) try engine.checked(c.JS_NewError(engine.context)) else try project(engine, result, job.index) else try engine.checked(c.JS_NewError(engine.context));
        defer engine.freeValue(value);
        if (reject) try vm.put(engine, value, "message", try sdk.text(engine, if (job.result) |result| result.content else @errorName(job.native_error.?)));
        if (!reject) {
            if (job.structured_json) |bytes| try vm.put(engine, value, "structuredContent", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "builtin-structured-result")));
            if (job.result.?.is_error) try vm.put(engine, value, "isError", c.pi_js_bool(engine.context, 1));
        }
        var args = [_]c.JSValue{job.failure orelse value};
        const ignored = try engine.checked(c.JS_Call(engine.context, if (reject) job.reject else job.resolve, c.pi_js_undefined(), 1, &args));
        engine.freeValue(ignored);
        worked = true;
    }
    return worked;
}

test "ToolInfo actual SDK default factories retain separate CWDs and execute real Zig read write edit and ls through owned workers" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(std.testing.io, "a");
    try temporary.dir.createDirPath(std.testing.io, "b");
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path_size = try temporary.dir.realPath(std.testing.io, &path_buffer);
    const path_a = try std.fs.path.join(std.testing.allocator, &.{ path_buffer[0..path_size], "a" });
    defer std.testing.allocator.free(path_a);
    const path_b = try std.fs.path.join(std.testing.allocator, &.{ path_buffer[0..path_size], "b" });
    defer std.testing.allocator.free(path_b);
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("native_stream.zig").install(engine);
    const exports = try vm.object(engine);
    defer engine.freeValue(exports);
    try sdk.install(engine, exports);
    try engine.registerValueModule("sdk-owned-builtins", exports);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try vm.put(engine, global, "cwdA", try sdk.text(engine, path_a));
    try vm.put(engine, global, "cwdB", try sdk.text(engine, path_b));
    const result = engine.evalModule(
        "import{createAgentSession,SessionManager,SettingsManager,DefaultResourceLoader,ModelRuntime}from'sdk-owned-builtins';" ++
            "const runtime=await ModelRuntime.create({refreshOnCreate:false});const model={id:'owned',provider:'owned',api:'owned',type:'chat',input:['text']};" ++
            "const create=async cwd=>(await createAgentSession({cwd,sessionManager:SessionManager.inMemory(cwd),settingsManager:SettingsManager.inMemory(),resourceLoader:new DefaultResourceLoader({cwd,agentDir:cwd,noExtensions:true}),modelRuntime:runtime,model})).session;" ++
            "const A=await create(cwdA),B=await create(cwdB);if(A.getAllTools().map(t=>t.name).join(',')!=='read,bash,powershell,edit,write,grep,find,ls')throw Error('default definitions');" ++
            "if(A.getActiveToolNames().join(',')!=='read,bash,edit,write')throw Error('default selection');" ++
            "if(A.getToolDefinition('read').parameters!==B.getToolDefinition('read').parameters||A.getToolDefinition('read').execute===B.getToolDefinition('read').execute||A.getToolDefinition('edit').prepareArguments!==B.getToolDefinition('edit').prepareArguments||A.getToolDefinition('edit').prepareArguments.name!=='prepareEditArguments')throw Error('factory ownership');" ++
            "const writeA=A.getToolDefinition('write'),writeB=B.getToolDefinition('write'),readA=A.getToolDefinition('read'),readB=B.getToolDefinition('read');" ++
            "const pending=writeA.execute('wa',{path:'same.txt',content:'alpha'});if(!(pending instanceof Promise))throw Error('worker promise');if((await pending).content[0].text!=='Successfully wrote to same.txt')throw Error('source write result');await writeB.execute('wb',{path:'same.txt',content:'bravo'});" ++
            "if(!(await readA.execute('ra',{path:'same.txt'})).content[0].text.includes('alpha')||!(await readB.execute('rb',{path:'same.txt'})).content[0].text.includes('bravo'))throw Error('retained CWD');if(!(await readA.execute('override',{path:'same.txt'},undefined,undefined,{cwd:cwdB})).content[0].text.includes('bravo'))throw Error('Source explicit context CWD');" ++
            "const edit=A.getToolDefinition('edit');const prepared=edit.prepareArguments({path:'same.txt',oldText:'alpha',newText:'owned'});const edited=await edit.execute('ea',prepared);if(edited.content[0].text!=='Successfully replaced 1 block(s) in same.txt.'||typeof edited.details.diff!=='string')throw Error('source edit result');" ++
            "if(!(await readA.execute('ra2',{path:'same.txt'})).content[0].text.includes('owned'))throw Error('real edit');" ++
            "if(!(await A.getToolDefinition('ls').execute('la',{path:'.'})).content[0].text.includes('same.txt'))throw Error('real ls');" ++
            "A.setActiveToolsByName(['ls','unknown','ls','read']);if(A.getActiveToolNames().join(',')!=='ls,read')throw Error('known active selection');" ++
            "A.dispose();await writeA.execute('retained',{path:'retained.txt',content:'retained factory'});if(!(await readA.execute('retained-read',{path:'retained.txt'})).content[0].text.includes('retained factory'))throw Error('retained definition');export const proof=true;",
        "actual-sdk-owned-builtin-execution.mjs",
    ) catch |err| {
        if (engine.last_error) |message| std.debug.print("SDK owned builtin execution: {s}\n", .{message});
        return err;
    };
    defer engine.freeValue(result);
    try std.testing.expect(!pending(engine));
}

test "ToolInfo actual SDK model turns declare and execute their own default tools through schema validation and preparation" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path_size = try temporary.dir.realPath(std.testing.io, &path_buffer);
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("native_stream.zig").install(engine);
    const exports = try vm.object(engine);
    defer engine.freeValue(exports);
    try sdk.install(engine, exports);
    try engine.registerValueModule("sdk-model-builtins", exports);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try vm.put(engine, global, "ownedCwd", try sdk.text(engine, path_buffer[0..path_size]));
    const result = engine.evalModule(
        "import{createAgentSession,SessionManager,SettingsManager,DefaultResourceLoader,ModelRuntime}from'sdk-model-builtins';import{createAssistantMessageEventStream}from'pi-ai';" ++
            "const runtime=await ModelRuntime.create({refreshOnCreate:false}),model={id:'native',provider:'native-sdk-tools',api:'native-sdk-tools',type:'chat',reasoning:false,input:['text'],cost:{input:0,output:0,cacheRead:0,cacheWrite:0},contextWindow:8192,maxTokens:512};let turn=0;" ++
            "runtime.registerNativeProvider({id:model.provider,auth:{apiKey:{resolve:async()=>({auth:{apiKey:'fixture-key'},source:'fixture'})}},getModels(){return[model]},getAllModels(){return[model]},streamSimple(model,context){if(context.tools.map(t=>t.name).join(',')!=='read,bash,edit,write')throw Error('foreign declared tools');const calls=[{type:'toolCall',id:'write-owned',name:'write',arguments:{path:'owned.txt',content:'alpha'}},{type:'toolCall',id:'edit-owned',name:'edit',arguments:{path:'owned.txt',oldText:'alpha',newText:'prepared'}},{type:'toolCall',id:'read-owned',name:'read',arguments:{path:'owned.txt',offset:'1'}}];const content=turn<3?[calls[turn++]]:[{type:'text',text:'done'}],message={role:'assistant',content,api:model.api,provider:model.provider,model:model.id,usage:{input:1,output:1,cacheRead:0,cacheWrite:0,totalTokens:2,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}},stopReason:content[0].type==='toolCall'?'toolUse':'stop',timestamp:1},stream=createAssistantMessageEventStream();queueMicrotask(()=>{stream.push({type:'start',partial:message});stream.push({type:'done',reason:message.stopReason,message});stream.end()});return stream}});" ++
            "const{session}=await createAgentSession({cwd:ownedCwd,model,modelRuntime:runtime,sessionManager:SessionManager.inMemory(ownedCwd),settingsManager:SettingsManager.inMemory(),resourceLoader:new DefaultResourceLoader({cwd:ownedCwd,agentDir:ownedCwd,noExtensions:true})});await session.prompt('execute owned defaults');" ++
            "const results=session.messages.filter(m=>m.role==='toolResult');if(results.length!==3||results.some(m=>m.isError)||results[0].content[0].text!=='Successfully wrote to owned.txt'||!results[1].content[0].text.startsWith('Successfully replaced')||results[2].content[0].text!=='prepared')throw Error('default model execution');session.dispose();export const proof=true;",
        "actual-sdk-model-builtin-execution.mjs",
    ) catch |err| {
        if (engine.last_error) |message| std.debug.print("SDK model builtin execution: {s}\n", .{message});
        return err;
    };
    defer engine.freeValue(result);
    try std.testing.expect(!pending(engine));
}

test "ToolInfo SDK Bash factories preserve shell settings real progress raw rejection and owned process cancellation" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path_size = try temporary.dir.realPath(std.testing.io, &path_buffer);
    var environment = try std.process.Environ.createMap(std.testing.environ, std.testing.allocator);
    defer environment.deinit();
    var config = try @import("../durable/startup.zig").shellConfig(std.testing.allocator, std.testing.io, &environment, null);
    defer config.deinit(std.testing.allocator);
    if (@import("builtin").os.tag == .windows) {
        const shell_directory = std.fs.path.dirname(config.program).?;
        const git_root = std.fs.path.dirname(shell_directory).?;
        const usr_bin = try std.fs.path.join(std.testing.allocator, &.{ git_root, "usr", "bin" });
        defer std.testing.allocator.free(usr_bin);
        const executable_path = try std.fmt.allocPrint(std.testing.allocator, "{s};C:\\Windows\\System32", .{usr_bin});
        defer std.testing.allocator.free(executable_path);
        try environment.put("PATH", executable_path);
    }
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"native-sdk-shell"});
    try @import("native_stream.zig").install(engine);
    if (engine.abort_signal_class == 0) try @import("abort_signal.zig").install(engine);
    const exports = try vm.object(engine);
    defer engine.freeValue(exports);
    try sdk.install(engine, exports);
    try engine.registerValueModule("sdk-owned-shell", exports);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try vm.put(engine, global, "ownedCwd", try sdk.text(engine, path_buffer[0..path_size]));
    const absolute_shell = try @import("../durable/startup.zig").resolveProgram(std.testing.allocator, std.testing.io, config.program, path_buffer[0..path_size], &environment);
    defer std.testing.allocator.free(absolute_shell);
    try vm.put(engine, global, "ownedShell", try sdk.text(engine, absolute_shell));
    const result = engine.evalModule(
        "import{createAgentSession,SessionManager,SettingsManager,DefaultResourceLoader,ModelRuntime}from'sdk-owned-shell';" ++
            "const settings=SettingsManager.inMemory({shellPath:ownedShell,shellCommandPrefix:'export OWNED_PREFIX=retained'}),runtime=await ModelRuntime.create({refreshOnCreate:false}),model={id:'m',provider:'owned-shell',api:'owned-shell',type:'chat',input:['text']};" ++
            "const{session}=await createAgentSession({cwd:ownedCwd,model,modelRuntime:runtime,sessionManager:SessionManager.inMemory(ownedCwd),settingsManager:settings,resourceLoader:new DefaultResourceLoader({cwd:ownedCwd,agentDir:ownedCwd,noExtensions:true})});" ++
            "const bash=session.getToolDefinition('bash');settings.applyOverrides({shellPath:'missing-after-factory',shellCommandPrefix:'export OWNED_PREFIX=mutated'});" ++
            "const updates=[];const normal=await bash.execute('normal',{command:'printf %s \"$OWNED_PREFIX\"'},undefined,row=>updates.push(row));if(normal.content[0].text!=='retained'||normal.structuredContent.output!=='retained'||normal.structuredContent.exit_code!==0||normal.structuredContent.truncated!==false||typeof normal.structuredContent.wall_time_seconds!=='number')throw Error('source shell result/settings');" ++
            "if(updates.length<2||updates[0].content.length!==0||!Object.hasOwn(updates[0],'details')||updates[updates.length-1].content[0].text!=='retained')throw Error('source progress lifecycle');" ++
            "const failed=await bash.execute('exit',{command:'printf bad;exit 7'});if(failed.isError!==true||failed.structuredContent.exit_code!==7||failed.content[0].text!=='bad\\n\\nCommand exited with code 7')throw Error('source nonzero result');" ++
            "const marker={owned:true};let rejected;const callbackFailure=bash.execute('callback',{command:'printf never'},undefined,()=>{throw marker});if(!(callbackFailure instanceof Promise))throw Error('async rejection');try{await callbackFailure}catch(e){rejected=e}if(rejected!==marker)throw Error('raw update failure');" ++
            "const controller=new AbortController();const cancelled=bash.execute('cancel',{command:'printf before;sleep 5;printf after'},controller.signal,row=>{if(row.content[0]?.text.includes('before'))controller.abort()});let abortError;try{await cancelled}catch(e){abortError=e}if(!abortError?.message.includes('Command aborted')||abortError.message.includes('after'))throw Error('owned process cancellation');" ++
            "const preAborted=new AbortController();preAborted.abort();let early;try{await bash.execute('preabort',{command:'printf should-not-run'},preAborted.signal)}catch(e){early=e}if(early?.message!=='Command aborted')throw Error('preabort');session.dispose();export const proof=true;",
        "actual-sdk-owned-shell-execution.mjs",
    ) catch |err| {
        if (engine.last_error) |message| std.debug.print("SDK owned shell execution: {s}\n", .{message});
        return err;
    };
    defer engine.freeValue(result);
    try std.testing.expect(!pending(engine));
}

test "ToolInfo actual SDK default selection matches Source allow exclude noTools modifiers and MCP name policy" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_stream.zig").install(engine);
    const exports = try vm.object(engine);
    defer engine.freeValue(exports);
    try sdk.install(engine, exports);
    try engine.registerValueModule("sdk-selection", exports);
    const source = try std.json.parseFromSlice(std.json.Value, engine.gpa, @embedFile("../durable/fixtures/sdk-tool-selection-1ced.json"), .{});
    defer source.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try vm.put(engine, global, "sourceSelectionCases", try engine.fromJsonValue(source.value));
    const result = engine.evalModule(
        "import{createAgentSession,SessionManager,SettingsManager,DefaultResourceLoader,ModelRuntime}from'sdk-selection';" ++
            "const runtime=await ModelRuntime.create({refreshOnCreate:false}),model={id:'fixture',provider:'fixture',api:'openai-responses',name:'Fixture',input:['text'],contextWindow:8192,maxTokens:1024,cost:{input:0,output:0,cacheRead:0,cacheWrite:0}};" ++
            "for(const expected of sourceSelectionCases){const cwd='/sdk',settings=SettingsManager.inMemory(expected.settings),loader=new DefaultResourceLoader({cwd,agentDir:cwd,settingsManager:settings,noExtensions:true,noSkills:true,noPromptTemplates:true,noThemes:true,noContextFiles:true}),customTools=[{name:'own',description:'sdk-own',parameters:{type:'object'},execute(){return{content:[]}}},{name:'hidden',description:'sdk-hidden',parameters:{type:'object'},exposure:'hidden',execute(){return{content:[]}}},{name:'model_only',description:'sdk-model-only',parameters:{type:'object'},exposure:'model-only',defaultActive:false,execute(){return{content:[]}}},{name:'mcp__fixture__tool',description:'sdk-mcp-name',parameters:{type:'object'},defaultActive:false,execute(){return{content:[]}}},{name:'list_mcp_resources',description:'sdk-resource-name',parameters:{type:'object'},defaultActive:false,execute(){return{content:[]}}}];let session,error;try{({session}=await createAgentSession({cwd,agentDir:cwd,model,modelRuntime:runtime,sessionManager:SessionManager.inMemory(cwd),settingsManager:settings,resourceLoader:loader,customTools,...expected.options}))}catch(e){error=e;}if(expected.error){if(error?.name!==expected.error.name||error?.message!==expected.error.message)throw Error(expected.name+' error '+error);continue;}if(error)throw error;const names=session.getAllTools().map(t=>t.name),active=session.getActiveToolNames();if(JSON.stringify(names)!==JSON.stringify(expected.names)||JSON.stringify(active)!==JSON.stringify(expected.active))throw Error(expected.name+' '+JSON.stringify({names,active,expected}));session.dispose();}export const proof=true;",
        "sdk-source-selection-corpus.mjs",
    ) catch |err| {
        if (engine.last_error) |message| std.debug.print("SDK Source selection: {s}\n", .{message});
        return err;
    };
    defer engine.freeValue(result);
}

test "ToolInfo actual SDK explicit loadout exposure and active state observe Source array copy and identity" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_stream.zig").install(engine);
    const exports = try vm.object(engine);
    defer engine.freeValue(exports);
    try sdk.install(engine, exports);
    try engine.registerValueModule("sdk-active-state", exports);
    const source = @embedFile("../durable/fixtures/sdk-active-definition-state-1ced.json");
    const fixture = try engine.checked(c.JS_ParseJSON(engine.context, source, source.len, "actual-sdk-active-state"));
    defer engine.freeValue(fixture);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try vm.put(engine, global, "sourceActiveState", c.JS_DupValue(engine.context, fixture));
    const output = engine.evalModule(
        \\import{createAgentSession,SessionManager,SettingsManager,DefaultResourceLoader,ModelRuntime}from'sdk-active-state';
        \\const runtime=await ModelRuntime.create({refreshOnCreate:false}),cwd='/sdk',model={id:'fixture',provider:'fixture',api:'openai-responses',input:['text']};
        \\for(const search of [false,true]){
        \\ const settings=SettingsManager.inMemory({}),loader=new DefaultResourceLoader({cwd,agentDir:cwd,settingsManager:settings,noExtensions:true,noSkills:true,noPromptTemplates:true,noThemes:true,noContextFiles:true});await loader.reload();
        \\ const def=(name,exposure='direct')=>({name,exposure,description:name,parameters:{type:'object'},execute:async()=>({content:[]})});
        \\ const customTools=[def('direct'),def('hidden','hidden'),def('deferred','deferred'),def('codemode','codemode'),def('mcp__fixture__deferred','deferred'),def('mcp__fixture__direct'),...(search?[def('tool_search')]:[])];
        \\ const{session}=await createAgentSession({cwd,agentDir:cwd,model,modelRuntime:runtime,sessionManager:SessionManager.inMemory(cwd),settingsManager:settings,resourceLoader:loader,customTools,tools:['read','direct','hidden','deferred','codemode',...(search?['tool_search']:[])]});
        \\ session.setActiveToolsByName(['codemode','deferred','hidden','missing','direct','deferred','mcp__fixture__deferred','mcp__fixture__direct']);
        \\ const selected=session.getActiveToolNames();const injected=def('injected'),supplied=[injected];session.state.tools=supplied;supplied.push(def('later'));const observed=session.getActiveToolNames();
        \\ const row={name:search?'search':'no-search',selected,observed,topCopy:session.state.tools!==supplied,elementIdentity:session.state.tools[0]===injected,unregistered:session.getToolDefinition('injected')===undefined};
        \\ const expected=sourceActiveState.cases.find(item=>item.name===row.name);if(JSON.stringify(row)!==JSON.stringify(expected))throw Error(JSON.stringify({row,expected}));session.dispose();
        \\}
    , "actual-sdk-active-state") catch |err| {
        std.debug.print("Source active tool state: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(output);
}

test "ToolInfo native SDK builtin execution matches actual Source file listing search shell and context CWD results" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    for ([_][]const u8{ "listing/folder", "a", "b", "nested" }) |path| try temporary.dir.createDirPath(std.testing.io, path);
    const initial = [_]struct { path: []const u8, text: []const u8 }{
        .{ .path = "listing/.dot.txt", .text = "hidden" }, .{ .path = "listing/Alpha.txt", .text = "alpha\nbeta\ngamma" },
        .{ .path = "listing/beta.txt", .text = "beta" },   .{ .path = "a/same.txt", .text = "A" },
        .{ .path = "b/same.txt", .text = "B" },
    };
    for (initial) |row| try temporary.dir.writeFile(std.testing.io, .{ .sub_path = row.path, .data = row.text });
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path_size = try temporary.dir.realPath(std.testing.io, &path_buffer);
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment = try std.process.Environ.createMap(std.testing.environ, std.testing.allocator);
    defer environment.deinit();
    try environment.put("PI_OFFLINE", "1");
    if (@import("builtin").os.tag == .windows) {
        // The native gate excludes Node from PATH. Supply the actual shell
        // installation explicitly for the Source PowerShell execution row.
        const existing_path = environment.get("PATH") orelse "";
        const shell_path = try std.fmt.allocPrint(engine.gpa, "{s};C:\\Program Files\\PowerShell\\7;C:\\Windows\\System32\\WindowsPowerShell\\v1.0", .{existing_path});
        defer engine.gpa.free(shell_path);
        try environment.put("PATH", shell_path);
    }
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"native-sdk-io-corpus"});
    try @import("native_stream.zig").install(engine);
    const factory_exports = try vm.object(engine);
    defer engine.freeValue(factory_exports);
    try sdk.install(engine, factory_exports);
    try engine.registerValueModule("sdk-io-factory", factory_exports);
    const root = path_buffer[0..path_size];
    const definitions = try createDefinitions(engine, root, true);
    defer engine.freeValue(definitions);
    const source = try std.json.parseFromSlice(std.json.Value, engine.gpa, @embedFile("../durable/fixtures/sdk-builtin-execution-1ced.json"), .{});
    defer source.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try vm.put(engine, global, "nativeIoDefinitions", c.JS_DupValue(engine.context, definitions));
    try vm.put(engine, global, "nativeIoCases", try engine.fromJsonValue(source.value));
    try vm.put(engine, global, "nativeIoCwd", try sdk.text(engine, root));
    const a_cwd = try std.fs.path.join(engine.gpa, &.{ root, "a" });
    defer engine.gpa.free(a_cwd);
    try vm.put(engine, global, "nativeIoReadA", try createDefinition(engine, "read", a_cwd, true));
    const source_rg = try @import("../agent/tool_manager.zig").ensure(engine.gpa, std.testing.io, &environment, .rg, .{ .offline = true });
    defer if (source_rg) |path| engine.gpa.free(path);
    try vm.put(engine, global, "nativeIoHasRg", c.pi_js_bool(engine.context, @intFromBool(source_rg != null)));
    try vm.put(engine, global, "nativeIoWindows", c.pi_js_bool(engine.context, @intFromBool(@import("builtin").os.tag == .windows)));
    const result = engine.evalModule(
        "import{createFindToolDefinition}from'sdk-io-factory';" ++
            "const normalize=v=>typeof v==='string'?v.replaceAll(nativeIoCwd,'$CWD').replaceAll('\\\\','/'):Array.isArray(v)?v.map(normalize):v&&typeof v==='object'?Object.fromEntries(Object.entries(v).map(([k,x])=>[k,normalize(x)])):v;globalThis.nativeIoObserved=[];" ++
            "for(const expected of nativeIoCases){if(expected.tool==='grep'&&!nativeIoHasRg)continue;if(expected.tool==='powershell'&&!nativeIoWindows)continue;let definition=expected.factoryCwd?nativeIoReadA:nativeIoDefinitions.find(d=>d.name===expected.tool);if(expected.name.startsWith('find-custom'))definition=createFindToolDefinition(nativeIoCwd,{operations:{exists:()=>true,glob:(pattern,search,{limit})=>['.dot.txt','Alpha.txt','beta.txt'].filter(name=>pattern==='*.txt').slice(0,limit).map(name=>search+'/'+name)}});const context=expected.ctx?{cwd:nativeIoCwd+'/b'}:undefined;let result,error;try{result=await definition.execute('native-corpus',expected.args,undefined,undefined,context);if(result.structuredContent&&typeof result.structuredContent==='object'&&'wall_time_seconds'in result.structuredContent)delete result.structuredContent.wall_time_seconds;}catch(e){error={name:e.name,message:e.message}}if(expected.error){if(JSON.stringify(normalize(error))!==JSON.stringify(normalize(expected.error)))throw Error(expected.name+' '+JSON.stringify(normalize({error,expected:expected.error})));}else if(JSON.stringify(normalize(result))!==JSON.stringify(normalize(expected.result)))throw Error(expected.name+' '+JSON.stringify(normalize({result,expected:expected.result})));nativeIoObserved.push(expected.name);}export const proof=true;",
        "native-sdk-actual-source-io-corpus.mjs",
    ) catch |err| {
        if (engine.last_error) |message| std.debug.print("SDK Source I/O corpus: {s}\n", .{message});
        return err;
    };
    defer engine.freeValue(result);
}

test "ToolInfo SDK fd default find matches actual Source ignore nested repository full path and error policy" {
    var environment = try std.process.Environ.createMap(std.testing.environ, std.testing.allocator);
    defer environment.deinit();
    const fixture_directory = environment.get("PI_SDK_TOOL_FIXTURE_DIR") orelse return error.SkipZigTest;
    const owned_fixture = try std.testing.allocator.dupe(u8, fixture_directory);
    defer std.testing.allocator.free(owned_fixture);
    try environment.put("PI_CODING_AGENT_DIR", owned_fixture);
    try environment.put("PI_OFFLINE", "1");
    const fd = (try @import("../agent/tool_manager.zig").ensure(std.testing.allocator, std.testing.io, &environment, .fd, .{ .offline = true })) orelse return error.MissingSDKFdFixture;
    defer std.testing.allocator.free(fd);
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    for ([_][]const u8{ "repo/.git", "repo/sub", "repo/nested/.git", "repo/nested/sub", "outside/sub" }) |path| try temporary.dir.createDirPath(std.testing.io, path);
    const files = [_]struct { path: []const u8, text: []const u8 }{
        .{ .path = "repo/.gitignore", .text = "ignored.txt\nsub/\n" }, .{ .path = "repo/kept.txt", .text = "keep" },
        .{ .path = "repo/ignored.txt", .text = "ignored" },            .{ .path = "repo/.hidden.txt", .text = "hidden" },
        .{ .path = "repo/sub/hidden.txt", .text = "ignored" },         .{ .path = "repo/nested/kept.txt", .text = "nested" },
        .{ .path = "repo/nested/sub/visible.txt", .text = "visible" }, .{ .path = "outside/.gitignore", .text = "ignored.txt\n" },
        .{ .path = "outside/ignored.txt", .text = "ignored" },         .{ .path = "outside/kept.txt", .text = "kept" },
        .{ .path = "outside/sub/code.ts", .text = "code" },
    };
    for (files) |row| try temporary.dir.writeFile(std.testing.io, .{ .sub_path = row.path, .data = row.text });
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_size = try temporary.dir.realPath(std.testing.io, &root_buffer);
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"sdk-real-fd-corpus"});
    const definition = try createDefinition(engine, "find", root_buffer[0..root_size], true);
    defer engine.freeValue(definition);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try vm.put(engine, global, "fdDefinition", c.JS_DupValue(engine.context, definition));
    try vm.put(engine, global, "nativeFdLinux", c.pi_js_bool(engine.context, @intFromBool(@import("builtin").os.tag == .linux)));
    try vm.put(engine, global, "fdCwd", try sdk.text(engine, root_buffer[0..root_size]));
    const source = @embedFile("../durable/fixtures/sdk-default-find-1ced.json");
    try vm.put(engine, global, "fdSource", try engine.checked(c.JS_ParseJSON(engine.context, source, source.len, "actual-default-fd")));
    const output = engine.evalModule(
        \\const normalize=v=>typeof v==='string'?v.replaceAll(fdCwd,'$CWD').replaceAll('\\','/'):Array.isArray(v)?v.map(normalize):v&&typeof v==='object'?Object.fromEntries(Object.entries(v).map(([k,x])=>[k,normalize(x)])):v;
        \\for(const expected of fdSource.cases){let result,error;try{result=await fdDefinition.execute('native',expected.args)}catch(e){error={name:e.name,message:e.message}}const platformError=nativeFdLinux?expected.errorLinux??expected.error:expected.error,observed=normalize(platformError?error:result),wanted=platformError??(nativeFdLinux?expected.resultLinux??expected.result:expected.result);if(JSON.stringify(observed)!==JSON.stringify(wanted))throw Error(expected.name+' '+JSON.stringify({observed,wanted}));}
    , "actual-sdk-default-fd") catch |err| {
        std.debug.print("Actual Source fd: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(output);
}

test "ToolInfo SDK custom find operations return before delegated awaits cancel independently and preserve marked factory ownership" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_stream.zig").install(engine);
    const exports = try vm.object(engine);
    defer engine.freeValue(exports);
    try sdk.install(engine, exports);
    try engine.registerValueModule("sdk-custom-find", exports);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const source = @embedFile("../durable/fixtures/sdk-custom-find-async-1ced.json");
    try vm.put(engine, global, "customFindSource", try engine.checked(c.JS_ParseJSON(engine.context, source, source.len, "actual-source-custom-find")));
    try vm.put(engine, global, "customFindBase", try sdk.text(engine, if (@import("builtin").os.tag == .windows) "C:/sdk-base" else "/sdk-base"));
    try vm.put(engine, global, "customFindOverride", try sdk.text(engine, if (@import("builtin").os.tag == .windows) "C:/override" else "/override"));
    const output = engine.evalModule(
        \\import{createFindToolDefinition,createFindTool}from'sdk-custom-find';
        \\const cases=[],cwd=customFindBase;
        \\{
        \\ let release;const gate=new Promise(resolve=>release=resolve),calls=[],operations={exists(path){calls.push(['exists',path]);return gate},glob(pattern,path,options){calls.push(['glob',pattern,path,options]);return[path+'/owned.txt']}};
        \\ const options={operations},definition=createFindToolDefinition(cwd,options);options.operations={exists(){throw Error('mutated')}};
        \\ const pending=definition.execute('gated',{pattern:'*.txt'},undefined,undefined,{cwd:customFindOverride}),isPromise=pending instanceof Promise,before=calls.map(row=>row[0]);release(true);const result=await pending;
        \\ cases.push({name:'gated-custom',isPromise,before,calls,result});
        \\}
        \\{
        \\ let release;const gate=new Promise(resolve=>release=resolve),events=[],controller=new AbortController(),signal={get aborted(){return controller.signal.aborted},addEventListener(...args){events.push(['add',args[0],args[2]?.once===true]);return controller.signal.addEventListener(...args)},removeEventListener(...args){events.push(['remove',args[0]]);return controller.signal.removeEventListener(...args)}};
        \\ const definition=createFindToolDefinition(cwd,{operations:{exists:()=>gate,glob(){events.push(['glob']);return[]}}});const pending=definition.execute('cancel',{pattern:'*'},signal);controller.abort();let error;try{await pending}catch(e){error={name:e.name,message:e.message}}release(true);for(let i=0;i<3;i++)await Promise.resolve();cases.push({name:'cancel-delegated-await',error,events});
        \\}
        \\{
        \\ const error=new Error('owned failure'),definition=createFindToolDefinition(cwd,{operations:{exists(){throw error},glob:()=>[]}});let thrown;try{await definition.execute('raw',{pattern:'*'})}catch(value){thrown=value}
        \\ const wrapped=createFindTool(cwd,{operations:{exists:()=>true,glob:()=>[]}});cases.push({name:'factory-wrapper',originalError:thrown===error,keys:Object.keys(wrapped),sharedParameters:wrapped.parameters===definition.parameters,result:await wrapped.execute('wrapped',{pattern:'*'})});
        \\}
        \\const windowsPath=customFindOverride.replaceAll('/','\\');const encoded=JSON.stringify(cases).replaceAll(customFindOverride,'$OVERRIDE').replaceAll(JSON.stringify(windowsPath).slice(1,-1),'$OVERRIDE');
        \\const actual=JSON.parse(encoded);if(JSON.stringify(actual)!==JSON.stringify(customFindSource.cases))throw Error(JSON.stringify({actual,expected:customFindSource.cases}));
    , "actual-sdk-custom-find") catch |err| {
        std.debug.print("Actual Source custom find: {s}\n", .{engine.last_error orelse "no diagnostic"});
        if (engine.captured_exception) |exception_value| {
            const stack = try vm.get(engine, exception_value, "stack");
            defer engine.freeValue(stack);
            const stack_text = try engine.toString(stack);
            defer engine.gpa.free(stack_text);
            std.debug.print("Custom find original stack: {s}\n", .{stack_text});
        }
        return err;
    };
    engine.freeValue(output);
}

test "ToolInfo SDK actual ripgrep formatter preserves Source UTF16 cuts lone surrogates and byte window details" {
    var environment = try std.process.Environ.createMap(std.testing.environ, std.testing.allocator);
    defer environment.deinit();
    const fixture_directory = environment.get("PI_SDK_TOOL_FIXTURE_DIR") orelse return error.SkipZigTest;
    const owned_fixture = try std.testing.allocator.dupe(u8, fixture_directory);
    defer std.testing.allocator.free(owned_fixture);
    try environment.put("PI_CODING_AGENT_DIR", owned_fixture);
    try environment.put("PI_OFFLINE", "1");
    const rg = (try @import("../agent/tool_manager.zig").ensure(std.testing.allocator, std.testing.io, &environment, .rg, .{ .offline = true })) orelse return error.MissingSDKRgFixture;
    defer std.testing.allocator.free(rg);
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var content: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer content.deinit();
    for (0..501) |_| try content.writer.writeAll("é");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "bmp.txt", .data = content.written() });
    content.clearRetainingCapacity();
    for (0..498) |_| try content.writer.writeByte('a');
    try content.writer.writeAll("😀z");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "pair.txt", .data = content.written() });
    content.clearRetainingCapacity();
    for (0..499) |_| try content.writer.writeByte('a');
    try content.writer.writeAll("😀z");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "half.txt", .data = content.written() });
    content.clearRetainingCapacity();
    for (0..400) |index| {
        if (index != 0) try content.writer.writeByte('\n');
        try content.writer.print("line{d} ", .{index});
        for (0..100) |_| try content.writer.writeAll("é");
    }
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "long.txt", .data = content.written() });
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_size = try temporary.dir.realPath(std.testing.io, &root_buffer);
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"sdk-real-rg-corpus"});
    const definition = try createDefinition(engine, "grep", root_buffer[0..root_size], true);
    defer engine.freeValue(definition);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try vm.put(engine, global, "rgDefinition", c.JS_DupValue(engine.context, definition));
    const source = @embedFile("../durable/fixtures/sdk-grep-unicode-1ced.json");
    try vm.put(engine, global, "rgSource", try engine.checked(c.JS_ParseJSON(engine.context, source, source.len, "actual-rg-utf16")));
    const output = engine.evalModule(
        \\for(const expected of rgSource.cases){const observed=await rgDefinition.execute('native',expected.args);if(JSON.stringify(observed)!==JSON.stringify(expected.result))throw Error(expected.name+' '+JSON.stringify({observed,wanted:expected.result}));}
    , "actual-sdk-rg-utf16") catch |err| {
        std.debug.print("Actual Source ripgrep Unicode: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(output);
}

test "ToolInfo SDK builtin factory worker admission projection and custom operation cycles retire every failed host allocation" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "owned.txt", .data = "owned" });
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_size = try temporary.dir.realPath(std.testing.io, &root_buffer);
    const Probe = struct {
        fn exercise(gpa: std.mem.Allocator, root: []const u8) !void {
            const engine = try Engine.init(gpa, .{});
            defer engine.deinit();
            engine.native_io = std.testing.io;
            try @import("native_stream.zig").install(engine);
            const exports = try vm.object(engine);
            defer engine.freeValue(exports);
            try installFindFactories(engine, exports);
            try engine.registerValueModule("sdk-builtin-allocation", exports);
            const definitions = try createDefinitions(engine, root, true);
            defer engine.freeValue(definitions);
            const global = c.JS_GetGlobalObject(engine.context);
            defer engine.freeValue(global);
            try vm.put(engine, global, "allocationDefinitions", c.JS_DupValue(engine.context, definitions));
            try vm.put(engine, global, "allocationRoot", try sdk.text(engine, root));
            const output = engine.evalModule(
                \\import{createFindToolDefinition,createFindTool}from'sdk-builtin-allocation';
                \\const read=allocationDefinitions.find(tool=>tool.name==='read');const readResult=await read.execute('allocation',{path:'owned.txt'});if(readResult.content[0].text!=='owned'||readResult.structuredContent!=='owned')throw Error('owned native read');
                \\await(async()=>{const operations={exists:async()=>true,glob:async(_,root)=>[root+'/owned.txt']};const definition=createFindToolDefinition(allocationRoot,{operations});operations.definition=definition;const result=await definition.execute('custom',{pattern:'*'});if(result.content[0].text!=='owned.txt')throw Error('marked custom factory');const wrapped=createFindTool(allocationRoot,{operations:{exists:()=>true,glob:()=>[]}});if((await wrapped.execute('wrapped',{pattern:'*'})).content[0].text!=='No files found matching pattern')throw Error('wrapped custom factory')})();
            , "sdk-builtin-allocation") catch |err| {
                const allocator: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                if (!allocator.has_induced_failure) std.debug.print("SDK builtin allocation baseline: {s}\n", .{engine.last_error orelse @errorName(err)});
                return err;
            };
            engine.freeValue(output);
            _ = try engine.drainReadyJobs();
            c.JS_RunGC(engine.runtime);
            try std.testing.expect(!pending(engine));
        }
        fn run(gpa: std.mem.Allocator, root: []const u8) !void {
            exercise(gpa, root) catch |err| {
                const allocator: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                if (allocator.has_induced_failure and (err == error.OutOfMemory or err == error.JavaScriptException)) return error.OutOfMemory;
                return err;
            };
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{root_buffer[0..root_size]});
}
