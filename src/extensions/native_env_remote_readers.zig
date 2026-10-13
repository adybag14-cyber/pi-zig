//! Source Env reader orchestration, whole-file reads and directory listing.
const js = @import("native_js_values.zig");
const h = @import("native_env_remote_helpers.zig");
const range = @import("native_env_remote_range.zig");
const Scope = h.Scope;
const c = js.c;
const Stage = enum(c_int) { resolved, opened, aborted_close, file_read, file_range, file_closed, directory, directory_closed, directory_paths, lines_opened, line, lines_closed };
fn number(scope: *Scope, value: usize) c.JSValue {
    return c.JS_NewInt64(scope.engine.context, @intCast(value));
}
fn binary(scope: *Scope, operation: c_int, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, operation, left, right)));
}
fn getOperation(scope: *Scope, captures: c.JSValue) !@import("native_env_remote.zig").Method {
    var raw: i32 = undefined;
    if (c.JS_ToInt32(scope.engine.context, &raw, try scope.get(captures, "method")) < 0) return js.capture(scope.engine);
    return @enumFromInt(raw);
}
fn decoder(scope: *Scope) !c.JSValue {
    if (scope.engine.text_decoder_class == 0) try @import("text_decoder.zig").install(scope.engine);
    const options = try scope.object();
    try scope.put(options, "ignoreBOM", c.pi_js_bool(scope.engine.context, 1));
    return scope.own(try js.builtin(scope.engine, "TextDecoder", &.{ try scope.text("utf-8"), options }));
}
fn decode(scope: *Scope, captures: c.JSValue, bytes: ?c.JSValue, finish: bool) !c.JSValue {
    const reader = try scope.get(captures, "decoder");
    if (finish) return if (bytes) |given| scope.invoke(reader, "decode", &.{given}) else scope.invoke(reader, "decode", &.{});
    const options = try scope.object();
    try scope.put(options, "stream", c.pi_js_bool(scope.engine.context, 1));
    return scope.invoke(reader, "decode", &.{ bytes.?, options });
}
fn buffer(scope: *Scope, bytes: c.JSValue) !c.JSValue {
    return scope.invoke(try scope.global("Buffer"), "from", &.{bytes});
}
fn finished(scope: *Scope, captures: c.JSValue, value: c.JSValue, failed: bool, stage: Stage) !c.JSValue {
    try scope.put(captures, "completion", value);
    try scope.put(captures, "failed", c.pi_js_bool(scope.engine.context, @intFromBool(failed)));
    const close = try scope.invoke(try scope.get(captures, "handle"), "close", &.{});
    return h.wait(advance, scope, captures, close, stage);
}
fn fileAbort(scope: *Scope, captures: c.JSValue) !c.JSValue {
    const bindings = try scope.get(captures, "bindings");
    const constructor = try scope.get(bindings, "FileError");
    const args = [_]c.JSValue{ try scope.text("aborted"), try scope.text("The operation was aborted"), try scope.get(captures, "path") };
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, args.len, @constCast(&args))));
}
fn filePump(scope: *Scope, captures: c.JSValue) !c.JSValue {
    const unknown = scope.truthy(try scope.get(captures, "unknown"));
    if (unknown) {
        if (try range.aborted(scope, captures)) return finished(scope, captures, try fileAbort(scope, captures), true, .file_closed);
        return h.wait(advance, scope, captures, try range.pread(scope, captures, null, number(scope, 64 * 1024)), Stage.file_read);
    }
    const flight = try scope.get(captures, "flight");
    const chunk = try scope.get(captures, "chunk");
    while (scope.truthy(try binary(scope, 4, try scope.get(flight, "length"), number(scope, 8)))) {
        const offset = try scope.get(captures, "next");
        const pending = try range.pread(scope, captures, offset, chunk);
        try range.swallowed(scope, pending);
        _ = try scope.invoke(flight, "push", &.{pending});
        try scope.put(captures, "next", try binary(scope, 0, offset, chunk));
    }
    return h.wait(advance, scope, captures, try scope.invoke(flight, "shift", &.{}), Stage.file_read);
}
fn startFile(scope: *Scope, captures: c.JSValue, reply: c.JSValue) !c.JSValue {
    const json = try scope.get(reply, "json");
    const stat_error = try scope.get(json, "statError");
    if (!c.JS_IsUndefined(stat_error)) {
        const constructor = try scope.get(try scope.get(captures, "bindings"), "RemoteError");
        const reason = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, 1, @constCast(&stat_error))));
        return finished(scope, captures, reason, true, .file_closed);
    }
    if (try range.aborted(scope, captures)) return finished(scope, captures, try fileAbort(scope, captures), true, .file_closed);
    const stat = try scope.get(json, "stat");
    const size = if (scope.equal(try scope.get(stat, "kind"), try scope.text("file"))) try scope.get(stat, "size") else number(scope, 0);
    if (scope.truthy(try binary(scope, 6, size, number(scope, 2_147_483_647)))) {
        const message = try scope.concat(try scope.concat(try scope.text("File size ("), size), try scope.text(") is greater than 2 GiB"));
        const failure = try h.errors.errorResult(scope, captures, try scope.text("unknown"), message, try scope.get(captures, "path"), c.pi_js_undefined());
        return finished(scope, captures, try scope.get(failure, "error"), true, .file_closed);
    }
    try scope.put(captures, "size", size);
    try scope.put(captures, "total", number(scope, 0));
    try scope.put(captures, "chunks", try scope.array());
    try scope.put(captures, "text", try scope.text(""));
    const unknown = scope.equal(size, number(scope, 0));
    try scope.put(captures, "unknown", c.pi_js_bool(scope.engine.context, @intFromBool(unknown)));
    const encoding = scope.truthy(try scope.get(captures, "encoding"));
    if (!unknown and !encoding) {
        if (scope.truthy(try binary(scope, 5, size, number(scope, 512 * 1024)))) {
            try scope.put(captures, "single", c.pi_js_bool(scope.engine.context, 1));
            return h.wait(advance, scope, captures, try range.pread(scope, captures, number(scope, 0), size), Stage.file_read);
        }
        return h.wait(advance, scope, captures, try range.start(scope, captures, try scope.get(captures, "handle"), number(scope, 0), size, 512 * 1024), Stage.file_range);
    }
    try scope.put(captures, "decoder", try decoder(scope));
    if (!unknown) {
        try scope.put(captures, "chunk", try scope.invoke(try scope.global("Math"), "min", &.{ size, number(scope, 512 * 1024) }));
        try scope.put(captures, "flight", try scope.array());
        try scope.put(captures, "next", number(scope, 0));
        try scope.put(captures, "first", c.pi_js_bool(scope.engine.context, 1));
    }
    return filePump(scope, captures);
}
fn fileRead(scope: *Scope, captures: c.JSValue, bytes: c.JSValue) !c.JSValue {
    if (scope.truthy(try scope.get(captures, "single"))) return finished(scope, captures, try buffer(scope, bytes), false, .file_closed);
    if (try range.aborted(scope, captures)) return finished(scope, captures, try fileAbort(scope, captures), true, .file_closed);
    const size = try scope.get(bytes, "length");
    const total = try binary(scope, 0, try scope.get(captures, "total"), size);
    try scope.put(captures, "total", total);
    const encoding = scope.truthy(try scope.get(captures, "encoding"));
    if (scope.truthy(try scope.get(captures, "unknown"))) {
        if (scope.equal(size, number(scope, 0))) {
            const value = if (!encoding) try scope.invoke(try scope.global("Buffer"), "concat", &.{ try scope.get(captures, "chunks"), total }) else if (scope.equal(total, number(scope, 0))) try scope.text("") else try scope.concat(try scope.get(captures, "text"), try decode(scope, captures, null, true));
            return finished(scope, captures, value, false, .file_closed);
        }
        _ = try scope.invoke(try scope.get(captures, "chunks"), "push", &.{bytes});
        if (encoding) try scope.put(captures, "text", try scope.concat(try scope.get(captures, "text"), try decode(scope, captures, bytes, false)));
        return filePump(scope, captures);
    }
    if (scope.equal(size, number(scope, 0)) or scope.equal(total, try scope.get(captures, "size")) or !scope.equal(size, try scope.get(captures, "chunk"))) {
        const value = if (scope.truthy(try scope.get(captures, "first"))) try scope.invoke(try buffer(scope, bytes), "toString", &.{try scope.text("utf8")}) else try scope.concat(try scope.get(captures, "text"), try decode(scope, captures, try buffer(scope, bytes), true));
        return finished(scope, captures, value, false, .file_closed);
    }
    try scope.put(captures, "text", try scope.concat(try scope.get(captures, "text"), try decode(scope, captures, try buffer(scope, bytes), false)));
    try scope.put(captures, "first", c.pi_js_bool(scope.engine.context, 0));
    return filePump(scope, captures);
}
fn directoryPump(scope: *Scope, captures: c.JSValue) !c.JSValue {
    const json = try scope.object();
    try scope.put(json, "max", number(scope, 1000));
    return h.wait(advance, scope, captures, try h.handleRequest(scope, try scope.get(captures, "handle"), "readdir", json, null), Stage.directory);
}
fn compare(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return compareValues(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn compareValues(engine: *js.Engine, left: c.JSValue, right: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var keys: [2]c.JSValue = undefined;
    for ([_]c.JSValue{ left, right }, 0..) |entry, index| {
        const raw = try scope.get(entry, "raw");
        keys[index] = try buffer(&scope, if (h.nullish(raw)) try scope.invoke(try scope.global("Buffer"), "from", &.{ try scope.get(entry, "name"), try scope.text("utf8") }) else raw);
    }
    return c.JS_DupValue(engine.context, try scope.invoke(try scope.global("Buffer"), "compare", &keys));
}
fn directoryConvert(scope: *Scope, captures: c.JSValue, info: c.JSValue) !c.JSValue {
    const bindings = try scope.get(captures, "bindings");
    const paths = try h.path.paths(scope, bindings, info);
    const entries = try scope.get(captures, "entries");
    if (scope.equal(paths, try scope.get(try scope.get(bindings, "paths"), "posix"))) {
        const comparator = try scope.own(try scope.engine.checked(c.JS_NewCFunction(scope.engine.context, compare, "", 2)));
        _ = try scope.invoke(entries, "sort", &.{comparator});
    }
    const results = try scope.array();
    var iterator = try js.Iterator.init(scope.engine, entries, try scope.get(try scope.global("Symbol"), "iterator"));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        _ = try row.own(entry);
        if (try h.errors.aborted(&row, captures)) |early| return scope.own(c.JS_DupValue(scope.engine.context, early));
        const entry_path = try row.invoke(paths, "resolve", &.{ try row.get(captures, "path"), try row.get(entry, "name") });
        const child = try row.object();
        try row.put(child, "bindings", bindings);
        try row.put(child, "path", entry_path);
        const failure = try row.get(entry, "error");
        if (!c.JS_IsUndefined(failure)) {
            const constructor = try row.get(bindings, "RemoteError");
            const reason = try row.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, 1, @constCast(&failure))));
            return scope.own(c.JS_DupValue(scope.engine.context, try h.errors.mapError(&row, child, reason)));
        }
        const result = try h.fileInfo(&row, child, try row.get(entry, "info"), paths);
        if (row.truthy(try row.get(result, "ok"))) _ = try row.invoke(results, "push", &.{try row.get(result, "value")});
    }
    return h.values.result(scope, true, results);
}
fn linesPump(scope: *Scope, captures: c.JSValue) !c.JSValue {
    const maximum = try h.optional(scope, try scope.get(captures, "options"), "maxLines");
    const lines = try scope.get(captures, "lines");
    if (!c.JS_IsUndefined(maximum) and !scope.truthy(try binary(scope, 4, try scope.get(lines, "length"), try scope.get(try scope.get(captures, "options"), "maxLines")))) return finished(scope, captures, try h.values.result(scope, true, lines), false, .lines_closed);
    const pending = try scope.invoke(try scope.get(captures, "handle"), "readLine", &.{try scope.get(captures, "context")});
    return h.wait(advance, scope, captures, pending, Stage.line);
}
fn continuation(scope: *Scope, captures: c.JSValue, value: c.JSValue, stage: Stage) !c.JSValue {
    const kind = try getOperation(scope, captures);
    const receiver = try scope.get(captures, "self");
    const bindings = try scope.get(captures, "bindings");
    switch (stage) {
        .resolved => {
            try scope.put(captures, "path", value);
            if (try h.errors.aborted(scope, captures)) |early| return early;
            const json = try scope.object();
            try scope.put(json, "path", value);
            const directory = kind == .listDir or kind == .openDirReader;
            if (kind == .openBinaryReader) try scope.put(json, "noFollow", c.pi_js_bool(scope.engine.context, @intFromBool(scope.equal(try h.optional(scope, try scope.get(captures, "options"), "noFollow"), c.pi_js_bool(scope.engine.context, 1))))) else if (!directory) try scope.put(json, "mode", try scope.text("read"));
            return h.wait(advance, scope, captures, try h.request(scope, receiver, if (directory) "opendir" else "open", json, null), Stage.opened);
        },
        .opened => {
            const retained = try h.handle(scope, bindings, receiver, value, try scope.get(captures, "path"));
            try scope.put(captures, "handle", retained);
            if (kind == .readTextFile or kind == .readBinaryFile) return startFile(scope, captures, value);
            if (kind == .listDir) {
                try scope.put(captures, "entries", try scope.array());
                return directoryPump(scope, captures);
            }
            if (try h.errors.aborted(scope, captures)) |early| return finished(scope, captures, early, false, .aborted_close);
            const constructor = try scope.get(bindings, switch (kind) {
                .openBinaryReader => "RemoteBinaryReader",
                .openTextLineReader => "RemoteTextLineReader",
                .openDirReader => "RemoteDirReader",
                else => unreachable,
            });
            const reader = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, 1, @constCast(&retained))));
            return h.values.result(scope, true, reader);
        },
        .aborted_close => return scope.get(captures, "completion"),
        .file_read => return fileRead(scope, captures, value),
        .file_range => return finished(scope, captures, if (c.JS_IsUndefined(value)) try fileAbort(scope, captures) else try range.concat(scope, value, true), c.JS_IsUndefined(value), .file_closed),
        .file_closed => {
            const completion = try scope.get(captures, "completion");
            return if (scope.truthy(try scope.get(captures, "failed"))) h.errors.mapError(scope, captures, completion) else h.values.result(scope, true, completion);
        },
        .directory => {
            const json = try scope.get(value, "json");
            const entries = try scope.get(captures, "entries");
            var iterator = try js.Iterator.init(scope.engine, try scope.get(json, "entries"), try scope.get(try scope.global("Symbol"), "iterator"));
            defer iterator.deinit();
            errdefer iterator.closePreserving();
            while (try iterator.next()) |entry| {
                _ = try scope.own(entry);
                _ = try scope.invoke(entries, "push", &.{entry});
            }
            if (scope.equal(try scope.get(json, "done"), c.pi_js_bool(scope.engine.context, 1))) return finished(scope, captures, c.pi_js_undefined(), false, .directory_closed);
            return directoryPump(scope, captures);
        },
        .directory_closed => {
            if (scope.truthy(try scope.get(captures, "failed"))) return h.errors.mapError(scope, captures, try scope.get(captures, "completion"));
            return h.wait(advance, scope, captures, try scope.invoke(try scope.get(receiver, "connection"), "info", &.{}), Stage.directory_paths);
        },
        .directory_paths => return directoryConvert(scope, captures, value),
        .lines_opened => {
            if (!scope.truthy(try scope.get(value, "ok"))) return value;
            try scope.put(captures, "handle", try scope.get(value, "value"));
            try scope.put(captures, "lines", try scope.array());
            return linesPump(scope, captures);
        },
        .line => {
            if (!scope.truthy(try scope.get(value, "ok"))) return finished(scope, captures, value, false, .lines_closed);
            const line = try scope.get(value, "value");
            if (c.JS_IsUndefined(line)) return finished(scope, captures, try h.values.result(scope, true, try scope.get(captures, "lines")), false, .lines_closed);
            _ = try scope.invoke(try scope.get(captures, "lines"), "push", &.{try scope.get(line, "text")});
            return linesPump(scope, captures);
        },
        .lines_closed => return if (scope.truthy(try scope.get(captures, "failed"))) h.throw(scope, try scope.get(captures, "completion")) else scope.get(captures, "completion"),
    }
}
fn fail(scope: *Scope, captures: c.JSValue, reason: c.JSValue, stage: Stage) !c.JSValue {
    if (stage == .lines_opened or stage == .lines_closed) return h.throw(scope, reason);
    if (stage == .line) return finished(scope, captures, reason, true, .lines_closed);
    if (stage == .file_read or stage == .file_range or stage == .directory) return finished(scope, captures, reason, true, if (stage == .directory) .directory_closed else .file_closed);
    return h.errors.mapError(scope, captures, reason);
}
fn advance(engine: *js.Engine, captures: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const stage: Stage = @enumFromInt(raw);
    const result = if (rejected) try fail(&scope, captures, value, stage) else continuation(&scope, captures, value, stage) catch |err| {
        if (err != error.JavaScriptException) return err;
        return c.JS_DupValue(engine.context, try fail(&scope, captures, try h.errors.captured(&scope), stage));
    };
    return c.JS_DupValue(engine.context, result);
}
pub fn invoke(scope: *Scope, captures: c.JSValue, kind: anytype, args: []const c.JSValue) !c.JSValue {
    if (kind == .readTextLines) {
        const options = h.arg(args, 1);
        const limit = try h.optional(scope, options, "maxLines");
        if (!c.JS_IsUndefined(limit) and scope.truthy(try binary(scope, 5, try scope.get(options, "maxLines"), number(scope, 0)))) return h.resolved(scope, try h.values.result(scope, true, try scope.array()));
        return h.wait(advance, scope, captures, try scope.invoke(try scope.get(captures, "self"), "openTextLineReader", &.{ h.arg(args, 0), h.arg(args, 2) }), Stage.lines_opened);
    }
    try scope.put(captures, "encoding", c.pi_js_bool(scope.engine.context, @intFromBool(kind == .readTextFile)));
    const pending = h.path.resolve(scope, try scope.get(captures, "bindings"), try scope.get(captures, "self"), h.arg(args, 0)) catch |err| try h.rejected(scope, err);
    return h.wait(advance, scope, captures, pending, Stage.resolved);
}
