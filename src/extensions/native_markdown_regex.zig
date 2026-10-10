//! Native C regexp programs for the pinned Marked18 grammar data.
const std = @import("std");
const Engine = @import("engine.zig").Engine;
const c = @import("engine.zig").c;
pub const Range = struct { start: usize, end: usize };
pub const Match = struct {
    gpa: std.mem.Allocator,
    ranges: []?Range,
    pub fn deinit(self: *Match) void {
        self.gpa.free(self.ranges);
        self.* = undefined;
    }
    pub fn optional(self: Match, source: []const u16, index: usize) ?[]const u16 {
        if (index >= self.ranges.len) return null;
        const range = self.ranges[index] orelse return null;
        return source[range.start..range.end];
    }
    pub fn group(self: Match, source: []const u16, index: usize) []const u16 {
        return self.optional(source, index) orelse &.{};
    }
};
pub const Program = struct { bytes: [*]u8, length: usize };
pub const Scope = enum { block, inline_rule, other };
pub const Grammar = struct {
    engine: *Engine,
    fixture: std.json.Parsed(std.json.Value),
    programs: std.StringHashMapUnmanaged(Program) = .empty,
    pub fn init(engine: *Engine) !Grammar {
        return .{ .engine = engine, .fixture = try std.json.parseFromSlice(std.json.Value, engine.gpa, @embedFile("fixtures/marked-rules-original-18.json"), .{}) };
    }
    pub fn deinit(self: *Grammar) void {
        var iterator = self.programs.iterator();
        while (iterator.next()) |entry| {
            c.js_free(self.engine.context, entry.value_ptr.bytes);
            self.engine.gpa.free(entry.key_ptr.*);
        }
        self.programs.deinit(self.engine.gpa);
        self.fixture.deinit();
        self.* = undefined;
    }
    pub fn rule(self: *Grammar, scope: Scope, name: []const u8) std.json.Value {
        return switch (scope) {
            .other => self.fixture.value.object.get("other").?.object.get(name).?,
            .block => self.fixture.value.object.get("rules").?.object.get("block").?.object.get("gfm").?.object.get(name).?,
            .inline_rule => self.fixture.value.object.get("rules").?.object.get("inline").?.object.get("gfm").?.object.get(name).?,
        };
    }
    pub fn matchRule(self: *Grammar, scope: Scope, name: []const u8, source: []const u16) !?Match {
        const value = self.rule(scope, name);
        const pattern = value.object.get("source") orelse return null;
        return self.match(pattern.string, value.object.get("flags").?.string, source, 0);
    }
    pub fn compile(self: *Grammar, pattern: []const u8, flags: []const u8) !Program {
        const key = try std.fmt.allocPrint(self.engine.gpa, "{s}\x00{s}", .{ flags, pattern });
        var transferred = false;
        defer if (!transferred) self.engine.gpa.free(key);
        if (self.programs.get(key)) |program| return program;
        var bits: c_int = 0;
        for (flags) |flag| bits |= switch (flag) {
            'g' => c.LRE_FLAG_GLOBAL,
            'i' => c.LRE_FLAG_IGNORECASE,
            'm' => c.LRE_FLAG_MULTILINE,
            's' => c.LRE_FLAG_DOTALL,
            'u' => c.LRE_FLAG_UNICODE,
            'y' => c.LRE_FLAG_STICKY,
            'v' => c.LRE_FLAG_UNICODE_SETS,
            'd' => c.LRE_FLAG_INDICES,
            else => return error.InvalidNativeMarkdownRegexFlags,
        };
        var length: c_int = 0;
        var diagnostic: [256]u8 = @splat(0);
        // QuickJS's parser checks the sentinel after consuming buf_len.
        const terminated = try self.engine.gpa.dupeZ(u8, pattern);
        defer self.engine.gpa.free(terminated);
        const bytes = c.lre_compile(&length, &diagnostic, diagnostic.len, terminated.ptr, pattern.len, bits, self.engine.context) orelse {
            const message = std.mem.sliceTo(&diagnostic, 0);
            if (std.mem.indexOf(u8, message, "memory") != null) return error.OutOfMemory;
            std.debug.print("Native Marked grammar compile: {s}\n", .{message});
            return error.InvalidNativeMarkdownRegex;
        };
        errdefer c.js_free(self.engine.context, bytes);
        const program: Program = .{ .bytes = bytes, .length = @intCast(length) };
        try self.programs.put(self.engine.gpa, key, program);
        transferred = true;
        return program;
    }
    pub fn match(self: *Grammar, pattern: []const u8, flags: []const u8, source: []const u16, start: usize) !?Match {
        const program = try self.compile(pattern, flags);
        const count: usize = @intCast(c.lre_get_capture_count(program.bytes));
        const captures = try self.engine.gpa.alloc([*c]u8, count * 2);
        defer self.engine.gpa.free(captures);
        @memset(captures, null);
        if (source.len > std.math.maxInt(c_int) or start > source.len) return error.NativeMarkdownSourceLimit;
        const matched = c.lre_exec(captures.ptr, program.bytes, @ptrCast(source.ptr), @intCast(start), @intCast(source.len), 1, self.engine.context);
        switch (matched) {
            0 => return null,
            1 => {},
            c.LRE_RET_MEMORY_ERROR => return error.OutOfMemory,
            c.LRE_RET_TIMEOUT => {
                _ = try self.engine.checked(c.JS_ThrowInternalError(self.engine.context, "interrupted"));
                unreachable;
            },
            else => return error.NativeMarkdownRegexFailure,
        }
        const ranges = try self.engine.gpa.alloc(?Range, count);
        errdefer self.engine.gpa.free(ranges);
        for (ranges, 0..) |*range, index| {
            const first = captures[index * 2];
            const last = captures[index * 2 + 1];
            range.* = if (first == null or last == null) null else .{
                .start = (@intFromPtr(first) - @intFromPtr(source.ptr)) / 2,
                .end = (@intFromPtr(last) - @intFromPtr(source.ptr)) / 2,
            };
        }
        return .{ .gpa = self.engine.gpa, .ranges = ranges };
    }
};
