// Copyright Sindre Sorhus and Node contributors. MIT; retained Node authority.
//! Complete internal/tty native module assembly and original hasColors.
//! The private realm receives an actual completed default record. This owner
//! does not register a public C module or change the public builtin allowlist.
const a = @import("native_node_argument_values.zig");
const functions = @import("native_node_module_callable.zig");
const sync = @import("native_sync_arguments.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const builtin_require = @import("native_node_internal_builtin_require.zig");
const color_depth = @import("native_node_tty_color_depth.zig");
const argument_errors = @import("native_node_argument_errors.zig");
const c = a.c;
const Scope = a.Scope;
const owner_key = "\x00native.internal.tty.owner";
pub const module_name = "internal/tty";
/// These exact admissions belong in the application's complete selected
/// private builtin set BEFORE any consumer obtains its requireBuiltin.
pub const bindings = [_]builtin_require.Binding{
    .{ .id = "os", .module_name = "node:os" },
    .{ .id = "internal/tty", .module_name = module_name },
};
pub const Inputs = struct {
    /// The existing actual per-Engine private requireBuiltin, already admitted
    /// for the above subset. No callback or replacement namespace is accepted.
    require: c.JSValue,
};
const Attempt = struct { owner: c.JSValue, default_record: c.JSValue };

fn ready(s: *Scope, record: c.JSValue) !void {
    if (!s.truthy(try s.get(record, "ready"))) return error.ActualInternalTtyAssemblyReentry;
}
fn actualRequire(s: *Scope, supplied: c.JSValue) !c.JSValue {
    // Do not silently create a restricted require owner and block the caller's
    // later admissions. The full bootstrap assembler owns its selected set.
    if (!s.engine.native_module_values.contains("pi-native:private/internal-builtin-require"))
        return error.RequiredBootstrappedActualInternalBuiltinRequire;
    const expected = try s.own(try builtin_require.acquire(s.engine, .{ .bindings = &bindings }));
    if (!s.equal(expected, supplied)) return error.ActualInternalTtyRequireIdentityChanged;
    return a.duplicate(s.engine, expected);
}
fn actualProcess(s: *Scope) !c.JSValue {
    const known = s.engine.native_module_values.get("node:process") orelse return error.RequiredActualInternalTtyProcess;
    const record = try s.own(a.duplicate(s.engine, known));
    var descriptor = try s.descriptor(record, try s.text("default")) orelse return error.RequiredActualInternalTtyProcessDefault;
    defer s.releaseDescriptor(&descriptor);
    if (descriptor.flags & c.JS_PROP_GETSET != 0 or !c.JS_IsObject(descriptor.value))
        return error.RequiredActualInternalTtyProcessData;
    return a.duplicate(s.engine, descriptor.value);
}
fn publishPending(s: *Scope, record: c.JSValue) !void {
    const retained = a.duplicate(s.engine, record);
    s.engine.native_module_values.put(s.engine.gpa, owner_key, retained) catch |err| {
        var completion = a.owned.Completion.initVoid(s.engine, err);
        completion.release(retained);
        return completion.finishVoid();
    };
}
fn discardAttempt(s: *Scope, attempt: Attempt) void {
    // Remove both exact identities before either release can reenter. Never
    // remove a later successful owner installed by a nested attempt.
    var discarded = [_]c.JSValue{c.pi_js_undefined(), c.pi_js_undefined()};
    if (!c.JS_IsUndefined(attempt.default_record)) {
        if (s.engine.native_module_values.get(module_name)) |known| {
            if (s.equal(known, attempt.default_record))
                discarded[0] = s.engine.native_module_values.fetchRemove(module_name).?.value;
        }
    }
    if (s.engine.native_module_values.get(owner_key)) |known| {
        if (s.equal(known, attempt.owner))
            discarded[1] = s.engine.native_module_values.fetchRemove(owner_key).?.value;
    }
    for (&discarded) |*value| s.boundary.release(value);
}
fn publishCompleted(s: *Scope, attempt: Attempt) !void {
    if (s.engine.native_module_values.contains(module_name) or s.engine.native_module_names.contains(module_name))
        return error.ActualInternalTtyModuleConflict;
    const retained = a.duplicate(s.engine, attempt.default_record);
    s.engine.native_module_values.put(s.engine.gpa, module_name, retained) catch |err| {
        var completion = a.owned.Completion.initVoid(s.engine, err);
        completion.release(retained);
        return completion.finishVoid();
    };
    const generation = try s.beforeAllocation();
    const status = c.JS_SetPropertyStr(s.engine.context, attempt.owner, "ready", c.pi_js_bool(s.engine.context, 1));
    try s.boundary.checkPendingSince(generation);
    if (status < 0) return error.MissingActualInternalTtyReadyReason;
}
/// Owned original module.exports. Its native default record is private: normal
/// Engine.requireBuiltin continues to reject internal/tty because no public
/// native_module_names admission is made here.
pub fn acquire(engine: *a.v.em.Engine, inputs: Inputs) !c.JSValue {
    var s = Scope.init(engine);
    var outputs = [_]c.JSValue{c.pi_js_undefined()};
    var failure: ?anyerror = null;
    var attempt: ?Attempt = null;
    if (acquireBody(&s, inputs, &attempt)) |value| outputs[0] = value else |err| failure = err;
    s.boundary.retire(failure, &s.values, &outputs);
    if (!s.boundary.failed(failure)) {
        if (attempt) |created| publishCompleted(&s, created) catch |err| { failure = err; };
    }
    if (s.boundary.failed(failure)) {
        if (attempt) |created| { attempt = null; discardAttempt(&s, created); }
    }
    try s.boundary.finishRetired(failure, &outputs);
    return outputs[0];
}
fn acquireBody(s: *Scope, inputs: Inputs, attempt: *?Attempt) !c.JSValue {
    try s.pending();
    if (s.engine.native_module_values.get(owner_key)) |known| {
        const record = try s.own(a.duplicate(s.engine, known));
        try ready(s, record);
        if (!s.equal(try s.get(record, "require"), inputs.require)) return error.ActualInternalTtyRequireIdentityChanged;
        const published = s.engine.native_module_values.get(module_name) orelse return error.ActualInternalTtyModuleMissing;
        if (s.engine.native_module_names.contains(module_name) or !s.equal(published, try s.get(record, "default")))
            return error.ActualInternalTtyModuleConflict;
        return a.duplicate(s.engine, try s.get(record, "exports"));
    }
    if (s.engine.native_module_values.contains(module_name) or s.engine.native_module_names.contains(module_name))
        return error.ActualInternalTtyModuleConflict;
    const require = try s.own(try a.expression(s.engine, actualRequire, .{inputs.require}));
    const process = try s.own(try a.expression(s.engine, actualProcess, .{}));
    const cached_map = s.engine.native_module_values.get("\x00native.fs.SafeMap") orelse
        return error.RequiredBootstrappedActualInternalTtySafeMap;
    const safe_map = try s.own(a.duplicate(s.engine, cached_map));
    const validate_integer = try s.own(try argument_errors.validateInteger(s.engine));
    if (!c.JS_IsFunction(s.engine.context, validate_integer)) return error.RequiredActualInternalTtyIntegerValidator;
    const record = try s.objectProto(c.pi_js_null());
    try s.define(record, "ready", a.boolean(s, false), c.JS_PROP_WRITABLE);
    try s.define(record, "require", require, 0);
    try publishPending(s, record);
    // Until a completed default record exists, undefined is an exact private
    // token which cannot remove any preexisting (already rejected) admission.
    attempt.* = .{ .owner = record, .default_record = c.pi_js_undefined() };
    const depth = try s.own(try color_depth.create(s.engine,
        .{ .process = process, .require = require, .safe_map = safe_map }));
    const colors = try s.own(try functions.createWithArguments(s.engine, "hasColors", 2, true,
        .{ .formal_count = 2, .callback = colorsCallback }, &.{depth, validate_integer}));
    const exports = try s.object();
    try s.define(exports, "getColorDepth", depth, c.JS_PROP_C_W_E);
    try s.define(exports, "hasColors", colors, c.JS_PROP_C_W_E);
    // The same Engine producer used by registered native defaults supplies
    // this record; its C-module/public-name publication step is intentionally
    // absent for this original private builtin.
    const default_record = try s.own(try s.engine.defaultExports(exports));
    try s.define(record, "default", default_record, 0);
    try s.define(record, "exports", exports, 0);
    attempt.* = .{ .owner = record, .default_record = default_record };
    return a.duplicate(s.engine, exports);
}
fn validateCount(s: *Scope, validator: c.JSValue, count: c.JSValue) !c.JSValue {
    _ = try s.call(validator, c.pi_js_undefined(), &.{count, try s.text("count"), c.JS_NewInt32(s.engine.context, 2)});
    return c.pi_js_undefined();
}
fn colorCapacity(s: *Scope, depth: c.JSValue, environment: c.JSValue) !c.JSValue {
    const result = try s.call(depth, c.pi_js_undefined(), &.{environment});
    return a.duplicate(s.engine, try s.binary(@intFromEnum(arithmetic.Operation.power),
        c.JS_NewInt32(s.engine.context, 2), result));
}
fn colorsCallback(engine: *a.v.em.Engine, _: c.JSValue, args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, colorsBody, .{args, roots[0], roots[1]});
}
fn colorsBody(s: *Scope, args: *sync.Arguments, depth: c.JSValue, validator: c.JSValue) !c.JSValue {
    try s.pending();
    const count = args.get(0);
    if (c.JS_IsUndefined(args.get(1)) and
        (c.JS_IsUndefined(count) or (c.JS_IsObject(count) and !c.JS_IsFunction(s.engine.context, count) and !c.JS_IsNull(count))))
    {
        // Actual mutable Source formals: publish env=count before replacing
        // count. Its original value therefore survives through env ownership.
        try args.copy(1, args.get(0));
        try args.copy(0, c.JS_NewInt32(s.engine.context, 16));
    } else {
        // The ignored call result retires before entering getColorDepth.
        _ = try a.expression(s.engine, validateCount, .{validator, args.get(0)});
    }
    const left = try s.own(a.duplicate(s.engine, args.get(0)));
    const right = try s.own(try a.expression(s.engine, colorCapacity, .{depth, args.get(1)}));
    return a.duplicate(s.engine, try s.binary(@intFromEnum(arithmetic.Operation.less_equal), left, right));
}
