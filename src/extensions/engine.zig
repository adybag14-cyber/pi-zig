//! Direct C ABI for the extension language. No Node process or bridge source.
const std = @import("std");
pub const c = @cImport({
    @cInclude("engine_abi.h");
});

pub const Options = struct {
    memory_limit: usize = 64 * 1024 * 1024,
    stack_limit: usize = 1024 * 1024,
    interrupt_budget: u64 = 10_000,
    job_budget: usize = 100_000,
};

pub const Engine = struct {
    gpa: std.mem.Allocator,
    runtime: *c.JSRuntime,
    context: *c.JSContext,
    options: Options,
    interrupts: u64 = 0,
    cancelled: std.atomic.Value(bool) = .init(false),
    last_error: ?[]u8 = null,
    modules: std.StringHashMapUnmanaged([:0]u8) = .empty,

    pub fn init(gpa: std.mem.Allocator, options: Options) !*Engine {
        const self = try gpa.create(Engine);
        errdefer gpa.destroy(self);
        const runtime = c.JS_NewRuntime() orelse return error.OutOfMemory;
        errdefer c.JS_FreeRuntime(runtime);
        c.JS_SetMemoryLimit(runtime, options.memory_limit);
        c.JS_SetMaxStackSize(runtime, options.stack_limit);
        const context = c.JS_NewContext(runtime) orelse return error.OutOfMemory;
        self.* = .{ .gpa = gpa, .runtime = runtime, .context = context, .options = options };
        c.JS_SetContextOpaque(context, self);
        c.JS_SetRuntimeOpaque(runtime, self);
        c.JS_SetInterruptHandler(runtime, interrupt, self);
        c.JS_SetModuleLoaderFunc(runtime, null, moduleLoader, self);
        return self;
    }

    pub fn deinit(self: *Engine) void {
        c.JS_FreeContext(self.context);
        c.JS_FreeRuntime(self.runtime);
        if (self.last_error) |message| self.gpa.free(message);
        var modules = self.modules.iterator();
        while (modules.next()) |entry| {
            self.gpa.free(entry.key_ptr.*);
            self.gpa.free(entry.value_ptr.*);
        }
        self.modules.deinit(self.gpa);
        const gpa = self.gpa;
        gpa.destroy(self);
    }

    pub fn fromContext(context: *c.JSContext) *Engine {
        return @ptrCast(@alignCast(c.JS_GetContextOpaque(context).?));
    }

    pub fn beginInvocation(self: *Engine) void {
        self.interrupts = 0;
        self.cancelled.store(false, .release);
        if (self.last_error) |message| self.gpa.free(message);
        self.last_error = null;
    }

    pub fn cancel(self: *Engine) void {
        self.cancelled.store(true, .release);
    }

    /// Register native-loader input; source is extension input, not host code.
    pub fn registerModule(self: *Engine, name: []const u8, source: []const u8) !void {
        if (self.modules.contains(name)) return error.DuplicateExtensionModule;
        const key = try self.gpa.dupe(u8, name);
        errdefer self.gpa.free(key);
        const terminated = try self.gpa.dupeZ(u8, source);
        errdefer self.gpa.free(terminated);
        try self.modules.put(self.gpa, key, terminated);
    }

    /// Evaluate an ES module and return its owned export namespace.
    pub fn evalModule(self: *Engine, source: []const u8, filename: [:0]const u8) !c.JSValue {
        const compiled = try self.eval(source, filename, c.JS_EVAL_TYPE_MODULE | c.JS_EVAL_FLAG_COMPILE_ONLY);
        const module = c.pi_js_module(compiled) orelse {
            self.freeValue(compiled);
            return error.InvalidExtensionModule;
        };
        // JS_EvalFunction consumes the compiled module value even on failure.
        const evaluated = try self.checked(c.JS_EvalFunction(self.context, compiled));
        defer self.freeValue(evaluated);
        const settled = try self.awaitValue(evaluated);
        defer self.freeValue(settled);
        return self.checked(c.JS_GetModuleNamespace(self.context, module));
    }

    fn moduleLoader(context: ?*c.JSContext, name: [*c]const u8, context_data: ?*anyopaque) callconv(.c) ?*c.JSModuleDef {
        const self: *Engine = @ptrCast(@alignCast(context_data.?));
        const source = self.modules.get(std.mem.span(name)) orelse {
            _ = c.JS_ThrowReferenceError(context, "Native extension module not registered: %s", name);
            return null;
        };
        const compiled = c.JS_Eval(context, source.ptr, source.len, name, c.JS_EVAL_TYPE_MODULE | c.JS_EVAL_FLAG_COMPILE_ONLY);
        if (c.JS_IsException(compiled)) return null;
        // QuickJS keeps the compiled dependency in its module registry.
        const module = c.pi_js_module(compiled);
        c.JS_FreeValue(context, compiled);
        return module;
    }

    /// Returns an owned value. The caller releases it with freeValue().
    pub fn eval(self: *Engine, source: []const u8, filename: [:0]const u8, flags: c_int) !c.JSValue {
        const terminated = try self.gpa.dupeZ(u8, source);
        defer self.gpa.free(terminated);
        return self.checked(c.JS_Eval(self.context, terminated.ptr, source.len, filename.ptr, flags));
    }

    pub fn checked(self: *Engine, value: c.JSValue) !c.JSValue {
        if (c.JS_IsException(value)) {
            self.captureException(self.context);
            return error.JavaScriptException;
        }
        return value;
    }

    pub fn freeValue(self: *Engine, value: c.JSValue) void {
        c.JS_FreeValue(self.context, value);
    }

    pub const NativeFunction = *const fn (?*c.JSContext, c.JSValue, c_int, [*c]c.JSValue) callconv(.c) c.JSValue;

    /// Install a Zig callback as a real extension-language function.
    pub fn bindFunction(self: *Engine, name: [:0]const u8, function: NativeFunction, arity: c_int) !void {
        const global = c.JS_GetGlobalObject(self.context);
        defer self.freeValue(global);
        const native = try self.checked(c.JS_NewCFunction(self.context, function, name.ptr, arity));
        // SetProperty consumes native on both its success and failure paths.
        if (c.JS_SetPropertyStr(self.context, global, name.ptr, native) < 0) {
            self.captureException(self.context);
            return error.JavaScriptException;
        }
    }

    pub fn stringify(self: *Engine, value: c.JSValue) ![]u8 {
        const encoded = try self.checked(c.JS_JSONStringify(self.context, value, c.pi_js_undefined(), c.pi_js_undefined()));
        defer self.freeValue(encoded);
        return self.toString(encoded);
    }

    pub fn toString(self: *Engine, value: c.JSValue) ![]u8 {
        var length: usize = 0;
        const bytes = c.JS_ToCStringLen(self.context, &length, value);
        if (bytes == null) {
            self.captureException(self.context);
            return error.JavaScriptException;
        }
        defer c.JS_FreeCString(self.context, bytes);
        return self.gpa.dupe(u8, bytes[0..length]);
    }

    /// Return a new owned result without consuming the caller's promise/value.
    pub fn awaitValue(self: *Engine, value: c.JSValue) !c.JSValue {
        var jobs: usize = 0;
        while (c.JS_PromiseState(self.context, value) == c.JS_PROMISE_PENDING) {
            if (jobs >= self.options.job_budget) return error.JavaScriptJobLimit;
            jobs += 1;
            var context: ?*c.JSContext = null;
            const status = c.JS_ExecutePendingJob(self.runtime, &context);
            if (status < 0) {
                self.captureException(context orelse self.context);
                return error.JavaScriptException;
            }
            if (status == 0) return error.JavaScriptPromiseUnsettled;
        }
        return switch (c.JS_PromiseState(self.context, value)) {
            c.JS_PROMISE_REJECTED => blk: {
                const reason = c.JS_PromiseResult(self.context, value);
                defer self.freeValue(reason);
                if (self.last_error) |message| self.gpa.free(message);
                self.last_error = self.toString(reason) catch null;
                break :blk error.JavaScriptException;
            },
            c.JS_PROMISE_FULFILLED => c.JS_PromiseResult(self.context, value),
            else => c.JS_DupValue(self.context, value),
        };
    }

    fn captureException(self: *Engine, context: *c.JSContext) void {
        const exception = c.JS_GetException(context);
        defer c.JS_FreeValue(context, exception);
        const text = c.JS_ToCString(context, exception);
        defer if (text != null) c.JS_FreeCString(context, text);
        if (self.last_error) |message| self.gpa.free(message);
        self.last_error = if (text == null) null else self.gpa.dupe(u8, std.mem.span(text)) catch null;
    }

    fn interrupt(_: ?*c.JSRuntime, context_data: ?*anyopaque) callconv(.c) c_int {
        const self: *Engine = @ptrCast(@alignCast(context_data.?));
        if (self.cancelled.load(.acquire)) return 1;
        self.interrupts += 1;
        return if (self.interrupts > self.options.interrupt_budget) 1 else 0;
    }
};

test "linked C engine executes modern extension language without Node" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const value = try engine.eval("JSON.stringify({ value: 2 ** 5, text: 'hello 🌍', spread: [...new Set([1, 1, 2])] })", "fixture.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(value);
    const text = try engine.toString(value);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"value\":32,\"text\":\"hello 🌍\",\"spread\":[1,2]}", text);
}

test "linked C engine settles promises and async generator code" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const promise = try engine.eval("(async () => { async function* values() { yield 2; yield 3; } let total = 0; for await (const value of values()) total += value; return total; })()", "async-fixture.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(promise);
    const result = try engine.awaitValue(promise);
    defer engine.freeValue(result);
    const text = try engine.stringify(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("5", text);
}

test "linked C engine reports rejected promises and syntax errors" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try std.testing.expectError(error.JavaScriptException, engine.eval("const = invalid;", "invalid-fixture.js", c.JS_EVAL_TYPE_GLOBAL));
    try std.testing.expect(engine.last_error != null);
    engine.beginInvocation();
    const promise = try engine.eval("Promise.reject(new Error('extension rejected'))", "rejected-fixture.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(promise);
    try std.testing.expectError(error.JavaScriptException, engine.awaitValue(promise));
    try std.testing.expect(std.mem.indexOf(u8, engine.last_error.?, "extension rejected") != null);
}

test "linked C engine interrupts infinite loops and supports cancellation" {
    const engine = try Engine.init(std.testing.allocator, .{ .interrupt_budget = 2 });
    defer engine.deinit();
    try std.testing.expectError(error.JavaScriptException, engine.eval("while (true) {}", "hostile-fixture.js", c.JS_EVAL_TYPE_GLOBAL));
    engine.beginInvocation();
    engine.cancel();
    try std.testing.expectError(error.JavaScriptException, engine.eval("while (true) {}", "cancel-fixture.js", c.JS_EVAL_TYPE_GLOBAL));
}

test "native module loader resolves relative imports and top level await" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.registerModule("helpers/value.js", "export const value = 41;");
    const namespace = try engine.evalModule("import { value } from './helpers/value.js'; export const answer = await Promise.resolve(value + 1); export default (name) => `hello ${name}`;", "entry.js");
    defer engine.freeValue(namespace);
    const answer = c.JS_GetPropertyStr(engine.context, namespace, "answer");
    defer engine.freeValue(answer);
    const encoded = try engine.stringify(answer);
    defer std.testing.allocator.free(encoded);
    try std.testing.expectEqualStrings("42", encoded);
    const factory = c.JS_GetPropertyStr(engine.context, namespace, "default");
    defer engine.freeValue(factory);
    const name = c.JS_NewString(engine.context, "pi");
    defer engine.freeValue(name);
    var arguments = [_]c.JSValue{name};
    const result = try engine.checked(c.JS_Call(engine.context, factory, c.pi_js_undefined(), 1, &arguments));
    defer engine.freeValue(result);
    const greeting = try engine.toString(result);
    defer std.testing.allocator.free(greeting);
    try std.testing.expectEqualStrings("hello pi", greeting);
}

test "native module loader rejects missing dependencies and duplicate registrations" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.registerModule("helper.js", "export const value = 1;");
    try std.testing.expectError(error.DuplicateExtensionModule, engine.registerModule("helper.js", "export const value = 2;"));
    try std.testing.expectError(error.JavaScriptException, engine.evalModule("import './missing.js';", "missing-entry.js"));
    try std.testing.expect(engine.last_error != null);
}

test "extension calls a Zig host function through the direct C ABI" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const Add = struct {
        fn call(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
            if (argc != 2) return c.JS_ThrowTypeError(context, "nativeAdd expects two integer arguments");
            var left: i32 = 0;
            var right: i32 = 0;
            if (c.JS_ToInt32(context, &left, argv[0]) < 0 or c.JS_ToInt32(context, &right, argv[1]) < 0) return c.JS_ThrowTypeError(context, "nativeAdd expects integers");
            const value = std.math.add(i32, left, right) catch return c.JS_ThrowRangeError(context, "nativeAdd overflow");
            return c.pi_js_int32(context, value);
        }
    };
    try engine.bindFunction("nativeAdd", Add.call, 2);
    const value = try engine.eval("nativeAdd(19, 23)", "native-host-fixture.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(value);
    const encoded = try engine.stringify(value);
    defer std.testing.allocator.free(encoded);
    try std.testing.expectEqualStrings("42", encoded);
    try std.testing.expectError(error.JavaScriptException, engine.eval("nativeAdd(1)", "native-argument-fixture.js", c.JS_EVAL_TYPE_GLOBAL));
}
