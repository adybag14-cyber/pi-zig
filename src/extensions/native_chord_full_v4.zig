//! Private b45 v4 graph diagnostic composition; full public exports remain gated.
const h = @import("native_chord_host_values.zig");
const Scope = h.Scope;
const js = h.js;
const c = h.c;
pub const Classes = struct { exports: c.JSValue, bindings: c.JSValue };
fn arrow(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, mode: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    const args = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    return (if (mode == 0) createHost(engine, c.pi_js_undefined(), args, captures[0..1]) else definition(engine, c.pi_js_undefined(), args, captures[0..1])) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn createHost(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const options = if (c.JS_IsUndefined(h.arg(args, 0))) try s.record() else h.arg(args, 0);
    return s.result(try h.construct(&s, captures[0], "HostImpl", &.{options}));
}
fn definition(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const registry = c.JS_ToBool(engine.context, captures[0]) != 0;
    const options = if (c.JS_IsUndefined(h.arg(args, 1))) try s.record() else h.arg(args, 1);
    const result = try s.record();
    try h.field(&s, result, if (registry) "name" else "setup", h.arg(args, 0));
    const value = try s.get(options, if (registry) "conflict" else "uses");
    try h.field(&s, result, if (registry) "conflict" else "uses", if (registry and h.nullish(value)) try s.text("error") else value);
    return s.result(result);
}
fn inflateMessage(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    return s.result(try @import("native_chord_packing_v4.zig").inflateMessage(&s, h.arg(args, 0)));
}
pub fn classes(engine: *h.Engine) !Classes {
    const generation = engine.native_allocation_generation;
    return createClasses(engine) catch |err| return engine.nativeAllocationError(err, generation);
}
fn createClasses(engine: *h.Engine) !Classes {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try @import("abort_signal.zig").install(engine);
    // Host.resolve uses the genuine URL brand even for object facet references.
    try @import("node_url.zig").install(engine);
    if (engine.buffer_prototype == null) try @import("node_buffer.zig").install(engine);
    const bindings = try s.record();
    try h.field(&s, bindings, "classes", try s.record());
    const object = try s.keep(try js.global(engine, "Object"));
    try h.field(&s, bindings, "objectPrototype", try s.get(object, "prototype"));
    const resources = try @import("native_chord_latest_resources.zig").classes(engine);
    _ = try s.keep(resources.exports);
    _ = try s.keep(resources.bindings);
    try h.field(&s, bindings, "errors", resources.exports);
    try h.field(&s, bindings, "resourceBindings", resources.bindings);
    inline for (.{ "ResourceImpl", "ResourceFacade" }) |name| try h.field(&s, bindings, name, try s.get(resources.exports, name));
    const contracts = try s.keep(try @import("native_chord_contracts_v4.zig").exports(engine, try s.get(resources.exports, "ChordError")));
    try h.field(&s, bindings, "contracts", contracts);
    try h.field(&s, bindings, "schema", try s.keep(try @import("native_chord_schema_api.zig").exports(engine)));
    try h.field(&s, bindings, "emptyTable", try h.map(&s));
    try h.field(&s, bindings, "refsByProxy", try s.keep(try js.builtin(engine, "WeakMap", &.{})));
    try @import("native_chord_publish.zig").initialize(engine, bindings);
    try @import("native_chord_object_declarations.zig").install(engine, bindings);
    try @import("native_chord_cells_v4.zig").install(engine, bindings);
    try @import("native_chord_packing_v4.zig").install(&s, bindings);
    try @import("native_chord_links_v4.zig").install(engine, bindings);
    try @import("native_chord_delta_codec.zig").install(engine, bindings);
    try @import("native_chord_wire_v4.zig").install(engine, bindings);
    try @import("native_chord_latest_host.zig").install(engine, bindings);
    try @import("native_chord_object_context.zig").install(engine, bindings);
    try @import("native_chord_object_self.zig").install(engine, bindings);
    try @import("native_chord_object.zig").install(engine, bindings);
    try @import("native_chord_object_readable.zig").install(engine, bindings);
    try @import("native_chord_object_ref.zig").install(engine, bindings);
    try @import("native_chord_remote_binding_v4.zig").install(engine, bindings);
    try @import("native_chord_remote_ref_v4.zig").install(engine, bindings);
    try @import("native_chord_relay_v4.zig").install(engine, bindings);
    try @import("native_chord_connection_v4.zig").install(engine, bindings);
    try @import("native_chord_reload.zig").install(engine, bindings);
    const api = try s.record();
    try js.spreadInto(engine, api, contracts);
    inline for (.{ "ChordError", "isChordError", "forbidden", "invalid" }) |name| try h.field(&s, api, name, try s.get(resources.exports, name));
    inline for (.{ "memoryLinkPair", "ipcLink", "webSocketLink" }) |name| try h.field(&s, api, name, try s.get(bindings, name));

    var host_capture = [_]c.JSValue{bindings};
    try js.define(engine, api, "createHost", try engine.checked(c.JS_NewCFunctionData2(engine.context, arrow, "createHost", 0, 0, 1, &host_capture)));
    inline for (.{ "defineFacet", "defineRegistry" }, 0..) |name, index| {
        var capture = [_]c.JSValue{c.pi_js_bool(engine.context, @intCast(index))};
        try js.define(engine, api, name, try engine.checked(c.JS_NewCFunctionData2(engine.context, arrow, name, 1, 1, 1, &capture)));
    }
    try js.define(engine, api, "inflateMessage", try @import("native_node_function.zig").create(engine, "inflateMessage", 1, inflateMessage, &.{}));
    try @import("native_chord_accept_websockets.zig").install(engine, api, bindings);
    // state.ts imports the genuine shared context module. Preserve its exact
    // BACKGROUND_CONTEXT identity rather than manufacturing another context.
    try @import("native_durable_context.zig").install(engine);
    const context = engine.native_module_values.get("@earendil-works/chord/context") orelse return error.NativeChordContextUnavailable;
    try @import("native_chord_replicated_state.zig").install(engine, api, try s.get(context, "BACKGROUND_CONTEXT"));
    try h.field(&s, api, "PACK_THRESHOLD", c.JS_NewInt32(engine.context, @import("native_chord_packing_v4.zig").threshold));
    try h.field(&s, api, "PROTOCOL_VERSION", c.JS_NewInt32(engine.context, 4));
    try @import("native_chord_json.zig").install(engine, api);
    return .{ .exports = s.result(api), .bindings = s.result(bindings) };
}
