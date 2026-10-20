//! Actual native MapKVStore controls. No JS environment/interceptor is mocked.
//! The standard-container reference and new_handler adapter are test-only C++.
const std = @import("std");
const c = @cImport({
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("engine_abi.h");
    @cInclude("native_node_environment_map.h");
    @cInclude("native_node_environment_map_test_support.h");
});
const Map = c.PiNodeEnvironmentMap;
const memory_limit: usize = 32 * 1024 * 1024;
const long_key = "actual-native-key-" ++ ("k" ** 300);
const long_value = "actual-native-value-" ++ ("v" ** 600);

const Fixture = struct {
    runtime: ?*c.JSRuntime = null,
    context: ?*c.JSContext = null,
    memory: ?*anyopaque = null,
    map: ?*Map = null,
    before_map_used: usize = 0,

    fn init(self: *Fixture) !void {
        self.* = .{};
        self.runtime = c.pi_js_new_runtime(memory_limit, &self.memory) orelse return error.OutOfMemory;
        errdefer self.deinit();
        self.context = c.JS_NewContext(self.runtime.?) orelse return error.OutOfMemory;
        self.before_map_used = c.pi_js_native_memory_used(self.memory);
        self.map = c.pi_node_environment_map_create(self.memory, self.context) orelse return error.MissingNativeMap;
    }
    fn deinit(self: *Fixture) void {
        if (self.map) |map| { self.map = null; c.pi_node_environment_map_release(map); }
        if (self.context) |context| {
            self.context = null;
            while (c.JS_HasException(context))
                c.JS_FreeValue(context, c.JS_GetException(context));
            c.JS_FreeContext(context);
        }
        if (self.runtime) |runtime| { self.runtime = null; c.JS_FreeRuntime(runtime); }
        if (self.memory) |memory| { self.memory = null; c.pi_js_release_memory_owner(memory); }
    }
    fn used(self: *Fixture) usize { return c.pi_js_native_memory_used(self.memory); }
};
fn set(map: *Map, key: []const u8, value: []const u8) void {
    c.pi_node_environment_map_lock(map);
    defer c.pi_node_environment_map_unlock(map);
    c.pi_node_environment_map_set_locked(map, key.ptr, key.len, value.ptr, value.len);
}
fn remove(map: *Map, key: []const u8) void {
    c.pi_node_environment_map_lock(map);
    defer c.pi_node_environment_map_unlock(map);
    c.pi_node_environment_map_delete_locked(map, key.ptr, key.len);
}
const Capture = struct {
    bytes: [2048]u8 = undefined,
    length: usize = 0,
    calls: usize = 0,
    overflow: bool = false,
    memory: ?*anyopaque = null,
    used_during: usize = 0,
    fn receive(raw: ?*anyopaque, bytes: [*c]const u8, length: usize) callconv(.c) void {
        const self: *Capture = @ptrCast(@alignCast(raw.?));
        self.calls += 1;
        if (self.memory != null) self.used_during = c.pi_js_native_memory_used(self.memory);
        if (length > self.bytes.len) { self.overflow = true; return; }
        self.length = length;
        @memcpy(self.bytes[0..length], bytes[0..length]);
    }
    fn expect(self: *const Capture, expected: []const u8) !void {
        try std.testing.expect(!self.overflow);
        try std.testing.expectEqual(@as(usize, 1), self.calls);
        try std.testing.expectEqualStrings(expected, self.bytes[0..self.length]);
    }
};
fn get(map: *Map, key: [*:0]const u8, expected: []const u8) !void {
    var captured: Capture = .{};
    try std.testing.expectEqual(@as(c_int, 1),
        c.pi_node_environment_map_get(map, key, Capture.receive, &captured));
    try captured.expect(expected);
}
const KeyList = struct {
    bytes: [8192]u8 = undefined,
    length: usize = 0,
    count: usize = 0,
    declared_count: ?usize = null,
    overflow: bool = false,
    release_map: ?*Map = null,
    fn append(self: *KeyList, bytes: []const u8) void {
        if (bytes.len > std.math.maxInt(u32) or self.length + 4 + bytes.len > self.bytes.len) {
            self.overflow = true; return;
        }
        const n: u32 = @intCast(bytes.len);
        for (0..4) |i| self.bytes[self.length + i] = @truncate(n >> @intCast(i * 8));
        self.length += 4;
        @memcpy(self.bytes[self.length..][0..bytes.len], bytes);
        self.length += bytes.len;
        self.count += 1;
    }
    fn reference(raw: ?*anyopaque, bytes: [*c]const u8, length: usize) callconv(.c) void {
        const self: *KeyList = @ptrCast(@alignCast(raw.?));
        self.append(bytes[0..length]);
    }
    fn native(raw: ?*anyopaque, keys: ?*c.PiNodeEnvironmentKeys) callconv(.c) void {
        const self: *KeyList = @ptrCast(@alignCast(raw.?));
        self.declared_count = c.pi_node_environment_keys_count(keys);
        if (self.release_map) |map| {
            self.release_map = null;
            c.pi_node_environment_map_release(map);
        }
        while (true) {
            var bytes: [*c]const u8 = null;
            var length: usize = 0;
            if (c.pi_node_environment_keys_next(keys, &bytes, &length) == 0) break;
            self.append(bytes[0..length]);
        }
    }
    fn check(self: *const KeyList) !void {
        try std.testing.expect(!self.overflow);
        if (self.declared_count) |count| try std.testing.expectEqual(count, self.count);
    }
};
const Operation = struct {
    map: *Map,
    mode: enum { read, read_js, query, replace, erase },
    key: [*:0]const u8,
    key_length: usize,
    value: []const u8 = "z",
    result: c_int = -99,
    captured: Capture = .{},
    fn run(raw: ?*anyopaque) callconv(.c) void {
        const self: *Operation = @ptrCast(@alignCast(raw.?));
        switch (self.mode) {
            .read => self.result = c.pi_node_environment_map_get(
                self.map, self.key, Capture.receive, &self.captured),
            .read_js => self.result = c.pi_node_environment_map_get_js(
                self.map, self.key, Capture.receive, &self.captured),
            .query => self.result = c.pi_node_environment_map_query(self.map, self.key),
            .replace => { set(self.map, self.key[0..self.key_length], self.value); self.result = 0; },
            .erase => { remove(self.map, self.key[0..self.key_length]); self.result = 0; },
        }
    }
};
fn retry(f: *Fixture, operation: *Operation) !c.PiEnvironmentRetryObservation {
    var observation: c.PiEnvironmentRetryObservation = std.mem.zeroes(c.PiEnvironmentRetryObservation);
    try std.testing.expectEqual(@as(c_int, 0),
        c.pi_environment_test_retry(f.memory, memory_limit, Operation.run, operation, &observation));
    return observation;
}

test "native environment map starts empty without exposing a detached key snapshot" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    var captured: Capture = .{};
    try std.testing.expectEqual(@as(c_int, 0),
        c.pi_node_environment_map_get(f.map.?, "missing", Capture.receive, &captured));
    try std.testing.expectEqual(@as(usize, 0), captured.calls);
    try std.testing.expectEqual(@as(i32, -1), c.pi_node_environment_map_query(f.map.?, "missing"));
    var keys: KeyList = .{};
    c.pi_node_environment_map_with_keys(f.map.?, KeyList.native, &keys);
    try keys.check();
    try std.testing.expectEqual(@as(usize, 0), keys.count);
}

test "native environment map copies caller key and value storage before publication" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    var key = "alpha".*;
    var value = "original".*;
    set(f.map.?, &key, &value);
    @memset(&key, 'x'); @memset(&value, 'y');
    try get(f.map.?, "alpha", "original");
    try std.testing.expectEqual(@as(i32, -1), c.pi_node_environment_map_query(f.map.?, "xxxxx"));
    set(f.map.?, "alpha", "replacement");
    try get(f.map.?, "alpha", "replacement");
}

test "native environment map replacement constructs the original long temporary key" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    set(f.map.?, long_key, "x");
    const before = f.used();
    var operation: Operation = .{ .map = f.map.?, .mode = .replace, .key = long_key, .key_length = long_key.len };
    const observed = try retry(&f, &operation);
    try std.testing.expectEqual(@as(usize, 1), observed.calls);
    try std.testing.expectEqual(memory_limit, observed.first_used);
    try std.testing.expectEqual(before, f.used());
    try get(f.map.?, long_key, "z");
}

test "native environment map Get constructs and retires a long C string lookup key" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    set(f.map.?, long_key, "present");
    const before = f.used();
    var operation: Operation = .{ .map = f.map.?, .mode = .read, .key = long_key, .key_length = long_key.len };
    const observed = try retry(&f, &operation);
    try std.testing.expectEqual(@as(usize, 1), observed.calls);
    try std.testing.expectEqual(@as(c_int, 1), operation.result);
    try operation.captured.expect("present");
    try std.testing.expectEqual(before, f.used());
}

test "native environment map Query constructs the same real temporary even for an absent key" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const before = f.used();
    var operation: Operation = .{ .map = f.map.?, .mode = .query, .key = long_key, .key_length = long_key.len };
    const observed = try retry(&f, &operation);
    try std.testing.expectEqual(@as(usize, 1), observed.calls);
    try std.testing.expectEqual(@as(i32, -1), operation.result);
    try std.testing.expectEqual(before, f.used());
}

const Reentry = struct {
    map: *Map,
    captured: Capture = .{},
    fn receive(raw: ?*anyopaque, bytes: [*c]const u8, length: usize) callconv(.c) void {
        const self: *Reentry = @ptrCast(@alignCast(raw.?));
        set(self.map, "selected", "later");
        Capture.receive(&self.captured, bytes, length);
    }
};
test "native environment map Get unlocks before its owned value survives a real replacement" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    set(f.map.?, "selected", long_value);
    var observation: Reentry = .{ .map = f.map.? };
    try std.testing.expectEqual(@as(c_int, 1),
        c.pi_node_environment_map_get(f.map.?, "selected", Reentry.receive, &observation));
    try observation.captured.expect(long_value);
    try get(f.map.?, "selected", "later");
}

test "native environment map JS Get retains both original native string copies" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    set(f.map.?, "key", long_value);
    const before = f.used();
    var one: Capture = .{ .memory = f.memory };
    var two: Capture = .{ .memory = f.memory };
    try std.testing.expectEqual(@as(c_int, 1),
        c.pi_node_environment_map_get(f.map.?, "key", Capture.receive, &one));
    try std.testing.expectEqual(before, f.used());
    try std.testing.expectEqual(@as(c_int, 1),
        c.pi_node_environment_map_get_js(f.map.?, "key", Capture.receive, &two));
    try one.expect(long_value); try two.expect(long_value);
    try std.testing.expect(one.used_during > before);
    try std.testing.expectEqual(one.used_during - before, two.used_during - one.used_during);
    try std.testing.expectEqual(before, f.used());
}

test "native environment map missing Get still allocates and retires its long temporary key" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const before = f.used();
    var operation: Operation = .{ .map = f.map.?, .mode = .read, .key = long_key, .key_length = long_key.len };
    const observed = try retry(&f, &operation);
    try std.testing.expectEqual(@as(usize, 1), observed.calls);
    try std.testing.expectEqual(@as(c_int, 0), operation.result);
    try std.testing.expectEqual(@as(usize, 0), operation.captured.calls);
    try std.testing.expectEqual(before, f.used());
}

test "native environment map Get and Query use C prefixes while Set retains full spans" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    set(f.map.?, "prefix", "plain");
    set(f.map.?, "prefix\x00suffix", "full");
    try get(f.map.?, "prefix\x00suffix", "plain");
    try std.testing.expectEqual(@as(i32, 0), c.pi_node_environment_map_query(f.map.?, "prefix\x00suffix"));
    var actual: KeyList = .{};
    c.pi_node_environment_map_with_keys(f.map.?, KeyList.native, &actual);
    try actual.check(); try std.testing.expectEqual(@as(usize, 2), actual.count);
    const actions = [_]c.PiEnvironmentReferenceAction{
        .{ .kind = 0, .key = "prefix", .key_length = 6, .value = "plain", .value_length = 5 },
        .{ .kind = 0, .key = "prefix\x00suffix", .key_length = 13, .value = "full", .value_length = 4 },
    };
    var expected: KeyList = .{};
    c.pi_environment_test_reference_keys(&actions, actions.len, KeyList.reference, &expected);
    try expected.check();
    try std.testing.expectEqualSlices(u8, expected.bytes[0..expected.length], actual.bytes[0..actual.length]);
}

test "native environment map Delete selects the full span independently of C prefix lookups" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    set(f.map.?, "prefix", "plain"); set(f.map.?, "prefix\x00suffix", "full");
    remove(f.map.?, "prefix\x00suffix");
    try get(f.map.?, "prefix", "plain");
    var keys: KeyList = .{}; c.pi_node_environment_map_with_keys(f.map.?, KeyList.native, &keys);
    try keys.check(); try std.testing.expectEqual(@as(usize, 1), keys.count);
    remove(f.map.?, "prefix");
    try std.testing.expectEqual(@as(i32, -1), c.pi_node_environment_map_query(f.map.?, "prefix"));
}

test "native environment map uses the original case sensitive map on admitted platforms" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    set(f.map.?, "Path", "mixed"); set(f.map.?, "PATH", "upper");
    try get(f.map.?, "Path", "mixed"); try get(f.map.?, "PATH", "upper");
    try std.testing.expectEqual(@as(i32, -1), c.pi_node_environment_map_query(f.map.?, "path"));
    remove(f.map.?, "PATH"); try get(f.map.?, "Path", "mixed");
}

test "native environment map enumeration follows the actual original standard container after growth and erase" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    var names: [48][32]u8 = undefined;
    var actions: [58]c.PiEnvironmentReferenceAction = undefined;
    var count: usize = 0;
    for (&names, 0..) |*name, i| {
        const key = try std.fmt.bufPrint(name, "key-{d}-suffix", .{i});
        set(f.map.?, key, "value");
        actions[count] = .{ .kind = 0, .key = key.ptr, .key_length = key.len, .value = "value", .value_length = 5 };
        count += 1;
    }
    for (0..5) |i| {
        const key = actions[i * 3].key[0..actions[i * 3].key_length];
        remove(f.map.?, key);
        actions[count] = .{ .kind = 1, .key = key.ptr, .key_length = key.len, .value = null, .value_length = 0 };
        count += 1;
    }
    for (0..5) |i| {
        const key = actions[i * 3].key[0..actions[i * 3].key_length];
        set(f.map.?, key, "new");
        actions[count] = .{ .kind = 0, .key = key.ptr, .key_length = key.len, .value = "new", .value_length = 3 };
        count += 1;
    }
    var actual: KeyList = .{}; var expected: KeyList = .{};
    c.pi_node_environment_map_with_keys(f.map.?, KeyList.native, &actual);
    c.pi_environment_test_reference_keys(&actions, count, KeyList.reference, &expected);
    try actual.check(); try expected.check();
    try std.testing.expectEqual(@as(usize, 48), actual.count);
    try std.testing.expectEqualSlices(u8, expected.bytes[0..expected.length], actual.bytes[0..actual.length]);
}

test "native environment map Clone copies actual entries before independent mutation" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    set(f.map.?, long_key, long_value);
    const copy = c.pi_node_environment_map_clone(f.map.?, f.memory, f.context) orelse return error.MissingNativeMap;
    defer c.pi_node_environment_map_release(copy);
    set(f.map.?, long_key, "changed");
    try get(copy, long_key, long_value);
    remove(copy, long_key);
    try get(f.map.?, long_key, "changed");
}

test "native environment map enumeration retains its native owner after caller release" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    set(f.map.?, "one", "1"); set(f.map.?, "two", "2");
    const map = f.map.?; f.map = null;
    var keys: KeyList = .{ .release_map = map };
    defer if (keys.release_map) |unreleased| c.pi_node_environment_map_release(unreleased);
    c.pi_node_environment_map_with_keys(map, KeyList.native, &keys);
    // The adapter released the caller entitlement while the native guard held
    // the real mutex; no borrowed Keys or key span survives this return.
    try keys.check(); try std.testing.expectEqual(@as(usize, 2), keys.count);
    try std.testing.expect(keys.release_map == null);
    try std.testing.expectEqual(f.before_map_used, f.used());
}

test "native environment map mutation guard independently retains the live native table" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const map = f.map.?; f.map = null;
    c.pi_node_environment_map_lock(map);
    c.pi_node_environment_map_release(map);
    c.pi_node_environment_map_set_locked(map, long_key, long_key.len, long_value, long_value.len);
    c.pi_node_environment_map_delete_locked(map, long_key, long_key.len);
    c.pi_node_environment_map_unlock(map);
    try std.testing.expectEqual(f.before_map_used, f.used());
}

test "native environment map retained store survives full runtime and caller domain retirement" {
    const owners = c.pi_js_native_memory_owners();
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const map = f.map.?; c.pi_node_environment_map_retain(map);
    defer c.pi_node_environment_map_release(map);
    set(map, long_key, long_value);
    f.deinit();
    try std.testing.expectEqual(owners + 1, c.pi_js_native_memory_owners());
    try get(map, long_key, long_value);
    set(map, "after", "runtime");
    try get(map, "after", "runtime");
}

const Worker = struct {
    map: *Map,
    key: [*:0]const u8,
    proceed: std.atomic.Value(bool) = .init(false),
    observed: bool = false,
    fn run(self: *Worker) void {
        while (!self.proceed.load(.acquire)) std.atomic.spinLoopHint();
        var success = true;
        for (0..100) |_| {
            set(self.map, std.mem.span(self.key), "worker-value");
            var value: Capture = .{};
            if (c.pi_node_environment_map_get(self.map, self.key, Capture.receive, &value) != 1 or
                value.overflow or value.calls != 1 or
                !std.mem.eql(u8, value.bytes[0..value.length], "worker-value"))
                success = false;
        }
        self.observed = success;
        c.pi_node_environment_map_release(self.map);
    }
};
test "native environment map actual workers share a mutex and domain after runtime retirement" {
    const owners = c.pi_js_native_memory_owners();
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const map = f.map.?;
    c.pi_node_environment_map_retain(map);
    var first: Worker = .{ .map = map, .key = "first-worker" };
    var first_owned = true;
    defer if (first_owned) c.pi_node_environment_map_release(map);
    c.pi_node_environment_map_retain(map);
    var second: Worker = .{ .map = map, .key = "second-worker" };
    var second_owned = true;
    defer if (second_owned) c.pi_node_environment_map_release(map);
    const first_thread = try std.Thread.spawn(.{}, Worker.run, .{&first});
    first_owned = false;
    var first_joined = false;
    defer { if (!first_joined) { first.proceed.store(true, .release); first_thread.join(); } }
    const second_thread = try std.Thread.spawn(.{}, Worker.run, .{&second});
    second_owned = false;
    var second_joined = false;
    defer { if (!second_joined) { second.proceed.store(true, .release); second_thread.join(); } }
    f.deinit();
    try std.testing.expectEqual(owners + 1, c.pi_js_native_memory_owners());
    first.proceed.store(true, .release); second.proceed.store(true, .release);
    first_thread.join(); first_joined = true;
    second_thread.join(); second_joined = true;
    try std.testing.expect(first.observed and second.observed);
    try std.testing.expectEqual(owners, c.pi_js_native_memory_owners());
}

test "native environment map Clone allocations belong to the actual destination domain" {
    const owners = c.pi_js_native_memory_owners();
    var first: Fixture = .{}; try first.init(); defer first.deinit();
    var second: Fixture = .{}; try second.init(); defer second.deinit();
    set(first.map.?, long_key, long_value);
    const clone = c.pi_node_environment_map_clone(first.map.?, second.memory, second.context) orelse return error.MissingNativeMap;
    defer c.pi_node_environment_map_release(clone);
    first.deinit();
    try std.testing.expectEqual(owners + 1, c.pi_js_native_memory_owners());
    try get(clone, long_key, long_value);
    set(clone, "later", "destination");
    try get(clone, "later", "destination");
}

test "native environment map empty keys are ignored but empty values remain real entries" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    set(f.map.?, "", "ignored"); set(f.map.?, "empty", "");
    try std.testing.expectEqual(@as(i32, -1), c.pi_node_environment_map_query(f.map.?, ""));
    try get(f.map.?, "empty", "");
    var keys: KeyList = .{}; c.pi_node_environment_map_with_keys(f.map.?, KeyList.native, &keys);
    try keys.check(); try std.testing.expectEqual(@as(usize, 1), keys.count);
}

test "native environment map native retry leaves actual pending and VM OOM occurrence untouched" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    set(f.map.?, long_key, "value");
    const reason = c.JS_NewError(f.context.?);
    defer c.JS_FreeValue(f.context.?, reason);
    try std.testing.expect(!c.JS_IsException(reason));
    _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, reason));
    const occurrence = c.JS_PiOutOfMemoryOccurrence(f.runtime.?);
    var operation: Operation = .{ .map = f.map.?, .mode = .read, .key = long_key, .key_length = long_key.len };
    const observed = try retry(&f, &operation);
    try std.testing.expectEqual(@as(usize, 1), observed.calls);
    try operation.captured.expect("value");
    try std.testing.expectEqual(occurrence, c.JS_PiOutOfMemoryOccurrence(f.runtime.?));
    try std.testing.expect(c.JS_HasException(f.context.?));
    const actual = c.JS_GetException(f.context.?); defer c.JS_FreeValue(f.context.?, actual);
    try std.testing.expect(c.JS_IsSameValue(f.context.?, reason, actual));
}

test "native environment map actual short string lookup needs no artificial heap allocation" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    set(f.map.?, "short", "small");
    const before = f.used();
    var operation: Operation = .{ .map = f.map.?, .mode = .read_js, .key = "short", .key_length = 5 };
    const observed = try retry(&f, &operation);
    try std.testing.expectEqual(@as(usize, 0), observed.calls);
    try operation.captured.expect("small");
    try std.testing.expectEqual(before, f.used());
}

test "native environment map Delete constructs its real long span temporary before erase" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    set(f.map.?, long_key, "value");
    var operation: Operation = .{ .map = f.map.?, .mode = .erase, .key = long_key, .key_length = long_key.len };
    const observed = try retry(&f, &operation);
    try std.testing.expectEqual(@as(usize, 1), observed.calls);
    try std.testing.expectEqual(@as(i32, -1), c.pi_node_environment_map_query(f.map.?, long_key));
}
