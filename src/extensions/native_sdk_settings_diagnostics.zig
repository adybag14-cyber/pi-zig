//! Complete original settings-diagnostics functions as a private native owner.
//! Type-only Source imports impose no runtime substitute. Actual callers supply
//! the genuine SettingsManager; live drainErrors/map/filter/Set remain live.
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = h.c;
const Engine = h.Engine;
const Scope = h.Scope;
const sync = @import("native_sync_arguments.zig");
const frames = @import("native_public_lexical_frame.zig");
const CollectFrame = frames.Frame(enum { scope, path, error_value });
const SeenFrame = frames.Frame(enum { seen });
const KeyFrame = frames.Frame(enum { key });
const cache_key = "pi-private:actual-sdk-settings-diagnostics";

/// The complete two-function private owner is published only after both genuine
/// ordinary functions exist. This is not a partial SDK or public namespace.
pub fn create(engine: *Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cache_key)) |cached| return h.duplicate(engine, cached);
    const candidate = try h.expression(engine, createBody, .{});
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var completion = v.owned.Completion.initValue(engine, @as(anyerror!c.JSValue, err));
        completion.release(candidate);
        return completion.finishValue();
    };
    engine.native_module_values.putAssumeCapacity(cache_key, candidate);
    return h.duplicate(engine, candidate);
}
fn createBody(s: *Scope) !c.JSValue {
    const result = try v.stateObject(s);
    try v.put(s, result, "collectSettingsDiagnostics", try ordinary(s,
        "collectSettingsDiagnostics", collectCall, .{}));
    try v.put(s, result, "deduplicateDiagnostics", try ordinary(s,
        "deduplicateDiagnostics", deduplicateCall, sync.frameHooks(SeenFrame)));
    return v.duplicate(s, result);
}
fn ordinary(s: *Scope, name: [*:0]const u8, callback: sync.Callback, hooks: sync.Hooks) !c.JSValue {
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    return boundary.finishValue(s, v.function.createWithArguments(s.engine, name, 1,
        .{ .formal_count = 1, .callback = callback, .hooks = hooks }, &.{}));
}
fn arrow(s: *Scope, callback: sync.Callback, hooks: sync.Hooks, roots: []const c.JSValue) !c.JSValue {
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    return boundary.finishValue(s, v.function.createArrowWithArguments(s.engine, "", 1,
        .{ .formal_count = 1, .callback = callback, .hooks = hooks }, roots));
}

fn collectCall(engine: *Engine, _: c.JSValue, arguments: *sync.Arguments, _: []const c.JSValue) !c.JSValue {
    return h.expression(engine, collectBody, .{arguments});
}
fn collectBody(s: *Scope, arguments: *sync.Arguments) !c.JSValue {
    // drainErrors and its call complete before the returned object's map Get.
    const errors = try v.own(s, try v.invokeOwned(s.engine, arguments.get(0), "drainErrors", &.{}));
    const map = try v.get(s, errors, "map");
    const callback = try arrow(s, collectRowCall, sync.frameHooks(CollectFrame), &.{});
    return v.duplicate(s, try v.call(s, map, errors, &.{callback}));
}
fn collectRowCall(engine: *Engine, _: c.JSValue, arguments: *sync.Arguments, _: []const c.JSValue) !c.JSValue {
    return h.expression(engine, collectRowBody, .{arguments});
}
fn destructureBody(s: *Scope, frame: *CollectFrame, incoming: c.JSValue) !void {
    // A destructuring parameter boxes once. All three original Gets happen
    // before the object literal starts; the temporary box then retires.
    const object = try v.guest.toObject(s, incoming);
    try frame.take(.scope, h.get(s.engine, object, "scope"));
    try frame.take(.path, h.get(s.engine, object, "path"));
    try frame.take(.error_value, h.get(s.engine, object, "error"));
}
fn collectRowBody(s: *Scope, arguments: *sync.Arguments) !c.JSValue {
    const frame = try arguments.createFrame(s, CollectFrame);
    try h.statement(s.engine, destructureBody, .{ frame, arguments.get(0) });
    const result = try v.object(s);
    try v.put(s, result, "type", try v.text(s, "warning"));
    try v.put(s, result, "message", try v.own(s, try h.expression(s.engine, messageBody, .{frame})));
    return v.duplicate(s, result);
}
fn fieldStringBody(s: *Scope, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return v.duplicate(s, try v.stringify(s, try v.get(s, object, name)));
}
fn messageBody(s: *Scope, frame: *CollectFrame) !c.JSValue {
    const with_path = v.truthy(s, frame.get(.path));
    const prefix = try v.text(s, if (with_path) "Invalid settings file " else "Invalid ");
    const location = try v.stringify(s, if (with_path) frame.get(.path) else frame.get(.scope));
    var message = try h.binary(s, .add, prefix, location);
    message = try h.binary(s, .add, message, try v.text(s, if (with_path) ": " else " settings: "));
    // Template coercion of the location precedes the error.message Get.
    const detail = try v.own(s, try h.expression(s.engine, fieldStringBody,
        .{ frame.get(.error_value), @as([*:0]const u8, "message") }));
    return v.duplicate(s, try h.binary(s, .add, message, detail));
}

fn deduplicateCall(engine: *Engine, _: c.JSValue, arguments: *sync.Arguments, _: []const c.JSValue) !c.JSValue {
    return h.expression(engine, deduplicateBody, .{arguments});
}
fn deduplicateBody(s: *Scope, arguments: *sync.Arguments) !c.JSValue {
    const frame = try arguments.createFrame(s, SeenFrame);
    // The Source resolves the current global constructor for every invocation.
    try frame.take(.seen, h.construct(s.engine, "Set", &.{}));
    const diagnostics = arguments.get(0);
    const filter = try v.get(s, diagnostics, "filter");
    const binding = try frame.capture(s, .seen, "seen");
    const callback = try arrow(s, predicateCall, sync.frameHooks(KeyFrame), &.{binding});
    return v.duplicate(s, try v.call(s, filter, diagnostics, &.{callback}));
}
fn predicateCall(engine: *Engine, _: c.JSValue, arguments: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, predicateBody, .{ arguments, roots[0] });
}
fn keyBody(s: *Scope, diagnostic: c.JSValue) !c.JSValue {
    // ToString(type) completes before Get(message), with a literal NUL separator.
    const kind = try v.own(s, try h.expression(s.engine, fieldStringBody,
        .{ diagnostic, @as([*:0]const u8, "type") }));
    const prefix = try h.binary(s, .add, kind, try v.text(s, "\x00"));
    const message = try v.own(s, try h.expression(s.engine, fieldStringBody,
        .{ diagnostic, @as([*:0]const u8, "message") }));
    return v.duplicate(s, try h.binary(s, .add, prefix, message));
}
fn hasBody(s: *Scope, binding: c.JSValue, key: c.JSValue) !c.JSValue {
    const seen = try SeenFrame.read(s, binding);
    const has = try v.get(s, seen, "has");
    return v.boolean(s, v.truthy(s, try v.call(s, has, seen, &.{key})));
}
fn addBody(s: *Scope, binding: c.JSValue, key: c.JSValue) !void {
    const seen = try SeenFrame.read(s, binding);
    const add = try v.get(s, seen, "add");
    _ = try v.call(s, add, seen, &.{key});
}
fn predicateBody(s: *Scope, arguments: *sync.Arguments, binding: c.JSValue) !c.JSValue {
    const frame = try arguments.createFrame(s, KeyFrame);
    try frame.take(.key, h.expression(s.engine, keyBody, .{arguments.get(0)}));
    if (h.truthy(s.engine, try h.expression(s.engine, hasBody, .{ binding, frame.get(.key) })))
        return v.boolean(s, false);
    try h.statement(s.engine, addBody, .{ binding, frame.get(.key) });
    return v.boolean(s, true);
}
