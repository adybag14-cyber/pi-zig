const std = @import("std");
const runtime_mod = @import("extensions/js_runtime.zig");
const Io = std.Io;

const Frontend = struct {
    io: Io,
    label: []const u8,
    calls: std.atomic.Value(usize) = .init(0),
    idle_done: Io.Event = .unset,
    idle_correct: std.atomic.Value(bool) = .init(false),
    fn request(raw: ?*anyopaque, gpa: std.mem.Allocator, method: []const u8, _: []const u8) ![]u8 {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        if (!std.mem.eql(u8, method, "input")) return error.UnexpectedServiceDialog;
        _ = self.calls.fetchAdd(1, .acq_rel);
        return std.json.Stringify.valueAlloc(gpa, self.label, .{});
    }
    fn action(raw: ?*anyopaque, _: std.mem.Allocator, method: []const u8, args: []const u8) !void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        if (std.mem.eql(u8, method, "notify")) {
            self.idle_correct.store(std.mem.indexOf(u8, args, "idle:A") != null, .release);
            self.idle_done.set(self.io);
        }
    }
    fn bridge(self: *@This()) runtime_mod.UiBridge {
        return .{ .context = self, .request_fn = request, .action_fn = action };
    }
};

test "native UI service process retains original bridge after Main completion rebinding and idle timer" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var inherited = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer inherited.deinit();
    const binary = inherited.get("PI_UI_SERVICE_TEST_BINARY") orelse return error.MissingNativeServiceFixtureBinary;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "service.mjs", .data = @embedFile("extensions/fixtures/main-ui-service-lifetime-6fb2e78.txt") });
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    const source = try std.fs.path.join(gpa, &.{ buffer[0..length], "service.mjs" });
    defer gpa.free(source);
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    try environment.put("PATH", std.fs.path.dirname(binary).?);
    try environment.put("HOME", buffer[0..length]);
    try environment.put("USERPROFILE", buffer[0..length]);
    try environment.put("PI_AGENT_DIR", buffer[0..length]);
    try environment.put("PI_OFFLINE", "1");
    if (inherited.get("SystemRoot")) |value| try environment.put("SystemRoot", value);
    var started = try runtime_mod.Runtime.startNativeGroup(gpa, io, &.{source}, .{ .executable = binary, .environ_map = &environment, .startup_context_json = "{\"hasUI\":true,\"mode\":\"interactive\"}" });
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    try started.runtime.setContextJson("{\"hasUI\":true,\"mode\":\"interactive\"}");
    var a: Frontend = .{ .io = io, .label = "A" };
    var b: Frontend = .{ .io = io, .label = "B" };
    started.runtime.setUiBridge(a.bridge());
    const capture = try started.runtime.invokeCommand("capture", "", "{}");
    defer gpa.free(capture);
    try std.testing.expect(std.mem.indexOf(u8, capture, "\"same\":true") != null);
    started.runtime.setUiBridge(b.bridge());
    const retained = try started.runtime.invokeCommand("later", "", "{}");
    defer gpa.free(retained);
    try std.testing.expect(std.mem.indexOf(u8, retained, "\"value\":\"A\"") != null);
    const fresh = try started.runtime.invokeCommand("fresh", "", "{}");
    defer gpa.free(fresh);
    try std.testing.expect(std.mem.indexOf(u8, fresh, "\"value\":\"B\"") != null);
    const scheduled = try started.runtime.invokeCommand("schedule", "", "{}");
    defer gpa.free(scheduled);
    try std.testing.expect(std.mem.indexOf(u8, scheduled, "\"scheduled\":true") != null);
    // No following ordinary request is sent to wake the VM or consume the UI
    // reply. Its persistent reader and idle owner pump must finish the timer.
    try a.idle_done.waitTimeout(io, .{ .duration = .{ .raw = .fromSeconds(5), .clock = .awake } });
    try std.testing.expect(a.idle_correct.load(.acquire));
    try std.testing.expectEqual(@as(usize, 2), a.calls.load(.acquire));
    try std.testing.expectEqual(@as(usize, 1), b.calls.load(.acquire));
}

test "native UI service process single abort preserves sibling catalog ACKs and raw frontend after extension removal" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var inherited = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer inherited.deinit();
    const binary = inherited.get("PI_UI_SERVICE_TEST_BINARY") orelse return error.MissingNativeServiceFixtureBinary;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "control.mjs", .data = @embedFile("extensions/fixtures/main-ui-service-control-6fb2e78.txt") });
    try tmp.dir.writeFile(io, .{ .sub_path = "siblings.mjs", .data = @embedFile("extensions/fixtures/main-ui-service-siblings-6fb2e78.txt") });
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    const control = try std.fs.path.join(gpa, &.{ buffer[0..length], "control.mjs" });
    defer gpa.free(control);
    const siblings = try std.fs.path.join(gpa, &.{ buffer[0..length], "siblings.mjs" });
    defer gpa.free(siblings);
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    try environment.put("PATH", std.fs.path.dirname(binary).?);
    try environment.put("HOME", buffer[0..length]);
    try environment.put("USERPROFILE", buffer[0..length]);
    try environment.put("PI_AGENT_DIR", buffer[0..length]);
    try environment.put("PI_OFFLINE", "1");
    if (inherited.get("SystemRoot")) |value| try environment.put("SystemRoot", value);
    var started = try runtime_mod.Runtime.startNativeGroup(gpa, io, &.{ control, siblings }, .{ .executable = binary, .environ_map = &environment, .startup_context_json = "{\"hasUI\":true,\"mode\":\"interactive\"}" });
    var runtime_open = true;
    defer if (runtime_open) started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    try started.runtime.setContextJson("{\"hasUI\":true,\"mode\":\"interactive\"}");
    const Held = struct {
        calls: std.atomic.Value(usize) = .init(0),
        both: Io.Event = .unset,
        first_canceled: Io.Event = .unset,
        ordinary_entered: Io.Event = .unset,
        ordinary_release: Io.Event = .unset,
        second_release: Io.Event = .unset,
        siblings_done: Io.Event = .unset,
        shutdown_entered: Io.Event = .unset,
        shutdown_release: Io.Event = .unset,
        shutdown_canceled: std.atomic.Value(usize) = .init(0),
        fn request(raw: ?*anyopaque, allocator: std.mem.Allocator, _: []const u8, args: []const u8) ![]u8 {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            var parsed = try std.json.parseFromSlice(std.json.Value, allocator, args, .{});
            defer parsed.deinit();
            const title = parsed.value.object.get("title").?.string;
            if (std.mem.eql(u8, title, "first") or std.mem.eql(u8, title, "second")) {
                if (self.calls.fetchAdd(1, .acq_rel) + 1 == 2) self.both.set(std.testing.io);
                if (std.mem.eql(u8, title, "first")) {
                    self.shutdown_release.wait(std.testing.io) catch |err| {
                        self.first_canceled.set(std.testing.io);
                        return err;
                    };
                    return error.FirstRequestWasNotCanceled;
                }
                try self.second_release.wait(std.testing.io);
                return allocator.dupe(u8, "\"second-result\"");
            }
            if (std.mem.eql(u8, title, "ordinary")) {
                self.ordinary_entered.set(std.testing.io);
                try self.ordinary_release.wait(std.testing.io);
                return allocator.dupe(u8, "\"ordinary-result\"");
            }
            if (std.mem.eql(u8, title, "shutdown")) {
                self.shutdown_entered.set(std.testing.io);
                self.shutdown_release.wait(std.testing.io) catch |err| {
                    _ = self.shutdown_canceled.fetchAdd(1, .acq_rel);
                    return err;
                };
                return error.ShutdownDidNotCancel;
            }
            if (std.mem.eql(u8, title, "after-remove")) return allocator.dupe(u8, "\"original-frontend\"");
            return error.UnexpectedServiceTitle;
        }
        fn action(raw: ?*anyopaque, _: std.mem.Allocator, method: []const u8, args: []const u8) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (std.mem.eql(u8, method, "notify") and std.mem.indexOf(u8, args, "siblings-done") != null) self.siblings_done.set(std.testing.io);
        }
    };
    var held: Held = .{};
    started.runtime.setUiBridge(.{ .context = &held, .request_fn = Held.request, .action_fn = Held.action });
    const captured = try started.runtime.invokeGroupRequest(2, "{\"kind\":\"command\",\"name\":\"capture-service\",\"rawArguments\":\"\",\"flags\":{}}", null);
    defer gpa.free(captured);
    const begun = try started.runtime.invokeGroupRequest(2, "{\"kind\":\"command\",\"name\":\"start-siblings\",\"rawArguments\":\"\",\"flags\":{}}", null);
    defer gpa.free(begun);
    const events = @import("test_support/event_wait.zig");
    try events.untilSet(io, &held.both, 5000);
    const canceled = try started.runtime.invokeCommand("abort-first", "", "{}");
    defer gpa.free(canceled);
    try events.untilSet(io, &held.first_canceled, 5000);
    try std.testing.expect(!held.siblings_done.isSet());
    const Pending = struct {
        runtime: *runtime_mod.Runtime,
        result: ?[]u8 = null,
        failure: ?anyerror = null,
        done: Io.Event = .unset,
        fn run(self: *@This()) void {
            defer self.done.set(std.testing.io);
            self.result = self.runtime.invokeCommand("ordinary-held", "", "{}") catch |err| {
                self.failure = err;
                return;
            };
        }
    };
    var pending: Pending = .{ .runtime = started.runtime };
    var invocation: Io.Group = .init;
    try invocation.concurrent(io, Pending.run, .{&pending});
    defer {
        held.ordinary_release.set(io);
        invocation.cancel(io);
        invocation.await(io) catch {};
        if (pending.result) |value| gpa.free(value);
    }
    try events.untilSet(io, &held.ordinary_entered, 5000);
    var catalog = try std.json.parseFromSlice(std.json.Value, gpa, "{\"owners\":[]}", .{});
    defer catalog.deinit();
    try started.runtime.admitNativeToolCatalog(catalog.value);
    var invalid = try std.json.parseFromSlice(std.json.Value, gpa, "{\"owners\":1}", .{});
    defer invalid.deinit();
    try std.testing.expectError(error.NativeCatalogRejected, started.runtime.admitNativeToolCatalog(invalid.value));
    try std.testing.expect(!pending.done.isSet());
    held.ordinary_release.set(io);
    try invocation.await(io);
    if (pending.failure) |err| return err;
    try std.testing.expect(std.mem.indexOf(u8, pending.result.?, "ordinary-result") != null);
    try std.testing.expect(!held.siblings_done.isSet());
    held.second_release.set(io);
    try events.untilSet(io, &held.siblings_done, 5000);
    const states = try started.runtime.invokeCommand("inspect-service", "", "{}");
    defer gpa.free(states);
    try std.testing.expect(std.mem.indexOf(u8, states, "\"first\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, states, "\"second\":\"second-result\"") != null);
    const removed = try started.runtime.invokeGroupRequest(1, "{\"kind\":\"group_remove_source\",\"ownerId\":2}", null);
    defer gpa.free(removed);
    const after = try started.runtime.invokeCommand("retained-after-remove", "", "{}");
    defer gpa.free(after);
    try std.testing.expect(std.mem.indexOf(u8, after, "original-frontend") != null);
    const shutdown = try started.runtime.invokeCommand("shutdown-held", "", "{}");
    defer gpa.free(shutdown);
    try events.untilSet(io, &held.shutdown_entered, 5000);
    started.runtime.deinit();
    runtime_open = false;
    try std.testing.expectEqual(@as(usize, 1), held.shutdown_canceled.load(.acquire));
}

test "native UI service process stale actual SDK event uses retained Main frontend without reviving SDK Pi" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var inherited = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer inherited.deinit();
    const binary = inherited.get("PI_UI_SERVICE_TEST_BINARY") orelse return error.MissingNativeServiceFixtureBinary;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "sdk-service.mjs", .data = @embedFile("extensions/fixtures/main-ui-service-stale-sdk-6fb2e78.txt") });
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    const source = try std.fs.path.join(gpa, &.{ buffer[0..length], "sdk-service.mjs" });
    defer gpa.free(source);
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    try environment.put("PATH", std.fs.path.dirname(binary).?);
    try environment.put("HOME", buffer[0..length]);
    try environment.put("USERPROFILE", buffer[0..length]);
    try environment.put("PI_AGENT_DIR", buffer[0..length]);
    try environment.put("PI_OFFLINE", "1");
    if (inherited.get("SystemRoot")) |value| try environment.put("SystemRoot", value);
    const context = try std.json.Stringify.valueAlloc(gpa, .{ .cwd = buffer[0..length], .hasUI = true, .mode = "interactive" }, .{});
    defer gpa.free(context);
    var started = try runtime_mod.Runtime.startNativeGroup(gpa, io, &.{source}, .{ .executable = binary, .environ_map = &environment, .startup_context_json = context });
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    try started.runtime.setContextJson(context);
    const Report = struct {
        done: Io.Event = .unset,
        correct: std.atomic.Value(bool) = .init(false),
        requests: std.atomic.Value(usize) = .init(0),
        fn request(raw: ?*anyopaque, allocator: std.mem.Allocator, method: []const u8, args: []const u8) ![]u8 {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (!std.mem.eql(u8, method, "input") or std.mem.indexOf(u8, args, "from-stale-sdk") == null) return error.UnexpectedStaleSdkDialog;
            _ = self.requests.fetchAdd(1, .acq_rel);
            return allocator.dupe(u8, "\"MainOriginal\"");
        }
        fn action(raw: ?*anyopaque, allocator: std.mem.Allocator, method: []const u8, args: []const u8) !void {
            if (!std.mem.eql(u8, method, "notify")) return;
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            var parsed = try std.json.parseFromSlice(std.json.Value, allocator, args, .{});
            defer parsed.deinit();
            const message = parsed.value.object.get("message") orelse return error.MissingStaleSdkReport;
            const prefix = "sdk-stale-report:";
            if (message != .string or !std.mem.startsWith(u8, message.string, prefix)) return;
            var report = try std.json.parseFromSlice(std.json.Value, allocator, message.string[prefix.len..], .{});
            defer report.deinit();
            const object = report.value.object;
            const stale = @import("extensions/native_context_lifetime.zig").default_message;
            const correct = !object.contains("ctxAllowed") and !object.contains("piBeforeAllowed") and !object.contains("piAfterAllowed") and
                std.mem.eql(u8, object.get("main").?.string, "MainOriginal") and std.mem.eql(u8, object.get("ctxError").?.string, stale) and
                std.mem.eql(u8, object.get("piBeforeError").?.string, stale) and std.mem.eql(u8, object.get("piAfterError").?.string, stale);
            self.correct.store(correct, .release);
            self.done.set(std.testing.io);
        }
    };
    var report: Report = .{};
    started.runtime.setUiBridge(.{ .context = &report, .request_fn = Report.request, .action_fn = Report.action });
    const scheduled = try started.runtime.invokeCommand("schedule-stale-sdk", "", "{}");
    defer gpa.free(scheduled);
    try std.testing.expect(std.mem.indexOf(u8, scheduled, "\"scheduled\":true") != null);
    // The original Main invocation has returned before the actual disposed
    // SDK event runs. Its successful UI await must keep SDK APIs denied.
    try @import("test_support/event_wait.zig").untilSet(io, &report.done, 5000);
    try std.testing.expect(report.correct.load(.acquire));
    try std.testing.expectEqual(@as(usize, 1), report.requests.load(.acquire));
}

test "native UI service process asynchronous custom factory render input and close preserve retained state" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var inherited = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer inherited.deinit();
    const binary = inherited.get("PI_UI_SERVICE_TEST_BINARY") orelse return error.MissingNativeServiceFixtureBinary;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "component.mjs", .data = @embedFile("extensions/fixtures/main-ui-service-component-6fb2e78.txt") });
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    const source = try std.fs.path.join(gpa, &.{ buffer[0..length], "component.mjs" });
    defer gpa.free(source);
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    try environment.put("PATH", std.fs.path.dirname(binary).?);
    try environment.put("HOME", buffer[0..length]);
    try environment.put("USERPROFILE", buffer[0..length]);
    try environment.put("PI_AGENT_DIR", buffer[0..length]);
    try environment.put("PI_OFFLINE", "1");
    if (inherited.get("SystemRoot")) |value| try environment.put("SystemRoot", value);
    const context = "{\"hasUI\":true,\"mode\":\"interactive\",\"width\":40,\"height\":15}";
    var started = try runtime_mod.Runtime.startNativeGroup(gpa, io, &.{source}, .{ .executable = binary, .environ_map = &environment, .startup_context_json = context });
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    try started.runtime.setContextJson(context);
    const components = @import("extensions/component_protocol.zig");
    const Driver = struct {
        scenes: std.atomic.Value(usize) = .init(0),
        closes: std.atomic.Value(usize) = .init(0),
        fn request(_: ?*anyopaque, _: std.mem.Allocator, _: []const u8, _: []const u8) ![]u8 {
            return error.UnexpectedStandardDialog;
        }
        fn action(_: ?*anyopaque, _: std.mem.Allocator, _: []const u8, _: []const u8) !void {}
        fn scene(raw: ?*anyopaque, received: components.Scene, queue: *components.ControlQueue) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            var owned = received;
            var consumed = false;
            defer if (consumed) owned.deinit();
            try std.testing.expectEqualStrings("retained-component:40", received.frame.lines[0]);
            if (self.scenes.fetchAdd(1, .acq_rel) == 0) {
                var control: components.Control = .{ .gpa = std.heap.page_allocator, .fence = received.fence, .kind = .{ .input = try std.heap.page_allocator.dupe(u8, "finish") } };
                var sent = false;
                defer if (!sent) control.deinit();
                try queue.send(control);
                sent = true;
            }
            consumed = true;
        }
        fn close(raw: ?*anyopaque, _: components.Fence) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            _ = self.closes.fetchAdd(1, .acq_rel);
        }
    };
    var driver: Driver = .{};
    started.runtime.setUiBridge(.{ .context = &driver, .request_fn = Driver.request, .action_fn = Driver.action, .component_scene_fn = Driver.scene, .component_close_fn = Driver.close });
    const capture = try started.runtime.invokeCommand("capture-component-ui", "", "{}");
    defer gpa.free(capture);
    for ([_][]const u8{ "normal", "input-error", "render-error" }) |mode| {
        driver.scenes.store(0, .release);
        driver.closes.store(0, .release);
        const result = try started.runtime.invokeCommand("retained-component", mode, "{}");
        defer gpa.free(result);
        try std.testing.expect(std.mem.indexOf(u8, result, "\"disposed\":1") != null);
        if (std.mem.eql(u8, mode, "normal")) {
            try std.testing.expect(std.mem.indexOf(u8, result, "component-result") != null);
            try std.testing.expect(driver.scenes.load(.acquire) >= 1);
        } else try std.testing.expect(std.mem.indexOf(u8, result, "\"original\":true") != null);
        try std.testing.expectEqual(@as(usize, 1), driver.closes.load(.acquire));
    }
}
