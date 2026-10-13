//! Test-only owner-thread phase observations. Original promise deadlines are
//! untouched; every mark is synchronous and reads only this Engine's runtime.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
pub const Probe = struct {
    counters: em.ProgressProbe = .{},
    started_ms: i64 = 0,
    previous_ms: i64 = 0,
    previous: em.ProgressProbe = .{},
    marks: u64 = 0,

    pub fn install(self: *Probe, engine: *em.Engine) !void {
        self.started_ms = std.Io.Clock.awake.now(engine.native_io.?).toMilliseconds();
        self.previous_ms = self.started_ms;
        engine.progress_probe = &self.counters;
        errdefer engine.progress_probe = null;
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        const function = try engine.checked(c.JS_NewCFunction2(engine.context, mark, "nativeLatencyMark", 2, c.JS_CFUNC_generic, 0));
        if (c.JS_SetPropertyStr(engine.context, global, "nativeLatencyMark", function) < 0) return error.JavaScriptException;
    }
    pub fn detach(self: *Probe, engine: *em.Engine) void {
        self.record(engine, "test-return", -1);
        engine.progress_probe = null;
    }
    fn record(self: *Probe, engine: *em.Engine, phase: []const u8, case_index: i32) void {
        const now = std.Io.Clock.awake.now(engine.native_io.?).toMilliseconds();
        const current = self.counters;
        self.marks += 1;
        std.debug.print("NATIVE_PHASE case={d} phase={s} total_ms={d} phase_ms={d} entries={d} pumps={d} jobs={d} empty={d} wake_epoch={d} waits={d} wait_timeouts={d} pending={any}\n", .{
            case_index,                                               phase,                                                now - self.started_ms,                              now - self.previous_ms,
            current.context_entries -% self.previous.context_entries, current.control_pumps -% self.previous.control_pumps, current.job_attempts -% self.previous.job_attempts, current.empty_job_polls -% self.previous.empty_job_polls,
            engine.native_owner_signal.observe(),                     engine.native_owner_signal.waits,                     engine.native_owner_signal.timeouts,                c.JS_IsJobPending(engine.runtime),
        });
        self.previous = current;
        self.previous_ms = now;
    }
    fn mark(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
        const engine = em.Engine.fromContext(context.?);
        const counters = engine.progress_probe orelse return c.pi_js_undefined();
        const self: *Probe = @fieldParentPtr("counters", counters);
        var case_index: i32 = -1;
        if (argc > 1 and c.JS_ToInt32(context, &case_index, argv[1]) < 0) return c.JS_Throw(context, c.JS_GetException(context));
        if (argc > 0) {
            var length: usize = 0;
            const phase = c.JS_ToCStringLen2(context, &length, argv[0], false) orelse return c.JS_Throw(context, c.JS_GetException(context));
            defer c.JS_FreeCString(context, phase);
            self.record(engine, phase[0..length], case_index);
        }
        return c.pi_js_undefined();
    }
};
