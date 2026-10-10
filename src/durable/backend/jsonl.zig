//! Portable format-v1 JSONL storage over the supplied filesystem capability.
const std = @import("std");
const memory = @import("memory.zig");
const query = @import("query.zig");
const source_scan = @import("source_scan.zig");
pub const json = memory.json;
const env = @import("../env_capability.zig");
const types = @import("../types.zig");
const Value = json.Value;
pub const Options = struct { fsync: bool = false };
const Sidecar = struct { file: []const u8, content: std.ArrayList(u8) = .empty, path: ?[]u8 = null };
const Replacement = struct { file: []const u8, content: []const u8 };
const Line = struct { value: Value, start: u64, confirmed: bool = false };
const ParsedFile = struct { name: []const u8, path: []const u8, lines: std.ArrayList(Line) = .empty };
const Key = struct { file: []const u8, seq: u64, ordinal: u64 };
const KeyContext = struct {
    pub fn hash(_: KeyContext, key: Key) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(key.file);
        hasher.update(std.mem.asBytes(&key.seq));
        hasher.update(std.mem.asBytes(&key.ordinal));
        return hasher.final();
    }
    pub fn eql(_: KeyContext, a: Key, b: Key) bool {
        return a.seq == b.seq and a.ordinal == b.ordinal and std.mem.eql(u8, a.file, b.file);
    }
};
const Index = std.HashMapUnmanaged(Key, *Line, KeyContext, std.hash_map.default_max_load_percentage);
fn text(value: Value, name: []const u8) ![]const u8 {
    return json.asString(try memory.field(value, name));
}
fn integer(value: Value, name: []const u8) !u64 {
    return json.asInteger(try memory.field(value, name));
}
fn object(allocator: std.mem.Allocator, pairs: anytype) !Value {
    var value: Value = .{ .object = .empty };
    inline for (pairs) |pair| try value.object.put(allocator, pair[0], pair[1]);
    return value;
}
fn number(value: u64) Value {
    return .{ .integer = @intCast(value) };
}
fn isType(value: Value, wanted: []const u8) bool {
    const tag = json.get(value, "type") orelse return false;
    return tag == .string and std.mem.eql(u8, tag.string, wanted);
}
fn terminal(record: Value) bool {
    const state = json.get(record, "state") orelse return false;
    const status = json.get(state, "status") orelse return false;
    return status == .string and std.mem.eql(u8, status.string, "terminal");
}
fn currentOnly(record: Value) !bool {
    const scope = try text(try memory.field(record, "scope"), "kind");
    const history = json.get(record, "history");
    return !std.mem.eql(u8, scope, "conversation") or (history != null and history.? == .string and std.mem.eql(u8, history.?.string, "latest"));
}
fn sidecarName(allocator: std.mem.Allocator, kind: []const u8, id: u64) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}-{d}.jsonl", .{ kind, id });
}
fn sidecarId(name: []const u8, reclaim: bool) ?u64 {
    if (!std.mem.startsWith(u8, name, "doc-") and !std.mem.startsWith(u8, name, "task-")) return null;
    const ending = if (reclaim) ".jsonl.reclaim" else ".jsonl";
    if (!std.mem.endsWith(u8, name, ending)) return null;
    const start = (std.mem.indexOfScalar(u8, name, '-') orelse return null) + 1;
    const digits = name[start .. name.len - ending.len];
    if (digits.len == 0 or (digits.len > 1 and digits[0] == '0')) return null;
    for (digits) |byte| if (!std.ascii.isDigit(byte)) return null;
    return std.fmt.parseInt(u64, digits, 10) catch std.math.maxInt(u64);
}
fn appendLine(allocator: std.mem.Allocator, buffer: *std.ArrayList(u8), value: Value) !void {
    const encoded = try json.stringify(allocator, value);
    defer allocator.free(encoded);
    try buffer.appendSlice(allocator, encoded);
    try buffer.append(allocator, '\n');
}
fn compare(_: void, a: ParsedFile, b: ParsedFile) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}
pub const Jsonl = struct {
    gpa: std.mem.Allocator,
    fs: env.FileSystem,
    directory: []u8,
    main_path: []u8,
    options: Options,
    memory: memory.Memory,
    current_only: std.AutoHashMapUnmanaged(u64, void) = .empty,
    live_tasks: std.AutoHashMapUnmanaged(u64, void) = .empty,
    closed: bool = false,
    poisoned: bool = false,
    last_error: ?[]u8 = null,
    last_cause: ?anyerror = null,
    pub fn open(gpa: std.mem.Allocator, directory: []const u8, filesystem: anytype, context: types.Context, options: Options) !Jsonl {
        const fs = env.FileSystem.from(filesystem);
        const absolute = try fs.absolutePath(directory, context);
        if (absolute == .failure) {
            var failure = absolute.failure;
            defer failure.deinit(fs.gpa);
            return error.JsonlPathResolutionFailed;
        }
        defer fs.gpa.free(absolute.value);
        var created = try fs.createDir(absolute.value, .{ .recursive = true }, context);
        if (created == .failure) {
            defer created.failure.deinit(fs.gpa);
            return error.JsonlDirectoryCreationFailed;
        }
        const owned = try gpa.dupe(u8, absolute.value);
        errdefer gpa.free(owned);
        const main = try fs.joinPath(&.{ owned, "main.jsonl" }, context);
        if (main == .failure) {
            var failure = main.failure;
            defer failure.deinit(fs.gpa);
            return error.JsonlPathJoinFailed;
        }
        defer fs.gpa.free(main.value);
        const main_path = try gpa.dupe(u8, main.value);
        errdefer gpa.free(main_path);
        const state = try memory.Memory.init(gpa);
        var self: Jsonl = .{ .gpa = gpa, .fs = fs, .directory = owned, .main_path = main_path, .options = options, .memory = state };
        errdefer self.memory.deinit();
        errdefer {
            self.current_only.deinit(gpa);
            self.live_tasks.deinit(gpa);
            if (self.last_error) |message| gpa.free(message);
        }
        try self.recover(context);
        return self;
    }
    pub fn deinit(self: *Jsonl) void {
        self.memory.deinit();
        self.current_only.deinit(self.gpa);
        self.live_tasks.deinit(self.gpa);
        self.gpa.free(self.directory);
        self.gpa.free(self.main_path);
        if (self.last_error) |message| self.gpa.free(message);
        self.* = undefined;
    }
    pub fn close(self: *Jsonl) void {
        if (self.closed) return;
        self.closed = true;
        self.memory.close();
    }
    pub fn assertUsable(self: *const Jsonl) !void {
        if (self.closed) return error.JsonlStorageClosed;
        if (self.poisoned) return error.JsonlStoragePoisoned;
    }
    fn issue(self: *Jsonl, cause: anyerror, comptime format: []const u8, args: anytype) anyerror {
        const message = std.fmt.allocPrint(self.gpa, format, args) catch return error.OutOfMemory;
        if (self.last_error) |old| self.gpa.free(old);
        self.last_error = message;
        self.last_cause = cause;
        return cause;
    }
    fn fileFailure(self: *Jsonl, action: []const u8, failure: types.FileError, poison: bool) anyerror {
        var released = failure;
        defer released.deinit(self.fs.gpa);
        if (poison) self.poisoned = true;
        return self.issue(if (poison) error.JsonlStoragePoisoned else error.JsonlFilesystemFailure, "JSONL {s} failed: {s}", .{ action, failure.message });
    }
    fn resolveFile(self: *const Jsonl, file: []const u8, context: types.Context) ![]u8 {
        var path = try self.fs.joinPath(&.{ self.directory, file }, context);
        if (path == .failure) {
            defer path.failure.deinit(self.fs.gpa);
            return error.JsonlPathJoinFailed;
        }
        return path.value;
    }
    fn encode(self: *Jsonl, allocator: std.mem.Allocator, seq: u64, writes: Value, sidecars: *std.ArrayList(Sidecar)) ![]u8 {
        var main_writes: Value = .{ .array = std.array_list.Managed(Value).init(allocator) };
        var ordinal: u64 = 0;
        for (writes.array.items) |write| {
            const tag = try text(write, "type");
            if (std.mem.eql(u8, tag, "conversation") or std.mem.eql(u8, tag, "entry") or std.mem.eql(u8, tag, "submission") or std.mem.eql(u8, tag, "document.retire")) {
                try main_writes.array.append(write);
                continue;
            }
            var file: []const u8 = undefined;
            var payload: Value = undefined;
            var operation: Value = undefined;
            if (std.mem.eql(u8, tag, "task")) {
                const record = try memory.field(write, "value");
                if (terminal(record)) {
                    try main_writes.array.append(write);
                    continue;
                }
                const id = try integer(record, "id");
                file = try sidecarName(allocator, "task", id);
                payload = try object(allocator, .{ .{ "type", Value{ .string = "task" } }, .{ "value", record } });
                operation = try object(allocator, .{ .{ "type", Value{ .string = "task.sidecar" } }, .{ "id", number(id) }, .{ "ordinal", number(ordinal) } });
            } else if (std.mem.eql(u8, tag, "document.create") or std.mem.eql(u8, tag, "document.change")) {
                const id = if (std.mem.eql(u8, tag, "document.create")) try integer(try memory.field(write, "record"), "id") else try integer(write, "id");
                file = try sidecarName(allocator, "doc", id);
                payload = try object(allocator, .{ .{ "type", Value{ .string = "document" } }, .{ "id", number(id) }, .{ "content", try memory.field(write, "content") } });
                operation = try object(allocator, .{ .{ "type", Value{ .string = tag } }, .{ if (std.mem.eql(u8, tag, "document.create")) "record" else "id", if (std.mem.eql(u8, tag, "document.create")) try memory.field(write, "record") else number(id) }, .{ "ordinal", number(ordinal) } });
            } else return error.UnknownStorageWrite;
            var index: usize = 0;
            while (index < sidecars.items.len and !std.mem.eql(u8, sidecars.items[index].file, file)) : (index += 1) {}
            if (index == sidecars.items.len) try sidecars.append(allocator, .{ .file = file });
            const record = try object(allocator, .{ .{ "format", number(1) }, .{ "type", Value{ .string = "record" } }, .{ "seq", number(seq) }, .{ "ordinal", number(ordinal) }, .{ "payload", payload } });
            try appendLine(allocator, &sidecars.items[index].content, record);
            ordinal += 1;
            try main_writes.array.append(operation);
        }
        const marker = try object(allocator, .{ .{ "format", number(1) }, .{ "type", Value{ .string = "commit" } }, .{ "seq", number(seq) }, .{ "writes", main_writes } });
        var encoded: std.ArrayList(u8) = .empty;
        try appendLine(allocator, &encoded, marker);
        _ = self;
        return encoded.items;
    }
    fn replacements(self: *Jsonl, allocator: std.mem.Allocator, writes: Value, sidecars: []const Sidecar) ![]Replacement {
        var created: std.AutoArrayHashMapUnmanaged(u64, void) = .empty;
        var retired: std.AutoArrayHashMapUnmanaged(u64, void) = .empty;
        var bases: std.AutoArrayHashMapUnmanaged(u64, void) = .empty;
        var final_tasks: std.AutoArrayHashMapUnmanaged(u64, Value) = .empty;
        for (writes.array.items) |write| {
            if (isType(write, "document.create")) {
                const record = try memory.field(write, "record");
                if (try currentOnly(record)) try created.put(allocator, try integer(record, "id"), {});
            }
            if (isType(write, "document.retire")) try retired.put(allocator, try integer(write, "id"), {});
            if (isType(write, "document.change") and std.mem.eql(u8, try text(try memory.field(write, "content"), "kind"), "base")) try bases.put(allocator, try integer(write, "id"), {});
            if (isType(write, "task")) {
                const record = try memory.field(write, "value");
                try final_tasks.put(allocator, try integer(record, "id"), record);
            }
        }
        var output: std.ArrayList(Replacement) = .empty;
        for (retired.keys()) |id| if (self.current_only.contains(id) or created.contains(id)) try output.append(allocator, .{ .file = try sidecarName(allocator, "doc", id), .content = "" });
        for (bases.keys()) |id| if ((self.current_only.contains(id) or created.contains(id)) and !retired.contains(id)) {
            const file = try sidecarName(allocator, "doc", id);
            for (sidecars) |sidecar| if (std.mem.eql(u8, sidecar.file, file)) {
                try output.append(allocator, .{ .file = file, .content = sidecar.content.items });
                break;
            };
        };
        var tasks = final_tasks.iterator();
        while (tasks.next()) |item| if (terminal(item.value_ptr.*)) {
            const file = try sidecarName(allocator, "task", item.key_ptr.*);
            var exists = self.live_tasks.contains(item.key_ptr.*);
            for (sidecars) |sidecar| if (std.mem.eql(u8, sidecar.file, file)) {
                exists = true;
                break;
            };
            if (exists) try output.append(allocator, .{ .file = file, .content = "" });
        };
        return output.items;
    }
    pub fn commitAt(self: *Jsonl, writes: Value, sequence: ?u64, context: types.Context) !u64 {
        try self.assertUsable();
        var prepared = try self.memory.prepare(writes, sequence);
        defer prepared.deinit();
        var arena = std.heap.ArenaAllocator.init(self.gpa);
        defer arena.deinit();
        const allocator = arena.allocator();
        var sidecars: std.ArrayList(Sidecar) = .empty;
        const marker = try self.encode(allocator, prepared.seq, prepared.writes, &sidecars);
        const replacements_list = try self.replacements(allocator, prepared.writes, sidecars.items);
        // All allocation and path preparation precedes any append.
        try self.current_only.ensureUnusedCapacity(self.gpa, @intCast(prepared.writes.array.items.len));
        try self.live_tasks.ensureUnusedCapacity(self.gpa, @intCast(prepared.writes.array.items.len));
        defer for (sidecars.items) |sidecar| if (sidecar.path) |path| self.fs.gpa.free(path);
        for (sidecars.items) |*sidecar| sidecar.path = try self.resolveFile(sidecar.file, context);
        for (sidecars.items) |sidecar| {
            const result = self.fs.appendFile(sidecar.path.?, sidecar.content.items, context) catch |err| {
                self.poisoned = true;
                return err;
            };
            if (result == .failure) return self.fileFailure(sidecar.file, result.failure, true);
        }
        if (self.options.fsync) for (sidecars.items) |sidecar| {
            const result = self.fs.flushFile(sidecar.path.?, context) catch |err| {
                self.poisoned = true;
                return err;
            };
            if (result == .failure) return self.fileFailure(sidecar.file, result.failure, true);
        };
        const result = self.fs.appendFile(self.main_path, marker, context) catch |err| {
            self.poisoned = true;
            return err;
        };
        if (result == .failure) return self.fileFailure("append to main.jsonl", result.failure, true);
        const seq = try prepared.apply();
        for (prepared.writes.array.items) |write| {
            if (isType(write, "document.create")) {
                const record = try memory.field(write, "record");
                if (try currentOnly(record)) self.current_only.putAssumeCapacity(try integer(record, "id"), {});
            }
            if (isType(write, "task")) {
                const record = try memory.field(write, "value");
                const id = try integer(record, "id");
                if (terminal(record)) {
                    _ = self.live_tasks.remove(id);
                } else self.live_tasks.putAssumeCapacity(id, {});
            }
        }
        self.reclaim(replacements_list, context);
        return seq;
    }
    pub fn commit(self: *Jsonl, writes: Value, context: types.Context) !u64 {
        return self.commitAt(writes, null, context);
    }
    fn reclaim(self: *Jsonl, replacements_list: []const Replacement, context: types.Context) void {
        if (replacements_list.len == 0) return;
        if (self.options.fsync) {
            var result = self.fs.flushFile(self.main_path, context) catch return;
            if (result == .failure) {
                result.failure.deinit(self.fs.gpa);
                return;
            }
        }
        for (replacements_list) |replacement| self.replace(replacement, context);
    }
    fn replace(self: *Jsonl, replacement: Replacement, context: types.Context) void {
        const path = self.resolveFile(replacement.file, context) catch return;
        defer self.fs.gpa.free(path);
        if (replacement.content.len == 0) {
            var result = self.fs.remove(path, .{ .force = true }, context) catch return;
            if (result == .failure) result.failure.deinit(self.fs.gpa);
            return;
        }
        const temporary = std.fmt.allocPrint(self.gpa, "{s}.reclaim", .{replacement.file}) catch return;
        defer self.gpa.free(temporary);
        const temporary_path = self.resolveFile(temporary, context) catch return;
        defer self.fs.gpa.free(temporary_path);
        var written = self.fs.writeFile(temporary_path, replacement.content, context) catch return;
        if (written == .failure) {
            written.failure.deinit(self.fs.gpa);
            return;
        }
        if (self.options.fsync) {
            var flushed = self.fs.flushFile(temporary_path, context) catch return;
            if (flushed == .failure) {
                flushed.failure.deinit(self.fs.gpa);
                return;
            }
        }
        var moved = self.fs.renameFile(temporary_path, path, context) catch return;
        if (moved == .failure) moved.failure.deinit(self.fs.gpa);
    }
    fn corrupt(self: *Jsonl, comptime format: []const u8, args: anytype) anyerror {
        return self.issue(error.JsonlCorruption, format, args);
    }
    fn parseLine(self: *Jsonl, allocator: std.mem.Allocator, bytes: []const u8, name: []const u8, line: u64, main: bool) !Value {
        if (!std.unicode.utf8ValidateSlice(bytes)) return self.corrupt("Invalid UTF-8 in complete {s} line {d}", .{ name, line });
        const text_bytes = if (std.mem.startsWith(u8, bytes, "\xef\xbb\xbf")) bytes[3..] else bytes;
        const value = json.parseLeaky(allocator, text_bytes) catch |err| {
            if (err == error.OutOfMemory) return err;
            return self.corrupt("Malformed complete {s} line {d}", .{ name, line });
        };
        if (value != .object or (integer(value, "format") catch 0) != 1 or (integer(value, "seq") catch 0) < 1) return if (main) self.corrupt("Invalid commit marker in {s} line {d}", .{ name, line }) else self.corrupt("Invalid sidecar record in {s} line {d}", .{ name, line });
        if (main) {
            const writes = json.get(value, "writes");
            if (!isType(value, "commit") or writes == null or writes.? != .array) return self.corrupt("Invalid commit marker in {s} line {d}", .{ name, line });
            for (writes.?.array.items) |write| try self.validateOperation(write, name, line);
        } else {
            const payload = json.get(value, "payload");
            if (!isType(value, "record") or payload == null or payload.? != .object or (integer(value, "ordinal") catch return self.corrupt("Invalid sidecar record in {s} line {d}", .{ name, line })) > memory.max_integer) return self.corrupt("Invalid sidecar record in {s} line {d}", .{ name, line });
            if (isType(payload.?, "task")) {
                const record = json.get(payload.?, "value");
                const state = if (record) |value_record| json.get(value_record, "state") else null;
                if (record == null or record.? != .object or (integer(record.?, "id") catch return self.corrupt("Invalid live task record in {s} line {d}", .{ name, line })) > memory.max_integer or state == null or state.? != .object or terminal(record.?)) return self.corrupt("Invalid live task record in {s} line {d}", .{ name, line });
            } else if (isType(payload.?, "document")) {
                _ = integer(payload.?, "id") catch return self.corrupt("Invalid document record in {s} line {d}", .{ name, line });
                const content = json.get(payload.?, "content") orelse return self.corrupt("Invalid document content in {s} line {d}", .{ name, line });
                const kind = text(content, "kind") catch return self.corrupt("Invalid document content in {s} line {d}", .{ name, line });
                const version = integer(content, "version") catch 0;
                const data = json.get(content, if (std.mem.eql(u8, kind, "base")) "value" else "ops");
                if (version < 1 or data == null or (if (std.mem.eql(u8, kind, "base")) data.? != .object else !std.mem.eql(u8, kind, "delta") or data.? != .array)) return self.corrupt("Invalid document content in {s} line {d}", .{ name, line });
            } else return self.corrupt("Unknown sidecar record type in {s} line {d}", .{ name, line });
        }
        return value;
    }
    fn validateOperation(self: *Jsonl, write: Value, name: []const u8, line: u64) !void {
        const tag = text(write, "type") catch return self.corrupt("Invalid write in {s} line {d}", .{ name, line });
        if (std.mem.eql(u8, tag, "conversation") or std.mem.eql(u8, tag, "entry") or std.mem.eql(u8, tag, "submission") or std.mem.eql(u8, tag, "task")) {
            const record = json.get(write, "value");
            if (record == null or record.? != .object) return self.corrupt("Invalid {s} write in {s} line {d}", .{ tag, name, line });
            _ = integer(record.?, "id") catch return self.corrupt("Invalid {s} write in {s} line {d}", .{ tag, name, line });
            if (std.mem.eql(u8, tag, "task") and !terminal(record.?)) return self.corrupt("Invalid terminal task write in {s} line {d}", .{ name, line });
            return;
        }
        if (std.mem.eql(u8, tag, "document.retire")) {
            _ = integer(write, "id") catch return self.corrupt("Invalid document retirement in {s} line {d}", .{ name, line });
            return;
        }
        if (!std.mem.eql(u8, tag, "task.sidecar") and !std.mem.eql(u8, tag, "document.create") and !std.mem.eql(u8, tag, "document.change")) return self.corrupt("Unknown write type in {s} line {d}", .{ name, line });
        _ = integer(write, "ordinal") catch return self.corrupt("Invalid {s} in {s} line {d}", .{ tag, name, line });
        if (std.mem.eql(u8, tag, "document.create")) {
            _ = integer(json.get(write, "record") orelse .null, "id") catch return self.corrupt("Invalid document creation in {s} line {d}", .{ name, line });
        } else {
            _ = integer(write, "id") catch return self.corrupt("Invalid {s} in {s} line {d}", .{ tag, name, line });
        }
    }
    fn readLines(self: *Jsonl, allocator: std.mem.Allocator, path: []const u8, name: []const u8, main: bool, context: types.Context) !ParsedFile {
        var read = try self.fs.readBinaryFile(path, context);
        if (read == .failure) {
            if (read.failure.code == .not_found) {
                read.failure.deinit(self.fs.gpa);
                return .{ .name = name, .path = path };
            }
            return self.fileFailure(name, read.failure, false);
        }
        defer self.fs.gpa.free(read.value);
        const bytes = read.value;
        var complete = bytes.len;
        if (complete > 0 and bytes[complete - 1] != '\n') {
            complete = if (std.mem.lastIndexOfScalar(u8, bytes, '\n')) |index| index + 1 else 0;
            const truncated = try self.fs.truncateFile(path, complete, context);
            if (truncated == .failure) return self.fileFailure("torn-line truncation", truncated.failure, false);
        }
        var parsed: ParsedFile = .{ .name = name, .path = path };
        var start: usize = 0;
        var line: u64 = 1;
        for (bytes[0..complete], 0..) |byte, index| if (byte == '\n') {
            try parsed.lines.append(allocator, .{ .value = try self.parseLine(allocator, bytes[start..index], name, line, main), .start = start });
            start = index + 1;
            line += 1;
        };
        return parsed;
    }
    fn confirmRecord(self: *Jsonl, index: *Index, key: Key, optional: bool) !?*Line {
        if (index.get(key)) |line| {
            if (line.confirmed) return self.corrupt("Sidecar record is confirmed more than once", .{});
            line.confirmed = true;
            return line;
        }
        if (optional) return null;
        return self.corrupt("Missing confirmed sidecar record {s} at sequence {d}", .{ key.file, key.seq });
    }
    fn recover(self: *Jsonl, context: types.Context) !void {
        var arena = std.heap.ArenaAllocator.init(self.gpa);
        defer arena.deinit();
        const allocator = arena.allocator();
        const main = try self.readLines(allocator, self.main_path, "main.jsonl", true, context);
        var previous: u64 = 0;
        for (main.lines.items) |line| {
            const seq = try integer(line.value, "seq");
            if (seq <= previous) return self.corrupt("Commit sequence does not strictly increase in main.jsonl", .{});
            previous = seq;
        }
        const listing = try self.fs.listDir(self.directory, context);
        if (listing == .failure) return self.fileFailure("directory listing", listing.failure, false);
        defer {
            for (listing.value) |*info| info.deinit(self.fs.gpa);
            self.fs.gpa.free(listing.value);
        }
        var files: std.ArrayList(ParsedFile) = .empty;
        for (listing.value) |info| if (info.kind == .file) {
            if (sidecarId(info.name, true) != null) {
                var removed = self.fs.remove(info.path, .{ .force = true }, context) catch continue;
                if (removed == .failure) removed.failure.deinit(self.fs.gpa);
            }
            if (sidecarId(info.name, false) != null) {
                const name = try allocator.dupe(u8, info.name);
                const path = try allocator.dupe(u8, info.path);
                try files.append(allocator, try self.readLines(allocator, path, name, false, context));
            }
        };
        std.mem.sort(ParsedFile, files.items, {}, compare);
        var records: Index = .empty;
        for (files.items) |file| {
            var seq: u64 = 0;
            var ordinal: u64 = 0;
            var first = true;
            for (file.lines.items) |line| {
                const next_seq = try integer(line.value, "seq");
                const next_ordinal = try integer(line.value, "ordinal");
                if (!first and (next_seq < seq or (next_seq == seq and next_ordinal <= ordinal))) return self.corrupt("Sidecar records are out of order in {s}", .{file.name});
                seq = next_seq;
                ordinal = next_ordinal;
                first = false;
            }
        }
        for (files.items) |*file| for (file.lines.items) |*line| try records.put(allocator, .{ .file = file.name, .seq = try integer(line.value, "seq"), .ordinal = try integer(line.value, "ordinal") }, line);
        var current: std.AutoHashMapUnmanaged(u64, void) = .empty;
        var retired: std.AutoHashMapUnmanaged(u64, void) = .empty;
        var final_tasks: std.AutoHashMapUnmanaged(u64, bool) = .empty;
        for (main.lines.items) |line| for ((try memory.field(line.value, "writes")).array.items) |write| {
            if (isType(write, "document.create")) {
                const record_value = try memory.field(write, "record");
                if (try currentOnly(record_value)) try current.put(allocator, try integer(record_value, "id"), {});
            }
            if (isType(write, "document.retire")) try retired.put(allocator, try integer(write, "id"), {});
            if (isType(write, "task")) try final_tasks.put(allocator, try integer(try memory.field(write, "value"), "id"), false);
            if (isType(write, "task.sidecar")) try final_tasks.put(allocator, try integer(write, "id"), true);
        };
        var latest_bases: std.AutoHashMapUnmanaged(u64, Key) = .empty;
        for (main.lines.items) |line| for ((try memory.field(line.value, "writes")).array.items) |write| {
            if (!isType(write, "document.create") and !isType(write, "document.change")) continue;
            const id = if (isType(write, "document.create")) try integer(try memory.field(write, "record"), "id") else try integer(write, "id");
            if (!current.contains(id)) continue;
            const key: Key = .{ .file = try sidecarName(allocator, "doc", id), .seq = try integer(line.value, "seq"), .ordinal = try integer(write, "ordinal") };
            if (records.get(key)) |record_line| {
                const payload = try memory.field(record_line.value, "payload");
                if (isType(payload, "document") and try integer(payload, "id") == id and std.mem.eql(u8, try text(try memory.field(payload, "content"), "kind"), "base")) try latest_bases.put(allocator, id, key);
            }
        };
        for (main.lines.items) |line| {
            const seq = try integer(line.value, "seq");
            var writes: Value = .{ .array = std.array_list.Managed(Value).init(allocator) };
            for ((try memory.field(line.value, "writes")).array.items) |write| {
                if (isType(write, "task.sidecar")) {
                    const id = try integer(write, "id");
                    const optional = !(final_tasks.get(id) orelse true);
                    const record_line = try self.confirmRecord(&records, .{ .file = try sidecarName(allocator, "task", id), .seq = seq, .ordinal = try integer(write, "ordinal") }, optional);
                    if (record_line) |record_value| {
                        const payload = try memory.field(record_value.value, "payload");
                        if (!isType(payload, "task") or try integer(try memory.field(payload, "value"), "id") != id) return self.corrupt("Confirmed task sidecar data does not match commit {d}", .{seq});
                        if (!optional) try writes.array.append(try object(allocator, .{ .{ "type", Value{ .string = "task" } }, .{ "value", try memory.field(payload, "value") } }));
                    }
                } else if (isType(write, "document.create") or isType(write, "document.change")) {
                    const create = isType(write, "document.create");
                    const id = if (create) try integer(try memory.field(write, "record"), "id") else try integer(write, "id");
                    const ordinal = try integer(write, "ordinal");
                    const base = latest_bases.get(id);
                    const reclaimed = (current.contains(id) and retired.contains(id)) or (base != null and (seq < base.?.seq or (seq == base.?.seq and ordinal < base.?.ordinal)));
                    const record_line = try self.confirmRecord(&records, .{ .file = try sidecarName(allocator, "doc", id), .seq = seq, .ordinal = ordinal }, reclaimed);
                    var content: ?Value = null;
                    if (record_line) |record_value| {
                        const payload = try memory.field(record_value.value, "payload");
                        if (!isType(payload, "document") or try integer(payload, "id") != id) return self.corrupt("Confirmed document sidecar data does not match commit {d}", .{seq});
                        content = try memory.field(payload, "content");
                    }
                    if (create) {
                        if (content != null and !std.mem.eql(u8, try text(content.?, "kind"), "base")) return self.corrupt("Document creation lacks a confirmed base in commit {d}", .{seq});
                        const empty = try object(allocator, .{ .{ "kind", Value{ .string = "base" } }, .{ "version", number(1) }, .{ "value", Value{ .object = .empty } } });
                        try writes.array.append(try object(allocator, .{ .{ "type", Value{ .string = "document.create" } }, .{ "record", try memory.field(write, "record") }, .{ "content", if (reclaimed or content == null) empty else content.? } }));
                    } else if (!reclaimed and content != null) try writes.array.append(try object(allocator, .{ .{ "type", Value{ .string = "document.change" } }, .{ "id", number(id) }, .{ "content", content.? } }));
                } else try writes.array.append(write);
            }
            var prepared = self.memory.prepare(writes, seq) catch |err| {
                if (err == error.OutOfMemory) return err;
                return self.corrupt("Invalid committed state at sequence {d}", .{seq});
            };
            defer prepared.deinit();
            _ = try prepared.apply();
        }
        var replacements_list: std.ArrayList(Replacement) = .empty;
        for (files.items) |file| {
            var unconfirmed: ?u64 = null;
            for (file.lines.items) |line| if (line.confirmed) {
                if (unconfirmed != null) return self.corrupt("Confirmed record follows an unconfirmed tail in {s}", .{file.name});
            } else if (unconfirmed == null) {
                unconfirmed = line.start;
            };
            if (unconfirmed) |offset| {
                const result = try self.fs.truncateFile(file.path, offset, context);
                if (result == .failure) return self.fileFailure("tail truncation", result.failure, false);
            }
            const id = sidecarId(file.name, false).?;
            const is_task = std.mem.startsWith(u8, file.name, "task-");
            const remove = (is_task and !(final_tasks.get(id) orelse true)) or (!is_task and current.contains(id) and retired.contains(id));
            const base = if (!is_task) latest_bases.get(id) else null;
            if (remove) {
                try replacements_list.append(allocator, .{ .file = file.name, .content = "" });
                continue;
            }
            if (base) |latest| {
                var retained: std.ArrayList(u8) = .empty;
                var count: usize = 0;
                var confirmed_count: usize = 0;
                for (file.lines.items) |line| if (line.confirmed) {
                    confirmed_count += 1;
                    const seq = try integer(line.value, "seq");
                    const ordinal = try integer(line.value, "ordinal");
                    if (seq > latest.seq or (seq == latest.seq and ordinal >= latest.ordinal)) {
                        count += 1;
                        try appendLine(allocator, &retained, line.value);
                    }
                };
                if (count < confirmed_count or count == 0) try replacements_list.append(allocator, .{ .file = file.name, .content = retained.items });
            }
        }
        self.reclaim(replacements_list.items, context);
        var ids = current.keyIterator();
        while (ids.next()) |id| try self.current_only.put(self.gpa, id.*, {});
        var tasks = final_tasks.iterator();
        while (tasks.next()) |item| if (item.value_ptr.*) try self.live_tasks.put(self.gpa, item.key_ptr.*, {});
    }
    pub fn mintId(self: *Jsonl) !u64 {
        try self.assertUsable();
        return self.memory.mintId();
    }
    pub fn snapshot(self: *Jsonl, gpa: std.mem.Allocator) !*memory.State {
        try self.assertUsable();
        return self.memory.state.duplicate(gpa);
    }
    pub fn readRecord(self: *Jsonl, gpa: std.mem.Allocator, id: u64) !?json.Owned {
        try self.assertUsable();
        return self.memory.readRecord(gpa, id);
    }
    pub fn readTableRecord(self: *Jsonl, gpa: std.mem.Allocator, table: memory.Table, id: u64) !?json.Owned {
        try self.assertUsable();
        const row = self.memory.state.rows.get(id) orelse return null;
        if (row.table != table) return null;
        return self.memory.readRecord(gpa, id);
    }
    pub fn readEntry(self: *Jsonl, gpa: std.mem.Allocator, id: u64, conversation_id: ?u64) !?json.Owned {
        try self.assertUsable();
        return query.entry(gpa, &self.memory, id, conversation_id);
    }
    pub fn readDocument(self: *Jsonl, gpa: std.mem.Allocator, id: u64, point: memory.Point) !?json.Owned {
        try self.assertUsable();
        return self.memory.readDocument(gpa, id, point);
    }
    pub fn scan(self: *Jsonl, gpa: std.mem.Allocator, parameters: query.Query) !json.Owned {
        try self.assertUsable();
        return query.scan(gpa, &self.memory, parameters);
    }
    pub fn scanConversations(self: *Jsonl, gpa: std.mem.Allocator, filters: Value, limit: u64, cursor: ?Value) !json.Owned {
        try self.assertUsable();
        return source_scan.scan(gpa, &self.memory, .conversation, filters, limit, cursor);
    }
    pub fn scanEntries(self: *Jsonl, gpa: std.mem.Allocator, filters: Value, limit: u64, cursor: ?Value) !json.Owned {
        try self.assertUsable();
        return source_scan.scan(gpa, &self.memory, .entry, filters, limit, cursor);
    }
    pub fn scanTasks(self: *Jsonl, gpa: std.mem.Allocator, filters: Value, limit: u64, cursor: ?Value) !json.Owned {
        try self.assertUsable();
        return source_scan.scan(gpa, &self.memory, .task, filters, limit, cursor);
    }
    pub fn scanSubmissions(self: *Jsonl, gpa: std.mem.Allocator, filters: Value, limit: u64, cursor: ?Value) !json.Owned {
        try self.assertUsable();
        return source_scan.scan(gpa, &self.memory, .submission, filters, limit, cursor);
    }
    pub fn scanDocuments(self: *Jsonl, gpa: std.mem.Allocator, filters: Value, limit: u64, cursor: ?Value) !json.Owned {
        try self.assertUsable();
        return source_scan.scan(gpa, &self.memory, .document, filters, limit, cursor);
    }
    pub fn findLatestHeadMarker(self: *Jsonl, gpa: std.mem.Allocator, conversation_id: u64, before: ?u64) !?json.Owned {
        try self.assertUsable();
        return source_scan.latestHead(gpa, &self.memory, conversation_id, before);
    }
    pub fn findDocument(self: *Jsonl, gpa: std.mem.Allocator, address: Value, point: memory.Point) !?json.Owned {
        try self.assertUsable();
        return query.findDocument(gpa, &self.memory, address, point);
    }
    pub fn conversation(self: *Jsonl, gpa: std.mem.Allocator, id: u64) !?json.Owned {
        return self.readTableRecord(gpa, .conversation, id);
    }
    pub fn task(self: *Jsonl, gpa: std.mem.Allocator, id: u64) !?json.Owned {
        return self.readTableRecord(gpa, .task, id);
    }
    pub fn submission(self: *Jsonl, gpa: std.mem.Allocator, id: u64) !?json.Owned {
        return self.readTableRecord(gpa, .submission, id);
    }
    pub fn document(self: *Jsonl, gpa: std.mem.Allocator, id: u64, point: memory.Point) !?json.Owned {
        return self.readDocument(gpa, id, point);
    }
    pub fn entry(self: *Jsonl, gpa: std.mem.Allocator, conversation_id: u64, id: u64) !?json.Owned {
        return self.readEntry(gpa, id, conversation_id);
    }
    pub fn submissionByRequest(self: *Jsonl, gpa: std.mem.Allocator, conversation_id: u64, request: []const u8) !?json.Owned {
        try self.assertUsable();
        const key = try memory.requestKey(gpa, number(conversation_id), .{ .string = request });
        defer gpa.free(key);
        const id = self.memory.state.submissionRequests.get(key) orelse return null;
        return self.memory.readRecord(gpa, id);
    }
};
