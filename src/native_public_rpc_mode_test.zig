//! Complete actual c268 runRpcMode activation, commands and extension UI.
//! Source imports are replaced only at their six literal import declarations;
//! genuine same-realm platform, child, guard, shell, Theme and crypto owners
//! supply their inputs. Authored controls are not execution receipts.
const std = @import("std");
const v = @import("extensions/native_public_values.zig");
const c = v.c;
const support = @import("native_public_rpc_mode_test_support.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
fn record(engine: *v.em.Engine) !c.JSValue {
    var s: v.Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, recordBody(&s));
}
fn recordBody(s: *v.Scope) !c.JSValue {
    return v.duplicate(s, try v.get(s, try v.global(s, "rpcHooks"), "record"));
}
test "Public RPC actual genuine AF shape and completed original owner graph" {
    var fixture: support.Fixture = undefined;
    try fixture.init(true); defer fixture.deinit();
    try support.run(fixture.engine,
        \\for(const api of[sourceRpc,nativeRpc]){
        \\ const fn=api.runRpcMode;
        \\ if(fn.name!=="runRpcMode"||fn.length!==1||Object.hasOwn(fn,"prototype")||Object.prototype.toString.call(fn)!=="[object AsyncFunction]")throw Error("actual runRpcMode shape");
        \\ if(Object.keys(api).join()!=="runRpcMode")throw Error("actual RPC export set");
        \\}
        \\if(typeof actualRpcShell.killTrackedDetachedChildren!=="function"||actualRpcShell.killTrackedDetachedChildren.length!==0)throw Error("actual shell owner");
        \\if(typeof actualRpcJsonl.attachJsonlLineReader!=="function"||typeof actualRpcJson.toJsonEvent!=="function")throw Error("actual protocol owners");
    );
    var s: v.Scope = .{ .engine = fixture.engine }; defer s.deinit();
    const output = try @import("extensions/native_sdk_output_guard.zig").create(fixture.engine, try v.global(&s, "process"), fixture.frontend.lease.?);
    defer output.deinit(fixture.engine);
    const repeated = try v.own(&s, try support.public_rpc.create(fixture.engine, .{
        .output = output, .shell = try v.global(&s, "actualRpcShell"), .theme = try v.global(&s, "actualRpcTheme"),
    }));
    try std.testing.expect(v.equal(&s, repeated, try v.global(&s, "nativeRpc")));
}
test "Public RPC actual queue thinking compaction retry and abort command paths" {
    try support.both("await observeRpcCoreCommands();");
}
test "Public RPC actual state model selection cycles and missing model diagnostic" {
    try support.both("await observeRpcStateAndModels();");
}
test "Public RPC actual session transitions cancellation clone and rebind Await" {
    try support.both("await observeRpcSessions();");
}
test "Public RPC actual entries tree messages names and three command lists" {
    try support.both("await observeRpcEntriesAndCommands();");
}
test "Public RPC actual extension Bash interception and native session execution arguments" {
    try support.both("await observeRpcBash();");
}
test "Public RPC actual prompt preflight escaped callbacks and rejection response ownership" {
    try support.both("await observeRpcPrompt();");
}
test "Public RPC actual command context actions events and live subscription rebinding" {
    try support.both("await observeRpcActionsAndEvents();");
}
test "Public RPC actual select confirm input editor and real UUID pending replies" {
    try support.both("await observeRpcDialogs();");
}
test "Public RPC actual complete UI method shapes wire fields and original Theme proxy" {
    try support.both("await observeRpcUiShapes();");
}
test "Public RPC actual live timeout reads abort cleanup and pre-aborted defaults" {
    try support.both("await observeRpcUiAbortTimeout();");
}
test "Public RPC actual pending request publication precedes output failure" {
    try support.both("await observeRpcPendingPublication();");
}
test "Public RPC actual parse and command catches preserve ordinary reason semantics" {
    try support.both("await observeRpcParseAndCommandFailures();");
}
test "Public RPC actual escaped rebind callback preserves TDZ then initialized binding" {
    try support.both("await observeRpcTdz();");
}
test "Public RPC actual EOF and signal shutdown dispose detach pause and conditional flush" {
    inline for (.{ false, true }) |native| {
        inline for (.{ "EOF", "SIGTERM" }) |signal| {
            var fixture: support.Fixture = undefined;
            try fixture.init(native); defer fixture.deinit();
            try support.run(fixture.engine, "await observeRpcShutdown('" ++ signal ++ "');");
        }
    }
}
test "Public RPC actual requested shutdown follows command response" {
    try support.both("await observeRpcShutdownRequest();");
}
test "Public RPC actual agent backpressure follows the same real output queue tail" {
    try support.both("await observeRpcBackpressure();");
}
test "Public RPC actual intrinsic outer Promise adopts the final live pending Promise" {
    try support.both("await observeRpcIntrinsicAdoption();");
}
test "Public RPC actual session assignment and bind callee retirement precede later getters" {
    try support.both("await observeRpcRebindRetirement();");
}
test "Public RPC actual state and tree receivers obey Source expression retirement" {
    try support.both("await observeRpcCommandRetirement();");
}
test "Public RPC actual command list heads survive done and later iterable getters" {
    try support.both("await observeRpcCommandHeads();");
}
test "Public RPC actual command IteratorClose distinguishes body and next failures" {
    inline for (.{ false, true }) |native| {
        inline for (.{ "true", "false" }) |next_throws| {
            var fixture: support.Fixture = undefined;
            try fixture.init(native); defer fixture.deinit();
            try support.run(fixture.engine, "await observeRpcCommandClose(" ++ next_throws ++ ");");
        }
    }
}
test "Public RPC actual parse callee and template operand retire before output" {
    try support.both("await observeRpcParseRetirement();");
}
test "Public RPC actual same-operation private DATA stays ordinary in commands and dialogs" {
    try support.both("await observeRpcPrivateData(\"command\");");
    try support.both("await observeRpcPrivateData(\"dialog\");");
}
test "Public RPC actual initial setup rejection precedes subscriptions without invented cleanup" {
    try support.both("await observeRpcSetupFailure();");
}
test "Public RPC actual current native B bypasses setup rejection and guest catch" {
    var fixture: support.Fixture = undefined;
    try fixture.init(true); defer fixture.deinit();
    const observed = try record(fixture.engine); defer fixture.engine.freeValue(observed);
    try std.testing.expectError(error.JavaScriptException, support.run(fixture.engine, "await observeRpcCurrentFatal();"));
    try retirement.verifyRecordedActualNativeFatal(fixture.engine, observed);
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), fixture.engine.native_exception_diagnostics_suppressed);
}
test "Public RPC actual cancellation on command head replacement prevents next guest work" {
    var fixture: support.Fixture = undefined;
    try fixture.init(true); defer fixture.deinit();
    const observed = try record(fixture.engine); defer fixture.engine.freeValue(observed);
    try std.testing.expectError(error.JavaScriptException, support.run(fixture.engine, "await observeRpcCancellation();"));
    try retirement.verifyActualCancellationNoGuestClose(fixture.engine, observed);
}
