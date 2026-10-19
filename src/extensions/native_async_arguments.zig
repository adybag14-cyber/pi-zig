//! Actual mutable formal slots in one opted-in native AsyncFunction invocation.
//! The C owner duplicates supplied arguments once and initializes missing
//! formals to undefined; this adapter never owns a second parameter array.
const em = @import("engine.zig");
const c = em.c;
const guest = @import("native_sdk_guest_operation.zig");
const owned = @import("native_sdk_owned_completion.zig");

pub const Arguments = struct {
    engine: *em.Engine,
    frame: *c.JSPiNativeAsyncArguments,
    /// Borrowed supplied slots for an actual prologue/rest producer. This is
    /// the current storage, not a saved copy of the original values. Mutable
    /// formal reads, including missing formals, must use get().
    supplied: []const c.JSValue,

    pub fn current(engine: *em.Engine, supplied: []const c.JSValue) !Arguments {
        var boundary: guest.Boundary = .{ .engine = engine }; try boundary.begin();
        const frame = c.JS_PiGetNativeAsyncArguments(engine.context);
        try boundary.finishStatus(if (frame == null) -1 else 0);
        return .{ .engine = engine, .frame = frame.?, .supplied = supplied };
    }
    /// Borrowed actual formal value. The index is below declared formal_count.
    pub fn get(self: *const Arguments, index: u16) c.JSValue {
        return c.JS_PiAsyncArgumentGet(self.frame, index);
    }
    /// Consume the incoming completion. The actual C slot is replaced before
    /// its prior value retires; a cleanup failure cannot undo that assignment.
    pub fn take(self: *Arguments, index: u16, incoming: anyerror!c.JSValue) !void {
        const value = try incoming;
        var boundary: guest.Boundary = .{ .engine = self.engine };
        boundary.begin() catch |err| return discard(self.engine, value, err);
        return boundary.finishStatus(c.JS_PiAsyncArgumentSet(self.engine.context, self.frame, index, value));
    }
    pub fn copy(self: *Arguments, index: u16, value: c.JSValue) !void {
        return self.take(index, c.JS_DupValue(self.engine.context, value));
    }
};

fn discard(engine: *em.Engine, value: c.JSValue, err: anyerror) !void {
    var completion = owned.Completion.initVoid(engine, err);
    completion.release(value);
    return completion.finishVoid();
}
