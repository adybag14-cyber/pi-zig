//! Committed conversation mount revisions and observer fan-out.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
const Scope = struct {
    engine: *Engine,
    values: std.ArrayList(c.JSValue) = .empty,
    fn deinit(self: *Scope) void {
        for (self.values.items) |value| self.engine.freeValue(value);
        self.values.deinit(self.engine.gpa);
    }
    fn own(self: *Scope, value: c.JSValue) !c.JSValue {
        self.values.append(self.engine.gpa, value) catch |err| {
            self.engine.freeValue(value);
            return err;
        };
        return value;
    }
    fn get(self: *Scope, object: c.JSValue, key: [:0]const u8) !c.JSValue {
        return self.own(try vm.get(self.engine, object, key));
    }
    fn item(self: *Scope, object: c.JSValue, index: usize) !c.JSValue {
        return self.own(try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, object, @intCast(index))));
    }
    fn invoke(self: *Scope, object: c.JSValue, key: [:0]const u8, args: []const c.JSValue) !c.JSValue {
        return self.own(try vm.invoke(self.engine, object, key, args));
    }
    fn text(self: *Scope, bytes: []const u8) !c.JSValue {
        return self.own(try self.engine.checked(c.JS_NewStringLen(self.engine.context, bytes.ptr, bytes.len)));
    }
    fn array(self: *Scope, values: []const c.JSValue) !c.JSValue {
        const result = try self.own(try vm.array(self.engine));
        for (values) |value| try js.push(self.engine, result, value);
        return result;
    }
};
fn put(engine: *Engine, object: c.JSValue, key: [:0]const u8, value: c.JSValue) !void {
    try @import("native_tool_info.zig").putData(engine, object, key, c.JS_DupValue(engine.context, value));
}
fn same(engine: *Engine, left: c.JSValue, right: c.JSValue) bool {
    return c.JS_IsStrictEqual(engine.context, left, right);
}
fn mounted(engine: *Engine, kind: c.JSValue) !bool {
    const text = try engine.toString(kind);
    defer engine.gpa.free(text);
    for ([_][]const u8{ "pi.agent", "pi.live", "pi.inbox", "pi.provider", "pi.usage" }) |name| if (std.mem.eql(u8, text, name)) return true;
    return false;
}
fn prefix(scope: *Scope, operation: c.JSValue, path: c.JSValue) !c.JSValue {
    const kind = try scope.item(operation, 0);
    if (same(scope.engine, kind, try scope.text("r"))) return scope.array(&.{ try scope.text("s"), path, try scope.item(operation, 1) });
    const old_path = try scope.item(operation, 1);
    const next_path = try scope.invoke(path, "concat", &.{old_path});
    const result = try scope.array(&.{ kind, next_path });
    for (2..try vm.length(scope.engine, operation)) |index| try js.push(scope.engine, result, try scope.item(operation, index));
    return result;
}
fn notify(scope: *Scope, observers: c.JSValue, name: [:0]const u8, arguments: []const c.JSValue, report: c.JSValue) !void {
    const engine = scope.engine;
    const symbol = try scope.get(try scope.own(try js.global(engine, "Symbol")), "iterator");
    const snapshot = try scope.own(try js.collect(engine, observers, symbol));
    for (0..try vm.length(engine, snapshot)) |index| {
        const observer = try scope.item(snapshot, index);
        const callback = try scope.get(observer, name);
        if (c.JS_IsUndefined(callback) or c.JS_IsNull(callback)) continue;
        const result = js.call(engine, callback, observer, arguments) catch |err| {
            if (err != error.JavaScriptException) return err;
            const cause = try scope.own(c.JS_DupValue(engine.context, engine.captured_exception orelse return err));
            const reported = js.call(engine, report, c.pi_js_undefined(), &.{cause}) catch |report_error| {
                if (report_error != error.JavaScriptException) return report_error;
                continue;
            };
            engine.freeValue(reported);
            continue;
        };
        engine.freeValue(result);
    }
}
pub fn advance(engine: *Engine, id: c.JSValue, mount: c.JSValue, publication: c.JSValue, context: c.JSValue, report: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const doc_ops = try scope.array(&.{});
    const entry_ops = try scope.array(&.{});
    const before = try scope.get(mount, "value");
    var entries = try scope.get(before, "entries");
    const changes = try scope.get(publication, "changes");
    const docs = try scope.get(mount, "docs");
    for (0..try vm.length(engine, changes)) |index| {
        const change = try scope.item(changes, index);
        const kind = try scope.get(change, "type");
        if (same(engine, kind, try scope.text("entry"))) {
            const entry = try scope.get(change, "value");
            if (!same(engine, try scope.get(entry, "conversationId"), id)) continue;
            const inserted = try scope.array(&.{entry});
            const head = try scope.get(entry, "head");
            if (c.JS_IsUndefined(head)) {
                try js.push(engine, entry_ops, try scope.array(&.{ try scope.text("p"), try scope.array(&.{try scope.text("entries")}), c.JS_NewFloat64(engine.context, @floatFromInt(try vm.length(engine, entries))), c.JS_NewInt32(engine.context, 0), inserted }));
                entries = try scope.invoke(entries, "concat", &.{inserted});
            } else {
                var target: f64 = 0;
                if (c.JS_ToFloat64(engine.context, &target, head) < 0) return js.capture(engine);
                var kept = try vm.length(engine, entries);
                for (0..kept) |entry_index| {
                    const candidate = try scope.item(entries, entry_index);
                    if (!c.JS_IsUndefined(try scope.get(candidate, "head"))) continue;
                    var candidate_id: f64 = 0;
                    if (c.JS_ToFloat64(engine.context, &candidate_id, try scope.get(candidate, "id")) < 0) return js.capture(engine);
                    if (candidate_id >= target) {
                        kept = entry_index;
                        break;
                    }
                }
                try js.push(engine, entry_ops, try scope.array(&.{ try scope.text("p"), try scope.array(&.{try scope.text("entries")}), c.JS_NewInt32(engine.context, 0), c.JS_NewFloat64(engine.context, @floatFromInt(kept)), inserted }));
                const suffix = try scope.invoke(entries, "slice", &.{c.JS_NewFloat64(engine.context, @floatFromInt(kept))});
                entries = try scope.invoke(inserted, "concat", &.{suffix});
            }
            continue;
        }
        if (!same(engine, kind, try scope.text("document")) or !same(engine, try scope.get(change, "conversationId"), id)) continue;
        const record = try scope.get(change, "record");
        const document_kind = try scope.get(record, "kind");
        if (!try mounted(engine, document_kind) or !c.JS_IsUndefined(try scope.get(record, "key"))) continue;
        const path = try scope.array(&.{ try scope.text("docs"), document_kind });
        const incarnation = try scope.invoke(docs, "get", &.{document_kind});
        const record_id = try scope.get(record, "id");
        const value = try scope.get(change, "value");
        if (c.JS_IsNull(value)) {
            if (c.JS_IsUndefined(incarnation) or !same(engine, try scope.get(incarnation, "id"), record_id)) continue;
            _ = try scope.invoke(docs, "delete", &.{document_kind});
            try js.push(engine, doc_ops, try scope.array(&.{ try scope.text("d"), path }));
        } else {
            const version = try scope.get(change, "version");
            if (!c.JS_IsUndefined(incarnation) and same(engine, try scope.get(incarnation, "id"), record_id) and same(engine, try scope.get(incarnation, "version"), version)) {
                const operations = try scope.get(change, "ops");
                for (0..try vm.length(engine, operations)) |operation_index| try js.push(engine, doc_ops, try prefix(&scope, try scope.item(operations, operation_index), path));
            } else {
                const next = try scope.own(try vm.object(engine));
                try put(engine, next, "id", record_id);
                try put(engine, next, "version", version);
                _ = try scope.invoke(docs, "set", &.{ document_kind, next });
                try js.push(engine, doc_ops, try scope.array(&.{ try scope.text("s"), path, value }));
            }
        }
    }
    const operations = try scope.invoke(doc_ops, "concat", &.{entry_ops});
    const frame_context = try scope.own(try @import("native_durable_context.zig").withoutAbortSignal(engine, context));
    const observers = try scope.get(mount, "observers");
    if (try vm.length(engine, operations) > 0) {
        var after = if (try vm.length(engine, doc_ops) == 0) before else try scope.own(try @import("native_durable_view_delta.zig").apply(engine, before, doc_ops));
        if (!same(engine, entries, try scope.get(after, "entries"))) {
            after = try scope.own(try js.spread(engine, after));
            try put(engine, after, "entries", entries);
        }
        try put(engine, mount, "value", after);
        try notify(&scope, observers, "advance", &.{ after, operations, frame_context }, report);
    }
    try notify(&scope, observers, "publication", &.{ before, try scope.get(mount, "value"), operations, publication, frame_context }, report);
}
