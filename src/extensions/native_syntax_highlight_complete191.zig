//! Private complete-index candidate. Default application binding is unchanged.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const eager_module = @import("native_syntax_highlight.zig");
const index = @import("native_highlight_index191.zig");
const Scope = @import("native_highlight_scope.zig").Scope;
const ordinary = @import("native_node_function.zig");
const c = em.c;
pub const Bundle = struct {
    eager: eager_module.Eager,
    syntax: c.JSValue,
    load: c.JSValue,
    readiness: c.JSValue,
    import_function: c.JSValue,
    pub fn deinit(self: Bundle, engine: *em.Engine) void {
        self.eager.deinit(engine);
        engine.releaseNativeValue(self.syntax);
        engine.releaseNativeValue(self.load);
        engine.releaseNativeValue(self.readiness);
        engine.releaseNativeValue(self.import_function);
    }
    pub fn ready(self: Bundle, engine: *em.Engine) bool {
        return index.ready(engine, self.eager.core);
    }
};
fn settle(engine: *em.Engine, state: c.JSValue, key: [*:0]const u8, value: c.JSValue) !void {
    const function = try engine.checked(native_guest_1: { try engine.checkNativeEntry(); break :native_guest_1 c.JS_GetPropertyStr(engine.context, state, key); });
    defer engine.releaseNativeValue(function);
    var args = [_]c.JSValue{value};
    const result = try engine.checked(native_guest_0: { try engine.checkNativeEntry(); break :native_guest_0 c.JS_Call(engine.context, function, c.pi_js_undefined(), args.len, &args); });
    engine.releaseNativeValue(result);
}
fn rejectPrivateReadiness(engine: *em.Engine, state: c.JSValue) !void {
    _ = c.JS_ThrowTypeError(engine.context, "Actual complete191 grammar registration is required");
    try @import("native_pending_owner.zig").checkFatal(engine);
    const reason = c.JS_GetException(engine.context);
    defer engine.releaseNativeValue(reason);
    try settle(engine, state, "readyReject", reason);
}
fn importIndex(engine: *em.Engine, state: c.JSValue) !void {
    const core = try engine.checked(native_guest_1: { try engine.checkNativeEntry(); break :native_guest_1 c.JS_GetPropertyStr(engine.context, state, "core"); });
    defer engine.releaseNativeValue(core);
    const ready = index.registerAll(engine, core) catch |err| {
        if (err == error.OutOfMemory) _ = engine.throwNativeOutOfMemoryFatal();
        _ = sdk.fail(engine, err);
        try @import("native_pending_owner.zig").checkFatal(engine);
        const reason = c.JS_GetException(engine.context);
        defer engine.releaseNativeValue(reason);
        try settle(engine, state, "importReject", reason);
        try settle(engine, state, "readyReject", reason);
        return;
    };
    const namespace = try engine.checked(native_guest_0: { try engine.checkNativeEntry(); break :native_guest_0 c.JS_GetPropertyStr(engine.context, state, "namespace"); });
    defer engine.releaseNativeValue(namespace);
    // Source import success and private actual-factory readiness are distinct.
    // A safe-mode factory fallback still fulfills Source's module import.
    try settle(engine, state, "importResolve", namespace);
    if (ready) try settle(engine, state, "readyResolve", c.pi_js_undefined()) else try rejectPrivateReadiness(engine, state);
}
fn importJob(context: ?*c.JSContext, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const pending_engine = @import("engine.zig").Engine.fromContext(context.?);
    var pending_frame = @import("native_pending_owner.zig").Frame.init(pending_engine);
    pending_frame.enter() catch return pending_frame.finishCallback(c.pi_js_exception());
    return pending_frame.finishCallback(importJobPendingBody(context, argc, argv));
}
fn importJobPendingBody(context: ?*c.JSContext, argc: c_int, argv: [*c]c.JSValue) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    if (argc != 1) return c.JS_ThrowInternalError(engine.context, "Native full-index job state absent");
    importIndex(engine, argv[0]) catch |err| return sdk.fail(engine, err);
    return c.pi_js_undefined();
}
fn requestImport(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const state = roots[0];
    var pending = try s.get(state, "importPromise");
    if (c.JS_IsUndefined(pending)) {
        var resolvers: [2]c.JSValue = undefined;
        pending = try s.own(try engine.checked(c.JS_NewPromiseCapability(engine.context, &resolvers)));
        const resolve = try s.own(resolvers[0]);
        const reject = try s.own(resolvers[1]);
        try s.set(state, "importPromise", pending);
        try s.put(state, "importResolve", resolve);
        try s.put(state, "importReject", reject);
        var args = [_]c.JSValue{state};
        if (native_guest_0: { try engine.checkNativeEntry(); break :native_guest_0 c.JS_EnqueueJob(engine.context, importJob, args.len, &args); } < 0) return @import("native_js_values.zig").capture(engine);
    }
    return c.JS_DupValue(engine.context, pending);
}
pub fn create(engine: *em.Engine) !Bundle {
    const eager = try eager_module.createEager(engine);
    errdefer eager.deinit(engine);
    try index.install(engine, eager.core, eager.factories);
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const state = try s.object();
    try s.put(state, "core", eager.core);
    try s.put(state, "importPromise", c.pi_js_undefined());
    const exports = try s.object();
    try s.put(exports, "default", eager.core);
    try s.put(exports, "module.exports", eager.core);
    try s.put(state, "namespace", try s.own(try engine.valueNamespace(exports)));
    var ready_resolvers: [2]c.JSValue = undefined;
    const readiness = try s.own(try engine.checked(c.JS_NewPromiseCapability(engine.context, &ready_resolvers)));
    const resolve = try s.own(ready_resolvers[0]);
    const reject = try s.own(ready_resolvers[1]);
    c.JS_PromiseMarkAsHandled(engine.context, readiness);
    try s.put(state, "readyResolve", resolve);
    try s.put(state, "readyReject", reject);
    const importer = try s.own(try ordinary.createArrow(engine, "nativeHighlightIndexImport", 0, requestImport, &.{state}));
    const load = try s.own(try @import("native_highlight_lazy_loader.zig").create(engine, importer));
    try s.put(eager.syntax, "loadAllHighlightLanguages", load);
    const syntax = try s.own(try engine.valueNamespace(eager.syntax));
    return .{ .eager = eager, .syntax = c.JS_DupValue(engine.context, syntax), .load = c.JS_DupValue(engine.context, load), .readiness = c.JS_DupValue(engine.context, readiness), .import_function = c.JS_DupValue(engine.context, importer) };
}
