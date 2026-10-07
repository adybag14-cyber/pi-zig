//! Native durable tool registrations over an explicitly owned local environment.
const std = @import("std");
const registry = @import("registry.zig");
const invoke = @import("invoke.zig");
const json = registry.json;
const types = @import("../types.zig");
const tools = @import("../tools.zig");
const execution_env = @import("../execution_env.zig");
const commands = @import("../shell.zig");
const capability = @import("../env_capability.zig");
const names = [_][]const u8{ "read", "write", "edit", "bash" };
const schemas = [_][]const u8{
    "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"offset\":{\"type\":\"number\"},\"limit\":{\"type\":\"number\"}},\"required\":[\"path\"]}",
    "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"}},\"required\":[\"path\",\"content\"]}",
    "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"edits\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{\"oldText\":{\"type\":\"string\"},\"newText\":{\"type\":\"string\"}},\"required\":[\"oldText\",\"newText\"]}}},\"required\":[\"path\",\"edits\"]}",
    "{\"type\":\"object\",\"properties\":{\"command\":{\"type\":\"string\"},\"timeout\":{\"type\":\"number\"}},\"required\":[\"command\"]}",
};
const Entry = struct { owner: *Bindings, method: usize };
pub const Bindings = struct {
    gpa: std.mem.Allocator,
    env: capability.ExecutionEnv,
    metadata: json.Owned,
    entries: [4]Entry,
    tools: [4]registry.Tool,
    refs: std.atomic.Value(usize) = .init(1),
    pub fn create(gpa: std.mem.Allocator, env: anytype) !*Bindings {
        const self = try gpa.create(Bindings);
        errdefer gpa.destroy(self);
        self.* = .{ .gpa = gpa, .env = capability.ExecutionEnv.from(env), .metadata = try json.Owned.empty(gpa), .entries = undefined, .tools = undefined };
        errdefer self.metadata.deinit();
        for (names, schemas, 0..) |name, schema, index| {
            self.entries[index] = .{ .owner = self, .method = index };
            self.tools[index] = .{ .name = name, .description = name, .parameters = try json.parseLeaky(self.metadata.arena.allocator(), schema), .prepare = if (index == 2) prepareEdits else null, .execute = execute, .resource = .{ .context = &self.entries[index], .retain = retain, .release = release }, .limits = .{ .retain = if (index == 3) .tail else .head } };
        }
        return self;
    }
    pub fn drop(self: *Bindings) void {
        if (self.refs.fetchSub(1, .acq_rel) == 1) {
            const gpa = self.gpa;
            self.metadata.deinit();
            gpa.destroy(self);
        }
    }
    pub fn install(self: *Bindings, owner: *registry.Registry) !void {
        try owner.install(.{ .name = "pi.tools", .tools = &self.tools });
    }
};
/// Explicit registration; the default four-tool Bindings set stays unchanged.
/// prepare_context must outlive the registry snapshots/invocations holding this binding.
pub const PowerShellBinding = struct {
    gpa: std.mem.Allocator,
    env: capability.ExecutionEnv,
    metadata: json.Owned,
    options: tools.PowerShellOptions,
    environment: ?std.process.Environ.Map = null,
    tool: registry.Tool,
    refs: std.atomic.Value(usize) = .init(1),
    pub fn create(gpa: std.mem.Allocator, env: anytype, options: tools.PowerShellOptions) !*PowerShellBinding {
        const self = try gpa.create(PowerShellBinding);
        errdefer gpa.destroy(self);
        self.* = .{ .gpa = gpa, .env = capability.ExecutionEnv.from(env), .metadata = try json.Owned.empty(gpa), .options = options, .tool = undefined };
        errdefer self.metadata.deinit();
        const a = self.metadata.arena.allocator();
        if (options.commandPrefix) |prefix| self.options.commandPrefix = try a.dupe(u8, prefix);
        if (options.cwd) |cwd| self.options.cwd = try a.dupe(u8, cwd);
        const programs = try a.alloc([]const u8, options.programs.len);
        for (programs, options.programs) |*program, value| program.* = try a.dupe(u8, value);
        self.options.programs = programs;
        if (options.env) |environment| {
            self.environment = try environment.clone(gpa);
            self.options.env = &self.environment.?;
        }
        errdefer if (self.environment) |*environment| environment.deinit();
        self.tool = .{
            .name = "powershell",
            .description = "Execute a PowerShell command in the current working directory. Returns combined stdout and stderr. Output is truncated to last 2000 lines or 50KB (whichever is hit first). If truncated, full output is saved to a temp file. Optionally provide a timeout in seconds.",
            .parameters = try json.parseLeaky(a, "{\"type\":\"object\",\"properties\":{\"command\":{\"type\":\"string\",\"description\":\"PowerShell command to execute\"},\"timeout\":{\"type\":\"number\",\"description\":\"Timeout in seconds (optional, no default timeout)\"}},\"required\":[\"command\"]}"),
            .execute = executePowerShell,
            .resource = .{ .context = self, .retain = retainPowerShell, .release = releasePowerShell },
            .limits = .{ .retain = .tail },
        };
        return self;
    }
    pub fn drop(self: *PowerShellBinding) void {
        if (self.refs.fetchSub(1, .acq_rel) == 1) {
            const gpa = self.gpa;
            if (self.environment) |*environment| environment.deinit();
            self.metadata.deinit();
            gpa.destroy(self);
        }
    }
    pub fn install(self: *PowerShellBinding, owner: *registry.Registry) !void {
        try owner.install(.{ .name = "pi.tools.powershell", .tools = &.{self.tool} });
    }
};
pub fn createPowerShellTool(gpa: std.mem.Allocator, env: anytype, options: tools.PowerShellOptions) !*PowerShellBinding {
    return PowerShellBinding.create(gpa, env, options);
}
fn retainPowerShell(raw: ?*anyopaque) void {
    const binding: *PowerShellBinding = @ptrCast(@alignCast(raw.?));
    _ = binding.refs.fetchAdd(1, .monotonic);
}
fn releasePowerShell(raw: ?*anyopaque) void {
    const binding: *PowerShellBinding = @ptrCast(@alignCast(raw.?));
    binding.drop();
}
fn executePowerShell(raw: ?*anyopaque, args: json.Value, opaque_api: *anyopaque, context: types.Context) !registry.Execution {
    const binding: *PowerShellBinding = @ptrCast(@alignCast(raw.?));
    const api: *invoke.Api = @ptrCast(@alignCast(opaque_api));
    if (api.gpa.ptr != binding.env.fs.gpa.ptr or api.gpa.vtable != binding.env.fs.gpa.vtable) return error.IncompatibleEnvironmentAllocator;
    var options = binding.options;
    options.onOutput = onOutput;
    options.output_context = api;
    options.outputWindow = api.outputWindow();
    const result = try tools.powershell_runner.execute(api.gpa, binding.env, .{ .command = try string(args, "command"), .timeout = try numeric(args, "timeout") }, options, context);
    return .{ .result = result, .contentProvided = false };
}
fn retain(state: ?*anyopaque) void {
    const entry: *Entry = @ptrCast(@alignCast(state.?));
    _ = entry.owner.refs.fetchAdd(1, .monotonic);
}
fn release(state: ?*anyopaque) void {
    const entry: *Entry = @ptrCast(@alignCast(state.?));
    entry.owner.drop();
}
fn string(value: json.Value, name: []const u8) ![]const u8 {
    return json.asString(try json.required(value, name));
}
fn numeric(value: json.Value, name: []const u8) !?f64 {
    return if (json.get(value, name)) |field| try json.asNumber(field) else null;
}
fn onOutput(state: ?*anyopaque, text: []const u8, _: types.Context, info: commands.OutputInfo) !void {
    const api: *invoke.Api = @ptrCast(@alignCast(state.?));
    try api.outputText(text, info.skipped);
}
fn execute(state: ?*anyopaque, args: json.Value, opaque_api: *anyopaque, context: types.Context) !registry.Execution {
    const entry: *Entry = @ptrCast(@alignCast(state.?));
    const owner = entry.owner;
    const api: *invoke.Api = @ptrCast(@alignCast(opaque_api));
    if (api.gpa.ptr != owner.env.fs.gpa.ptr or api.gpa.vtable != owner.env.fs.gpa.vtable) return error.IncompatibleEnvironmentAllocator;
    var set: tools.ToolSet = .{ .gpa = api.gpa, .io = owner.env.fs.io };
    const result = switch (entry.method) {
        0 => try tools.read.execute(owner.env, .{ .path = try string(args, "path"), .offset = try numeric(args, "offset"), .limit = try numeric(args, "limit") }, context),
        1 => try set.write(owner.env, try string(args, "path"), try string(args, "content"), context),
        2 => blk: {
            const input = try json.required(args, "edits");
            if (input != .array) return error.InvalidEdits;
            const edits = try api.gpa.alloc(tools.edit_match.Edit, input.array.items.len);
            defer api.gpa.free(edits);
            for (edits, input.array.items) |*edit, value| edit.* = .{ .oldText = try string(value, "oldText"), .newText = try string(value, "newText") };
            break :blk try set.edit(owner.env, try string(args, "path"), edits, context);
        },
        3 => try set.bash(owner.env, .{ .command = try string(args, "command"), .timeout = try numeric(args, "timeout") }, .{ .onOutput = onOutput, .output_context = api, .outputWindow = api.outputWindow() }, context),
        else => unreachable,
    };
    return .{ .result = result, .contentProvided = entry.method != 3 };
}
fn singleEdit(value: json.Value) bool {
    return value == .object and json.get(value, "oldText") != null and json.get(value, "oldText").? == .string and json.get(value, "newText") != null and json.get(value, "newText").? == .string;
}
fn prepareEdits(_: ?*anyopaque, gpa: std.mem.Allocator, input: json.Value, _: types.Context) !json.Value {
    var args = try json.clone(gpa, input);
    if (args != .object) return args;
    if (json.get(args, "edits")) |original| {
        var value = original;
        if (value == .string) value = json.parseLeaky(gpa, value.string) catch |err| {
            if (err == error.OutOfMemory) return err;
            return args;
        };
        if (value == .array) try args.object.put(gpa, "edits", value) else if (singleEdit(value)) {
            var edits: std.array_list.Managed(json.Value) = .init(gpa);
            try edits.append(value);
            try args.object.put(gpa, "edits", .{ .array = edits });
        }
    }
    const old = json.get(args, "oldText");
    const new = json.get(args, "newText");
    if (old == null or new == null or old.? != .string or new.? != .string) return args;
    var edits: std.array_list.Managed(json.Value) = .init(gpa);
    if (json.get(args, "edits")) |value| {
        if (value == .array) edits = value.array;
    }
    var edit: json.Value = .{ .object = .empty };
    try edit.object.put(gpa, "oldText", old.?);
    try edit.object.put(gpa, "newText", new.?);
    try edits.append(edit);
    try args.object.put(gpa, "edits", .{ .array = edits });
    _ = args.object.orderedRemove("oldText");
    _ = args.object.orderedRemove("newText");
    return args;
}

test "durable Harness builtin registry executes actual files repaired edits and real bash" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try scratch.dir.realPath(io, &buffer);
    var parent = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer parent.deinit();
    var env = try execution_env.ExecutionEnv.init(gpa, io, .{ .cwd = buffer[0..length], .environ = &parent, .temp_dir = buffer[0..length] });
    defer env.deinit();
    var owner = try registry.Registry.init(gpa, io);
    defer owner.deinit();
    const bindings = try Bindings.create(gpa, &env);
    defer bindings.drop();
    try bindings.install(&owner);
    const snapshot = owner.snapshot();
    defer snapshot.release();
    const rows = [_]struct { name: []const u8, input: []const u8, expected: []const u8 }{
        .{ .name = "write", .input = "{\"path\":\"file\",\"content\":\"alpha\\nbeta\"}", .expected = "Successfully wrote to file" },
        .{ .name = "edit", .input = "{\"path\":\"file\",\"oldText\":\"beta\",\"newText\":\"BETA\"}", .expected = "Successfully replaced 1 block(s) in file." },
        .{ .name = "read", .input = "{\"path\":\"file\",\"offset\":\"2\"}", .expected = "BETA" },
        .{ .name = "bash", .input = "{\"command\":\"printf 'native-output'\"}", .expected = "native-output" },
    };
    for (rows) |row| {
        var args = try json.Owned.parse(gpa, row.input);
        defer args.deinit();
        var result = try invoke.invoke(gpa, snapshot, row.name, args.value, .{}, .{});
        defer result.deinit();
        if (json.get(result.value.value, "isError")) |error_value| try std.testing.expect(!error_value.bool);
        const content = try json.required(result.value.value, "content");
        try std.testing.expectEqualStrings(row.expected, try json.asString(try json.required(content.array.items[0], "text")));
    }
}
