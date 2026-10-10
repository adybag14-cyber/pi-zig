const std = @import("std");
const em = @import("extensions/engine.zig");
const bindings = @import("extensions/native_bindings.zig");
const ui = @import("extensions/ui.zig");
const native_ui = @import("extensions/native_ui.zig");
const c = em.c;
const json = @import("mcp/protocol.zig").json;
comptime {
    _ = @import("extensions/native_worker.zig");
    _ = @import("extensions/native_ui_sync.zig");
}
const Frontend = struct {
    engine: *em.Engine,
    controller: *ui.Controller,
    theme_changed: usize = 0,
    record_status: bool = false,
    fn request(_: ?*anyopaque, _: u32, _: []const u8, _: []const u8) !void {
        return error.UnexpectedAsyncUi;
    }
    fn action(raw: ?*anyopaque, method: []const u8, args: []const u8) !void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        try self.controller.applyAction(method, args);
    }
    fn sync(raw: ?*anyopaque, _: u32, method: []const u8, args: []const u8) !c.JSValue {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        const encoded = try self.controller.request(self.engine.gpa, method, args);
        defer self.engine.gpa.free(encoded);
        if (self.record_status and std.mem.eql(u8, method, "toolsExpansionComplete")) {
            var input = try json.Owned.parse(self.engine.gpa, args);
            defer input.deinit();
            const expanded = input.value.object.get("expanded").?.bool;
            const global = c.JS_GetGlobalObject(self.engine.context);
            defer self.engine.freeValue(global);
            const trace = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, global, "expandedTrace"));
            defer self.engine.freeValue(trace);
            const length = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, trace, "length"));
            defer self.engine.freeValue(length);
            var index: u32 = 0;
            if (c.JS_ToUint32(self.engine.context, &index, length) < 0) return error.JavaScriptException;
            const row = try self.engine.checked(c.JS_NewArray(self.engine.context));
            if (c.JS_SetPropertyUint32(self.engine.context, row, 0, try self.engine.checked(c.JS_NewString(self.engine.context, "status"))) < 0) {
                self.engine.freeValue(row);
                return error.JavaScriptException;
            }
            if (c.JS_SetPropertyUint32(self.engine.context, row, 1, try self.engine.checked(c.JS_NewString(self.engine.context, if (expanded) "Tool output: expanded" else "Tool output: collapsed"))) < 0) {
                self.engine.freeValue(row);
                return error.JavaScriptException;
            }
            if (c.JS_SetPropertyUint32(self.engine.context, trace, index, row) < 0) return error.JavaScriptException;
        }
        if (std.mem.eql(u8, method, "setTheme")) {
            self.theme_changed += 1;
            const global = c.JS_GetGlobalObject(self.engine.context);
            defer self.engine.freeValue(global);
            if (c.JS_SetPropertyStr(self.engine.context, global, "themeChanged", c.JS_NewInt64(self.engine.context, @intCast(self.theme_changed))) < 0) return error.JavaScriptException;
        }
        var parsed = try json.Owned.parse(self.engine.gpa, encoded);
        defer parsed.deinit();
        return self.engine.fromJsonValue(parsed.value);
    }
    fn cancel(_: ?*anyopaque, _: u32) !void {}
    fn open(_: ?*anyopaque, _: @import("extensions/native_ui_service_protocol.zig").Lease) !void {}
    fn close(_: ?*anyopaque, _: @import("extensions/native_ui_service_protocol.zig").Lease) !void {}
    fn bridge(self: *@This()) native_ui.Bridge {
        return .{ .context = self, .request = request, .action = action, .sync_request = sync, .cancel = cancel, .service_open = open, .service_close = close };
    }
};
fn writeTheme(directory: std.Io.Dir, name: []const u8, accent: []const u8, path: []const u8) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, @embedFile("themes/fixtures/dark-original-6fb.json"), .{});
    defer parsed.deinit();
    try parsed.value.object.put(std.testing.allocator, "name", .{ .string = name });
    try parsed.value.object.getPtr("colors").?.object.put(std.testing.allocator, "accent", .{ .string = accent });
    const encoded = try std.json.Stringify.valueAlloc(std.testing.allocator, parsed.value, .{});
    defer std.testing.allocator.free(encoded);
    try directory.writeFile(std.testing.io, .{ .sub_path = path, .data = encoded });
}
fn expectJson(gpa: std.mem.Allocator, raw: []const u8, expected: []const u8) !void {
    var actual = try json.Owned.parse(gpa, raw);
    defer actual.deinit();
    var wanted = try json.Owned.parse(gpa, expected);
    defer wanted.deinit();
    if (!json.equal(actual.value, wanted.value)) std.debug.print("Main UI actual={s}\n", .{raw});
    try std.testing.expect(json.equal(actual.value, wanted.value));
}

test "native Main UI adapter expanded state actual producer header callback noop and original throw order" {
    @import("tui/render.zig").setSilent(true);
    defer @import("tui/render.zig").setSilent(false);
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const owner = try bindings.Bindings.init(std.testing.allocator, engine);
    defer owner.deinit();
    try owner.installSchemas();
    var controller = try ui.Controller.init(std.testing.allocator, std.testing.io, true, 80);
    defer controller.deinit();
    var frontend: Frontend = .{ .engine = engine, .controller = &controller };
    owner.ui_manager.bridge = frontend.bridge();
    try owner.loadFactory("export default pi=>pi.registerCommand('capture',{handler(_args,ctx){const ui=ctx.ui;globalThis.savedUI=ui;const trace=[],header={render(){return []},setExpanded(value){trace.push(['header',value,this===header])}};ui.setHeader(()=>header);const rows=[ui.getToolsExpanded()];ui.setToolsExpanded(true);rows.push(ui.getToolsExpanded());ui.setToolsExpanded(true);ui.setToolsExpanded(false);rows.push(ui.getToolsExpanded());const original={tag:'identity'};header.setExpanded=function(value){trace.push(['throw',value]);throw original};let same=false;try{ui.setToolsExpanded(true)}catch(error){same=error===original}rows.push(ui.getToolsExpanded());return{rows,trace,same}}})", "main-ui-expanded.mjs");
    try owner.setContext("{\"hasUI\":true,\"mode\":\"interactive\",\"nativeRuntimeBound\":true}");
    const raw = try owner.invokeCommand("capture", "");
    defer engine.gpa.free(raw);
    try expectJson(engine.gpa, raw, "{\"rows\":[false,true,false,true],\"trace\":[[\"header\",true,true],[\"header\",false,true],[\"throw\",true]],\"same\":true}");
    try std.testing.expect(controller.toolsExpanded());
    var failed_header_surface = try controller.snapshotRetained(engine.gpa);
    defer failed_header_surface.deinit();
    try std.testing.expect(!failed_header_surface.tools_expanded);
    const result = try engine.eval("savedUI.getToolsExpanded()", "retained-ui-expanded.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    try std.testing.expect(c.JS_ToBool(engine.context, result) != 0);
    try controller.applyAction("setToolsExpanded", "{\"expanded\":false}");
    const updated = try engine.eval("try{savedUI.setToolsExpanded(true)}catch(error){if(error.tag!=='identity')throw error}savedUI.getToolsExpanded()", "retained-ui-keyboard-update.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(updated);
    try std.testing.expect(c.JS_ToBool(engine.context, updated) != 0);
    try std.testing.expect(controller.toolsExpanded());
}

test "native Main UI adapter genuine theme registry files named settings in-memory identity and system fallback match Source" {
    @import("tui/render.zig").setSilent(true);
    defer @import("tui/render.zig").setSilent(false);
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(std.testing.io, "agent/themes");
    try writeTheme(temporary.dir, "alpha", "#123456", "agent/themes/alpha.json");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "agent/themes/bad.json", .data = "not-json" });
    try writeTheme(temporary.dir, "registered", "#abcdef", "registered.json");
    try writeTheme(temporary.dir, "alpha", "#fedcba", "override.json");
    try writeTheme(temporary.dir, "instance-name", "#112233", "instance.json");
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try temporary.dir.realPath(std.testing.io, &buffer);
    const root = buffer[0..length];
    const agent_dir = try std.fs.path.join(std.testing.allocator, &.{ root, "agent" });
    defer std.testing.allocator.free(agent_dir);
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try environment.put("PI_CODING_AGENT_DIR", agent_dir);
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{});
    try @import("extensions/node_path.zig").install(engine, std.testing.io);
    try @import("extensions/node_fs.zig").install(engine, std.testing.io);
    const owner = try bindings.Bindings.init(std.testing.allocator, engine);
    defer owner.deinit();
    try owner.installSchemas();
    var registry = @import("themes/registry.zig").Registry.init(std.testing.allocator, std.testing.io);
    defer registry.deinit();
    inline for (.{ "registered.json", "override.json" }) |file| {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root, file });
        defer std.testing.allocator.free(path);
        try registry.loadPath(path);
    }
    var controller = try ui.Controller.init(std.testing.allocator, std.testing.io, true, 80);
    defer controller.deinit();
    try controller.setThemeResources(&registry);
    var reports = try @import("extensions/terminal_theme_producer.zig").Producer.init(std.testing.allocator, std.testing.io, &controller, .truecolor, false);
    defer reports.deinit();
    // The Source InteractiveThemeController constructor marks reports pending
    // before any query. Model that actual producer transition explicitly.
    try reports.begin();
    try reports.select(@embedFile("themes/fixtures/dark-original-6fb.json"), "initial-dark");
    var producer = try @import("extensions/main_theme_producer.zig").Producer.init(std.testing.allocator, std.testing.io, &controller, &reports, agent_dir, root, false, "dark");
    defer producer.deinit();
    producer.attach();
    var frontend: Frontend = .{ .engine = engine, .controller = &controller };
    owner.ui_manager.bridge = frontend.bridge();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const instance_path = try std.fs.path.join(std.testing.allocator, &.{ root, "instance.json" });
    defer std.testing.allocator.free(instance_path);
    if (c.JS_SetPropertyStr(engine.context, global, "instancePath", try engine.checked(c.JS_NewStringLen(engine.context, instance_path.ptr, instance_path.len))) < 0) return error.JavaScriptException;
    owner.loadFactory("import{loadThemeFromPath}from'pi-coding-agent';import{basename}from'node:path';import{existsSync}from'node:fs';export default pi=>pi.registerCommand('themes',{handler(_args,ctx){const ui=ctx.ui,proxy=ui.theme,all=ui.getAllThemes(),registered=ui.getTheme('registered'),alpha=ui.getTheme('alpha');const rows=[],observe=tag=>rows.push({tag,name:ui.theme.name,accent:ui.theme.colors.accent,setting:pi.getSettings().theme});observe('initial');const a=ui.setTheme('registered');observe('registered');const instance=loadThemeFromPath(instancePath);const b=ui.setTheme(instance);observe('instance');instance.name='mutated-name';observe('instance-mutated');const d=ui.setTheme('missing');observe('missing');const e=ui.setTheme('dark');observe('dark');return{source:'6fb2e7815167e6b19006fc526d1a5d0f5f998787',all:all.map(value=>({name:value.name,path:value.path===undefined?null:basename(value.path)})),allPathsExist:all.every(value=>value.path===undefined||existsSync(value.path)),alphaListUsesCustom:all.find(value=>value.name==='alpha').path.endsWith('alpha.json'),registeredSame:ui.getTheme('registered')===registered,alphaSame:ui.getTheme('alpha')===alpha,missing:ui.getTheme('missing')===undefined,proxySame:ui.theme===proxy,results:[a,b,d,e],rows,changed:globalThis.themeChanged}}})", "main-ui-themes.mjs") catch |err| {
        std.debug.print("Main UI theme module: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    const snapshot = try controller.contextJson(engine.gpa, .{ .mode = "interactive", .cwd = root, .session_id = "main-ui", .runtime_bound = true, .settings_json = "{\"theme\":\"dark\"}" });
    defer engine.gpa.free(snapshot);
    try owner.setContext(snapshot);
    const raw = try owner.invokeCommand("themes", "");
    defer engine.gpa.free(raw);
    try expectJson(engine.gpa, raw, @embedFile("extensions/fixtures/main-ui-themes-source-400.json"));
    _ = try engine.drainReadyJobs();
    try std.testing.expectEqual(@as(usize, 0), producer.writes.items.len);
    var saved = try @import("coding_agent/settings.zig").loadMergeTrusted(engine.gpa, std.testing.io, agent_dir, root, false);
    defer saved.deinit(engine.gpa);
    try std.testing.expectEqualStrings("dark", saved.theme.?);
}

test "native Main UI adapter Source409 settings writes run after the guest stack and record actual IO failures while retaining memory" {
    @import("tui/render.zig").setSilent(true);
    defer @import("tui/render.zig").setSilent(false);
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(std.testing.io, "agent");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "agent/settings.json", .data = "{\"theme\":\"dark\"}" });
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root = buffer[0..try temporary.dir.realPath(std.testing.io, &buffer)];
    const directory = try std.fs.path.join(std.testing.allocator, &.{ root, "agent" });
    defer std.testing.allocator.free(directory);
    const path = try std.fs.path.join(std.testing.allocator, &.{ directory, "settings.json" });
    defer std.testing.allocator.free(path);
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("extensions/node_fs.zig").install(engine, std.testing.io);
    const owner = try bindings.Bindings.init(std.testing.allocator, engine);
    defer owner.deinit();
    try owner.installSchemas();
    var controller = try ui.Controller.init(std.testing.allocator, std.testing.io, true, 80);
    defer controller.deinit();
    var reports = try @import("extensions/terminal_theme_producer.zig").Producer.init(std.testing.allocator, std.testing.io, &controller, .truecolor, false);
    defer reports.deinit();
    try reports.select(@embedFile("themes/fixtures/dark-original-6fb.json"), "initial-dark");
    var producer = try @import("extensions/main_theme_producer.zig").Producer.init(std.testing.allocator, std.testing.io, &controller, &reports, directory, root, false, "dark");
    defer producer.deinit();
    producer.attach();
    var frontend: Frontend = .{ .engine = engine, .controller = &controller };
    owner.ui_manager.bridge = frontend.bridge();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    if (c.JS_SetPropertyStr(engine.context, global, "settingsPath", try engine.checked(c.JS_NewStringLen(engine.context, path.ptr, path.len))) < 0) return error.JavaScriptException;
    try owner.loadFactory("import{readFileSync}from'node:fs';export default pi=>{pi.registerCommand('timing',{handler(_,ctx){const result=ctx.ui.setTheme('light');return{result,diskBeforeReturn:JSON.parse(readFileSync(settingsPath,'utf8')).theme,setting:pi.getSettings().theme,theme:ctx.ui.theme.name}}});pi.registerCommand('failure',{handler(_,ctx){let thrown=false,result;try{result=ctx.ui.setTheme('dark')}catch(error){thrown=true}return{thrown,result,theme:ctx.ui.theme.name,setting:pi.getSettings().theme}}})}", "settings-write-main-ui.mjs");
    const snapshot = try controller.contextJson(engine.gpa, .{ .mode = "interactive", .cwd = root, .session_id = "write-timing", .runtime_bound = true, .settings_json = "{\"theme\":\"dark\"}" });
    defer engine.gpa.free(snapshot);
    try owner.setContext(snapshot);
    const timing = try owner.invokeCommand("timing", "");
    defer engine.gpa.free(timing);
    try expectJson(engine.gpa, timing, "{\"result\":{\"success\":true},\"diskBeforeReturn\":\"dark\",\"setting\":\"light\",\"theme\":\"light\"}");
    _ = try engine.drainReadyJobs();
    try std.testing.expectEqual(@as(usize, 0), producer.writes.items.len);
    try temporary.dir.deleteFile(std.testing.io, "agent/settings.json");
    try temporary.dir.createDir(std.testing.io, "agent/settings.json", .default_dir);
    const failure = try owner.invokeCommand("failure", "");
    defer engine.gpa.free(failure);
    try expectJson(engine.gpa, failure, "{\"thrown\":false,\"result\":{\"success\":true},\"theme\":\"dark\",\"setting\":\"dark\"}");
    _ = try engine.drainReadyJobs();
    try std.testing.expectEqual(@as(usize, 0), producer.writes.items.len);
    try std.testing.expectEqual(@as(usize, 1), producer.errors.items.len);
    try std.testing.expectEqualStrings(path, producer.errors.items[0].path);
    try std.testing.expect(std.mem.indexOf(u8, producer.errors.items[0].message, "settings could not be saved") != null);
}

fn themeProducerAllocationCase(gpa: std.mem.Allocator) !void {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(std.testing.io, "agent");
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root = buffer[0..try temporary.dir.realPath(std.testing.io, &buffer)];
    const directory = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(directory);
    var controller = try ui.Controller.init(gpa, std.testing.io, true, 80);
    defer controller.deinit();
    var reports = try @import("extensions/terminal_theme_producer.zig").Producer.init(gpa, std.testing.io, &controller, .truecolor, false);
    defer reports.deinit();
    var producer = try @import("extensions/main_theme_producer.zig").Producer.init(gpa, std.testing.io, &controller, &reports, directory, root, false, "dark");
    defer producer.deinit();
    producer.attach();
    const selected = try controller.request(gpa, "setTheme", "{\"resource\":" ++ @embedFile("themes/fixtures/light-original-6fb.json") ++ ",\"resourceIdentity\":\"allocation-owned\",\"settingName\":\"light\"}");
    defer gpa.free(selected);
    const persisted = try controller.request(gpa, "persistMainThemeSetting", "{\"persistWriteId\":1}");
    defer gpa.free(persisted);
    try std.testing.expectEqualStrings("light", producer.setting.?);
    try std.testing.expectEqual(@as(usize, 0), producer.writes.items.len);
    try std.testing.expectEqual(@as(usize, 1), producer.published.items.len);
}
fn themeProducerAllocationProbe(gpa: std.mem.Allocator) !void {
    themeProducerAllocationCase(gpa) catch |err| {
        const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
        if (failing.has_induced_failure and (err == error.OutOfMemory or err == error.WriteFailed)) return error.OutOfMemory;
        return err;
    };
    const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
    if (failing.has_induced_failure) return error.OutOfMemory;
}
test "native Main UI adapter exhaustive actual parent theme settings publication allocation ownership" {
    @import("tui/render.zig").setSilent(true);
    defer @import("tui/render.zig").setSilent(false);
    try @import("test_support/sdk_allocation_shards.zig").check("main-ui-parent-theme", themeProducerAllocationProbe, .{});
}

fn expectVisible(gpa: std.mem.Allocator, lines: []const []u8, expected: std.json.Value) !void {
    var index: usize = 0;
    for (lines) |line| {
        const visible = try @import("tui/terminal_text.zig").stripAlloc(gpa, line);
        defer gpa.free(visible);
        const trimmed = std.mem.trimEnd(u8, visible, " ");
        if (std.mem.trim(u8, trimmed, " ").len == 0) continue;
        if (index >= expected.array.items.len) return error.ExtraVisibleToolRow;
        try std.testing.expectEqualStrings(expected.array.items[index].string, trimmed);
        index += 1;
    }
    try std.testing.expectEqual(expected.array.items.len, index);
}
fn presentationAllocationCase(gpa: std.mem.Allocator) !void {
    var oracle = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("extensions/fixtures/main-ui-tool-fallback-source-415.json"), .{});
    defer oracle.deinit();
    const fields = &oracle.value.object;
    const dark = "{\"colorMode\":\"truecolor\",\"resource\":" ++ @embedFile("themes/fixtures/dark-original-6fb.json") ++ "}";
    const light = "{\"colorMode\":\"truecolor\",\"resource\":" ++ @embedFile("themes/fixtures/light-original-6fb.json") ++ "}";
    var transcript = @import("coding_agent/transcript_view.zig").Transcript.init(gpa);
    defer transcript.deinit();
    try transcript.setThemeState(dark);
    inline for (.{ "accent", "toolTitle", "toolOutput" }) |token| try std.testing.expectEqualStrings(fields.get("darkColors").?.object.get(token).?.string, transcript.palette.?.get(token));
    const arguments = try std.json.Stringify.valueAlloc(gpa, fields.get("args").?, .{});
    defer gpa.free(arguments);
    try transcript.event(.{ .kind = .tool_execution_start, .id = "sample-row", .name = "sample", .args_json = arguments });
    try transcript.event(.{ .kind = .tool_execution_end, .id = "sample-row", .name = "sample", .text = fields.get("text").?.string });
    var view = try transcript.component().render(gpa, 120);
    defer view.deinit(gpa);
    try expectVisible(gpa, view.items, fields.get("genericCollapsed").?);
    transcript.setToolsExpanded(true);
    var expanded = try transcript.component().render(gpa, 120);
    defer expanded.deinit(gpa);
    try expectVisible(gpa, expanded.items, fields.get("genericExpanded").?);
    for ([_]bool{ false, true }) |is_expanded| {
        const call = try @import("tui/tool_fallback.zig").format(gpa, "sample", fields.get("args").?, is_expanded, &transcript.palette.?);
        defer gpa.free(call);
        const plain = try @import("tui/terminal_text.zig").stripAlloc(gpa, call);
        defer gpa.free(plain);
        try std.testing.expectEqualStrings(fields.get(if (is_expanded) "callExpanded" else "callCollapsed").?.string, plain);
    }
    const identity = "\"version\":1,\"ownerGeneration\":\"1\",\"extensionId\":\"2\",\"rowGeneration\":\"3\",\"toolCallId\":\"sample-row\",\"width\":120";
    var record = try std.json.parseFromSlice(std.json.Value, gpa, "{" ++ identity ++ ",\"type\":\"renderer_register\",\"toolName\":\"sample\"}", .{});
    defer record.deinit();
    var registration = try @import("extensions/renderer_protocol.zig").read(gpa, &record.value.object);
    defer registration.deinit();
    _ = try transcript.adoptRenderer(&registration);
    var frame = try std.json.parseFromSlice(std.json.Value, gpa, "{" ++ identity ++ ",\"type\":\"renderer_frame\",\"sequence\":\"1\",\"revision\":\"1\",\"slot\":\"call\",\"lines\":[\"custom-call\"]}", .{});
    defer frame.deinit();
    var rendered = try @import("extensions/renderer_protocol.zig").read(gpa, &frame.value.object);
    defer rendered.deinit();
    _ = try transcript.adoptRenderer(&rendered);
    transcript.setToolsExpanded(false);
    var collapsed = try transcript.component().render(gpa, 120);
    defer collapsed.deinit(gpa);
    try expectVisible(gpa, collapsed.items, fields.get("resultCollapsed").?);
    transcript.setToolsExpanded(true);
    var result_expanded = try transcript.component().render(gpa, 120);
    defer result_expanded.deinit(gpa);
    try expectVisible(gpa, result_expanded.items, fields.get("resultExpanded").?);
    try transcript.setThemeState(light);
    inline for (.{ "accent", "toolTitle", "toolOutput" }) |token| try std.testing.expectEqualStrings(fields.get("lightColors").?.object.get(token).?.string, transcript.palette.?.get(token));
    try transcript.syncBranch(&.{.{ .entry_type = .message, .id = "durable-sample", .parent_id = null, .role = "toolResult", .content = fields.get("text").?.string, .tool_call_id = "sample-row" }}, null);
    try std.testing.expect(transcript.tools_expanded);
    inline for (.{ "accent", "toolTitle", "toolOutput" }) |token| try std.testing.expectEqualStrings(fields.get("lightColors").?.object.get(token).?.string, transcript.palette.?.get(token));
}
fn presentationAllocationProbe(gpa: std.mem.Allocator) !void {
    presentationAllocationCase(gpa) catch |err| {
        const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
        if (failing.has_induced_failure and (err == error.OutOfMemory or err == error.WriteFailed)) return error.OutOfMemory;
        return err;
    };
    const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
    if (failing.has_induced_failure) return error.OutOfMemory;
}
test "native Main UI adapter Source415 genuine ToolExecution fallback plain text call formatting palette publication durable reconciliation and allocation ownership" {
    try @import("test_support/sdk_allocation_shards.zig").check("main-ui-presentation", presentationAllocationProbe, .{});
}

fn assetsAllocationCase(gpa: std.mem.Allocator) !void {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDir(std.testing.io, "theme", .default_dir);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "theme/dark.json", .data = "existing-user-asset" });
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root = buffer[0..try temporary.dir.realPath(std.testing.io, &buffer)];
    const directory = try std.fs.path.join(gpa, &.{ root, "theme" });
    defer gpa.free(directory);
    const assets = @import("extensions/native_theme_assets.zig");
    try assets.ensure(gpa, std.testing.io, directory);
    try assets.ensure(gpa, std.testing.io, directory);
    const existing = try temporary.dir.readFileAlloc(std.testing.io, "theme/dark.json", gpa, .limited(1024));
    defer gpa.free(existing);
    try std.testing.expectEqualStrings("existing-user-asset", existing);
    const installed = try temporary.dir.readFileAlloc(std.testing.io, "theme/light.json", gpa, .limited(64 * 1024));
    defer gpa.free(installed);
    try std.testing.expectEqualStrings(@embedFile("themes/fixtures/light-original-6fb.json"), installed);
    const directory_handle = try temporary.dir.openDir(std.testing.io, "theme", .{ .iterate = true });
    defer directory_handle.close(std.testing.io);
    var iterator = directory_handle.iterate();
    while (try iterator.next(std.testing.io)) |entry| try std.testing.expect(!std.mem.endsWith(u8, entry.name, ".tmp"));
}
fn assetsAllocationProbe(gpa: std.mem.Allocator) !void {
    assetsAllocationCase(gpa) catch |err| {
        const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
        if (failing.has_induced_failure and (err == error.OutOfMemory or err == error.WriteFailed)) return error.OutOfMemory;
        return err;
    };
    const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
    if (failing.has_induced_failure) return error.OutOfMemory;
}
test "native Main UI adapter installed builtin assets preserve supplied files atomically and release every allocation" {
    try @import("test_support/sdk_allocation_shards.zig").check("main-ui-builtin-assets", assetsAllocationProbe, .{});
}

test "native Main UI adapter Source423 expanded header double lookup replacement and nested toggle preserve actual state and status order" {
    @import("tui/render.zig").setSilent(true);
    defer @import("tui/render.zig").setSilent(false);
    var oracle = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, @embedFile("extensions/fixtures/main-ui-expanded-reentry-source-423.json"), .{});
    defer oracle.deinit();
    const cases = .{
        .{ "nested", "let reads=0;const header={render(){return[]},get setExpanded(){trace.push(['get',++reads]);return function(value){trace.push(['call',value,this===header]);if(value)ui.setToolsExpanded(false)}}};ui.setHeader(()=>header);ui.setToolsExpanded(true);return{expanded:ui.getToolsExpanded(),trace}" },
        .{ "replaced", "let reads=0;const old={render(){return[]},get setExpanded(){trace.push(['get',++reads]);if(reads===1)ui.setHeader(()=>({render(){return[]},setExpanded(){trace.push(['new-called'])}}));return function(value){trace.push(['old-call',value,this===old])}}};ui.setHeader(()=>old);ui.setToolsExpanded(true);return{expanded:ui.getToolsExpanded(),trace}" },
        .{ "changing", "let reads=0;ui.setHeader(()=>({render(){return[]},get setExpanded(){trace.push(['get',++reads]);return reads===1?()=>{}:17}}));let name;try{ui.setToolsExpanded(true)}catch(error){name=error.name}return{expanded:ui.getToolsExpanded(),trace,name}" },
    };
    inline for (cases) |case| {
        const engine = try em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        engine.native_io = std.testing.io;
        const owner = try bindings.Bindings.init(std.testing.allocator, engine);
        defer owner.deinit();
        try owner.installSchemas();
        var controller = try ui.Controller.init(std.testing.allocator, std.testing.io, true, 80);
        defer controller.deinit();
        var frontend: Frontend = .{ .engine = engine, .controller = &controller, .record_status = true };
        owner.ui_manager.bridge = frontend.bridge();
        try owner.loadFactory("export default pi=>pi.registerCommand('capture',{handler(_,ctx){globalThis.expandedTrace=[];const trace=expandedTrace,ui=ctx.ui;" ++ case[1] ++ "}})", "expanded-header-reentry.mjs");
        try owner.setContext("{\"hasUI\":true,\"mode\":\"interactive\",\"nativeRuntimeBound\":true}");
        const result = try owner.invokeCommand("capture", "");
        defer engine.gpa.free(result);
        var observed = try json.Owned.parse(engine.gpa, result);
        defer observed.deinit();
        var surface = try controller.snapshotRetained(engine.gpa);
        defer surface.deinit();
        try observed.value.object.put(observed.arena.allocator(), "childrenExpanded", .{ .bool = surface.tools_expanded });
        const with_children = try std.json.Stringify.valueAlloc(engine.gpa, observed.value, .{});
        defer engine.gpa.free(with_children);
        const expected = try std.json.Stringify.valueAlloc(engine.gpa, oracle.value.object.get(case[0]).?, .{});
        defer engine.gpa.free(expected);
        try expectJson(engine.gpa, with_children, expected);
        try std.testing.expectEqual(!std.mem.eql(u8, case[0], "nested"), controller.toolsExpanded());
    }
}
