//! User bash output decoding and ANSI suffix admission. The pinned direct-C
//! regexp and decoder execute language primitives; streaming policy is Zig.
const std = @import("std");
const engine_mod = @import("../extensions/engine.zig");
const c = engine_mod.c;
const decoder = @import("../extensions/text_decoder.zig");
const unfinished = "(?:\\u001B\\](?:[^\\u0007\\u009C\\u001B]|\\u001B(?!\\\\))*|[\\u001B\\u009B][[\\]()#;?]*(?:\\d{1,4}(?:[;:]\\d{0,4})*)?)$";
const complete = "(?:\\u001B\\][\\s\\S]*?(?:\\u0007|\\u001B\\u005C|\\u009C))|[\\u001B\\u009B][[\\]()#;?]*(?:\\d{1,4}(?:[;:]\\d{0,4})*)?[\\dA-PR-TZcf-nq-uy=><~]";
pub const Stream = struct {
    engine: *engine_mod.Engine,
    text_decoder: c.JSValue,
    suffix: c.JSValue,
    ansi: c.JSValue,
    pending: c.JSValue,
    pub fn init(gpa: std.mem.Allocator) !Stream {
        const engine = try engine_mod.Engine.init(gpa, .{ .memory_limit = 8 * 1024 * 1024, .interrupt_budget = 100_000 });
        errdefer engine.deinit();
        try decoder.install(engine);
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        const constructor = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "TextDecoder"));
        defer engine.freeValue(constructor);
        const text_decoder = try engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null));
        errdefer engine.freeValue(text_decoder);
        const suffix = try regexp(engine, global, unfinished, "");
        errdefer engine.freeValue(suffix);
        const ansi = try regexp(engine, global, complete, "g");
        errdefer engine.freeValue(ansi);
        return .{ .engine = engine, .text_decoder = text_decoder, .suffix = suffix, .ansi = ansi, .pending = try engine.checked(c.JS_NewString(engine.context, "")) };
    }
    pub fn deinit(self: *Stream) void {
        for ([_]c.JSValue{ self.text_decoder, self.suffix, self.ansi, self.pending }) |value| self.engine.freeValue(value);
        self.engine.deinit();
    }
    fn regexp(engine: *engine_mod.Engine, global: c.JSValue, pattern: []const u8, flags: []const u8) !c.JSValue {
        const constructor = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "RegExp"));
        defer engine.freeValue(constructor);
        var args = [_]c.JSValue{ try engine.checked(c.JS_NewStringLen(engine.context, pattern.ptr, pattern.len)), try engine.checked(c.JS_NewStringLen(engine.context, flags.ptr, flags.len)) };
        defer for (args) |value| engine.freeValue(value);
        return engine.checked(c.JS_CallConstructor(engine.context, constructor, args.len, &args));
    }
    fn invoke(self: *Stream, receiver: c.JSValue, name: [:0]const u8, args: []c.JSValue) !c.JSValue {
        const callback = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, receiver, name));
        defer self.engine.freeValue(callback);
        return self.engine.checked(c.JS_Call(self.engine.context, callback, receiver, @intCast(args.len), args.ptr));
    }
    pub fn feed(self: *Stream, bytes: []const u8) ![]u8 {
        return self.decode(bytes, false);
    }
    pub fn finish(self: *Stream) ![]u8 {
        return self.decode(&.{}, true);
    }
    fn decode(self: *Stream, bytes: []const u8, final: bool) ![]u8 {
        const engine = self.engine;
        // The process pipe callbacks serialize this runtime under one mutex,
        // but stdout/stderr/final flush may run on different native threads.
        c.JS_UpdateStackTop(engine.runtime);
        const buffer = try engine.checked(c.JS_NewArrayBufferCopy(engine.context, bytes.ptr, bytes.len));
        defer engine.freeValue(buffer);
        const options = try engine.checked(c.JS_NewObject(engine.context));
        defer engine.freeValue(options);
        if (c.JS_SetPropertyStr(engine.context, options, "stream", c.pi_js_bool(engine.context, @intFromBool(!final))) < 0) return error.JavaScriptException;
        var decode_args = [_]c.JSValue{ buffer, options };
        const text = try self.invoke(self.text_decoder, "decode", &decode_args);
        defer engine.freeValue(text);
        const previous = try engine.toString(self.pending);
        defer engine.gpa.free(previous);
        const current = try engine.toString(text);
        defer engine.gpa.free(current);
        const joined = try std.mem.concat(engine.gpa, u8, &.{ previous, current });
        defer engine.gpa.free(joined);
        const whole = try engine.checked(c.JS_NewStringLen(engine.context, joined.ptr, joined.len));
        defer engine.freeValue(whole);
        var admitted = c.JS_DupValue(engine.context, whole);
        defer engine.freeValue(admitted);
        const empty = try engine.checked(c.JS_NewString(engine.context, ""));
        defer engine.freeValue(empty);
        engine.freeValue(self.pending);
        self.pending = c.JS_DupValue(engine.context, empty);
        if (!final) {
            var window_args = [_]c.JSValue{c.JS_NewInt32(engine.context, -256)};
            const window = try self.invoke(whole, "slice", &window_args);
            defer engine.freeValue(window);
            var match_args = [_]c.JSValue{window};
            const match = try self.invoke(self.suffix, "exec", &match_args);
            defer engine.freeValue(match);
            if (!c.JS_IsNull(match)) {
                const window_length_value = try engine.checked(c.JS_GetPropertyStr(engine.context, window, "length"));
                defer engine.freeValue(window_length_value);
                const whole_length_value = try engine.checked(c.JS_GetPropertyStr(engine.context, whole, "length"));
                defer engine.freeValue(whole_length_value);
                const index_value = try engine.checked(c.JS_GetPropertyStr(engine.context, match, "index"));
                defer engine.freeValue(index_value);
                var window_length: i32 = 0;
                var whole_length: i32 = 0;
                var index: i32 = 0;
                if (c.JS_ToInt32(engine.context, &window_length, window_length_value) < 0 or c.JS_ToInt32(engine.context, &whole_length, whole_length_value) < 0 or c.JS_ToInt32(engine.context, &index, index_value) < 0) return error.JavaScriptException;
                var head_args = [_]c.JSValue{ c.JS_NewInt32(engine.context, 0), c.JS_NewInt32(engine.context, whole_length - window_length + index) };
                engine.freeValue(admitted);
                admitted = try self.invoke(whole, "slice", &head_args);
                var tail_args = [_]c.JSValue{head_args[1]};
                const pending = try self.invoke(whole, "slice", &tail_args);
                engine.freeValue(self.pending);
                self.pending = pending;
            }
        }
        var replace_args = [_]c.JSValue{ self.ansi, empty };
        const stripped = try self.invoke(admitted, "replace", &replace_args);
        defer engine.freeValue(stripped);
        const raw = try engine.toString(stripped);
        defer engine.gpa.free(raw);
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(engine.gpa);
        var iterator = (try std.unicode.Wtf8View.init(raw)).iterator();
        var encoded: [4]u8 = undefined;
        while (iterator.nextCodepoint()) |point| {
            if (point <= 8 or point == 11 or point == 12 or (point >= 14 and point <= 31) or (point >= 0xfff9 and point <= 0xfffb) or point == '\r') continue;
            const count = try std.unicode.wtf8Encode(point, &encoded);
            try out.appendSlice(engine.gpa, encoded[0..count]);
        }
        return out.toOwnedSlice(engine.gpa);
    }
};

test "user bash streamed ANSI sequences spanning UTF8 and escape boundaries retain only actual text" {
    const gpa = std.testing.allocator;
    var stream = try Stream.init(gpa);
    defer stream.deinit();
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(gpa);
    for ([_][]const u8{ "hello\x1b[3", "1mred\x1b[0", "m\x1b]0;title\x1b", "\\world\r\n\xf0\x9f", "\x8c\x8d" }) |chunk| {
        const admitted = try stream.feed(chunk);
        defer gpa.free(admitted);
        try result.appendSlice(gpa, admitted);
    }
    const tail = try stream.finish();
    defer gpa.free(tail);
    try result.appendSlice(gpa, tail);
    try std.testing.expectEqualStrings("helloredworld\n🌍", result.items);
}

test "user bash output matches actual f109 upstream chunk and end-of-stream captures" {
    const gpa = std.testing.allocator;
    const fixture = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("assets/bash-ansi-f109.json"), .{});
    defer fixture.deinit();
    for (fixture.value.object.get("cases").?.array.items) |case| {
        var stream = try Stream.init(gpa);
        defer stream.deinit();
        var joined: std.ArrayList(u8) = .empty;
        defer joined.deinit(gpa);
        var index: usize = 0;
        const expected = case.object.get("output").?.array.items;
        for (case.object.get("chunks").?.array.items) |chunk| {
            const text = try stream.feed(chunk.string);
            defer gpa.free(text);
            if (text.len != 0) {
                try std.testing.expect(index < expected.len);
                try std.testing.expectEqualStrings(expected[index].string, text);
                index += 1;
                try joined.appendSlice(gpa, text);
            }
        }
        const tail = try stream.finish();
        defer gpa.free(tail);
        if (tail.len != 0) {
            try std.testing.expect(index < expected.len);
            try std.testing.expectEqualStrings(expected[index].string, tail);
            index += 1;
            try joined.appendSlice(gpa, tail);
        }
        try std.testing.expectEqual(expected.len, index);
        try std.testing.expectEqualStrings(case.object.get("joined").?.string, joined.items);
    }
}

test "user bash ANSI decoder allocation failures release native objects and retained suffix" {
    const Check = struct {
        fn run(gpa: std.mem.Allocator) !void {
            var probe = std.testing.FailingAllocator.init(std.testing.allocator, .{});
            exercise(gpa) catch |cause| {
                if (cause == error.JavaScriptException and gpa.vtable == probe.allocator().vtable) {
                    const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                    if (failing.has_induced_failure) return error.OutOfMemory;
                }
                return cause;
            };
        }
        fn exercise(gpa: std.mem.Allocator) !void {
            var stream = try Stream.init(gpa);
            defer stream.deinit();
            const first = try stream.feed("text\x1b[3");
            defer gpa.free(first);
            const second = try stream.feed("1mred\x1b[0m");
            defer gpa.free(second);
            const tail = try stream.finish();
            defer gpa.free(tail);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Check.run, .{});
}
