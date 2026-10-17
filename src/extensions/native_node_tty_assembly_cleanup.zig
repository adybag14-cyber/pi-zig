//! Leaf-local assembly retirement. History is escrowed before callbacks;
//! current events are ranked before EACH owned value release. No Scope change.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
pub const Cleanup = struct {
    engine: *v.em.Engine,
    history: ?c.JSValue,
    selected: ?c.JSValue = null,
    fatal: bool = false,
    pub fn begin(engine: *v.em.Engine) Cleanup {
        const history = engine.captured_exception; engine.captured_exception = null;
        return .{ .engine = engine, .history = history };
    }
    fn currentFatal(self: *Cleanup, reason: c.JSValue, generation: u64) bool {
        if (c.JS_IsUncatchableError(reason)) return true;
        const tag = c.pi_js_native_allocation_error_generation(reason);
        const distance = tag -% generation;
        if (tag == 0 or distance == 0 or distance > self.engine.native_allocation_generation -% generation) return false;
        c.JS_SetUncatchableError(self.engine.context, reason); return true;
    }
    fn select(self: *Cleanup, reason: c.JSValue, generation: u64) ?c.JSValue {
        const fatal = self.currentFatal(reason, generation);
        if (self.selected == null) { self.selected = reason; self.fatal = fatal; return null; }
        if (fatal and !self.fatal) { const old = self.selected; self.selected = reason; self.fatal = true; return old; }
        return reason;
    }
    pub fn collect(self: *Cleanup, generation: u64) void {
        const pending: ?c.JSValue = if (c.JS_HasException(self.engine.context)) c.JS_GetException(self.engine.context) else null;
        const captured = self.engine.captured_exception; self.engine.captured_exception = null;
        var discarded: [2]?c.JSValue = .{ null, null };
        if (pending) |reason| discarded[0] = self.select(reason, generation);
        if (captured) |reason| discarded[1] = self.select(reason, generation);
        for (discarded) |value| if (value) |reason| self.release(reason);
    }
    pub fn release(self: *Cleanup, value: c.JSValue) void {
        const generation = self.engine.native_allocation_generation;
        self.engine.freeValue(value); self.collect(generation);
    }
    pub fn scope(self: *Cleanup, value: *v.Scope) void {
        const count = value.inline_count; value.inline_count = 0;
        for (value.inline_values[0..count]) |owned| self.release(owned);
        const owned = value.values.items; value.values.items.len = 0;
        for (owned) |entry| self.release(entry);
        value.values.deinit(self.engine.gpa); value.values = .empty;
    }
    /// On success/history-only host error restore the previous capture without
    /// classifying its flags. On a real current event release history under the
    /// same reducer before publishing the winner once, after all root cleanup.
    pub fn finish(self: *Cleanup, failure: ?anyerror) !void {
        if (failure == error.OutOfMemory and !self.fatal) {
            // A trusted direct allocator failure cannot become catchable just
            // because ordinary cleanup threw. An already selected NEW fatal
            // wins without synthesizing another allocation event.
            const generation = self.engine.native_allocation_generation;
            _ = self.engine.throwNativeOutOfMemory(); self.collect(generation);
        }
        if (self.selected != null) {
            if (self.history) |history| { self.history = null; self.release(history); }
            const reason = self.selected.?; self.selected = null;
            _ = try self.engine.checked(c.JS_Throw(self.engine.context, reason));
            unreachable;
        }
        self.engine.captured_exception = self.history; self.history = null;
        if (failure) |err| return err;
    }
    pub fn restoreHistory(self: *Cleanup) void {
        @import("std").debug.assert(self.selected == null and self.engine.captured_exception == null and !c.JS_HasException(self.engine.context));
        self.engine.captured_exception = self.history; self.history = null;
    }
};
