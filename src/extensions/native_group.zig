//! One directly linked VM owner with distinct extension registrations.
const std = @import("std");
const engine_mod = @import("engine.zig");
const bindings_mod = @import("native_bindings.zig");
const native_ui = @import("native_ui.zig");
const native_renderers = @import("native_renderers.zig");
const abort_signal = @import("abort_signal.zig");
const c = engine_mod.c;

pub const Entry = struct { id: u64, source: []u8, binding: *bindings_mod.Bindings };
pub const Group = struct {
    engine: *engine_mod.Engine,
    ui: *native_ui.Manager,
    renderers: *native_renderers.Manager,
    broker: bindings_mod.Bindings.InvocationBroker = .{},
    entries: std.ArrayList(Entry) = .empty,
    next_id: u64 = 1,

    pub fn init(engine: *engine_mod.Engine) !*Group {
        if (engine.host_data != null or engine.native_ui_manager != null) return error.NativeGroupAlreadyAttached;
        if (!engine.abort_signals_ready) try abort_signal.install(engine);
        const ui = try native_ui.Manager.init(engine);
        errdefer ui.deinit();
        const renderers = try native_renderers.Manager.init(engine);
        errdefer renderers.deinit();
        const self = try engine.gpa.create(Group);
        self.* = .{ .engine = engine, .ui = ui, .renderers = renderers };
        return self;
    }

    pub fn deinit(self: *Group) void {
        for (self.entries.items) |entry| {
            entry.binding.deinit();
            self.engine.gpa.free(entry.source);
        }
        self.entries.deinit(self.engine.gpa);
        self.renderers.deinit();
        self.ui.deinit();
        self.engine.gpa.destroy(self);
    }

    pub fn add(self: *Group, path: []const u8) !*bindings_mod.Bindings {
        if (self.entries.items.len >= 4096 or self.next_id >= 9_007_199_254_740_991) return error.NativeGroupExtensionLimit;
        const source = try self.engine.gpa.dupe(u8, path);
        errdefer self.engine.gpa.free(source);
        const binding = try bindings_mod.Bindings.initShared(self.engine.gpa, self.engine, .{ .ui = self.ui, .renderers = self.renderers, .broker = &self.broker, .owner_id = self.next_id, .tool_lookup = lookupTool, .tool_context = self });
        errdefer binding.deinit();
        try binding.setSourcePath(path);
        try self.entries.append(self.engine.gpa, .{ .id = self.next_id, .source = source, .binding = binding });
        self.next_id += 1;
        return binding;
    }

    pub fn selected(self: *Group, id: u64) !*bindings_mod.Bindings {
        for (self.entries.items) |entry| if (entry.id == id) return entry.binding;
        return error.UnknownNativeExtensionOwner;
    }

    pub fn remove(self: *Group, id: u64) void {
        for (self.entries.items, 0..) |entry, index| if (entry.id == id) {
            const removed = self.entries.orderedRemove(index);
            removed.binding.deinit();
            self.engine.gpa.free(removed.source);
            return;
        };
    }

    pub fn tool(self: *Group, name: []const u8) ?c.JSValue {
        for (self.entries.items) |entry| if (entry.binding.tools.get(name)) |value| return value;
        return null;
    }

    fn lookupTool(context: ?*anyopaque, name: []const u8) ?c.JSValue {
        const self: *Group = @ptrCast(@alignCast(context.?));
        return self.tool(name);
    }

    pub fn manifest(self: *Group) ![]u8 {
        var arena: std.heap.ArenaAllocator = .init(self.engine.gpa);
        defer arena.deinit();
        const allocator = arena.allocator();
        var entries: std.json.Array = .init(allocator);
        for (self.entries.items) |entry| {
            const raw = try entry.binding.manifestJson(entry.source);
            defer self.engine.gpa.free(raw);
            var manifest_value = try std.json.parseFromSliceLeaky(std.json.Value, allocator, raw, .{});
            try manifest_value.object.put(allocator, "extensionId", .{ .integer = @intCast(entry.id) });
            try manifest_value.object.put(allocator, "sourcePath", .{ .string = entry.source });
            try entries.append(manifest_value);
        }
        return std.json.Stringify.valueAlloc(self.engine.gpa, std.json.Value{ .array = entries }, .{});
    }
};

test "native group retains real resolver base component state identity and action origin across extension callbacks" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const group = try Group.init(engine);
    defer group.deinit();
    const first = try group.add("group-resolver-first.mjs");
    try first.installSchemas();
    try first.loadFactory("export default pi=>{globalThis.firstApi=pi;pi.registerToolRenderer((name,next)=>{const base=next();if(!base)return base;return {...base,renderCall(args,theme,ctx){const component=base.renderCall(args,theme,ctx);if(component!==globalThis.baseComponent||ctx.state!==globalThis.baseState)throw Error('resolver identity');firstApi.appendEntry('origin-first',{identity:true});return component}}})}", "group-resolver-first.mjs");
    const second = try group.add("group-tool-second.mjs");
    try second.loadFactory("import {Text} from 'pi-tui';export default pi=>pi.registerTool({name:'second-tool',execute(){return {}},renderCall(args,theme,ctx){globalThis.baseState=ctx.state;globalThis.baseComponent=ctx.lastComponent??new Text('actual',0,0);return baseComponent}})", "group-tool-second.mjs");
    const actual = group.tool("second-tool").?;
    const first_resolved = try group.renderers.resolve("second-tool", actual);
    defer engine.freeValue(first_resolved);
    try std.testing.expect(c.JS_IsObject(first_resolved));
    try second.setContext("{\"cwd\":\"group\"}");
    const shared_tool = c.JS_DupValue(engine.context, actual);
    defer engine.freeValue(shared_tool);
    // Begin the selected extension invocation; another extension's resolver
    // records its action to this invocation while retaining its own origin.
    const signal = try abort_signal.create(engine);
    defer engine.freeValue(signal);
    try second.setInvocationOptions(signal, null, null);
    const raw = try second.invokeRenderer(.render_tool_call, "second-tool", "{\"toolCallId\":\"group-row\",\"args\":{}}");
    defer std.testing.allocator.free(raw);
    try std.testing.expect(std.mem.indexOf(u8, raw, "actual") != null);
    try std.testing.expectEqual(@as(usize, 1), second.actions.items.len);
    const origin = try engine.checked(c.JS_GetPropertyStr(engine.context, second.actions.items[0], "sourceExtensionId"));
    defer engine.freeValue(origin);
    var owner_id: i64 = 0;
    try std.testing.expect(c.JS_ToInt64(engine.context, &owner_id, origin) == 0);
    try std.testing.expectEqual(@as(i64, 1), owner_id);
    // Renderer output actions are display-only. The source still belongs to
    // firstApi and never mutates the second extension's registrations.
    try std.testing.expect(!first.tools.contains("second-tool") and second.tools.contains("second-tool"));
    c.JS_RunGC(engine.runtime);
}

test "native group retired owner callbacks cannot attribute late actions to surviving invocations" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const group = try Group.init(engine);
    defer group.deinit();
    const first = try group.add("retired-owner.mjs");
    try first.loadFactory("export default pi=>{globalThis.retiredApi=pi;pi.registerToolRenderer((name,next)=>next())}", "retired-owner.mjs");
    const second = try group.add("surviving-owner.mjs");
    try second.loadFactory("export default pi=>pi.registerCommand('late',{handler(){let rejected=false;try{retiredApi.appendEntry('late',{spoof:true})}catch(error){rejected=true}pi.appendEntry('live',{});return {message:String(rejected)}}})", "surviving-owner.mjs");
    group.remove(1);
    c.JS_RunGC(engine.runtime);
    const raw = try second.invokeCommand("late", "");
    defer std.testing.allocator.free(raw);
    try std.testing.expect(std.mem.indexOf(u8, raw, "\"message\":\"true\"") != null);
    try std.testing.expectEqual(@as(usize, 1), second.actions.items.len);
    const value = try engine.checked(c.JS_GetPropertyStr(engine.context, second.actions.items[0], "sourceExtensionName"));
    defer engine.freeValue(value);
    const name = try engine.toString(value);
    defer std.testing.allocator.free(name);
    try std.testing.expectEqualStrings("surviving-owner", name);
    try std.testing.expect(group.broker.active == null);
    c.JS_RunGC(engine.runtime);
}

test "native group API reads use active session while flags keep their registration owner" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const group = try Group.init(engine);
    defer group.deinit();
    const first = try group.add("first-read.mjs");
    try first.loadFactory("export default pi=>{globalThis.firstReadApi=pi;pi.registerFlag('label',{type:'string',default:'first'})}", "first-read.mjs");
    try first.setContext("{\"settings\":{\"marker\":\"old\"},\"sessionName\":\"old\"}");
    const second = try group.add("second-read.mjs");
    try second.loadFactory("export default pi=>pi.registerCommand('read',{handler(){firstReadApi.setSessionName('changed');return {message:firstReadApi.getSettings().marker+':'+firstReadApi.getSessionName()+':'+firstReadApi.getFlag('label')}}})", "second-read.mjs");
    try second.setContext("{\"settings\":{\"marker\":\"active\"},\"sessionName\":\"before\"}");
    const raw = try second.invokeCommand("read", "");
    defer std.testing.allocator.free(raw);
    try std.testing.expect(std.mem.indexOf(u8, raw, "active:changed:first") != null);
}
