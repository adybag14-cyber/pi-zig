//! Source-only intake anchor. No runtime input or replacement Subject exists.
//! This actual-call compile/link target must never run/query its sentinel.
const std = @import("std");
fn Anchor(comptime function: anytype) type {
    const Args = std.meta.ArgsTuple(@TypeOf(function));
    const Return = @typeInfo(@TypeOf(function)).@"fn".return_type.?;
    const Payload = @typeInfo(Return).error_union.payload;
    return struct {
        fn entry(raw_args: *const anyopaque, raw_result: ?*anyopaque) callconv(.c) c_int {
            const args: *const Args = @ptrCast(@alignCast(raw_args));
            if (Payload == void) { @call(.never_inline, function, args.*) catch return 1; }
            else {
                const result: *Payload = @ptrCast(@alignCast(raw_result orelse return 2));
                result.* = @call(.never_inline, function, args.*) catch return 1;
            }
            return 0;
        }
    };
}
fn retain(comptime module: type, comptime names: anytype) void {
    inline for (names) |name| @export(&Anchor(@field(module, name)).entry, .{ .name = "sdk_exec_compile_only_" ++ name });
}
comptime {
    @setEvalBranchQuota(100_000);
    retain(@import("extensions/native_sdk_exec.zig"), .{"create"});
    retain(@import("native_sdk_exec_controls.zig"), .{
        "verifyActualAsyncMetadata", "startActualCaller", "verifyAcceptedOriginalRows",
        "verifyActualPendingBeforeExecEntry", "verifyActualExecutorFatalSurvivesPromiseConstruction",
    });
}
test "SDK exec compile-only sentinel MUST NEVER RUN" { return error.SourceOnlyCompileSentinelExecuted; }
