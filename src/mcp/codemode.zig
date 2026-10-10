//! Isolated directly linked C VM for codemode user scripts. Host callbacks,
//! JSON ownership, output and storage are implemented in Zig.
const std = @import("std");
const engine_mod = @import("../extensions/engine.zig");
const c = engine_mod.c;
const json = @import("protocol.zig").json;
const Value = json.Value;
const discovery = @import("codemode_discovery.zig");
const models = @import("codemode_models.zig");

pub const Tool = struct {
    name: []const u8,
    description: []const u8 = "",
    discovery_metadata: ?discovery.Tool = null,
    context: ?*anyopaque = null,
    /// Native workers may call different tools concurrently. The callback must
    /// not access VM values and must observe its cooperative abort flag.
    execute: *const fn (?*anyopaque, std.mem.Allocator, ?Value, ?*bool) anyerror!json.Owned,
    execute_sequenced: ?*const fn (?*anyopaque, std.mem.Allocator, ?Value, ?*bool, usize) anyerror!json.Owned = null,
    /// Agent adapters can return an owned marker with the exact error message;
    /// ordinary sandbox tools keep arbitrary object results unchanged.
    error_marker: bool = false,
    success_envelope: bool = false,
};
pub const Options = struct {
    model_runtime: ?models.Runtime = null,
    model_call_id: []const u8 = "codemode",
    progress_context: ?*anyopaque = null,
    progress: ?*const fn (?*anyopaque, Value) anyerror!void = null,
    enable_discovery: bool = false,
    timeout_ms: ?u64 = 300_000,
    memory_limit: usize = 256 * 1024 * 1024,
    stack_limit: usize = 1024 * 1024,
    interrupt_budget: ?f64 = null,
    abort_flag: ?*bool = null,
    store: Value = .{ .object = .empty },
};
const Work = struct {
    gpa: std.mem.Allocator,
    tool: Tool,
    args: ?json.Owned,
    sequence: usize = 0,
    aborted: bool = false,
    done: std.atomic.Value(bool) = .init(false),
    future: ?std.Io.Future(anyerror!json.Owned) = null,
    model_operation: ?models.Operation = null,
    model_runtime: ?models.Runtime = null,
    model_ref: ?[]u8 = null,
    model_admitted: std.atomic.Value(bool) = .init(false),
    fn modelAdmitted(raw: ?*anyopaque, canonical: Value) !void {
        const self: *Work = @ptrCast(@alignCast(raw.?));
        self.model_ref = try std.fmt.allocPrint(self.gpa, "{s}/{s}", .{ json.get(canonical, "provider").?.string, json.get(canonical, "id").?.string });
        self.model_admitted.store(true, .release);
    }
    fn noop(_: ?*anyopaque, _: std.mem.Allocator, _: ?Value, _: ?*bool) anyerror!json.Owned {
        return error.UnreachableModelTool;
    }
    fn limited(self: *const Work) bool {
        return self.model_operation == .classify or self.model_operation == .generateImages;
    }
    fn run(self: *Work) anyerror!json.Owned {
        defer self.done.store(true, .release);
        if (self.model_operation) |operation| {
            var runtime = self.model_runtime.?;
            runtime.admitted_context = self;
            runtime.admitted = modelAdmitted;
            var outcome = try models.executeOutcome(self.gpa, runtime, operation, self.args.?.value, &self.aborted);
            if (outcome.is_error) return outcome.value;
            defer outcome.value.deinit();
            var result = try json.Owned.empty(self.gpa);
            errdefer result.deinit();
            const a = result.arena.allocator();
            result.value = .{ .object = .empty };
            try result.value.object.put(a, "__pi_codemode_value", try json.clone(a, outcome.value.value));
            return result;
        }
        if (self.tool.execute_sequenced) |callback| return callback(self.tool.context, self.gpa, if (self.args) |args| args.value else null, &self.aborted, self.sequence);
        return self.tool.execute(self.tool.context, self.gpa, if (self.args) |args| args.value else null, &self.aborted);
    }
};
const Pending = struct { work: *Work, resolve: c.JSValue, reject: c.JSValue, started: i64, record_index: ?usize };
const Execution = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    engine: *engine_mod.Engine,
    tools: []const Tool,
    options: Options,
    result: json.Owned,
    stored: Value,
    writes: Value = .{ .object = .empty },
    pending: std.ArrayList(Pending) = .empty,
    output_chars: usize = 0,
    output_overflow: bool = false,
    exit_requested: bool = false,
    deadline: ?i64,
    aborted: bool = false,
    timed_out: bool = false,
    interrupt_polls: f64 = 0,
    budget_exhausted: bool = false,
    script_settled: bool = false,
    tool_names: std.ArrayList([]u8) = .empty,
    discovery_tools: []const discovery.Tool = &.{},
    model_call_count: usize = 0,

    fn from(context: ?*c.JSContext) *Execution {
        const engine = engine_mod.Engine.fromContext(context.?);
        return @ptrCast(@alignCast(engine.host_data.?));
    }
    fn now(self: *Execution) i64 {
        return std.Io.Clock.awake.now(self.io).toMilliseconds();
    }
    fn interrupt(_: ?*c.JSRuntime, raw: ?*anyopaque) callconv(.c) c_int {
        const self: *Execution = @ptrCast(@alignCast(raw.?));
        return @intFromBool(self.checkLimits(true));
    }
    fn checkLimits(self: *Execution, consume_poll: bool) bool {
        if (self.options.abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) {
            self.aborted = true;
            return true;
        };
        if (self.deadline) |deadline| if (self.now() >= deadline) {
            self.timed_out = true;
            return true;
        };
        if (self.exit_requested or self.output_overflow or self.budget_exhausted or self.script_settled) return true;
        if (consume_poll) if (self.options.interrupt_budget) |budget| {
            self.interrupt_polls += 1;
            if (!(self.interrupt_polls <= budget)) {
                self.budget_exhausted = true;
                self.timed_out = true;
                return true;
            }
        };
        return false;
    }
    fn drainJobs(self: *Execution) !void {
        defer self.engine.finishJob();
        while (c.JS_IsJobPending(self.engine.runtime)) {
            const jobs = try self.engine.runReadyJobs(50);
            if (self.script_settled) return;
            if (jobs == 50 and self.checkLimits(true)) return;
        }
    }
    fn markSettled(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
        from(context).script_settled = true;
        return c.pi_js_undefined();
    }
    fn observeTerminal(self: *Execution, promise: c.JSValue) !void {
        if (!c.JS_IsObject(promise)) return;
        const then = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, promise, "then"));
        defer self.engine.freeValue(then);
        const callback = try self.engine.checked(c.JS_NewCFunction(self.engine.context, markSettled, "", 0));
        defer self.engine.freeValue(callback);
        var callbacks = [_]c.JSValue{ callback, callback };
        const observed = try self.engine.checked(c.JS_Call(self.engine.context, then, promise, 2, &callbacks));
        self.engine.freeValue(observed);
    }
    fn fail(self: *Execution, cause: anyerror) c.JSValue {
        if (cause == error.JavaScriptException) return self.engine.throwCaptured();
        if (cause == error.OutOfMemory) return c.JS_ThrowOutOfMemory(self.engine.context);
        return c.JS_ThrowTypeError(self.engine.context, "%s", @as([*:0]const u8, @errorName(cause)));
    }
    fn put(self: *Execution, object: c.JSValue, name: [:0]const u8, value: c.JSValue) !void {
        if (c.JS_DefinePropertyValueStr(self.engine.context, object, name.ptr, value, c.JS_PROP_ENUMERABLE) < 0) return error.JavaScriptException;
    }
    fn discoveryError(self: *Execution, message: [:0]const u8) anyerror!c.JSValue {
        const value = try self.engine.checked(c.JS_NewError(self.engine.context));
        var transferred = false;
        errdefer if (!transferred) self.engine.freeValue(value);
        try self.put(value, "message", try self.engine.checked(c.JS_NewString(self.engine.context, message)));
        transferred = true;
        _ = c.JS_Throw(self.engine.context, value);
        return error.JavaScriptException;
    }
    fn discoveryValue(self: *Execution, kind: c_int, argc: c_int, argv: [*c]c.JSValue) !c.JSValue {
        const context = self.engine.context;
        if (argc == 0 or !c.JS_IsString(argv[0])) return self.discoveryError(switch (kind) {
            0 => "searchTools() expects a query string",
            1 => "describeTool() expects a tool name",
            else => "describeNamespace() expects a namespace name",
        });
        const name = try self.engine.toString(argv[0]);
        defer self.gpa.free(name);
        if (kind == 1) {
            const index = try discovery.findTool(self.gpa, self.discovery_tools, name) orelse return c.pi_js_undefined();
            const sample = self.discovery_tools[index].sample;
            return self.engine.checked(c.JS_NewStringLen(context, sample.ptr, sample.len));
        }
        if (kind == 2) {
            var namespace: ?discovery.Namespace = null;
            const result = try self.engine.checked(c.JS_NewObject(context));
            errdefer self.engine.freeValue(result);
            const names = try self.engine.checked(c.JS_NewArray(context));
            defer self.engine.freeValue(names);
            var index: u32 = 0;
            for (self.discovery_tools) |tool| if (tool.namespace) |info| {
                if (!try discovery.namespaceMatches(self.gpa, info.name, name)) continue;
                if (namespace == null) namespace = info;
                const id = try discovery.identifier(self.gpa, tool.name);
                defer self.gpa.free(id);
                if (c.JS_SetPropertyUint32(context, names, index, c.JS_NewStringLen(context, id.ptr, id.len)) < 0) return error.JavaScriptException;
                index += 1;
            };
            const info = namespace orelse {
                self.engine.freeValue(result);
                return c.pi_js_undefined();
            };
            try self.put(result, "name", try self.engine.checked(c.JS_NewStringLen(context, info.name.ptr, info.name.len)));
            if (info.description.len > 0) try self.put(result, "description", try self.engine.checked(c.JS_NewStringLen(context, info.description.ptr, info.description.len)));
            if (info.instructions.len > 0) try self.put(result, "instructions", try self.engine.checked(c.JS_NewStringLen(context, info.instructions.ptr, info.instructions.len)));
            try self.put(result, "tools", c.JS_DupValue(context, names));
            return result;
        }
        var limit: usize = 8;
        var namespace: ?[]u8 = null;
        defer if (namespace) |value| self.gpa.free(value);
        if (argc > 1 and !c.JS_IsUndefined(argv[1]) and !c.JS_IsNull(argv[1])) {
            const requested = try self.engine.checked(c.JS_GetPropertyStr(context, argv[1], "limit"));
            defer self.engine.freeValue(requested);
            if (!c.JS_IsUndefined(requested) and !c.JS_IsNull(requested)) {
                if (!c.JS_IsNumber(requested)) return self.discoveryError("searchTools() limit must be a positive integer");
                var number: f64 = undefined;
                if (c.JS_ToFloat64(context, &number, requested) < 0) return error.JavaScriptException;
                if (!std.math.isFinite(number) or number <= 0 or @floor(number) != number) return self.discoveryError("searchTools() limit must be a positive integer");
                limit = @intFromFloat(@min(number, @as(f64, @floatFromInt(self.discovery_tools.len))));
            }
            const requested_namespace = try self.engine.checked(c.JS_GetPropertyStr(context, argv[1], "namespace"));
            defer self.engine.freeValue(requested_namespace);
            if (!c.JS_IsUndefined(requested_namespace) and !c.JS_IsNull(requested_namespace)) {
                if (!c.JS_IsString(requested_namespace)) return self.discoveryError("searchTools() namespace must be a string");
                namespace = try self.engine.toString(requested_namespace);
            }
        }
        const matches = try discovery.rank(self.gpa, self.discovery_tools, name, limit, namespace);
        defer self.gpa.free(matches);
        const result = try self.engine.checked(c.JS_NewArray(context));
        errdefer self.engine.freeValue(result);
        for (matches, 0..) |match, index| {
            const tool_index = (try discovery.findTool(self.gpa, self.discovery_tools, match.name)).?;
            const tool = self.discovery_tools[tool_index];
            const id = try discovery.identifier(self.gpa, tool.name);
            defer self.gpa.free(id);
            const value = try self.engine.checked(c.JS_NewObject(context));
            defer self.engine.freeValue(value);
            try self.put(value, "name", try self.engine.checked(c.JS_NewStringLen(context, id.ptr, id.len)));
            try self.put(value, "description", try self.engine.checked(c.JS_NewStringLen(context, tool.sample.ptr, tool.sample.len)));
            if (c.JS_SetPropertyUint32(context, result, @intCast(index), c.JS_DupValue(context, value)) < 0) return error.JavaScriptException;
        }
        return result;
    }
    fn discover(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
        const self = from(context);
        var callbacks: [2]c.JSValue = undefined;
        const promise = self.engine.checked(c.JS_NewPromiseCapability(context, &callbacks)) catch |cause| return self.fail(cause);
        defer for (callbacks) |value| self.engine.freeValue(value);
        var rejected = false;
        const value = self.discoveryValue(magic, argc, argv) catch |cause| blk: {
            rejected = true;
            _ = self.fail(cause);
            break :blk c.JS_GetException(context);
        };
        defer self.engine.freeValue(value);
        var parameters = [_]c.JSValue{value};
        const settled = c.JS_Call(context, callbacks[@intFromBool(rejected)], c.pi_js_undefined(), 1, &parameters);
        self.engine.freeValue(settled);
        return promise;
    }
    fn overrideGet(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
        return c.JS_DupValue(context, data[2]);
    }
    fn overrideSet(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
        if (c.JS_IsStrictEqual(context, receiver, data[0])) return c.JS_ThrowTypeError(context, "Cannot assign to read only property of a built-in");
        if (!c.JS_IsObject(receiver)) return c.pi_js_undefined();
        const atom = c.JS_ValueToAtom(context, data[1]);
        if (atom == c.JS_ATOM_NULL) return c.JS_Throw(context, c.JS_GetException(context));
        defer c.JS_FreeAtom(context, atom);
        if (c.JS_DefinePropertyValue(context, receiver, atom, c.JS_DupValue(context, if (argc > 0) argv[0] else c.pi_js_undefined()), c.JS_PROP_C_W_E) < 0) return c.JS_Throw(context, c.JS_GetException(context));
        return c.pi_js_undefined();
    }
    fn freezeGraph(self: *Execution, globals: c.JSValue) !void {
        const engine = self.engine;
        const object_type = try engine.checked(c.JS_GetPropertyStr(engine.context, globals, "Object"));
        defer engine.freeValue(object_type);
        const object_prototype = try engine.checked(c.JS_GetPropertyStr(engine.context, object_type, "prototype"));
        defer engine.freeValue(object_prototype);
        const freeze = try engine.checked(c.JS_GetPropertyStr(engine.context, object_type, "freeze"));
        defer engine.freeValue(freeze);
        var objects: std.ArrayList(c.JSValue) = .empty;
        var seen: std.AutoHashMapUnmanaged(usize, void) = .empty;
        defer seen.deinit(self.gpa);
        defer {
            for (objects.items) |value| engine.freeValue(value);
            objects.deinit(self.gpa);
        }
        const root = c.JS_DupValue(engine.context, globals);
        objects.append(self.gpa, root) catch |cause| {
            engine.freeValue(root);
            return cause;
        };
        // Iterator/generator intrinsics are not reached through ordinary global
        // properties. These expressions select values; all graph traversal and
        // descriptor changes are performed by the native host below.
        for ([_][]const u8{
            "Object.getPrototypeOf(function*(){})",
            "Object.getPrototypeOf(async function(){})",
            "Object.getPrototypeOf(async function*(){})",
            "Object.getPrototypeOf(Int8Array)",
            "Object.getPrototypeOf([][Symbol.iterator]())",
            "Object.getPrototypeOf(new Map()[Symbol.iterator]())",
            "Object.getPrototypeOf(new Set()[Symbol.iterator]())",
            "Object.getPrototypeOf(''[Symbol.iterator]())",
            "Object.getPrototypeOf(/a/[Symbol.matchAll](''))",
        }) |selector| {
            const selected = try engine.eval(selector, "codemode-intrinsic.js", c.JS_EVAL_TYPE_GLOBAL);
            defer engine.freeValue(selected);
            try self.graphAdd(&objects, &seen, globals, selected);
        }
        var index: usize = 0;
        while (index < objects.items.len) : (index += 1) {
            const object = objects.items[index];
            const prototype = try engine.checked(c.JS_GetPrototype(engine.context, object));
            defer engine.freeValue(prototype);
            try self.graphAdd(&objects, &seen, globals, prototype);
            var names: [*c]c.JSPropertyEnum = null;
            var length: u32 = 0;
            if (c.JS_GetOwnPropertyNames(engine.context, &names, &length, object, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK) < 0) return error.JavaScriptException;
            defer {
                for (names[0..length]) |name| c.JS_FreeAtom(engine.context, name.atom);
                c.js_free(engine.context, names);
            }
            for (names[0..length]) |name| {
                var descriptor: c.JSPropertyDescriptor = undefined;
                const found = c.JS_GetOwnProperty(engine.context, &descriptor, object, name.atom);
                if (found < 0) return error.JavaScriptException;
                if (found == 0) continue;
                defer {
                    engine.freeValue(descriptor.value);
                    engine.freeValue(descriptor.getter);
                    engine.freeValue(descriptor.setter);
                }
                try self.graphAdd(&objects, &seen, globals, descriptor.value);
                try self.graphAdd(&objects, &seen, globals, descriptor.getter);
                try self.graphAdd(&objects, &seen, globals, descriptor.setter);
                if (index == 0 and descriptor.flags & c.JS_PROP_CONFIGURABLE != 0 and descriptor.flags & c.JS_PROP_TMASK == c.JS_PROP_NORMAL) {
                    if (c.JS_DefineProperty(engine.context, object, name.atom, c.pi_js_undefined(), c.pi_js_undefined(), c.pi_js_undefined(), c.JS_PROP_HAS_CONFIGURABLE | c.JS_PROP_HAS_WRITABLE) < 0) return error.JavaScriptException;
                }
                const key = try engine.checked(c.JS_AtomToValue(engine.context, name.atom));
                defer engine.freeValue(key);
                var overridable = c.JS_IsStrictEqual(engine.context, object, object_prototype);
                if (c.JS_IsString(key)) {
                    const text = try engine.toString(key);
                    defer self.gpa.free(text);
                    for ([_][]const u8{ "constructor", "name", "message", "toString", "toLocaleString", "valueOf", "toJSON" }) |allowed| if (std.mem.eql(u8, allowed, text)) {
                        overridable = true;
                        break;
                    };
                }
                if (index != 0 and overridable and descriptor.flags & c.JS_PROP_WRITABLE != 0 and descriptor.flags & c.JS_PROP_CONFIGURABLE != 0) {
                    var data = [_]c.JSValue{ object, key, descriptor.value };
                    const getter = try engine.checked(c.JS_NewCFunctionData2(engine.context, overrideGet, "get", 0, 0, data.len, &data));
                    const setter = engine.checked(c.JS_NewCFunctionData2(engine.context, overrideSet, "set", 1, 0, data.len, &data)) catch |cause| {
                        engine.freeValue(getter);
                        return cause;
                    };
                    // DefinePropertyGetSet consumes both callbacks.
                    if (c.JS_DefinePropertyGetSet(engine.context, object, name.atom, getter, setter, descriptor.flags & c.JS_PROP_ENUMERABLE) < 0) return error.JavaScriptException;
                }
            }
            if (index != 0) {
                var args = [_]c.JSValue{object};
                const frozen = try engine.checked(c.JS_Call(engine.context, freeze, object_type, 1, &args));
                engine.freeValue(frozen);
            }
        }
    }
    fn graphAdd(self: *Execution, objects: *std.ArrayList(c.JSValue), seen: *std.AutoHashMapUnmanaged(usize, void), globals: c.JSValue, value: c.JSValue) !void {
        if (!c.JS_IsObject(value) or c.JS_IsStrictEqual(self.engine.context, value, globals)) return;
        // All retained entries are objects, so their VM pointer is exactly the
        // identity used by strict equality. Retained roots prevent pointer reuse.
        const identity = @intFromPtr(c.pi_js_object_identity(value));
        if (seen.contains(identity)) return;
        if (objects.items.len >= 8192) return error.CodemodeIntrinsicGraphLimit;
        try seen.ensureUnusedCapacity(self.gpa, 1);
        try objects.ensureUnusedCapacity(self.gpa, 1);
        const retained = c.JS_DupValue(self.engine.context, value);
        seen.putAssumeCapacity(identity, {});
        objects.appendAssumeCapacity(retained);
    }
    fn guardedGet(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
        const self = from(context);
        if (argc < 2) return c.pi_js_undefined();
        const atom = c.JS_ValueToAtom(context, argv[1]);
        if (atom == c.JS_ATOM_NULL) return c.JS_Throw(context, c.JS_GetException(context));
        defer c.JS_FreeAtom(context, atom);
        const present = c.JS_HasProperty(context, argv[0], atom);
        if (present < 0) return c.JS_Throw(context, c.JS_GetException(context));
        if (present > 0 or !c.JS_IsString(argv[1])) return c.JS_GetProperty(context, argv[0], atom);
        const property = self.engine.toString(argv[1]) catch |cause| return self.fail(cause);
        defer self.gpa.free(property);
        if (std.mem.eql(u8, property, "then") or std.mem.eql(u8, property, "toJSON")) return c.pi_js_undefined();
        const global = c.JS_GetGlobalObject(context);
        defer self.engine.freeValue(global);
        const object = self.engine.checked(c.JS_GetPropertyStr(context, global, "Object")) catch |cause| return self.fail(cause);
        defer self.engine.freeValue(object);
        const prototype = self.engine.checked(c.JS_GetPropertyStr(context, object, "prototype")) catch |cause| return self.fail(cause);
        defer self.engine.freeValue(prototype);
        if (c.JS_HasProperty(context, prototype, atom) > 0) return c.pi_js_undefined();
        const message = self.guardMessage(property) catch |cause| return self.fail(cause);
        defer self.gpa.free(message);
        const terminated = self.gpa.dupeZ(u8, message) catch |cause| return self.fail(cause);
        defer self.gpa.free(terminated);
        return c.JS_ThrowTypeError(context, "%s", terminated.ptr);
    }
    fn guardMessage(self: *Execution, property: []const u8) ![]u8 {
        const wanted = try comparable(self.gpa, property);
        defer self.gpa.free(wanted);
        var exact: std.ArrayList([]const u8) = .empty;
        defer exact.deinit(self.gpa);
        var close: std.ArrayList([]const u8) = .empty;
        defer close.deinit(self.gpa);
        for (self.tool_names.items) |name| {
            const candidate = try comparable(self.gpa, name);
            defer self.gpa.free(candidate);
            if (std.mem.eql(u8, wanted, candidate)) try exact.append(self.gpa, name) else if (wanted.len != 0 and (std.mem.indexOf(u8, candidate, wanted) != null or std.mem.indexOf(u8, wanted, candidate) != null)) try close.append(self.gpa, name);
        }
        var message: std.Io.Writer.Allocating = .init(self.gpa);
        errdefer message.deinit();
        try message.writer.print("tools.{s} does not exist.", .{property});
        const matches = if (exact.items.len != 0) exact.items else close.items;
        if (matches.len != 0) {
            try message.writer.writeAll(" Did you mean ");
            for (matches[0..@min(5, matches.len)], 0..) |name, index| {
                if (index != 0) try message.writer.writeAll(", ");
                try message.writer.print("tools.{s}", .{name});
            }
            try message.writer.writeByte('?');
        } else if (self.tool_names.items.len <= 20) {
            try message.writer.writeAll(" Available: ");
            for (self.tool_names.items, 0..) |name, index| {
                if (index != 0) try message.writer.writeAll(", ");
                try message.writer.writeAll(name);
            }
            try message.writer.writeByte('.');
        }
        try message.writer.print(" ALL_TOOLS lists every tool; searchTools(query) finds tools by topic. Check for a member with \"{s}\" in tools.", .{property});
        return message.toOwnedSlice();
    }
    fn parseArgument(self: *Execution, value: c.JSValue) !?json.Owned {
        if (c.JS_IsUndefined(value)) return null;
        const bytes = try self.engine.stringify(value);
        defer self.gpa.free(bytes);
        if (std.mem.eql(u8, bytes, "undefined")) return null;
        return try json.Owned.parse(self.gpa, bytes);
    }
    fn callTool(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
        const self = from(context);
        const args = self.parseArgument(if (argc > 0) argv[0] else c.pi_js_undefined()) catch |cause| return self.fail(cause);
        return self.enqueue(self.tools[@intCast(magic)], args, null) catch |cause| self.fail(cause);
    }
    fn callModel(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
        const self = from(context);
        const array = self.engine.checked(c.JS_NewArray(context)) catch |cause| return self.fail(cause);
        defer self.engine.freeValue(array);
        for (0..@intCast(argc)) |index| if (c.JS_SetPropertyUint32(context, array, @intCast(index), c.JS_DupValue(context, argv[index])) < 0) return self.fail(error.JavaScriptException);
        const args = self.parseArgument(array) catch |cause| return self.fail(cause);
        const operation: models.Operation = @enumFromInt(magic);
        const name: []const u8 = switch (operation) {
            .getModelsOfType => "models.getModelsOfType",
            .getAvailableOfType => "models.getAvailableOfType",
            .getModelOfType => "models.getModelOfType",
            .classify => "models.classify",
            .generateImages => "models.generateImages",
        };
        return self.enqueue(.{ .name = name, .execute = Work.noop, .error_marker = true, .success_envelope = true }, args, operation) catch |cause| self.fail(cause);
    }
    fn enqueue(self: *Execution, tool: Tool, args: ?json.Owned, operation: ?models.Operation) !c.JSValue {
        const context = self.engine.context;
        var owned_args = args;
        defer if (owned_args) |*value| value.deinit();
        var functions: [2]c.JSValue = undefined;
        const promise = self.engine.checked(c.JS_NewPromiseCapability(context, &functions)) catch |cause| return self.fail(cause);
        const work = self.gpa.create(Work) catch |cause| {
            for (functions) |value| self.engine.freeValue(value);
            self.engine.freeValue(promise);
            return self.fail(cause);
        };
        work.* = .{ .gpa = self.gpa, .tool = tool, .args = owned_args, .model_operation = operation, .model_runtime = self.options.model_runtime };
        owned_args = null;
        const started = self.now();
        var record_index: ?usize = null;
        if (operation == null) self.recordCall(work.tool.name, "cancelled", started) catch |cause| {
            if (work.args) |*value| value.deinit();
            self.gpa.destroy(work);
            for (functions) |value| self.engine.freeValue(value);
            self.engine.freeValue(promise);
            return self.fail(cause);
        };
        if (operation == null) {
            record_index = self.result.value.object.getPtr("calls").?.array.items.len - 1;
            work.sequence = record_index.? + 1;
        }
        self.pending.append(self.gpa, .{ .work = work, .resolve = functions[0], .reject = functions[1], .started = started, .record_index = record_index }) catch |cause| {
            if (work.args) |*value| value.deinit();
            self.gpa.destroy(work);
            for (functions) |value| self.engine.freeValue(value);
            self.engine.freeValue(promise);
            return self.fail(cause);
        };
        var active: usize = 0;
        for (self.pending.items) |pending| if (pending.work != work and pending.work.limited() and pending.work.future != null and !pending.work.done.load(.acquire)) {
            active += 1;
        };
        if (!work.limited() or active < 4) work.future = self.io.concurrent(Work.run, .{work}) catch |cause| {
            _ = self.pending.pop();
            if (work.args) |*value| value.deinit();
            self.gpa.destroy(work);
            for (functions) |value| self.engine.freeValue(value);
            self.engine.freeValue(promise);
            return self.fail(cause);
        };
        return promise;
    }
    fn appendText(self: *Execution, text: []const u8, console: bool) !void {
        if (self.exit_requested or self.output_overflow) return;
        const a = self.result.arena.allocator();
        const array = &self.result.value.object.getPtr("output").?.array;
        // The upstream quotas count UTF-16 code units rather than UTF-8 bytes.
        const count = utf16Length(text);
        if (array.items.len >= 100_000 or count > 16 * 1024 * 1024 -| self.output_chars) {
            self.output_overflow = true;
            return error.CodemodeOutputLimit;
        }
        var item: Value = .{ .object = .empty };
        try item.object.put(a, "type", .{ .string = "text" });
        try item.object.put(a, "text", .{ .string = try a.dupe(u8, text) });
        if (console) try item.object.put(a, "console", .{ .bool = true });
        try array.append(item);
        self.output_chars += count;
    }
    fn emitText(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
        const self = from(context);
        const value = if (argc > 0) argv[0] else c.pi_js_undefined();
        const rendered = (if (c.JS_IsObject(value)) self.engine.stringify(value) else self.engine.toString(value)) catch |cause| return self.fail(cause);
        defer self.gpa.free(rendered);
        self.appendText(rendered, false) catch |cause| return self.fail(cause);
        return c.pi_js_undefined();
    }
    fn consoleCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
        const self = from(context);
        var buffer: std.Io.Writer.Allocating = .init(self.gpa);
        defer buffer.deinit();
        for (0..@intCast(argc)) |index| {
            if (index != 0) buffer.writer.writeByte(' ') catch |cause| return self.fail(cause);
            const rendered = (if (c.JS_IsObject(argv[index])) self.engine.stringify(argv[index]) else self.engine.toString(argv[index])) catch self.engine.toString(argv[index]) catch |cause| return self.fail(cause);
            defer self.gpa.free(rendered);
            buffer.writer.writeAll(rendered) catch |cause| return self.fail(cause);
        }
        self.appendText(buffer.written(), true) catch |cause| return self.fail(cause);
        return c.pi_js_undefined();
    }
    fn image(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
        const self = from(context);
        self.appendImage(if (argc > 0) argv[0] else c.pi_js_undefined()) catch |cause| return self.fail(cause);
        return c.pi_js_undefined();
    }
    fn appendImage(self: *Execution, value: c.JSValue) !void {
        if (self.exit_requested or self.output_overflow) return;
        var url: []u8 = undefined;
        if (c.JS_IsString(value)) {
            url = try self.engine.toString(value);
        } else if (c.JS_IsObject(value) and !c.JS_IsArray(value)) {
            const image_url = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, value, "image_url"));
            defer self.engine.freeValue(image_url);
            if (!c.JS_IsUndefined(image_url)) {
                if (!c.JS_IsString(image_url)) return error.InvalidCodemodeImageInput;
                url = try self.engine.toString(image_url);
            } else {
                const kind = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, value, "type"));
                defer self.engine.freeValue(kind);
                const kind_text = try self.engine.toString(kind);
                defer self.gpa.free(kind_text);
                if (!std.mem.eql(u8, kind_text, "image")) return error.InvalidCodemodeImageBlockType;
                const data = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, value, "data"));
                defer self.engine.freeValue(data);
                if (!c.JS_IsString(data)) return error.InvalidCodemodeImageData;
                const text = try self.engine.toString(data);
                defer self.gpa.free(text);
                if (text.len == 0) return error.InvalidCodemodeImageData;
                url = if (text.len >= 5 and std.ascii.eqlIgnoreCase(text[0..5], "data:")) try self.gpa.dupe(u8, text) else try std.fmt.allocPrint(self.gpa, "data:;base64,{s}", .{text});
            }
        } else return error.InvalidCodemodeImageInput;
        defer self.gpa.free(url);
        const colon = std.mem.indexOfScalar(u8, url, ':') orelse return error.InvalidCodemodeImageUri;
        if (std.ascii.eqlIgnoreCase(url[0..colon], "http") or std.ascii.eqlIgnoreCase(url[0..colon], "https")) return error.RemoteCodemodeImageUnsupported;
        const comma = std.mem.indexOfScalar(u8, url, ',') orelse return error.InvalidCodemodeImageUri;
        if (!std.ascii.eqlIgnoreCase(url[0..colon], "data") or comma <= colon) return error.InvalidCodemodeImageUri;
        var parts = std.mem.splitScalar(u8, url[colon + 1 .. comma], ';');
        _ = parts.next();
        var base64 = false;
        while (parts.next()) |part| if (std.ascii.eqlIgnoreCase(part, "base64")) {
            base64 = true;
        };
        if (!base64) return error.InvalidCodemodeImageUri;
        var data: std.ArrayList(u8) = .empty;
        defer data.deinit(self.gpa);
        var iterator = std.unicode.Wtf8View.initUnchecked(url[comma + 1 ..]).iterator();
        while (iterator.nextCodepoint()) |point| {
            if (jsWhitespace(point)) continue;
            if (point > 127) return error.InvalidCodemodeImageBase64;
            try data.append(self.gpa, @intCast(point));
        }
        if (data.items.len == 0 or data.items.len % 4 != 0) return error.InvalidCodemodeImageBase64;
        var padding: usize = 0;
        for (data.items) |byte| {
            if (byte == '=') padding += 1 else if (padding != 0 or (!std.ascii.isAlphanumeric(byte) and byte != '+' and byte != '/')) return error.InvalidCodemodeImageBase64;
        }
        if (padding > 2) return error.InvalidCodemodeImageBase64;
        const mime: []const u8 = if (std.mem.startsWith(u8, data.items, "iVBORw0KGg")) "image/png" else if (std.mem.startsWith(u8, data.items, "/9j/") and (data.items.len == 4 or data.items[4] != '9')) "image/jpeg" else if (std.mem.startsWith(u8, data.items, "R0lGODdh") or std.mem.startsWith(u8, data.items, "R0lGODlh")) "image/gif" else if (data.items.len >= 16 and std.mem.startsWith(u8, data.items, "UklG") and std.mem.eql(u8, data.items[12..16], "RUJQ")) "image/webp" else return error.InvalidCodemodeImageFormat;
        const array = &self.result.value.object.getPtr("output").?.array;
        if (array.items.len >= 100_000 or data.items.len > 16 * 1024 * 1024 -| self.output_chars) {
            self.output_overflow = true;
            return error.CodemodeOutputLimit;
        }
        const a = self.result.arena.allocator();
        var item: Value = .{ .object = .empty };
        try item.object.put(a, "type", .{ .string = "image" });
        try item.object.put(a, "data", .{ .string = try a.dupe(u8, data.items) });
        try item.object.put(a, "mimeType", .{ .string = mime });
        try array.append(item);
        self.output_chars += data.items.len;
    }
    fn storeKey(self: *Execution, argc: c_int, argv: [*c]c.JSValue) ![]u8 {
        if (argc == 0 or !c.JS_IsString(argv[0])) return error.CodemodeStoreKeyMustBeString;
        return self.engine.toString(argv[0]);
    }
    fn store(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
        const self = from(context);
        const name = self.storeKey(argc, argv) catch |cause| return self.fail(cause);
        defer self.gpa.free(name);
        const a = self.result.arena.allocator();
        if (argc < 2 or c.JS_IsUndefined(argv[1])) {
            _ = self.stored.object.orderedRemove(name);
            self.writes.object.put(a, a.dupe(u8, name) catch |cause| return self.fail(cause), .null) catch |cause| return self.fail(cause);
            return c.pi_js_undefined();
        }
        const bytes = self.engine.stringify(argv[1]) catch |cause| return self.fail(cause);
        defer self.gpa.free(bytes);
        if (std.mem.eql(u8, bytes, "undefined")) return self.fail(error.CodemodeStoreNotSerializable);
        if (utf16Length(bytes) > 256 * 1024) return self.fail(error.CodemodeStoreValueLimit);
        var total: usize = utf16Length(name) + utf16Length(bytes);
        var iterator = self.stored.object.iterator();
        while (iterator.next()) |entry| {
            if (std.mem.eql(u8, entry.key_ptr.*, name)) continue;
            const encoded = json.stringify(self.gpa, entry.value_ptr.*) catch |cause| return self.fail(cause);
            defer self.gpa.free(encoded);
            total += utf16Length(entry.key_ptr.*) + utf16Length(encoded);
        }
        if (total > 1024 * 1024) return self.fail(error.CodemodeStoreTotalLimit);
        var parsed = json.Owned.parse(self.gpa, bytes) catch |cause| return self.fail(cause);
        defer parsed.deinit();
        const value = json.clone(a, parsed.value) catch |cause| return self.fail(cause);
        const owned_name = a.dupe(u8, name) catch |cause| return self.fail(cause);
        self.stored.object.put(a, owned_name, value) catch |cause| return self.fail(cause);
        self.writes.object.put(a, owned_name, .{ .array = .init(a) }) catch |cause| return self.fail(cause);
        return c.pi_js_undefined();
    }
    fn load(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
        const self = from(context);
        const name = self.storeKey(argc, argv) catch |cause| return self.fail(cause);
        defer self.gpa.free(name);
        return if (self.stored.object.get(name)) |value| self.engine.fromJsonValue(value) catch |cause| self.fail(cause) else c.pi_js_undefined();
    }
    fn exit(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
        const self = from(context);
        self.exit_requested = true;
        return c.JS_ThrowTypeError(context, "codemode exit");
    }
    fn dispatch(self: *Execution) !bool {
        if (self.pending.items.len == 0) return false;
        var selected: ?usize = null;
        var active: usize = 0;
        for (self.pending.items) |pending| if (pending.work.limited() and pending.work.future != null and !pending.work.done.load(.acquire)) {
            active += 1;
        };
        for (self.pending.items, 0..) |*pending, index| {
            if (pending.work.future == null and (!pending.work.limited() or active < 4)) {
                pending.work.future = try self.io.concurrent(Work.run, .{pending.work});
                if (pending.work.limited()) active += 1;
            }
            if (pending.record_index == null and pending.work.model_admitted.load(.acquire)) {
                try self.recordCall(pending.work.tool.name, "running", pending.started);
                pending.record_index = self.result.value.object.getPtr("calls").?.array.items.len - 1;
                self.model_call_count += 1;
                const a = self.result.arena.allocator();
                const record = &self.result.value.object.getPtr("calls").?.array.items[pending.record_index.?];
                try record.object.put(a, "id", .{ .string = try std.fmt.allocPrint(a, "{s}/{s}/{d}", .{ self.options.model_call_id, pending.work.tool.name, self.model_call_count }) });
                try record.object.put(a, "args", .{ .string = try a.dupe(u8, pending.work.model_ref.?) });
                _ = record.object.swapRemove("durationMs");
                if (self.options.progress) |notify| try notify(self.options.progress_context, self.result.value.object.get("calls").?);
            }
            if (pending.work.done.load(.acquire) and selected == null) selected = index;
        }
        const index = selected orelse {
            try self.io.sleep(.fromMilliseconds(1), .awake);
            return true;
        };
        const pending = self.pending.orderedRemove(index);
        defer {
            if (pending.work.args) |*args| args.deinit();
            if (pending.work.model_ref) |reference| self.gpa.free(reference);
            self.gpa.destroy(pending.work);
            self.engine.freeValue(pending.resolve);
            self.engine.freeValue(pending.reject);
        }
        var reply = pending.work.future.?.await(self.io) catch |cause| {
            if (cause == error.OutOfMemory) return cause;
            const message = try self.engine.checked(c.JS_NewError(self.engine.context));
            defer self.engine.freeValue(message);
            if (c.JS_SetPropertyStr(self.engine.context, message, "message", c.JS_NewString(self.engine.context, @errorName(cause))) < 0) return error.JavaScriptException;
            var args = [_]c.JSValue{message};
            const settled = try self.engine.checked(c.JS_Call(self.engine.context, pending.reject, c.pi_js_undefined(), 1, &args));
            self.engine.freeValue(settled);
            try self.completeCall(pending.record_index, "error", pending.started);
            return true;
        };
        defer reply.deinit();
        const success_value = if (pending.work.tool.success_envelope) json.get(reply.value, "__pi_codemode_value") else null;
        if (pending.work.tool.error_marker and success_value == null) if (json.get(reply.value, "__pi_codemode_error")) |error_value| {
            const error_text = try json.asString(error_value);
            const message = try self.engine.checked(c.JS_NewError(self.engine.context));
            defer self.engine.freeValue(message);
            if (c.JS_SetPropertyStr(self.engine.context, message, "message", c.JS_NewStringLen(self.engine.context, error_text.ptr, error_text.len)) < 0) return error.JavaScriptException;
            var parameters = [_]c.JSValue{message};
            const settled = try self.engine.checked(c.JS_Call(self.engine.context, pending.reject, c.pi_js_undefined(), 1, &parameters));
            self.engine.freeValue(settled);
            try self.completeCall(pending.record_index, "error", pending.started);
            return true;
        };
        const payload = success_value orelse reply.value;
        const value = if (pending.work.model_operation == .getModelOfType and payload == .null) c.pi_js_undefined() else try self.engine.fromJsonValue(payload);
        defer self.engine.freeValue(value);
        var args = [_]c.JSValue{value};
        const settled = try self.engine.checked(c.JS_Call(self.engine.context, pending.resolve, c.pi_js_undefined(), 1, &args));
        self.engine.freeValue(settled);
        const stop = json.get(payload, "stopReason");
        const status: []const u8 = if (pending.work.limited() and stop != null and stop.? == .string) if (std.mem.eql(u8, stop.?.string, "stop")) "ok" else if (std.mem.eql(u8, stop.?.string, "aborted")) "cancelled" else "error" else "ok";
        try self.completeCall(pending.record_index, status, pending.started);
        if (pending.work.limited()) {
            const a = self.result.arena.allocator();
            if (pending.record_index) |record_index| {
                const record = &self.result.value.object.getPtr("calls").?.array.items[record_index];
                if (json.get(payload, "errorMessage")) |message| if (message == .string and message.string.len > 0) {
                    var iterator = (try std.unicode.Wtf8View.init(message.string)).iterator();
                    var units: usize = 0;
                    var end: usize = 0;
                    while (iterator.nextCodepoint()) |point| {
                        units += if (point > 0xffff) @as(usize, 2) else 1;
                        if (units <= 497) end = iterator.i;
                    }
                    try record.object.put(a, "error", .{ .string = if (units > 500) try std.fmt.allocPrint(a, "{s}...", .{message.string[0..end]}) else try a.dupe(u8, message.string) });
                };
                if (json.get(payload, "usage")) |usage| {
                    if (json.get(usage, "cost")) |cost| if (json.get(cost, "total")) |total| try record.object.put(a, "cost", try json.clone(a, total));
                    const combined = if (self.result.value.object.get("usage")) |previous| try models.combineUsage(a, previous, usage) else try json.clone(a, usage);
                    try self.result.value.object.put(a, "usage", combined);
                }
            }
            if (pending.work.model_operation == .generateImages) if (json.get(payload, "output")) |blocks| if (blocks == .array) {
                var count: i64 = 0;
                for (blocks.array.items) |block| if (json.get(block, "type")) |kind| {
                    if (kind == .string and std.mem.eql(u8, kind.string, "image")) count += 1;
                };
                const previous = if (self.result.value.object.get("generatedImages")) |value_| value_.integer else 0;
                try self.result.value.object.put(a, "generatedImages", .{ .integer = previous + count });
            };
            if (self.options.progress) |notify| try notify(self.options.progress_context, self.result.value.object.get("calls").?);
        }
        return true;
    }
    fn completeCall(self: *Execution, optional_index: ?usize, status: []const u8, started: i64) !void {
        const index = optional_index orelse return;
        const a = self.result.arena.allocator();
        const record = &self.result.value.object.getPtr("calls").?.array.items[index];
        try record.object.put(a, "status", .{ .string = status });
        try record.object.put(a, "durationMs", .{ .integer = @max(0, self.now() - started) });
    }
    fn recordCall(self: *Execution, name: []const u8, status: []const u8, started: i64) !void {
        const a = self.result.arena.allocator();
        var record: Value = .{ .object = .empty };
        try record.object.put(a, "name", .{ .string = try a.dupe(u8, name) });
        try record.object.put(a, "status", .{ .string = status });
        try record.object.put(a, "durationMs", .{ .integer = @max(0, self.now() - started) });
        try self.result.value.object.getPtr("calls").?.array.append(record);
    }
};
fn utf16Length(bytes: []const u8) usize {
    var count: usize = 0;
    var iterator = std.unicode.Wtf8View.initUnchecked(bytes).iterator();
    while (iterator.nextCodepoint()) |point| count += if (point > 0xffff) @as(usize, 2) else 1;
    return count;
}
fn jsWhitespace(point: u21) bool {
    return switch (point) {
        9...13, 32, 0xa0, 0x1680, 0x2000...0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff => true,
        else => false,
    };
}
fn comparable(gpa: std.mem.Allocator, value: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(gpa);
    for (value) |byte| if (std.ascii.isAlphanumeric(byte)) try result.append(gpa, std.ascii.toLower(byte));
    return result.toOwnedSlice(gpa);
}
pub fn identifier(gpa: std.mem.Allocator, name: []const u8) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(gpa);
    var iterator = std.unicode.Wtf8View.initUnchecked(name).iterator();
    while (iterator.nextCodepoint()) |point| {
        const valid = point < 128 and (std.ascii.isAlphabetic(@intCast(point)) or point == '_' or point == '$' or (output.items.len != 0 and std.ascii.isDigit(@intCast(point))));
        try output.append(gpa, if (valid) @intCast(point) else '_');
    }
    if (output.items.len == 0) try output.append(gpa, '_');
    return output.toOwnedSlice(gpa);
}
pub fn execute(gpa: std.mem.Allocator, io: std.Io, tools: []const Tool, source: []const u8, options: Options) !json.Owned {
    const engine = try engine_mod.Engine.init(gpa, .{ .memory_limit = options.memory_limit, .stack_limit = options.stack_limit, .interrupt_budget = std.math.maxInt(u64) });
    defer engine.deinit();
    var state: Execution = .{ .gpa = gpa, .io = io, .engine = engine, .tools = tools, .options = options, .result = try json.Owned.empty(gpa), .stored = .{ .object = .empty }, .deadline = if (options.timeout_ms) |timeout| std.Io.Clock.awake.now(io).toMilliseconds() +| @as(i64, @intCast(@min(timeout, std.math.maxInt(i64)))) else null };
    errdefer state.result.deinit();
    const a = state.result.arena.allocator();
    const discovery_tools = try a.alloc(discovery.Tool, tools.len);
    for (tools, discovery_tools) |tool, *metadata| metadata.* = tool.discovery_metadata orelse .{ .name = tool.name, .description = tool.description, .sample = tool.description };
    state.discovery_tools = discovery_tools;
    state.result.value = .{ .object = .empty };
    try state.result.value.object.put(a, "output", .{ .array = .init(a) });
    try state.result.value.object.put(a, "calls", .{ .array = .init(a) });
    state.stored = try json.clone(a, options.store);
    defer {
        for (state.tool_names.items) |name| gpa.free(name);
        state.tool_names.deinit(gpa);
        for (state.pending.items) |*pending| {
            @atomicStore(bool, &pending.work.aborted, true, .release);
            if (pending.work.future) |*future| {
                if (future.cancel(io)) |reply| {
                    var owned = reply;
                    owned.deinit();
                } else |_| {}
            }
            if (pending.work.args) |*args| args.deinit();
            if (pending.work.model_ref) |reference| gpa.free(reference);
            gpa.destroy(pending.work);
            engine.freeValue(pending.resolve);
            engine.freeValue(pending.reject);
        }
        state.pending.deinit(gpa);
    }
    engine.host_data = &state;
    try engine.bindFunction("text", Execution.emitText, 1);
    try engine.bindFunction("image", Execution.image, 1);
    try engine.bindFunction("store", Execution.store, 2);
    try engine.bindFunction("load", Execution.load, 1);
    try engine.bindFunction("exit", Execution.exit, 0);
    const globals = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(globals);
    const tool_object = try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null()));
    defer engine.freeValue(tool_object);
    const metadata = try engine.checked(c.JS_NewArray(engine.context));
    defer engine.freeValue(metadata);
    for (tools, 0..) |tool, index| {
        const js_name = try identifier(gpa, tool.name);
        defer gpa.free(js_name);
        const name_z = try gpa.dupeZ(u8, tool.name);
        defer gpa.free(name_z);
        const js_name_z = try gpa.dupeZ(u8, js_name);
        defer gpa.free(js_name_z);
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, Execution.callTool, name_z, 1, @intCast(index), 0, null));
        defer engine.freeValue(function);
        const alias_atom = c.JS_NewAtom(engine.context, js_name_z);
        defer c.JS_FreeAtom(engine.context, alias_atom);
        if (c.JS_HasProperty(engine.context, tool_object, alias_atom) == 0) {
            try state.put(tool_object, js_name_z, c.JS_DupValue(engine.context, function));
            const owned_name = try gpa.dupe(u8, js_name);
            state.tool_names.append(gpa, owned_name) catch |cause| {
                gpa.free(owned_name);
                return cause;
            };
            const info = try engine.checked(c.JS_NewObject(engine.context));
            defer engine.freeValue(info);
            try state.put(info, "name", try engine.checked(c.JS_NewStringLen(engine.context, js_name.ptr, js_name.len)));
            const detail = if (options.enable_discovery) discovery_tools[index].sample else tool.description;
            try state.put(info, "description", try engine.checked(c.JS_NewStringLen(engine.context, detail.ptr, detail.len)));
            if (c.JS_SetPropertyUint32(engine.context, metadata, @intCast(state.tool_names.items.len - 1), c.JS_DupValue(engine.context, info)) < 0) return error.JavaScriptException;
        }
        if (!std.mem.eql(u8, js_name, tool.name)) {
            const raw_atom = c.JS_NewAtom(engine.context, name_z);
            defer c.JS_FreeAtom(engine.context, raw_atom);
            if (c.JS_HasProperty(engine.context, tool_object, raw_atom) == 0) try state.put(tool_object, name_z, c.JS_DupValue(engine.context, function));
        }
    }
    const handler = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(handler);
    try state.put(handler, "get", try engine.checked(c.JS_NewCFunction(engine.context, Execution.guardedGet, "get", 3)));
    const proxy_type = try engine.checked(c.JS_GetPropertyStr(engine.context, globals, "Proxy"));
    defer engine.freeValue(proxy_type);
    var proxy_args = [_]c.JSValue{ tool_object, handler };
    const guarded_tools = try engine.checked(c.JS_CallConstructor(engine.context, proxy_type, 2, &proxy_args));
    defer engine.freeValue(guarded_tools);
    try state.put(globals, "tools", c.JS_DupValue(engine.context, guarded_tools));
    try state.put(globals, "ALL_TOOLS", c.JS_DupValue(engine.context, metadata));
    if (options.model_runtime != null) {
        const model_object = try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null()));
        defer engine.freeValue(model_object);
        inline for (std.meta.fields(models.Operation)) |field| try state.put(model_object, field.name, try engine.checked(c.JS_NewCFunctionData2(engine.context, Execution.callModel, field.name, 0, field.value, 0, null)));
        try state.put(globals, "models", c.JS_DupValue(engine.context, model_object));
    }
    if (options.enable_discovery) inline for (.{ "searchTools", "describeTool", "describeNamespace" }, 0..) |name, index| try state.put(globals, name, try engine.checked(c.JS_NewCFunctionData2(engine.context, Execution.discover, name, 1, index, 0, null)));
    const console = try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null()));
    defer engine.freeValue(console);
    inline for (.{ "log", "info", "warn", "error", "debug" }) |name| try state.put(console, name, try engine.checked(c.JS_NewCFunction(engine.context, Execution.consoleCall, name, 0)));
    try state.put(globals, "console", c.JS_DupValue(engine.context, console));
    inline for (.{ "text", "image", "store", "load", "exit" }) |name| {
        const function = try engine.checked(c.JS_GetPropertyStr(engine.context, globals, name));
        try state.put(globals, name, function);
    }
    try state.freezeGraph(globals);
    c.JS_SetInterruptHandler(engine.runtime, Execution.interrupt, &state);
    const wrapped = try std.fmt.allocPrint(gpa, "(async (tools, console) => {{{s}\n}})(tools, console)", .{source});
    defer gpa.free(wrapped);
    var script_failure: ?anyerror = null;
    const promise = if (state.checkLimits(false)) c.pi_js_undefined() else engine.eval(wrapped, "codemode.js", c.JS_EVAL_TYPE_GLOBAL) catch |cause| blk: {
        script_failure = cause;
        break :blk c.pi_js_undefined();
    };
    defer engine.freeValue(promise);
    if (script_failure == null and !state.timed_out and !state.aborted) state.observeTerminal(promise) catch |cause| {
        if (state.budget_exhausted) {
            script_failure = cause;
        } else return cause;
    };
    while (script_failure == null and !state.exit_requested) {
        if (state.checkLimits(false)) break;
        state.drainJobs() catch |cause| {
            script_failure = cause;
            break;
        };
        if (c.JS_PromiseState(engine.context, promise) != c.JS_PROMISE_PENDING) break;
        if (!try state.dispatch()) {
            script_failure = error.CodemodeStalledPromise;
            break;
        }
    }
    const success = state.exit_requested or ((script_failure == null or state.script_settled) and !state.aborted and !state.timed_out and !state.output_overflow and c.JS_PromiseState(engine.context, promise) == c.JS_PROMISE_FULFILLED);
    for (state.pending.items) |pending| try state.completeCall(pending.record_index, "cancelled", pending.started);
    try state.result.value.object.put(a, "ok", .{ .bool = success });
    if (success) {
        if (!state.exit_requested) {
            const value = c.JS_PromiseResult(engine.context, promise);
            defer engine.freeValue(value);
            if (try state.parseArgument(value)) |owned| {
                var actual = owned;
                defer actual.deinit();
                try state.result.value.object.put(a, "value", try json.clone(a, actual.value));
            }
        }
        var set: Value = .{ .object = .empty };
        var delete: Value = .{ .array = .init(a) };
        var writes = state.writes.object.iterator();
        while (writes.next()) |entry| if (entry.value_ptr.* == .null) {
            try delete.array.append(.{ .string = entry.key_ptr.* });
        } else try set.object.put(a, entry.key_ptr.*, state.stored.object.get(entry.key_ptr.*).?);
        var output: Value = .{ .object = .empty };
        try output.object.put(a, "set", set);
        try output.object.put(a, "delete", delete);
        try state.result.value.object.put(a, "storeWrites", output);
    } else {
        var error_value: Value = .{ .object = .empty };
        try error_value.object.put(a, "kind", .{ .string = if (state.aborted) "aborted" else if (state.timed_out) "timeout" else "script" });
        var message: []const u8 = if (state.aborted) "The script was aborted" else if (state.timed_out) "The script timed out" else if (state.output_overflow) "script output exceeded the limit" else if (script_failure) |cause| @errorName(cause) else "The script failed";
        if (c.JS_PromiseState(engine.context, promise) == c.JS_PROMISE_REJECTED) {
            const rejection = c.JS_PromiseResult(engine.context, promise);
            defer engine.freeValue(rejection);
            const error_message = if (c.JS_IsObject(rejection)) try engine.checked(c.JS_GetPropertyStr(engine.context, rejection, "message")) else c.pi_js_undefined();
            defer engine.freeValue(error_message);
            const described = try engine.toString(if (c.JS_IsUndefined(error_message)) rejection else error_message);
            defer gpa.free(described);
            message = try a.dupe(u8, described);
        }
        if (state.budget_exhausted) {
            const budget_text = try engine.toString(c.JS_NewFloat64(engine.context, options.interrupt_budget.?));
            defer gpa.free(budget_text);
            message = try std.fmt.allocPrint(a, "Execution exceeded its interrupt budget of {s}", .{budget_text});
        }
        try error_value.object.put(a, "message", .{ .string = message });
        try state.result.value.object.put(a, "error", error_value);
    }
    return state.result;
}

pub fn executeInline(gpa: std.mem.Allocator, io: std.Io, tools: []const Tool, source: []const u8, options: Options) !json.Owned {
    var inline_options = options;
    if (inline_options.interrupt_budget == null) inline_options.interrupt_budget = 100_000;
    inline_options.stack_limit = 256 * 1024;
    return execute(gpa, io, tools, source, inline_options);
}

test "native codemode Source c5 inline interrupt budget bounds synchronous and promise job loops" {
    const gpa = std.testing.allocator;
    var original = try json.Owned.parse(gpa, @embedFile("fixtures/codemode-portable-c5f5b328.json"));
    defer original.deinit();
    for (original.value.object.get("rows").?.array.items) |row| {
        const name = row.object.get("name").?.string;
        const is_budget = std.mem.startsWith(u8, name, "budget-");
        if (!is_budget and !std.mem.eql(u8, name, "sync") and !std.mem.eql(u8, name, "jobs")) continue;
        const budget: f64 = if (!is_budget) 1000 else if (std.mem.eql(u8, name[7..], "NaN")) std.math.nan(f64) else try std.fmt.parseFloat(f64, name[7..]);
        var result = try executeInline(gpa, std.testing.io, &.{}, if (std.mem.eql(u8, name, "jobs")) "while(true)await null" else "while(true){}", .{ .timeout_ms = null, .interrupt_budget = budget });
        defer result.deinit();
        const expected = row.object.get("result").?;
        try std.testing.expectEqual(expected.object.get("ok").?.bool, result.value.object.get("ok").?.bool);
        try std.testing.expect(json.equal(expected.object.get("error").?, result.value.object.get("error").?));
    }
}

test "native codemode Source c5 inline startup limits and terminal result precede orphan promise work" {
    const gpa = std.testing.allocator;
    var original = try json.Owned.parse(gpa, @embedFile("fixtures/codemode-inline-boundaries-c5f5b328.json"));
    defer original.deinit();
    for (original.value.object.get("rows").?.array.items) |row| {
        const budget_text = row.object.get("budget").?.string;
        const budget = if (std.mem.eql(u8, budget_text, "NaN")) std.math.nan(f64) else try std.fmt.parseFloat(f64, budget_text);
        var result = try executeInline(gpa, std.testing.io, &.{}, row.object.get("code").?.string, .{ .timeout_ms = null, .interrupt_budget = budget });
        defer result.deinit();
        const expected = row.object.get("result").?;
        if (!json.equal(expected.object.get("output").?, result.value.object.get("output").?)) std.debug.print("Inline budget{s} code{s}: output differs\n", .{ budget_text, row.object.get("code").?.string });
        try std.testing.expectEqual(expected.object.get("ok").?.bool, result.value.object.get("ok").?.bool);
        try std.testing.expect(json.equal(expected.object.get("output").?, result.value.object.get("output").?));
        if (expected.object.get("error")) |failure| try std.testing.expect(json.equal(failure, result.value.object.get("error").?));
        if (expected.object.get("value")) |value| try std.testing.expect(json.equal(value, result.value.object.get("value").?));
    }
}

test "native codemode executes isolated user script with JSON tool promises ordered output and successful store writes" {
    const Double = struct {
        fn run(_: ?*anyopaque, gpa: std.mem.Allocator, args: ?Value, _: ?*bool) !json.Owned {
            var result = try json.Owned.empty(gpa);
            result.value = .{ .integer = @intCast((try json.asInteger(args.?.object.get("value").?)) * 2) };
            return result;
        }
    };
    var result = try execute(std.testing.allocator, std.testing.io, &.{.{ .name = "my-tool", .execute = Double.run }}, "text('before'); const value=await tools.my_tool({value:3}); console.log('after',value); store('answer',value); return {value};", .{});
    defer result.deinit();
    try std.testing.expect(result.value.object.get("ok").?.bool);
    try std.testing.expectEqual(@as(u64, 6), try json.asInteger(result.value.object.get("value").?.object.get("value").?));
    try std.testing.expectEqual(@as(usize, 2), result.value.object.get("output").?.array.items.len);
    try std.testing.expectEqualStrings("before", result.value.object.get("output").?.array.items[0].object.get("text").?.string);
    try std.testing.expectEqualStrings("after 6", result.value.object.get("output").?.array.items[1].object.get("text").?.string);
    try std.testing.expectEqual(@as(u64, 6), try json.asInteger(result.value.object.get("storeWrites").?.object.get("set").?.object.get("answer").?));
}

test "native codemode replays actual original 7fb sandbox output stores aliases and error results" {
    const gpa = std.testing.allocator;
    var fixture = try json.Owned.parse(gpa, @embedFile("fixtures/codemode-7fb.json"));
    defer fixture.deinit();
    const Double = struct {
        fn run(_: ?*anyopaque, allocator: std.mem.Allocator, args: ?Value, _: ?*bool) !json.Owned {
            var result = try json.Owned.empty(allocator);
            result.value = .{ .integer = @intCast((try json.asInteger(args.?.object.get("value").?)) * 2) };
            return result;
        }
    };
    for (fixture.value.object.get("cases").?.array.items) |case| {
        var actual = try execute(gpa, std.testing.io, &.{.{ .name = "my-tool", .description = "double", .execute = Double.run }}, case.object.get("code").?.string, .{ .store = case.object.get("store").? });
        defer actual.deinit();
        for (actual.value.object.getPtr("calls").?.array.items) |*call| _ = call.object.orderedRemove("durationMs");
        const expected_bytes = try json.stringify(gpa, case.object.get("result").?);
        defer gpa.free(expected_bytes);
        const actual_bytes = try json.stringify(gpa, actual.value);
        defer gpa.free(actual_bytes);
        // Compare JSON values after parsing so object field insertion order is
        // irrelevant; array/output/call ordering remains significant.
        const expected = try std.json.parseFromSlice(Value, gpa, expected_bytes, .{});
        defer expected.deinit();
        const replayed = try std.json.parseFromSlice(Value, gpa, actual_bytes, .{});
        defer replayed.deinit();
        try expectJsonEquivalent(expected.value, replayed.value);
    }
}

test "native codemode interrupt bounds runaway user code and represents prior caller cancellation" {
    const gpa = std.testing.allocator;
    var timeout = try execute(gpa, std.testing.io, &.{}, "text('retained');while(true){}", .{ .timeout_ms = 1_000 });
    defer timeout.deinit();
    try std.testing.expect(!timeout.value.object.get("ok").?.bool);
    try std.testing.expectEqualStrings("timeout", timeout.value.object.get("error").?.object.get("kind").?.string);
    try std.testing.expectEqual(@as(usize, 1), timeout.value.object.get("output").?.array.items.len);
    var immediate = try execute(gpa, std.testing.io, &.{}, "text('must not run')", .{ .timeout_ms = 0 });
    defer immediate.deinit();
    try std.testing.expect(!immediate.value.object.get("ok").?.bool);
    try std.testing.expectEqualStrings("timeout", immediate.value.object.get("error").?.object.get("kind").?.string);
    try std.testing.expectEqual(@as(usize, 0), immediate.value.object.get("output").?.array.items.len);
    var flag = true;
    var aborted = try execute(gpa, std.testing.io, &.{}, "throw new Error('must not run')", .{ .abort_flag = &flag });
    defer aborted.deinit();
    try std.testing.expect(!aborted.value.object.get("ok").?.bool);
    try std.testing.expectEqualStrings("aborted", aborted.value.object.get("error").?.object.get("kind").?.string);
    try std.testing.expectEqual(@as(usize, 0), aborted.value.object.get("output").?.array.items.len);
}

test "native codemode tool calls overlap retain declaration call order and cancel joined unawaited workers" {
    const Capture = struct {
        io: std.Io,
        entered: std.Io.Event = .unset,
        completed: std.atomic.Value(usize) = .init(0),
        fn first(raw: ?*anyopaque, gpa: std.mem.Allocator, _: ?Value, _: ?*bool) !json.Owned {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            try self.entered.wait(self.io);
            var result = try json.Owned.empty(gpa);
            result.value = .{ .string = "first" };
            _ = self.completed.fetchAdd(1, .release);
            return result;
        }
        fn second(raw: ?*anyopaque, gpa: std.mem.Allocator, _: ?Value, _: ?*bool) !json.Owned {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.entered.set(self.io);
            var result = try json.Owned.empty(gpa);
            result.value = .{ .string = "second" };
            _ = self.completed.fetchAdd(1, .release);
            return result;
        }
        fn slow(raw: ?*anyopaque, gpa: std.mem.Allocator, _: ?Value, flag: ?*bool) !json.Owned {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            while (!@atomicLoad(bool, flag.?, .acquire)) self.io.sleep(.fromMilliseconds(1), .awake) catch {};
            _ = self.completed.fetchAdd(1, .release);
            return json.Owned.empty(gpa);
        }
    };
    const gpa = std.testing.allocator;
    var capture: Capture = .{ .io = std.testing.io };
    var result = try execute(gpa, std.testing.io, &.{ .{ .name = "first", .context = &capture, .execute = Capture.first }, .{ .name = "second", .context = &capture, .execute = Capture.second } }, "return await Promise.all([tools.first({}),tools.second({})]);", .{});
    defer result.deinit();
    try std.testing.expect(result.value.object.get("ok").?.bool);
    try std.testing.expectEqual(@as(usize, 2), capture.completed.load(.acquire));
    const calls = result.value.object.get("calls").?.array.items;
    try std.testing.expectEqualStrings("first", calls[0].object.get("name").?.string);
    try std.testing.expectEqualStrings("second", calls[1].object.get("name").?.string);
    var abandoned = try execute(gpa, std.testing.io, &.{.{ .name = "slow", .context = &capture, .execute = Capture.slow }}, "tools.slow({});return 9;", .{});
    defer abandoned.deinit();
    try std.testing.expect(abandoned.value.object.get("ok").?.bool);
    try std.testing.expectEqual(@as(usize, 3), capture.completed.load(.acquire));
    try std.testing.expectEqualStrings("cancelled", abandoned.value.object.get("calls").?.array.items[0].object.get("status").?.string);
}

test "native codemode allocation failures free host ownership output stores callbacks and VM roots" {
    const Check = struct {
        fn run(gpa: std.mem.Allocator) !void {
            var result = try execute(gpa, std.testing.io, &.{}, "store('owned',{x:1});text(load('owned'));return {done:true};", .{});
            defer result.deinit();
            try std.testing.expect(result.value.object.get("ok").?.bool);
        }
    };
    try @import("../test_support/allocation_shards.zig").check(Check.run);
}

test "native codemode allocation failures join tool workers and release JSON results and promise roots" {
    const Check = struct {
        fn tool(_: ?*anyopaque, gpa: std.mem.Allocator, args: ?Value, _: ?*bool) !json.Owned {
            var result = try json.Owned.empty(gpa);
            errdefer result.deinit();
            result.value = try json.clone(result.arena.allocator(), args.?);
            return result;
        }
        fn run(gpa: std.mem.Allocator) !void {
            var result = try execute(gpa, std.testing.io, &.{.{ .name = "echo", .execute = tool }}, "const value=await tools.echo({x:1});text(value);return value;", .{});
            defer result.deinit();
            try std.testing.expect(result.value.object.get("ok").?.bool);
        }
    };
    try @import("../test_support/allocation_shards.zig").check(Check.run);
}

test "native codemode unknown tool guard matches original suggested identifier diagnostics" {
    const gpa = std.testing.allocator;
    const ToolFn = struct {
        fn run(_: ?*anyopaque, allocator: std.mem.Allocator, _: ?Value, _: ?*bool) !json.Owned {
            return json.Owned.empty(allocator);
        }
    };
    var fixture = try json.Owned.parse(gpa, @embedFile("fixtures/codemode-guard-7fb.json"));
    defer fixture.deinit();
    var actual = try execute(gpa, std.testing.io, &.{.{ .name = "my-tool", .description = "double", .execute = ToolFn.run }}, "return tools.mytool({value:1});", .{});
    defer actual.deinit();
    try std.testing.expectEqualStrings(fixture.value.object.get("error").?.object.get("message").?.string, actual.value.object.get("error").?.object.get("message").?.string);
    try std.testing.expectEqual(@as(usize, 0), actual.value.object.get("calls").?.array.items.len);
}
test "native codemode discovery globals replay original ranked metadata namespace aliases and async errors" {
    const gpa = std.testing.allocator;
    var original = try json.Owned.parse(gpa, @embedFile("fixtures/codemode-discovery-original-6fb.json"));
    defer original.deinit();
    const original_tools = json.get(original.value, "tools").?.array.items;
    const samples = json.get(original.value, "samples").?.object;
    const info = json.get(original.value, "namespace").?.object;
    const Callback = struct {
        fn call(_: ?*anyopaque, allocator: std.mem.Allocator, _: ?Value, _: ?*bool) !json.Owned {
            return json.Owned.empty(allocator);
        }
    };
    var tools: [2]Tool = undefined;
    for (original_tools, &tools, 0..) |value, *tool, index| {
        const name = value.object.get("name").?.string;
        tool.* = .{ .name = name, .description = value.object.get("description").?.string, .execute = Callback.call, .discovery_metadata = .{
            .name = name,
            .description = value.object.get("description").?.string,
            .sample = samples.get(name).?.string,
            .parameters = value.object.get("parameters").?,
            .namespace = if (index == 0) .{ .name = info.get("name").?.string, .description = info.get("description").?.string, .instructions = info.get("instructions").?.string } else null,
        } };
    }
    for (json.get(original.value, "rows").?.array.items) |row| {
        const args = try json.stringify(gpa, row.object.get("args").?);
        defer gpa.free(args);
        const code = try std.fmt.allocPrint(gpa, "try{{const value=await {s}(...{s});text({{result:value??null,undefined:value===undefined}})}}catch(error){{text({{error:{{name:error.name,message:error.message}}}})}}", .{ row.object.get("name").?.string, args });
        defer gpa.free(code);
        var result = try execute(gpa, std.testing.io, &tools, code, .{ .enable_discovery = true });
        defer result.deinit();
        const output = result.value.object.get("output").?.array.items;
        try std.testing.expectEqual(@as(usize, 1), output.len);
        var actual = try json.Owned.parse(gpa, output[0].object.get("text").?.string);
        defer actual.deinit();
        if (row.object.get("error")) |expected| try expectJsonEquivalent(expected, actual.value.object.get("error").?) else {
            try expectJsonEquivalent(row.object.get("result").?, actual.value.object.get("result").?);
            try std.testing.expectEqual(row.object.get("undefined").?.bool, actual.value.object.get("undefined").?.bool);
        }
        try std.testing.expectEqual(@as(usize, 0), result.value.object.get("calls").?.array.items.len);
    }
}

test "native codemode discovery allocation failures release metadata promises errors and namespace values" {
    const Check = struct {
        fn call(_: ?*anyopaque, gpa: std.mem.Allocator, _: ?Value, _: ?*bool) !json.Owned {
            return json.Owned.empty(gpa);
        }
        fn run(gpa: std.mem.Allocator) !void {
            const tool: Tool = .{ .name = "mcp__repo__issues-list", .description = "repository issues", .execute = call, .discovery_metadata = .{
                .name = "mcp__repo__issues-list",
                .description = "repository issues",
                .sample = "issue declaration",
                .namespace = .{ .name = "mcp__repo", .description = "Repository", .instructions = "issue tracker" },
            } };
            var result = try execute(gpa, std.testing.io, &.{tool}, "text(await searchTools('issues'));text(await describeTool('mcp__repo__issues_list'));text(await describeNamespace('repo'));try{await searchTools(4)}catch(error){text(error.message)}", .{ .enable_discovery = true });
            defer result.deinit();
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Check.run, .{});
}

fn expectJsonEquivalent(expected: Value, actual: Value) anyerror!void {
    try std.testing.expectEqual(std.meta.activeTag(expected), std.meta.activeTag(actual));
    switch (expected) {
        .object => |object| {
            try std.testing.expectEqual(object.count(), actual.object.count());
            var iterator = object.iterator();
            while (iterator.next()) |entry| try expectJsonEquivalent(entry.value_ptr.*, actual.object.get(entry.key_ptr.*) orelse return error.MissingCodemodeResultField);
        },
        .array => |array| {
            try std.testing.expectEqual(array.items.len, actual.array.items.len);
            for (array.items, actual.array.items) |left, right| try expectJsonEquivalent(left, right);
        },
        .string => |string| try std.testing.expectEqualStrings(string, actual.string),
        .integer => |number| try std.testing.expectEqual(number, actual.integer),
        .float => |number| try std.testing.expectEqual(number, actual.float),
        .bool => |boolean| try std.testing.expectEqual(boolean, actual.bool),
        .null => {},
        else => return error.UnexpectedCodemodeResultValue,
    }
}
