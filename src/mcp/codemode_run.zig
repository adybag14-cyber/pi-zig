//! Owner-thread deterministic VM run. The host answers calls; no tool worker
//! executes on its behalf. Transport and public extension bindings own scheduling.
const std = @import("std");
const vm = @import("codemode.zig");
const em = @import("../extensions/engine.zig");
const c = em.c;
const json = @import("protocol.zig").json;
const host_mod = @import("codemode_run_host.zig");
const clock_mod = @import("codemode_clock.zig");
pub const Tool = struct { name: []const u8, js_name: ?[]const u8 = null, description: []const u8 = "" };
pub const Global = struct { name: []const u8, spread: bool = false };
pub const Call = struct { id: u64, target: enum { tool, global }, name: []const u8, args: ?json.Value };
pub const Observer = struct {
    context: ?*anyopaque = null,
    started: ?*const fn (?*anyopaque, *Run, []const u8) anyerror!void = null,
    call: *const fn (?*anyopaque, *Run, Call) anyerror!void,
    idle: ?*const fn (?*anyopaque, *Run, f64, f64) anyerror!void = null,
    output: ?*const fn (?*anyopaque, json.Value) anyerror!void = null,
};
pub const Options = struct {
    started_at: f64,
    seed: f64,
    tools: []const Tool = &.{},
    globals: []const Global = &.{},
    store: json.Value = .{ .object = .empty },
    observer: Observer,
    timeout_ms: ?u64 = null,
    memory_limit: usize = 64 * 1024 * 1024,
    stack_limit: usize = 256 * 1024,
    interrupt_budget: ?f64 = 100_000,
    abort_flag: ?*bool = null,
    deterministic: bool = true,
};
const Pending = struct { resolve: c.JSValue, reject: c.JSValue, started: i64, record: ?usize };
pub const Run = struct {
    gpa: std.mem.Allocator,
    core: vm.Execution,
    host: host_mod.Host,
    clock: clock_mod.Clock,
    observer: Observer,
    globals: []const Global,
    source: []const u8,
    fingerprint: []const u8,
    promise: c.JSValue,
    pending: std.AutoHashMapUnmanaged(u64, Pending) = .empty,
    next_id: u64 = 1,
    begun: bool = false,
    in_vm: bool = false,
    pumping: bool = false,
    finished: bool = false,
    suppressing_diagnostics: bool = false,
    script_failure: ?anyerror = null,
    sandbox_failure: ?[]const u8 = null,
    abort_message: ?[]const u8 = null,
    last_idle: ?struct { seq: f64, issued: f64 } = null,
    deterministic: bool = true,

    /// Creation performs validation and ownership admission. begin() is a
    /// separate owner turn, so callbacks cannot precede publication of this Run.
    pub fn create(gpa: std.mem.Allocator, io: std.Io, source: []const u8, options: Options) !*Run {
        const clock = try clock_mod.Clock.init(options.started_at, options.seed);
        if (options.deterministic) try validateDeclarations(gpa, options.tools, options.globals);
        const self = try gpa.create(Run);
        var transferred = false;
        errdefer if (!transferred) gpa.destroy(self);
        var host = try host_mod.Host.init(gpa, options.started_at, options.seed);
        errdefer if (!transferred) host.deinit();
        var result = try json.Owned.empty(gpa);
        errdefer if (!transferred) result.deinit();
        const engine = try em.Engine.init(gpa, .{ .memory_limit = options.memory_limit, .stack_limit = options.stack_limit, .interrupt_budget = std.math.maxInt(u64), .deterministic_clock = if (options.deterministic) clock else null, .node_locale_compare = false, .node_json_diagnostics = false });
        errdefer if (!transferred) engine.deinit();
        self.* = .{ .gpa = gpa, .core = .{ .gpa = gpa, .io = io, .engine = engine, .tools = &.{}, .options = .{ .timeout_ms = options.timeout_ms, .memory_limit = options.memory_limit, .stack_limit = options.stack_limit, .interrupt_budget = options.interrupt_budget, .store = options.store }, .result = result, .stored = .{ .object = .empty }, .deadline = if (options.timeout_ms) |limit| std.Io.Clock.awake.now(io).toMilliseconds() +| @as(i64, @intCast(@min(limit, std.math.maxInt(i64)))) else null }, .host = host, .clock = clock, .observer = options.observer, .globals = &.{}, .source = "", .fingerprint = "", .promise = c.pi_js_undefined() };
        transferred = true;
        errdefer self.deinit();
        self.core.options.abort_flag = options.abort_flag;
        self.deterministic = options.deterministic;
        const arena = self.core.result.arena.allocator();
        self.source = try arena.dupe(u8, source);
        const tools = try arena.alloc(vm.Tool, options.tools.len);
        for (options.tools, tools) |tool, *owned| owned.* = .{ .name = try arena.dupe(u8, tool.name), .js_name = if (tool.js_name) |name| try arena.dupe(u8, name) else null, .description = try arena.dupe(u8, tool.description), .execute = forbiddenExecutor };
        self.core.tools = tools;
        const globals = try arena.alloc(Global, options.globals.len);
        for (options.globals, globals) |global, *owned| owned.* = .{ .name = try arena.dupe(u8, global.name), .spread = global.spread };
        self.globals = globals;
        self.core.result.value = .{ .object = .empty };
        try self.core.result.value.object.put(arena, "output", .{ .array = .init(arena) });
        try self.core.result.value.object.put(arena, "calls", .{ .array = .init(arena) });
        self.core.stored = try json.clone(arena, options.store);
        const metadata = try arena.alloc(@import("codemode_discovery.zig").Tool, tools.len);
        for (tools, metadata) |tool, *entry| entry.* = .{ .name = tool.name, .description = tool.description, .sample = tool.description };
        self.core.discovery_tools = metadata;
        self.core.control_context = self;
        self.core.control_call = toolCall;
        self.core.control_output = output;
        engine.host_data = &self.core;
        engine.native_exception_diagnostics_suppressed += 1;
        self.suppressing_diagnostics = true;
        c.JS_SetInterruptHandler(engine.runtime, vm.Execution.interrupt, &self.core);
        const global_object = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global_object);
        if (options.deterministic) inline for (.{ "WeakRef", "FinalizationRegistry" }) |name| {
            const atom = c.JS_NewAtom(engine.context, name);
            if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
            defer c.JS_FreeAtom(engine.context, atom);
            if (c.JS_DeleteProperty(engine.context, global_object, atom, c.JS_PROP_THROW) < 0) return error.JavaScriptException;
        };
        try self.core.installVm();
        try self.installGlobals(global_object);
        const budget = if (options.interrupt_budget) |value| try std.fmt.allocPrint(arena, "{d}", .{value}) else "none";
        self.fingerprint = try std.fmt.allocPrint(arena, "quickjs-native clock-v1, quickjs {d}.{d}.{d}, implementation sha256:{s}, deterministic {d}, stack {d}, heap {d}, budget {s}", .{ c.QJS_VERSION_MAJOR, c.QJS_VERSION_MINOR, c.QJS_VERSION_PATCH, @import("native_vm_identity").sha256, @intFromBool(options.deterministic), options.stack_limit, options.memory_limit, budget });
        return self;
    }
    pub fn deinit(self: *Run) void {
        std.debug.assert(!self.in_vm);
        var values = self.pending.valueIterator();
        while (values.next()) |value| {
            self.core.engine.freeValue(value.resolve);
            self.core.engine.freeValue(value.reject);
        }
        self.pending.deinit(self.gpa);
        self.host.deinit();
        self.core.engine.freeValue(self.promise);
        for (self.core.tool_names.items) |name| self.gpa.free(name);
        self.core.tool_names.deinit(self.gpa);
        if (self.suppressing_diagnostics) self.core.engine.native_exception_diagnostics_suppressed -= 1;
        self.core.engine.deinit();
        self.core.result.deinit();
        self.gpa.destroy(self);
    }
    pub fn begin(self: *Run) !void {
        if (self.begun or self.finished) return error.RunAlreadyStarted;
        self.begun = true;
        if (self.deterministic) if (self.observer.started) |notify| try notify(self.observer.context, self, self.fingerprint);
        if (self.finished) return;
        if (self.core.aborted) return self.finish();
        if (self.core.checkLimits(true)) return self.finish();
        const wrapped = try std.fmt.allocPrint(self.gpa, "(async (tools, console) => {{{s}\n}})", .{self.source});
        defer self.gpa.free(wrapped);
        {
            self.in_vm = true;
            defer self.in_vm = false;
            const function = self.core.engine.eval(wrapped, "codemode.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| failed: {
                self.script_failure = err;
                if (err == error.OutOfMemory) return err;
                if (self.core.engine.captured_exception) |reason| try self.core.captureTerminalError(reason);
                break :failed c.pi_js_undefined();
            };
            defer self.core.engine.freeValue(function);
            if (self.script_failure == null) {
                const global = c.JS_GetGlobalObject(self.core.engine.context);
                defer self.core.engine.freeValue(global);
                const tools = try self.core.engine.checked(c.JS_GetPropertyStr(self.core.engine.context, global, "tools"));
                defer self.core.engine.freeValue(tools);
                const console = try self.core.engine.checked(c.JS_GetPropertyStr(self.core.engine.context, global, "console"));
                defer self.core.engine.freeValue(console);
                var args = [_]c.JSValue{ tools, console };
                self.promise = self.core.engine.checked(c.JS_Call(self.core.engine.context, function, c.pi_js_undefined(), args.len, &args)) catch |err| failed: {
                    if (err == error.OutOfMemory) return err;
                    self.script_failure = err;
                    if (!self.core.aborted and !self.core.timed_out) if (self.core.engine.captured_exception) |reason| try self.core.captureTerminalError(reason);
                    break :failed c.pi_js_undefined();
                };
            }
            if (self.script_failure == null) try self.core.observeTerminal(self.promise);
        }
        try self.pump();
    }
    /// Delivery owns copies before consuming either a call or a result number.
    /// While the VM is executing, answers are buffered until its next drain.
    pub fn deliver(self: *Run, seq: f64, now: f64, id: u64, outcome: host_mod.Outcome) !void {
        try self.host.deliver(seq, now, id, outcome);
        if (self.finished) return;
        // Host acceptance finishes the call observation even if an earlier
        // sequence gap prevents the VM from consuming this answer yet.
        const pending = self.pending.getPtr(id) orelse return error.MissingPendingRunCall;
        try self.core.completeCall(pending.record, if (outcome == .success) "ok" else "error", pending.started);
        pending.record = null;
    }
    pub fn abort(self: *Run) !void {
        return self.abortWithMessage("Execution aborted");
    }
    pub fn abortWithMessage(self: *Run, message: []const u8) !void {
        if (self.finished) return;
        self.abort_message = try self.core.result.arena.allocator().dupe(u8, message);
        self.core.aborted = true;
        if (!self.in_vm) try self.finish();
    }
    /// The owner bridge supplies the original callback failure text. Capture
    /// it without unwinding through a VM call or re-entering an active VM.
    pub fn failHost(self: *Run, message: []const u8) !void {
        if (self.finished) return;
        self.sandbox_failure = try std.fmt.allocPrint(self.core.result.arena.allocator(), "Sandbox host failed: {s}", .{message});
        if (!self.in_vm) try self.finish();
    }
    pub fn pump(self: *Run) !void {
        if (self.finished or self.in_vm or self.pumping or !self.begun) return;
        self.pumping = true;
        defer self.pumping = false;
        try self.drain();
        while (!self.finished) {
            var reply = self.host.next() orelse return;
            defer reply.deinit();
            const removed = self.pending.fetchRemove(reply.id) orelse return error.MissingPendingRunCall;
            defer self.core.engine.freeValue(removed.value.resolve);
            defer self.core.engine.freeValue(removed.value.reject);
            if (self.deterministic) {
                try self.clock.advance(self.host.clock);
                if (c.JS_PIAdvanceDeterministicTime(self.core.engine.runtime, self.clock.realtime(), self.clock.elapsed()) < 0) return error.InvalidDeterministicTime;
            }
            const value = self.replyValue(reply) catch |err| {
                if (err == error.OutOfMemory) return err;
                const text = if (self.core.engine.captured_exception) |exception| try self.core.engine.toString(exception) else try self.gpa.dupe(u8, @errorName(err));
                defer self.gpa.free(text);
                self.sandbox_failure = try self.core.result.arena.allocator().dupe(u8, text);
                return self.finish();
            };
            defer self.core.engine.freeValue(value);
            var args = [_]c.JSValue{value};
            self.in_vm = true;
            const settled = self.core.engine.checked(c.JS_Call(self.core.engine.context, if (reply.ok) removed.value.resolve else removed.value.reject, c.pi_js_undefined(), args.len, &args)) catch |err| {
                self.in_vm = false;
                return err;
            };
            self.in_vm = false;
            self.core.engine.freeValue(settled);
            try self.core.completeCall(removed.value.record, if (reply.ok) "ok" else "error", removed.value.started);
            try self.drain();
        }
    }
    fn drain(self: *Run) !void {
        self.in_vm = true;
        self.core.drainJobs() catch |err| {
            self.script_failure = err;
            if (err == error.OutOfMemory) {
                self.in_vm = false;
                return err;
            }
        };
        self.in_vm = false;
        if (self.core.terminal_failure) |failure| if (failure == error.OutOfMemory) return error.OutOfMemory;
        if (self.sandbox_failure != null or self.core.script_settled or self.core.exit_requested or self.script_failure != null or self.core.checkLimits(false)) return self.finish();
        if (self.pending.count() == 0) {
            self.script_failure = error.CodemodeStalledPromise;
            return self.finish();
        }
        if (self.deterministic) if (self.observer.idle) |notify| {
            if (self.last_idle) |last| if (last.seq == self.host.current and last.issued == self.host.issued) return;
            self.last_idle = .{ .seq = self.host.current, .issued = self.host.issued };
            try notify(self.observer.context, self, self.host.current, self.host.issued);
        };
    }
    fn finish(self: *Run) !void {
        if (self.finished) return;
        const arena = self.core.result.arena.allocator();
        const success = self.sandbox_failure == null and (self.core.exit_requested or (self.core.script_settled and self.core.terminal_error == null and self.core.terminal_failure == null and !self.core.aborted and !self.core.timed_out and !self.core.output_overflow));
        var values = self.pending.valueIterator();
        while (values.next()) |pending| try self.core.completeCall(pending.record, "cancelled", pending.started);
        try self.core.result.value.object.put(arena, "ok", .{ .bool = success });
        var during: json.Value = .{ .object = .empty };
        try during.object.put(arena, "seq", .{ .float = self.host.current });
        try during.object.put(arena, "issued", .{ .float = self.host.issued });
        if (self.deterministic and self.sandbox_failure == null and !self.core.aborted and !self.core.timed_out) try self.core.result.value.object.put(arena, "during", during);
        if (success) {
            var set: json.Value = .{ .object = .empty };
            var deleted: json.Value = .{ .array = .init(arena) };
            var writes = self.core.writes.object.iterator();
            while (writes.next()) |entry| if (entry.value_ptr.* == .null) {
                try deleted.array.append(.{ .string = entry.key_ptr.* });
            } else try set.object.put(arena, entry.key_ptr.*, self.core.stored.object.get(entry.key_ptr.*).?);
            var result: json.Value = .{ .object = .empty };
            try result.object.put(arena, "set", set);
            try result.object.put(arena, "delete", deleted);
            try self.core.result.value.object.put(arena, "storeWrites", result);
        } else {
            var failure: json.Value = .{ .object = .empty };
            const stalled = if (self.script_failure) |cause| cause == error.CodemodeStalledPromise else false;
            try failure.object.put(arena, "kind", .{ .string = if (self.sandbox_failure != null) "sandbox" else if (self.core.aborted) "aborted" else if (self.core.timed_out) "timeout" else "script" });
            if (self.sandbox_failure) |message| {
                try failure.object.put(arena, "message", .{ .string = message });
            } else if (self.core.aborted) {
                try failure.object.put(arena, "message", .{ .string = self.abort_message orelse "Execution aborted" });
            } else if (self.core.terminal_error) |description| {
                var fields = description.object.iterator();
                while (fields.next()) |field| try failure.object.put(arena, field.key_ptr.*, field.value_ptr.*);
            } else {
                if (stalled) try failure.object.put(arena, "name", .{ .string = "Error" });
                try failure.object.put(arena, "message", .{ .string = if (self.core.aborted) "The script was aborted" else if (self.core.timed_out) "The script timed out" else if (stalled) "The script is waiting on a promise that can never settle: no tool call is pending, and timers do not exist here." else "The script failed" });
            }
            try self.core.result.value.object.put(arena, "error", failure);
        }
        self.finished = true;
        self.host.finish();
    }
    fn toolCall(raw: ?*anyopaque, name: []const u8, args: ?json.Owned) !c.JSValue {
        const self: *Run = @ptrCast(@alignCast(raw.?));
        return self.enqueue(.tool, name, args);
    }
    fn output(raw: ?*anyopaque, item: json.Value) !void {
        const self: *Run = @ptrCast(@alignCast(raw.?));
        if (self.observer.output) |notify| try notify(self.observer.context, item);
    }
    fn enqueue(self: *Run, target: @FieldType(Call, "target"), name: []const u8, args: ?json.Owned) !c.JSValue {
        var owned_args = args;
        defer if (owned_args) |*value| value.deinit();
        const engine = self.core.engine;
        var functions: [2]c.JSValue = undefined;
        const promise = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
        errdefer engine.freeValue(promise);
        errdefer for (functions) |value| engine.freeValue(value);
        try self.pending.ensureUnusedCapacity(self.gpa, 1);
        const arena = self.core.result.arena.allocator();
        const id = self.next_id;
        const copied_args: ?json.Value = if (owned_args) |value| try json.clone(arena, value.value) else null;
        const started = self.core.now();
        const record: ?usize = if (target == .tool) record: {
            try self.core.recordCall(name, "cancelled", started);
            break :record self.core.result.value.object.get("calls").?.array.items.len - 1;
        } else null;
        try self.host.issue(id);
        self.next_id += 1;
        self.pending.putAssumeCapacity(id, .{ .resolve = functions[0], .reject = functions[1], .started = started, .record = record });
        // The run owns callbacks before onCall, allowing a synchronous answer.
        self.observer.call(self.observer.context, self, .{ .id = id, .target = target, .name = name, .args = copied_args }) catch |err| {
            _ = self.pending.remove(id);
            _ = self.host.waiting.remove(id);
            return err;
        };
        return promise;
    }
    fn replyValue(self: *Run, reply: host_mod.Reply) !c.JSValue {
        const engine = self.core.engine;
        if (reply.ok) {
            if (reply.payload) |bytes| {
                const terminated = try self.gpa.dupeZ(u8, bytes);
                defer self.gpa.free(terminated);
                return engine.checked(c.JS_ParseJSON(engine.context, terminated.ptr, terminated.len, "host-result.json"));
            }
            return c.pi_js_undefined();
        }
        const value = try engine.checked(c.JS_NewError(engine.context));
        errdefer engine.freeValue(value);
        const message = reply.payload orelse "";
        if (c.JS_DefinePropertyValueStr(engine.context, value, "message", c.JS_NewStringLen(engine.context, message.ptr, message.len), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return error.JavaScriptException;
        if (reply.properties) |bytes| {
            const terminated = try self.gpa.dupeZ(u8, bytes);
            defer self.gpa.free(terminated);
            const parsed = try engine.checked(c.JS_ParseJSON(engine.context, terminated.ptr, terminated.len, "host-properties.json"));
            defer engine.freeValue(parsed);
            const properties = try engine.checked(c.JS_ToObject(engine.context, parsed));
            defer engine.freeValue(properties);
            var fields: [*c]c.JSPropertyEnum = null;
            var count: u32 = 0;
            if (c.JS_GetOwnPropertyNames(engine.context, &fields, &count, properties, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) {
                return @import("../extensions/native_js_values.zig").capture(engine);
            }
            defer c.JS_FreePropertyEnum(engine.context, fields, count);
            for (fields[0..count]) |field| {
                const key_value = try engine.checked(c.JS_AtomToString(engine.context, field.atom));
                defer engine.freeValue(key_value);
                const key = try engine.toString(key_value);
                defer self.gpa.free(key);
                if (std.mem.eql(u8, key, "name") or std.mem.eql(u8, key, "message") or std.mem.eql(u8, key, "stack")) continue;
                const property = try engine.checked(c.JS_GetProperty(engine.context, properties, field.atom));
                if (c.JS_DefinePropertyValue(engine.context, value, field.atom, property, c.JS_PROP_C_W_E) < 0) {
                    return @import("../extensions/native_js_values.zig").capture(engine);
                }
            }
        }
        return value;
    }
    fn installGlobals(self: *Run, global_object: c.JSValue) !void {
        const engine = self.core.engine;
        for (self.globals, 0..) |global, index| {
            var target = c.JS_DupValue(engine.context, global_object);
            defer engine.freeValue(target);
            var member = global.name;
            if (std.mem.indexOfScalar(u8, global.name, '.')) |dot| {
                const prefix = try self.gpa.dupeZ(u8, global.name[0..dot]);
                defer self.gpa.free(prefix);
                const existing = try engine.checked(c.JS_GetPropertyStr(engine.context, global_object, prefix));
                if (c.JS_IsUndefined(existing)) {
                    engine.freeValue(existing);
                    const namespace = try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null()));
                    errdefer engine.freeValue(namespace);
                    if (c.JS_DefinePropertyValueStr(engine.context, global_object, prefix, c.JS_DupValue(engine.context, namespace), c.JS_PROP_ENUMERABLE) < 0) return error.JavaScriptException;
                    engine.freeValue(target);
                    target = namespace;
                } else {
                    engine.freeValue(target);
                    target = existing;
                }
                member = global.name[dot + 1 ..];
            }
            const key = try self.gpa.dupeZ(u8, member);
            defer self.gpa.free(key);
            const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, globalCall, key, 0, @intCast(index), 0, null));
            if (c.JS_DefinePropertyValueStr(engine.context, target, key, callback, c.JS_PROP_ENUMERABLE) < 0) return error.JavaScriptException;
        }
    }
    fn globalCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
        const engine = em.Engine.fromContext(context.?);
        const core: *vm.Execution = @ptrCast(@alignCast(engine.host_data.?));
        const self: *Run = @ptrCast(@alignCast(core.control_context.?));
        return self.globalValue(argc, argv, @intCast(magic)) catch |err| if (err == error.JavaScriptException) engine.throwCaptured() else if (err == error.OutOfMemory) engine.throwNativeOutOfMemory() else c.JS_ThrowTypeError(context, "%s", @as([*:0]const u8, @errorName(err)));
    }
    fn globalValue(self: *Run, argc: c_int, argv: [*c]c.JSValue, index: usize) !c.JSValue {
        const global = self.globals[index];
        const engine = self.core.engine;
        const value = if (global.spread) args: {
            const array = try engine.checked(c.JS_NewArray(engine.context));
            errdefer engine.freeValue(array);
            for (0..@intCast(argc)) |i| if (c.JS_SetPropertyUint32(engine.context, array, @intCast(i), c.JS_DupValue(engine.context, argv[i])) < 0) return error.JavaScriptException;
            break :args array;
        } else c.JS_DupValue(engine.context, if (argc > 0) argv[0] else c.pi_js_undefined());
        defer engine.freeValue(value);
        return self.enqueue(.global, global.name, try self.core.parseArgument(value));
    }
};
fn forbiddenExecutor(_: ?*anyopaque, _: std.mem.Allocator, _: ?json.Value, _: ?*bool) anyerror!json.Owned {
    return error.ControlledRunCannotExecuteHostTool;
}
fn identifier(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value, 0..) |byte, index| if (!(std.ascii.isAlphabetic(byte) or byte == '_' or byte == '$' or (index != 0 and std.ascii.isDigit(byte)))) return false;
    return true;
}
pub fn validateDeclarations(gpa: std.mem.Allocator, tools: []const Tool, globals: []const Global) !void {
    var raw_names: std.StringHashMapUnmanaged(void) = .empty;
    defer raw_names.deinit(gpa);
    for (tools) |tool| {
        const item = try raw_names.getOrPut(gpa, tool.name);
        if (item.found_existing) return error.DuplicateToolName;
    }
    var names: std.StringHashMapUnmanaged(void) = .empty;
    defer {
        var keys = names.keyIterator();
        while (keys.next()) |key| gpa.free(key.*);
        names.deinit(gpa);
    }
    for (tools) |tool| {
        const name = if (tool.js_name) |declared| try gpa.dupe(u8, declared) else try vm.identifier(gpa, tool.name);
        errdefer gpa.free(name);
        const item = try names.getOrPut(gpa, name);
        if (item.found_existing) return error.DuplicateToolScriptName;
    }
    var globals_seen: std.StringHashMapUnmanaged(void) = .empty;
    defer globals_seen.deinit(gpa);
    for (globals) |global| {
        var parts = std.mem.splitScalar(u8, global.name, '.');
        const first = parts.next().?;
        if (!identifier(first)) return error.InvalidGlobalName;
        inline for (.{ "tools", "ALL_TOOLS", "console", "text", "image", "exit", "globalThis", "store", "load" }) |reserved| if (std.mem.eql(u8, first, reserved)) return error.InvalidGlobalName;
        if (parts.next()) |member| if (!identifier(member) or parts.next() != null) return error.InvalidGlobalName;
        const item = try globals_seen.getOrPut(gpa, global.name);
        if (item.found_existing) return error.DuplicateGlobalName;
    }
    for (globals) |global| if (std.mem.indexOfScalar(u8, global.name, '.')) |dot| if (globals_seen.contains(global.name[0..dot])) return error.ConflictingGlobalNamespace;
}
