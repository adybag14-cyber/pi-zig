//! Additive actual-VM/SQLite controls; original25/four declarations untouched.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
const Roots = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const v = @import("extensions/native_chord_sqlite_node_values.zig");
const fnc = @import("extensions/native_node_function.zig");
fn noFs(_: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return error.MemoryCaseMustNotUseFilesystem; }
fn carriers(engine: *em.Engine, roots: *Roots) !struct { sqlite: c.JSValue, api: c.JSValue } {
    const sqlite = try roots.own(try @import("extensions/native_node_sqlite.zig").create(engine));
    const sentinel = try roots.own(try fnc.createArrow(engine, "mustNotUseFilesystem", 0, noFs, &.{}));
    const api = try roots.own(try @import("extensions/native_chord_sqlite_node.zig").create(engine, .{ .database_sync = try roots.get(sqlite, "DatabaseSync"), .mkdir = sentinel, .dirname = sentinel }));
    return .{ .sqlite = sqlite, .api = api };
}
fn clear(engine: *em.Engine) void {
    const old = engine.captured_exception; engine.captured_exception = null;
    if (old) |value| engine.freeValue(value);
    if (c.JS_HasException(engine.context)) engine.freeValue(c.JS_GetException(engine.context));
}
fn errorValue(engine: *em.Engine) !c.JSValue { return engine.checked(c.JS_NewError(engine.context)); }
const Pending = struct {
    var engine: ?*em.Engine = null;
    var first: c.JSValue = undefined;
    var second: c.JSValue = undefined;
    var keys: c.JSValue = undefined;
    var proto: c.JSValue = undefined;
    var failing: ?*std.testing.FailingAllocator = null;
    var armed_alloc: usize = 0;
    var armed_resize: usize = 0;
    var mode: enum { cleanup_result, number, keys, prototype } = .number;
    var returned_class: c.JSClassID = 0;
    var finalized: bool = false;
    var next_reads: usize = 0;
    var calls: usize = 0;
    var raw_first = false;
    var raw_cleanup = false;
    var raw_first_reason: ?c.JSValue = null;
    var raw_cleanup_reason: ?c.JSValue = null;
    fn arm() void {
        if (failing) |allocator| {
            armed_alloc = allocator.alloc_index; armed_resize = allocator.resize_index;
            allocator.fail_index = allocator.alloc_index; allocator.resize_fail_index = allocator.resize_index;
        }
    }
    fn disarm() void { if (failing) |allocator| { allocator.fail_index = std.math.maxInt(usize); allocator.resize_fail_index = std.math.maxInt(usize); } }
    fn poison(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
        calls += 1;
        const value = switch (mode) { .number => c.JS_NewInt32(context, 1), .keys => c.JS_DupValue(context, keys), .prototype => c.JS_DupValue(context, proto), .cleanup_result => c.JS_NewObjectClass(context, returned_class) };
        if (c.JS_IsException(value)) return value;
        arm();
        if (raw_first) {
            _ = engine.?.throwNativeOutOfMemory();
            const reason = c.JS_GetException(context);
            raw_first_reason = c.JS_DupValue(context, reason);
            _ = c.JS_Throw(context, reason);
        } else _ = c.JS_Throw(context, c.JS_DupValue(context, first));
        return value; // Genuine successful native return WITH actual pending.
    }
    fn next(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue { next_reads += 1; return c.JS_NewInt32(engine.?.context, 2); }
    fn finalizedResult(_: ?*c.JSRuntime, _: c.JSValue) callconv(.c) void {
        finalized = true;
        if (raw_cleanup) {
            _ = engine.?.throwNativeOutOfMemory();
            const reason = c.JS_GetException(engine.?.context);
            raw_cleanup_reason = c.JS_DupValue(engine.?.context, reason);
            _ = c.JS_Throw(engine.?.context, reason);
        } else _ = c.JS_Throw(engine.?.context, c.JS_DupValue(engine.?.context, second));
    }
};
fn pendingSetup(engine: *em.Engine, roots: *Roots, failing: *std.testing.FailingAllocator) !void {
    Pending.engine = engine; Pending.failing = failing; Pending.next_reads = 0; Pending.finalized = false; Pending.calls = 0;
    Pending.raw_first = false; Pending.raw_cleanup = false; Pending.raw_first_reason = null; Pending.raw_cleanup_reason = null;
    Pending.first = try roots.own(try errorValue(engine)); Pending.second = try roots.own(try errorValue(engine));
    Pending.keys = try roots.array(); try roots.index(Pending.keys, 0, try roots.text(":x")); try roots.index(Pending.keys, 1, try roots.text(":y"));
    Pending.proto = try roots.object();
    _ = c.JS_NewClassID(engine.runtime, &Pending.returned_class);
    const definition: c.JSClassDef = .{ .class_name = "Owned SQLite pending cleanup control", .finalizer = Pending.finalizedResult };
    if (c.JS_NewClass(engine.runtime, Pending.returned_class, &definition) < 0) return error.OutOfMemory;
}
fn getter(engine: *em.Engine, roots: *Roots, object: c.JSValue, name: [*:0]const u8, callback: *const c.JSCFunction) !void {
    const value = try roots.own(try engine.checked(c.JS_NewCFunction(engine.context, callback, "ownedPendingGetter", 0)));
    const atom = c.JS_NewAtom(engine.context, name); defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyGetSet(engine.context, object, atom, c.JS_DupValue(engine.context, value), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return @import("extensions/native_js_values.zig").capture(engine);
}
fn assertNoRootAllocation(failing: *std.testing.FailingAllocator) !void {
    try std.testing.expect(!failing.has_induced_failure);
    try std.testing.expectEqual(Pending.armed_alloc, failing.alloc_index);
    try std.testing.expectEqual(Pending.armed_resize, failing.resize_index);
}
test "native SQLite current pending wins returned finalizer before first root allocation" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try em.Engine.init(failing.allocator(), .{}); defer engine.deinit();
    var roots: Roots = .{ .engine = engine }; defer roots.deinit();
    try pendingSetup(engine, &roots, &failing); defer { Pending.disarm(); Pending.failing = null; }
    const object = try roots.object(); try getter(engine, &roots, object, "owned", Pending.poison);
    // The private scope starts empty: the old helper would attempt its first
    // GPA append before checking pending, hitting this real failing allocator.
    var scope: v.Scope = .{ .engine = engine }; defer scope.deinit();
    Pending.mode = .cleanup_result;
    const result = v.get(&scope, object, "owned"); Pending.disarm();
    try std.testing.expectError(error.JavaScriptException, result);
    try assertNoRootAllocation(&failing); try std.testing.expect(Pending.finalized);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, Pending.first, engine.captured_exception.?));
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    clear(engine);
}
test "native SQLite raw fresh native fatal beats ordinary cleanup and preserves first fatal across wrap" {
    inline for (.{ 0, 1, 2 }) |kind| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const engine = try em.Engine.init(failing.allocator(), .{}); defer engine.deinit();
        var roots: Roots = .{ .engine = engine }; defer roots.deinit();
        try pendingSetup(engine, &roots, &failing);
        defer {
            Pending.disarm(); Pending.failing = null;
            if (Pending.raw_first_reason) |reason| engine.freeValue(reason);
            if (Pending.raw_cleanup_reason) |reason| engine.freeValue(reason);
            Pending.raw_first_reason = null; Pending.raw_cleanup_reason = null;
        }
        const object = try roots.object(); try getter(engine, &roots, object, "owned", Pending.poison);
        var scope: v.Scope = .{ .engine = engine }; defer scope.deinit();
        Pending.mode = .cleanup_result; Pending.raw_cleanup = true; Pending.raw_first = kind != 0;
        if (kind == 2) engine.native_allocation_generation = std.math.maxInt(u64) - 1;
        const result = v.get(&scope, object, "owned"); Pending.disarm();
        try std.testing.expectError(error.JavaScriptException, result);
        try assertNoRootAllocation(&failing); try std.testing.expect(Pending.finalized);
        const expected = if (kind == 0) Pending.raw_cleanup_reason.? else Pending.raw_first_reason.?;
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, expected, engine.captured_exception.?));
        try std.testing.expect(c.JS_IsUncatchableError(expected));
        try std.testing.expect(c.pi_js_native_allocation_error_generation(expected) != 0);
        if (kind == 2) try std.testing.expectEqual(@as(u64, 1), engine.native_allocation_generation);
        clear(engine);
    }
}
test "native SQLite real named getter and ownKeys pending stop SQL and next getter" {
    inline for (.{ false, true }) |own_keys| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const engine = try em.Engine.init(failing.allocator(), .{}); defer engine.deinit();
        var roots: Roots = .{ .engine = engine }; defer roots.deinit();
        const modules = try carriers(engine, &roots); try pendingSetup(engine, &roots, &failing); defer { Pending.disarm(); Pending.failing = null; }
        const db_args = [_]c.JSValue{try roots.text(":memory:")};
        const db = try roots.own(try engine.checked(c.JS_CallConstructor(engine.context, try roots.get(modules.sqlite, "DatabaseSync"), db_args.len, @constCast(&db_args))));
        _ = try roots.invoke(db, "exec", &.{try roots.text("CREATE TABLE owned(x INTEGER,y INTEGER)")});
        const statement = try roots.invoke(db, "prepare", &.{try roots.text("INSERT INTO owned VALUES(:x,:y)")});
        const object = try roots.object();
        try getter(engine, &roots, object, ":x", Pending.poison); try getter(engine, &roots, object, ":y", Pending.next);
        var parameters = object;
        if (own_keys) {
            const handler = try roots.object(); try roots.put(handler, "ownKeys", try roots.own(try engine.checked(c.JS_NewCFunction(engine.context, Pending.poison, "ownedOwnKeys", 0))));
            const proxy_args = [_]c.JSValue{ object, handler };
            parameters = try roots.own(try engine.checked(c.JS_CallConstructor(engine.context, try roots.global("Proxy"), proxy_args.len, @constCast(&proxy_args))));
        }
        const run = try roots.get(statement, "run"); Pending.mode = if (own_keys) .keys else .number;
        var args = [_]c.JSValue{parameters};
        const result = c.JS_Call(engine.context, run, statement, args.len, &args); Pending.disarm(); defer engine.freeValue(result);
        try std.testing.expect(c.JS_IsException(result) and c.JS_HasException(engine.context));
        const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, Pending.first));
        try assertNoRootAllocation(&failing); try std.testing.expectEqual(@as(usize, 0), Pending.next_reads);
        clear(engine);
        const row = try roots.invoke(try roots.invoke(db, "prepare", &.{try roots.text("SELECT count(*) AS n FROM owned")}), "get", &.{});
        try std.testing.expect(roots.equal(try roots.get(row, "n"), c.JS_NewInt32(engine.context, 0)));
        _ = try roots.invoke(db, "close", &.{});
    }
}
test "native SQLite constructor prototype pending precedes database allocation and factory cache" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try em.Engine.init(failing.allocator(), .{}); defer engine.deinit();
    var roots: Roots = .{ .engine = engine }; defer roots.deinit();
    const modules = try carriers(engine, &roots); try pendingSetup(engine, &roots, &failing); defer { Pending.disarm(); Pending.failing = null; }
    const target = try roots.own(try engine.eval("(function OwnedNewTarget(){})", "actual-sqlite-new-target.js", c.JS_EVAL_TYPE_GLOBAL));
    const handler = try roots.object(); try roots.put(handler, "get", try roots.own(try engine.checked(c.JS_NewCFunction(engine.context, Pending.poison, "ownedPrototypeGet", 3))));
    const proxy_args = [_]c.JSValue{ target, handler };
    const proxy = try roots.own(try engine.checked(c.JS_CallConstructor(engine.context, try roots.global("Proxy"), proxy_args.len, @constCast(&proxy_args))));
    const constructor = try roots.get(modules.sqlite, "DatabaseSync"); var args = [_]c.JSValue{try roots.text(":memory:")};
    Pending.mode = .prototype;
    const result = c.JS_CallConstructor2(engine.context, constructor, proxy, args.len, &args); Pending.disarm(); defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsException(result) and c.JS_HasException(engine.context));
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, Pending.first)); try assertNoRootAllocation(&failing);
    clear(engine);
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, Pending.first));
    const cached = @import("extensions/native_node_sqlite.zig").create(engine);
    try std.testing.expectError(error.JavaScriptException, cached);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, engine.captured_exception.?, Pending.first));
    clear(engine);
}
test "native SQLite queue coercion pending stops before enqueue and real SQL" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try em.Engine.init(failing.allocator(), .{}); defer engine.deinit();
    var roots: Roots = .{ .engine = engine }; defer roots.deinit();
    const modules = try carriers(engine, &roots); try pendingSetup(engine, &roots, &failing); defer { Pending.disarm(); Pending.failing = null; }
    const args = [_]c.JSValue{try roots.text(":memory:")};
    const db = try roots.own(try engine.checked(c.JS_CallConstructor(engine.context, try roots.get(modules.sqlite, "DatabaseSync"), args.len, @constCast(&args))));
    _ = try roots.invoke(db, "exec", &.{try roots.text("CREATE TABLE owned(n INTEGER)")});
    const adapter_args = [_]c.JSValue{db}; const adapter = try roots.own(try engine.checked(c.JS_CallConstructor(engine.context, try roots.get(modules.api, "NodeSqliteDatabase"), adapter_args.len, @constCast(&adapter_args))));
    const access = try roots.get(adapter, "access"); const numeric = try roots.object();
    try roots.put(numeric, "valueOf", try roots.own(try engine.checked(c.JS_NewCFunction(engine.context, Pending.poison, "ownedPendingCoercion", 0))));
    try roots.set(access, "pending", numeric); const exec = try roots.get(adapter, "exec"); var sql = [_]c.JSValue{try roots.text("INSERT INTO owned VALUES(1)")};
    Pending.mode = .number;
    const result = c.JS_Call(engine.context, exec, adapter, sql.len, &sql); Pending.disarm(); defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsException(result) and c.JS_HasException(engine.context));
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, Pending.first)); try assertNoRootAllocation(&failing); try std.testing.expectEqual(@as(usize, 1), Pending.calls); clear(engine);
    const row = try roots.invoke(try roots.invoke(db, "prepare", &.{try roots.text("SELECT count(*) AS n FROM owned")}), "get", &.{});
    try std.testing.expect(roots.equal(try roots.get(row, "n"), c.JS_NewInt32(engine.context, 0)));
    _ = try roots.invoke(db, "close", &.{});
}
test "native SQLite All range exit resets genuine shared-table lock before another writer" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var roots: Roots = .{ .engine = engine }; defer roots.deinit(); const modules = try carriers(engine, &roots);
    const global = try roots.own(c.JS_GetGlobalObject(engine.context)); try roots.put(global, "actualSqlite", modules.sqlite);
    const pending = try engine.eval(
        "(async()=>{const uri='file:chord-sqlite-owned-all-reset?mode=memory&cache=shared';const a=new actualSqlite.DatabaseSync(uri),b=new actualSqlite.DatabaseSync(uri);try{" ++
        "a.exec('CREATE TABLE owned(n INTEGER)');a.exec('INSERT INTO owned VALUES(9007199254740993)');" ++
        "if(b.prepare('SELECT count(*) AS n FROM owned').get().n!==1)throw Error('Shared-cache visibility precondition failed');" ++
        "a.exec('BEGIN');a.prepare('SELECT count(*) AS n FROM owned').get();" ++
        "let blocked=false;try{b.exec('ALTER TABLE owned ADD COLUMN precondition TEXT')}catch(error){blocked=error.code==='ERR_SQLITE_ERROR'&&(error.errcode&255)===6}" ++
        "a.exec('ROLLBACK');if(!blocked)throw Error('Real shared-table lock precondition missing');" ++
        "const query=a.prepare('SELECT n FROM owned');let range=false;try{query.all()}catch(error){range=error.code==='ERR_OUT_OF_RANGE'}if(!range)throw Error('Actual range conversion did not fail');" ++
        "b.exec('ALTER TABLE owned ADD COLUMN after_reset TEXT');b.exec('INSERT INTO owned(n) VALUES(2)');" ++
        "if(b.prepare('SELECT count(*) AS n FROM owned').get().n!==2)throw Error('Writer after All range cleanup did not finish');" ++
        "}finally{a.close();b.close()}})()", "actual-sqlite-all-shared-lock.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(pending); const value = try engine.awaitValue(pending); defer engine.freeValue(value);
}
const Data = struct {
    var engine: ?*em.Engine = null;
    var last: ?c.JSValue = null;
    var tagged = true;
    var historical: ?c.JSValue = null;
    fn make(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
        const host = engine.?;
        const reason = if (historical) |old| c.JS_DupValue(context, old) else if (tagged) blk: { _ = host.throwNativeOutOfMemory(); break :blk c.JS_GetException(context); } else c.JS_NewError(context);
        if (c.JS_IsException(reason)) return reason;
        c.JS_SetUncatchableError(context, reason);
        if (last) |old| host.freeValue(old);
        last = c.JS_DupValue(context, reason);
        return reason; // Intentional rejected DATA, with no pending VM event.
    }
};
test "native Chord SQLite flagged rejected data rolls back closes and preserves source order" {
    inline for (.{ 0, 1, 2 }) |kind| {
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        var roots: Roots = .{ .engine = engine }; defer roots.deinit(); const modules = try carriers(engine, &roots);
        Data.engine = engine; Data.tagged = kind != 0; Data.last = null; Data.historical = null;
        if (kind == 2) { _ = engine.throwNativeOutOfMemory(); Data.historical = c.JS_GetException(engine.context); c.JS_SetUncatchableError(engine.context, Data.historical.?); }
        defer { if (Data.last) |last| engine.freeValue(last); if (Data.historical) |old| engine.freeValue(old); Data.last = null; Data.historical = null; Data.engine = null; }
        const observer = try roots.own(try engine.evalModule(@embedFile("../verification/chord-node-sqlite-c268-sourceonly-20261017/correction-observer.mjs"), "actual-chord-node-correction-observer.mjs"));
        const factory = try roots.own(try engine.checked(c.JS_NewCFunction(engine.context, Data.make, "makeRejectedData", 0)));
        const promise = try roots.call(try roots.get(observer, "observeCorrections"), c.pi_js_undefined(), &.{ modules.api, modules.sqlite, factory });
        const output = try roots.own(try engine.awaitValue(promise));
        const rows = try roots.get(output, "rows");
        const transaction_row = try roots.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, 0)));
        const transaction_value = try roots.get(transaction_row, "value");
        try std.testing.expect(roots.truthy(try roots.get(transaction_value, "same")));
        try std.testing.expect(!roots.truthy(try roots.get(transaction_value, "active")));
        try std.testing.expect(roots.equal(try roots.get(transaction_value, "n"), c.JS_NewInt32(engine.context, 0)));
        const config_row = try roots.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, 1)));
        const config_value = try roots.get(config_row, "value");
        try std.testing.expect(roots.truthy(try roots.get(config_value, "same")) and roots.truthy(try roots.get(config_value, "closed")));
        try std.testing.expect(roots.equal(try roots.get(config_value, "closeCalls"), c.JS_NewInt32(engine.context, 1)));
        const super_row = try roots.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, 2)));
        const super_value = try roots.get(super_row, "value");
        try std.testing.expect(roots.truthy(try roots.get(super_value, "database")) and roots.truthy(try roots.get(super_value, "statements")));
        try std.testing.expect(!roots.truthy(try roots.get(super_value, "wrongBase")));
        const queue_row = try roots.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, 3)));
        const queue_value = try roots.get(queue_row, "value");
        try std.testing.expect(roots.truthy(try roots.get(queue_value, "intrinsic")) and roots.truthy(try roots.get(queue_value, "tail")));
        try std.testing.expect(roots.equal(try roots.get(queue_value, "pending"), c.JS_NewInt32(engine.context, 0)));
        try std.testing.expect(Data.last != null and c.JS_IsUncatchableError(Data.last.?));
        try std.testing.expect((c.pi_js_native_allocation_error_generation(Data.last.?) != 0) == (kind != 0));
    }
}
fn noNewReason(_: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return error.JavaScriptException; }
const CallbackEvents = struct {
    var calls: usize = 0;
    fn ordinary(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
        calls += 1;
        return c.JS_NewInt32(engine.context, 7);
    }
    fn currentFatal(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
        calls += 1;
        _ = engine.checked(engine.throwNativeOutOfMemory()) catch {};
        c.JS_SetUncatchableError(engine.context, engine.captured_exception.?);
        // A genuine producer captured this event during this invocation. The
        // successful return must not erase it or turn it into ordinary DATA.
        return c.JS_NewInt32(engine.context, 7);
    }
};
const AllocatorCleanup = struct {
    fn fail(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
        var scope: v.Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
        // The scope owns the sole object reference. The actual allocator error
        // unwinds it, and its actual finalizer produces the first owned fatal B.
        _ = try scope.own(try engine.checked(c.JS_NewObjectClass(engine.context, Pending.returned_class)));
        Pending.arm();
        const allocation = try engine.gpa.alloc(u8, 1);
        engine.gpa.free(allocation);
        return error.ActualAllocatorFailureWasNotReached;
    }
};
test "native SQLite allocator unwind retains current cleanup fatal without replacement OOM" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try em.Engine.init(failing.allocator(), .{}); defer engine.deinit();
    var roots: Roots = .{ .engine = engine }; defer roots.deinit();
    try pendingSetup(engine, &roots, &failing);
    defer {
        Pending.disarm(); Pending.failing = null;
        if (Pending.raw_cleanup_reason) |reason| engine.freeValue(reason);
        Pending.raw_cleanup_reason = null;
    }
    Pending.raw_cleanup = true;
    const generation = engine.native_allocation_generation;
    const result = v.callback(AllocatorCleanup.fail)(engine, c.pi_js_undefined(), &.{}, &.{});
    Pending.disarm();
    try std.testing.expectError(error.JavaScriptException, result);
    try std.testing.expect(failing.has_induced_failure and Pending.finalized);
    try std.testing.expect(Pending.raw_cleanup_reason != null);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, Pending.raw_cleanup_reason.?, engine.captured_exception.?));
    try std.testing.expect(c.JS_IsUncatchableError(engine.captured_exception.?));
    try std.testing.expectEqual(generation + 1, engine.native_allocation_generation);
    try std.testing.expect(!c.JS_HasException(engine.context));
    clear(engine);
}
test "native SQLite callback separates historical flagged data from current producer events" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var roots: Roots = .{ .engine = engine }; defer roots.deinit();
    const old = try roots.own(try errorValue(engine)); c.JS_SetUncatchableError(engine.context, old);
    const first = try roots.own(try errorValue(engine));
    CallbackEvents.calls = 0;
    engine.captured_exception = c.JS_DupValue(engine.context, old);
    const ordinary = try v.callback(CallbackEvents.ordinary)(engine, c.pi_js_undefined(), &.{}, &.{});
    defer engine.freeValue(ordinary);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, ordinary, c.JS_NewInt32(engine.context, 7)));
    try std.testing.expectEqual(@as(usize, 1), CallbackEvents.calls);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, engine.captured_exception.?, old));
    // Actual pending wins over historical flagged capture, without running body.
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, first));
    try std.testing.expectError(error.JavaScriptException, v.callback(CallbackEvents.ordinary)(engine, c.pi_js_undefined(), &.{}, &.{}));
    try std.testing.expectEqual(@as(usize, 1), CallbackEvents.calls);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, engine.captured_exception.?, first));
    clear(engine);
    engine.captured_exception = c.JS_DupValue(engine.context, old);
    try std.testing.expectError(error.JavaScriptException, v.callback(CallbackEvents.currentFatal)(engine, c.pi_js_undefined(), &.{}, &.{}));
    try std.testing.expectEqual(@as(usize, 2), CallbackEvents.calls);
    const actual = engine.captured_exception.?;
    try std.testing.expect(c.JS_IsUncatchableError(actual));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(actual) != 0);
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, actual, old));
    clear(engine);
}
test "native SQLite scope cleanup promotes first actual fatal and retains it over later fatal" {
    inline for (.{ 0, 1, 2 }) |kind| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const engine = try em.Engine.init(failing.allocator(), .{}); defer engine.deinit();
        var roots: Roots = .{ .engine = engine }; defer roots.deinit();
        try pendingSetup(engine, &roots, &failing); defer { Pending.disarm(); Pending.failing = null; }
        if (kind != 0) c.JS_SetUncatchableError(engine.context, Pending.first);
        if (kind != 2) c.JS_SetUncatchableError(engine.context, Pending.second);
        var scope: v.Scope = .{ .engine = engine };
        _ = try scope.own(try engine.checked(c.JS_NewObjectClass(engine.context, Pending.returned_class)));
        scope.unwind = c.JS_DupValue(engine.context, Pending.first);
        scope.deinit();
        try std.testing.expect(Pending.finalized);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, engine.captured_exception.?, if (kind == 0) Pending.second else Pending.first));
        try std.testing.expect(c.JS_IsUncatchableError(engine.captured_exception.?));
        try std.testing.expect(!c.JS_HasException(engine.context));
        try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
        clear(engine);
    }
}
test "native SQLite local callback cannot rethrow an older capture as a new failure" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var roots: Roots = .{ .engine = engine }; defer roots.deinit();
    const old = try roots.own(try errorValue(engine));
    const function = try roots.own(try fnc.createMethod(engine, "missingCurrentReason", 0, v.callback(noNewReason), &.{}));
    engine.captured_exception = c.JS_DupValue(engine.context, old);
    const result = c.JS_Call(engine.context, function, c.pi_js_undefined(), 0, null); defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsException(result) and c.JS_HasException(engine.context));
    const current = c.JS_GetException(engine.context); defer engine.freeValue(current);
    try std.testing.expect(c.JS_IsError(current) and !c.JS_IsStrictEqual(engine.context, current, old));
    clear(engine);
}

/// Future separately granted Windows owner only: the function refuses an
/// existing file and reparsed ancestors. It never deletes the resulting file.
pub fn allResetWithOwnedFile(engine: *em.Engine, actual_sqlite: c.JSValue, owned_file: c.JSValue) !void {
    if (@import("builtin").os.tag != .windows) return error.WindowsOwnedFileGrantRequired;
    try v.pending(engine);
    if (!c.JS_IsString(owned_file)) return error.OwnedSqlitePathRequired;
    const path = try engine.toString(owned_file); defer engine.gpa.free(path);
    const normalized = try std.fs.path.resolve(engine.gpa, &.{path}); defer engine.gpa.free(normalized);
    if (!std.ascii.startsWithIgnoreCase(normalized, "C:\\Users\\adyba\\pi-zig\\upstream\\runtime\\chord-sqlite-owned-") or
        !std.mem.endsWith(u8, normalized, ".sqlite") or std.mem.indexOfScalar(u8, normalized[2..], ':') != null)
        return error.FreshContainedOwnedSqliteFileRequired;
    const Windows = struct {
        extern "kernel32" fn GetFileAttributesW([*:0]const u16) callconv(.winapi) u32;
        extern "kernel32" fn GetLastError() callconv(.winapi) u32;
    };
    const wide = try std.unicode.utf8ToUtf16LeAllocZ(engine.gpa, normalized); defer engine.gpa.free(wide);
    if (Windows.GetFileAttributesW(wide) != 0xffffffff) return error.OwnedSqliteFileAlreadyExists;
    const missing = Windows.GetLastError(); if (missing != 2 and missing != 3) return error.OwnedSqliteFreshnessUnverifiable;
    var ancestor = std.fs.path.dirname(normalized) orelse return error.OwnedSqliteParentRequired;
    while (ancestor.len > 3) {
        const parent_wide = try std.unicode.utf8ToUtf16LeAllocZ(engine.gpa, ancestor); defer engine.gpa.free(parent_wide);
        const attributes = Windows.GetFileAttributesW(parent_wide);
        if (attributes == 0xffffffff or attributes & 0x10 == 0 or attributes & 0x400 != 0) return error.PhysicalOwnedSqliteParentRequired;
        ancestor = std.fs.path.dirname(ancestor) orelse break;
    }
    var roots: Roots = .{ .engine = engine }; defer roots.deinit();
    const global = try roots.own(c.JS_GetGlobalObject(engine.context));
    try roots.put(global, "ownedFileSqlite", actual_sqlite); try roots.put(global, "ownedResetFile", owned_file);
    const pending = try engine.eval(
        "(async()=>{const a=new ownedFileSqlite.DatabaseSync(ownedResetFile),b=new ownedFileSqlite.DatabaseSync(ownedResetFile);try{" ++
        "a.exec('CREATE TABLE owned(n INTEGER)');a.exec('INSERT INTO owned VALUES(9007199254740993)');" ++
        "if(b.prepare('SELECT count(*) AS n FROM owned').get().n!==1)throw Error('Physical database sharing precondition failed');" ++
        "a.exec('BEGIN');a.prepare('SELECT count(*) AS n FROM owned').get();let blocked=false;try{b.exec('ALTER TABLE owned ADD COLUMN before_reset TEXT')}catch(error){blocked=error.code==='ERR_SQLITE_ERROR'&&(error.errcode&255)===5}" ++
        "a.exec('ROLLBACK');if(!blocked)throw Error('Physical pager lock precondition missing');" ++
        "const q=a.prepare('SELECT n FROM owned');let range=false;try{q.all()}catch(error){range=error.code==='ERR_OUT_OF_RANGE'}if(!range)throw Error('Actual physical All range failure missing');" ++
        "b.exec('ALTER TABLE owned ADD COLUMN after_reset TEXT');b.exec('INSERT INTO owned(n) VALUES(2)');" ++
        "if(b.prepare('SELECT count(*) AS n FROM owned').get().n!==2)throw Error('Physical writer after All reset did not finish');" ++
        "}finally{a.close();b.close()}})()", "actual-sqlite-owned-file-all-reset.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(pending); const value = try engine.awaitValue(pending); defer engine.freeValue(value);
}

pub fn compareOriginalCorrections(engine: *em.Engine, actual_api: c.JSValue, actual_sqlite: c.JSValue, reason_factory: c.JSValue, original_json: []const u8) !void {
    var roots: Roots = .{ .engine = engine }; defer roots.deinit();
    const observer = try roots.own(try engine.evalModule(@embedFile("../verification/chord-node-sqlite-c268-sourceonly-20261017/correction-observer.mjs"), "actual-chord-node-correction-compare.mjs"));
    const promise = try roots.call(try roots.get(observer, "observeCorrections"), c.pi_js_undefined(), &.{ actual_api, actual_sqlite, reason_factory });
    const actual = try roots.own(try engine.awaitValue(promise));
    const bytes = try engine.gpa.dupeZ(u8, original_json); defer engine.gpa.free(bytes);
    const original = try roots.own(try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, original_json.len, "actual-original-chord-node-corrections.json")));
    try std.testing.expect(roots.equal(try roots.get(original, "authority"), try roots.text("actual-c268-Chord-Node-SQLite-corrections")));
    try std.testing.expect(roots.equal(try roots.get(try roots.get(original, "rows"), "length"), c.JS_NewInt32(engine.context, 4)));
    const json = try roots.global("JSON"); const stringify = try roots.get(json, "stringify");
    try std.testing.expect(roots.equal(try roots.call(stringify, json, &.{original}), try roots.call(stringify, json, &.{actual})));
}
