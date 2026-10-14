//! Actual Source frame schema and error vocabulary used by native connections.
const h = @import("native_chord_host_values.zig");
const Scope = h.Scope;
const js = h.js;
const c = h.c;
const Field = struct { name: [*:0]const u8, schema: c.JSValue };
fn object(s: *Scope, types: c.JSValue, fields: []const Field) !c.JSValue {
    const properties = try s.record();
    for (fields) |field| try h.field(s, properties, field.name, field.schema);
    return h.invoke(s, types, "Object", &.{properties});
}
fn optional(s: *Scope, types: c.JSValue, schema: c.JSValue) !c.JSValue {
    return h.invoke(s, types, "Optional", &.{schema});
}
fn list(s: *Scope, types: c.JSValue, schema: c.JSValue) !c.JSValue {
    return h.invoke(s, types, "Array", &.{schema});
}
fn integer(s: *Scope, types: c.JSValue, minimum: i32) !c.JSValue {
    if (minimum < 0) return h.invoke(s, types, "Integer", &.{});
    const options = try s.record();
    try h.field(s, options, "minimum", c.JS_NewInt32(s.engine.context, minimum));
    return h.invoke(s, types, "Integer", &.{options});
}
fn variant(s: *Scope, types: c.JSValue, union_types: c.JSValue, name: []const u8, fields: []const Field) !void {
    const properties = try s.record();
    try h.field(s, properties, "t", try h.invoke(s, types, "Literal", &.{try s.text(name)}));
    for (fields) |field| try h.field(s, properties, field.name, field.schema);
    try js.push(s.engine, union_types, try h.invoke(s, types, "Object", &.{properties}));
}
fn frameSchema(s: *Scope) !c.JSValue {
    const types = try s.keep(try @import("typebox.zig").create(s.engine));
    const id = try integer(s, types, 1);
    const string = try h.invoke(s, types, "String", &.{});
    const min_length = try s.record();
    try h.field(s, min_length, "minLength", c.JS_NewInt32(s.engine.context, 1));
    const name = try h.invoke(s, types, "String", &.{min_length});
    const unknown = try h.invoke(s, types, "Unknown", &.{});
    const root = try object(s, types, &.{ .{ .name = "rootId", .schema = name }, .{ .name = "codeVersion", .schema = id } });
    const codes = try s.list();
    inline for (.{ "aborted", "contract_mismatch", "forbidden", "gone", "invalid", "not_in_variant", "not_ready", "released", "superseded", "unavailable", "upgrade_conflict", "upgrade_required" }) |code| try js.push(s.engine, codes, try h.invoke(s, types, "Literal", &.{try s.text(code)}));
    const error_shape = try object(s, types, &.{ .{ .name = "code", .schema = try h.invoke(s, types, "Union", &.{codes}) }, .{ .name = "message", .schema = string }, .{ .name = "reason", .schema = try optional(s, types, string) } });
    const unconstrained_int = try integer(s, types, -1);
    const strings = try list(s, types, string);
    const dictionary = try h.invoke(s, types, "Record", &.{ string, unknown });
    const boolean = try h.invoke(s, types, "Boolean", &.{});
    const host_kind = try s.list();
    inline for (.{ "host", "client" }) |kind| try js.push(s.engine, host_kind, try h.invoke(s, types, "Literal", &.{try s.text(kind)}));
    const frame_types = try s.list();
    try variant(s, types, frame_types, "hello", &.{ .{ .name = "protocol", .schema = try optional(s, types, id) }, .{ .name = "name", .schema = name }, .{ .name = "kind", .schema = try h.invoke(s, types, "Union", &.{host_kind}) }, .{ .name = "codeVersion", .schema = try integer(s, types, 0) }, .{ .name = "acks", .schema = try optional(s, types, boolean) } });
    try variant(s, types, frame_types, "ack", &.{.{ .name = "n", .schema = id }});
    const scopes = try s.list();
    inline for (.{ "remote", "local" }) |scope| try js.push(s.engine, scopes, try h.invoke(s, types, "Literal", &.{try s.text(scope)}));
    const schema_object = try object(s, types, &.{});
    const descriptions = try s.list();
    try js.push(s.engine, descriptions, try object(s, types, &.{ .{ .name = "kind", .schema = try h.invoke(s, types, "Literal", &.{try s.text("method")}) }, .{ .name = "args", .schema = try optional(s, types, schema_object) }, .{ .name = "result", .schema = try optional(s, types, schema_object) } }));
    try js.push(s.engine, descriptions, try object(s, types, &.{ .{ .name = "kind", .schema = try h.invoke(s, types, "Literal", &.{try s.text("state")}) }, .{ .name = "schema", .schema = schema_object } }));
    try js.push(s.engine, descriptions, try object(s, types, &.{ .{ .name = "kind", .schema = try h.invoke(s, types, "Literal", &.{try s.text("opaque")}) }, .{ .name = "id", .schema = string } }));
    const variants = try h.invoke(s, types, "Record", &.{ string, try h.invoke(s, types, "Record", &.{ string, try h.invoke(s, types, "Union", &.{descriptions}) }) });
    const token = try object(s, types, &.{ .{ .name = "name", .schema = name }, .{ .name = "scope", .schema = try h.invoke(s, types, "Union", &.{scopes}) }, .{ .name = "version", .schema = unconstrained_int }, .{ .name = "input", .schema = schema_object }, .{ .name = "variants", .schema = variants } });
    try variant(s, types, frame_types, "hold", &.{ .{ .name = "id", .schema = id }, .{ .name = "at", .schema = name }, .{ .name = "token", .schema = token }, .{ .name = "input", .schema = unknown }, .{ .name = "principal", .schema = try optional(s, types, unknown) }, .{ .name = "client", .schema = try optional(s, types, boolean) } });
    try variant(s, types, frame_types, "release", &.{.{ .name = "id", .schema = id }});
    try variant(s, types, frame_types, "shape", &.{ .{ .name = "id", .schema = id }, .{ .name = "variant", .schema = try optional(s, types, string) }, .{ .name = "members", .schema = strings }, .{ .name = "contract", .schema = string }, .{ .name = "codeVersion", .schema = unconstrained_int } });
    try variant(s, types, frame_types, "gone", &.{ .{ .name = "id", .schema = id }, .{ .name = "error", .schema = error_shape } });
    try variant(s, types, frame_types, "call", &.{ .{ .name = "id", .schema = id }, .{ .name = "hold", .schema = id }, .{ .name = "member", .schema = name }, .{ .name = "args", .schema = try optional(s, types, unknown) }, .{ .name = "root", .schema = try optional(s, types, root) } });
    try variant(s, types, frame_types, "result", &.{ .{ .name = "id", .schema = id }, .{ .name = "value", .schema = try optional(s, types, unknown) }, .{ .name = "error", .schema = try optional(s, types, error_shape) } });
    try variant(s, types, frame_types, "cancel", &.{.{ .name = "id", .schema = id }});
    try variant(s, types, frame_types, "sub", &.{ .{ .name = "id", .schema = id }, .{ .name = "hold", .schema = id }, .{ .name = "member", .schema = name } });
    try variant(s, types, frame_types, "unsub", &.{.{ .name = "id", .schema = id }});
    try variant(s, types, frame_types, "state", &.{ .{ .name = "id", .schema = id }, .{ .name = "snap", .schema = try optional(s, types, unknown) }, .{ .name = "reset", .schema = try optional(s, types, unknown) }, .{ .name = "ops", .schema = try optional(s, types, try list(s, types, try list(s, types, unknown))) }, .{ .name = "error", .schema = try optional(s, types, error_shape) } });
    inline for (.{ "ping", "pong" }) |verb| try variant(s, types, frame_types, verb, &.{.{ .name = "n", .schema = unconstrained_int }});
    try variant(s, types, frame_types, "bye", &.{.{ .name = "reason", .schema = try optional(s, types, string) }});
    try variant(s, types, frame_types, "root_end", &.{.{ .name = "rootId", .schema = name }});
    try variant(s, types, frame_types, "invalidate", &.{.{ .name = "pattern", .schema = dictionary }});
    const number = try h.invoke(s, types, "Number", &.{});
    const options = try object(s, types, &.{ .{ .name = "remove", .schema = try optional(s, types, strings) }, .{ .name = "gateDeadline", .schema = try optional(s, types, number) }, .{ .name = "retireDeadline", .schema = try optional(s, types, number) } });
    try variant(s, types, frame_types, "prepare", &.{ .{ .name = "reload", .schema = id }, .{ .name = "codeVersion", .schema = id }, .{ .name = "plugins", .schema = strings }, .{ .name = "options", .schema = options } });
    const report = try object(s, types, &.{ .{ .name = "codeVersion", .schema = unconstrained_int }, .{ .name = "previous", .schema = unconstrained_int }, .{ .name = "changed", .schema = strings }, .{ .name = "removed", .schema = strings }, .{ .name = "prepared", .schema = strings }, .{ .name = "gated", .schema = strings } });
    try variant(s, types, frame_types, "vote", &.{ .{ .name = "reload", .schema = id }, .{ .name = "error", .schema = try optional(s, types, error_shape) }, .{ .name = "report", .schema = try optional(s, types, report) } });
    try variant(s, types, frame_types, "commit", &.{.{ .name = "reload", .schema = id }});
    try variant(s, types, frame_types, "retire", &.{.{ .name = "codeVersion", .schema = id }});
    try variant(s, types, frame_types, "abort", &.{.{ .name = "reload", .schema = id }});
    return h.invoke(s, types, "Union", &.{frame_types});
}
fn toWire(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const error_value = h.arg(args, 0);
    const instance = c.JS_IsInstanceOf(engine.context, error_value, captures[0]);
    if (instance < 0) return js.capture(engine);
    const result = try s.record();
    if (instance != 0) {
        const reason = try s.get(error_value, "reason");
        try h.field(&s, result, "code", try s.get(error_value, "code"));
        try h.field(&s, result, "message", try s.get(error_value, "message"));
        if (!c.JS_IsUndefined(reason)) try h.field(&s, result, "reason", try s.get(error_value, "reason"));
    } else {
        try h.field(&s, result, "code", try s.text("unavailable"));
        const base = c.JS_IsInstanceOf(engine.context, error_value, try s.keep(try js.global(engine, "Error")));
        if (base < 0) return js.capture(engine);
        try h.field(&s, result, "message", if (base != 0) try s.get(error_value, "message") else try s.keep(try js.call(engine, try s.keep(try js.global(engine, "String")), c.pi_js_undefined(), &.{error_value})));
    }
    return s.result(result);
}
fn arrow(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return invoke(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), magic, captures[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn invoke(engine: *h.Engine, input: c.JSValue, magic: c_int, captured: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (magic == 1) return c.pi_js_bool(engine.context, @intFromBool(try @import("native_tool_validation.zig").checkWithContext(engine, try s.record(), captured, input)));
    const code = try s.get(input, "code");
    const message = try s.get(input, "message");
    const replace = try s.get(message, "replace");
    var pattern_args = [_]c.JSValue{try s.text("^[a-z_]+(/[a-z_]+)?: ")};
    const pattern = try s.keep(try engine.checked(c.JS_CallConstructor(engine.context, engine.intrinsic_regexp_constructor, 1, &pattern_args)));
    const text = try s.keep(try js.call(engine, replace, message, &.{ pattern, try s.text("") }));
    const options = try s.record();
    try h.field(&s, options, "reason", try s.get(input, "reason"));
    var args = [_]c.JSValue{ code, text, options };
    return engine.checked(c.JS_CallConstructor(engine.context, captured, 3, &args));
}
pub fn install(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const api = try s.record();
    try h.field(&s, api, "PROTOCOL_VERSION", c.JS_NewInt32(engine.context, 2));
    const chord_error = try s.get(try s.get(bindings, "errors"), "ChordError");
    try js.define(engine, api, "toWireError", try @import("native_node_function.zig").create(engine, "toWireError", 1, toWire, &.{chord_error}));
    var error_captures = [_]c.JSValue{chord_error};
    try js.define(engine, api, "fromWireError", try engine.checked(c.JS_NewCFunctionData2(engine.context, arrow, "fromWireError", 1, 0, 1, &error_captures)));
    var schema_captures = [_]c.JSValue{try frameSchema(&s)};
    try js.define(engine, api, "isFrame", try engine.checked(c.JS_NewCFunctionData2(engine.context, arrow, "isFrame", 1, 1, 1, &schema_captures)));
    try h.field(&s, bindings, "Wire", api);
}
