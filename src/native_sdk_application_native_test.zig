//! Real available platform/AI execution plus strict existing session gates.
//! Complete factory execution still requires the real owner's Completed graph.
const std = @import("std");
const builtin = @import("builtin");
const em = @import("extensions/engine.zig");
const c = em.c;
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const bootstrap = @import("extensions/native_sdk_application_bootstrap.zig");
const production = @import("native_sdk_session_production_test.zig");

fn eval(engine: *em.Engine, source: []const u8) !void {
    const result = try engine.evalModule(source, "actual-sdk-application-probe.mjs");
    engine.freeValue(result);
}
fn expose(s: *Scope, name: [*:0]const u8, value: c.JSValue) !void {
    try s.put(try s.own(c.JS_GetGlobalObject(s.engine.context)), name, value);
}

test "SDK actual application platform executes real file IO path URL timers and process" {
    const gpa = std.testing.allocator;
    var temporary = std.testing.tmpDir(.{}); defer temporary.cleanup();
    var environment: std.process.Environ.Map = .init(gpa); defer environment.deinit();
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit();
    try bootstrap.installPlatform(engine, std.testing.io, &environment, &.{"actual-sdk-application-test"});
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try temporary.dir.realPath(std.testing.io, &path_buffer);
    try expose(&s, "actualSdkRoot", try s.text(path_buffer[0..length]));
    try eval(engine,
        \\import fs from 'node:fs';import fsp from 'node:fs/promises';import path from 'node:path';import{pathToFileURL,fileURLToPath}from'node:url';import{setTimeout as delay}from'timers/promises';
        \\const filename=path.join(actualSdkRoot,'sdk-actual-owned.txt');fs.writeFileSync(filename,'owned:\u0000λ','utf8');const before=fs.readFileSync(filename,'utf8');if(before!=='owned:\u0000λ')throw Error('actual sync filesystem');const after=await fsp.readFile(filename,'utf8');if(after!==before)throw Error('actual promise filesystem');if(fileURLToPath(pathToFileURL(filename))!==filename)throw Error('actual URL/path');if(await delay(0,'actual-timer')!=='actual-timer')throw Error('actual timer');if(typeof process.versions.zig!=='string'||typeof process.cwd()!=='string')throw Error('actual native process');fs.unlinkSync(filename);
    );
}

test "SDK actual application canonical AI graph survives real GC with exact imported bindings" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit();
    try bootstrap.installPlatform(engine, std.testing.io, &environment, &.{"actual-sdk-ai-identity"});
    try @import("native_sdk_application_assembly_test.zig").verifyActualAiIdentity(engine);
}

test "SDK actual application managers are original manager constructors and real own session tree" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit();
    try bootstrap.installPlatform(engine, std.testing.io, &environment, &.{"actual-sdk-managers"});
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const first = try s.own(try @import("extensions/native_sdk.zig").managerImports(engine));
    const second = try s.own(try @import("extensions/native_sdk.zig").managerImports(engine));
    try std.testing.expect(s.equal(first, second));
    c.JS_RunGC(engine.runtime);
    try expose(&s, "actualSdkManagers", first);
    try eval(engine,
        \\const{SessionManager,SettingsManager}=actualSdkManagers;if('AgentSession'in actualSdkManagers||'ModelRuntime'in actualSdkManagers||'DefaultResourceLoader'in actualSdkManagers)throw Error('legacy defaults selected');const manager=SessionManager.inMemory(process.cwd());const a=manager.appendCustomEntry('a',{n:1});manager.appendCustomEntry('b',{n:2});manager.branch(a);const c=manager.appendCustomEntry('c',{n:3});if(manager.getEntryCount()!==3||manager.getBranch().map(e=>e.id).join()!==[a,c].join()||manager.getChildren(a).length!==2)throw Error('actual manager tree');const settings=SettingsManager.inMemory({retry:{enabled:true,maxRetries:5}});settings.applyOverrides({retry:{baseDelayMs:10}});if(settings.getRetrySettings().maxRetries!==5||settings.getRetrySettings().baseDelayMs!==10)throw Error('actual settings merge');await settings.flush();if(settings.drainErrors().length!==0)throw Error('actual settings flush');
    );
}

test "SDK actual application os uses native account fallback and genuine cached OS release" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit();
    try bootstrap.installPlatform(engine, std.testing.io, &environment, &.{"actual-sdk-os"});
    try eval(engine,
        \\import os from'node:os';import path from'node:path';const home=os.homedir();if(typeof home!=='string'||!path.isAbsolute(home))throw Error('native account fallback');const release=os.release();if(typeof release!=='string'||release.length===0||String(os.release)!==release)throw Error('actual cached release');if(os.arch()!==process.arch||os.platform()!==process.platform)throw Error('live process OS bindings');
    );
}

test "SDK actual application os preserves platform empty home and exact system error fields" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    try environment.put(if (builtin.os.tag == .windows) "USERPROFILE" else "HOME", "");
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit();
    try bootstrap.installPlatform(engine, std.testing.io, &environment, &.{"actual-sdk-os-empty"});
    try eval(engine, if (builtin.os.tag == .windows)
        \\import os from'node:os';let caught;try{os.homedir()}catch(e){caught=e}if(!(caught instanceof Error)||caught.code!=='ERR_SYSTEM_ERROR'||caught.info.code!=='ENOENT'||caught.errno!==-4058||caught.syscall!=='uv_os_homedir'||caught.info.syscall!==caught.syscall)throw Error('actual empty Windows home error');
    else
        \\import os from'node:os';if(os.homedir()!=='')throw Error('POSIX empty HOME must survive');
    );
}

test "SDK actual application os error context keeps exact inherited setter reason" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    try environment.put("USERPROFILE", "");
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit();
    try bootstrap.installPlatform(engine, std.testing.io, &environment, &.{"actual-sdk-os-context"});
    try eval(engine,
        \\import os from'node:os';const reason={identity:'native-context-setter'};let entered=0;Object.defineProperty(Object.prototype,'errno',{configurable:true,set(value){entered++;if(value!==-4058)throw Error('wrong native errno');throw reason}});let caught;try{os.homedir()}catch(error){caught=error}if(caught!==reason||entered!==1)throw Error('native context lost setter reason');delete Object.prototype.errno;
    );
}

test "SDK actual application direct SystemError context getter stays raw before host catch" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try bootstrap.installPlatform(engine, std.testing.io, &environment, &.{"actual-sdk-direct-system-context"});
    try eval(engine,
        \\globalThis.contextDiagnosticReads=0;globalThis.contextRawReason={toString(){contextDiagnosticReads++;return'forbidden diagnostic'}};globalThis.actualErrorContext={code:'EIO',syscall:'owned-context',get message(){throw contextRawReason}};
    );
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const root = try s.own(c.JS_GetGlobalObject(engine.context));
    const context = try s.get(root, "actualErrorContext");
    const reason = try s.get(root, "contextRawReason");
    const produced = @import("extensions/native_node_fs_system_error.zig").fromContext(engine, context) catch |err| {
        try std.testing.expect(err == error.JavaScriptException);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.captured_exception orelse return error.MissingActualContextReason));
        const reads = try s.get(root, "contextDiagnosticReads");
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, reads, c.JS_NewInt32(engine.context, 0)));
        try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
        return;
    };
    engine.freeValue(produced);
    return error.RequiredActualContextGetterFailure;
}

/// Strict full-gate entrypoint. It constructs the genuine application over the
/// real completed inputs, then invokes existing unmodified Source27/Source166
/// comparators. No missing dependency is replaced, skipped or considered pass.
pub fn verifyFullApplication(engine: *em.Engine, completed: bootstrap.Completed) !void {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const graph = try s.own(try bootstrap.create(engine, completed));
    const api = try s.get(graph, "exports");
    var temporary = std.testing.tmpDir(.{}); defer temporary.cleanup();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try temporary.dir.realPath(std.testing.io, &path_buffer);
    const caller = try s.own(try @import("extensions/native_js_values.zig").spread(engine, api));
    try s.put(caller, "fixtureCwd", try s.text(path_buffer[0..length]));
    try @import("native_sdk_factory_production_test.zig").compareActualSourceCases(engine, caller, @embedFile("extensions/fixtures/sdk-factory-production-4954.json"));
    try production.verifyActualPrototype(engine, try s.get(api, "AgentSession"));
}

/// The owner supplies an actual accepted builtin Node capture; expected data is
/// never authored natively. Execute the exact genuine caller without stdout.
pub fn compareActualOsSource(engine: *em.Engine, reference: []const u8) !void {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    try eval(engine, @embedFile("extensions/fixtures/node-os-consumed-24_14.input.mjs"));
    const root = try s.own(c.JS_GetGlobalObject(engine.context));
    const actual = try engine.stringify(try s.get(root, "nativeOsConsumedRows")); defer engine.gpa.free(actual);
    const expected = try s.own(try engine.checked(c.JS_ParseJSON(engine.context, reference.ptr, reference.len, "actual-node-os-reference.json")));
    const normalized = try engine.stringify(expected); defer engine.gpa.free(normalized);
    try std.testing.expectEqualStrings(normalized, actual);
}

// The historical Original64 private-registry target stays separate: its setup
// supplies model/resource collaborators, so importing it here would not prove
// the genuine completed application. Its inputs/references remain untouched.

// Retain the genuine full graph comparison body for typecheck/link even while
// its completed loader/jiti/platform owner is still unavailable for execution.
// No replacement inputs are constructed or passed by this compile anchor.
fn fullApplicationAnchor(raw_engine: *anyopaque, raw_completed: *const anyopaque) callconv(.c) c_int {
    const engine: *em.Engine = @ptrCast(@alignCast(raw_engine));
    const completed: *const bootstrap.Completed = @ptrCast(@alignCast(raw_completed));
    @call(.never_inline, verifyFullApplication, .{ engine, completed.* }) catch return 1;
    return 0;
}
comptime { @export(&fullApplicationAnchor, .{ .name = "sdk_actual_application_full_factory27_source166_body" }); }
