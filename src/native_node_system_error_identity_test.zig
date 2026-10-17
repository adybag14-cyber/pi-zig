//! Prepared shared Source class/marker regression. Not build-selected or run.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
const Scope = @import("extensions/native_models_stream_scope.zig").Scope;
const shared = @import("extensions/native_node_system_errors.zig");
test "TTY init and filesystem retry errors share one actual SystemError class and marker" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"native-shared-system-errors"});
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const global = try s.own(c.JS_GetGlobalObject(engine.context));
    try @import("extensions/native_node_stream.zig").install(engine, try s.get(global, "process"));
    const fs_class = try s.own(try shared.constructor(engine, "ERR_SYSTEM_ERROR"));
    const tty_class = try s.own(try shared.constructor(engine, "ERR_TTY_INIT_FAILED"));
    try s.put(global, "FsSystemError", fs_class);
    try s.put(global, "TtyInitError", tty_class);
    const result = try engine.evalModule(
        "const parent=Object.getPrototypeOf(FsSystemError);if(parent!==Object.getPrototypeOf(TtyInitError)||parent.name!=='SystemError')throw Error('different shared SystemError parents');"
        ++ "const fs=new FsSystemError('write failed'),ctx={syscall:'uv_tty_init',code:'EBADF',message:'bad file descriptor',errno:-4083},tty=new TtyInitError(ctx);"
        ++ "if(fs.code!=='ERR_SYSTEM_ERROR'||tty.code!=='ERR_TTY_INIT_FAILED'||fs.info!=='write failed'||tty.info!==ctx||tty.message!=='TTY initialization failed: uv_tty_init returned EBADF (bad file descriptor)')throw Error('actual registered key/context message');"
        ++ "const marker=Object.getOwnPropertySymbols(fs).find(k=>k.description==='kIsNodeError');if(!marker||!Object.getOwnPropertySymbols(tty).includes(marker)||!tty[marker])throw Error('different private marker');"
        ++ "if(Object.getOwnPropertyDescriptor(tty,'info').writable||Object.getOwnPropertyDescriptor(tty,'name').enumerable||Object.getOwnPropertyDescriptor(tty,'message').enumerable)throw Error('source descriptors');tty.errno=7;if(ctx.errno!==7)throw Error('live context setter');"
        ++ "try{TtyInitError(ctx);throw Error('ordinary class call accepted')}catch(e){if(!(e instanceof TypeError)||!e.message.includes('NodeError'))throw e}"
        ++ "Object.defineProperty(globalThis,'Function',{configurable:true,get(){throw Error('late global Function')}});const again=new TtyInitError(ctx);if(Object.getPrototypeOf(again)!==TtyInitError.prototype)throw Error('late class rebuilt');"
        ++ "const reason={};Object.defineProperty(ctx,'code',{get(){throw reason}});try{new TtyInitError(ctx);throw Error('ctx throw accepted')}catch(e){if(e!==reason)throw e}export const proof=true;",
        "shared-system-error-source-identity.mjs",
    );
    engine.freeValue(result);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    try std.testing.expect(engine.captured_exception == null);
}
