// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Selected original options.cc serializers over the Engine's actual owned
//! startup configuration. These callables are private inputs to the genuine
//! JavaScript declarations; they do not publish a partial internalBinding.
const a = @import("native_node_argument_values.zig");
const c = a.c;
const Scope = a.Scope;
const config = @import("native_node_options_config.zig");
const functions = @import("native_node_module_callable.zig");
pub const Exports = struct { values: c.JSValue, embedder: c.JSValue };
fn known(engine: *a.v.em.Engine) !*config.Config {
    return engine.node_options orelse return error.ActualNodeOptionsConfigurationRequired;
}
fn define(s: *Scope, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    return s.define(target, name, value, c.JS_PROP_C_W_E);
}
fn strings(s: *Scope, input: []const []const u8) !c.JSValue {
    const result = try a.array(s);
    for (input, 0..) |value, index| try a.index(s, result, @intCast(index), try s.text(value));
    return a.duplicate(s.engine, result);
}
fn fieldValue(s: *Scope, values: *const config.Values, comptime entry: config.Entry) !c.JSValue {
    const input = @field(values, @tagName(entry.field));
    return switch (comptime entry.kind) {
        .boolean => a.boolean(s, input),
        .optional_boolean => a.boolean(s, input orelse return error.ActualNodeStripTypesBuildDefaultRequired),
        .string => a.duplicate(s.engine, try s.text(input)),
        .string_list => strings(s, input),
    };
}
fn boolean(s: *Scope, target: c.JSValue, comptime name: [:0]const u8, value: bool) !void {
    // GetCLIOptionsValues adds the negated entry before its original Boolean.
    try define(s, target, "--no" ++ name[1..], a.boolean(s, !value));
    try define(s, target, name, a.boolean(s, value));
}
fn bootstrapError(s: *Scope, serialized: ?*bool) !c.JSValue {
    // Exact ERR_OPTIONS_BEFORE_BOOTSTRAPPING(Error) macro: intrinsic Error,
    // own message, then the actual live code Set before the explicit throw.
    const code = try s.text("ERR_OPTIONS_BEFORE_BOOTSTRAPPING");
    const message = try s.text("Should not query options before bootstrapping is done");
    const allocation = try s.beforeAllocation();
    const reason = try s.checkedAllocation(c.JS_NewError(s.engine.context), allocation);
    try s.define(reason, "message", message, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    // V8 Object::Set uses kDontThrow: a normal false assignment still returns
    // normally. Actual setter/proxy exceptions remain pending and are checked.
    const key = try s.text("code");
    try s.pending();
    const status = c.JS_SetPropertyValue(s.engine.context, reason,
        c.JS_DupValue(s.engine.context, key), c.JS_DupValue(s.engine.context, code), 0);
    try s.pending();
    if (status < 0) return error.MissingActualNodeOptionsBootstrapSetReason;
    const failure = a.raise(s, reason);
    // THROW_ERR is a void native helper, not a return from GetCLIOptionsValues.
    // Its serialized flag is set after the explicit throw, before native unwind.
    if (serialized) |flag| flag.* = true;
    return @as(anyerror!c.JSValue, failure);
}
fn valuesBody(s: *Scope) !c.JSValue {
    const owner = try known(s.engine);
    if (!owner.bootstrapped) return bootstrapError(s, &owner.serialized);
    try owner.beforeSerialize();
    const output = try s.objectProto(c.pi_js_null());
    inline for (config.entries) |entry| {
        if (comptime entry.kind == .boolean or entry.kind == .optional_boolean) {
            const value = @field(owner.values, @tagName(entry.field));
            try boolean(s, output, entry.name,
                if (comptime entry.kind == .boolean) value else value.?);
        } else {
            const value = try s.own(try a.expression(s.engine, fieldValue, .{ &owner.values, entry }));
            try define(s, output, entry.name, value);
        }
    }
    // The compile-disabled QUIC option is kNoOp, whose value is undefined;
    // only the actual enabled Boolean option gets a --no-* companion.
    if (owner.original.features.quic) {
        try boolean(s, output, "--experimental-quic", owner.values.experimental_quic);
    } else try define(s, output, "--experimental-quic", c.pi_js_undefined());
    try boolean(s, output, "--inspect", owner.values.inspector_enabled);
    try boolean(s, output, "--inspect-brk", owner.values.inspect_brk);
    try boolean(s, output, "--inspect-brk-node", owner.values.inspect_brk_node);
    try boolean(s, output, "--inspect-wait", owner.values.inspect_wait);
    const host_port = try s.objectProto(c.pi_js_null());
    try define(s, host_port, "host", try s.text(owner.values.inspect_host));
    try define(s, host_port, "port", c.JS_NewInt32(s.engine.context, owner.values.inspect_port));
    try define(s, output, "--inspect-port", host_port);
    return a.duplicate(s.engine, output);
}
fn valuesCallback(engine: *a.v.em.Engine, _: c.JSValue, _: *@import("native_sync_arguments.zig").Arguments, _: []const c.JSValue) !c.JSValue {
    return a.expression(engine, valuesBody, .{});
}
fn embedderBody(s: *Scope) !c.JSValue {
    const owner = try known(s.engine);
    if (!owner.bootstrapped) return bootstrapError(s, null);
    const values = owner.original.embedder;
    const result = try s.objectProto(c.pi_js_null());
    try define(s, result, "shouldNotRegisterESMLoader", a.boolean(s, values.should_not_register_esm_loader));
    try define(s, result, "noGlobalSearchPaths", a.boolean(s, values.no_global_search_paths or !owner.values.global_search_paths));
    try define(s, result, "noBrowserGlobals", a.boolean(s, values.no_browser_globals));
    try define(s, result, "hasEmbedderPreload", a.boolean(s, values.has_embedder_preload));
    return a.duplicate(s.engine, result);
}
fn embedderCallback(engine: *a.v.em.Engine, _: c.JSValue, _: *@import("native_sync_arguments.zig").Arguments, _: []const c.JSValue) !c.JSValue {
    return a.expression(engine, embedderBody, .{});
}
pub fn create(engine: *a.v.em.Engine) !Exports {
    var s = Scope.init(engine);
    var outputs = [_]c.JSValue{ c.pi_js_undefined(), c.pi_js_undefined() };
    var failure: ?anyerror = null;
    createBody(&s, &outputs) catch |err| { failure = err; };
    try s.boundary.finishMany(failure, &s.values, &outputs);
    return .{ .values = outputs[0], .embedder = outputs[1] };
}
fn createBody(s: *Scope, outputs: *[2]c.JSValue) !void {
    _ = try known(s.engine);
    const values = try s.own(try functions.createWithArguments(s.engine, "getCLIOptionsValues", 0, false,
        .{ .formal_count = 0, .callback = valuesCallback }, &.{}));
    const embedder = try s.own(try functions.createWithArguments(s.engine, "getEmbedderOptions", 0, false,
        .{ .formal_count = 0, .callback = embedderCallback }, &.{}));
    outputs.* = .{ a.duplicate(s.engine, values), a.duplicate(s.engine, embedder) };
}
