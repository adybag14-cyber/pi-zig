//! Source write/append chunk queues, abort precedence, close finalizers and temporary files.
const std = @import("std");
const js = @import("native_js_values.zig");
const h = @import("native_env_remote_helpers.zig");
const range = @import("native_env_remote_range.zig");
const Scope = h.Scope;
const c = js.c;
const Stage = enum(c_int) { resolved, first, chunk, remaining, abort_settled, final_settled, closed, temp_dir, temp_paths, temp_write };
fn number(scope: *Scope, value: usize) c.JSValue {
    return c.JS_NewInt64(scope.engine.context, @intCast(value));
}
fn binary(scope: *Scope, operation: c_int, a: c.JSValue, b: c.JSValue) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, operation, a, b)));
}
fn settleAll(scope: *Scope, captures: c.JSValue) !c.JSValue {
    return scope.invoke(try scope.global("Promise"), "allSettled", &.{try scope.get(captures, "flight")});
}
fn result(scope: *Scope, captures: c.JSValue) !c.JSValue {
    if (scope.truthy(try scope.get(captures, "append"))) if (try h.errors.aborted(scope, captures)) |early| return early;
    return h.values.result(scope, true, c.pi_js_undefined());
}
fn finish(scope: *Scope, captures: c.JSValue, reason: c.JSValue, failed: bool) !c.JSValue {
    try scope.put(captures, "failure", reason);
    try scope.put(captures, "failed", c.pi_js_bool(scope.engine.context, @intFromBool(failed)));
    return h.wait(advance, scope, captures, try settleAll(scope, captures), Stage.final_settled);
}
fn aborted(scope: *Scope, captures: c.JSValue) !bool {
    const signal = try scope.get(captures, "signal");
    return !h.nullish(signal) and scope.truthy(try scope.get(signal, "aborted"));
}
fn pump(scope: *Scope, captures: c.JSValue) !c.JSValue {
    const bytes = try scope.get(captures, "bytes");
    const flight = try scope.get(captures, "flight");
    var offset = try scope.get(captures, "offset");
    while (scope.truthy(try binary(scope, 4, offset, try scope.get(bytes, "length")))) {
        if (try aborted(scope, captures)) return h.wait(advance, scope, captures, try settleAll(scope, captures), Stage.abort_settled);
        const end = try binary(scope, 0, offset, number(scope, 512 * 1024));
        const options = try scope.object();
        try scope.put(options, "payload", try scope.invoke(bytes, "subarray", &.{ offset, end }));
        const pending = try h.handleRequest(scope, try scope.get(captures, "handle"), "writeChunk", try scope.object(), options);
        try range.swallowed(scope, pending);
        _ = try scope.invoke(flight, "push", &.{pending});
        offset = end;
        try scope.put(captures, "offset", offset);
        if (scope.truthy(try binary(scope, 7, try scope.get(flight, "length"), number(scope, 8)))) return h.wait(advance, scope, captures, try scope.invoke(flight, "shift", &.{}), Stage.chunk);
    }
    try scope.put(captures, "remaining", number(scope, 0));
    return remaining(scope, captures);
}
fn remaining(scope: *Scope, captures: c.JSValue) !c.JSValue {
    const index = try scope.get(captures, "remaining");
    const flight = try scope.get(captures, "flight");
    if (!scope.truthy(try binary(scope, 4, index, try scope.get(flight, "length")))) return finish(scope, captures, c.pi_js_undefined(), false);
    const pending = try scope.own(try js.getKey(scope.engine, flight, index));
    try scope.put(captures, "remaining", try binary(scope, 0, index, number(scope, 1)));
    return h.wait(advance, scope, captures, pending, Stage.remaining);
}
fn uuid(scope: *Scope) !c.JSValue {
    var bytes: [16]u8 = undefined;
    try (scope.engine.native_io orelse return error.NativeIoRequired).randomSecure(&bytes);
    bytes[6] = bytes[6] & 15 | 64;
    bytes[8] = bytes[8] & 63 | 128;
    const hex = std.fmt.bytesToHex(bytes, .lower);
    const text = try std.fmt.allocPrint(scope.engine.gpa, "{s}-{s}-{s}-{s}-{s}", .{ hex[0..8], hex[8..12], hex[12..16], hex[16..20], hex[20..32] });
    defer scope.engine.gpa.free(text);
    return scope.text(text);
}
fn continuation(scope: *Scope, captures: c.JSValue, value: c.JSValue, stage: Stage) !c.JSValue {
    const receiver = try scope.get(captures, "self");
    const bindings = try scope.get(captures, "bindings");
    switch (stage) {
        .resolved => {
            try scope.put(captures, "path", value);
            if (try h.errors.aborted(scope, captures)) |early| return early;
            const bytes = try scope.get(captures, "bytes");
            const first = try scope.invoke(bytes, "subarray", &.{ number(scope, 0), number(scope, 512 * 1024) });
            const keep = try binary(scope, 6, try scope.get(bytes, "length"), number(scope, 512 * 1024));
            try scope.put(captures, "keep", keep);
            const json = try scope.object();
            try scope.put(json, "path", value);
            try scope.put(json, "append", try scope.get(captures, "append"));
            try scope.put(json, "keep", keep);
            const options = try scope.object();
            try scope.put(options, "payload", first);
            return h.wait(advance, scope, captures, try h.request(scope, receiver, "write", json, options), Stage.first);
        },
        .first => {
            if (!scope.truthy(try scope.get(captures, "keep"))) return result(scope, captures);
            try scope.put(captures, "handle", try h.handle(scope, bindings, receiver, value, try scope.get(captures, "path")));
            try scope.put(captures, "flight", try scope.array());
            try scope.put(captures, "offset", number(scope, 512 * 1024));
            return pump(scope, captures);
        },
        .chunk => return pump(scope, captures),
        .remaining => return remaining(scope, captures),
        .abort_settled => {
            var iterator = try js.Iterator.init(scope.engine, value, try scope.get(try scope.global("Symbol"), "iterator"));
            defer iterator.deinit();
            errdefer iterator.closePreserving();
            while (try iterator.next()) |entry| {
                _ = try scope.own(entry);
                if (scope.equal(try scope.get(entry, "status"), try scope.text("rejected"))) return finish(scope, captures, try scope.get(entry, "reason"), true);
            }
            const failure = try h.errors.errorResult(scope, captures, try scope.text("aborted"), try scope.text("The operation was aborted"), try scope.get(captures, "path"), c.pi_js_undefined());
            return finish(scope, captures, try scope.get(failure, "error"), true);
        },
        .final_settled => return h.wait(advance, scope, captures, try scope.invoke(try scope.get(captures, "handle"), "close", &.{}), Stage.closed),
        .closed => return if (scope.truthy(try scope.get(captures, "failed"))) h.errors.mapError(scope, captures, try scope.get(captures, "failure")) else result(scope, captures),
        .temp_dir => {
            if (!scope.truthy(try scope.get(value, "ok"))) return value;
            try scope.put(captures, "directory", try scope.get(value, "value"));
            try scope.put(captures, "path", try scope.text(""));
            return h.wait(advance, scope, captures, try scope.invoke(try scope.get(receiver, "connection"), "info", &.{}), Stage.temp_paths);
        },
        .temp_paths => {
            const options = try scope.get(captures, "options");
            const given_prefix = try h.optional(scope, options, "prefix");
            const prefix = try scope.stringify(if (h.nullish(given_prefix)) try scope.text("") else given_prefix);
            const name = try scope.concat(prefix, try uuid(scope));
            const given_suffix = try h.optional(scope, options, "suffix");
            const suffix = try scope.stringify(if (h.nullish(given_suffix)) try scope.text("") else given_suffix);
            const path = try scope.invoke(try h.path.paths(scope, bindings, value), "join", &.{ try scope.get(captures, "directory"), try scope.concat(name, suffix) });
            try scope.put(captures, "path", path);
            const json = try scope.object();
            try scope.put(json, "path", path);
            try scope.put(json, "append", c.pi_js_bool(scope.engine.context, 0));
            try scope.put(json, "parents", c.pi_js_bool(scope.engine.context, 0));
            const opts = try scope.object();
            try scope.put(opts, "payload", try scope.own(try js.builtin(scope.engine, "Uint8Array", &.{number(scope, 0)})));
            return h.wait(advance, scope, captures, try h.request(scope, receiver, "write", json, opts), Stage.temp_write);
        },
        .temp_write => return h.values.result(scope, true, try scope.get(captures, "path")),
    }
}
fn fail(scope: *Scope, captures: c.JSValue, reason: c.JSValue, stage: Stage) !c.JSValue {
    if (stage == .temp_dir) return h.throw(scope, reason);
    if (stage == .chunk or stage == .remaining or (stage == .first and !c.JS_IsUndefined(try scope.get(captures, "handle")))) return finish(scope, captures, reason, true);
    return h.errors.mapError(scope, captures, reason);
}
fn advance(engine: *js.Engine, captures: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const stage: Stage = @enumFromInt(raw);
    const result_value = if (rejected) try fail(&scope, captures, value, stage) else continuation(&scope, captures, value, stage) catch |err| {
        if (err != error.JavaScriptException) return err;
        return c.JS_DupValue(engine.context, try fail(&scope, captures, try h.errors.captured(&scope), stage));
    };
    return c.JS_DupValue(engine.context, result_value);
}
pub fn invoke(scope: *Scope, captures: c.JSValue, kind: anytype, args: []const c.JSValue) !c.JSValue {
    if (kind == .createTempFile) return h.wait(advance, scope, captures, try scope.invoke(try scope.get(captures, "self"), "createTempDir", &.{ try scope.text("tmp-"), h.arg(args, 1) }), Stage.temp_dir);
    const content = h.arg(args, 1);
    const bytes = if (c.JS_IsString(content)) try scope.invoke(try scope.global("Buffer"), "from", &.{ content, try scope.text("utf8") }) else content;
    try scope.put(captures, "bytes", bytes);
    try scope.put(captures, "append", c.pi_js_bool(scope.engine.context, @intFromBool(kind == .appendFile)));
    try scope.put(captures, "signal", if (kind == .appendFile) c.pi_js_undefined() else try scope.get(try scope.get(captures, "context"), "abortSignal"));
    const pending = h.path.resolve(scope, try scope.get(captures, "bindings"), try scope.get(captures, "self"), h.arg(args, 0)) catch |err| try h.rejected(scope, err);
    return h.wait(advance, scope, captures, pending, Stage.resolved);
}
