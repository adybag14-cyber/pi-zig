const std = @import("std");
const implementation = @import("durable/backend/jsonl.zig");
const json = implementation.json;
const local = @import("durable/execution_env.zig");
const observed = @import("durable/backend/jsonl_test_support.zig");
const remote = @import("env/remote_env.zig");
const connection = @import("env/connection.zig");
test "durable JSONL native format and reopen match independently captured latest original markers and sidecars" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    var env = try local.ExecutionEnv.init(gpa, io, .{ .cwd = buffer[0..length], .environ = &environ, .temp_dir = buffer[0..length] });
    defer env.deinit();
    var capture = try json.Owned.parse(gpa, @embedFile("durable/fixtures/jsonl-7fb59f9.json"));
    defer capture.deinit();
    const example = capture.value.object.get("cases").?.array.items[0];
    var store = try implementation.Jsonl.open(gpa, ".", &env, .{}, .{ .fsync = true });
    defer store.deinit();
    for (example.object.get("commits").?.array.items, example.object.get("seqs").?.array.items) |writes, seq| try std.testing.expectEqual(try json.asInteger(seq), try store.commit(writes, .{}));
    const files = example.object.get("files").?.object;
    var iterator = files.iterator();
    while (iterator.next()) |item| {
        const expected = try gpa.alloc(u8, item.value_ptr.string.len / 2);
        defer gpa.free(expected);
        _ = try std.fmt.hexToBytes(expected, item.value_ptr.string);
        const actual = try tmp.dir.readFileAlloc(io, item.key_ptr.*, gpa, .limited(1024 * 1024));
        defer gpa.free(actual);
        // Serialized number spelling can differ; physical line ordering and
        // complete decoded records must match the source byte capture.
        var wanted = std.mem.splitScalar(u8, expected, '\n');
        var found = std.mem.splitScalar(u8, actual, '\n');
        while (wanted.next()) |line| {
            const current = found.next() orelse return error.MissingNativeRecord;
            if (line.len == 0) {
                try std.testing.expectEqualStrings("", current);
                continue;
            }
            var first = try json.Owned.parse(gpa, line);
            defer first.deinit();
            var second = try json.Owned.parse(gpa, current);
            defer second.deinit();
            if (!json.equal(first.value, second.value)) std.debug.print("JSONL record differs {s}:\nexpected:{s}\nactual:{s}\n", .{ item.key_ptr.*, line, current });
            try std.testing.expect(json.equal(first.value, second.value));
        }
        try std.testing.expect(found.next() == null);
    }
    store.close();
    var reopened = try implementation.Jsonl.open(gpa, ".", &env, .{}, .{ .fsync = true });
    defer reopened.deinit();
    var document = (try reopened.readDocument(gpa, 4, .current)).?;
    defer document.deinit();
    try std.testing.expect(json.equal(example.object.get("document").?, document.value));
    var copied = (try reopened.readDocument(gpa, 5, .current)).?;
    defer copied.deinit();
    try std.testing.expect(json.equal(example.object.get("copy").?, copied.value));
    try std.testing.expectEqual(try json.asInteger(example.object.get("nextId").?), try reopened.mintId());
}
test "durable JSONL actual source publication ordering poisoned short writes and committed-marker recovery" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    var capture = try json.Owned.parse(gpa, @embedFile("durable/fixtures/jsonl-7fb59f9.json"));
    defer capture.deinit();
    const cases = capture.value.object.get("cases").?.array.items;
    for (cases[0..3], 0..) |example, index| {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const length = try tmp.dir.realPath(io, &buffer);
        var base = try local.ExecutionEnv.init(gpa, io, .{ .cwd = buffer[0..length], .environ = &environ, .temp_dir = buffer[0..length] });
        defer base.deinit();
        var fs = observed.Observed.init(&base);
        defer fs.deinit();
        var store = try implementation.Jsonl.open(gpa, ".", &fs, .{}, .{ .fsync = index == 0 });
        defer store.deinit();
        if (index == 0) {
            for (example.object.get("commits").?.array.items) |writes| {
                _ = try store.commit(writes, .{});
            }
            var reopened = try implementation.Jsonl.open(gpa, ".", &fs, .{}, .{ .fsync = true });
            defer reopened.deinit();
            const expected = example.object.get("operations").?.array.items;
            try std.testing.expectEqual(expected.len, fs.operations.items.len);
            for (expected, fs.operations.items) |wanted, actual| {
                const wanted_label = if (std.mem.startsWith(u8, wanted.string, "rename:")) wanted.string[0..std.mem.indexOfScalar(u8, wanted.string, '>').?] else wanted.string;
                try std.testing.expectEqualStrings(wanted_label, actual);
            }
        } else {
            var root = try json.Owned.parse(gpa, "[{\"type\":\"conversation\",\"value\":{\"id\":1}}]");
            defer root.deinit();
            _ = try store.commit(root.value, .{});
            fs.clear();
            fs.fault = .{ .operation = .append, .call = 1, .mode = if (index == 1) .short else .after };
            var owned = try json.Owned.parse(gpa, "[{\"type\":\"conversation\",\"value\":{\"id\":2}}]");
            defer owned.deinit();
            const writes = if (index == 1) example.object.get("failedCommit").? else owned.value;
            try std.testing.expectError(error.JsonlStoragePoisoned, store.commit(writes, .{}));
            try std.testing.expectError(error.JsonlStoragePoisoned, store.mintId());
            fs.fault = null;
            var reopened = try implementation.Jsonl.open(gpa, ".", &fs, .{}, .{});
            defer reopened.deinit();
            try std.testing.expectEqual(try json.asInteger(example.object.get("nextId").?), try reopened.mintId());
            if (index == 1) {
                try std.testing.expect((try reopened.readTableRecord(gpa, .task, 2)) == null);
                const bytes = try tmp.dir.readFileAlloc(io, "task-2.jsonl", gpa, .limited(1024 * 1024));
                defer gpa.free(bytes);
                try std.testing.expectEqual(@as(usize, 0), bytes.len);
            } else {
                var record = (try reopened.readTableRecord(gpa, .conversation, 2)).?;
                defer record.deinit();
                try std.testing.expect(json.equal(example.object.get("conversation").?, record.value));
            }
        }
    }
}
test "durable JSONL complete malformed UTF8 and JSON fail while an incomplete tail is truncated" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    var capture = try json.Owned.parse(gpa, @embedFile("durable/fixtures/jsonl-7fb59f9.json"));
    defer capture.deinit();
    for (capture.value.object.get("cases").?.array.items[3..]) |example| {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const length = try tmp.dir.realPath(io, &buffer);
        var env = try local.ExecutionEnv.init(gpa, io, .{ .cwd = buffer[0..length], .environ = &environ, .temp_dir = buffer[0..length] });
        defer env.deinit();
        const hex = example.object.get("input").?.string;
        const bytes = try gpa.alloc(u8, hex.len / 2);
        defer gpa.free(bytes);
        _ = try std.fmt.hexToBytes(bytes, hex);
        try tmp.dir.writeFile(io, .{ .sub_path = "main.jsonl", .data = bytes });
        if (std.mem.eql(u8, example.object.get("name").?.string, "torn-main")) {
            var store = try implementation.Jsonl.open(gpa, ".", &env, .{}, .{});
            defer store.deinit();
            const actual = try tmp.dir.readFileAlloc(io, "main.jsonl", gpa, .limited(1024));
            defer gpa.free(actual);
            try std.testing.expectEqual(@as(usize, 0), actual.len);
        } else try std.testing.expectError(error.JsonlCorruption, implementation.Jsonl.open(gpa, ".", &env, .{}, .{}));
    }
}
test "durable JSONL latest source order cursors fork visibility head lookup and detached pages match original captures" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    var env = try local.ExecutionEnv.init(gpa, io, .{ .cwd = buffer[0..length], .environ = &environ, .temp_dir = buffer[0..length] });
    defer env.deinit();
    var capture = try json.Owned.parse(gpa, @embedFile("durable/fixtures/jsonl-scans-7fb59f9.json"));
    defer capture.deinit();
    var store = try implementation.Jsonl.open(gpa, ".", &env, .{}, .{});
    defer store.deinit();
    for (capture.value.object.get("commits").?.array.items) |writes| {
        _ = try store.commit(writes, .{});
    }
    for (capture.value.object.get("reads").?.array.items) |record| {
        const method = record.object.get("method").?.string;
        const filters = record.object.get("query").?;
        const limit = try json.asInteger(record.object.get("limit").?);
        const cursor = record.object.get("cursor");
        const result = if (std.mem.eql(u8, method, "scanConversations")) store.scanConversations(gpa, filters, limit, cursor) else if (std.mem.eql(u8, method, "scanEntries")) store.scanEntries(gpa, filters, limit, cursor) else if (std.mem.eql(u8, method, "scanDocuments")) store.scanDocuments(gpa, filters, limit, cursor) else if (std.mem.eql(u8, method, "scanSubmissions")) store.scanSubmissions(gpa, filters, limit, cursor) else store.scanTasks(gpa, filters, limit, cursor);
        if (record.object.get("error")) |failure| {
            const message = failure.object.get("message").?.string;
            const expected = if (std.mem.startsWith(u8, message, "The cursor continues")) error.ScanCursorOrderMismatch else if (std.mem.startsWith(u8, message, "Invalid scan order")) error.InvalidScanOrder else error.InvalidStorageCursor;
            try std.testing.expectError(expected, result);
        } else {
            var page = try result;
            defer page.deinit();
            if (!json.equal(record.object.get("value").?, page.value)) {
                const actual = try json.stringify(gpa, page.value);
                defer gpa.free(actual);
                std.debug.print("Source scan {s} differs: {s}\n", .{ method, actual });
            }
            try std.testing.expect(json.equal(record.object.get("value").?, page.value));
        }
    }
    var head = (try store.findLatestHeadMarker(gpa, 3, null)).?;
    defer head.deinit();
    try std.testing.expect(json.equal(capture.value.object.get("head").?, head.value));
    var entry = (try store.readEntry(gpa, 10, 3)).?;
    defer entry.deinit();
    try std.testing.expect(json.equal(capture.value.object.get("entry").?, entry.value));
}
fn openAllocation(gpa: std.mem.Allocator, provider: *local.ExecutionEnv, path: []const u8) !void {
    var store = try implementation.Jsonl.open(gpa, path, provider, .{}, .{});
    defer store.deinit();
    var document = (try store.readDocument(gpa, 4, .current)).?;
    defer document.deinit();
}
fn commitAllocation(gpa: std.mem.Allocator, provider: *local.ExecutionEnv, path: []const u8, writes: json.Value) !void {
    var store = try implementation.Jsonl.open(gpa, path, provider, .{}, .{});
    defer store.deinit();
    _ = try store.commit(writes, .{});
}
test "durable JSONL staged publication and recovered arenas release on every induced allocation failure" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    var provider = try local.ExecutionEnv.init(gpa, io, .{ .cwd = buffer[0..length], .environ = &environ, .temp_dir = buffer[0..length] });
    defer provider.deinit();
    var capture = try json.Owned.parse(gpa, @embedFile("durable/fixtures/jsonl-7fb59f9.json"));
    defer capture.deinit();
    const example = capture.value.object.get("cases").?.array.items[0];
    {
        var store = try implementation.Jsonl.open(gpa, "recover", &provider, .{}, .{});
        defer store.deinit();
        for (example.object.get("commits").?.array.items) |writes| {
            _ = try store.commit(writes, .{});
        }
    }
    try std.testing.checkAllAllocationFailures(gpa, openAllocation, .{ &provider, "recover" });
    // Each preparation tries a fresh path; append starts only after all fallible
    // encoding/metadata staging, so retries need no destructive rollback.
    const Probe = struct {
        provider: *local.ExecutionEnv,
        writes: json.Value,
        next: usize = 0,
        fn run(allocator: std.mem.Allocator, self: *@This()) !void {
            const path = try std.fmt.allocPrint(std.testing.allocator, "allocation-{d}", .{self.next});
            defer std.testing.allocator.free(path);
            self.next += 1;
            try commitAllocation(allocator, self.provider, path, self.writes);
        }
    };
    var state: Probe = .{ .provider = &provider, .writes = example.object.get("commits").?.array.items[0] };
    try std.testing.checkAllAllocationFailures(gpa, Probe.run, .{&state});
}
test "durable JSONL supplied remote capability persists actual daemon files reopens and detaches committed records" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    const program = environ.get("PI_TEST_ENV_DAEMON") orelse return error.SkipZigTest;
    const client = try connection.Connection.start(gpa, io, &.{program}, 107);
    defer client.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    var provider = try remote.RemoteExecutionEnv.init(gpa, .{ .connection = .{ .native = client }, .id = "jsonl-remote", .cwd = buffer[0..length] });
    defer provider.deinit();
    var capture = try json.Owned.parse(gpa, @embedFile("durable/fixtures/jsonl-7fb59f9.json"));
    defer capture.deinit();
    const example = capture.value.object.get("cases").?.array.items[0];
    var store = try implementation.Jsonl.open(gpa, "remote-dir", &provider, .{}, .{ .fsync = true });
    defer store.deinit();
    for (example.object.get("commits").?.array.items) |writes| {
        _ = try store.commit(writes, .{});
    }
    var row = (try store.task(gpa, 2)).?;
    defer row.deinit();
    try row.value.object.put(row.arena.allocator(), "kind", .{ .string = "caller-mutated" });
    var unchanged = (try store.task(gpa, 2)).?;
    defer unchanged.deinit();
    try std.testing.expectEqualStrings("test.task", unchanged.value.object.get("kind").?.string);
    store.close();
    try std.testing.expectError(error.JsonlStorageClosed, store.mintId());
    var reopened = try implementation.Jsonl.open(gpa, "remote-dir", &provider, .{}, .{});
    defer reopened.deinit();
    var document = (try reopened.document(gpa, 4, .current)).?;
    defer document.deinit();
    try std.testing.expect(json.equal(example.object.get("document").?, document.value));
    const physical = try tmp.dir.openDir(io, "remote-dir", .{});
    defer physical.close(io);
    const marker = try physical.readFileAlloc(io, "main.jsonl", gpa, .limited(1024 * 1024));
    defer gpa.free(marker);
    try std.testing.expectEqual(@as(usize, 11), std.mem.count(u8, marker, "\n"));
}
test "durable JSONL submission request replacement and deletion retain exact source insertion semantics across reopen" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    var env = try local.ExecutionEnv.init(gpa, io, .{ .cwd = buffer[0..length], .environ = &environ, .temp_dir = buffer[0..length] });
    defer env.deinit();
    var capture = try json.Owned.parse(gpa, @embedFile("durable/fixtures/jsonl-submission-7fb59f9.json"));
    defer capture.deinit();
    var store = try implementation.Jsonl.open(gpa, ".", &env, .{}, .{});
    defer store.deinit();
    for (capture.value.object.get("commits").?.array.items, capture.value.object.get("reads").?.array.items) |writes, expected| {
        _ = try store.commit(writes, .{});
        for ([_][]const u8{ "shared", "moved" }) |request| {
            var actual = try store.submissionByRequest(gpa, 1, request);
            defer if (actual) |*row| row.deinit();
            const wanted = expected.object.get(request);
            try std.testing.expectEqual(wanted != null, actual != null);
            if (wanted) |value| try std.testing.expect(json.equal(value, actual.?.value));
        }
    }
    var reopened = try implementation.Jsonl.open(gpa, ".", &env, .{}, .{});
    defer reopened.deinit();
    try std.testing.expect((try reopened.submissionByRequest(gpa, 1, "shared")) == null);
    var moved = (try reopened.submissionByRequest(gpa, 1, "moved")).?;
    defer moved.deinit();
    try std.testing.expect(json.equal(capture.value.object.get("reopened").?.object.get("moved").?, moved.value));
}
test "durable JSONL requires confirmed history sidecars rejects sequence reuse and discards unconfirmed tails" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    var capture = try json.Owned.parse(gpa, @embedFile("durable/fixtures/jsonl-7fb59f9.json"));
    defer capture.deinit();
    const example = capture.value.object.get("cases").?.array.items[0];
    for (0..3) |scenario| {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const length = try tmp.dir.realPath(io, &buffer);
        var env = try local.ExecutionEnv.init(gpa, io, .{ .cwd = buffer[0..length], .environ = &environ, .temp_dir = buffer[0..length] });
        defer env.deinit();
        {
            var store = try implementation.Jsonl.open(gpa, ".", &env, .{}, .{});
            defer store.deinit();
            for (example.object.get("commits").?.array.items) |writes| {
                _ = try store.commit(writes, .{});
            }
        }
        if (scenario == 0) {
            try tmp.dir.deleteFile(io, "doc-4.jsonl");
            try std.testing.expectError(error.JsonlCorruption, implementation.Jsonl.open(gpa, ".", &env, .{}, .{}));
        } else if (scenario == 1) {
            const repeated = "{\"format\":1,\"type\":\"commit\",\"seq\":11,\"writes\":[]}\n";
            try std.testing.expect((try env.appendFile("main.jsonl", repeated, .{})) == .value);
            try std.testing.expectError(error.JsonlCorruption, implementation.Jsonl.open(gpa, ".", &env, .{}, .{}));
        } else {
            const pending = "{\"format\":1,\"type\":\"record\",\"seq\":12,\"ordinal\":0,\"payload\":{\"type\":\"document\",\"id\":4,\"content\":{\"kind\":\"base\",\"version\":1,\"value\":{\"orphan\":true}}}}\n";
            const original = try tmp.dir.readFileAlloc(io, "doc-4.jsonl", gpa, .limited(1024 * 1024));
            defer gpa.free(original);
            try std.testing.expect((try env.appendFile("doc-4.jsonl", pending, .{})) == .value);
            try tmp.dir.writeFile(io, .{ .sub_path = "doc-99.jsonl.reclaim", .data = "retry-maintenance" });
            var reopened = try implementation.Jsonl.open(gpa, ".", &env, .{}, .{});
            defer reopened.deinit();
            const retained = try tmp.dir.readFileAlloc(io, "doc-4.jsonl", gpa, .limited(1024 * 1024));
            defer gpa.free(retained);
            try std.testing.expectEqualSlices(u8, original, retained);
            try std.testing.expect(!(try env.exists("doc-99.jsonl.reclaim", .{})).value);
        }
    }
}
test "durable JSONL marker publication wins over failed best-effort reclamation and repairs on reopen" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    var base = try local.ExecutionEnv.init(gpa, io, .{ .cwd = buffer[0..length], .environ = &environ, .temp_dir = buffer[0..length] });
    defer base.deinit();
    var fs = observed.Observed.init(&base);
    defer fs.deinit();
    var writes = try json.Owned.parse(gpa, "[{\"type\":\"conversation\",\"value\":{\"id\":1}},{\"type\":\"document.create\",\"record\":{\"id\":2,\"kind\":\"latest\",\"scope\":{\"kind\":\"session\"}},\"content\":{\"kind\":\"base\",\"version\":1,\"value\":{\"n\":0}}}]");
    defer writes.deinit();
    var replacement = try json.Owned.parse(gpa, "[{\"type\":\"document.change\",\"id\":2,\"content\":{\"kind\":\"base\",\"version\":1,\"value\":{\"n\":1}}}]");
    defer replacement.deinit();
    var store = try implementation.Jsonl.open(gpa, ".", &fs, .{}, .{ .fsync = true });
    defer store.deinit();
    _ = try store.commit(writes.value, .{});
    fs.clear();
    fs.fault = .{ .operation = .rename, .call = 1, .mode = .before };
    try std.testing.expectEqual(@as(u64, 2), try store.commit(replacement.value, .{}));
    try std.testing.expect(!store.poisoned);
    fs.fault = null;
    var reopened = try implementation.Jsonl.open(gpa, ".", &fs, .{}, .{ .fsync = true });
    defer reopened.deinit();
    var document = (try reopened.document(gpa, 2, .current)).?;
    defer document.deinit();
    try std.testing.expectEqual(@as(u64, 1), try json.asInteger(document.value.object.get("value").?.object.get("n").?));
    const file = try tmp.dir.readFileAlloc(io, "doc-2.jsonl", gpa, .limited(1024 * 1024));
    defer gpa.free(file);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, file, "\n"));
    try std.testing.expect(!(try base.exists("doc-2.jsonl.reclaim", .{})).value);
}
