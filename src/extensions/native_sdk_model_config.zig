//! Immutable SDK models.json loading and source-schema validation.
const std = @import("std");
const sdk = @import("native_sdk.zig");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
pub fn stripComments(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    const raw = if (std.mem.startsWith(u8, input, "\xef\xbb\xbf")) input[3..] else input;
    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();
    var index: usize = 0;
    var quoted = false;
    while (index < raw.len) {
        const byte = raw[index];
        if (quoted) {
            output.writer.writeByte(byte) catch return error.OutOfMemory;
            index += 1;
            if (byte == '\\' and index < raw.len) {
                output.writer.writeByte(raw[index]) catch return error.OutOfMemory;
                index += 1;
            } else if (byte == '"') quoted = false;
            continue;
        }
        if (byte == '"') quoted = true;
        if (byte == '/' and index + 1 < raw.len and raw[index + 1] == '/') {
            while (index < raw.len and raw[index] != '\n') index += 1;
            continue;
        }
        output.writer.writeByte(byte) catch return error.OutOfMemory;
        index += 1;
    }
    const first = try output.toOwnedSlice();
    defer gpa.free(first);
    quoted = false;
    index = 0;
    while (index < first.len) {
        const byte = first[index];
        if (quoted) {
            output.writer.writeByte(byte) catch return error.OutOfMemory;
            index += 1;
            if (byte == '\\' and index < first.len) {
                output.writer.writeByte(first[index]) catch return error.OutOfMemory;
                index += 1;
            } else if (byte == '"') quoted = false;
            continue;
        }
        if (byte == '"') quoted = true;
        if (byte == ',') {
            var next = index + 1;
            while (next < first.len and std.ascii.isWhitespace(first[next])) next += 1;
            if (next < first.len and (first[next] == '}' or first[next] == ']')) {
                index += 1;
                continue;
            }
        }
        output.writer.writeByte(byte) catch return error.OutOfMemory;
        index += 1;
    }
    return output.toOwnedSlice();
}
const Report = struct { writer: *std.Io.Writer, count: usize = 0 };
fn errorLine(out: *Report, path: []const u8, message: []const u8) !void {
    if (out.count >= 8) return;
    out.count += 1;
    try out.writer.print("  - {s}: {s}\n", .{ if (path.len == 0) "root" else path, message });
}
fn childPath(gpa: std.mem.Allocator, parent: []const u8, key: []const u8) ![]u8 {
    const result = if (parent.len == 0) try gpa.dupe(u8, key) else try std.fmt.allocPrint(gpa, "{s}.{s}", .{ parent, key });
    std.mem.replaceScalar(u8, result, '/', '.');
    return result;
}
pub fn validate(gpa: std.mem.Allocator, schema: std.json.Value, value: std.json.Value, path: []const u8, output: *std.Io.Writer, depth: usize) anyerror!void {
    var report: Report = .{ .writer = output };
    try walk(gpa, schema, value, path, &report, depth);
}
fn walk(gpa: std.mem.Allocator, schema: std.json.Value, value: std.json.Value, path: []const u8, output: *Report, depth: usize) anyerror!void {
    if (depth > 64) return error.NativeSDKModelSchemaDepth;
    if (schema != .object) return;
    const object = schema.object;
    if (object.get("enum")) |allowed| if (allowed == .array) {
        var matches = false;
        for (allowed.array.items) |candidate| {
            matches = matches or switch (candidate) {
                .string => value == .string and std.mem.eql(u8, candidate.string, value.string),
                .bool => value == .bool and candidate.bool == value.bool,
                .null => value == .null,
                .integer => value == .integer and candidate.integer == value.integer,
                .float => value == .float and candidate.float == value.float,
                else => false,
            };
        }
        if (!matches) return errorLine(output, path, "must be equal to one of the allowed values");
    };
    if (object.get("anyOf")) |branches| {
        if (branches == .array) {
            var failures: std.Io.Writer.Allocating = .init(gpa);
            defer failures.deinit();
            var report: Report = .{ .writer = &failures.writer };
            for (branches.array.items) |branch| {
                var trial: std.Io.Writer.Allocating = .init(gpa);
                defer trial.deinit();
                var candidate: Report = .{ .writer = &trial.writer };
                try walk(gpa, branch, value, path, &candidate, depth + 1);
                if (candidate.count == 0) return;
                var lines = std.mem.splitScalar(u8, std.mem.trimEnd(u8, trial.written(), "\n"), '\n');
                while (lines.next()) |line| {
                    if (report.count >= 8) break;
                    try report.writer.print("{s}\n", .{line});
                    report.count += 1;
                }
            }
            var lines = std.mem.splitScalar(u8, std.mem.trimEnd(u8, failures.written(), "\n"), '\n');
            while (lines.next()) |line| {
                if (output.count >= 8) break;
                try output.writer.print("{s}\n", .{line});
                output.count += 1;
            }
            return errorLine(output, path, "must match a schema in anyOf");
        }
    }
    if (object.get("type")) |kind| if (kind == .string) {
        const matches = if (std.mem.eql(u8, kind.string, "object")) value == .object else if (std.mem.eql(u8, kind.string, "array")) value == .array else if (std.mem.eql(u8, kind.string, "string")) value == .string else if (std.mem.eql(u8, kind.string, "boolean")) value == .bool else if (std.mem.eql(u8, kind.string, "null")) value == .null else if (std.mem.eql(u8, kind.string, "number")) value == .integer or value == .float else if (std.mem.eql(u8, kind.string, "integer")) value == .integer or (value == .float and @trunc(value.float) == value.float) else true;
        if (!matches) {
            const message = try std.fmt.allocPrint(gpa, "must be {s}", .{kind.string});
            defer gpa.free(message);
            return errorLine(output, path, message);
        }
    };
    if (object.get("const")) |constant| {
        if (!std.mem.eql(u8, @tagName(constant), @tagName(value)) or (constant == .string and !std.mem.eql(u8, constant.string, value.string))) return errorLine(output, path, "must be equal to constant");
    }
    if (value == .integer or value == .float) {
        const number: f64 = if (value == .integer) @floatFromInt(value.integer) else value.float;
        inline for (.{ "minimum", "maximum", "exclusiveMinimum" }) |keyword| {
            if (object.get(keyword)) |bound| {
                const limit: f64 = if (bound == .integer) @floatFromInt(bound.integer) else bound.float;
                const valid = if (comptime std.mem.eql(u8, keyword, "minimum")) number >= limit else if (comptime std.mem.eql(u8, keyword, "maximum")) number <= limit else number > limit;
                if (!valid) {
                    const message = try std.fmt.allocPrint(gpa, "must be {s} {d}", .{ if (comptime std.mem.eql(u8, keyword, "minimum")) ">=" else if (comptime std.mem.eql(u8, keyword, "maximum")) "<=" else ">", limit });
                    defer gpa.free(message);
                    try errorLine(output, path, message);
                }
            }
        }
    }
    if (value == .array) if (object.get("maxItems")) |bound| {
        if (value.array.items.len > bound.integer) {
            const message = try std.fmt.allocPrint(gpa, "must not have more than {d} items", .{bound.integer});
            defer gpa.free(message);
            try errorLine(output, path, message);
        }
    };
    if (value == .string) if (object.get("minLength")) |minimum| {
        const min = if (minimum == .integer) minimum.integer else 0;
        var utf16: usize = 0;
        var text = (std.unicode.Utf8View.init(value.string) catch return error.InvalidUtf8).iterator();
        while (text.nextCodepoint()) |point| utf16 += if (point > 0xffff) @as(usize, 2) else 1;
        if (utf16 < min) {
            const message = try std.fmt.allocPrint(gpa, "must not have fewer than {d} characters", .{min});
            defer gpa.free(message);
            try errorLine(output, path, message);
        }
    };
    if (value == .object) {
        if (object.get("required")) |required| if (required == .array) {
            var missing: std.Io.Writer.Allocating = .init(gpa);
            defer missing.deinit();
            var first: ?[]const u8 = null;
            for (required.array.items) |key| {
                if (key != .string or value.object.contains(key.string)) continue;
                if (first != null) try missing.writer.writeAll(", ") else first = key.string;
                try missing.writer.writeAll(key.string);
            }
            if (first) |key| {
                const child = try childPath(gpa, path, key);
                defer gpa.free(child);
                const message = try std.fmt.allocPrint(gpa, "must have required properties {s}", .{missing.written()});
                defer gpa.free(message);
                try errorLine(output, child, message);
            }
        };
        if (object.get("properties")) |properties| if (properties == .object) {
            var fields = properties.object.iterator();
            while (fields.next()) |entry| {
                const current = value.object.get(entry.key_ptr.*) orelse continue;
                const child = try childPath(gpa, path, entry.key_ptr.*);
                defer gpa.free(child);
                try walk(gpa, entry.value_ptr.*, current, child, output, depth + 1);
            }
        };
        if (object.get("patternProperties")) |patterns| if (patterns == .object) {
            var pattern_it = patterns.object.iterator();
            while (pattern_it.next()) |pattern| {
                // Captured Type.String records use this unconstrained pattern.
                if (!std.mem.eql(u8, pattern.key_ptr.*, "^(.*)$") and !std.mem.eql(u8, pattern.key_ptr.*, "^.*$")) return error.NativeSDKModelSchemaPattern;
                var fields = value.object.iterator();
                while (fields.next()) |entry| {
                    if (std.mem.indexOfScalar(u8, entry.key_ptr.*, '\n') != null or std.mem.indexOfScalar(u8, entry.key_ptr.*, '\r') != null) continue;
                    const child = try childPath(gpa, path, entry.key_ptr.*);
                    defer gpa.free(child);
                    try walk(gpa, pattern.value_ptr.*, entry.value_ptr.*, child, output, depth + 1);
                }
            }
        };
    }
    if (value == .array) if (object.get("items")) |items| for (value.array.items, 0..) |item, index| {
        const key = try std.fmt.allocPrint(gpa, "{d}", .{index});
        defer gpa.free(key);
        const child = try childPath(gpa, path, key);
        defer gpa.free(child);
        try walk(gpa, items, item, child, output, depth + 1);
    };
}
pub fn load(engine: *engine_mod.Engine, options: c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try sdk.put(engine, result, "providers", try sdk.object(engine));
    try sdk.put(engine, result, "error", c.pi_js_undefined());
    const configured_path = if (c.JS_IsObject(options)) try sdk.get(engine, options, "modelsPath") else c.pi_js_undefined();
    defer engine.freeValue(configured_path);
    if (c.JS_IsNull(configured_path)) return result;
    const path = if (c.JS_IsString(configured_path)) try engine.toString(configured_path) else default: {
        const directory = try sdk.agentDir(engine);
        defer engine.gpa.free(directory);
        break :default try std.fs.path.join(engine.gpa, &.{ directory, "models.json" });
    };
    defer engine.gpa.free(path);
    if (path.len == 0 or engine.native_io == null) return result;
    const raw = std.Io.Dir.cwd().readFileAlloc(engine.native_io.?, path, engine.gpa, .limited(4 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return result,
        error.OutOfMemory => return err,
        else => {
            const message = try std.fmt.allocPrint(engine.gpa, "Failed to load models.json: {s}\n\nFile: {s}", .{ @errorName(err), path });
            defer engine.gpa.free(message);
            try sdk.put(engine, result, "error", try sdk.text(engine, message));
            return result;
        },
    };
    defer engine.gpa.free(raw);
    const stripped = try stripComments(engine.gpa, raw);
    defer engine.gpa.free(stripped);
    var parsed = std.json.parseFromSlice(std.json.Value, engine.gpa, stripped, .{ .allocate = .alloc_always }) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => {
            // Preserve the engine's native JSON diagnostic while making parse
            // failure cached configuration state, as the public SDK requires.
            const malformed = sdk.jsonObject(engine, stripped) catch {
                const exception = if (engine.captured_exception) |value| c.JS_DupValue(engine.context, value) else c.JS_GetException(engine.context);
                defer engine.freeValue(exception);
                const diagnostic = try sdk.get(engine, exception, "message");
                defer engine.freeValue(diagnostic);
                const reason = try engine.toString(diagnostic);
                defer engine.gpa.free(reason);
                const message = try std.fmt.allocPrint(engine.gpa, "Failed to parse models.json: {s}\n\nFile: {s}", .{ reason, path });
                defer engine.gpa.free(message);
                try sdk.put(engine, result, "error", try sdk.text(engine, message));
                return result;
            };
            engine.freeValue(malformed);
            return error.NativeSDKModelsJsonParse;
        },
    };
    defer parsed.deinit();
    var schema = try std.json.parseFromSlice(std.json.Value, engine.gpa, @embedFile("fixtures/model-config-6fb2e78.schema.json"), .{});
    defer schema.deinit();
    var errors: std.Io.Writer.Allocating = .init(engine.gpa);
    defer errors.deinit();
    validate(engine.gpa, schema.value, parsed.value, "", &errors.writer, 0) catch |err| switch (err) {
        error.WriteFailed => return error.OutOfMemory,
        else => return err,
    };
    if (errors.written().len > 0) {
        const message = try std.fmt.allocPrint(engine.gpa, "Invalid models.json schema:\n{s}\n\nFile: {s}", .{ std.mem.trimEnd(u8, errors.written(), "\n"), path });
        defer engine.gpa.free(message);
        try sdk.put(engine, result, "error", try sdk.text(engine, message));
        return result;
    }
    const value = try sdk.jsonObject(engine, stripped);
    defer engine.freeValue(value);
    const providers = try sdk.get(engine, value, "providers");
    defer engine.freeValue(providers);
    // The JSON parser already owns an independent graph. Deep freezing is
    // performed by native recursive Object.freeze calls on that graph.
    try freeze(engine, providers, 0);
    try sdk.put(engine, result, "providers", c.JS_DupValue(engine.context, providers));
    return result;
}
fn freeze(engine: *engine_mod.Engine, value: c.JSValue, depth: usize) !void {
    if (!c.JS_IsObject(value)) return;
    if (depth > 64) return error.NativeSDKModelSchemaDepth;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const object = try sdk.get(engine, global, "Object");
    defer engine.freeValue(object);
    const children = try sdk.invoke(engine, object, "values", &.{value});
    defer engine.freeValue(children);
    for (0..try sdk.length(engine, children)) |index| {
        const child = try engine.checked(c.JS_GetPropertyUint32(engine.context, children, @intCast(index)));
        defer engine.freeValue(child);
        try freeze(engine, child, depth + 1);
    }
    const frozen = try sdk.invoke(engine, object, "freeze", &.{value});
    engine.freeValue(frozen);
}
