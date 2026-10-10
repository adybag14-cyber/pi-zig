//! Owner-thread raw terminal listeners, including transform and consumption.
const std = @import("std");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const Token = struct { gpa: std.mem.Allocator, manager: ?*Manager };
const Listener = struct { owner: u64, id: u64, function: c.JSValue };
fn finalizer(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const token: *Token = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    token.gpa.destroy(token);
}
pub const Result = struct { data: []u8, consume: bool = false };
pub const Manager = struct {
    engine: *engine_mod.Engine,
    token: c.JSValue,
    token_class: c.JSClassID,
    owners: std.AutoHashMapUnmanaged(u64, void) = .empty,
    listeners: std.ArrayList(Listener) = .empty,
    next_id: u64 = 1,
    pub fn init(engine: *engine_mod.Engine) !Manager {
        var class: c.JSClassID = 0;
        _ = c.JS_NewClassID(engine.runtime, &class);
        const definition: c.JSClassDef = .{ .class_name = "Native Terminal Listener", .finalizer = finalizer };
        if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
        const token = try engine.checked(c.JS_NewObjectClass(engine.context, @intCast(class)));
        errdefer engine.freeValue(token);
        const state = try engine.gpa.create(Token);
        state.* = .{ .gpa = engine.gpa, .manager = null };
        _ = c.JS_SetOpaque(token, state);
        return .{ .engine = engine, .token = token, .token_class = class };
    }
    pub fn attach(self: *Manager) void {
        const state: *Token = @ptrCast(@alignCast(c.JS_GetOpaque(self.token, self.token_class).?));
        state.manager = self;
    }
    pub fn deinit(self: *Manager) void {
        const state: *Token = @ptrCast(@alignCast(c.JS_GetOpaque(self.token, self.token_class).?));
        state.manager = null;
        for (self.listeners.items) |entry| self.engine.freeValue(entry.function);
        self.listeners.deinit(self.engine.gpa);
        self.owners.deinit(self.engine.gpa);
        self.engine.freeValue(self.token);
    }
    pub fn addOwner(self: *Manager, owner: u64) !void {
        try self.owners.put(self.engine.gpa, owner, {});
    }
    pub fn removeOwner(self: *Manager, owner: u64) void {
        _ = self.owners.remove(owner);
        var index: usize = 0;
        while (index < self.listeners.items.len) {
            if (self.listeners.items[index].owner == owner) self.engine.freeValue(self.listeners.orderedRemove(index).function) else index += 1;
        }
    }
    pub fn add(self: *Manager, owner: u64, function: c.JSValue) !c.JSValue {
        if (!self.owners.contains(owner)) return error.StaleNativeExtensionOwner;
        if (!c.JS_IsFunction(self.engine.context, function)) return error.InvalidTerminalListener;
        if (self.listeners.items.len >= 256) return error.TerminalListenerLimit;
        const existing = for (self.listeners.items) |entry| {
            if (c.JS_IsStrictEqual(self.engine.context, entry.function, function)) break entry.id;
        } else null;
        const id = existing orelse self.next_id;
        if (existing == null) self.next_id += 1;
        var data = [_]c.JSValue{ self.token, c.JS_NewInt64(self.engine.context, self.token_class), c.JS_NewInt64(self.engine.context, @intCast(id)) };
        defer self.engine.freeValue(data[1]);
        defer self.engine.freeValue(data[2]);
        const unsubscribe = try self.engine.checked(c.JS_NewCFunctionData2(self.engine.context, remove, "unsubscribe", 0, 0, data.len, &data));
        errdefer self.engine.freeValue(unsubscribe);
        if (existing != null) return unsubscribe;
        const retained = c.JS_DupValue(self.engine.context, function);
        errdefer self.engine.freeValue(retained);
        try self.listeners.append(self.engine.gpa, .{ .owner = owner, .id = id, .function = retained });
        return unsubscribe;
    }
    fn remove(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
        const engine = engine_mod.Engine.fromContext(context.?);
        var class: i64 = 0;
        var id: i64 = 0;
        if (c.JS_ToInt64(context, &class, data[1]) < 0 or c.JS_ToInt64(context, &id, data[2]) < 0) return engine.throwCaptured();
        const token: *Token = @ptrCast(@alignCast(c.JS_GetOpaque(data[0], @intCast(class)) orelse return c.pi_js_undefined()));
        const self = token.manager orelse return c.pi_js_undefined();
        for (self.listeners.items, 0..) |entry, index| if (entry.id == id) {
            self.engine.freeValue(self.listeners.orderedRemove(index).function);
            break;
        };
        return c.pi_js_undefined();
    }
    pub fn dispatch(self: *Manager, data: []const u8) !Result {
        var current = try self.engine.gpa.dupe(u8, data);
        errdefer self.engine.gpa.free(current);
        // JavaScript Set iteration is live: deleted successors are skipped and
        // listeners appended by a callback participate in this same input.
        var cursor: u64 = 0;
        var calls: usize = 0;
        while (true) {
            const entry = for (self.listeners.items) |live| {
                if (live.id > cursor) break live;
            } else break;
            cursor = entry.id;
            calls += 1;
            if (calls > 4096) return error.TerminalListenerIterationLimit;
            const rooted = c.JS_DupValue(self.engine.context, entry.function);
            defer self.engine.freeValue(rooted);
            var args = [_]c.JSValue{try self.engine.checked(c.JS_NewStringLen(self.engine.context, current.ptr, current.len))};
            defer self.engine.freeValue(args[0]);
            const value = try self.engine.checked(c.JS_Call(self.engine.context, rooted, c.pi_js_undefined(), 1, &args));
            defer self.engine.freeValue(value);
            if (!c.JS_IsObject(value)) continue;
            const consume = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, value, "consume"));
            defer self.engine.freeValue(consume);
            if (c.JS_ToBool(self.engine.context, consume) != 0) return .{ .data = current, .consume = true };
            const transformed = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, value, "data"));
            defer self.engine.freeValue(transformed);
            if (c.JS_IsString(transformed)) {
                const next = try self.engine.toString(transformed);
                self.engine.gpa.free(current);
                current = next;
            }
        }
        return .{ .data = current };
    }
};

test "native terminal listeners replay original live Set iteration consumption GC and retirement" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var manager = try Manager.init(engine);
    manager.attach();
    defer manager.deinit();
    try manager.addOwner(1);
    const values = try engine.eval("globalThis.trace=[];globalThis.dropB=()=>{};globalThis.appendC=()=>{};globalThis.a=data=>{trace.push('a:'+data);dropB();appendC();return {data:data+'A'}};globalThis.b=data=>trace.push('b:'+data);globalThis.c=data=>{trace.push('c:'+data);return {data:data+'C'}};({a,b,c})", "terminal-original-set.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(values);
    const first = try engine.checked(c.JS_GetPropertyStr(engine.context, values, "a"));
    defer engine.freeValue(first);
    const second = try engine.checked(c.JS_GetPropertyStr(engine.context, values, "b"));
    defer engine.freeValue(second);
    const third = try engine.checked(c.JS_GetPropertyStr(engine.context, values, "c"));
    defer engine.freeValue(third);
    const offA = try manager.add(1, first);
    defer engine.freeValue(offA);
    const duplicate = try manager.add(1, first);
    defer engine.freeValue(duplicate);
    const offB = try manager.add(1, second);
    defer engine.freeValue(offB);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    if (c.JS_SetPropertyStr(engine.context, global, "dropB", c.JS_DupValue(engine.context, offB)) < 0) return error.JavaScriptException;
    // Register the successor from inside the first callback using the real
    // owner-rooted UI API through the manager's native callback entrypoint.
    var data = [_]c.JSValue{ manager.token, c.JS_NewInt64(engine.context, manager.token_class), third };
    defer engine.freeValue(data[1]);
    const append = try engine.checked(c.JS_NewCFunctionData2(engine.context, testAppendListener, "appendC", 0, 0, data.len, &data));
    if (c.JS_SetPropertyStr(engine.context, global, "appendC", append) < 0) return error.JavaScriptException;
    c.JS_RunGC(engine.runtime);
    const result = try manager.dispatch("x");
    defer engine.gpa.free(result.data);
    try std.testing.expectEqualStrings("xAC", result.data);
    const trace = try engine.eval("trace", "terminal-original-trace.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(trace);
    const actual = try engine.stringify(trace);
    defer engine.gpa.free(actual);
    var capture = try std.json.parseFromSlice(std.json.Value, engine.gpa, @embedFile("fixtures/terminal-listeners-original-7fb.json"), .{});
    defer capture.deinit();
    const expected = try std.json.Stringify.valueAlloc(engine.gpa, capture.value.object.get("liveIteration").?, .{});
    defer engine.gpa.free(expected);
    try std.testing.expectEqualStrings(expected, actual);
    manager.removeOwner(1);
    const late = try engine.checked(c.JS_Call(engine.context, offA, c.pi_js_undefined(), 0, null));
    engine.freeValue(late);
    const after = try manager.dispatch("!");
    defer engine.gpa.free(after.data);
    try std.testing.expectEqualStrings("!", after.data);
    try std.testing.expectEqual(@as(usize, 0), manager.listeners.items.len);
}
fn testAppendListener(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    var class: i64 = 0;
    if (c.JS_ToInt64(context, &class, data[1]) < 0) return engine.throwCaptured();
    const token: *Token = @ptrCast(@alignCast(c.JS_GetOpaque(data[0], @intCast(class)).?));
    const manager = token.manager orelse return c.pi_js_undefined();
    return manager.add(1, data[2]) catch |err| if (err == error.OutOfMemory) c.JS_ThrowOutOfMemory(context) else c.JS_ThrowTypeError(context, "Listener append failed");
}
fn listenerOwnershipCase(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    var manager = try Manager.init(engine);
    manager.attach();
    defer manager.deinit();
    try manager.addOwner(1);
    const listener = try engine.eval("data=>({data:data+'Ω'})", "listener-owned.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(listener);
    const off = try manager.add(1, listener);
    defer engine.freeValue(off);
    const result = try manager.dispatch("x");
    defer gpa.free(result.data);
    manager.removeOwner(1);
    c.JS_RunGC(engine.runtime);
    const late = try engine.checked(c.JS_Call(engine.context, off, c.pi_js_undefined(), 0, null));
    engine.freeValue(late);
}
test "terminal listener roots and dispatch release every host allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, listenerOwnershipCase, .{});
}
