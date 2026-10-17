//! Actual jiti2.7.0 jiti.import method. Requires the actual ordinary jitiRequire
//! binding; a namespace importer is not silently used as that implementation.
//! Derived from jiti2.7.0, Copyright Pooya Parsa, MIT; see the retained authority LICENSE.
//! Local revision2: current-event ownership is distinct from rejected DATA.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const body = @import("native_async_body.zig");
const af = body.native;
pub fn create(engine: *v.em.Engine, actual_context: c.JSValue, actual_jiti_require: c.JSValue) !c.JSValue {
    if (!c.JS_IsFunction(engine.context, actual_jiti_require)) return error.RequiredActualJitiRequire;
    return af.createResumable(engine, "import", 2, invoke, &.{ actual_context, actual_jiti_require });
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn put(engine: *v.em.Engine, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void { try v.js.define(engine, target, name, c.JS_DupValue(engine.context, value)); }
fn invoke(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    // Engine's previous diagnostic capture is not an exception event in this
    // invocation. Move ownership away before any call can populate a new slot.
    // Re-throwing the SAME old object still populates a new slot; pointer
    // inequality is neither necessary nor sufficient to classify the event.
    const prior = engine.captured_exception;
    engine.captured_exception = null;
    defer {
        if (engine.captured_exception == null) engine.captured_exception = prior else if (prior) |reason| engine.freeValue(reason);
    }
    // A C2 execution-context hook can leave a real pending fatal before this
    // callback is entered. Rejected DATA is not proof that the VM slot is empty.
    // Preserve any actual pending event before scope/flag/guest operations.
    if (c.JS_HasException(engine.context)) return v.js.capture(engine);
    const generation = engine.native_allocation_generation;
    return inner(engine, args, roots, state, completion, input) catch |err| {
        if (err == error.OutOfMemory) return err;
        if (err == error.JavaScriptException) {
            // Normalize a still-pending current event, never a restored old
            // capture. A missing actual event fails closed as an internal error.
            if (engine.captured_exception == null and c.JS_HasException(engine.context)) {
                const capture_error = v.js.capture(engine);
                if (capture_error != error.JavaScriptException) return capture_error;
            }
            const reason = engine.captured_exception orelse return error.MissingJitiImportCurrentCapturedReason;
            if (c.JS_IsUncatchableError(reason)) return err;
            try body.rethrowRecognizedAllocation(engine, reason, generation);
            engine.captured_exception = null;
            return .{ .thrown = reason };
        }
        return body.failureSince(engine, err, generation);
    };
}
fn inner(engine: *v.em.Engine, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (completion == .start) {
        const job = try body.init(&s, state);
        try put(engine, job, "generation", try s.own(try engine.checked(c.JS_NewBigUint64(engine.context, engine.native_allocation_generation))));
        const options = try s.object();
        try v.js.spreadInto(engine, options, arg(args, 1));
        try put(engine, options, "async", c.pi_js_bool(engine.context, 1));
        const result = try s.call(roots[1], c.pi_js_undefined(), &.{ roots[0], arg(args, 0), options });
        return .{ .awaited = c.JS_DupValue(engine.context, result) };
    }
    if (completion == .rejected) {
        try body.enterRejectedContinuation(engine);
        return .{ .thrown = c.JS_DupValue(engine.context, input) };
    }
    return .{ .returned = try @import("native_jiti_interop.zig").importDefault(engine, input, arg(args, 1)) };
}
