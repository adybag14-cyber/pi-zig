// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Actual fs.realpathSync component walk. JS locals remain VM values; native
//! stat/lstat/readlink supply the real OS status and the shared stat arrays.
//! The caller owns the activation until encoding and function completion.
const std = @import("std");
const builtin = @import("builtin");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = @import("native_node_operation_scope.zig").Scope;
const owned = @import("native_sdk_owned_completion.zig");
const frames = @import("native_public_lexical_frame.zig");
const stat = @import("native_file_stat.zig");
const stat_values = @import("native_node_fs_stat_values.zig");
const errors = @import("native_node_fs_private_error.zig");
const realm = @import("native_node_internal_realm.zig");
const Operation = @import("native_image_arithmetic.zig").Operation;
pub const Names = enum {
    p, options, cache, maybe_cached_result, seen_links, known_hard, original,
    pos, current, base, previous, initial_out, result, last, resolved_link,
    maybe_cached_resolved, stats, link_target, id, dev, ino, restart_out,
};
pub const Activation = frames.Frame(Names);
pub const Imports = struct {
    paths: c.JSValue,
    safe_map: c.JSValue,
    safe_set: c.JSValue,
    stat_owner: c.JSValue,
    string_slice: c.JSValue,
    string_index_of: c.JSValue,
    string_char_code_at: c.JSValue,
    bigint_to_string: c.JSValue,
    number: c.JSValue,
    root_regex: c.JSValue,
};
fn duplicate(engine: *v.em.Engine, value: c.JSValue) c.JSValue { return c.JS_DupValue(engine.context, value); }
fn integer(engine: *v.em.Engine, value: i32) c.JSValue { return c.JS_NewInt32(engine.context, value); }
fn equal(engine: *v.em.Engine, a: c.JSValue, b: c.JSValue) bool { return c.JS_IsStrictEqual(engine.context, a, b); }
fn truthy(engine: *v.em.Engine, value: c.JSValue) bool { return c.JS_ToBool(engine.context, value) == 1; }
fn finishFrame(s: *Scope, frame: anytype, result: anyerror!c.JSValue) !c.JSValue {
    var completion = owned.Completion.initValue(s.engine, result);
    frame.close(&completion);
    return s.finish(completion.finishValue());
}
fn reset(frame: *Activation, comptime names: anytype) !void {
    inline for (names) |name| try frame.clear(name);
}
fn getBody(s: *Scope, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return duplicate(s.engine, try s.get(receiver, name));
}
pub fn get(engine: *v.em.Engine, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    var s = Scope.init(engine); return s.finish(getBody(&s, receiver, name));
}
fn callBody(s: *Scope, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return duplicate(s.engine, try s.call(function, receiver, args));
}
pub fn call(engine: *v.em.Engine, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    var s = Scope.init(engine); return s.finish(callBody(&s, function, receiver, args));
}
fn constructBody(s: *Scope, function: c.JSValue) !c.JSValue { return duplicate(s.engine, try s.construct(function, &.{})); }
fn construct(engine: *v.em.Engine, function: c.JSValue) !c.JSValue {
    var s = Scope.init(engine); return s.finish(constructBody(&s, function));
}
fn invokeBody(s: *Scope, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue, optional: bool) !c.JSValue {
    if (optional and v.nullish(receiver)) return c.pi_js_undefined();
    return duplicate(s.engine, try s.call(try s.get(receiver, name), receiver, args));
}
fn invoke(engine: *v.em.Engine, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue, optional: bool) !c.JSValue {
    var s = Scope.init(engine); return s.finish(invokeBody(&s, receiver, name, args, optional));
}
fn discardBody(s: *Scope, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue, optional: bool) !c.JSValue {
    if (optional and v.nullish(receiver)) return c.pi_js_undefined();
    _ = try s.call(try s.get(receiver, name), receiver, args);
    return c.pi_js_undefined();
}
fn discard(engine: *v.em.Engine, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue, optional: bool) !void {
    var s = Scope.init(engine); _ = try s.finish(discardBody(&s, receiver, name, args, optional));
}
fn testCallBody(s: *Scope, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const result = try s.call(try s.get(receiver, name), receiver, args);
    return c.pi_js_bool(s.engine.context, @intFromBool(s.truthy(result)));
}
fn testCall(engine: *v.em.Engine, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !bool {
    var s = Scope.init(engine); return truthy(engine, try s.finish(testCallBody(&s, receiver, name, args)));
}
fn cacheEqualBody(s: *Scope, cache: c.JSValue, path: c.JSValue) !c.JSValue {
    const result = if (v.nullish(cache)) c.pi_js_undefined() else try s.call(try s.get(cache, "get"), cache, &.{path});
    return c.pi_js_bool(s.engine.context, @intFromBool(s.equal(result, path)));
}
fn cacheEqual(engine: *v.em.Engine, cache: c.JSValue, path: c.JSValue) !bool {
    var s = Scope.init(engine); return truthy(engine, try s.finish(cacheEqualBody(&s, cache, path)));
}
fn binaryBody(s: *Scope, operation: Operation, a: c.JSValue, b: c.JSValue) !c.JSValue {
    return duplicate(s.engine, try s.binary(@intFromEnum(operation), a, b));
}
fn binary(engine: *v.em.Engine, operation: Operation, a: c.JSValue, b: c.JSValue) !c.JSValue {
    var s = Scope.init(engine); return s.finish(binaryBody(&s, operation, a, b));
}
fn lessLengthBody(s: *Scope, position: c.JSValue, input: c.JSValue) !c.JSValue {
    const length = try s.get(input, "length");
    const result = try s.binary(@intFromEnum(Operation.less), position, length);
    return c.pi_js_bool(s.engine.context, @intFromBool(s.truthy(result)));
}
fn lessLength(engine: *v.em.Engine, position: c.JSValue, input: c.JSValue) !bool {
    var s = Scope.init(engine); return truthy(engine, try s.finish(lessLengthBody(&s, position, input)));
}
fn incrementBody(s: *Scope, value: c.JSValue) !c.JSValue {
    try s.pending();
    return duplicate(s.engine, try s.checked(c.JS_PiIncrement(s.engine.context, value)));
}
fn increment(engine: *v.em.Engine, value: c.JSValue) !c.JSValue {
    var s = Scope.init(engine); return s.finish(incrementBody(&s, value));
}
fn charCodeIsSlashBody(s: *Scope, imports: Imports, input: c.JSValue, position: c.JSValue) !c.JSValue {
    const code = try s.call(imports.string_char_code_at, input, &.{position});
    return c.pi_js_bool(s.engine.context, @intFromBool(s.equal(code, integer(s.engine, '/'))));
}
fn charCodeIsSlash(engine: *v.em.Engine, imports: Imports, input: c.JSValue, position: c.JSValue) !bool {
    var s = Scope.init(engine); return truthy(engine, try s.finish(charCodeIsSlashBody(&s, imports, input, position)));
}
const Cursor = frames.Frame(enum { input, position, character });
fn splitRootBody(s: *Scope, frame: *Cursor, imports: Imports) !c.JSValue {
    if (builtin.os.tag == .windows) {
        // Source lazily initializes the actual private realm at first use.
        const internal = try s.own(try realm.acquire(s.engine));
        const result = try realm.regexpExec(s, internal, imports.root_regex, frame.get(.input));
        return duplicate(s.engine, try s.getKey(result, integer(s.engine, 0)));
    }
    var steps: usize = 0;
    while (try lessLength(s.engine, frame.get(.position), frame.get(.input))) {
        try @import("native_node_commonjs_interrupt.zig").step(s.engine, &steps);
        if (!try charCodeIsSlash(s.engine, imports, frame.get(.input), frame.get(.position)))
            return call(s.engine, imports.string_slice, frame.get(.input), &.{integer(s.engine, 0), frame.get(.position)});
        try frame.take(.position, increment(s.engine, frame.get(.position)));
    }
    return duplicate(s.engine, frame.get(.input));
}
fn splitRoot(engine: *v.em.Engine, imports: Imports, input: c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    const frame = Cursor.create(&s.values) catch |err| return s.finish(err);
    const result: anyerror!c.JSValue = body: {
        frame.copy(.input, input) catch |err| break :body err;
        frame.take(.position, integer(engine, 0)) catch |err| break :body err;
        break :body splitRootBody(&s, frame, imports);
    };
    return finishFrame(&s, frame, result);
}
fn nextPartBody(s: *Scope, frame: *Cursor, imports: Imports) !c.JSValue {
    if (builtin.os.tag != .windows)
        return duplicate(s.engine, try s.call(imports.string_index_of, frame.get(.input), &.{try s.text("/"), frame.get(.position)}));
    var steps: usize = 0;
    while (try lessLength(s.engine, frame.get(.position), frame.get(.input))) {
        try @import("native_node_commonjs_interrupt.zig").step(s.engine, &steps);
        // The last ch survives a false next condition; reset only on true entry.
        try frame.clear(.character);
        try frame.take(.character, call(s.engine, imports.string_char_code_at, frame.get(.input), &.{frame.get(.position)}));
        if (equal(s.engine, frame.get(.character), integer(s.engine, '\\')) or equal(s.engine, frame.get(.character), integer(s.engine, '/')))
            return duplicate(s.engine, frame.get(.position));
        try frame.take(.position, increment(s.engine, frame.get(.position)));
    }
    return integer(s.engine, -1);
}
fn nextPart(engine: *v.em.Engine, imports: Imports, input: c.JSValue, position: c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    const frame = Cursor.create(&s.values) catch |err| return s.finish(err);
    const result: anyerror!c.JSValue = body: {
        frame.copy(.input, input) catch |err| break :body err;
        frame.copy(.position, position) catch |err| break :body err;
        break :body nextPartBody(&s, frame, imports);
    };
    return finishFrame(&s, frame, result);
}
fn appendSliceBody(s: *Scope, imports: Imports, prefix: c.JSValue, input: c.JSValue, position: c.JSValue, end: c.JSValue, trailing: bool) !c.JSValue {
    const limit = if (trailing) try s.binary(@intFromEnum(Operation.add), end, integer(s.engine, 1)) else end;
    const suffix = try s.call(imports.string_slice, input, &.{position, limit});
    return duplicate(s.engine, try s.binary(@intFromEnum(Operation.add), prefix, suffix));
}
fn appendSlice(engine: *v.em.Engine, imports: Imports, prefix: c.JSValue, input: c.JSValue, position: c.JSValue, end: c.JSValue, trailing: bool) !c.JSValue {
    var s = Scope.init(engine); return s.finish(appendSliceBody(&s, imports, prefix, input, position, end, trailing));
}
fn resolveRestBody(s: *Scope, imports: Imports, resolved: c.JSValue, input: c.JSValue, position: c.JSValue) !c.JSValue {
    // The live resolve getter precedes evaluation of the second argument.
    const function = try s.get(imports.paths, "resolve");
    const suffix = try s.call(imports.string_slice, input, &.{position});
    return duplicate(s.engine, try s.call(function, imports.paths, &.{resolved, suffix}));
}
fn resolveRest(engine: *v.em.Engine, imports: Imports, resolved: c.JSValue, input: c.JSValue, position: c.JSValue) !c.JSValue {
    var s = Scope.init(engine); return s.finish(resolveRestBody(&s, imports, resolved, input, position));
}
fn idPartBody(s: *Scope, imports: Imports, stats: c.JSValue, position: i32) !c.JSValue {
    const value = try s.getKey(stats, integer(s.engine, position));
    return duplicate(s.engine, try s.call(imports.bigint_to_string, value, &.{integer(s.engine, 32)}));
}
fn idPart(engine: *v.em.Engine, imports: Imports, stats: c.JSValue, position: i32) !c.JSValue {
    var s = Scope.init(engine); return s.finish(idPartBody(&s, imports, stats, position));
}
fn idBody(s: *Scope, dev: c.JSValue, ino: c.JSValue) !c.JSValue {
    // Template-literal substitutions use string hint, separately and in order.
    const first = try s.toString(dev);
    const prefix = try s.binary(@intFromEnum(Operation.add), first, try s.text(":"));
    return duplicate(s.engine, try s.binary(@intFromEnum(Operation.add), prefix, try s.toString(ino)));
}
fn linkId(engine: *v.em.Engine, dev: c.JSValue, ino: c.JSValue) !c.JSValue {
    var s = Scope.init(engine); return s.finish(idBody(&s, dev, ino));
}
fn isFileTypeBody(s: *Scope, imports: Imports, stats: c.JSValue, kind: i32) !c.JSValue {
    var mode = try s.getKey(stats, integer(s.engine, 1));
    if (c.JS_IsBigInt(mode)) mode = try s.call(imports.number, c.pi_js_undefined(), &.{mode});
    const masked = try s.binary(@intFromEnum(Operation.bit_and), mode, integer(s.engine, 0o170000));
    return c.pi_js_bool(s.engine.context, @intFromBool(s.equal(masked, integer(s.engine, kind))));
}
fn isFileType(engine: *v.em.Engine, imports: Imports, stats: c.JSValue, kind: i32) !bool {
    var s = Scope.init(engine); return truthy(engine, try s.finish(isFileTypeBody(&s, imports, stats, kind)));
}
fn pathBytes(s: *Scope, value: c.JSValue) ![]u8 {
    if (!c.JS_IsString(value)) return error.RequiredActualFsBindingString;
    const bytes = try s.engine.toString(value);
    errdefer s.engine.gpa.free(bytes);
    try s.pending();
    return bytes;
}
fn metadataFailure(s: *Scope, windows: bool, raw: u32, operation: []const u8, path: []const u8) !stat.Stat {
    _ = try errors.throw(s, if (windows) errors.windowsCode(raw, false) else try errors.posixCode(raw), operation, path);
    unreachable;
}
fn readMetadata(s: *Scope, path: []const u8, follow: bool) !stat.Stat {
    try s.pending();
    // The binding's actual ToNamespacedPath runs before its OS request. Keep
    // those same bytes for UVException after the native owner has closed.
    const native_path = try @import("native_node_package_path.zig").namespaced(s.engine.gpa, path);
    defer s.engine.gpa.free(native_path);
    if (follow) return switch (try stat.readWithStatus(s.engine.gpa, native_path)) {
        .metadata => |value| value,
        .windows_error => |raw| metadataFailure(s, true, raw, "stat", native_path),
        .posix_error => |raw| metadataFailure(s, false, raw, "stat", native_path),
    };
    return switch (try stat.readLinkWithStatus(s.engine.gpa, native_path)) {
        .metadata => |value| value,
        .windows_error => |raw| metadataFailure(s, true, raw, "lstat", native_path),
        .posix_error => |raw| metadataFailure(s, false, raw, "lstat", native_path),
    };
}
fn bindingStatBody(s: *Scope, imports: Imports, path_value: c.JSValue, use_bigint: bool, follow: bool) !c.JSValue {
    const path = try pathBytes(s, path_value); defer s.engine.gpa.free(path);
    const info = try readMetadata(s, path, follow);
    try s.pending();
    return stat_values.record(s.engine, imports.stat_owner, use_bigint, info, false);
}
fn bindingStat(engine: *v.em.Engine, imports: Imports, path: c.JSValue, use_bigint: bool, follow: bool) !c.JSValue {
    var s = Scope.init(engine); return s.finish(bindingStatBody(&s, imports, path, use_bigint, follow));
}
fn discardStatBody(s: *Scope, imports: Imports, path: c.JSValue) !c.JSValue {
    _ = try s.own(try bindingStat(s.engine, imports, path, false, true));
    return c.pi_js_undefined();
}
fn discardStat(engine: *v.em.Engine, imports: Imports, path: c.JSValue) !void {
    var s = Scope.init(engine); _ = try s.finish(discardStatBody(&s, imports, path));
}
fn readlinkBody(s: *Scope, path_value: c.JSValue) !c.JSValue {
    const supplied = try pathBytes(s, path_value); defer s.engine.gpa.free(supplied);
    const path = try @import("native_node_package_path.zig").namespaced(s.engine.gpa, supplied);
    defer s.engine.gpa.free(path);
    try s.pending();
    const bytes = switch (try stat.readLinkBytesWithStatus(s.engine.gpa, path)) {
        .bytes => |value| value,
        .windows_error => |raw| { _ = try errors.throw(s, errors.windowsCode(raw, true), "readlink", path); unreachable; },
        .posix_error => |raw| { _ = try errors.throw(s, try errors.posixCode(raw), "readlink", path); unreachable; },
    };
    defer bytes.deinit(s.engine.gpa);
    return duplicate(s.engine, try s.text(bytes.slice()));
}
fn readlink(engine: *v.em.Engine, path: c.JSValue) !c.JSValue {
    var s = Scope.init(engine); return s.finish(readlinkBody(&s, path));
}
fn root(engine: *v.em.Engine, frame: *Activation, imports: Imports) !void {
    try frame.take(.base, splitRoot(engine, imports, frame.get(.p)));
    try frame.copy(.current, frame.get(.base));
    try frame.take(.pos, get(engine, frame.get(.current), "length"));
}
pub const Result = struct { value: c.JSValue, cache_hit: bool };
pub fn walk(engine: *v.em.Engine, frame: *Activation, imports: Imports) !Result {
    try frame.take(.maybe_cached_result, invoke(engine, frame.get(.cache), "get", &.{frame.get(.p)}, true));
    if (truthy(engine, frame.get(.maybe_cached_result)))
        return .{ .value = duplicate(engine, frame.get(.maybe_cached_result)), .cache_hit = true };
    try frame.take(.seen_links, construct(engine, imports.safe_map));
    try frame.take(.known_hard, construct(engine, imports.safe_set));
    try frame.copy(.original, frame.get(.p));
    try root(engine, frame, imports);
    if (builtin.os.tag == .windows) {
        try frame.clear(.initial_out);
        try frame.take(.initial_out, bindingStat(engine, imports, frame.get(.base), false, false));
        if (c.JS_IsUndefined(frame.get(.initial_out))) return .{ .value = c.pi_js_undefined(), .cache_hit = true };
        try discard(engine, frame.get(.known_hard), "add", &.{frame.get(.base)}, false);
    }
    var steps: usize = 0;
    while (try lessLength(engine, frame.get(.pos), frame.get(.p))) {
        try @import("native_node_commonjs_interrupt.zig").step(engine, &steps);
        // BCDF true-body entry initializes lexical slots in reverse declaration
        // order. A false condition/break keeps prior locals until function exit.
        try reset(frame, .{ .maybe_cached_resolved, .resolved_link, .result });
        try frame.take(.result, nextPart(engine, imports, frame.get(.p), frame.get(.pos)));
        try frame.copy(.previous, frame.get(.current));
        if (equal(engine, frame.get(.result), integer(engine, -1))) {
            try frame.clear(.last);
            try frame.take(.last, call(engine, imports.string_slice, frame.get(.p), &.{frame.get(.pos)}));
            try frame.take(.current, binary(engine, .add, frame.get(.current), frame.get(.last)));
            try frame.take(.base, binary(engine, .add, frame.get(.previous), frame.get(.last)));
            try frame.take(.pos, get(engine, frame.get(.p), "length"));
        } else {
            try frame.take(.current, appendSlice(engine, imports, frame.get(.current), frame.get(.p), frame.get(.pos), frame.get(.result), true));
            try frame.take(.base, appendSlice(engine, imports, frame.get(.previous), frame.get(.p), frame.get(.pos), frame.get(.result), false));
            try frame.take(.pos, binary(engine, .add, frame.get(.result), integer(engine, 1)));
        }
        if (try testCall(engine, frame.get(.known_hard), "has", &.{frame.get(.base)}) or try cacheEqual(engine, frame.get(.cache), frame.get(.base))) {
            if (try isFileType(engine, imports, stat_values.numeric(imports.stat_owner), 0o010000) or
                try isFileType(engine, imports, stat_values.numeric(imports.stat_owner), 0o140000)) break;
            continue;
        }
        try frame.take(.resolved_link, c.pi_js_undefined());
        try frame.take(.maybe_cached_resolved, invoke(engine, frame.get(.cache), "get", &.{frame.get(.base)}, true));
        if (truthy(engine, frame.get(.maybe_cached_resolved))) {
            try frame.copy(.resolved_link, frame.get(.maybe_cached_resolved));
        } else {
            try reset(frame, .{ .id, .link_target, .stats });
            try frame.take(.stats, bindingStat(engine, imports, frame.get(.base), true, false));
            if (c.JS_IsUndefined(frame.get(.stats))) return .{ .value = c.pi_js_undefined(), .cache_hit = true };
            if (!try isFileType(engine, imports, frame.get(.stats), 0o120000)) {
                try discard(engine, frame.get(.known_hard), "add", &.{frame.get(.base)}, false);
                try discard(engine, frame.get(.cache), "set", &.{frame.get(.base), frame.get(.base)}, true);
                continue;
            }
            try frame.take(.link_target, c.pi_js_null());
            try frame.take(.id, c.pi_js_undefined());
            if (builtin.os.tag != .windows) {
                try reset(frame, .{ .ino, .dev });
                try frame.take(.dev, idPart(engine, imports, frame.get(.stats), 0));
                try frame.take(.ino, idPart(engine, imports, frame.get(.stats), 7));
                try frame.take(.id, linkId(engine, frame.get(.dev), frame.get(.ino)));
                if (try testCall(engine, frame.get(.seen_links), "has", &.{frame.get(.id)}))
                    try frame.take(.link_target, invoke(engine, frame.get(.seen_links), "get", &.{frame.get(.id)}, false));
            }
            if (c.JS_IsNull(frame.get(.link_target))) {
                try discardStat(engine, imports, frame.get(.base));
                try frame.take(.link_target, readlink(engine, frame.get(.base)));
            }
            try frame.take(.resolved_link, invoke(engine, imports.paths, "resolve", &.{frame.get(.previous), frame.get(.link_target)}, false));
            try discard(engine, frame.get(.cache), "set", &.{frame.get(.base), frame.get(.resolved_link)}, true);
            if (builtin.os.tag != .windows)
                try discard(engine, frame.get(.seen_links), "set", &.{frame.get(.id), frame.get(.link_target)}, false);
        }
        try frame.take(.p, resolveRest(engine, imports, frame.get(.resolved_link), frame.get(.p), frame.get(.pos)));
        try root(engine, frame, imports);
        if (builtin.os.tag == .windows and !try testCall(engine, frame.get(.known_hard), "has", &.{frame.get(.base)})) {
            try frame.clear(.restart_out);
            try frame.take(.restart_out, bindingStat(engine, imports, frame.get(.base), false, false));
            if (c.JS_IsUndefined(frame.get(.restart_out))) return .{ .value = c.pi_js_undefined(), .cache_hit = true };
            try discard(engine, frame.get(.known_hard), "add", &.{frame.get(.base)}, false);
        }
    }
    try discard(engine, frame.get(.cache), "set", &.{frame.get(.original), frame.get(.p)}, true);
    return .{ .value = duplicate(engine, frame.get(.p)), .cache_hit = false };
}
