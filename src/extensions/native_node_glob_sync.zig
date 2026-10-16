//! Genuine synchronous filesystem traversal for PackageManager's simple globs.
//! Explicitly unselected. Unsupported Node options/grammar reject; missing paths
//! and unreadable directories alone produce the original empty traversal steps.
const std = @import("std");
const builtin = @import("builtin");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const pattern = @import("native_node_glob_pattern.zig");
const core = pattern.core;
const data = @import("native_sdk_package_data.zig");
const functions = @import("native_node_function.zig");
const path_codec = @import("native_node_glob_path_codec.zig");
const Entry = struct { name: []const u8, kind: std.Io.File.Kind };
const State = struct { indexes: []bool, symlinks: []bool, order: std.ArrayList(usize) = .empty };
const Work = struct { path: []const u8, state: State };
const Stat = struct { kind: std.Io.File.Kind };

/// The actual module owner supplies the captured node:path bindings once.
/// No filesystem namespace is replaced and no glob is executed at assembly.
pub fn create(engine: *v.em.Engine, actual_paths: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const imports = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    inline for (.{ "join", "resolve" }) |name| {
        const function = try s.get(actual_paths, name);
        if (!c.JS_IsFunction(engine.context, function)) return error.RequiredActualGlobPathImport;
        try data.put(engine, imports, name, function);
    }
    return functions.create(engine, "globSync", 2, globSync, &.{imports});
}

pub fn install(engine: *v.em.Engine, actual_filesystem: c.JSValue, actual_paths: c.JSValue) !void {
    const function = try create(engine, actual_paths);
    defer engine.freeValue(function);
    try data.put(engine, actual_filesystem, "globSync", function);
}

fn text(engine: *v.em.Engine, bytes: []const u8) !c.JSValue {
    var arena = std.heap.ArenaAllocator.init(engine.gpa);
    defer arena.deinit();
    const units = try core.decodeUnits(arena.allocator(), bytes);
    return engine.checked(c.JS_NewStringUTF16(engine.context, units.values.ptr, units.values.len));
}
fn bytes(engine: *v.em.Engine, value: c.JSValue) ![]u8 {
    return path_codec.fromValue(engine, value);
}

const Context = struct {
    engine: *v.em.Engine,
    io: std.Io,
    a: std.mem.Allocator,
    imports: c.JSValue,
    root: []const u8,
    parts: core.Pattern,
    regexes: []const c.JSValue,
    stats: std.StringHashMapUnmanaged(?Stat) = .empty,
    reads: std.StringHashMapUnmanaged([]const Entry) = .empty,
    seen: std.StringHashMapUnmanaged([]bool) = .empty,
    results_seen: std.StringHashMapUnmanaged(void) = .empty,
    results: std.ArrayList([]const u8) = .empty,
    queue: std.ArrayList(Work) = .empty,
    pending: std.ArrayList(Work) = .empty,
    steps: usize = 0,
    entries: usize = 0,

    fn tick(self: *Context) !void {
        self.steps += 1;
        if (self.steps > 1_000_000) return error.NodeGlobTraversalResourceLimit;
        const canceled = self.engine.cancelled.load(.acquire);
        if (self.steps % 256 == 0) self.engine.interrupts +|= 1;
        if (canceled or (self.steps % 256 == 0 and self.engine.interrupts > self.engine.options.interrupt_budget)) {
            _ = try self.engine.checked(c.JS_ThrowInternalError(self.engine.context, "interrupted"));
            unreachable;
        }
    }
    fn path(self: *Context, name: [*:0]const u8, first: []const u8, second: []const u8) ![]const u8 {
        var s: Scope = .{ .engine = self.engine };
        defer s.deinit();
        const function = try s.get(self.imports, name);
        const result = try s.call(function, c.pi_js_undefined(), &.{ try s.own(try text(self.engine, first)), try s.own(try text(self.engine, second)) });
        const value = try bytes(self.engine, result);
        defer self.engine.gpa.free(value);
        return self.a.dupe(u8, value);
    }
    fn stat(self: *Context, fullpath: []const u8) !?Stat {
        if (std.mem.indexOfScalar(u8, fullpath, 0) != null) return null;
        // Node's cache treats null misses as absent on the next stat call.
        if (self.stats.get(fullpath)) |cached| if (cached) |value| return value;
        const info = std.Io.Dir.cwd().statFile(self.io, fullpath, .{ .follow_symlinks = false }) catch |err| {
            if (err == error.OutOfMemory or err == error.Canceled) return err;
            try self.stats.put(self.a, fullpath, null);
            return null;
        };
        const value: Stat = .{ .kind = info.kind };
        try self.stats.put(self.a, fullpath, value);
        return value;
    }
    fn read(self: *Context, fullpath: []const u8) ![]const Entry {
        if (self.reads.get(fullpath)) |cached| return cached;
        var dir = std.Io.Dir.cwd().openDir(self.io, fullpath, .{ .iterate = true }) catch |err| {
            if (err == error.OutOfMemory or err == error.Canceled) return err;
            try self.reads.put(self.a, fullpath, &.{});
            return &.{};
        };
        defer dir.close(self.io);
        var out: std.ArrayList(Entry) = .empty;
        var iterator = dir.iterate();
        while (iterator.next(self.io) catch |err| {
            if (err == error.OutOfMemory or err == error.Canceled) return err;
            try self.reads.put(self.a, fullpath, &.{});
            return &.{};
        }) |entry| {
            // This admission error is outside filesystem-error fallbacks.
            // Never reinterpret an unsupported native name as an empty read.
            try path_codec.validateNativeName(entry.name);
            self.entries += 1;
            if (self.entries > 100_000) return error.NodeGlobDirectoryResourceLimit;
            const kind = if (entry.kind == .unknown) blk: {
                const info = dir.statFile(self.io, entry.name, .{ .follow_symlinks = false }) catch |err| {
                    if (err == error.OutOfMemory or err == error.Canceled) return err;
                    try self.reads.put(self.a, fullpath, &.{});
                    return &.{};
                };
                break :blk info.kind;
            } else entry.kind;
            try out.append(self.a, .{ .name = try self.a.dupe(u8, entry.name), .kind = kind });
        }
        if (builtin.os.tag != .windows) std.mem.sort(Entry, out.items, {}, struct {
            fn less(_: void, left: Entry, right: Entry) bool { return std.mem.lessThan(u8, left.name, right.name); }
        }.less);
        try self.reads.put(self.a, fullpath, out.items);
        return out.items;
    }
    fn state(self: *Context) !State {
        // The original sets can contain the position just past the pattern.
        // Keep these states: they affect cache keys and symlink admission.
        const indexes = try self.a.alloc(bool, self.parts.len + 2);
        const symlinks = try self.a.alloc(bool, self.parts.len + 2);
        @memset(indexes, false);
        @memset(symlinks, false);
        return .{ .indexes = indexes, .symlinks = symlinks };
    }
    fn one(self: *Context, index: usize) !State {
        var value = try self.state();
        try self.include(&value, index);
        return value;
    }
    fn include(self: *Context, value: *State, index: usize) !void {
        if (index >= value.indexes.len) return error.NodeGlobPatternStateResourceLimit;
        if (value.indexes[index]) return;
        try value.order.append(self.a, index);
        value.indexes[index] = true;
    }
    fn wasSeen(self: *Context, path_value: []const u8, index: usize) bool {
        const seen = self.seen.get(path_value) orelse return false;
        return seen[self.cacheIndex(index)];
    }
    fn cacheIndex(self: *Context, index: usize) usize {
        // Pattern.cacheKey joins the suffix glob strings. Positions after the
        // end and the final empty component share the same empty suffix key.
        if (index >= self.parts.len) return self.parts.len;
        if (index + 1 == self.parts.len) if (self.literal(index)) |value| if (value.len == 0) return self.parts.len;
        return index;
    }
    fn markSeen(self: *Context, item: Work) !bool {
        const seen = self.seen.get(item.path) orelse blk: {
            const value = try self.a.alloc(bool, self.parts.len + 1);
            @memset(value, false);
            try self.seen.put(self.a, item.path, value);
            break :blk value;
        };
        var repeated = false;
        for (item.state.order.items) |index| {
            const key = self.cacheIndex(index);
            repeated = repeated or seen[key];
            seen[key] = true;
        }
        return repeated;
    }
    fn result(self: *Context, value: []const u8) !void {
        if (self.results_seen.contains(value)) return;
        try self.results_seen.put(self.a, value, {});
        try self.results.append(self.a, value);
    }
    fn literal(self: *Context, index: usize) ?[]const u8 {
        if (index >= self.parts.len or self.parts[index] == .globstar) return null;
        return self.parts[index].regex.literal;
    }
    fn star(self: *Context, index: usize) bool { return index < self.parts.len and self.parts[index] == .globstar; }
    fn test(self: *Context, index: usize, name: []const u8) !bool {
        if (index >= self.parts.len) return false;
        if (self.star(index)) return true;
        const spec = self.parts[index].regex;
        if (spec.literal) |value| return std.mem.eql(u8, value, name);
        var s: Scope = .{ .engine = self.engine };
        defer s.deinit();
        const dot = name.len > 0 and name[0] == '.';
        switch (spec.fast) {
            .star => return name.len > 0 and !dot,
            .dot_star => return dot and !std.mem.eql(u8, name, ".") and !std.mem.eql(u8, name, ".."),
            .star_dot_star => return !dot and std.mem.indexOfScalar(u8, name, '.') != null,
            .suffix, .qmarks => {
                if (dot or (spec.fast == .qmarks and core.utf16Length(name) != spec.length)) return false;
                if (!spec.nocase) return std.mem.endsWith(u8, name, spec.suffix);
                const value = try s.invoke(try s.own(try text(self.engine, name)), "toLowerCase", &.{});
                const suffix = try s.invoke(try s.own(try text(self.engine, spec.suffix)), "toLowerCase", &.{});
                return s.truthy(try s.invoke(value, "endsWith", &.{suffix}));
            },
            .none => return s.truthy(try s.invoke(self.regexes[index], "test", &.{try s.own(try text(self.engine, name))})),
        }
    }
    fn add(self: *Context, path_value: []const u8, value: State) !void {
        try self.pending.append(self.a, .{ .path = path_value, .state = value });
    }
    fn visit(self: *Context, item: Work) !void {
        try self.tick();
        if (try self.markSeen(item)) return;
        const fullpath = try self.path("resolve", self.root, item.path);
        const info = try self.stat(fullpath);
        const last = self.parts.len - 1;
        var has_unfollowed = false;
        for (item.state.order.items) |index| if (!item.state.symlinks[index]) { has_unfollowed = true; };
        const directory = if (info) |value| value.kind == .directory or (value.kind == .sym_link and has_unfollowed) else false;
        const last_literal = self.literal(last);
        const is_last = item.state.indexes[last] or (last_literal != null and last_literal.?.len == 0 and directory and last > 0 and item.state.indexes[last - 1] and self.star(last - 1));
        const first = self.literal(0);
        if (item.state.indexes[0] and first != null) {
            if (builtin.os.tag == .windows and std.mem.endsWith(u8, first.?, ":")) {
                try self.add(try std.mem.concat(self.a, u8, &.{first.?, "\\"}), try self.one(1));
                return;
            }
            if (first.?.len == 0) { try self.add("/", try self.one(1)); return; }
            if (std.mem.eql(u8, first.?, ".")) { try self.add(".", try self.one(1)); return; }
        }
        const count = item.state.order.items.len;
        const only = if (count == 1) item.state.order.items[0] else 0;
        if (is_last and last_literal != null) {
            if (try self.stat(try self.path("join", fullpath, last_literal.?)) != null and (last_literal.?.len > 0 or directory))
                try self.result(try self.path("join", item.path, last_literal.?));
            if (count == 1 and item.state.indexes[last]) return;
        } else if (is_last and self.star(last) and (!std.mem.eql(u8, item.path, ".") or (first != null and std.mem.eql(u8, first.?, ".")) or (last == 0 and info != null))) {
            try self.result(item.path);
        }
        if (!directory) return;
        const children: []const Entry = if (count == 1 and self.literal(only) != null) blk: {
            const name = self.literal(only).?;
            const child = (try self.stat(try self.path("join", fullpath, name))) orelse return;
            const entries = try self.a.alloc(Entry, 1);
            entries[0] = .{ .name = name, .kind = child.kind };
            break :blk entries;
        } else try self.read(fullpath);
        for (children) |entry| {
            try self.tick();
            const entry_path = try self.path("join", item.path, entry.name);
            try self.stats.put(self.a, try self.path("join", fullpath, entry.name), .{ .kind = entry.kind });
            var next_state = try self.state();
            for (item.state.order.items) |index| {
                if (self.wasSeen(entry_path, index) or self.wasSeen(entry_path, index + 1)) return;
                const next = index + 1;
                const from_symlink = item.state.symlinks[index];
                if (self.star(index)) {
                    const next_matches = try self.test(next, entry.name);
                    var non_glob = next;
                    while (self.star(non_glob)) non_glob += 1;
                    if (entry.name.len > 0 and entry.name[0] == '.' and !try self.test(non_glob, entry.name)) continue;
                    if (!from_symlink and entry.kind == .directory) try self.include(&next_state, index)
                    else if (!from_symlink and index == last) try self.result(entry_path);
                    if (next_matches and next == last and !is_last) try self.result(entry_path)
                    else if (next_matches and entry.kind == .directory and index + 2 < next_state.indexes.len) try self.include(&next_state, index + 2);
                    if ((next_matches or (first != null and std.mem.eql(u8, first.?, "."))) and
                        (entry.kind == .directory or entry.kind == .sym_link) and !from_symlink and next < next_state.indexes.len)
                        try self.include(&next_state, next);
                    if (entry.kind == .sym_link) next_state.symlinks[index] = true;
                } else if (self.literal(index)) |value| {
                    if (try self.test(index, entry.name) and index != last) try self.include(&next_state, next)
                    else if (std.mem.eql(u8, value, ".") and try self.test(next, entry.name)) {
                        if (next == last) try self.result(entry_path)
                        else if (next + 1 < next_state.indexes.len) try self.include(&next_state, next + 1);
                    }
                } else if (try self.test(index, entry.name)) {
                    if (index == last) try self.result(entry_path)
                    else if (entry.kind == .directory) try self.include(&next_state, next);
                }
            }
            if (next_state.order.items.len > 0) try self.add(entry_path, next_state);
        }
    }
};

fn globSync(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const options = if (args.len > 1) args[1] else c.pi_js_undefined();
    if (!c.JS_IsUndefined(options) and (!c.JS_IsObject(options) or c.JS_IsArray(options) or c.JS_IsFunction(engine.context, options)))
        return v.js.typeError(engine, "globSync options must be an object");
    // Match the source destructuring order even though broader APIs reject.
    const exclude = if (c.JS_IsUndefined(options)) c.pi_js_undefined() else try s.get(options, "exclude");
    const cwd = if (c.JS_IsUndefined(options)) c.pi_js_undefined() else try s.get(options, "cwd");
    const with_types = if (c.JS_IsUndefined(options)) c.pi_js_undefined() else try s.get(options, "withFileTypes");
    if (!v.nullish(exclude) or s.truthy(with_types)) return error.NodeGlobOptionsOutsidePackageContract;
    if (!v.nullish(cwd) and !c.JS_IsString(cwd)) return error.NodeGlobCwdOutsidePackageContract;
    const input = if (args.len > 0) args[0] else c.pi_js_undefined();
    if (!c.JS_IsString(input)) return error.NodeGlobPatternArrayOutsidePackageContract;
    const original = try bytes(engine, input);
    defer engine.gpa.free(original);
    const root = if (v.nullish(cwd)) try engine.gpa.dupe(u8, ".") else try bytes(engine, cwd);
    defer engine.gpa.free(root);
    var arena = std.heap.ArenaAllocator.init(engine.gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const parts = try pattern.compile(a, original);
    const out = try s.array();
    if (parts.len == 0) return c.JS_DupValue(engine.context, out);
    const regexes = try a.alloc(c.JSValue, parts.len);
    for (parts, regexes) |part, *slot| {
        slot.* = c.pi_js_undefined();
        if (part == .globstar or part.regex.literal != null or part.regex.fast != .none) continue;
        const spec = part.regex;
        const flags: []const u8 = if (spec.unicode) (if (spec.nocase) "iu" else "u") else (if (spec.nocase) "i" else "");
        var constructor_args = [_]c.JSValue{ try s.own(try text(engine, spec.source)), try s.text(flags) };
        slot.* = try s.own(try engine.checked(c.JS_CallConstructor(engine.context, engine.intrinsic_regexp_constructor, constructor_args.len, &constructor_args)));
    }
    var context: Context = .{ .engine = engine, .io = engine.native_io orelse return error.NativeIoUnavailable, .a = a, .imports = roots[0], .root = root, .parts = parts, .regexes = regexes };
    try context.queue.append(a, .{ .path = ".", .state = try context.one(0) });
    while (context.queue.pop()) |item| {
        try context.visit(item);
        try context.queue.appendSlice(a, context.pending.items);
        context.pending.clearRetainingCapacity();
    }
    for (context.results.items, 0..) |value, index| try s.index(out, @intCast(index), try s.own(try text(engine, value)));
    return c.JS_DupValue(engine.context, out);
}
