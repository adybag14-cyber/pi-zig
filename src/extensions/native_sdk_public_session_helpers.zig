//! Actual c268 public session helpers. The projection bodies are shared with
//! SessionManager; parse/migration keep live methods, real import identity and
//! the interpreter's Source lexical-slot lifetime across loops and catches.
const std = @import("std");
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = h.c;
const Engine = h.Engine;
const Scope = h.Scope;
const live = @import("native_sdk_session_projection_live.zig");
const uuid = @import("native_node_crypto_uuid_binding.zig");
const key = "\x00sdk-public-session-helpers";
pub const current_session_version = 3;
const Public = enum { getLatestCompactionEntry, parseSessionEntries, migrateSessionEntries };
pub const names = .{
    "CURRENT_SESSION_VERSION", "buildContextEntries", "buildSessionProjection", "buildSessionContext",
    "sessionEntryToContextMessages", "getLatestCompactionEntry", "parseSessionEntries", "migrateSessionEntries",
};
pub fn create(engine: *Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(key)) |cached| return h.duplicate(engine, cached);
    const candidate = try h.expression(engine, createBody, .{});
    if (engine.native_module_values.get(key)) |cached| {
        var completion = v.owned.Completion.initValue(engine, h.duplicate(engine, cached));
        completion.release(candidate); return completion.finishValue();
    }
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var completion = v.owned.Completion.initVoid(engine, err); completion.release(candidate);
        try completion.finishVoid(); unreachable;
    };
    const result = h.duplicate(engine, candidate);
    engine.native_module_values.putAssumeCapacity(key, candidate);
    return result;
}
fn createBody(s: *Scope) !c.JSValue {
    const result = try v.own(s, try live.exports(s.engine));
    const random_uuid = try v.own(s, try uuid.create(s.engine));
    try v.put(s, result, "CURRENT_SESSION_VERSION", c.JS_NewInt32(s.engine.context, current_session_version));
    inline for (std.meta.fields(Public)) |field| {
        const Adapter = struct {
            fn call(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                return dispatch(engine, @enumFromInt(field.value), v.arg(args, 0), roots[0]);
            }
        };
        try v.put(s, result, field.name, try v.ordinary(s, field.name, 1, Adapter.call, &.{random_uuid}));
    }
    return v.duplicate(s, result);
}
pub fn install(engine: *Engine, namespace: c.JSValue) !void { return h.statement(engine, installBody, .{namespace}); }
fn installBody(s: *Scope, namespace: c.JSValue) !void {
    const actual = try v.own(s, try create(s.engine));
    inline for (names) |name| try v.put(s, namespace, name, try v.get(s, actual, name));
}
fn dispatch(engine: *Engine, operation: Public, input: c.JSValue, random_uuid: c.JSValue) !c.JSValue {
    try engine.checkNativeEntry();
    var invocation: Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    const result = (switch (operation) {
        .getLatestCompactionEntry => latest(engine, input),
        .parseSessionEntries => parseLines(engine, input, true),
        .migrateSessionEntries => migratePublic(engine, input, random_uuid),
    }) catch |err| @import("native_sdk.zig").fail(engine, err);
    return engine.checked(engine.leaveNativeInvocation(&invocation, result));
}
const ParseFrame = h.Frame(enum { entries, lines, line, entry });
pub fn parseLines(engine: *Engine, content: c.JSValue, trim_outer: bool) !c.JSValue {
    var f = ParseFrame.init(engine);
    return f.finish(parseBody(&f, content, trim_outer));
}
fn parseBody(f: *ParseFrame, content: c.JSValue, trim_outer: bool) !c.JSValue {
    try f.set(.entries, h.array(f.engine));
    try f.set(.lines, h.expression(f.engine, splitLines, .{ content, trim_outer }));
    var iterator = try v.Iterator.init(f.engine, f.get(.lines));
    try iterator.finish(parseRows(f, &iterator));
    return h.duplicate(f.engine, f.get(.entries));
}
fn splitLines(s: *Scope, content: c.JSValue, trim_outer: bool) !c.JSValue {
    const selected = if (trim_outer) try v.own(s, try v.invokeOwned(s.engine, content, "trim", &.{})) else content;
    return v.duplicate(s, try v.invoke(s, selected, "split", &.{try v.text(s, "\n")}));
}
fn nonemptyLine(s: *Scope, line: c.JSValue) !c.JSValue {
    return v.boolean(s, v.truthy(s, try v.invoke(s, line, "trim", &.{})));
}
fn parseRows(f: *ParseFrame, iterator: *v.Iterator) !void {
    while (try iterator.next()) |incoming| {
        try f.set(.line, incoming);
        if (!h.truthy(f.engine, try h.expression(f.engine, nonemptyLine, .{f.get(.line)}))) continue;
        // The try body's uncaptured entry slot is reset only after the trim
        // condition enters this try again. Blank lines leave its prior value.
        var completion = v.owned.Completion.initVoid(f.engine, parseTry(f));
        const action = try completion.finishAction();
        var retired = v.owned.Completion.initVoid(f.engine, {});
        switch (action) { .returned, .thrown => |value| retired.release(value), .awaited => unreachable }
        try retired.finishVoid();
    }
}
fn parseTry(f: *ParseFrame) !void {
    try f.clear(.entry);
    try f.set(.entry, h.expression(f.engine, parseJson, .{f.get(.line)}));
    try h.discard(f.engine, f.get(.entries), "push", &.{f.get(.entry)});
}
fn parseJson(s: *Scope, line: c.JSValue) !c.JSValue {
    const json = try v.global(s, "JSON"); const parse = try v.get(s, json, "parse");
    return v.duplicate(s, try v.call(s, parse, json, &.{line}));
}
const LatestFrame = h.Frame(enum { position });
fn latest(engine: *Engine, entries: c.JSValue) !c.JSValue {
    var f = LatestFrame.init(engine);
    return f.finish(latestBody(&f, entries));
}
fn latestBody(f: *LatestFrame, entries: c.JSValue) !c.JSValue {
    try f.set(.position, h.expression(f.engine, lastPosition, .{entries}));
    var steps: usize = 0;
    while (try h.compare(f.engine, .greater_equal, f.get(.position), h.number(f.engine, 0))) {
        try v.poll(f.engine, &steps);
        if (h.truthy(f.engine, try h.expression(f.engine, latestMatches, .{ entries, f.get(.position) })))
            return h.key(f.engine, entries, f.get(.position));
        try f.set(.position, h.expression(f.engine, decrement, .{f.get(.position)}));
    }
    return c.pi_js_null();
}
fn lastPosition(s: *Scope, entries: c.JSValue) !c.JSValue {
    return v.duplicate(s, try h.binary(s, .subtract, try v.get(s, entries, "length"), v.number(s, 1)));
}
fn latestMatches(s: *Scope, entries: c.JSValue, position: c.JSValue) !c.JSValue {
    const type_value = try v.own(s, try h.expression(s.engine, latestType, .{ entries, position }));
    return v.boolean(s, try v.eq(s, type_value, "compaction"));
}
fn latestType(s: *Scope, entries: c.JSValue, position: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.get(s, try v.key(s, entries, position), "type"));
}
fn decrement(s: *Scope, position: c.JSValue) !c.JSValue {
    return v.duplicate(s, try h.binary(s, .subtract, position, v.number(s, 1)));
}
const MigrationFrame = h.Frame(enum { header, version });
pub fn migrate(engine: *Engine, entries: c.JSValue) !bool {
    var s: Scope = .{ .engine = engine };
    const result = try v.owned.finishValue(&s, migrateWithImport(&s, entries));
    return h.truthy(engine, result);
}
fn migrateWithImport(s: *Scope, entries: c.JSValue) !c.JSValue {
    const random_uuid = try v.own(s, try uuid.create(s.engine));
    return migrateValue(s.engine, entries, random_uuid);
}
fn migratePublic(engine: *Engine, entries: c.JSValue, random_uuid: c.JSValue) !c.JSValue {
    _ = try migrateValue(engine, entries, random_uuid);
    return c.pi_js_undefined();
}
fn migrateValue(engine: *Engine, entries: c.JSValue, random_uuid: c.JSValue) !c.JSValue {
    var f = MigrationFrame.init(engine);
    return f.finish(migrateBody(&f, entries, random_uuid));
}
fn migrateBody(f: *MigrationFrame, entries: c.JSValue, random_uuid: c.JSValue) !c.JSValue {
    try f.set(.header, h.expression(f.engine, findHeader, .{entries}));
    try f.set(.version, if (v.nullish(f.get(.header))) h.number(f.engine, 1) else h.get(f.engine, f.get(.header), "version"));
    if (v.nullish(f.get(.version))) try f.set(.version, h.number(f.engine, 1));
    if (try h.compare(f.engine, .greater_equal, f.get(.version), h.number(f.engine, current_session_version)))
        return c.JS_NewBool(f.engine.context, false);
    if (try h.compare(f.engine, .less, f.get(.version), h.number(f.engine, 2))) try migrateV1(f.engine, entries, random_uuid);
    if (try h.compare(f.engine, .less, f.get(.version), h.number(f.engine, 3))) try migrateV2(f.engine, entries);
    return c.JS_NewBool(f.engine.context, true);
}
fn headerPredicate(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.JS_NewBool(engine.context, try h.fieldEqual(engine, v.arg(args, 0), "type", "session"));
}
fn findHeader(s: *Scope, entries: c.JSValue) !c.JSValue {
    const find = try v.get(s, entries, "find"); const predicate = try v.arrow(s, "", 1, headerPredicate, &.{});
    return v.duplicate(s, try v.call(s, find, entries, &.{predicate}));
}
const V1Frame = h.Frame(enum { ids, previous_id, entry, compaction, target_entry });
fn migrateV1(engine: *Engine, entries: c.JSValue, random_uuid: c.JSValue) !void {
    var f = V1Frame.init(engine);
    return f.finishVoid(migrateV1Body(&f, entries, random_uuid));
}
fn migrateV1Body(f: *V1Frame, entries: c.JSValue, random_uuid: c.JSValue) !void {
    try f.set(.ids, h.construct(f.engine, "Set", &.{})); try f.set(.previous_id, c.pi_js_null());
    var iterator = try v.Iterator.init(f.engine, entries);
    return iterator.finish(migrateV1Rows(f, &iterator, entries, random_uuid));
}
fn migrateV1Rows(f: *V1Frame, iterator: *v.Iterator, entries: c.JSValue, random_uuid: c.JSValue) !void {
    const engine = f.engine;
    while (try iterator.next()) |incoming| {
        try f.set(.entry, incoming);
        const entry = f.get(.entry);
        if (try h.fieldEqual(engine, entry, "type", "session")) {
            try h.assign(engine, entry, "version", h.number(engine, 2)); continue;
        }
        try h.statement(engine, assignGeneratedId, .{ entry, f.get(.ids), random_uuid });
        try h.assign(engine, entry, "parentId", f.get(.previous_id));
        try f.set(.previous_id, h.get(engine, entry, "id"));
        if (try h.fieldEqual(engine, entry, "type", "compaction")) {
            try f.clear(.compaction);
            try f.set(.compaction, h.duplicate(engine, entry));
            if (try h.fieldTest(engine, f.get(.compaction), "firstKeptEntryIndex", .number)) {
                try f.clear(.target_entry);
                try f.set(.target_entry, h.keyFromField(engine, entries, f.get(.compaction), "firstKeptEntryIndex"));
                if (h.truthy(engine, f.get(.target_entry)) and !try h.fieldEqual(engine, f.get(.target_entry), "type", "session"))
                    try h.statement(engine, assignKeptId, .{ f.get(.compaction), f.get(.target_entry) });
                try h.delete(engine, f.get(.compaction), "firstKeptEntryIndex");
            }
        }
    }
}
fn assignGeneratedId(s: *Scope, entry: c.JSValue, ids: c.JSValue, random_uuid: c.JSValue) !void {
    const generated = try v.own(s, try generateId(s.engine, ids, random_uuid));
    try v.set(s, entry, "id", generated);
}
fn assignKeptId(s: *Scope, compaction: c.JSValue, target: c.JSValue) !void {
    try v.set(s, compaction, "firstKeptEntryId", try v.get(s, target, "id"));
}
const IdFrame = h.Frame(enum { index, id });
fn generateId(engine: *Engine, ids: c.JSValue, random_uuid: c.JSValue) !c.JSValue {
    var f = IdFrame.init(engine);
    return f.finish(generateIdBody(&f, ids, random_uuid));
}
fn generateIdBody(f: *IdFrame, ids: c.JSValue, random_uuid: c.JSValue) !c.JSValue {
    try f.set(.index, h.number(f.engine, 0)); var steps: usize = 0;
    while (try h.compare(f.engine, .less, f.get(.index), h.number(f.engine, 100))) {
        try v.poll(f.engine, &steps); try f.clear(.id);
        try f.set(.id, h.expression(f.engine, shortId, .{random_uuid}));
        if (!h.truthy(f.engine, try h.expression(f.engine, hasId, .{ ids, f.get(.id) })))
            return h.duplicate(f.engine, f.get(.id));
        try f.set(.index, h.increment(f.engine, f.get(.index)));
    }
    return h.expression(f.engine, callUuid, .{random_uuid});
}
fn callUuid(s: *Scope, random_uuid: c.JSValue) !c.JSValue { return v.duplicate(s, try v.call(s, random_uuid, c.pi_js_undefined(), &.{})); }
fn shortId(s: *Scope, random_uuid: c.JSValue) !c.JSValue {
    const generated = try v.own(s, try h.expression(s.engine, callUuid, .{random_uuid}));
    return v.duplicate(s, try v.invoke(s, generated, "slice", &.{v.number(s, 0), v.number(s, 8)}));
}
fn hasId(s: *Scope, ids: c.JSValue, id: c.JSValue) !c.JSValue {
    return v.boolean(s, v.truthy(s, try v.invoke(s, ids, "has", &.{id})));
}
const V2Frame = h.Frame(enum { entry, message_entry });
fn migrateV2(engine: *Engine, entries: c.JSValue) !void {
    var f = V2Frame.init(engine);
    return f.finishVoid(migrateV2Body(&f, entries));
}
fn migrateV2Body(f: *V2Frame, entries: c.JSValue) !void {
    var iterator = try v.Iterator.init(f.engine, entries);
    return iterator.finish(migrateV2Rows(f, &iterator));
}
fn migrateV2Rows(f: *V2Frame, iterator: *v.Iterator) !void {
    while (try iterator.next()) |incoming| {
        try f.set(.entry, incoming);
        const entry = f.get(.entry);
        if (try h.fieldEqual(f.engine, entry, "type", "session")) {
            try h.assign(f.engine, entry, "version", h.number(f.engine, 3)); continue;
        }
        if (try h.fieldEqual(f.engine, entry, "type", "message")) {
            try f.clear(.message_entry); try f.set(.message_entry, h.duplicate(f.engine, entry));
            if (try h.fieldTest(f.engine, f.get(.message_entry), "message", .truthy) and
                try h.nestedEqual(f.engine, f.get(.message_entry), "message", "role", "hookMessage"))
                try h.statement(f.engine, renameRole, .{f.get(.message_entry)});
        }
    }
}
fn renameRole(s: *Scope, entry: c.JSValue) !void {
    const message = try v.get(s, entry, "message"); try v.set(s, message, "role", try v.text(s, "custom"));
}
