//! Read-only footer data with owner-thread subscriptions and native git metadata.
const std = @import("std");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const Method = enum(c_int) { getGitBranch, getExtensionStatuses, getAvailableProviderCount, onBranchChange, unsubscribe };
const Token = struct { gpa: std.mem.Allocator, manager: ?*Manager };
const Subscription = struct { id: u64, owner: u64, callback: c.JSValue };
fn finalizer(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const token: *Token = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    token.gpa.destroy(token);
}
pub const Manager = struct {
    engine: *engine_mod.Engine,
    token: c.JSValue,
    token_class: c.JSClassID,
    statuses: c.JSValue,
    owners: std.AutoHashMapUnmanaged(u64, void) = .empty,
    subscriptions: std.ArrayList(Subscription) = .empty,
    next_id: u64 = 1,
    cwd: ?[]u8 = null,
    branch: ?[]u8 = null,
    branch_cached: bool = false,
    provider_count: usize = 0,
    next_poll: ?i64 = null,
    notifying: bool = false,

    pub fn init(engine: *engine_mod.Engine) !Manager {
        var class: c.JSClassID = 0;
        _ = c.JS_NewClassID(engine.runtime, &class);
        const definition: c.JSClassDef = .{ .class_name = "Native Footer Data", .finalizer = finalizer };
        if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
        const token = try engine.checked(c.JS_NewObjectClass(engine.context, @intCast(class)));
        errdefer engine.freeValue(token);
        const state = try engine.gpa.create(Token);
        state.* = .{ .gpa = engine.gpa, .manager = null };
        _ = c.JS_SetOpaque(token, state);
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        const map = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "Map"));
        defer engine.freeValue(map);
        const statuses = try engine.checked(c.JS_CallConstructor(engine.context, map, 0, null));
        return .{ .engine = engine, .token = token, .token_class = class, .statuses = statuses };
    }
    pub fn attach(self: *Manager) void {
        const state: *Token = @ptrCast(@alignCast(c.JS_GetOpaque(self.token, self.token_class).?));
        state.manager = self;
    }
    pub fn deinit(self: *Manager) void {
        const state: *Token = @ptrCast(@alignCast(c.JS_GetOpaque(self.token, self.token_class).?));
        state.manager = null;
        for (self.subscriptions.items) |entry| self.engine.freeValue(entry.callback);
        self.subscriptions.deinit(self.engine.gpa);
        self.owners.deinit(self.engine.gpa);
        if (self.cwd) |path| self.engine.gpa.free(path);
        if (self.branch) |value| self.engine.gpa.free(value);
        self.engine.freeValue(self.statuses);
        self.engine.freeValue(self.token);
    }
    pub fn addOwner(self: *Manager, owner: u64) !void {
        try self.owners.put(self.engine.gpa, owner, {});
    }
    pub fn removeOwner(self: *Manager, owner: u64) void {
        _ = self.owners.remove(owner);
        var index: usize = 0;
        while (index < self.subscriptions.items.len) {
            if (self.subscriptions.items[index].owner == owner) self.engine.freeValue(self.subscriptions.orderedRemove(index).callback) else index += 1;
        }
    }
    fn function(self: *Manager, owner: u64, method: Method, id: u64) !c.JSValue {
        var data = [_]c.JSValue{ self.token, c.JS_NewInt64(self.engine.context, self.token_class), c.JS_NewInt64(self.engine.context, @intCast(owner)), c.JS_NewInt64(self.engine.context, @intCast(id)) };
        defer self.engine.freeValue(data[1]);
        defer self.engine.freeValue(data[2]);
        defer self.engine.freeValue(data[3]);
        return self.engine.checked(c.JS_NewCFunctionData2(self.engine.context, call, @tagName(method), if (method == .onBranchChange) 1 else 0, @intFromEnum(method), data.len, &data));
    }
    pub fn create(self: *Manager, owner: u64) !c.JSValue {
        const result = try self.engine.checked(c.JS_NewObject(self.engine.context));
        errdefer self.engine.freeValue(result);
        inline for (std.meta.fields(Method)) |field| if (field.value != @intFromEnum(Method.unsubscribe)) {
            if (c.JS_DefinePropertyValueStr(self.engine.context, result, field.name, try self.function(owner, @enumFromInt(field.value), 0), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        };
        return result;
    }
    fn call(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
        const engine = engine_mod.Engine.fromContext(context.?);
        var class: i64 = 0;
        var owner: i64 = 0;
        var id: i64 = 0;
        if (c.JS_ToInt64(context, &class, data[1]) < 0 or c.JS_ToInt64(context, &owner, data[2]) < 0 or c.JS_ToInt64(context, &id, data[3]) < 0) return engine.throwCaptured();
        const token: *Token = @ptrCast(@alignCast(c.JS_GetOpaque(data[0], @intCast(class)) orelse return c.pi_js_undefined()));
        const self = token.manager orelse return c.pi_js_undefined();
        const method: Method = @enumFromInt(magic);
        if (!self.owners.contains(@intCast(owner))) return if (method == .unsubscribe) c.pi_js_undefined() else c.JS_ThrowTypeError(context, "Retired footer owner");
        return self.operation(@intCast(owner), method, @intCast(id), if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| {
            if (err == error.JavaScriptException) return engine.throwCaptured();
            if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
            return c.JS_ThrowTypeError(context, "Native footer data: %s", @as([*:0]const u8, @errorName(err)));
        };
    }
    fn operation(self: *Manager, owner: u64, method: Method, id: u64, args: []c.JSValue) !c.JSValue {
        switch (method) {
            .getGitBranch => {
                if (!self.branch_cached) {
                    self.branch = try self.resolveBranch();
                    self.branch_cached = true;
                }
                return if (self.branch) |branch| self.engine.checked(c.JS_NewStringLen(self.engine.context, branch.ptr, branch.len)) else c.pi_js_null();
            },
            .getExtensionStatuses => return c.JS_DupValue(self.engine.context, self.statuses),
            .getAvailableProviderCount => return c.JS_NewInt64(self.engine.context, @intCast(self.provider_count)),
            .onBranchChange => {
                if (args.len == 0 or !c.JS_IsFunction(self.engine.context, args[0])) return error.InvalidBranchListener;
                if (self.subscriptions.items.len >= 256) return error.FooterSubscriptionLimit;
                const next = self.next_id;
                self.next_id += 1;
                const unsubscribe = try self.function(owner, .unsubscribe, next);
                errdefer self.engine.freeValue(unsubscribe);
                const retained = c.JS_DupValue(self.engine.context, args[0]);
                errdefer self.engine.freeValue(retained);
                try self.subscriptions.append(self.engine.gpa, .{ .id = next, .owner = owner, .callback = retained });
                if (self.engine.native_io) |io| self.next_poll = std.Io.Clock.awake.now(io).toMilliseconds() + 500;
                return unsubscribe;
            },
            .unsubscribe => {
                for (self.subscriptions.items, 0..) |entry, index| if (entry.id == id and entry.owner == owner) {
                    self.engine.freeValue(self.subscriptions.orderedRemove(index).callback);
                    break;
                };
                return c.pi_js_undefined();
            },
        }
    }
    pub fn setStatus(self: *Manager, key: c.JSValue, value: c.JSValue) !void {
        const method: [*:0]const u8 = if (c.JS_IsUndefined(value) or c.JS_IsNull(value)) "delete" else "set";
        const function_value = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, self.statuses, method));
        defer self.engine.freeValue(function_value);
        var args = [_]c.JSValue{ key, value };
        const result = try self.engine.checked(c.JS_Call(self.engine.context, function_value, self.statuses, if (std.mem.eql(u8, std.mem.span(method), "set")) 2 else 1, &args));
        self.engine.freeValue(result);
    }
    pub fn update(self: *Manager, snapshot: c.JSValue) !void {
        const cwd_value = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, snapshot, "cwd"));
        defer self.engine.freeValue(cwd_value);
        if (c.JS_IsString(cwd_value)) {
            const path = try self.engine.toString(cwd_value);
            if (self.cwd == null or !std.mem.eql(u8, self.cwd.?, path)) {
                if (self.cwd) |old| self.engine.gpa.free(old);
                self.cwd = path;
                self.branch_cached = false;
                if (self.branch) |old| self.engine.gpa.free(old);
                self.branch = null;
                try self.notify();
            } else self.engine.gpa.free(path);
        }
        const encoded = try self.engine.stringify(snapshot);
        defer self.engine.gpa.free(encoded);
        var arena = std.heap.ArenaAllocator.init(self.engine.gpa);
        defer arena.deinit();
        const json = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), encoded, .{});
        if (json != .object) return;
        var unique: std.StringHashMapUnmanaged(void) = .empty;
        const scoped = json.object.get("scopedModels");
        const has_scoped = if (scoped) |value| value == .array and value.array.items.len > 0 else false;
        const models = if (has_scoped) scoped else json.object.get("availableModels");
        // Unbound availability preserves the last bound count. An explicit
        // empty vector resets it to zero without refreshing any provider.
        if (models == null or models.? != .array) return;
        if (models) |list| if (list == .array) for (list.array.items) |item| {
            if (item != .object) continue;
            const model = item.object.get("model") orelse item;
            if (model != .object) continue;
            const provider = model.object.get("provider") orelse continue;
            if (provider != .string) continue;
            try unique.put(arena.allocator(), provider.string, {});
        };
        self.provider_count = unique.count();
    }
    fn resolveBranch(self: *Manager) !?[]u8 {
        const io = self.engine.native_io orelse return null;
        var directory = try self.engine.gpa.dupe(u8, self.cwd orelse return null);
        defer self.engine.gpa.free(directory);
        while (true) {
            const git = try std.fs.path.join(self.engine.gpa, &.{ directory, ".git" });
            defer self.engine.gpa.free(git);
            const git_stat = std.Io.Dir.cwd().statFile(io, git, .{}) catch null;
            var recognized_git_file = false;
            var head = try std.fs.path.join(self.engine.gpa, &.{ git, "HEAD" });
            defer self.engine.gpa.free(head);
            const git_file = std.Io.Dir.cwd().readFileAlloc(io, git, self.engine.gpa, .limited(65536)) catch |err| switch (err) {
                error.OutOfMemory => return err,
                else => null,
            };
            if (git_file) |body| {
                defer self.engine.gpa.free(body);
                const trimmed = std.mem.trim(u8, body, " \r\n\t");
                if (std.mem.startsWith(u8, trimmed, "gitdir: ")) {
                    recognized_git_file = true;
                    const resolved = try std.fs.path.resolve(self.engine.gpa, &.{ directory, std.mem.trim(u8, trimmed[8..], " \r\n\t") });
                    defer self.engine.gpa.free(resolved);
                    const replacement = try std.fs.path.join(self.engine.gpa, &.{ resolved, "HEAD" });
                    self.engine.gpa.free(head);
                    head = replacement;
                }
            }
            const contents = std.Io.Dir.cwd().readFileAlloc(io, head, self.engine.gpa, .limited(65536)) catch |err| switch (err) {
                error.OutOfMemory => return err,
                else => null,
            };
            if (contents) |body| {
                defer self.engine.gpa.free(body);
                const trimmed = std.mem.trim(u8, body, " \r\n\t");
                const branch = if (std.mem.startsWith(u8, trimmed, "ref: refs/heads/")) trimmed[16..] else "detached";
                if (std.mem.eql(u8, branch, ".invalid")) {
                    const result = std.process.run(self.engine.gpa, io, .{
                        .argv = &.{ "git", "--no-optional-locks", "symbolic-ref", "--quiet", "--short", "HEAD" },
                        .cwd = .{ .path = directory },
                        .stdout_limit = .limited(65536),
                        .stderr_limit = .limited(65536),
                        .timeout = .{ .duration = .{ .raw = .fromSeconds(5), .clock = .awake } },
                    }) catch |err| switch (err) {
                        error.OutOfMemory => return err,
                        else => return try self.engine.gpa.dupe(u8, "detached"),
                    };
                    defer self.engine.gpa.free(result.stdout);
                    defer self.engine.gpa.free(result.stderr);
                    const resolved = std.mem.trim(u8, result.stdout, " \r\n\t");
                    return try self.engine.gpa.dupe(u8, if (result.term == .exited and result.term.exited == 0 and resolved.len > 0) resolved else "detached");
                }
                return try self.engine.gpa.dupe(u8, branch);
            }
            if (git_stat) |stat| if (stat.kind == .directory or recognized_git_file) return null;
            const parent = std.fs.path.dirname(directory) orelse return null;
            if (parent.len == 0 or std.mem.eql(u8, parent, directory)) return null;
            const replacement = try self.engine.gpa.dupe(u8, parent);
            self.engine.gpa.free(directory);
            directory = replacement;
        }
    }
    pub fn poll(self: *Manager) !bool {
        const io = self.engine.native_io orelse return false;
        const due = self.next_poll orelse return false;
        if (std.Io.Clock.awake.now(io).toMilliseconds() < due) return false;
        self.next_poll = if (self.subscriptions.items.len > 0) due + 500 else null;
        const next = try self.resolveBranch();
        const same = if (self.branch) |old| if (next) |value| std.mem.eql(u8, old, value) else false else next == null;
        if (same) {
            if (next) |value| self.engine.gpa.free(value);
            return false;
        }
        if (self.branch) |old| self.engine.gpa.free(old);
        self.branch = next;
        self.branch_cached = true;
        try self.notify();
        return true;
    }
    fn notify(self: *Manager) !void {
        if (self.notifying) return;
        self.notifying = true;
        defer self.notifying = false;
        const snapshot = try self.engine.gpa.dupe(Subscription, self.subscriptions.items);
        defer self.engine.gpa.free(snapshot);
        for (snapshot) |*entry| entry.callback = c.JS_DupValue(self.engine.context, entry.callback);
        defer for (snapshot) |entry| self.engine.freeValue(entry.callback);
        for (snapshot) |entry| {
            const active = for (self.subscriptions.items) |current| {
                if (current.id == entry.id) break true;
            } else false;
            if (active) {
                const result = try self.engine.checked(c.JS_Call(self.engine.context, entry.callback, c.pi_js_undefined(), 0, null));
                self.engine.freeValue(result);
            }
        }
    }
};

fn testSnapshot(engine: *engine_mod.Engine, source: []const u8) !c.JSValue {
    const terminated = try engine.gpa.dupeZ(u8, source);
    defer engine.gpa.free(terminated);
    return engine.checked(c.JS_ParseJSON(engine.context, terminated.ptr, source.len, "native-footer-source-snapshot"));
}
test "native footer provider count replays original scope precedence distinct IDs and bound empty availability" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var manager = try Manager.init(engine);
    manager.attach();
    defer manager.deinit();
    var source = try std.json.parseFromSlice(std.json.Value, engine.gpa, @embedFile("fixtures/footer-scope-count-original-7fb.json"), .{});
    defer source.deinit();
    for (source.value.object.get("cases").?.array.items) |case| {
        var out: std.Io.Writer.Allocating = .init(engine.gpa);
        defer out.deinit();
        try out.writer.writeAll("{\"scopedModels\":");
        try std.json.Stringify.value(case.object.get("scope").?, .{}, &out.writer);
        try out.writer.writeAll(",\"availableModels\":");
        try std.json.Stringify.value(case.object.get("available").?, .{}, &out.writer);
        try out.writer.writeByte('}');
        const snapshot = try testSnapshot(engine, out.written());
        defer engine.freeValue(snapshot);
        try manager.update(snapshot);
        try std.testing.expectEqual(@as(usize, @intCast(case.object.get("count").?.integer)), manager.provider_count);
    }
    const unbound = try testSnapshot(engine, "{\"scopedModels\":[],\"availableModels\":null,\"configuredProviders\":[\"invented\"]}");
    defer engine.freeValue(unbound);
    try manager.update(unbound);
    try std.testing.expectEqual(@as(usize, 2), manager.provider_count);
    const empty = try testSnapshot(engine, "{\"scopedModels\":[],\"availableModels\":[]}");
    defer engine.freeValue(empty);
    try manager.update(empty);
    try std.testing.expectEqual(@as(usize, 0), manager.provider_count);
}

test "native footer branch reads nested repo atomic HEAD replacement worktree detached and malformed git markers" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "repo/.git");
    try tmp.dir.createDirPath(io, "repo/nested/child");
    try tmp.dir.createDirPath(io, "worktree/nested");
    try tmp.dir.createDirPath(io, "metadata");
    try tmp.dir.writeFile(io, .{ .sub_path = "repo/.git/HEAD", .data = "ref: refs/heads/source-main\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "metadata/HEAD", .data = "ref: refs/heads/worktree-branch\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "worktree/.git", .data = "gitdir: ../metadata\n" });
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = io;
    var manager = try Manager.init(engine);
    manager.attach();
    defer manager.deinit();
    const paths = [_][]const u8{ "repo/nested/child", "worktree/nested" };
    for (paths, [_][]const u8{ "source-main", "worktree-branch" }) |path, expected| {
        var buffer: [std.fs.max_path_bytes]u8 = undefined;
        const size = try tmp.dir.realPathFile(io, path, &buffer);
        if (manager.cwd) |previous| engine.gpa.free(previous);
        manager.cwd = try engine.gpa.dupe(u8, buffer[0..size]);
        const actual = (try manager.resolveBranch()).?;
        defer engine.gpa.free(actual);
        try std.testing.expectEqualStrings(expected, actual);
    }
    try tmp.dir.writeFile(io, .{ .sub_path = "metadata/next", .data = "0123456789012345678901234567890123456789\n" });
    try tmp.dir.rename("metadata/next", tmp.dir, "metadata/HEAD", io);
    const detached = (try manager.resolveBranch()).?;
    defer engine.gpa.free(detached);
    try std.testing.expectEqualStrings("detached", detached);
    try tmp.dir.deleteFile(io, "metadata/HEAD");
    try std.testing.expect((try manager.resolveBranch()) == null);
}

fn footerOwnershipCase(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    var manager = try Manager.init(engine);
    manager.attach();
    defer manager.deinit();
    try manager.addOwner(1);
    const provider = try manager.create(1);
    defer engine.freeValue(provider);
    const snapshot = try testSnapshot(engine, "{\"cwd\":\"footer-fixture\",\"availableModels\":[{\"provider\":\"a\"},{\"provider\":\"a\"},{\"provider\":\"b\"}]}");
    defer engine.freeValue(snapshot);
    try manager.update(snapshot);
    const callback = try engine.eval("()=>{}", "footer-owned-callback.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(callback);
    var args = [_]c.JSValue{callback};
    const off = try manager.operation(1, .onBranchChange, 0, &args);
    defer engine.freeValue(off);
    const key = try engine.checked(c.JS_NewString(engine.context, "status"));
    defer engine.freeValue(key);
    try manager.setStatus(key, key);
    c.JS_RunGC(engine.runtime);
    manager.removeOwner(1);
    const late = try engine.checked(c.JS_Call(engine.context, off, c.pi_js_undefined(), 0, null));
    engine.freeValue(late);
}
test "native footer provider data status subscription and retirement release every host allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, footerOwnershipCase, .{});
}
