const std = @import("std");
const engine_mod = @import("extensions/engine.zig");
const delta = @import("extensions/native_durable_view_delta.zig");
const vm = @import("extensions/native_values.zig");
const json = @import("durable/backend/json.zig");
const c = engine_mod.c;
fn exercise(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const generation = engine.native_allocation_generation;
    return exerciseWithEngine(engine) catch |err| engine.nativeAllocationError(err, generation);
}
fn exerciseWithEngine(engine: *engine_mod.Engine) !void {
    const bytes = @embedFile("extensions/fixtures/durable-view-persistent-delta-original.json");
    const source = try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "actual-source-view-delta"));
    defer engine.freeValue(source);
    const rows = try vm.get(engine, source, "rows");
    defer engine.freeValue(rows);
    for (0..try vm.length(engine, rows)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
        defer engine.freeValue(row);
        const base = try vm.get(engine, row, "base");
        defer engine.freeValue(base);
        const operations = try vm.get(engine, row, "ops");
        defer engine.freeValue(operations);
        const before = try engine.stringify(base);
        defer engine.gpa.free(before);
        const result = try delta.apply(engine, base, operations);
        defer engine.freeValue(result);
        const actual_text = try engine.stringify(result);
        defer engine.gpa.free(actual_text);
        const expected = try vm.get(engine, row, "result");
        defer engine.freeValue(expected);
        const expected_text = try engine.stringify(expected);
        defer engine.gpa.free(expected_text);
        var actual = try json.Owned.parse(engine.gpa, actual_text);
        defer actual.deinit();
        var wanted = try json.Owned.parse(engine.gpa, expected_text);
        defer wanted.deinit();
        try std.testing.expect(json.equal(wanted.value, actual.value));
        const after = try engine.stringify(base);
        defer engine.gpa.free(after);
        try std.testing.expectEqualStrings(before, after);
        inline for (.{ .{ "conversation", "conversationShared" }, .{ "entries", "entriesShared" } }) |field| {
            const original = try vm.get(engine, base, field[0]);
            defer engine.freeValue(original);
            const next = try vm.get(engine, result, field[0]);
            defer engine.freeValue(next);
            const shared = try vm.get(engine, row, field[1]);
            defer engine.freeValue(shared);
            try std.testing.expectEqual(c.JS_ToBool(engine.context, shared) != 0, c.JS_IsStrictEqual(engine.context, original, next));
        }
    }
}
test "native durable view persistent operations match actual Chord source and retain untouched references" {
    try exercise(std.testing.allocator);
}
test "native durable view persistent operation allocations roll back without leaks" {
    var baseline = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    try exercise(baseline.allocator());
    for (0..baseline.alloc_index) |index| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = index });
        exercise(failing.allocator()) catch |err| {
            if (!failing.has_induced_failure) return err;
        };
        if (failing.allocated_bytes != failing.freed_bytes) {
            std.debug.print("View delta allocation {d}/{d}: {d}/{d} bytes\n", .{ index, baseline.alloc_index, failing.allocated_bytes, failing.freed_bytes });
            return error.MemoryLeakDetected;
        }
    }
}

fn exerciseMount(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const generation = engine.native_allocation_generation;
    return exerciseMountWithEngine(engine) catch |err| engine.nativeAllocationError(err, generation);
}
fn exerciseMountWithEngine(engine: *engine_mod.Engine) !void {
    try @import("extensions/abort_signal.zig").install(engine);
    const make = try engine.eval(@embedFile("extensions/fixtures/durable-view-advance-runtime.txt"), "actual-view-advance-fixture", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(make);
    var source = try json.Owned.parse(engine.gpa, @embedFile("extensions/fixtures/durable-view-advance-original.json"));
    defer source.deinit();
    for (source.value.object.get("rows").?.array.items) |row| {
        const scenario = row.object.get("scenario").?.string;
        const name = try engine.checked(c.JS_NewStringLen(engine.context, scenario.ptr, scenario.len));
        defer engine.freeValue(name);
        var arguments = [_]c.JSValue{name};
        const fixture = try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), 1, &arguments));
        defer engine.freeValue(fixture);
        var values = [_]c.JSValue{c.pi_js_undefined()} ** 4;
        defer for (values) |value| engine.freeValue(value);
        inline for (.{ "mount", "event", "context", "report" }, 0..) |key, index| values[index] = try vm.get(engine, fixture, key);
        try @import("extensions/native_durable_view_mount.zig").advance(engine, c.JS_NewInt32(engine.context, 1), values[0], values[1], values[2], values[3]);
        const inspected = try vm.invoke(engine, fixture, "inspect", &.{});
        defer engine.freeValue(inspected);
        const text = try engine.stringify(inspected);
        defer engine.gpa.free(text);
        var actual = try json.Owned.parse(engine.gpa, text);
        defer actual.deinit();
        if (!json.equal(row, actual.value)) std.debug.print("View mount {s}: {s}\n", .{ scenario, text });
        try std.testing.expect(json.equal(row, actual.value));
    }
}
test "native durable view revisions match Source resets incarnation changes and observer isolation" {
    try exerciseMount(std.testing.allocator);
}
test "native durable view mount fan-out releases every failed allocation" {
    var baseline = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    try exerciseMount(baseline.allocator());
    for (0..baseline.alloc_index) |index| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = index });
        exerciseMount(failing.allocator()) catch |err| {
            if (!failing.has_induced_failure) return err;
        };
        if (failing.allocated_bytes != failing.freed_bytes) {
            std.debug.print("View mount allocation {d}/{d}: {d}/{d} bytes\n", .{ index, baseline.alloc_index, failing.allocated_bytes, failing.freed_bytes });
            return error.MemoryLeakDetected;
        }
    }
}

test "native durable view public states hydrate and watches deliver committed exact frames" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/native_durable.zig").install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    const result = engine.evalModule(@embedFile("extensions/fixtures/durable-view-public-runtime.txt"), "native-public-conversation-view") catch |err| {
        std.debug.print("Public view {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "missing" });
        return err;
    };
    engine.freeValue(result);
    const normalized = try engine.eval("JSON.stringify(publicViewProof,(key,value)=>key==='sessionId'?'<session-id>':value)", "public-view-normalization", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(normalized);
    const text = try engine.toString(normalized);
    defer std.testing.allocator.free(text);
    var actual = try json.Owned.parse(std.testing.allocator, text);
    defer actual.deinit();
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-view-public-original.json"));
    defer source.deinit();
    if (!json.equal(source.value, actual.value)) std.debug.print("Public view actual: {s}\n", .{text});
    try std.testing.expect(json.equal(source.value, actual.value));
}

test "native durable view cancellation closure and listener failures match actual Source" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/native_durable.zig").install(engine);
    const result = engine.evalModule(@embedFile("extensions/fixtures/durable-view-lifecycle-runtime.txt"), "native-public-view-lifecycle") catch |err| {
        std.debug.print("View lifecycle {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "missing" });
        return err;
    };
    engine.freeValue(result);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const rows = try vm.get(engine, global, "publicViewLifecycleRows");
    defer engine.freeValue(rows);
    const text = try engine.stringify(rows);
    defer std.testing.allocator.free(text);
    var actual = try json.Owned.parse(std.testing.allocator, text);
    defer actual.deinit();
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-view-lifecycle-original.json"));
    defer source.deinit();
    if (!json.equal(source.value.object.get("rows").?, actual.value)) std.debug.print("View lifecycle actual: {s}\n", .{text});
    try std.testing.expect(json.equal(source.value.object.get("rows").?, actual.value));
}

test "native durable views reset remount cancellation and exact frame overflow match actual Source" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/native_durable.zig").install(engine);
    const result = engine.evalModule(@embedFile("extensions/fixtures/durable-view-revisions-runtime.txt"), "native-public-view-revisions") catch |err| {
        std.debug.print("View revisions {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "missing" });
        return err;
    };
    engine.freeValue(result);
    const normalized = try engine.eval("JSON.stringify(publicViewRevisionRows,(key,value)=>key==='sessionId'?'<session-id>':value)", "public-view-revision-normalization", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(normalized);
    const text = try engine.toString(normalized);
    defer std.testing.allocator.free(text);
    var actual = try json.Owned.parse(std.testing.allocator, text);
    defer actual.deinit();
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-view-revisions-original.json"));
    defer source.deinit();
    if (!json.equal(source.value.object.get("rows").?, actual.value)) std.debug.print("View revisions actual: {s}\n", .{text});
    try std.testing.expect(json.equal(source.value.object.get("rows").?, actual.value));
}

test "native durable view public task graph hydration ownership remount and closure match actual Source" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/native_durable.zig").install(engine);
    const result = engine.evalModule(@embedFile("extensions/fixtures/durable-task-graph-public-runtime.txt"), "native-public-task-graph") catch |err| {
        std.debug.print("Public task graph {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "missing" });
        return err;
    };
    engine.freeValue(result);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const proof = try vm.get(engine, global, "publicTaskGraphProof");
    defer engine.freeValue(proof);
    const text = try engine.stringify(proof);
    defer std.testing.allocator.free(text);
    var actual = try json.Owned.parse(std.testing.allocator, text);
    defer actual.deinit();
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-task-graph-public-original.json"));
    defer source.deinit();
    if (!json.equal(source.value.object.get("result").?, actual.value)) std.debug.print("Public task graph actual: {s}\n", .{text});
    try std.testing.expect(json.equal(source.value.object.get("result").?, actual.value));
}

fn exerciseGraph(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const generation = engine.native_allocation_generation;
    return exerciseGraphWithEngine(engine) catch |err| engine.nativeAllocationError(err, generation);
}
fn exerciseGraphWithEngine(engine: *engine_mod.Engine) !void {
    try @import("extensions/abort_signal.zig").install(engine);
    const make = try engine.eval(@embedFile("extensions/fixtures/durable-task-graph-runtime.txt"), "actual-task-graph-fixture", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(make);
    var source = try json.Owned.parse(engine.gpa, @embedFile("extensions/fixtures/durable-task-graph-original.json"));
    defer source.deinit();
    for (source.value.object.get("rows").?.array.items) |row| {
        const scenario = row.object.get("scenario").?.string;
        const name = try engine.checked(c.JS_NewStringLen(engine.context, scenario.ptr, scenario.len));
        defer engine.freeValue(name);
        var arguments = [_]c.JSValue{name};
        const fixture = try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), 1, &arguments));
        defer engine.freeValue(fixture);
        var values = [_]c.JSValue{c.pi_js_undefined()} ** 4;
        defer for (values) |value| engine.freeValue(value);
        inline for (.{ "mount", "event", "context", "report" }, 0..) |key, index| values[index] = try vm.get(engine, fixture, key);
        try @import("extensions/native_durable_task_graph.zig").advance(engine, values[0], values[1], values[2], values[3]);
        const inspected = try vm.invoke(engine, fixture, "inspect", &.{});
        defer engine.freeValue(inspected);
        const text = try engine.stringify(inspected);
        defer engine.gpa.free(text);
        var actual = try json.Owned.parse(engine.gpa, text);
        defer actual.deinit();
        if (!json.equal(row, actual.value)) std.debug.print("Task graph {s}: {s}\n", .{ scenario, text });
        try std.testing.expect(json.equal(row, actual.value));
    }
}
test "native durable view task graph transitions match actual Source with observer isolation" {
    try exerciseGraph(std.testing.allocator);
}
test "native durable view task graph allocations unwind every injected failure" {
    var baseline = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    try exerciseGraph(baseline.allocator());
    for (0..baseline.alloc_index) |index| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = index });
        exerciseGraph(failing.allocator()) catch |err| {
            if (!failing.has_induced_failure) return err;
        };
        try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
    }
}

fn exerciseEventProgress(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const generation = engine.native_allocation_generation;
    return exerciseEventProgressWithEngine(engine) catch |err| engine.nativeAllocationError(err, generation);
}
fn exerciseEventProgressWithEngine(engine: *engine_mod.Engine) !void {
    const progress = @import("extensions/native_durable_event_progress.zig");
    var scope: @import("extensions/native_durable_view_mount.zig").Scope = .{ .engine = engine };
    defer scope.deinit();
    const bytes = @embedFile("extensions/fixtures/durable-events-progress-original.json");
    const source = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "actual-event-progress")));
    const rows = try scope.get(source, "rows");
    for (0..try vm.length(engine, rows)) |index| {
        const row = try scope.item(rows, index);
        const kind = try engine.toString(try scope.get(row, "kind"));
        defer engine.gpa.free(kind);
        const operations = try scope.get(row, "ops");
        const result = if (std.mem.eql(u8, kind, "message")) try scope.own(try progress.messageChanges(engine, operations, try scope.get(row, "message"))) else blk: {
            const slot = try scope.get(row, "slot");
            const previous = try scope.get(row, "previous");
            inline for (.{ .{ "sharedDetails", "details" }, .{ "sharedDiagnostics", "diagnostics" } }) |field| {
                if (c.JS_ToBool(engine.context, try scope.get(row, field[0])) != 0) try @import("extensions/native_tool_info.zig").putData(engine, slot, field[1], c.JS_DupValue(engine.context, try scope.get(previous, field[1])));
            }
            const call = try scope.own(try progress.callOf(engine, slot));
            const actual_call = try engine.stringify(call);
            defer engine.gpa.free(actual_call);
            const wanted_call = try engine.stringify(try scope.get(row, "call"));
            defer engine.gpa.free(wanted_call);
            try std.testing.expectEqualStrings(wanted_call, actual_call);
            break :blk try scope.own(try progress.toolUpdate(engine, operations, try scope.get(row, "at"), slot, previous));
        };
        const actual_text = try engine.stringify(if (c.JS_IsUndefined(result)) c.pi_js_null() else result);
        defer engine.gpa.free(actual_text);
        const expected_text = try engine.stringify(try scope.get(row, "result"));
        defer engine.gpa.free(expected_text);
        var actual = try json.Owned.parse(engine.gpa, actual_text);
        defer actual.deinit();
        var expected = try json.Owned.parse(engine.gpa, expected_text);
        defer expected.deinit();
        if (!json.equal(expected.value, actual.value)) std.debug.print("Event progress row {d}: {s}\n", .{ index, actual_text });
        try std.testing.expect(json.equal(expected.value, actual.value));
    }
}
test "native durable view assistant and tool progress events match actual Source" {
    try exerciseEventProgress(std.testing.allocator);
}
test "native durable view progress event allocation failures unwind without leaks" {
    var baseline = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    try exerciseEventProgress(baseline.allocator());
    for (0..baseline.alloc_index) |index| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = index });
        exerciseEventProgress(failing.allocator()) catch |err| {
            if (!failing.has_induced_failure) return err;
        };
        try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
    }
}

fn exerciseProjectionAcquisition(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const generation = engine.native_allocation_generation;
    try @import("extensions/native_durable.zig").install(engine);
    const result = engine.evalModule(
        \\import{Harness,MemoryStorage,createRegistry,GenerationTask}from'@earendil-works/pi-durable';const harness=await Harness.open(new MemoryStorage(),{registry:createRegistry()},{});try{const root=await harness.root({});await root.commit(async tx=>{const task=await tx.createTask(GenerationTask,{},{ownership:{kind:'conversation'}});await tx.createConversation({ownership:{kind:'task',taskId:task}})},{});const first=await root.viewState({}),watch=await root.watch({}),second=await root.viewState({}),graph=await harness.taskGraph({}),graphWatch=await harness.watchTaskGraph({});const a=first.subscribe(()=>{}),b=second.subscribe(()=>{}),d=graph.subscribe(()=>{});watch.start(async()=>{});graphWatch.start(async()=>{});await watch.stop();await graphWatch.stop();a();b();d();first.dispose();second.dispose();graph.dispose();}finally{await harness.close({})}
    , "native-view-acquisition-allocation") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(result);
}

test "native durable view public mount acquisition shared observers and release unwind every allocation failure" {
    // Acquiring/releasing views never resumes the task scheduler. Counters
    // remain on this owner thread; no failing allocator crosses a worker.
    var baseline = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    try exerciseProjectionAcquisition(baseline.allocator());
    for (0..baseline.alloc_index) |index| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = index });
        exerciseProjectionAcquisition(failing.allocator()) catch |err| {
            if (!failing.has_induced_failure) return err;
        };
        if (failing.allocated_bytes != failing.freed_bytes) {
            std.debug.print("Public view acquisition {d}/{d}: {d}/{d} bytes\n", .{ index, baseline.alloc_index, failing.allocated_bytes, failing.freed_bytes });
            return error.MemoryLeakDetected;
        }
    }
}
