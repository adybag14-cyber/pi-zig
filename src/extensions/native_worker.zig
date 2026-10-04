//! Internal native extension process. The production runtime switches here
//! only after the complete compatibility surface is certified.
const std = @import("std");
const engine_mod = @import("engine.zig");
const bindings_mod = @import("native_bindings.zig");
const typescript = @import("typescript.zig");
const node_fs = @import("node_fs.zig");
const console = @import("console.zig");
const module_resolver = @import("module_resolver.zig");
const text_encoding = @import("text_encoding.zig");
const node_path = @import("node_path.zig");
const node_url = @import("node_url.zig");
const commonjs = @import("commonjs.zig");
const timers = @import("timers.zig");

const Loader = struct {
    io: std.Io,
    engine: *engine_mod.Engine,
    fn normalize(context: ?*anyopaque, gpa: std.mem.Allocator, base: []const u8, specifier: []const u8) anyerror![]u8 {
        return normalizeMode(context, gpa, base, specifier, false);
    }
    fn normalizeRequire(context: ?*anyopaque, gpa: std.mem.Allocator, base: []const u8, specifier: []const u8) anyerror![]u8 {
        return normalizeMode(context, gpa, base, specifier, true);
    }
    fn normalizeMode(context: ?*anyopaque, gpa: std.mem.Allocator, base: []const u8, specifier: []const u8, require_mode: bool) anyerror![]u8 {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        var resolver: module_resolver.Resolver = .{ .io = self.io, .native_modules = &self.engine.native_module_names, .require_mode = require_mode };
        return gpa.dupe(u8, try resolver.resolve(arena.allocator(), base, specifier));
    }
    fn source(context: ?*anyopaque, gpa: std.mem.Allocator, name: []const u8) anyerror![]u8 {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        const bytes = try std.Io.Dir.cwd().readFileAlloc(self.io, name, gpa, .limited(16 * 1024 * 1024));
        errdefer gpa.free(bytes);
        if (std.mem.endsWith(u8, name, ".ts") or std.mem.endsWith(u8, name, ".mts") or std.mem.endsWith(u8, name, ".cts")) {
            const transformed = try typescript.transform(gpa, bytes);
            gpa.free(bytes);
            return transformed;
        }
        return bytes;
    }

    fn input(context: ?*anyopaque, engine: *engine_mod.Engine, name: []const u8) anyerror!engine_mod.ModuleInput {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        const bytes = try source(context, engine.gpa, name);
        errdefer engine.gpa.free(bytes);
        var is_commonjs = std.mem.endsWith(u8, name, ".cjs") or std.mem.endsWith(u8, name, ".cts");
        const json = std.mem.endsWith(u8, name, ".json");
        if (!is_commonjs and !json and std.mem.endsWith(u8, name, ".js")) {
            var directory = std.fs.path.dirname(name) orelse ".";
            var package_type: ?[]u8 = null;
            defer if (package_type) |owned| engine.gpa.free(owned);
            while (true) {
                const path = try std.fs.path.join(engine.gpa, &.{ directory, "package.json" });
                defer engine.gpa.free(path);
                const package_bytes = std.Io.Dir.cwd().readFileAlloc(self.io, path, engine.gpa, .limited(1024 * 1024)) catch |err| switch (err) {
                    error.FileNotFound, error.NotDir => null,
                    else => return err,
                };
                if (package_bytes) |content| {
                    defer engine.gpa.free(content);
                    var parsed = try std.json.parseFromSlice(std.json.Value, engine.gpa, content, .{});
                    defer parsed.deinit();
                    if (parsed.value != .object) return error.InvalidExtensionPackage;
                    if (parsed.value.object.get("type")) |value| {
                        if (value != .string) return error.InvalidExtensionPackage;
                        package_type = try engine.gpa.dupe(u8, value.string);
                    }
                    break;
                }
                if (std.mem.eql(u8, std.fs.path.basename(directory), "node_modules")) break;
                const parent = std.fs.path.dirname(directory) orelse break;
                if (std.mem.eql(u8, parent, directory)) break;
                directory = parent;
            }
            is_commonjs = if (package_type) |kind| std.mem.eql(u8, kind, "commonjs") else !try typescript.hasModuleSyntax(bytes);
        }
        if (is_commonjs or json) {
            const value = try commonjs.load(engine, bytes, name, json);
            engine.gpa.free(bytes);
            return .{ .exports = value };
        }
        return .{ .source = bytes };
    }
};

fn writeRecord(writer: *std.Io.Writer, value: std.json.Value) !void {
    try writer.writeByte(0x1e);
    try std.json.Stringify.value(value, .{}, writer);
    try writer.writeByte('\n');
    try writer.flush();
}

fn writeFailure(gpa: std.mem.Allocator, writer: *std.Io.Writer, message: []const u8) !void {
    var failure: std.json.ObjectMap = .empty;
    defer failure.deinit(gpa);
    try failure.put(gpa, "ok", .{ .bool = false });
    try failure.put(gpa, "error", .{ .string = message });
    try writeRecord(writer, .{ .object = failure });
}

fn requiredText(object: std.json.ObjectMap, name: []const u8) ![]const u8 {
    const value = object.get(name) orelse return error.MissingWorkerField;
    if (value != .string) return error.InvalidWorkerField;
    return value.string;
}

fn encoded(gpa: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();
    try std.json.Stringify.value(value, .{}, &output.writer);
    return output.toOwnedSlice();
}

pub fn normalizeToolResult(gpa: std.mem.Allocator, raw: []const u8, tool_name: []const u8) ![]u8 {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const allocator = arena.allocator();
    const result = try std.json.parseFromSliceLeaky(std.json.Value, allocator, raw, .{});
    const object = if (result == .object) result.object else std.json.ObjectMap.empty;
    if (object.get("__piDelegateBuiltin")) |delegate| {
        if (delegate == .string and std.mem.eql(u8, delegate.string, tool_name)) return gpa.dupe(u8, "{\"content\":\"\",\"isError\":false,\"delegateBuiltin\":true}");
    }
    var text: std.ArrayList(u8) = .empty;
    var images: std.json.Array = .init(allocator);
    const content = object.get("content") orelse std.json.Value.null;
    if (content == .string) {
        try text.appendSlice(allocator, content.string);
    } else if (content == .array) {
        var text_items: usize = 0;
        for (content.array.items) |item| {
            if (item == .string) {
                if (text_items > 0) try text.append(allocator, '\n');
                try text.appendSlice(allocator, item.string);
                text_items += 1;
            } else if (item == .object) {
                const kind = item.object.get("type") orelse continue;
                if (kind != .string) continue;
                if (std.mem.eql(u8, kind.string, "text")) {
                    const line = item.object.get("text") orelse std.json.Value{ .string = "" };
                    if (line != .string) return error.InvalidNativeToolText;
                    if (text_items > 0) try text.append(allocator, '\n');
                    try text.appendSlice(allocator, line.string);
                    text_items += 1;
                } else if (std.mem.eql(u8, kind.string, "image")) {
                    const data = item.object.get("data") orelse item.object.get("base64") orelse continue;
                    if (data != .string or data.string.len == 0) continue;
                    const mime = item.object.get("mimeType") orelse item.object.get("mime_type") orelse std.json.Value{ .string = "image/png" };
                    var image: std.json.ObjectMap = .empty;
                    try image.put(allocator, "dataBase64", data);
                    try image.put(allocator, "mimeType", mime);
                    try images.append(.{ .object = image });
                }
            }
        }
    } else if (content != .null) {
        const json = try encoded(allocator, content);
        try text.appendSlice(allocator, json);
    }
    var projected: std.json.ObjectMap = .empty;
    try projected.put(allocator, "content", .{ .string = text.items });
    const is_error = object.get("isError") orelse std.json.Value{ .bool = false };
    try projected.put(allocator, "isError", .{ .bool = is_error == .bool and is_error.bool });
    try projected.put(allocator, "details", object.get("details") orelse std.json.Value.null);
    const terminate = object.get("terminate") orelse std.json.Value{ .bool = false };
    try projected.put(allocator, "terminate", .{ .bool = terminate == .bool and terminate.bool });
    if (object.get("usage")) |usage| if (usage == .object) try projected.put(allocator, "usage", usage);
    if (object.get("addedToolNames")) |names| if (names == .array) {
        var valid: std.json.Array = .init(allocator);
        for (names.array.items) |name| if (name == .string and name.string.len > 0) try valid.append(name);
        try projected.put(allocator, "addedToolNames", .{ .array = valid });
    };
    if (object.get("actionQueue")) |actions| if (actions == .array) try projected.put(allocator, "actionQueue", actions);
    if (images.items.len > 0) {
        try projected.put(allocator, "imageBase64", images.items[0].object.get("dataBase64").?);
        try projected.put(allocator, "imageMime", images.items[0].object.get("mimeType").?);
        try projected.put(allocator, "images", .{ .array = images });
    }
    return encoded(gpa, .{ .object = projected });
}

fn invoke(gpa: std.mem.Allocator, bindings: *bindings_mod.Bindings, object: std.json.ObjectMap) ![]u8 {
    const kind = try requiredText(object, "kind");
    const snapshot = try encoded(gpa, object.get("context") orelse std.json.Value{ .object = .empty });
    defer gpa.free(snapshot);
    try bindings.setContext(snapshot);
    if (object.get("flags")) |flags| {
        const source = try encoded(gpa, flags);
        defer gpa.free(source);
        try bindings.setFlags(source);
    }
    if (std.mem.eql(u8, kind, "hook") or std.mem.eql(u8, kind, "tool")) {
        const source = try encoded(gpa, object.get("payload") orelse std.json.Value{ .object = .empty });
        defer gpa.free(source);
        const name = try requiredText(object, "name");
        if (std.mem.eql(u8, kind, "hook")) return bindings.invokeHook(name, source);
        const call_id = if (object.get("toolCallId")) |id| if (id == .string) id.string else "native-tool-call" else "native-tool-call";
        const result = try bindings.invokeTool(name, call_id, source);
        defer gpa.free(result);
        return normalizeToolResult(gpa, result, name);
    }
    if (std.mem.eql(u8, kind, "command")) {
        const arguments = if (object.get("rawArguments")) |value| if (value == .string) value.string else "" else "";
        return bindings.invokeCommand(try requiredText(object, "name"), arguments);
    }
    if (std.mem.eql(u8, kind, "provider_method")) {
        const append_signal = if (object.get("appendSignal")) |signal| signal == .bool and signal.bool else false;
        const aborted = if (object.get("aborted")) |value| value == .bool and value.bool else false;
        const arguments = try encoded(gpa, object.get("args") orelse std.json.Value{ .array = std.json.Array.init(gpa) });
        defer gpa.free(arguments);
        return bindings.invokeProviderMethodWithSignal(try requiredText(object, "callbackId"), arguments, append_signal, aborted);
    }
    return error.UnsupportedNativeWorkerRequest;
}

test "native tool result projection preserves text images details and usage" {
    const gpa = std.testing.allocator;
    const result = try normalizeToolResult(gpa, "{\"content\":[\"first\",{\"type\":\"text\",\"text\":\"second\"},{\"type\":\"image\",\"data\":\"YWJj\",\"mimeType\":\"image/jpeg\"}],\"details\":{\"marker\":42},\"usage\":{\"input\":1},\"addedToolNames\":[\"loaded\",\"\",3]}", "fixture");
    defer gpa.free(result);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, result, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("first\nsecond", parsed.value.object.get("content").?.string);
    try std.testing.expectEqualStrings("image/jpeg", parsed.value.object.get("imageMime").?.string);
    try std.testing.expectEqual(@as(usize, 1), parsed.value.object.get("images").?.array.items.len);
    try std.testing.expectEqual(@as(usize, 1), parsed.value.object.get("addedToolNames").?.array.items.len);
    try std.testing.expect(parsed.value.object.contains("details") and parsed.value.object.contains("usage"));
}

pub fn run(gpa: std.mem.Allocator, io: std.Io, extension_path: []const u8) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    var loader: Loader = .{ .io = io, .engine = engine };
    engine.setSourceLoader(.{ .context = &loader, .load = Loader.source, .normalize = Loader.normalize, .normalize_require = Loader.normalizeRequire, .input = Loader.input });
    const bindings = try bindings_mod.Bindings.init(gpa, engine);
    defer bindings.deinit();
    try timers.install(engine, io);
    try bindings.installSchemas();
    try node_fs.install(engine, io);
    try node_path.install(engine, io);
    try node_url.install(engine);
    try commonjs.install(engine);
    try console.install(engine, io);
    try text_encoding.install(engine);
    const absolute = try std.Io.Dir.cwd().realPathFileAlloc(io, extension_path, gpa);
    defer gpa.free(absolute);
    const filename = try gpa.dupeZ(u8, absolute);
    defer gpa.free(filename);
    for (filename) |*byte| if (byte.* == '\\') {
        byte.* = '/';
    };
    try bindings.setSourcePath(filename);
    const input_module = try Loader.input(&loader, engine, filename);
    defer switch (input_module) {
        .source => |source| gpa.free(source),
        .exports => |exports| engine.freeValue(exports),
    };
    const loaded_factory = switch (input_module) {
        .source => |source| bindings.loadFactory(source, filename),
        .exports => |exports| bindings.loadFactoryValue(exports),
    };
    loaded_factory catch |err| {
        if (engine.last_error) |message| {
            var error_buffer: [4096]u8 = undefined;
            var stderr = std.Io.File.stderr().writerStreaming(io, &error_buffer);
            try stderr.interface.print("Native extension load failed: {s}\n", .{message});
            try stderr.interface.flush();
        }
        return err;
    };
    var output_buffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(io, &output_buffer);
    const writer = &output.interface;
    const manifest = try bindings.manifestJson(extension_path);
    defer gpa.free(manifest);
    try writer.writeAll("\x1e{\"type\":\"ready\",\"manifest\":");
    try writer.writeAll(manifest);
    try writer.writeAll("}\n");
    try writer.flush();
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(io, &input_buffer);
    while (true) {
        var line: std.ArrayList(u8) = .empty;
        defer line.deinit(gpa);
        while (true) {
            const byte = input.interface.takeByte() catch |err| switch (err) {
                error.EndOfStream => {
                    if (std.mem.trim(u8, line.items, " \t\r").len != 0) return error.IncompleteNativeWorkerRequest;
                    return;
                },
                else => return err,
            };
            if (byte == '\n') break;
            if (line.items.len >= 4 * 1024 * 1024) return error.NativeWorkerRequestTooLarge;
            try line.append(gpa, byte);
        }
        if (std.mem.trim(u8, line.items, " \t\r").len == 0) continue;
        var arena: std.heap.ArenaAllocator = .init(gpa);
        defer arena.deinit();
        const allocator = arena.allocator();
        const request = std.json.parseFromSliceLeaky(std.json.Value, allocator, line.items, .{}) catch |err| {
            try writeFailure(allocator, writer, @errorName(err));
            continue;
        };
        if (request != .object) {
            try writeFailure(allocator, writer, "InvalidWorkerRequest");
            continue;
        }
        const kind = requiredText(request.object, "kind") catch |err| {
            try writeFailure(allocator, writer, @errorName(err));
            continue;
        };
        if (std.mem.eql(u8, kind, "shutdown")) {
            try writer.writeAll("\x1e{\"ok\":true,\"result\":{}}\n");
            try writer.flush();
            return;
        }
        engine.beginInvocation();
        const result = invoke(gpa, bindings, request.object) catch |err| {
            try writeFailure(allocator, writer, engine.last_error orelse @errorName(err));
            continue;
        };
        defer gpa.free(result);
        try writer.writeAll("\x1e{\"ok\":true,\"result\":");
        try writer.writeAll(result);
        try writer.writeAll("}\n");
        try writer.flush();
    }
}
