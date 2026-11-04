//! Actual native invocation ownership for host catch/rejection boundaries.
//! Captured diagnostics and Promise values never establish fatal authority.
const em = @import("engine.zig");
const c = em.c;

/// Surface only the actual slot or an independently retained native producer.
/// This operation neither inspects nor promotes captured diagnostic DATA.
pub fn checkFatal(engine: *em.Engine) !void {
    _ = engine.nativeCallbackResult(c.pi_js_undefined());
    if (engine.nativeTerminationObserved()) return error.ExecutionTerminated;
    if (c.JS_PiIsPendingUncatchable(engine.context))
        return error.JavaScriptException;
}

/// A direct Zig allocator result is a producer. Ordinary caught errors keep
/// the existing Source catch behavior without classifying their value.
pub fn catchFailure(engine: *em.Engine, err: anyerror) !void {
    if (err == error.OutOfMemory) {
        _ = engine.throwNativeOutOfMemoryFatal();
        return err;
    }
    // A canceled private event may already be empty; its historical host
    // unwind still cannot enter Source catch, reporting, or rejection work.
    if (err == error.ExecutionTerminated) return err;
    try checkFatal(engine);
}

/// Returned inactive. The containing wrapper keeps this object at a stable
/// address until its body's roots have retired and the invocation is popped.
pub const Frame = struct {
    engine: *em.Engine,
    invocation: em.Engine.NativeInvocation = .{},

    pub fn init(engine: *em.Engine) Frame { return .{ .engine = engine }; }

    pub fn enter(self: *Frame) !void {
        self.engine.enterNativeInvocation(&self.invocation);
        const pending = self.engine.nativeCallbackResult(c.pi_js_undefined());
        if (self.invocation.terminated) return error.ExecutionTerminated;
        if (c.JS_IsException(pending)) return error.JavaScriptException;
    }

    /// The real owner history remains readable after its final pop.
    pub fn terminated(self: *const Frame) bool { return self.invocation.terminated; }

    /// The actual C ABI receives the owned completion after the final pop.
    /// Historical termination is a native exit even when cancellation has
    /// removed its slot; it never creates a replacement reason or class.
    pub fn finishCallback(self: *Frame, result: c.JSValue) c.JSValue {
        var owned = result;
        if (self.invocation.terminated) {
            // Keep the selected actual tuple across this one-root retirement.
            if (!c.JS_IsException(owned)) self.engine.releaseNativeValue(owned);
            owned = self.historicalResult();
        }
        const finished = self.engine.leaveNativeInvocation(&self.invocation, owned);
        // leave() can first observe late history only while an actual pending
        // owner also consumes result. There is no normal value to retire here.
        if (self.invocation.terminated) return self.historicalResult();
        return finished;
    }

    /// Called only under this invocation's actual historical unwind authority.
    /// Normalize retained/actual ownership without polling a fresh request.
    fn historicalResult(self: *Frame) c.JSValue {
        self.engine.releaseNativeValue(c.pi_js_undefined());
        return if (c.JS_HasException(self.engine.context))
            c.pi_js_exception()
        else
            c.JS_PiNativeTerminationResult();
    }

    fn failure(self: *Frame, err: anyerror) anyerror {
        if (err == error.OutOfMemory) _ = self.engine.throwNativeOutOfMemoryFatal();
        const pending = self.engine.leaveNativeInvocation(&self.invocation, c.pi_js_undefined());
        if (self.invocation.terminated) return error.ExecutionTerminated;
        if (c.JS_IsException(pending) and err != error.OutOfMemory and err != error.ExecutionTerminated)
            return error.JavaScriptException;
        return err;
    }

    /// Host completion leaves an actual pending event in the VM slot; checked()
    /// would turn it into DATA after this last stable owner had already gone.
    pub fn finishValue(self: *Frame, outcome: anyerror!c.JSValue) !c.JSValue {
        const value = outcome catch |err| return self.failure(err);
        const result = if (self.invocation.terminated and !c.JS_HasException(self.engine.context)) blk: {
            // With no actual slot to escrow, retire the owned success under
            // this live owner. A pending tuple instead belongs to leave(),
            // which takes it before the result can run a native finalizer.
            self.engine.releaseNativeValue(value);
            break :blk self.engine.leaveNativeInvocation(&self.invocation, c.pi_js_undefined());
        } else self.engine.leaveNativeInvocation(&self.invocation, value);
        if (self.invocation.terminated) return error.ExecutionTerminated;
        if (c.JS_IsException(result)) return error.JavaScriptException;
        return result;
    }

    pub fn finishVoid(self: *Frame, outcome: anyerror!void) !void {
        outcome catch |err| return self.failure(err);
        const result = self.engine.leaveNativeInvocation(&self.invocation, c.pi_js_undefined());
        if (self.invocation.terminated) return error.ExecutionTerminated;
        if (c.JS_IsException(result)) return error.JavaScriptException;
    }

    pub fn finishBool(self: *Frame, outcome: anyerror!bool) !bool {
        const value = outcome catch |err| return self.failure(err);
        const result = self.engine.leaveNativeInvocation(&self.invocation, c.pi_js_undefined());
        if (self.invocation.terminated) return error.ExecutionTerminated;
        if (c.JS_IsException(result)) return error.JavaScriptException;
        return value;
    }

    pub fn finishNumber(self: *Frame, outcome: anyerror!f64) !f64 {
        const value = outcome catch |err| return self.failure(err);
        const result = self.engine.leaveNativeInvocation(&self.invocation, c.pi_js_undefined());
        if (self.invocation.terminated) return error.ExecutionTerminated;
        if (c.JS_IsException(result)) return error.JavaScriptException;
        return value;
    }
};
