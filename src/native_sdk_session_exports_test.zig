//! Ordinary Source methods composed with actual native collaborators.
//! Fixtures are derived from the retained genuine 5ab Source capture.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const js = @import("extensions/native_js_values.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;
fn utility(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const first = if (argc > 0) argv[0] else c.pi_js_undefined();
    return (switch (magic) {
        0 => @import("extensions/native_sdk_session_export_jsonl.zig").serialize(engine, first, if (argc > 1) argv[1] else c.pi_js_undefined()),
        1 => @import("extensions/native_export_ansi_html.zig").ansiToHtml(engine, first),
        2 => @import("extensions/native_export_ansi_html.zig").ansiLinesToHtml(engine, first),
        3 => themeByName(engine, first),
        4 => hashUtf8(engine, first),
        5 => @import("extensions/native_bash_executor.zig").truncateTail(engine, first),
        6 => statSnapshot(engine, first),
        else => unreachable,
    }) catch |err| sdk.fail(engine, err);
}
fn statSnapshot(engine: *em.Engine, value: c.JSValue) !c.JSValue {
    const path = try engine.toString(value);
    defer engine.gpa.free(path);
    const file = try std.Io.Dir.cwd().openFile(engine.native_io orelse return error.NativeIoUnavailable, path, .{});
    defer file.close(engine.native_io.?);
    const stat = try file.stat(engine.native_io.?);
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try sdk.put(engine, result, "size", c.JS_NewInt64(engine.context, @intCast(stat.size)));
    return result;
}
fn themeByName(engine: *em.Engine, value: c.JSValue) !c.JSValue {
    const name = try engine.toString(value);
    defer engine.gpa.free(name);
    return @import("extensions/native_theme.zig").getThemeByName(engine, name);
}
fn hashUtf8(engine: *em.Engine, value: c.JSValue) !c.JSValue {
    const text = try engine.toString(value);
    defer engine.gpa.free(text);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(text, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    return sdk.text(engine, &hex);
}
pub fn setup(engine: *em.Engine, environment: *std.process.Environ.Map) !void {
    engine.native_io = std.testing.io;
    try @import("extensions/native_process.zig").install(engine, std.testing.io, environment, &.{"ordinary-session-exports5ab-native"});
    try @import("extensions/abort_signal.zig").install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/text_encoding.zig").install(engine);
    if (engine.text_decoder_class == 0) try @import("extensions/text_decoder.zig").install(engine);
    try @import("extensions/node_buffer.zig").install(engine);
    try @import("extensions/node_fs.zig").install(engine, std.testing.io);
    try @import("extensions/node_path.zig").install(engine, std.testing.io);
    try @import("extensions/native_crypto_random.zig").install(engine);
    try @import("extensions/native_stream.zig").install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const api = try scope.object();
    try sdk.install(engine, api);
    try @import("extensions/native_agent_complete.zig").install(engine, api);
    try @import("extensions/native_auth_storage.zig").install(engine, api);
    try @import("extensions/native_auth_memory.zig").install(engine, try scope.get(api, "AuthStorage"));
    const prototype = try scope.object();
    inline for (.{
        @import("extensions/native_sdk_session_public_values.zig"),
        @import("extensions/native_sdk_session_events.zig"),
        @import("extensions/native_sdk_session_control.zig"),
    }) |module| try module.install(engine, prototype);
    try @import("extensions/native_sdk_session_compaction.zig").installHelpers(engine, prototype);
    const executor = try scope.own(try @import("extensions/native_bash_executor.zig").create(engine));
    const local = try scope.own(try @import("extensions/native_bash_local_operations.zig").create(engine));
    try scope.put(api, "executeBashWithOperations", executor);
    try scope.put(api, "createLocalBashOperations", local);
    try @import("extensions/native_sdk_session_bash.zig").install(engine, prototype, executor, local);
    try @import("extensions/native_sdk_session_exports.zig").installJsonl(engine, prototype);
    try @import("extensions/native_sdk_session_exports.zig").installHtml(engine, prototype);
    const compat = try scope.own(try @import("extensions/native_ai_compat.zig").create(engine, .{ .builtin_apis = &.{}, .compat_models = c.pi_js_undefined(), .get_env_api_key = c.pi_js_undefined() }));
    const complete = try scope.own(try @import("extensions/native_sdk_complete_summarization.zig").create(engine, try scope.own(try @import("extensions/native_ai_uuid.zig").create(engine)), try scope.get(compat, "completeSimple"), try scope.own(try @import("extensions/native_ai_retry_call.zig").create(engine))));
    const summary = try scope.own(try @import("extensions/native_sdk_bug_report_summary.zig").create(engine, complete));
    try @import("extensions/native_sdk_session_exports.zig").installSummary(engine, prototype, summary);
    const dependencies = try scope.object();
    try @import("extensions/native_sdk_chat_transport.zig").install(engine, dependencies);
    try scope.put(dependencies, "convertToLlm", try scope.own(try @import("extensions/native_sdk_messages.zig").create(engine)));
    try @import("extensions/native_sdk_session_request_auth.zig").install(engine, prototype, dependencies);
    try scope.put(api, "AgentSession", try scope.own(try @import("extensions/native_sdk_session_construct.zig").constructor(engine, prototype)));
    inline for (.{ "serializeSessionBranch", "ansiToHtml", "ansiLinesToHtml", "getThemeByName", "hashUtf8", "truncateTail", "statSnapshot" }, 0..) |name, i| try scope.put(api, name, try scope.own(try engine.checked(c.pi_js_function_magic(engine.context, utility, name, 1, @intCast(i)))));
    try scope.put(api, "createToolHtmlRenderer", try scope.own(try @import("extensions/native_export_tool_html.zig").createFactory(engine)));
    try @import("extensions/native_tui.zig").install(engine);
    try scope.put(api, "Text", try scope.get(engine.native_module_values.get("pi-tui").?, "Text"));
    try scope.put(api, "fs", engine.native_module_values.get("node:fs").?);
    try scope.put(api, "path", engine.native_module_values.get("node:path").?);
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "ordinaryAPI", api);
}
test "native ordinary session exports compare Source20 ANSI282 full HTML and real collaborators" {
    try runFixture(@embedFile("extensions/fixtures/sdk-session-exports5ab.input.txt"), @embedFile("extensions/fixtures/sdk-session-exports5ab-source.json"), "ordinaryRows", "observations", 20);
}
test "native ordinary session exports compare Source22 tail spill UTF8 and actual local Bash" {
    try runFixture(@embedFile("extensions/fixtures/sdk-session-exports5ab-more.input.txt"), @embedFile("extensions/fixtures/sdk-session-exports5ab-more-source.json"), "ordinaryMoreRows", "rows", 22);
}
fn runFixture(comptime input: []const u8, source: []const u8, comptime actual_name: []const u8, comptime expected_name: []const u8, comptime count: usize) !void {
    const io = std.testing.io;
    const original_dir = try std.Io.Dir.cwd().realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(original_dir);
    defer std.process.setCurrentPath(io, original_dir) catch {};
    var nonce: [8]u8 = undefined;
    try std.Io.randomSecure(io, &nonce);
    const root = try std.fmt.allocPrint(std.testing.allocator, "C:/Users/adyba/pi-zig-update-evidence-20261003/ordinary-session-exports5ab-native-state-{s}", .{std.fmt.bytesToHex(nonce, .lower)});
    defer std.testing.allocator.free(root);
    try std.Io.Dir.cwd().createDirPath(io, root);
    try std.process.setCurrentPath(io, root);
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment = try @import("extensions/native_env_node_path.zig").environment(std.testing.allocator);
    defer environment.deinit();
    const agent_directory = try std.fs.path.join(std.testing.allocator, &.{ root, "agent" });
    defer std.testing.allocator.free(agent_directory);
    try environment.put("PI_CODING_AGENT_DIR", agent_directory);
    try environment.put("PI_OFFLINE", "1");
    try setup(engine, &environment);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "ordinaryRoot", try scope.text(root));
    const expected = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "sdk-session-exports5ab-source.json")));
    try scope.put(global, "ordinarySource", expected);
    // Replay the actual Source-produced persistent session as export input.
    // Its random IDs are input data, not an expected-output normalization.
    try scope.put(global, "ordinarySourceSessionBytes", try scope.text(@embedFile("extensions/fixtures/sdk-session-exports5ab-source-session.input.txt")));
    const evaluated = engine.evalModule(input ++
        // Root is an independently created evidence directory. Normalize only
        // its literal and JSON-escaped spelling, including JSONL string bodies.
        "\nconst stable=(value,root)=>typeof value==='string'?value.split(root).join('ROOT').split(JSON.stringify(root).slice(1,-1)).join('ROOT'):Array.isArray(value)?value.map(item=>stable(item,root)):value&&typeof value==='object'?Object.fromEntries(Object.entries(value).map(([key,item])=>[key,stable(item,root)])):value;" ++
        "if(" ++ actual_name ++ ".length!==" ++ std.fmt.comptimePrint("{d}", .{count}) ++ "||ordinarySource." ++ expected_name ++ ".length!==" ++ std.fmt.comptimePrint("{d}", .{count}) ++ ")throw Error('All genuine Source cases required');for(let i=0;i<" ++ std.fmt.comptimePrint("{d}", .{count}) ++ ";i++){const actual=stable(" ++ actual_name ++ "[i],ordinaryAPI.path.normalize(ordinaryRoot)),expected=stable(ordinarySource." ++ expected_name ++ "[i],ordinarySource.root);if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({case:i,name:" ++ actual_name ++ "[i].name,actual,expected}));}", "native-ordinary-session-exports5ab.mjs") catch |err| {
        std.debug.print("Native ordinary exports differential: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    engine.freeValue(evaluated);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}
test "native ordinary session exports five method descriptors match retained Source166" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment = try @import("extensions/native_env_node_path.zig").environment(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const source = @embedFile("extensions/fixtures/sdk-session-prototype-original-e622.json");
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "ordinaryDescriptors", try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "source-session-descriptors.json"))));
    const result = try engine.evalModule(
        \\for(const key of ['executeBash','recordBashResult','exportToHtml','exportToJsonl','summarizeForBugReport']){const d=Object.getOwnPropertyDescriptor(ordinaryAPI.AgentSession.prototype,key);if(!d)throw Error('Missing ordinary method '+key);const f=d.value,actual={key,kind:'data',enumerable:d.enumerable,configurable:d.configurable,writable:d.writable,valueType:typeof f,function:{name:f.name,length:f.length,async:Object.getPrototypeOf(f)===Object.getPrototypeOf(async()=>{}),ownPrototype:Object.hasOwn(f,'prototype')}};const expected=ordinaryDescriptors.descriptors.find(row=>row.key===key);if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({actual,expected}));}export const done=true;
    , "native-ordinary-exports-descriptors.mjs");
    engine.freeValue(result);
}
test "native ordinary session exports pending Bash retains actual session and releases graph" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment = try @import("extensions/native_env_node_path.zig").environment(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const prepared = try engine.evalModule(
        \\(()=>{const {AgentSession,SessionManager,SettingsManager,Agent}=ordinaryAPI,s=Object.assign(Object.create(AgentSession.prototype),{sessionManager:SessionManager.inMemory(),settingsManager:SettingsManager.inMemory(),agent:new Agent({streamFn:()=>{throw Error('Unexpected model request in Bash graph test')}}),_isAgentRunActive:false,_pendingBashMessages:[],_bashAbortControllers:new Set(),_entryIdsByMessage:new WeakMap(),_eventListeners:[]});globalThis.sessionExecWeak=new WeakRef(s);globalThis.sessionExecPending=s.executeBash('held',undefined,{operations:{exec(command,cwd,{onData}){onData(Uint8Array.from([104,101,108,100]));return new Promise(resolve=>{globalThis.sessionExecRelease=resolve})}}});})();export const ready=true;
    , "native-ordinary-bash-gc-prepare.mjs");
    engine.freeValue(prepared);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\if(!sessionExecWeak.deref()||!sessionExecWeak.deref().isBashRunning)throw Error('Pending ordinary session lost');sessionExecRelease({exitCode:7});const result=await sessionExecPending;if(result.output!=='held'||result.exitCode!==7||sessionExecWeak.deref().isBashRunning||sessionExecWeak.deref().messages.at(-1).role!=='bashExecution')throw Error('Pending ordinary Bash graph lost');delete globalThis.sessionExecPending;delete globalThis.sessionExecRelease;export const done=true;
    , "native-ordinary-bash-gc-complete.mjs");
    engine.freeValue(completed);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const collected = try engine.eval("sessionExecWeak.deref()===undefined", "native-ordinary-bash-gc-collected.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(collected);
    try std.testing.expect(c.JS_ToBool(engine.context, collected) == 1);
}
