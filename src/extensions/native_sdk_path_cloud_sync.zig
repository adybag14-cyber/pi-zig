//! Actual utils/paths.ts markPathIgnoredByCloudSync over captured native imports.
//! Platform reads, array iteration and command effects remain guest-observable.
const v = @import("native_ai_provider_values.zig");
const data = @import("native_sdk_package_data.zig");
const Scope = v.Scope;
const c = v.c;
const functions = @import("native_node_function.zig");
const caught = @import("native_sdk_package_catch.zig");

pub fn create(engine: *v.em.Engine, actual_process: c.JSValue, spawn_process_sync: c.JSValue) !c.JSValue {
    if (!c.JS_IsObject(actual_process) or !c.JS_IsFunction(engine.context, spawn_process_sync))
        return error.RequiredActualCloudSyncImports;
    return functions.create(engine, "markPathIgnoredByCloudSync", 1, mark, &.{ actual_process, spawn_process_sync });
}

fn platform(s: *Scope, process: c.JSValue, name: []const u8) !bool {
    const value = try v.js.get(s.engine, process, "platform");
    defer s.engine.freeValue(value);
    return c.JS_IsStrictEqual(s.engine.context, value, try s.text(name));
}

fn mark(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const path = if (args.len > 0) args[0] else c.pi_js_undefined();
    const darwin = try platform(&s, roots[0], "darwin");
    const linux = if (darwin) false else try platform(&s, roots[0], "linux");
    const attrs = try s.array();
    if (darwin) {
        try s.index(attrs, 0, try s.text("com.dropbox.ignored"));
        try s.index(attrs, 1, try s.text("com.apple.fileprovider.ignore#P"));
    } else if (linux) {
        try s.index(attrs, 0, try s.text("user.com.dropbox.ignored"));
    }
    var iterator = try v.iterator(&s, attrs);
    defer iterator.deinit();
    const generation = engine.native_allocation_generation;
    run(engine, path, roots, &iterator) catch |err| return closeAfterThrow(&iterator, err, generation);
    return c.pi_js_undefined();
}

// IteratorClose preserves an ordinary body throw, including when return throws.
// Fatal/native allocation failures bypass guest cleanup; fresh fatal completion
// from return is propagated exactly, rather than swallowed by the shared helper.
fn closeAfterThrow(iterator: *v.js.Iterator, err: anyerror, generation: u64) !c.JSValue {
    const engine = iterator.engine;
    const original = (try caught.take(engine, err, generation)) orelse return err;
    defer engine.freeValue(original);
    const close_generation = engine.native_allocation_generation;
    iterator.close() catch |close_err| {
        if (try caught.take(engine, close_err, close_generation)) |discard| engine.freeValue(discard);
    };
    return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, original)));
}

fn run(engine: *v.em.Engine, path: c.JSValue, roots: []const c.JSValue, iterator: *v.js.Iterator) !void {
    while (try iterator.next()) |attr| {
        defer engine.freeValue(attr);
        var iteration: Scope = .{ .engine = engine };
        defer iteration.deinit();
        const is_darwin = try platform(&iteration, roots[0], "darwin");
        const command = try iteration.text(if (is_darwin) "xattr" else "setfattr");
        const argv = try iteration.array();
        if (is_darwin) {
            try iteration.index(argv, 0, try iteration.text("-w"));
            try iteration.index(argv, 1, attr);
            try iteration.index(argv, 2, try iteration.text("1"));
            try iteration.index(argv, 3, path);
        } else {
            try iteration.index(argv, 0, try iteration.text("-n"));
            try iteration.index(argv, 1, attr);
            try iteration.index(argv, 2, try iteration.text("-v"));
            try iteration.index(argv, 3, try iteration.text("1"));
            try iteration.index(argv, 4, path);
        }
        const options = try iteration.object();
        try data.put(engine, options, "encoding", try iteration.text("utf-8"));
        try data.put(engine, options, "stdio", try iteration.text("ignore"));
        // Source discards each result before advancing the live iterator.
        const result = try v.js.call(engine, roots[1], c.pi_js_undefined(), &.{ command, argv, options });
        engine.freeValue(result);
    }
}
