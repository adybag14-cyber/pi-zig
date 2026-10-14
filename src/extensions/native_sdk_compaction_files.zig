//! Original compaction file-operation tracking over live guest sets/messages.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
const Export = enum { createFileOps, extractFileOpsFromMessage, computeFileLists, formatFileOperations };
pub fn exports(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.object();
    inline for (@import("std").meta.fields(Export)) |field| {
        const kind: Export = @enumFromInt(field.value);
        const arity = switch (kind) {
            .createFileOps => 0,
            .computeFileLists => 1,
            else => 2,
        };
        const function = try scope.own(try @import("native_node_function.zig").create(engine, field.name, arity, callback(kind), &.{}));
        try scope.put(result, field.name, function);
    }
    return c.JS_DupValue(engine.context, result);
}
fn callback(comptime kind: Export) @import("native_node_function.zig").Callback {
    return struct {
        fn call(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            engine.native_exception_diagnostics_suppressed += 1;
            defer engine.native_exception_diagnostics_suppressed -= 1;
            const first = if (args.len > 0) args[0] else c.pi_js_undefined();
            const second = if (args.len > 1) args[1] else c.pi_js_undefined();
            return switch (kind) {
                .createFileOps => create(engine),
                .extractFileOpsFromMessage => blk: {
                    try extract(engine, first, second);
                    break :blk c.pi_js_undefined();
                },
                .computeFileLists => lists(engine, first),
                .formatFileOperations => format(engine, first, second),
            };
        }
    }.call;
}
fn is(scope: *Scope, value: c.JSValue, text: []const u8) !bool {
    return scope.equal(value, try scope.text(text));
}
fn nullish(value: c.JSValue) bool {
    return c.JS_IsUndefined(value) or c.JS_IsNull(value);
}
fn iterate(scope: *Scope, value: c.JSValue) !js.Iterator {
    const symbol = try scope.own(try scope.engine.checked(c.JS_GetIteratorSymbol(scope.engine.context)));
    return js.Iterator.init(scope.engine, value, symbol);
}
pub fn create(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.object();
    inline for (.{ "read", "written", "edited" }) |name| try scope.put(result, name, try scope.own(try js.builtin(engine, "Set", &.{})));
    return c.JS_DupValue(engine.context, result);
}
fn add(engine: *em.Engine, name: c.JSValue, args: c.JSValue, operations: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var path = c.pi_js_undefined();
    if (!nullish(args) and c.JS_IsString(try scope.get(args, "path"))) path = try scope.get(args, "path");
    if (!scope.truthy(path)) return;
    if (try is(&scope, name, "read")) {
        _ = try scope.invoke(try scope.get(operations, "read"), "add", &.{path});
    } else if (try is(&scope, name, "write")) {
        _ = try scope.invoke(try scope.get(operations, "written"), "add", &.{path});
    } else if (try is(&scope, name, "edit")) {
        _ = try scope.invoke(try scope.get(operations, "edited"), "add", &.{path});
    }
}
pub fn extract(engine: *em.Engine, message: c.JSValue, operations: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (try is(&scope, try scope.get(message, "role"), "toolResult")) {
        const nested = try scope.get(message, "nestedCalls");
        var calls = if (nullish(nested)) c.pi_js_undefined() else try scope.get(nested, "calls");
        if (nullish(calls)) calls = try scope.array();
        var entries = try iterate(&scope, calls);
        defer entries.deinit();
        errdefer entries.closePreserving();
        while (try entries.next()) |entry| {
            defer engine.freeValue(entry);
            var step: Scope = .{ .engine = engine };
            defer step.deinit();
            const name = try step.get(entry, "name");
            try add(engine, name, try step.get(entry, "arguments"), operations);
        }
        return;
    }
    if (!try is(&scope, try scope.get(message, "role"), "assistant")) return;
    if (!try js.hasKey(engine, message, try scope.text("content"))) return;
    const array = try scope.global("Array");
    const is_array = try scope.get(array, "isArray");
    if (!scope.truthy(try scope.call(is_array, array, &.{try scope.get(message, "content")}))) return;
    var blocks = try iterate(&scope, try scope.get(message, "content"));
    defer blocks.deinit();
    errdefer blocks.closePreserving();
    while (try blocks.next()) |block| {
        defer engine.freeValue(block);
        if (!c.JS_IsObject(block) or c.JS_IsFunction(engine.context, block)) continue;
        var step: Scope = .{ .engine = engine };
        defer step.deinit();
        if (!try js.hasKey(engine, block, try step.text("type")) or !try is(&step, try step.get(block, "type"), "toolCall")) continue;
        if (!try js.hasKey(engine, block, try step.text("arguments")) or !try js.hasKey(engine, block, try step.text("name"))) continue;
        const name = try step.get(block, "name");
        try add(engine, name, try step.get(block, "arguments"), operations);
    }
}
pub fn lists(engine: *em.Engine, operations: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const constructor = try scope.global("Set");
    const values = try scope.array();
    var value_index: u32 = 0;
    inline for (.{ "edited", "written" }) |name| {
        var entries = try iterate(&scope, try scope.get(operations, name));
        defer entries.deinit();
        errdefer entries.closePreserving();
        while (try entries.next()) |value| {
            defer engine.freeValue(value);
            try scope.index(values, value_index, value);
            value_index += 1;
        }
    }
    const modified = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, constructor, 1, @constCast(&[_]c.JSValue{values}))));
    const reads = try scope.array();
    var read_index: u32 = 0;
    var read_entries = try iterate(&scope, try scope.get(operations, "read"));
    defer read_entries.deinit();
    errdefer read_entries.closePreserving();
    while (try read_entries.next()) |value| {
        defer engine.freeValue(value);
        try scope.index(reads, read_index, value);
        read_index += 1;
    }
    var roots = [_]c.JSValue{modified};
    const filter = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, readOnly, "", 1, 0, roots.len, &roots)));
    const read_only = try scope.invoke(reads, "filter", &.{filter});
    const read_files = try scope.invoke(read_only, "sort", &.{});
    const modified_values = try scope.array();
    var modified_index: u32 = 0;
    var modified_entries = try iterate(&scope, modified);
    defer modified_entries.deinit();
    errdefer modified_entries.closePreserving();
    while (try modified_entries.next()) |value| {
        defer engine.freeValue(value);
        try scope.index(modified_values, modified_index, value);
        modified_index += 1;
    }
    const modified_files = try scope.invoke(modified_values, "sort", &.{});
    const result = try scope.object();
    try scope.put(result, "readFiles", read_files);
    try scope.put(result, "modifiedFiles", modified_files);
    return c.JS_DupValue(engine.context, result);
}
fn readOnly(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const value = js.invoke(engine, roots[0], "has", &.{if (argc > 0) argv[0] else c.pi_js_undefined()}) catch |err| return @import("native_sdk.zig").fail(engine, err);
    defer engine.freeValue(value);
    return c.pi_js_bool(engine.context, @intFromBool(c.JS_ToBool(engine.context, value) == 0));
}
pub fn format(engine: *em.Engine, read_files: c.JSValue, modified_files: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const sections = try scope.array();
    inline for (.{ .{ read_files, "read-files" }, .{ modified_files, "modified-files" } }) |section| {
        if (try scope.positive(try scope.get(section[0], "length"))) {
            // The push callee is resolved before the template argument, just
            // as in sections.push(`<tag>\n${files.join("\n")}\n</tag>`).
            const push = try scope.get(sections, "push");
            const joined = try scope.stringify(try scope.invoke(section[0], "join", &.{try scope.text("\n")}));
            const start = try scope.text("<" ++ section[1] ++ ">\n");
            const end = try scope.text("\n</" ++ section[1] ++ ">");
            const text = try scope.concat(try scope.concat(start, joined), end);
            _ = try scope.call(push, sections, &.{text});
        }
    }
    if (scope.equal(try scope.get(sections, "length"), c.JS_NewInt32(engine.context, 0))) return @import("native_sdk.zig").text(engine, "");
    const joined = try scope.stringify(try scope.invoke(sections, "join", &.{try scope.text("\n\n")}));
    return c.JS_DupValue(engine.context, try scope.concat(try scope.text("\n\n"), joined));
}
