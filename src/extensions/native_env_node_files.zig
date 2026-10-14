//! Source NodeExecutionEnv filesystem methods, with VM-owned continuations around native jobs.
const std = @import("std");
const builtin = @import("builtin");
const js = @import("native_js_values.zig");
const h = @import("native_env_remote_helpers.zig");
const errors = @import("native_env_node_errors.zig");
const readers = @import("native_env_node_readers.zig");
const paths = @import("native_env_node_path.zig");
const Method = @import("native_env_node_methods.zig").Method;
const Scope = h.Scope;
const c = js.c;
const Stage = enum(c_int) { binary_lstat, result, opened_text, opened_binary, binary_stat, binary_close, mkdir_write, mkdir_append, appended, truncate_open, truncated, flush_open, flush_stat, synced, finally_close, list, list_stat, opened_dir, temp_dir, temp_file, after_abort_close };
fn methodValue(scope: *Scope, saved: c.JSValue) !Method {
    var raw: i32 = undefined;
    if (c.JS_ToInt32(scope.engine.context, &raw, try scope.get(saved, "method")) < 0) return js.capture(scope.engine);
    return @enumFromInt(raw);
}
fn cachedSignal(method: Method) bool {
    return switch (method) {
        .readTextFile, .readBinaryFile, .writeFile, .appendFile, .truncateFile, .flushFile, .listDir => true,
        else => false,
    };
}
fn aborted(scope: *Scope, saved: c.JSValue) !?c.JSValue {
    const signal = if (cachedSignal(try methodValue(scope, saved))) try scope.get(saved, "signal") else try scope.get(try scope.get(saved, "context"), "abortSignal");
    if (!h.nullish(signal) and scope.truthy(try scope.get(signal, "aborted"))) return try errors.expected(scope, try scope.get(saved, "bindings"), "aborted", "aborted", try scope.get(saved, "path"));
    return null;
}
fn signalOptions(scope: *Scope, saved: c.JSValue) !c.JSValue {
    const options = try scope.object();
    try scope.put(options, "signal", try scope.get(saved, "signal"));
    return options;
}
fn failed(scope: *Scope, saved: c.JSValue, reason: c.JSValue) !c.JSValue {
    return errors.failed(scope, try scope.get(saved, "bindings"), reason, try scope.get(saved, "path"));
}
fn wait(scope: *Scope, saved: c.JSValue, pending: c.JSValue, stage: Stage) !c.JSValue {
    return h.wait(advance, scope, saved, pending, stage);
}
fn fs(scope: *Scope, saved: c.JSValue, name: [*:0]const u8, args: []const c.JSValue, stage: Stage) !c.JSValue {
    return wait(scope, saved, try scope.invoke(try scope.get(try scope.get(saved, "bindings"), "fs"), name, args), stage);
}
fn closeReturning(scope: *Scope, saved: c.JSValue, result: c.JSValue, stage: Stage) !c.JSValue {
    try scope.put(saved, "returning", result);
    return wait(scope, saved, try scope.invoke(try scope.get(saved, "file"), "close", &.{}), stage);
}
fn makeReader(scope: *Scope, saved: c.JSValue, kind: readers.Kind) !c.JSValue {
    const constructor = try scope.get(try scope.get(saved, "bindings"), switch (kind) {
        .binary => "NodeBinaryReader",
        .text => "NodeTextLineReader",
        .directory => "NodeDirReader",
    });
    const args = [_]c.JSValue{ try scope.get(saved, "file"), try scope.get(saved, "path") };
    const reader = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, args.len, @constCast(&args))));
    return h.values.result(scope, true, reader);
}
fn listNext(scope: *Scope, saved: c.JSValue) !c.JSValue {
    const entries = try scope.get(saved, "entries");
    const index = try scope.get(saved, "index");
    const length = try scope.get(entries, "length");
    if (scope.equal(index, length)) return h.values.result(scope, true, try scope.get(saved, "infos"));
    if (try aborted(scope, saved)) |result| return result;
    const entry = try scope.own(try js.getKey(scope.engine, entries, index));
    const entry_path = try scope.invoke(try scope.get(try scope.get(saved, "bindings"), "paths"), "resolve", &.{ try scope.get(saved, "path"), try scope.get(entry, "name") });
    try scope.put(saved, "entryPath", entry_path);
    return fs(scope, saved, "lstat", &.{entry_path}, .list_stat);
}
fn step(scope: *Scope, saved: c.JSValue, value: c.JSValue, rejected: bool, stage: Stage) !c.JSValue {
    if (stage == .finally_close or stage == .after_abort_close or stage == .binary_close) return try scope.get(saved, "returning");
    const method = try methodValue(scope, saved);
    const bindings = try scope.get(saved, "bindings");
    const path = try scope.get(saved, "path");
    if (rejected) {
        if (stage == .temp_dir) return h.throw(scope, value);
        if (stage == .opened_binary and scope.truthy(try scope.get(saved, "noFollow"))) {
            const code = try h.optional(scope, value, "code");
            const is_error = c.JS_IsInstanceOf(scope.engine.context, value, try scope.global("Error"));
            if (is_error < 0) return js.capture(scope.engine);
            if (is_error != 0 and (scope.equal(code, try scope.text("ELOOP")) or scope.equal(code, try scope.text("EMLINK")))) {
                const args = [_]c.JSValue{ try scope.text("invalid"), try scope.text("Refusing to follow a symbolic link"), path, try scope.call(try scope.get(bindings, "toError"), c.pi_js_undefined(), &.{value}) };
                return h.values.result(scope, false, try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.get(bindings, "FileError"), args.len, @constCast(&args)))));
            }
        }
        const result = try errors.failed(scope, bindings, value, if (stage == .list_stat) try scope.get(saved, "entryPath") else path);
        if (stage == .binary_stat or stage == .truncated or stage == .flush_stat or stage == .synced) return closeReturning(scope, saved, result, .finally_close);
        return result;
    }
    switch (stage) {
        .binary_lstat => {
            if (scope.truthy(try scope.invoke(value, "isSymbolicLink", &.{}))) return errors.expected(scope, bindings, "invalid", "Refusing to follow a symbolic link", path);
            return fs(scope, saved, "open", &.{ path, c.JS_NewInt32(scope.engine.context, 0) }, .opened_binary);
        },
        .opened_text, .opened_binary, .opened_dir => {
            try scope.put(saved, "file", value);
            if (stage == .opened_binary) return wait(scope, saved, try scope.invoke(value, "stat", &.{}), .binary_stat);
            if (try aborted(scope, saved)) |result| return closeReturning(scope, saved, result, .after_abort_close);
            return makeReader(scope, saved, if (stage == .opened_text) .text else .directory);
        },
        .binary_stat => {
            if (!scope.truthy(try scope.invoke(value, "isFile", &.{}))) {
                const directory = scope.truthy(try scope.invoke(value, "isDirectory", &.{}));
                return closeReturning(scope, saved, try errors.expected(scope, bindings, if (directory) "is_directory" else "invalid", if (directory) "EISDIR: illegal operation on a directory, read" else "Not a regular file", path), .binary_close);
            }
            if (try aborted(scope, saved)) |result| return closeReturning(scope, saved, result, .after_abort_close);
            return makeReader(scope, saved, .binary);
        },
        .mkdir_write, .mkdir_append => {
            if (try aborted(scope, saved)) |result| return result;
            if (stage == .mkdir_append) return fs(scope, saved, "appendFile", &.{ path, try scope.get(saved, "content") }, .appended);
            const options = try signalOptions(scope, saved);
            return fs(scope, saved, "writeFile", &.{ path, try scope.get(saved, "content"), options }, .result);
        },
        .appended => return (try aborted(scope, saved)) orelse try h.values.result(scope, true, c.pi_js_undefined()),
        .truncate_open, .flush_open => {
            try scope.put(saved, "file", value);
            return wait(scope, saved, if (stage == .truncate_open) try scope.invoke(value, "truncate", &.{try scope.get(saved, "size")}) else try scope.invoke(value, "stat", &.{}), if (stage == .truncate_open) .truncated else .flush_stat);
        },
        .flush_stat => {
            if (scope.truthy(try scope.invoke(value, "isDirectory", &.{}))) return closeReturning(scope, saved, try errors.expected(scope, bindings, "is_directory", "Is a directory", path), .finally_close);
            return wait(scope, saved, try scope.invoke(try scope.get(saved, "file"), "sync", &.{}), .synced);
        },
        .truncated, .synced => return closeReturning(scope, saved, (try aborted(scope, saved)) orelse try h.values.result(scope, true, c.pi_js_undefined()), .finally_close),
        .list => {
            try scope.put(saved, "entries", value);
            try scope.put(saved, "index", c.JS_NewInt32(scope.engine.context, 0));
            try scope.put(saved, "infos", try scope.array());
            return listNext(scope, saved);
        },
        .list_stat => {
            const info = try readers.fileInfo(scope, bindings, try scope.get(saved, "entryPath"), value);
            if (scope.truthy(try scope.get(info, "ok"))) _ = try scope.invoke(try scope.get(saved, "infos"), "push", &.{try scope.get(info, "value")});
            try scope.put(saved, "index", try scope.concat(try scope.get(saved, "index"), c.JS_NewInt32(scope.engine.context, 1)));
            return listNext(scope, saved);
        },
        .temp_dir => {
            if (!scope.truthy(try scope.get(value, "ok"))) return value;
            const options = try scope.get(saved, "options");
            const prefix = try h.optional(scope, options, "prefix");
            const prefix_text = try scope.stringify(if (h.nullish(prefix)) try scope.text("") else prefix);
            const uuid = try @import("../auth/pkce.zig").generateUuidV4(scope.engine.gpa, scope.engine.native_io.?);
            defer scope.engine.gpa.free(uuid);
            const suffix = try h.optional(scope, options, "suffix");
            const suffix_text = try scope.stringify(if (h.nullish(suffix)) try scope.text("") else suffix);
            const name = try scope.concat(try scope.concat(prefix_text, try scope.text(uuid)), suffix_text);
            const file_path = try scope.invoke(try scope.get(bindings, "paths"), "join", &.{ try scope.get(value, "value"), name });
            try scope.put(saved, "path", file_path);
            return fs(scope, saved, "writeFile", &.{ file_path, try scope.text("") }, .temp_file);
        },
        .temp_file => return h.values.result(scope, true, path),
        .result => {
            if (method == .fileInfo) return readers.fileInfo(scope, bindings, path, value);
            return h.values.result(scope, true, if (method == .readTextFile or method == .readBinaryFile or method == .canonicalPath or method == .createTempDir) value else c.pi_js_undefined());
        },
        else => unreachable,
    }
}
fn advance(engine: *js.Engine, saved: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const generation = engine.native_allocation_generation;
    const result = step(&scope, saved, value, rejected, @enumFromInt(raw)) catch |err| {
        if (engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
        if (@as(Stage, @enumFromInt(raw)) == .temp_dir) return err;
        _ = @import("native_durable.zig").reject(engine, err);
        return c.JS_DupValue(engine.context, try failed(&scope, saved, try scope.own(c.JS_GetException(engine.context))));
    };
    return c.JS_DupValue(engine.context, result);
}
fn start(scope: *Scope, saved: c.JSValue, args: []const c.JSValue, method: Method) !c.JSValue {
    const path = try scope.get(saved, "path");
    switch (method) {
        .openTextLineReader => return fs(scope, saved, "open", &.{ path, try scope.text("r") }, .opened_text),
        .openBinaryReader => {
            const options = try scope.object();
            const no_follow = scope.truthy(try scope.get(saved, "noFollow"));
            if (builtin.os.tag == .windows and no_follow) return fs(scope, saved, "lstat", &.{path}, .binary_lstat);
            try scope.put(options, "noFollow", c.pi_js_bool(scope.engine.context, @intFromBool(no_follow)));
            return fs(scope, saved, "open", &.{ path, c.JS_NewInt32(scope.engine.context, 0), options }, .opened_binary);
        },
        .readTextFile, .readBinaryFile => {
            const options = try signalOptions(scope, saved);
            if (method == .readTextFile) try scope.put(options, "encoding", try scope.text("utf8"));
            return fs(scope, saved, "readFile", &.{ path, options }, .result);
        },
        .writeFile, .appendFile => {
            try scope.put(saved, "content", h.arg(args, 1));
            const directory = try scope.invoke(try scope.get(try scope.get(saved, "bindings"), "paths"), "resolve", &.{ path, try scope.text("..") });
            const options = try scope.object();
            try scope.put(options, "recursive", c.pi_js_bool(scope.engine.context, 1));
            return fs(scope, saved, "mkdir", &.{ directory, options }, if (method == .writeFile) .mkdir_write else .mkdir_append);
        },
        .truncateFile, .flushFile => {
            return fs(scope, saved, "open", &.{ path, try scope.text("r+") }, if (method == .truncateFile) .truncate_open else .flush_open);
        },
        .renameFile => {
            const bindings = try scope.get(saved, "bindings");
            const destination = try paths.resolve(scope, bindings, try scope.get(try scope.get(saved, "self"), "cwd"), h.arg(args, 1));
            if (try errors.aborted(scope, bindings, try scope.get(saved, "context"), destination)) |result| return result;
            return fs(scope, saved, "rename", &.{ path, destination }, .result);
        },
        .fileInfo => return fs(scope, saved, "lstat", &.{path}, .result),
        .listDir => return fs(scope, saved, "readdir", &.{path}, .list),
        .openDirReader => return fs(scope, saved, "opendir", &.{path}, .opened_dir),
        .canonicalPath => return fs(scope, saved, "realpath", &.{path}, .result),
        .createDir => {
            const options = try scope.object();
            const recursive = try h.optional(scope, h.arg(args, 1), "recursive");
            try scope.put(options, "recursive", if (h.nullish(recursive)) c.pi_js_bool(scope.engine.context, 1) else recursive);
            return fs(scope, saved, "mkdir", &.{ path, options }, .result);
        },
        .remove => {
            const options = try scope.object();
            inline for (.{ "recursive", "force" }) |key| {
                const option = try h.optional(scope, h.arg(args, 1), key);
                try scope.put(options, key, if (h.nullish(option)) c.pi_js_bool(scope.engine.context, 0) else option);
            }
            return fs(scope, saved, "rm", &.{ path, options }, .result);
        },
        .createTempDir => {
            const prefix = if (h.nullish(h.arg(args, 0))) try scope.text("tmp-") else h.arg(args, 0);
            const joined = try scope.invoke(try scope.get(try scope.get(saved, "bindings"), "paths"), "join", &.{ try paths.temporary(scope), prefix });
            return fs(scope, saved, "mkdtemp", &.{joined}, .result);
        },
        .createTempFile => return wait(scope, saved, try scope.invoke(try scope.get(saved, "self"), "createTempDir", &.{ try scope.text("tmp-"), try scope.get(saved, "context") }), .temp_dir),
        else => return error.UnsupportedNativeNodeFilesystemMethod,
    }
}
pub fn invoke(engine: *js.Engine, receiver: c.JSValue, args: []const c.JSValue, bindings: c.JSValue, method: Method) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const saved = try scope.object();
    try scope.put(saved, "self", receiver);
    try scope.put(saved, "bindings", bindings);
    try scope.put(saved, "method", c.JS_NewInt32(engine.context, @intFromEnum(method)));
    try scope.put(saved, "options", h.arg(args, 0));
    const context = h.arg(args, switch (method) {
        .openBinaryReader, .writeFile, .appendFile, .truncateFile, .renameFile, .createDir, .remove => 2,
        else => 1,
    });
    try scope.put(saved, "context", context);
    const path = if (method == .createTempDir or method == .createTempFile) c.pi_js_undefined() else try paths.resolve(&scope, bindings, try scope.get(receiver, "cwd"), h.arg(args, 0));
    try scope.put(saved, "path", path);
    if (cachedSignal(method)) try scope.put(saved, "signal", try scope.get(context, "abortSignal"));
    // rename resolves both paths before its abort check, and reports the destination there.
    if (method != .createTempFile and method != .renameFile) if (try aborted(&scope, saved)) |result| return c.JS_DupValue(engine.context, result);
    if (method == .openBinaryReader) try scope.put(saved, "noFollow", c.pi_js_bool(engine.context, @intFromBool(scope.equal(try h.optional(&scope, h.arg(args, 1), "noFollow"), c.pi_js_bool(engine.context, 1)))));
    if (method == .truncateFile) {
        const size = h.arg(args, 1);
        if (!try h.validInteger(&scope, size, false)) return c.JS_DupValue(engine.context, try errors.expected(&scope, bindings, "invalid", "File size must be a non-negative safe integer", path));
        try scope.put(saved, "size", size);
    }
    if (method == .createTempFile) return c.JS_DupValue(engine.context, try start(&scope, saved, args, method));
    const generation = engine.native_allocation_generation;
    const result = start(&scope, saved, args, method) catch |err| {
        if (engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
        _ = @import("native_durable.zig").reject(engine, err);
        return c.JS_DupValue(engine.context, try failed(&scope, saved, try scope.own(c.JS_GetException(engine.context))));
    };
    return c.JS_DupValue(engine.context, result);
}
