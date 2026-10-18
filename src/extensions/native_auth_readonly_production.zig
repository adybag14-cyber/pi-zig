//! Actual c268 ReadOnlyAuthStorage. No Source method here contains Await;
//! genuine AF return performs adoption, and load/constructor remain ordinary.
//! Requires the separately reviewed canonical SDK ownRoot successor.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const owned = @import("native_sdk_owned_completion.zig");
const guards = @import("native_agent_af_values.zig");
const af = @import("native_async_function.zig");
const nf = @import("native_node_function.zig");
const Method = enum { load, read, list, modify, delete };
pub const Imports = struct { get_agent_dir: c.JSValue, resolve_config_value: c.JSValue, is_command_config_value: c.JSValue };
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }

// All newly owned values enter the actual provider root store through the
// canonical SDK helper. No raw Scope.own overflow can retire before host OOM.
const Ops = struct {
    scope: *Scope,
    fn engine(self: Ops) *v.em.Engine { return self.scope.engine; }
    fn adopt(self: Ops, generation: u64, result: anyerror!c.JSValue) !c.JSValue {
        const value = try guards.guard(self.engine(), generation, result);
        const checked = try guards.guard(self.engine(), generation, self.engine().checked(value));
        return owned.ownRoot(self.scope, checked);
    }
    fn own(self: Ops, value: c.JSValue) !c.JSValue { return owned.ownRoot(self.scope, value); }
    fn get(self: Ops, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
        const generation = self.engine().native_allocation_generation;
        return self.adopt(generation, v.js.get(self.engine(), object, name));
    }
    fn key(self: Ops, object: c.JSValue, key_value: c.JSValue) !c.JSValue {
        const generation = self.engine().native_allocation_generation;
        return self.adopt(generation, v.js.getKey(self.engine(), object, key_value));
    }
    fn global(self: Ops, name: [*:0]const u8) !c.JSValue {
        const generation = self.engine().native_allocation_generation;
        return self.adopt(generation, v.js.global(self.engine(), name));
    }
    fn text(self: Ops, text_value: []const u8) !c.JSValue {
        const generation = self.engine().native_allocation_generation;
        return self.adopt(generation, @import("native_sdk.zig").text(self.engine(), text_value));
    }
    fn object(self: Ops) !c.JSValue {
        const generation = self.engine().native_allocation_generation;
        return self.adopt(generation, v.js.object(self.engine()));
    }
    fn call(self: Ops, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
        const generation = self.engine().native_allocation_generation;
        return self.adopt(generation, v.js.call(self.engine(), function, receiver, args));
    }
    fn invoke(self: Ops, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
        return self.call(try self.get(receiver, name), receiver, args);
    }
    fn construct(self: Ops, constructor: c.JSValue, args: []const c.JSValue) !c.JSValue {
        const generation = self.engine().native_allocation_generation;
        return self.adopt(generation, self.engine().checked(c.JS_CallConstructor(self.engine().context, constructor, @intCast(args.len), @constCast(args.ptr))));
    }
    fn put(self: Ops, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
        const generation = self.engine().native_allocation_generation;
        const result = self.scope.put(target, name, value);
        _ = try guards.guard(self.engine(), generation, if (result) |_| self.engine().checked(c.pi_js_undefined()) else |err| err);
    }
    fn set(self: Ops, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
        const generation = self.engine().native_allocation_generation;
        const result = self.scope.set(target, name, value);
        _ = try guards.guard(self.engine(), generation, if (result) |_| self.engine().checked(c.pi_js_undefined()) else |err| err);
    }
    fn equal(self: Ops, left: c.JSValue, text_value: []const u8) !bool { return self.scope.equal(left, try self.text(text_value)); }
    fn truthy(self: Ops, value: c.JSValue) bool { return c.JS_ToBool(self.engine().context, value) != 0; }
    fn string(self: Ops, value: c.JSValue) !c.JSValue {
        const generation = self.engine().native_allocation_generation;
        return self.adopt(generation, self.engine().checked(c.JS_ToString(self.engine().context, value)));
    }
    fn concat(self: Ops, left: c.JSValue, right: c.JSValue) !c.JSValue {
        const generation = self.engine().native_allocation_generation;
        return self.adopt(generation, self.engine().checked(c.JS_PiBinaryOperator(self.engine().context, 0, left, right)));
    }
    fn raise(self: Ops, reason: c.JSValue) anyerror {
        _ = self.engine().checked(c.JS_Throw(self.engine().context, c.JS_DupValue(self.engine().context, reason))) catch |err| return err;
        unreachable;
    }
    fn fail(self: Ops, message: []const u8) anyerror {
        const constructor = self.global("Error") catch |err| return err;
        return self.raise(self.construct(constructor, &.{self.text(message) catch |err| return err}) catch |err| return err);
    }
    fn callback(self: Ops, name: [*:0]const u8, length: c_int, function: nf.Callback, roots: []const c.JSValue) !c.JSValue {
        const generation = self.engine().native_allocation_generation;
        return self.adopt(generation, nf.createArrow(self.engine(), name, length, function, roots));
    }
};
pub fn create(engine: *v.em.Engine, imports: Imports) !c.JSValue {
    try engine.checkNativeEntry();
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var invocation: v.em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    const result = createOwned(engine, imports) catch |err| {
        const failed = @import("native_sdk.zig").fail(engine, err);
        return engine.checked(engine.leaveNativeInvocation(&invocation, failed));
    };
    return engine.checked(engine.leaveNativeInvocation(&invocation, result));
}
fn createOwned(engine: *v.em.Engine, imports: Imports) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    return owned.finishValue(&scope, createBody(.{ .scope = &scope }, imports));
}
fn createBody(o: Ops, imports: Imports) !c.JSValue {
    inline for (@typeInfo(Imports).@"struct".fields) |field| if (!c.JS_IsFunction(o.engine().context, @field(imports, field.name))) return error.RequiredActualReadonlyAuthBinding;
    const io = o.engine().native_io orelse return error.RequiredReadonlyAuthIo;
    if (!o.engine().native_module_values.contains("node:fs")) try @import("node_fs.zig").install(o.engine(), io);
    if (!o.engine().native_module_values.contains("node:path")) try @import("node_path.zig").install(o.engine(), io);
    const owner = try o.object();
    inline for (@typeInfo(Imports).@"struct".fields) |field| try o.put(owner, field.name, @field(imports, field.name));
    try o.put(owner, "readFileSync", try o.get(o.engine().native_module_values.get("node:fs").?, "readFileSync"));
    try o.put(owner, "join", try o.get(o.engine().native_module_values.get("node:path").?, "join"));
    const prototype = try o.object();
    const generation = o.engine().native_allocation_generation;
    const constructor = try o.adopt(generation, @import("native_class.zig").constructor(o.engine(), "ReadOnlyAuthStorage", 0, prototype, construct, &.{owner}));
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        const method: Method = @enumFromInt(field.value);
        const Adapter = struct {
            fn call(host: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                var local: Scope = .{ .engine = host };
                return owned.finishValue(&local, invoke(.{ .scope = &local }, receiver, args, roots[0], method));
            }
        };
        const length: c_int = switch (method) { .load => 0, .list => 1, .read, .delete => 2, .modify => 3 };
        const function_generation = o.engine().native_allocation_generation;
        const function = try o.adopt(function_generation, if (method == .load)
            nf.createMethod(o.engine(), field.name, length, Adapter.call, &.{owner})
        else af.create(o.engine(), field.name, length, Adapter.call, &.{owner}));
        const define_generation = o.engine().native_allocation_generation;
        const status = c.JS_DefinePropertyValueStr(o.engine().context, prototype, field.name, c.JS_DupValue(o.engine().context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
        _ = try guards.guard(o.engine(), define_generation, if (status < 0) @as(anyerror!c.JSValue, v.js.capture(o.engine())) else o.engine().checked(c.pi_js_undefined()));
    }
    const exports = try o.object();
    try o.put(exports, "ReadOnlyAuthStorage", constructor);
    const helper_generation = o.engine().native_allocation_generation;
    const read_stored = try o.adopt(helper_generation, nf.create(o.engine(), "readStoredCredential", 1, readStoredCall, &.{owner}));
    try o.put(exports, "readStoredCredential", read_stored);
    return c.JS_DupValue(o.engine().context, exports);
}
fn readStoredCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    return owned.finishValue(&scope, readStoredStart(.{ .scope = &scope }, args, roots[0]));
}
fn readStoredStart(o: Ops, args: []const c.JSValue, owner: c.JSValue) !c.JSValue {
    var path = arg(args, 1);
    // Default argument evaluation is OUTSIDE Source's try/catch.
    if (c.JS_IsUndefined(path)) {
        const join = try o.get(owner, "join");
        path = try o.call(join, c.pi_js_undefined(), &.{ try o.call(try o.get(owner, "get_agent_dir"), c.pi_js_undefined(), &.{}), try o.text("auth.json") });
    }
    const result = readStoredTry(o.engine(), owner, path, arg(args, 0)) catch |err| {
        _ = try ordinaryCause(o, err); // Current/fresh fatal escapes; ordinary is suppressed.
        return c.pi_js_undefined();
    };
    return result;
}
fn readStoredTry(engine: *v.em.Engine, owner: c.JSValue, path: c.JSValue, provider: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    return owned.finishValue(&scope, readStoredTryBody(.{ .scope = &scope }, owner, path, provider));
}
fn readStoredTryBody(o: Ops, owner: c.JSValue, path: c.JSValue, provider: c.JSValue) !c.JSValue {
    const json = try o.global("JSON");
    const parse = try o.get(json, "parse");
    const read_file = try o.get(owner, "readFileSync");
    const generation = o.engine().native_allocation_generation;
    const normalized = try o.adopt(generation, @import("native_sdk_source_paths.zig").normalize(o.engine(), path, c.pi_js_undefined()));
    const text_value = try o.call(read_file, c.pi_js_undefined(), &.{ normalized, try o.text("utf-8") });
    const stripped = try o.own(try stripBom(o.engine(), text_value));
    const data_value = try o.call(parse, json, &.{stripped});
    return c.JS_DupValue(o.engine().context, try o.key(data_value, provider));
}
fn construct(engine: *v.em.Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    return owned.finishValue(&scope, constructBody(.{ .scope = &scope }, target, args, roots[0]));
}
fn constructBody(o: Ops, target: c.JSValue, args: []const c.JSValue, owner: c.JSValue) !c.JSValue {
    const prototype = try o.get(target, "prototype");
    const generation = o.engine().native_allocation_generation;
    const receiver = try o.adopt(generation, o.engine().checked(if (c.JS_IsObject(prototype)) c.JS_NewObjectProto(o.engine().context, prototype) else c.JS_NewObject(o.engine().context)));
    try o.put(receiver, "authPath", c.pi_js_undefined());
    try o.put(receiver, "data", c.pi_js_undefined());
    var path = arg(args, 0);
    if (c.JS_IsUndefined(path)) {
        const join = try o.get(owner, "join");
        path = try o.call(join, c.pi_js_undefined(), &.{ try o.call(try o.get(owner, "get_agent_dir"), c.pi_js_undefined(), &.{}), try o.text("auth.json") });
    }
    const normalize_generation = o.engine().native_allocation_generation;
    try o.set(receiver, "authPath", try o.adopt(normalize_generation, @import("native_sdk_source_paths.zig").normalize(o.engine(), path, c.pi_js_undefined())));
    return c.JS_DupValue(o.engine().context, receiver);
}
fn check(engine: *v.em.Engine, options: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    return owned.finishVoid(&scope, checkBody(.{ .scope = &scope }, options));
}
fn checkBody(o: Ops, options: c.JSValue) !void {
    if (v.nullish(options)) return;
    const signal = try o.get(options, "signal");
    if (!v.nullish(signal)) _ = try o.invoke(signal, "throwIfAborted", &.{});
}
fn invoke(o: Ops, receiver: c.JSValue, args: []const c.JSValue, owner: c.JSValue, method: Method) !c.JSValue {
    if (method == .modify or method == .delete) return o.fail("Read-only credential storage cannot modify auth.json");
    if (method == .load) return c.JS_DupValue(o.engine().context, try load(o, receiver, owner));
    const options = arg(args, if (method == .list) 0 else 1);
    try check(o.engine(), options);
    if (method == .list) {
        // Callee Object.entries is evaluated before this.load(), and map's
        // callee is read before its actual native mapper argument is created.
        const result = try o.own(try buildList(o.engine(), receiver));
        try check(o.engine(), options);
        return c.JS_DupValue(o.engine().context, result);
    }
    const credential = try o.key(try o.invoke(receiver, "load", &.{}), arg(args, 0));
    try check(o.engine(), options);
    if (!o.truthy(credential)) return c.pi_js_undefined();
    if (try cloneNeeded(o.engine(), credential, owner))
        return c.JS_DupValue(o.engine().context, try o.call(try o.global("structuredClone"), c.pi_js_undefined(), &.{credential}));
    const generation = o.engine().native_allocation_generation;
    const result = try o.adopt(generation, v.js.spread(o.engine(), credential));
    const resolver = try o.get(owner, "resolve_config_value");
    try o.put(result, "key", try o.call(resolver, c.pi_js_undefined(), &.{ try o.get(credential, "key"), try o.get(credential, "env") }));
    return c.JS_DupValue(o.engine().context, result);
}
fn ordinaryCause(o: Ops, err: anyerror) !c.JSValue {
    try o.engine().checkNativeEntry();
    if (err != error.JavaScriptException) return err;
    const reason = o.engine().captured_exception orelse return err;
    o.engine().captured_exception = null;
    return o.own(reason);
}
fn load(o: Ops, receiver: c.JSValue, owner: c.JSValue) !c.JSValue {
    const cached = try o.get(receiver, "data");
    if (o.truthy(cached)) return cached;
    const parsed = o.own(readParsed(o.engine(), receiver, owner) catch |err| {
        const reason = try ordinaryCause(o, err);
        if (try o.equal(try o.get(reason, "code"), "ENOENT")) {
            const empty = try o.object(); try o.set(receiver, "data", empty); return empty;
        }
        // new Error's callee is captured before its template interpolation.
        const constructor = try o.global("Error");
        const error_class = try o.global("Error");
        const generation = o.engine().native_allocation_generation;
        const instance = c.JS_IsInstanceOf(o.engine().context, reason, error_class);
        _ = try guards.guard(o.engine(), generation, if (instance < 0) @as(anyerror!c.JSValue, v.js.capture(o.engine())) else o.engine().checked(c.pi_js_undefined()));
        const detail = if (instance != 0) try o.get(reason, "message") else try o.call(try o.global("String"), c.pi_js_undefined(), &.{reason});
        const message = try o.concat(try o.text("Failed to read auth.json: "), try o.string(detail));
        return o.raise(try o.construct(constructor, &.{message}));
    }) catch |err| return err;
    try validate(o.engine(), parsed);
    try o.set(receiver, "data", parsed);
    return parsed;
}
fn readParsed(engine: *v.em.Engine, receiver: c.JSValue, owner: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    return owned.finishValue(&scope, readParsedBody(.{ .scope = &scope }, receiver, owner));
}
fn readParsedBody(o: Ops, receiver: c.JSValue, owner: c.JSValue) !c.JSValue {
    const json = try o.global("JSON");
    const parse = try o.get(json, "parse");
    const text = try o.call(try o.get(owner, "readFileSync"), c.pi_js_undefined(), &.{ try o.get(receiver, "authPath"), try o.text("utf-8") });
    const stripped = try o.own(try stripBom(o.engine(), text));
    return c.JS_DupValue(o.engine().context, try o.call(parse, json, &.{stripped}));
}

// The validation traversal and pair binding below are completed independently
// of the ordinary file read catch. Their errors must never be reformatted as
// read failures. Each iteration has its own native root retirement boundary.
fn stripBom(engine: *v.em.Engine, text_value: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    return owned.finishValue(&scope, stripBomBody(.{ .scope = &scope }, text_value));
}
fn stripBomBody(o: Ops, text_value: c.JSValue) !c.JSValue {
    const starts_with = try o.get(text_value, "startsWith");
    const result = if (o.truthy(try o.call(starts_with, text_value, &.{try o.text("\xef\xbb\xbf")})))
        try o.invoke(text_value, "slice", &.{c.JS_NewInt32(o.engine().context, 1)}) else text_value;
    return c.JS_DupValue(o.engine().context, result);
}
fn propertyTruth(engine: *v.em.Engine, target: c.JSValue, name: [*:0]const u8) !bool {
    var scope: Scope = .{ .engine = engine };
    const o: Ops = .{ .scope = &scope };
    const result = o.get(target, name);
    const selected: anyerror!c.JSValue = if (result) |value| c.pi_js_bool(engine.context, @intFromBool(o.truthy(value))) else |err| err;
    return c.JS_ToBool(engine.context, try owned.finishValue(&scope, selected)) != 0;
}
fn typeIsApiKey(engine: *v.em.Engine, target: c.JSValue) !bool {
    var scope: Scope = .{ .engine = engine };
    const result = typeIsApiKeyBody(.{ .scope = &scope }, target);
    const selected: anyerror!c.JSValue = if (result) |value| c.pi_js_bool(engine.context, @intFromBool(value)) else |err| err;
    return c.JS_ToBool(engine.context, try owned.finishValue(&scope, selected)) != 0;
}
fn typeIsApiKeyBody(o: Ops, target: c.JSValue) !bool { return o.equal(try o.get(target, "type"), "api_key"); }
fn cloneNeeded(engine: *v.em.Engine, credential: c.JSValue, owner: c.JSValue) !bool {
    if (!try typeIsApiKey(engine, credential)) return true;
    if (!try propertyTruth(engine, credential, "key")) return true;
    var scope: Scope = .{ .engine = engine };
    const result = commandCredential(.{ .scope = &scope }, credential, owner);
    const selected: anyerror!c.JSValue = if (result) |value| c.pi_js_bool(engine.context, @intFromBool(value)) else |err| err;
    return c.JS_ToBool(engine.context, try owned.finishValue(&scope, selected)) != 0;
}
fn commandCredential(o: Ops, credential: c.JSValue, owner: c.JSValue) !bool {
    return o.truthy(try o.call(try o.get(owner, "is_command_config_value"), c.pi_js_undefined(), &.{try o.get(credential, "key")}));
}
fn buildList(engine: *v.em.Engine, receiver: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    return owned.finishValue(&scope, buildListBody(.{ .scope = &scope }, receiver));
}
fn buildListBody(o: Ops, receiver: c.JSValue) !c.JSValue {
    const object = try o.global("Object");
    const entries = try o.get(object, "entries");
    const rows = try o.call(entries, object, &.{try o.invoke(receiver, "load", &.{})});
    const map = try o.get(rows, "map");
    const mapper = try o.callback("", 1, listMapper, &.{});
    return c.JS_DupValue(o.engine().context, try o.call(map, rows, &.{mapper}));
}

const Iterator = struct {
    o: Ops,
    iterator: c.JSValue,
    next_function: c.JSValue,
    done: bool = false,
    steps: usize = 0,
    fn init(o: Ops, iterable: c.JSValue) !Iterator {
        const iterator = try o.own(try iteratorValue(o.engine(), iterable));
        return .{ .o = o, .iterator = iterator, .next_function = try o.get(iterator, "next") };
    }
    fn next(self: *Iterator) !?c.JSValue {
        if (self.done) return null;
        self.steps +|= 1;
        try @import("native_jiti_budget.zig").check(self.o.engine(), self.steps);
        const result = nextValue(self.o.engine(), self.iterator, self.next_function) catch |err| {
            self.done = true; // Abrupt IteratorStepValue does not gain return().
            return err;
        };
        if (result == null) self.done = true;
        return result;
    }
    fn close(self: *Iterator) !void {
        if (self.done) return;
        self.done = true;
        const method = try self.o.get(self.iterator, "return");
        if (v.nullish(method)) return;
        const result = try self.o.call(method, self.iterator, &.{});
        if (!c.JS_IsObject(result)) return typeError(self.o, "Iterator return result is not an object");
    }
    fn abrupt(self: *Iterator, err: anyerror) anyerror {
        // Actual current/fresh fatal stops before guest close. Ordinary Source
        // A wins an ordinary return getter/call failure B; all roots still
        // retire under the surrounding owned completion with per-free guards.
        const original = ordinaryCause(self.o, err) catch |actual| return actual;
        self.close() catch |close_error| { _ = ordinaryCause(self.o, close_error) catch |actual| return actual; };
        return self.o.raise(original);
    }
};
fn typeError(o: Ops, text_value: [*:0]const u8) anyerror {
    const generation = o.engine().native_allocation_generation;
    _ = guards.guard(o.engine(), generation, @as(anyerror!c.JSValue, v.js.typeError(o.engine(), text_value))) catch |err| return err;
    unreachable;
}
fn iteratorValue(engine: *v.em.Engine, iterable: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    return owned.finishValue(&scope, iteratorValueBody(.{ .scope = &scope }, iterable));
}
fn iteratorValueBody(o: Ops, iterable: c.JSValue) !c.JSValue {
    const generation = o.engine().native_allocation_generation;
    const symbol = try o.adopt(generation, o.engine().checked(c.JS_GetIteratorSymbol(o.engine().context)));
    const method = try o.key(iterable, symbol);
    const iterator = try o.call(method, iterable, &.{});
    if (!c.JS_IsObject(iterator)) return typeError(o, "Iterator is not an object");
    return c.JS_DupValue(o.engine().context, iterator);
}
fn nextValue(engine: *v.em.Engine, iterator: c.JSValue, next: c.JSValue) !?c.JSValue {
    var scope: Scope = .{ .engine = engine };
    const outcome = nextValueBody(.{ .scope = &scope }, iterator, next);
    const complete = if (outcome) |value| value == null else |_| false;
    const selected: anyerror!c.JSValue = if (outcome) |value| value orelse c.pi_js_undefined() else |err| err;
    const value = try owned.finishValue(&scope, selected);
    return if (complete) null else value;
}
fn nextValueBody(o: Ops, iterator: c.JSValue, next: c.JSValue) !?c.JSValue {
    const step = try o.call(next, iterator, &.{});
    if (!c.JS_IsObject(step)) return typeError(o, "Iterator result is not an object");
    if (try propertyTruth(o.engine(), step, "done")) return null;
    return c.JS_DupValue(o.engine().context, try o.get(step, "value"));
}
const Pair = struct { first: c.JSValue = c.pi_js_undefined(), second: c.JSValue = c.pi_js_undefined() };
fn pair(engine: *v.em.Engine, value: c.JSValue) !Pair {
    var scope: Scope = .{ .engine = engine };
    var result: Pair = .{};
    const outcome = pairBody(.{ .scope = &scope }, value, &result);
    owned.finishVoid(&scope, outcome) catch |err| {
        var completion = owned.Completion.initVoid(engine, err);
        completion.release(result.first);
        completion.release(result.second);
        try completion.finishVoid();
        unreachable;
    };
    return result;
}
fn pairBody(o: Ops, value: c.JSValue, result: *Pair) !void {
    var iterator = try Iterator.init(o, value);
    const first = if (try iterator.next()) |item| try o.own(item) else c.pi_js_undefined();
    const second = if (try iterator.next()) |item| try o.own(item) else c.pi_js_undefined();
    try iterator.close();
    result.* = .{ .first = c.JS_DupValue(o.engine().context, first), .second = c.JS_DupValue(o.engine().context, second) };
}
fn ownPair(o: Ops, value: Pair) !Pair {
    const first = o.own(value.first) catch |err| {
        var completion = owned.Completion.initValue(o.engine(), err);
        completion.release(value.second);
        _ = try completion.finishValue();
        unreachable;
    };
    const second = try o.own(value.second);
    return .{ .first = first, .second = second };
}
fn listMapper(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    return owned.finishValue(&scope, listMapperBody(.{ .scope = &scope }, arg(args, 0)));
}
fn listMapperBody(o: Ops, value: c.JSValue) !c.JSValue {
    const fields = try ownPair(o, try pair(o.engine(), value));
    const result = try o.object();
    try o.put(result, "providerId", fields.first);
    try o.put(result, "type", try o.get(fields.second, "type"));
    return c.JS_DupValue(o.engine().context, result);
}
fn record(engine: *v.em.Engine, value: c.JSValue) !bool {
    var scope: Scope = .{ .engine = engine };
    const result = recordBody(.{ .scope = &scope }, value);
    const selected: anyerror!c.JSValue = if (result) |answer| c.pi_js_bool(engine.context, @intFromBool(answer)) else |err| err;
    return c.JS_ToBool(engine.context, try owned.finishValue(&scope, selected)) != 0;
}
fn recordBody(o: Ops, value: c.JSValue) !bool {
    if (!c.JS_IsObject(value) or c.JS_IsFunction(o.engine().context, value) or c.JS_IsNull(value)) return false;
    return !o.truthy(try o.invoke(try o.global("Array"), "isArray", &.{value}));
}
fn invalidCredential(o: Ops, id: c.JSValue) anyerror {
    const constructor = o.global("Error") catch |err| return err;
    const prefix = o.text("Invalid auth.json credential for provider \"") catch |err| return err;
    const text_value = o.concat(o.concat(prefix, o.string(id) catch |err| return err) catch |err| return err, o.text("\"") catch |err| return err) catch |err| return err;
    return o.raise(o.construct(constructor, &.{text_value}) catch |err| return err);
}
fn validate(engine: *v.em.Engine, parsed: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    return owned.finishVoid(&scope, validateBody(.{ .scope = &scope }, parsed));
}
fn validateBody(o: Ops, parsed: c.JSValue) !void {
    if (!try record(o.engine(), parsed)) return o.fail("Invalid auth.json: expected an object");
    const rows = try o.invoke(try o.global("Object"), "entries", &.{parsed});
    var iterator = try Iterator.init(o, rows);
    while (try iterator.next()) |value| {
        validateRow(o.engine(), value) catch |err| return iterator.abrupt(err);
    }
}
fn validateRow(engine: *v.em.Engine, value: c.JSValue) !void {
    const fields = pair(engine, value);
    var binding = owned.Completion.initVoid(engine, if (fields) |_| {} else |err| err);
    binding.release(value); // Completed iteration-value/pattern temporary.
    binding.finishVoid() catch |err| {
        if (fields) |result| {
            var cleanup = owned.Completion.initVoid(engine, err);
            cleanup.release(result.first);
            cleanup.release(result.second);
            try cleanup.finishVoid();
            unreachable;
        } else |_| return err;
    };
    var scope: Scope = .{ .engine = engine };
    return owned.finishVoid(&scope, validateRowBody(.{ .scope = &scope }, try fields));
}
fn validateRowBody(o: Ops, bindings: Pair) !void {
    const fields = try ownPair(o, bindings);
    const credential = fields.second;
    if (!try record(o.engine(), credential)) return invalidCredential(o, fields.first);
    if (try fieldEqual(o.engine(), credential, "type", "api_key")) {
        const valid_key = try fieldType(o.engine(), credential, "key", .undefined_value) or try fieldType(o.engine(), credential, "key", .string);
        const valid_env = try validEnvironment(o, credential);
        if (valid_key and valid_env) return;
    } else if (try fieldEqual(o.engine(), credential, "type", "oauth") and try fieldType(o.engine(), credential, "access", .string) and try fieldType(o.engine(), credential, "refresh", .string) and try fieldType(o.engine(), credential, "expires", .number)) {
        const number = try o.global("Number");
        const finite = try o.get(number, "isFinite");
        if (o.truthy(try o.call(finite, number, &.{try o.get(credential, "expires")}))) return;
    }
    return invalidCredential(o, fields.first);
}
fn validEnvironment(o: Ops, credential: c.JSValue) !bool {
    if (try fieldType(o.engine(), credential, "env", .undefined_value)) return true;
    // Deliberately repeat Source reads. Cached records are writable and a live
    // JSON/Object.entries collaborator can supply accessors/proxies.
    if (!try fieldType(o.engine(), credential, "env", .object_including_null)) return false;
    if (try fieldType(o.engine(), credential, "env", .null_value)) return false;
    if (try fieldArray(o.engine(), credential, "env")) return false;
    const object = try o.global("Object");
    const values = try o.get(object, "values");
    const entries = try o.call(values, object, &.{try o.get(credential, "env")});
    const every = try o.get(entries, "every");
    const callback = try o.callback("", 1, isString, &.{});
    return o.truthy(try o.call(every, entries, &.{callback}));
}
fn isString(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsString(arg(args, 0))));
}
const TypeTest = enum { undefined_value, string, number, object_including_null, null_value };
fn fieldType(engine: *v.em.Engine, target: c.JSValue, name: [*:0]const u8, kind: TypeTest) !bool {
    var scope: Scope = .{ .engine = engine };
    const o: Ops = .{ .scope = &scope };
    const result = o.get(target, name);
    const selected: anyerror!c.JSValue = if (result) |value| c.pi_js_bool(engine.context, @intFromBool(switch (kind) {
        .undefined_value => c.JS_IsUndefined(value), .string => c.JS_IsString(value), .number => c.JS_IsNumber(value),
        .object_including_null => c.JS_IsNull(value) or (c.JS_IsObject(value) and !c.JS_IsFunction(engine.context, value)),
        .null_value => c.JS_IsNull(value),
    })) else |err| err;
    return c.JS_ToBool(engine.context, try owned.finishValue(&scope, selected)) != 0;
}
fn fieldEqual(engine: *v.em.Engine, target: c.JSValue, name: [*:0]const u8, text_value: []const u8) !bool {
    var scope: Scope = .{ .engine = engine };
    const result = fieldEqualBody(.{ .scope = &scope }, target, name, text_value);
    const selected: anyerror!c.JSValue = if (result) |answer| c.pi_js_bool(engine.context, @intFromBool(answer)) else |err| err;
    return c.JS_ToBool(engine.context, try owned.finishValue(&scope, selected)) != 0;
}
fn fieldEqualBody(o: Ops, target: c.JSValue, name: [*:0]const u8, text_value: []const u8) !bool { return o.equal(try o.get(target, name), text_value); }
fn fieldArray(engine: *v.em.Engine, target: c.JSValue, name: [*:0]const u8) !bool {
    var scope: Scope = .{ .engine = engine };
    const result = fieldArrayBody(.{ .scope = &scope }, target, name);
    const selected: anyerror!c.JSValue = if (result) |answer| c.pi_js_bool(engine.context, @intFromBool(answer)) else |err| err;
    return c.JS_ToBool(engine.context, try owned.finishValue(&scope, selected)) != 0;
}
fn fieldArrayBody(o: Ops, target: c.JSValue, name: [*:0]const u8) !bool {
    const array = try o.global("Array");
    const function = try o.get(array, "isArray");
    return o.truthy(try o.call(function, array, &.{try o.get(target, name)}));
}
