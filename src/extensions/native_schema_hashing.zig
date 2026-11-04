//! TypeBox 1.3.27 value hashing used by uniqueItems. This is intentionally
//! separate from deep equality: signed zero, UTF-8 replacement, and wrapped
//! BigInts have the original distinct/equivalent hash behavior.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
pub fn hash(engine: *Engine, value: c.JSValue) !u64 {
    var arena = std.heap.ArenaAllocator.init(engine.gpa);
    defer arena.deinit();
    var context: Context = .{ .engine = engine, .a = arena.allocator() };
    engine.native_typebox_hash_accumulator = 14695981039346656037;
    try context.visit(value);
    return engine.native_typebox_hash_accumulator;
}
pub fn createFunction(engine: *Engine) !c.JSValue {
    return engine.checked(c.JS_NewCFunction(engine.context, callback, "Hash", 1));
}
fn callback(context: ?*c.JSContext, pending_arg1: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const pending_engine = @import("engine.zig").Engine.fromContext(context.?);
    var pending_frame = @import("native_pending_owner.zig").Frame.init(pending_engine);
    pending_frame.enter() catch return pending_frame.finishCallback(c.pi_js_exception());
    return pending_frame.finishCallback(callbackPendingBody(context, pending_arg1, argc, argv));
}
fn callbackPendingBody(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return hashValue(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| {
        if (err == error.OutOfMemory) return engine.throwNativeOutOfMemoryFatal();
        return engine.throwCaptured();
    };
}
fn hashValue(engine: *Engine, value: c.JSValue) !c.JSValue {
    const code = try hash(engine, value);
    var buffer: [16]u8 = undefined;
    const encoded = try std.fmt.bufPrint(&buffer, "{x:0>16}", .{code});
    return engine.checked(c.JS_NewStringLen(engine.context, encoded.ptr, encoded.len));
}
const Context = struct {
    engine: *Engine,
    a: std.mem.Allocator,
    active: std.ArrayList(c.JSValue) = .empty,
    fn byte(self: *Context, value: u8) void {
        self.engine.native_typebox_hash_accumulator = (self.engine.native_typebox_hash_accumulator ^ value) *% 1099511628211;
    }
    fn bytes(self: *Context, values: []const u8) void {
        for (values) |value| self.byte(value);
    }
    fn text(self: *Context, value: c.JSValue) ![]const u8 {
        const output = try self.engine.toString(value);
        defer self.engine.gpa.free(output);
        return self.a.dupe(u8, output);
    }
    fn property(self: *Context, value: c.JSValue, key: []const u8) !c.JSValue {
        const atom = c.JS_NewAtomLen(self.engine.context, key.ptr, key.len);
        defer c.JS_FreeAtom(self.engine.context, atom);
        return self.engine.checked(native_guest_0: { try self.engine.checkNativeEntry(); break :native_guest_0 c.JS_GetProperty(self.engine.context, value, atom); });
    }
    fn instance(self: *Context, value: c.JSValue, name: [:0]const u8) !bool {
        const global = c.JS_GetGlobalObject(self.engine.context);
        defer self.engine.releaseNativeValue(global);
        const constructor = try vm.get(self.engine, global, name);
        defer self.engine.releaseNativeValue(constructor);
        const result = c.JS_IsInstanceOf(self.engine.context, value, constructor);
        if (result < 0) {
            _ = try self.engine.checked(c.pi_js_exception());
            unreachable;
        }
        return result != 0;
    }
    fn string(self: *Context, value: c.JSValue) !void {
        self.byte(10);
        const data = try self.text(value);
        var iterator = (try std.unicode.Wtf8View.init(data)).iterator();
        while (iterator.nextCodepoint()) |point| {
            var encoded: [4]u8 = undefined;
            const scalar = if (point >= 0xd800 and point <= 0xdfff) 0xfffd else point;
            const length = try std.unicode.utf8Encode(scalar, &encoded);
            self.bytes(encoded[0..length]);
        }
    }
    fn number(self: *Context, value: c.JSValue) !void {
        self.byte(7);
        var scalar: f64 = 0;
        if (native_guest_0: { try self.engine.checkNativeEntry(); break :native_guest_0 c.JS_ToFloat64(self.engine.context, &scalar, value); } < 0) return error.JavaScriptException;
        var encoded: [8]u8 = undefined;
        std.mem.writeInt(u64, &encoded, @bitCast(scalar), .little);
        self.bytes(&encoded);
    }
    fn objectKeys(self: *Context, value: c.JSValue) !c.JSValue {
        const global = c.JS_GetGlobalObject(self.engine.context);
        defer self.engine.releaseNativeValue(global);
        const object = try vm.get(self.engine, global, "Object");
        defer self.engine.releaseNativeValue(object);
        const stop = try vm.get(self.engine, object, "prototype");
        defer self.engine.releaseNativeValue(stop);
        var current = c.JS_DupValue(self.engine.context, value);
        defer self.engine.releaseNativeValue(current);
        var seen: std.StringHashMapUnmanaged(void) = .empty;
        const result = try vm.array(self.engine);
        errdefer self.engine.releaseNativeValue(result);
        var count: u32 = 0;
        while (!c.JS_IsNull(current) and !c.JS_IsUndefined(current) and !c.JS_IsStrictEqual(self.engine.context, current, stop)) {
            var keys: [*c]c.JSPropertyEnum = null;
            var length: u32 = 0;
            if (native_guest_0: { try self.engine.checkNativeEntry(); break :native_guest_0 c.JS_GetOwnPropertyNames(self.engine.context, &keys, &length, current, c.JS_GPN_STRING_MASK); } < 0) return error.JavaScriptException;
            defer c.JS_FreePropertyEnum(self.engine.context, keys, length);
            for (0..length) |index| {
                const key = try self.engine.checked(c.JS_AtomToString(self.engine.context, keys[index].atom));
                defer self.engine.releaseNativeValue(key);
                const label = try self.text(key);
                if (std.mem.eql(u8, label, "constructor") or seen.contains(label)) continue;
                (seen.put(self.a, label, {}) catch |native_error| { if (native_error == error.OutOfMemory) _ = self.engine.throwNativeOutOfMemoryFatal(); return native_error; });
                if (c.JS_SetPropertyUint32(self.engine.context, result, count, c.JS_DupValue(self.engine.context, key)) < 0) return error.JavaScriptException;
                count += 1;
            }
            const next = try vm.invoke(self.engine, object, "getPrototypeOf", &.{current});
            self.engine.releaseNativeValue(current);
            current = next;
        }
        const sorted = try vm.invoke(self.engine, result, "sort", &.{});
        self.engine.releaseNativeValue(sorted);
        return result;
    }
    fn isConstructor(self: *Context, value: c.JSValue) !bool {
        if (!c.JS_IsFunction(self.engine.context, value)) return false;
        const global = c.JS_GetGlobalObject(self.engine.context);
        defer self.engine.releaseNativeValue(global);
        const function = try vm.get(self.engine, global, "Function");
        defer self.engine.releaseNativeValue(function);
        const prototype = try vm.get(self.engine, function, "prototype");
        defer self.engine.releaseNativeValue(prototype);
        const tostring = try vm.get(self.engine, prototype, "toString");
        defer self.engine.releaseNativeValue(tostring);
        var args = [_]c.JSValue{value};
        const rendered = try vm.invoke(self.engine, tostring, "call", &args);
        defer self.engine.releaseNativeValue(rendered);
        const data = try self.text(rendered);
        if (std.mem.indexOf(u8, data, "[native code]") != null) return true;
        return std.mem.startsWith(u8, data, "class") and data.len > 5 and std.ascii.isWhitespace(data[5]);
    }
    fn visit(self: *Context, value: c.JSValue) anyerror!void {
        const tracked = c.JS_IsObject(value) or c.JS_IsSymbol(value);
        if (tracked) {
            for (self.active.items) |entry| if (c.JS_IsStrictEqual(self.engine.context, entry, value)) {
                _ = try self.engine.checked(c.JS_ThrowRangeError(self.engine.context, "Maximum call stack size exceeded"));
                unreachable;
            };
            (self.active.append(self.a, value) catch |native_error| { if (native_error == error.OutOfMemory) _ = self.engine.throwNativeOutOfMemoryFatal(); return native_error; });
        }
        defer if (tracked) {
            _ = self.active.pop();
        };
        const global = c.JS_GetGlobalObject(self.engine.context);
        defer self.engine.releaseNativeValue(global);
        const array_buffer = try vm.get(self.engine, global, "ArrayBuffer");
        defer self.engine.releaseNativeValue(array_buffer);
        const is_view = try vm.invoke(self.engine, array_buffer, "isView", &.{value});
        defer self.engine.releaseNativeValue(is_view);
        if (c.JS_ToBool(self.engine.context, is_view) != 0) {
            self.byte(12);
            const buffer = try vm.get(self.engine, value, "buffer");
            defer self.engine.releaseNativeValue(buffer);
            const uint8 = try vm.get(self.engine, global, "Uint8Array");
            defer self.engine.releaseNativeValue(uint8);
            var args = [_]c.JSValue{buffer};
            const view = try self.engine.checked(native_guest_5: { try self.engine.checkNativeEntry(); break :native_guest_5 c.JS_CallConstructor(self.engine.context, uint8, 1, &args); });
            defer self.engine.releaseNativeValue(view);
            for (0..try vm.length(self.engine, view)) |index| {
                const item = try self.engine.checked(native_guest_4: { try self.engine.checkNativeEntry(); break :native_guest_4 c.JS_GetPropertyUint32(self.engine.context, view, @intCast(index)); });
                defer self.engine.releaseNativeValue(item);
                var scalar: u32 = 0;
                if (native_guest_3: { try self.engine.checkNativeEntry(); break :native_guest_3 c.JS_ToUint32(self.engine.context, &scalar, item); } < 0) return error.JavaScriptException;
                self.byte(@intCast(scalar));
            }
        } else if (try self.instance(value, "Date")) {
            self.byte(3);
            const scalar = try vm.invoke(self.engine, value, "getTime", &.{});
            defer self.engine.releaseNativeValue(scalar);
            try self.visit(scalar);
        } else if (try self.instance(value, "RegExp")) {
            self.byte(9);
            const rendered = try vm.invoke(self.engine, value, "toString", &.{});
            defer self.engine.releaseNativeValue(rendered);
            try self.string(rendered);
        } else if (try self.instance(value, "Boolean")) {
            const primitive = try vm.invoke(self.engine, value, "valueOf", &.{});
            defer self.engine.releaseNativeValue(primitive);
            self.byte(2);
            self.byte(@intFromBool(c.JS_ToBool(self.engine.context, primitive) != 0));
        } else if (try self.instance(value, "String")) {
            const primitive = try vm.invoke(self.engine, value, "valueOf", &.{});
            defer self.engine.releaseNativeValue(primitive);
            try self.string(primitive);
        } else if (try self.instance(value, "Number")) {
            const primitive = try vm.invoke(self.engine, value, "valueOf", &.{});
            defer self.engine.releaseNativeValue(primitive);
            try self.number(primitive);
        } else if (c.JS_IsNumber(value)) {
            try self.number(value);
        } else if (c.JS_IsArray(value)) {
            self.byte(0);
            for (0..try vm.length(self.engine, value)) |index| {
                const item = try self.engine.checked(native_guest_2: { try self.engine.checkNativeEntry(); break :native_guest_2 c.JS_GetPropertyUint32(self.engine.context, value, @intCast(index)); });
                defer self.engine.releaseNativeValue(item);
                try self.visit(item);
            }
        } else if (c.JS_IsBool(value)) {
            self.byte(2);
            self.byte(@intFromBool(c.JS_ToBool(self.engine.context, value) != 0));
        } else if (c.JS_IsBigInt(value)) {
            self.byte(1);
            var scalar: i64 = 0;
            if (native_guest_1: { try self.engine.checkNativeEntry(); break :native_guest_1 c.JS_ToBigInt64(self.engine.context, &scalar, value); } < 0) return error.JavaScriptException;
            var encoded: [8]u8 = undefined;
            std.mem.writeInt(u64, &encoded, @bitCast(scalar), .big);
            self.bytes(&encoded);
        } else if (try self.isConstructor(value)) {
            self.byte(4);
            const rendered = try vm.invoke(self.engine, value, "toString", &.{});
            defer self.engine.releaseNativeValue(rendered);
            try self.visit(rendered);
        } else if (c.JS_IsNull(value)) {
            self.byte(6);
        } else if (c.JS_IsObject(value) and !c.JS_IsFunction(self.engine.context, value)) {
            self.byte(8);
            const keys = try self.objectKeys(value);
            defer self.engine.releaseNativeValue(keys);
            for (0..try vm.length(self.engine, keys)) |index| {
                const key = try self.engine.checked(native_guest_0: { try self.engine.checkNativeEntry(); break :native_guest_0 c.JS_GetPropertyUint32(self.engine.context, keys, @intCast(index)); });
                defer self.engine.releaseNativeValue(key);
                try self.visit(key);
                const label = try self.text(key);
                const child = try self.property(value, label);
                defer self.engine.releaseNativeValue(child);
                try self.visit(child);
            }
        } else if (c.JS_IsString(value)) {
            try self.string(value);
        } else if (c.JS_IsSymbol(value)) {
            self.byte(11);
            const rendered = try vm.invoke(self.engine, value, "toString", &.{});
            defer self.engine.releaseNativeValue(rendered);
            try self.visit(rendered);
        } else if (c.JS_IsUndefined(value)) {
            self.byte(13);
        } else if (c.JS_IsFunction(self.engine.context, value)) {
            self.byte(5);
            const rendered = try vm.invoke(self.engine, value, "toString", &.{});
            defer self.engine.releaseNativeValue(rendered);
            try self.visit(rendered);
        } else return error.UnsupportedSchemaHashValue;
    }
};

test "native durable VM value hashes match pinned typed markers IEEE bytes Unicode replacement sparse arrays BigInt wrapping and sorted keys" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try vm.put(engine, global, "nativeHash", try createFunction(engine));
    errdefer std.debug.print("Schema hash VM failure: {s}\n", .{engine.last_error orelse "none"});
    const output = try engine.evalModule(
        \\const hashes=[undefined,null,true,false,0,-0,NaN,Infinity,-Infinity,0n,1n,-1n,18446744073709551616n,'','é','e\u0301','\ud800','\udfff',[],Array(2),[undefined],{a:undefined},{b:undefined},{b:2,a:1},{a:1,b:2},new Date(123),/a+/gi,new Uint8Array([1,2])].map((value,index)=>({index,hash:nativeHash(value)}));globalThis.result=JSON.stringify(hashes);
    , "native-schema-hash-source-corpus");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-schema-hash-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings(@embedFile("../durable/fixtures/schema-value-hashes-1ced.json"), text);
}
