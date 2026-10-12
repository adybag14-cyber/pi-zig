const std = @import("std");
const js = @import("extensions/native_js_values.zig");
const c = js.c;
const fatal = @import("extensions/native_application_fatal.zig");
const stacks = @import("extensions/native_error_stack.zig");
const lease: fatal.protocol.Lease = .{ .owner_generation = 31, .secret = .{0x7a} ** 32 };
fn script(engine: *js.Engine, source: []const u8) !void {
    engine.freeValue(try engine.eval(source, "application-fatal-caller.js", c.JS_EVAL_TYPE_GLOBAL));
}
const Fixture = struct {
    engine: *js.Engine,
    stack_owner: c.JSValue,
    manager: *fatal.Manager,
    fn init() !Fixture {
        const engine = try js.Engine.init(std.testing.allocator, .{});
        errdefer engine.deinit();
        const owner = try stacks.install(engine);
        errdefer {
            stacks.uninstall(engine);
            engine.freeValue(owner);
        }
        var env: std.process.Environ.Map = .init(std.testing.allocator);
        defer env.deinit();
        try @import("extensions/native_process.zig").install(engine, std.testing.io, &env, &.{"owned-application"});
        return .{ .engine = engine, .stack_owner = owner, .manager = try fatal.Manager.init(engine) };
    }
    fn deinit(self: Fixture) void {
        self.manager.deinit();
        stacks.uninstall(self.engine);
        self.engine.freeValue(self.stack_owner);
        self.engine.deinit();
    }
    fn reject(self: Fixture, source: []const u8) !void {
        try script(self.engine, source);
        _ = try self.engine.drainReadyJobs();
        try std.testing.expect(try self.manager.checkpoint());
    }
    fn release(self: Fixture) !void {
        const plan = self.manager.pending.?.plan;
        try self.manager.release(.{ .lease = lease, .sequence = 1, .release = switch (plan) {
            .uncaught_crash, .handler_failure => .restored,
            .emergency_terminal_exit => .terminal_dead,
            .already_shutting_down => .already_released,
        } });
    }
};

test "native application fatal original reason remains unread until terminal restoration acknowledgement" {
    const f = try Fixture.init();
    defer f.deinit();
    try f.reject("globalThis.events=[];globalThis.restored=false;globalThis.original=Error('autocomplete-original-rejection');Object.defineProperty(original,'stack',{get(){events.push('stack:'+restored);return 'Error: autocomplete-original-rejection\\n    at genuine (caller.js:2:9)'}});process.on('uncaughtExceptionMonitor',(e,o)=>events.push('monitor:'+(e===original)+':'+o));process.on('uncaughtException',()=>events.push('late'));process.on('exit',c=>events.push('exit:'+c));Promise.reject(original);");
    try std.testing.expectEqual(fatal.protocol.Plan.uncaught_crash, f.manager.pending.?.plan);
    const original = try js.global(f.engine, "original");
    defer f.engine.freeValue(original);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, original, f.manager.pending.?.reason));
    try std.testing.expectError(error.NativeTerminalReleasePending, f.manager.diagnostic(lease));
    try script(f.engine, "if(JSON.stringify(events)!=='[\"monitor:true:unhandledRejection\"]')throw Error(JSON.stringify(events));restored=true;");
    try f.release();
    var diagnostic = (try f.manager.diagnostic(lease)).?;
    defer diagnostic.deinit();
    try std.testing.expectEqual(@as(u8, 1), diagnostic.exit_code);
    try std.testing.expectEqualStrings("pi exiting due to uncaughtException:\nError: autocomplete-original-rejection\n    at genuine (caller.js:2:9)\n", diagnostic.bytes);
    try script(f.engine, "if(JSON.stringify(events)!=='[\"monitor:true:unhandledRejection\",\"stack:true\",\"exit:1\"]')throw Error(JSON.stringify(events));");
}
test "native application fatal Source four dead-terminal codes skip all diagnostic getters and exit129" {
    inline for (.{ "EIO", "EPIPE", "ENOTCONN", "ENOTTY" }) |code| {
        const f = try Fixture.init();
        defer f.deinit();
        try f.reject("globalThis.events=[];globalThis.original=Error('dead');original.code='" ++ code ++ "';Object.defineProperty(original,'stack',{get(){throw Error('must not inspect dead terminal')}});process.on('exit',c=>events.push(c));Promise.reject(original);");
        try std.testing.expectEqual(fatal.protocol.Plan.emergency_terminal_exit, f.manager.pending.?.plan);
        try f.release();
        try std.testing.expect((try f.manager.diagnostic(lease)) == null);
        try script(f.engine, "if(JSON.stringify(events)!=='[129]')throw Error(JSON.stringify(events));");
    }
}
test "native application fatal Source code getter failure exits7 without application reporting or exit listener" {
    const f = try Fixture.init();
    defer f.deinit();
    try f.reject("globalThis.events=[];globalThis.getterError=Error('code-getter-original');globalThis.original=Error('rejected');Object.defineProperty(original,'code',{get(){events.push('code');throw getterError}});process.on('exit',()=>events.push('exit'));Promise.reject(original);");
    try std.testing.expectEqual(fatal.protocol.Plan.handler_failure, f.manager.pending.?.plan);
    const original = try js.global(f.engine, "getterError");
    defer f.engine.freeValue(original);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, original, f.manager.pending.?.reason));
    try f.release();
    var diagnostic = (try f.manager.diagnostic(lease)).?;
    defer diagnostic.deinit();
    try std.testing.expectEqual(@as(u8, 7), diagnostic.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.bytes, "code-getter-original") != null);
    try script(f.engine, "if(JSON.stringify(events)!=='[\"code\"]')throw Error(JSON.stringify(events));");
}
test "native application fatal Source already-shutting branch performs no duplicate inspection" {
    const f = try Fixture.init();
    defer f.deinit();
    f.manager.is_shutting_down = true;
    try f.reject("globalThis.events=[];globalThis.original=Error('already');Object.defineProperty(original,'stack',{get(){throw Error('duplicate diagnostic')}});process.on('exit',c=>events.push(c));Promise.reject(original);");
    try std.testing.expectEqual(fatal.protocol.Plan.already_shutting_down, f.manager.pending.?.plan);
    try f.release();
    try std.testing.expect((try f.manager.diagnostic(lease)) == null);
    try script(f.engine, "if(JSON.stringify(events)!=='[1]')throw Error(JSON.stringify(events));");
}
test "native application fatal Source inspect ignores throwing stack getter after restoration" {
    const f = try Fixture.init();
    defer f.deinit();
    try f.reject("globalThis.restored=false;globalThis.reads=0;globalThis.original=Error('fallback-original');Object.defineProperty(original,'stack',{get(){if(!restored)throw Error('early');reads++;throw Error('ignored-stack-getter')}});Promise.reject(original);");
    try script(f.engine, "if(reads!==0)throw Error('early reads');restored=true;");
    try f.release();
    var diagnostic = (try f.manager.diagnostic(lease)).?;
    defer diagnostic.deinit();
    try std.testing.expectEqualStrings("pi exiting due to uncaughtException:\nError: fallback-original\n", diagnostic.bytes);
    try script(f.engine, "if(reads!==1)throw Error('getter count');");
}
test "native application fatal actual host await consumes rejection while discarded async promise remains fatal" {
    const f = try Fixture.init();
    defer f.deinit();
    const consumed = try f.engine.eval("Promise.reject(Error('consumed'))", "consumed.js", c.JS_EVAL_TYPE_GLOBAL);
    defer f.engine.freeValue(consumed);
    try std.testing.expectError(error.JavaScriptException, f.engine.awaitValue(consumed));
    try std.testing.expect(!try f.manager.checkpoint());
    try f.reject("void (async()=>{throw Error('discarded-original')})();");
    try f.release();
    var diagnostic = (try f.manager.diagnostic(lease)).?;
    defer diagnostic.deinit();
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.bytes, "discarded-original") != null);
}

test "native application fatal Source EPERM is ordinary and code values are never coerced" {
    inline for (.{ "'EPERM'", "({toString(){throw Error('must not coerce code')}})" }) |code| {
        const f = try Fixture.init();
        defer f.deinit();
        try f.reject("globalThis.original=Error('ordinary-code-original');original.code=" ++ code ++ ";Promise.reject(original);");
        try std.testing.expectEqual(fatal.protocol.Plan.uncaught_crash, f.manager.pending.?.plan);
        try f.release();
        var diagnostic = (try f.manager.diagnostic(lease)).?;
        defer diagnostic.deinit();
        try std.testing.expectEqual(@as(u8, 1), diagnostic.exit_code);
        try std.testing.expect(std.mem.indexOf(u8, diagnostic.bytes, "ordinary-code-original") != null);
    }
}

test "native application fatal real group teardown releases editor widget and dialog roots without guest disposal or replacement provider calls" {
    const f = try Fixture.init();
    defer f.deinit();
    const group = try @import("extensions/native_group.zig").Group.init(f.engine);
    var group_live = true;
    defer if (group_live) group.deinit();
    _ = try group.add("first-owned-input.mjs");
    _ = try group.add("second-owned-input.mjs");
    try script(f.engine,
        \\globalThis.events=[];
        \\globalThis.editorFactory=()=>({getText(){events.push('getText');return 'draft'},setText(){},render(){return ['draft']},handleInput(){},setAutocompleteProvider(){},get dispose(){events.push('editor-dispose-get');return ()=>events.push('editor-dispose')}});
        \\globalThis.widgetFactory=()=>({render(){return ['widget']},get dispose(){events.push('widget-dispose-get');return ()=>events.push('widget-dispose')}});
        \\globalThis.dialogFactory=()=>({render(){return ['dialog']},get dispose(){events.push('dialog-dispose-get');return ()=>events.push('dialog-dispose')}});
        \\globalThis.providerFactory=current=>{events.push('provider-factory');return current};
    );
    const editor = try js.global(f.engine, "editorFactory");
    defer f.engine.freeValue(editor);
    try group.ui.editors.setFactory(1, editor, c.pi_js_undefined(), group.ui.theme, group.ui.keybindings, 80, 24);
    const provider = try js.global(f.engine, "providerFactory");
    defer f.engine.freeValue(provider);
    try group.ui.editors.addAutocompleteProvider(2, provider);
    const widget = try js.global(f.engine, "widgetFactory");
    defer f.engine.freeValue(widget);
    try group.ui.widgets.set(1, "owned-widget", widget, .aboveEditor, group.ui.theme);
    const dialog = try js.global(f.engine, "dialogFactory");
    defer f.engine.freeValue(dialog);
    const opened = try group.ui.components.open(dialog, group.ui.theme, group.ui.keybindings);
    defer f.engine.freeValue(opened.result);
    try script(f.engine, "events.length=0;globalThis.original=Error('owned-group-original');Promise.reject(original);");
    _ = try f.engine.drainReadyJobs();
    try std.testing.expect(try f.manager.checkpoint());
    const original = try js.global(f.engine, "original");
    defer f.engine.freeValue(original);
    f.engine.native_fatal_teardown = true;
    group.deinit();
    group_live = false;
    c.JS_RunGC(f.engine.runtime);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, original, f.manager.pending.?.reason));
    try script(f.engine, "if(events.length!==0)throw Error(JSON.stringify(events));");
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(f.engine.context, opened.result));
    try f.release();
    var diagnostic = (try f.manager.diagnostic(lease)).?;
    defer diagnostic.deinit();
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.bytes, "owned-group-original") != null);
}

comptime {
    _ = @import("extensions/js_runtime.zig");
}
