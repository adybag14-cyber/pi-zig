//! Source loader.registerCommand validation and complete registration snapshot.
//! Source-only prerequisite, not wired into NativeBindings yet. The caller must
//! assert its actual runtime is active before entering, as the Source API does.
const js = @import("native_js_values.zig");
const sdk = @import("native_sdk.zig");
const text = @import("native_select_list.zig");
const c = js.c;

fn reject(engine: *js.Engine, extension: c.JSValue, name: ?c.JSValue) !void {
    const prefix = try sdk.text(engine, if (name != null) "Command \"/" else "Command registered by extension \"");
    defer engine.freeValue(prefix);
    const path = try js.get(engine, extension, "path");
    defer engine.freeValue(path);
    const message = if (name) |command| named: {
        const middle = try sdk.text(engine, "\" registered by extension \"");
        defer engine.freeValue(middle);
        const ending = try sdk.text(engine, "\" must define handler().");
        defer engine.freeValue(ending);
        break :named try text.concat(engine, &.{ prefix, command, middle, path, ending });
    } else unnamed: {
        const ending = try sdk.text(engine, "\" must have a non-empty string name. Use pi.registerCommand(\"name\", { description, handler }).");
        defer engine.freeValue(ending);
        break :unnamed try text.concat(engine, &.{ prefix, path, ending });
    };
    defer engine.freeValue(message);
    const reason = try js.builtin(engine, "Error", &.{message});
    _ = try engine.checked(c.JS_Throw(engine.context, reason));
}

/// Returns the owned snapshot for native compatibility bookkeeping. Public API
/// registerCommand returns undefined, irrespective of commands.set's result.
pub fn register(engine: *js.Engine, extension: c.JSValue, name: c.JSValue, options: c.JSValue) !c.JSValue {
    var valid_name = c.JS_IsString(name);
    if (valid_name) {
        const length = try js.get(engine, name, "length");
        defer engine.freeValue(length);
        var units: i64 = 0;
        if (c.JS_ToInt64(engine.context, &units, length) < 0) return js.capture(engine);
        valid_name = units != 0;
    }
    if (!valid_name) {
        try reject(engine, extension, null);
        unreachable;
    }
    const handler = if (c.JS_IsNull(options) or c.JS_IsUndefined(options)) c.pi_js_undefined() else try js.get(engine, options, "handler");
    defer engine.freeValue(handler);
    if (!c.JS_IsFunction(engine.context, handler)) {
        try reject(engine, extension, name);
        unreachable;
    }
    // Resolve extension.commands.set before object literal getters/spread.
    const commands = try js.get(engine, extension, "commands");
    defer engine.freeValue(commands);
    const setter = try js.get(engine, commands, "set");
    defer engine.freeValue(setter);
    const snapshot = try js.object(engine);
    errdefer engine.freeValue(snapshot);
    try js.define(engine, snapshot, "name", c.JS_DupValue(engine.context, name));
    const source = try js.get(engine, extension, "sourceInfo");
    try js.define(engine, snapshot, "sourceInfo", source);
    try js.spreadInto(engine, snapshot, options);
    const ignored = try js.call(engine, setter, commands, &.{ name, snapshot });
    engine.freeValue(ignored);
    return snapshot;
}
