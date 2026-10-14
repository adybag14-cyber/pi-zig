//! Owner-thread wrapper around the actual VM for-in iterator.
//! The owned iterator traces the source object until deinit releases it.
const em = @import("engine.zig");
const c = em.c;
extern fn JS_PiForInStart(?*c.JSContext, c.JSValue) c.JSValue;
extern fn JS_PiForInNext(?*c.JSContext, c.JSValue, *c_int) c.JSValue;

pub const Iterator = struct {
    engine: *em.Engine,
    value: c.JSValue,
    finished: bool = false,
    native_steps: usize = 0,

    pub fn init(engine: *em.Engine, source: c.JSValue) !Iterator {
        return .{ .engine = engine, .value = try engine.checked(JS_PiForInStart(engine.context, source)) };
    }
    pub fn deinit(self: *Iterator) void {
        self.engine.freeValue(self.value);
    }
    pub fn next(self: *Iterator) !?c.JSValue {
        if (self.finished) return null;
        self.native_steps +|= 1;
        if (self.engine.cancelled.load(.acquire) or (self.native_steps % 256 == 0 and blk: {
            self.engine.interrupts +|= 1;
            break :blk self.engine.interrupts > self.engine.options.interrupt_budget;
        })) {
            _ = try self.engine.checked(c.JS_ThrowInternalError(self.engine.context, "interrupted"));
            unreachable;
        }
        var done: c_int = 1;
        const key = try self.engine.checked(JS_PiForInNext(self.engine.context, self.value, &done));
        if (done != 0) {
            self.finished = true;
            self.engine.freeValue(key);
            return null;
        }
        return key;
    }
};
