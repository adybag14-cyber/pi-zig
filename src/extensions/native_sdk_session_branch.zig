//! Extract one conversation path with Source's label/compaction re-chaining.
const std = @import("std");
const sdk = @import("native_sdk.zig");
const models = @import("native_sdk_models.zig");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
pub fn install(engine: *engine_mod.Engine, prototype: c.JSValue) !void {
    const function = try engine.checked(c.JS_NewCFunction(engine.context, callback, "createBranchedSession", 1));
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "createBranchedSession", function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return error.JavaScriptException;
}
fn callback(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const self = sdk.state(engine, receiver) catch |err| return sdk.fail(engine, err);
    if (self.kind != .session_manager) return sdk.fail(engine, error.InvalidNativeSDKReceiver);
    return branch(self, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
pub fn branch(self: *sdk.State, leaf: c.JSValue) !c.JSValue {
    const engine = self.engine;
    const start = if (c.JS_IsNull(leaf) or c.JS_IsUndefined(leaf)) try sdk.get(engine, self.data, "leafId") else c.JS_DupValue(engine.context, leaf);
    defer engine.freeValue(start);
    const path = try sdk.branchEntries(self, start);
    defer engine.freeValue(path);
    if (try sdk.length(engine, path) == 0) {
        const id = try engine.toString(leaf);
        defer engine.gpa.free(id);
        const message = try std.fmt.allocPrint(engine.gpa, "Entry {s} not found", .{id});
        defer engine.gpa.free(message);
        return sdk.sourceError(engine, message);
    }
    const replacements = try @import("native_sdk_auth_snapshot.zig").collection(engine, "Map");
    defer engine.freeValue(replacements);
    const pending = try sdk.array(engine);
    defer engine.freeValue(pending);
    const rows = try sdk.array(engine);
    defer engine.freeValue(rows);
    const retained_ids = try @import("native_sdk_auth_snapshot.zig").collection(engine, "Set");
    defer engine.freeValue(retained_ids);
    var parent = c.pi_js_null();
    defer engine.freeValue(parent);
    for (0..try sdk.length(engine, path)) |index| {
        const original = try engine.checked(c.JS_GetPropertyUint32(engine.context, path, @intCast(index)));
        defer engine.freeValue(original);
        const typ = try sdk.get(engine, original, "type");
        defer engine.freeValue(typ);
        const id = try sdk.get(engine, original, "id");
        defer engine.freeValue(id);
        const raw_type = try engine.toString(typ);
        defer engine.gpa.free(raw_type);
        if (std.mem.eql(u8, raw_type, "label")) {
            try sdk.append(engine, pending, c.JS_DupValue(engine.context, id));
            continue;
        }
        for (0..try sdk.length(engine, pending)) |i| {
            const label = try engine.checked(c.JS_GetPropertyUint32(engine.context, pending, @intCast(i)));
            defer engine.freeValue(label);
            const added = try sdk.invoke(engine, replacements, "set", &.{ label, id });
            engine.freeValue(added);
        }
        try sdk.put(engine, pending, "length", c.JS_NewInt32(engine.context, 0));
        const row = try sdk.object(engine);
        defer engine.freeValue(row);
        try models.copy(engine, row, original);
        try sdk.put(engine, row, "parentId", c.JS_DupValue(engine.context, parent));
        if (std.mem.eql(u8, raw_type, "compaction")) {
            const kept = try sdk.get(engine, original, "firstKeptEntryId");
            defer engine.freeValue(kept);
            const replacement = try sdk.invoke(engine, replacements, "get", &.{kept});
            defer engine.freeValue(replacement);
            try sdk.put(engine, row, "firstKeptEntryId", c.JS_DupValue(engine.context, if (c.JS_IsStrictEqual(engine.context, kept, id) or c.JS_IsUndefined(replacement) or c.JS_IsNull(replacement)) kept else replacement));
        }
        const added = try sdk.invoke(engine, retained_ids, "add", &.{id});
        engine.freeValue(added);
        try sdk.append(engine, rows, c.JS_DupValue(engine.context, row));
        engine.freeValue(parent);
        parent = c.JS_DupValue(engine.context, id);
    }
    const labels = try sdk.get(engine, self.data, "sessionLabels");
    defer engine.freeValue(labels);
    const times = try sdk.get(engine, self.data, "sessionLabelTimes");
    defer engine.freeValue(times);
    const iterator = try sdk.invoke(engine, labels, "entries", &.{});
    defer engine.freeValue(iterator);
    while (true) {
        const next = try sdk.invoke(engine, iterator, "next", &.{});
        defer engine.freeValue(next);
        const done = try sdk.get(engine, next, "done");
        defer engine.freeValue(done);
        if (c.JS_ToBool(engine.context, done) == 1) break;
        const pair = try sdk.get(engine, next, "value");
        defer engine.freeValue(pair);
        const id = try engine.checked(c.JS_GetPropertyUint32(engine.context, pair, 0));
        defer engine.freeValue(id);
        const has = try sdk.invoke(engine, retained_ids, "has", &.{id});
        defer engine.freeValue(has);
        if (c.JS_ToBool(engine.context, has) != 1) continue;
        const label = try engine.checked(c.JS_GetPropertyUint32(engine.context, pair, 1));
        defer engine.freeValue(label);
        const stamp = try sdk.invoke(engine, times, "get", &.{id});
        defer engine.freeValue(stamp);
        const row = try sdk.object(engine);
        defer engine.freeValue(row);
        const new_id = try sdk.identifier(engine, "entry");
        defer engine.freeValue(new_id);
        try sdk.put(engine, row, "type", try sdk.text(engine, "label"));
        try sdk.put(engine, row, "id", c.JS_DupValue(engine.context, new_id));
        try sdk.put(engine, row, "parentId", c.JS_DupValue(engine.context, parent));
        try sdk.put(engine, row, "timestamp", c.JS_DupValue(engine.context, stamp));
        try sdk.put(engine, row, "targetId", c.JS_DupValue(engine.context, id));
        try sdk.put(engine, row, "label", c.JS_DupValue(engine.context, label));
        try sdk.append(engine, rows, c.JS_DupValue(engine.context, row));
        engine.freeValue(parent);
        parent = c.JS_DupValue(engine.context, new_id);
    }
    const working = try sdk.get(engine, self.data, "cwd");
    defer engine.freeValue(working);
    const directory = try sdk.get(engine, self.data, "sessionDir");
    defer engine.freeValue(directory);
    const previous_file = try sdk.get(engine, self.data, "sessionFile");
    defer engine.freeValue(previous_file);
    const persisted = try sdk.get(engine, self.data, "persistent");
    defer engine.freeValue(persisted);
    const persistent = c.JS_ToBool(engine.context, persisted) == 1;
    const options = try sdk.object(engine);
    defer engine.freeValue(options);
    try sdk.put(engine, options, "parentSession", if (persistent) c.JS_DupValue(engine.context, previous_file) else c.pi_js_undefined());
    const fresh = if (persistent) try sdk.initManager(engine, &.{ working, directory, options }, true) else try sdk.initManager(engine, &.{ working, options }, false);
    defer engine.freeValue(fresh);
    const owner = try sdk.state(engine, fresh);
    try sdk.put(engine, owner.data, "entries", c.JS_DupValue(engine.context, rows));
    try sdk.put(engine, owner.data, "leafId", c.JS_DupValue(engine.context, parent));
    if (!persistent) try sdk.put(engine, owner.data, "sessionFile", c.JS_DupValue(engine.context, previous_file));
    try sdk.rebuildSessionIndex(engine, owner.data);
    engine.freeValue(self.data);
    self.data = c.JS_DupValue(engine.context, owner.data);
    self.persisted_count = 0;
    if (persistent) {
        self.session_flushed = false;
        var conversation = false;
        for (0..try sdk.length(engine, rows)) |i| {
            const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(i)));
            defer engine.freeValue(row);
            const message = try sdk.get(engine, row, "message");
            defer engine.freeValue(message);
            if (!c.JS_IsObject(message)) continue;
            const role = try sdk.get(engine, message, "role");
            defer engine.freeValue(role);
            const text = try engine.toString(role);
            defer engine.gpa.free(text);
            if (std.mem.eql(u8, text, "user") or std.mem.eql(u8, text, "assistant")) conversation = true;
        }
        if (conversation) try @import("native_sdk_session_files.zig").rewrite(self);
        return sdk.get(engine, self.data, "sessionFile");
    }
    return c.pi_js_undefined();
}
