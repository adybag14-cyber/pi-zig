//! Actual c268 compaction file-operation utilities. Each source expression uses
//! AF33/C435, while source locals and plain for-of heads have explicit owners.
const std = @import("std");
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = v.c;
const Engine = v.em.Engine;
const Scope = v.Scope;
const cache_key = "\x00sdk-compaction-file-ops";
const Export = enum { createFileOps, extractFileOpsFromMessage, computeFileLists, formatFileOperations };
const AddFrame = h.Frame(enum { path });
const ExtractFrame = h.Frame(enum { call, block });
const ListsFrame = h.Frame(enum { modified, read_only, modified_files });
const FormatFrame = h.Frame(enum { sections });

pub fn exports(engine: *Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cache_key)) |cached| return h.duplicate(engine, cached);
    const candidate = try h.expression(engine, exportsBody, .{});
    if (engine.native_module_values.get(cache_key)) |cached| {
        var selected = v.owned.Completion.initValue(engine, h.duplicate(engine, cached));
        selected.release(candidate);
        return selected.finishValue();
    }
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var failed = v.owned.Completion.initValue(engine, @as(anyerror!c.JSValue, err));
        failed.release(candidate);
        return failed.finishValue();
    };
    engine.native_module_values.putAssumeCapacity(cache_key, candidate);
    return h.duplicate(engine, candidate);
}
fn exportsBody(s: *Scope) !c.JSValue {
    const result = try v.object(s);
    inline for (std.meta.fields(Export)) |field| {
        const kind: Export = @enumFromInt(field.value);
        const arity: c_int = switch (kind) { .createFileOps => 0, .computeFileLists => 1, else => 2 };
        try v.put(s, result, field.name, try v.ordinary(s, field.name, arity, callback(kind), &.{}));
    }
    return v.duplicate(s, result);
}
fn callback(comptime kind: Export) v.function.Callback {
    return struct {
        fn call(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            const first = v.arg(args, 0);
            const second = v.arg(args, 1);
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
fn createField(s: *Scope, result: c.JSValue, field: [*:0]const u8) !void {
    const set = try v.own(s, try h.construct(s.engine, "Set", &.{}));
    try v.put(s, result, field, set);
}
fn createBody(s: *Scope) !c.JSValue {
    const result = try v.object(s);
    inline for (.{ "read", "written", "edited" }) |name|
        try h.statement(s.engine, createField, .{ result, @as([*:0]const u8, name) });
    return v.duplicate(s, result);
}
pub fn create(engine: *Engine) !c.JSValue { return h.expression(engine, createBody, .{}); }

fn equalsText(s: *Scope, value: c.JSValue, expected: []const u8) !c.JSValue {
    return v.boolean(s, try v.eq(s, value, expected));
}
fn hasFieldBody(s: *Scope, receiver: c.JSValue, field: [*:0]const u8) !c.JSValue {
    if (!c.JS_IsObject(receiver)) return v.typeError(s, "invalid 'in' operand");
    const property = try v.text(s, std.mem.span(field));
    var atom_operation: v.guest.Boundary = .{ .engine = s.engine };
    try atom_operation.begin();
    const atom = c.JS_ValueToAtom(s.engine.context, property);
    defer if (atom != c.JS_ATOM_NULL) c.JS_FreeAtom(s.engine.context, atom);
    try atom_operation.finishStatus(if (atom == c.JS_ATOM_NULL) -1 else 0);
    var operation: v.guest.Boundary = .{ .engine = s.engine };
    try operation.begin();
    const found = c.JS_HasProperty(s.engine.context, receiver, atom);
    try operation.finishStatus(if (found < 0) -1 else 0);
    return v.boolean(s, found != 0);
}
fn hasField(engine: *Engine, receiver: c.JSValue, field: [*:0]const u8) !bool {
    return h.truthy(engine, try h.expression(engine, hasFieldBody, .{ receiver, field }));
}
fn addCall(s: *Scope, operations: c.JSValue, field: [*:0]const u8, path: c.JSValue) !void {
    const receiver = try v.get(s, operations, field);
    const method = try v.get(s, receiver, "add");
    _ = try v.call(s, method, receiver, &.{path});
}
fn addSource(f: *AddFrame, name: c.JSValue, args: c.JSValue, operations: c.JSValue) !void {
    const engine = f.engine;
    try f.set(.path, if (!v.nullish(args) and try h.fieldTest(engine, args, "path", .string))
        h.get(engine, args, "path") else c.pi_js_undefined());
    if (!h.truthy(engine, f.get(.path))) return;
    const field: [*:0]const u8 = if (h.truthy(engine, try h.expression(engine, equalsText, .{ name, @as([]const u8, "read") }))) "read" else
        if (h.truthy(engine, try h.expression(engine, equalsText, .{ name, @as([]const u8, "write") }))) "written" else
        if (h.truthy(engine, try h.expression(engine, equalsText, .{ name, @as([]const u8, "edit") }))) "edited" else return;
    return h.statement(engine, addCall, .{ operations, field, f.get(.path) });
}
fn add(engine: *Engine, name: c.JSValue, args: c.JSValue, operations: c.JSValue) !void {
    var f = AddFrame.init(engine);
    return f.finishVoid(addSource(&f, name, args, operations));
}
fn nestedCallLookup(s: *Scope, message: c.JSValue) !c.JSValue {
    const nested = try v.get(s, message, "nestedCalls");
    return if (v.nullish(nested)) c.pi_js_undefined() else v.duplicate(s, try v.get(s, nested, "calls"));
}
fn nestedCalls(s: *Scope, message: c.JSValue) !c.JSValue {
    // The optional-chain receiver retires before the nullish fallback array.
    const calls = try v.own(s, try h.expression(s.engine, nestedCallLookup, .{message}));
    return v.duplicate(s, if (v.nullish(calls)) try v.array(s) else calls);
}
fn extractCall(s: *Scope, entry: c.JSValue, operations: c.JSValue) !void {
    const name = try v.get(s, entry, "name");
    const arguments = try v.get(s, entry, "arguments");
    return add(s.engine, name, arguments, operations);
}
fn nestedSource(f: *ExtractFrame, iterator: *v.Iterator, operations: c.JSValue) !void {
    while (try iterator.next()) |entry| {
        try f.set(.call, entry);
        try h.statement(f.engine, extractCall, .{ f.get(.call), operations });
    }
}
fn arrayContent(s: *Scope, message: c.JSValue) !c.JSValue {
    const array = try v.global(s, "Array");
    const method = try v.get(s, array, "isArray");
    const content = try v.get(s, message, "content");
    return v.boolean(s, v.truthy(s, try v.call(s, method, array, &.{content})));
}
fn assistantSource(f: *ExtractFrame, iterator: *v.Iterator, operations: c.JSValue) !void {
    while (try iterator.next()) |block| {
        try f.set(.block, block);
        if (!c.JS_IsObject(f.get(.block)) or c.JS_IsFunction(f.engine.context, f.get(.block))) continue;
        if (!try hasField(f.engine, f.get(.block), "type") or !try h.fieldEqual(f.engine, f.get(.block), "type", "toolCall")) continue;
        if (!try hasField(f.engine, f.get(.block), "arguments") or !try hasField(f.engine, f.get(.block), "name")) continue;
        try h.statement(f.engine, extractCall, .{ f.get(.block), operations });
    }
}
fn extractSource(f: *ExtractFrame, message: c.JSValue, operations: c.JSValue) !void {
    const engine = f.engine;
    if (try h.fieldEqual(engine, message, "role", "toolResult")) {
        var iterator = try v.Iterator.initOwned(engine, try h.expression(engine, nestedCalls, .{message}));
        return iterator.finish(nestedSource(f, &iterator, operations));
    }
    if (!try h.fieldEqual(engine, message, "role", "assistant")) return;
    if (!try hasField(engine, message, "content") or !h.truthy(engine, try h.expression(engine, arrayContent, .{message}))) return;
    var iterator = try v.Iterator.initOwned(engine, try h.get(engine, message, "content"));
    return iterator.finish(assistantSource(f, &iterator, operations));
}
pub fn extract(engine: *Engine, message: c.JSValue, operations: c.JSValue) !void {
    var f = ExtractFrame.init(engine);
    return f.finishVoid(extractSource(&f, message, operations));
}

// This is the linked BCDF append opcode, not a for-of lowering. It performs
// its real iterator probe/second lookup, fast array path and abrupt close.
fn appendBody(s: *Scope, target: c.JSValue, position: *u32, incoming: anyerror!c.JSValue) !void {
    const iterable = try v.own(s, try incoming);
    var operation: v.guest.Boundary = .{ .engine = s.engine };
    try operation.begin();
    try operation.finishStatus(c.JS_PiArrayAppend(s.engine.context, target, position, iterable));
}
fn append(engine: *Engine, target: c.JSValue, position: *u32, incoming: anyerror!c.JSValue) !void {
    return h.statement(engine, appendBody, .{ target, position, incoming });
}
fn modifiedSet(s: *Scope, operations: c.JSValue) !c.JSValue {
    const constructor = try v.global(s, "Set");
    const values = try v.array(s);
    var position: u32 = 0;
    try append(s.engine, values, &position, h.get(s.engine, operations, "edited"));
    try append(s.engine, values, &position, h.get(s.engine, operations, "written"));
    return v.duplicate(s, try v.construct(s, constructor, &.{values}));
}
fn snapshotProperty(s: *Scope, operations: c.JSValue, field: [*:0]const u8) !c.JSValue {
    const values = try v.array(s);
    var position: u32 = 0;
    try append(s.engine, values, &position, h.get(s.engine, operations, field));
    return v.duplicate(s, values);
}
fn snapshotValue(s: *Scope, iterable: c.JSValue) !c.JSValue {
    const values = try v.array(s);
    var position: u32 = 0;
    try append(s.engine, values, &position, v.duplicate(s, iterable));
    return v.duplicate(s, values);
}
fn readOnlyBody(s: *Scope, modified: c.JSValue, value: c.JSValue) !c.JSValue {
    return v.boolean(s, !v.truthy(s, try v.invoke(s, modified, "has", &.{value})));
}
fn readOnly(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, readOnlyBody, .{ roots[0], v.arg(args, 0) });
}
fn filteredReads(s: *Scope, operations: c.JSValue, modified: c.JSValue) !c.JSValue {
    const reads = try v.own(s, try h.expression(s.engine, snapshotProperty, .{ operations, @as([*:0]const u8, "read") }));
    const method = try v.get(s, reads, "filter");
    const predicate = try v.arrow(s, "", 1, readOnly, &.{modified});
    return v.duplicate(s, try v.call(s, method, reads, &.{predicate}));
}
fn sortedIncoming(s: *Scope, incoming: anyerror!c.JSValue) !c.JSValue {
    const values = try v.own(s, try incoming);
    const method = try v.get(s, values, "sort");
    return v.duplicate(s, try v.call(s, method, values, &.{}));
}
fn listsResult(s: *Scope, f: *ListsFrame) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "readFiles", f.get(.read_only));
    try v.put(s, result, "modifiedFiles", f.get(.modified_files));
    return v.duplicate(s, result);
}
fn listsSource(f: *ListsFrame, operations: c.JSValue) !c.JSValue {
    const engine = f.engine;
    try f.set(.modified, h.expression(engine, modifiedSet, .{operations}));
    try f.set(.read_only, h.expression(engine, sortedIncoming, .{
        h.expression(engine, filteredReads, .{ operations, f.get(.modified) }),
    }));
    try f.set(.modified_files, h.expression(engine, sortedIncoming, .{
        h.expression(engine, snapshotValue, .{f.get(.modified)}),
    }));
    return h.expression(engine, listsResult, .{f});
}
pub fn lists(engine: *Engine, operations: c.JSValue) !c.JSValue {
    var f = ListsFrame.init(engine);
    return f.finish(listsSource(&f, operations));
}

fn lengthPositive(s: *Scope, values: c.JSValue) !c.JSValue {
    return v.duplicate(s, try h.binary(s, .greater, try v.get(s, values, "length"), v.number(s, 0)));
}
fn lengthZero(s: *Scope, values: c.JSValue) !c.JSValue {
    return v.boolean(s, v.equal(s, try v.get(s, values, "length"), v.number(s, 0)));
}
fn joinedText(s: *Scope, values: c.JSValue, separator: []const u8) !c.JSValue {
    const joined = try v.own(s, try v.invokeTextOwned(s.engine, values, "join", separator));
    return v.duplicate(s, try v.stringify(s, joined));
}
fn sectionText(s: *Scope, files: c.JSValue, comptime tag: []const u8) !c.JSValue {
    const joined = try v.own(s, try h.expression(s.engine, joinedText, .{ files, @as([]const u8, "\n") }));
    const prefix = try h.binary(s, .add, try v.text(s, "<" ++ tag ++ ">\n"), joined);
    return v.duplicate(s, try h.binary(s, .add, prefix, try v.text(s, "\n</" ++ tag ++ ">")));
}
fn appendSection(s: *Scope, sections: c.JSValue, files: c.JSValue, comptime tag: []const u8) !void {
    const method = try v.get(s, sections, "push");
    const text = try v.own(s, try h.expression(s.engine, sectionText, .{ files, tag }));
    _ = try v.call(s, method, sections, &.{text});
}
fn formattedSections(s: *Scope, sections: c.JSValue) !c.JSValue {
    const joined = try v.own(s, try h.expression(s.engine, joinedText, .{ sections, @as([]const u8, "\n\n") }));
    return v.duplicate(s, try h.binary(s, .add, try v.text(s, "\n\n"), joined));
}
fn formatSource(f: *FormatFrame, read_files: c.JSValue, modified_files: c.JSValue) !c.JSValue {
    const engine = f.engine;
    try f.set(.sections, h.array(engine));
    if (h.truthy(engine, try h.expression(engine, lengthPositive, .{read_files})))
        try h.statement(engine, appendSection, .{ f.get(.sections), read_files, "read-files" });
    if (h.truthy(engine, try h.expression(engine, lengthPositive, .{modified_files})))
        try h.statement(engine, appendSection, .{ f.get(.sections), modified_files, "modified-files" });
    if (h.truthy(engine, try h.expression(engine, lengthZero, .{f.get(.sections)}))) return h.text(engine, "");
    return h.expression(engine, formattedSections, .{f.get(.sections)});
}
pub fn format(engine: *Engine, read_files: c.JSValue, modified_files: c.JSValue) !c.JSValue {
    var f = FormatFrame.init(engine);
    return f.finish(formatSource(&f, read_files, modified_files));
}
