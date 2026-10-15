//! Original user-Bash streaming algorithm, on the owner VM and raw native operations.
//! One decoder observes combined stdout/stderr. Spill writes retain an exclusive handle.
const std = @import("std");
const builtin = @import("builtin");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const file = @import("native_output_file.zig");
const c = em.c;
const max_bytes = 50 * 1024;
const csi_start = "[\\u001B\\u009B][[\\]()#;?]*(?:\\d{1,4}(?:[;:]\\d{0,4})*)?";
fn regex(scope: *Scope, pattern: []const u8, flags: []const u8) !c.JSValue {
    return scope.own(try js.builtin(scope.engine, "RegExp", &.{ try scope.text(pattern), try scope.text(flags) }));
}
pub fn create(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const helpers = try scope.object();
    try scope.put(helpers, "strip", try regex(&scope, "(?:\\u001B\\][\\s\\S]*?(?:\\u0007|\\u001B\\u005C|\\u009C))|" ++ csi_start ++ "[\\dA-PR-TZcf-nq-uy=><~]", "g"));
    try scope.put(helpers, "pending", try regex(&scope, "(?:\\u001B\\](?:[^\\u0007\\u009C\\u001B]|\\u001B(?!\\\\))*|" ++ csi_start ++ ")$", ""));
    try scope.put(helpers, "binary", try regex(&scope, "[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F\\uFFF9-\\uFFFB]", "g"));
    try scope.put(helpers, "cr", try regex(&scope, "\\r", "g"));
    try scope.put(helpers, "tmpdir", try scope.own(try @import("native_os_tmpdir.zig").create(engine)));
    try scope.put(helpers, "fileClass", c.JS_NewUint32(engine.context, try file.registerClass(engine)));
    var roots = [_]c.JSValue{helpers};
    const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, execute, "executeBashWithOperations", 4, 0, roots.len, &roots)));
    const parent = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
    if (c.JS_SetPrototype(engine.context, function, parent) < 0) return js.capture(engine);
    return c.JS_DupValue(engine.context, function);
}
fn arg(args: []const c.JSValue, i: usize) c.JSValue {
    return if (i < args.len) args[i] else c.pi_js_undefined();
}
fn optional(scope: *Scope, object: c.JSValue, key: [*:0]const u8) !c.JSValue {
    return if (temp.nullish(object)) c.pi_js_undefined() else scope.get(object, key);
}
fn execute(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return begin(engine, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0]) catch |err| sdk.fail(engine, err);
}
fn begin(engine: *em.Engine, args: []const c.JSValue, helpers: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    start(engine, pending.owner, args, helpers) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn start(engine: *em.Engine, owner: c.JSValue, args: []const c.JSValue, helpers: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "helpers", helpers);
    try scope.put(owner, "options", arg(args, 3));
    try scope.put(owner, "chunks", try scope.array());
    try scope.put(owner, "outputBytes", c.JS_NewInt32(engine.context, 0));
    try scope.put(owner, "totalBytes", c.JS_NewInt32(engine.context, 0));
    try scope.put(owner, "pendingAnsi", try scope.text(""));
    try scope.put(owner, "decoder", try scope.own(try js.builtin(engine, "TextDecoder", &.{})));
    try scope.put(owner, "exitCode", c.pi_js_null());
    beginTry(engine, owner, args) catch |err| {
        const reason = flow.reason(engine, err);
        defer engine.freeValue(reason);
        return finish(engine, owner, reason, true, 0);
    };
}
fn beginTry(engine: *em.Engine, owner: c.JSValue, args: []const c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const options = try scope.object();
    var roots = [_]c.JSValue{owner};
    try scope.put(options, "onData", try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, onData, "onData", 1, 0, roots.len, &roots))));
    try scope.put(options, "signal", try optional(&scope, arg(args, 3), "signal"));
    const result = try scope.invoke(arg(args, 2), "exec", &.{ arg(args, 0), arg(args, 1), options });
    try flow.wait(finish, engine, owner, result, 0);
}
fn onData(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    data(engine, roots[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| return sdk.fail(engine, err);
    return c.pi_js_undefined();
}
fn data(engine: *em.Engine, owner: c.JSValue, input: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "totalBytes", try scope.concat(try scope.get(owner, "totalBytes"), try scope.get(input, "length")));
    const options = try scope.object();
    try scope.put(options, "stream", c.pi_js_bool(engine.context, 1));
    const text = try scope.concat(try scope.get(owner, "pendingAnsi"), try scope.invoke(try scope.get(owner, "decoder"), "decode", &.{ input, options }));
    var complete = text;
    var pending = try scope.text("");
    const has_escape = scope.truthy(try scope.invoke(text, "includes", &.{try scope.text("\x1b")})) or scope.truthy(try scope.invoke(text, "includes", &.{try scope.text("\u{9b}")}));
    if (has_escape) {
        const length = try sdk.length(engine, text);
        const window_start = length -| 256;
        const window = try scope.invoke(text, "slice", &.{c.JS_NewUint32(engine.context, window_start)});
        const match = try scope.invoke(try scope.get(try scope.get(owner, "helpers"), "pending"), "exec", &.{window});
        if (scope.truthy(match)) {
            const at = try scope.concat(c.JS_NewUint32(engine.context, window_start), try scope.get(match, "index"));
            complete = try scope.invoke(text, "slice", &.{ c.JS_NewInt32(engine.context, 0), at });
            pending = try scope.invoke(text, "slice", &.{at});
        }
    }
    try scope.put(owner, "pendingAnsi", pending);
    try append(engine, owner, complete);
}
fn write(engine: *em.Engine, lease: c.JSValue, value: c.JSValue) !void {
    const bytes = try utf8(engine, value);
    defer engine.gpa.free(bytes);
    try file.append(lease, bytes);
}
fn utf8(engine: *em.Engine, value: c.JSValue) ![]u8 {
    const text = try engine.toString(value);
    defer engine.gpa.free(text);
    return @import("binary_encoding.zig").encode(engine.gpa, text, .utf8);
}
fn ensureFile(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (scope.truthy(try scope.get(owner, "tempFilePath"))) return;
    const helpers = try scope.get(owner, "helpers");
    const temporary = try engine.toString(try scope.call(try scope.get(helpers, "tmpdir"), c.pi_js_undefined(), &.{}));
    defer engine.gpa.free(temporary);
    var nonce: [8]u8 = undefined;
    try std.Io.randomSecure(engine.native_io orelse return error.NativeIoUnavailable, &nonce);
    const filename = try std.fmt.allocPrint(engine.gpa, "pi-bash-{s}.log", .{std.fmt.bytesToHex(nonce, .lower)});
    defer engine.gpa.free(filename);
    const path = try @import("node_path.zig").join(engine.gpa, &.{ temporary, filename }, if (builtin.os.tag == .windows) .win32 else .posix);
    defer engine.gpa.free(path);
    var class_id: u32 = undefined;
    if (c.JS_ToUint32(engine.context, &class_id, try scope.get(helpers, "fileClass")) < 0) return js.capture(engine);
    const lease = try scope.own(try file.create(engine, class_id, path));
    try scope.put(owner, "tempFilePath", try scope.text(path));
    try scope.put(owner, "tempFileStream", lease);
    var chunks = try js.Iterator.init(engine, try scope.get(owner, "chunks"), try scope.own(try engine.checked(c.JS_GetIteratorSymbol(engine.context))));
    defer chunks.deinit();
    errdefer chunks.closePreserving();
    while (try chunks.next()) |chunk| {
        defer engine.freeValue(chunk);
        try write(engine, lease, chunk);
    }
}
fn numeric(engine: *em.Engine, value: c.JSValue) !f64 {
    return @import("native_color.zig").number(engine, value);
}
fn append(engine: *em.Engine, owner: c.JSValue, raw: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const helpers = try scope.get(owner, "helpers");
    var text = raw;
    if (scope.truthy(try scope.invoke(raw, "includes", &.{try scope.text("\x1b")})) or scope.truthy(try scope.invoke(raw, "includes", &.{try scope.text("\u{9b}")}))) text = try scope.invoke(raw, "replace", &.{ try scope.get(helpers, "strip"), try scope.text("") });
    text = try scope.invoke(text, "replace", &.{ try scope.get(helpers, "binary"), try scope.text("") });
    text = try scope.invoke(text, "replace", &.{ try scope.get(helpers, "cr"), try scope.text("") });
    if (!scope.truthy(text)) return;
    if (try numeric(engine, try scope.get(owner, "totalBytes")) > max_bytes) try ensureFile(engine, owner);
    const lease = try scope.get(owner, "tempFileStream");
    if (scope.truthy(lease)) try write(engine, lease, text);
    const chunks = try scope.get(owner, "chunks");
    _ = try scope.invoke(chunks, "push", &.{text});
    var output_bytes = try numeric(engine, try scope.get(owner, "outputBytes")) + try numeric(engine, try scope.get(text, "length"));
    while (output_bytes > max_bytes * 2 and try sdk.length(engine, chunks) > 1) {
        const removed = try scope.invoke(chunks, "shift", &.{});
        output_bytes -= try numeric(engine, try scope.get(removed, "length"));
    }
    try scope.put(owner, "outputBytes", c.JS_NewFloat64(engine.context, output_bytes));
    const options = try scope.get(owner, "options");
    if (scope.truthy(try optional(&scope, options, "onChunk"))) _ = try scope.invoke(options, "onChunk", &.{text});
}
fn close(engine: *em.Engine, owner: c.JSValue) !void {
    const lease = try sdk.get(engine, owner, "tempFileStream");
    defer engine.freeValue(lease);
    if (c.JS_ToBool(engine.context, lease) == 1) file.close(lease);
}
fn aborted(scope: *Scope, owner: c.JSValue) !c.JSValue {
    return optional(scope, try optional(scope, try scope.get(owner, "options"), "signal"), "aborted");
}
fn finish(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    // Destructuring the fulfilled exec result is itself inside Source's try.
    var failure = rejected;
    var reason = value;
    if (!failure) {
        const exit = scope.get(value, "exitCode") catch |err| failed: {
            failure = true;
            reason = try scope.own(flow.reason(engine, err));
            break :failed c.pi_js_null();
        };
        if (!failure) try scope.put(owner, "exitCode", exit);
    }
    if (failure and !scope.truthy(try aborted(&scope, owner))) {
        try close(engine, owner);
        return flow.settle(engine, owner, true, reason);
    }
    const rest = try scope.concat(try scope.get(owner, "pendingAnsi"), try scope.invoke(try scope.get(owner, "decoder"), "decode", &.{}));
    try scope.put(owner, "pendingAnsi", try scope.text(""));
    try append(engine, owner, rest);
    const full = try scope.invoke(try scope.get(owner, "chunks"), "join", &.{try scope.text("")});
    const tail = try scope.own(try truncateTail(engine, full));
    const truncated = try scope.get(tail, "truncated");
    if (scope.truthy(truncated)) try ensureFile(engine, owner);
    try close(engine, owner);
    const cancel_value = try aborted(&scope, owner);
    const cancelled = if (temp.nullish(cancel_value)) c.pi_js_bool(engine.context, 0) else cancel_value;
    const result = try scope.object();
    try scope.put(result, "output", if (scope.truthy(truncated)) try scope.get(tail, "content") else full);
    const exit = try scope.get(owner, "exitCode");
    try scope.put(result, "exitCode", if (scope.truthy(cancelled) or temp.nullish(exit)) c.pi_js_undefined() else exit);
    try scope.put(result, "cancelled", cancelled);
    try scope.put(result, "truncated", truncated);
    try scope.put(result, "fullOutputPath", try scope.get(owner, "tempFilePath"));
    try flow.settle(engine, owner, false, result);
}
pub fn truncateTail(engine: *em.Engine, input: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const raw = try utf8(engine, input);
    defer engine.gpa.free(raw);
    const lines = if (try sdk.length(engine, input) == 0) try scope.array() else try scope.invoke(input, "split", &.{try scope.text("\n")});
    if (scope.truthy(try scope.invoke(input, "endsWith", &.{try scope.text("\n")}))) _ = try scope.invoke(lines, "pop", &.{});
    const total_lines = try sdk.length(engine, lines);
    const truncated = total_lines > 2000 or raw.len > max_bytes;
    const result = try scope.object();
    if (!truncated) {
        try scope.put(result, "content", input);
        try scope.put(result, "truncated", c.pi_js_bool(engine.context, 0));
        return c.JS_DupValue(engine.context, result);
    }
    const selected = try scope.array();
    var bytes: usize = 0;
    var at = total_lines;
    while (at > 0 and try sdk.length(engine, selected) < 2000) {
        at -= 1;
        const line = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, lines, at)));
        const encoded = try utf8(engine, line);
        defer engine.gpa.free(encoded);
        const line_bytes = encoded.len + @as(usize, if (try sdk.length(engine, selected) > 0) 1 else 0);
        if (bytes + line_bytes > max_bytes) {
            if (try sdk.length(engine, selected) == 0) {
                var start_at = encoded.len - max_bytes;
                while (start_at < encoded.len and encoded[start_at] & 0xc0 == 0x80) start_at += 1;
                _ = try scope.invoke(selected, "unshift", &.{try scope.text(encoded[start_at..])});
            }
            break;
        }
        _ = try scope.invoke(selected, "unshift", &.{line});
        bytes += line_bytes;
    }
    try scope.put(result, "content", try scope.invoke(selected, "join", &.{try scope.text("\n")}));
    try scope.put(result, "truncated", c.pi_js_bool(engine.context, 1));
    return c.JS_DupValue(engine.context, result);
}
