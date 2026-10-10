//! Retained widget components. Only the VM owner thread enters user callbacks.
const std = @import("std");
const engine_mod = @import("engine.zig");
const components = @import("native_components.zig");
const protocol = @import("widget_protocol.zig");
const c = engine_mod.c;
const Token = struct { gpa: std.mem.Allocator, manager: ?*Manager };
const Entry = struct { key: []u8, owner: u64, generation: u64, component: c.JSValue, placement: protocol.Placement, dirty: bool = true, mounted: bool = true, slot: protocol.Slot = .widget };
const Method = enum(c_int) { requestRender, columns, rows };

fn finalizer(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *Token = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    state.gpa.destroy(state);
}
pub const Manager = struct {
    engine: *engine_mod.Engine,
    token: c.JSValue,
    token_class: c.JSClassID,
    owners: std.AutoHashMapUnmanaged(u64, void) = .empty,
    entries: std.ArrayList(Entry) = .empty,
    generation: u64 = 0,
    sequence: u64 = 0,
    owner_generation: u64 = 1,
    width: usize = 80,
    height: usize = 24,
    dimensions_controlled: bool = false,
    invalidate_pending: bool = false,
    busy: bool = false,
    record_fn: ?*const fn (?*anyopaque, protocol.Record) anyerror!void = null,
    record_context: ?*anyopaque = null,

    pub fn init(engine: *engine_mod.Engine) !Manager {
        var class: c.JSClassID = 0;
        _ = c.JS_NewClassID(engine.runtime, &class);
        const definition: c.JSClassDef = .{ .class_name = "Native Widget Owner", .finalizer = finalizer };
        if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
        const token = try engine.checked(c.JS_NewObjectClass(engine.context, @intCast(class)));
        errdefer engine.freeValue(token);
        const state = try engine.gpa.create(Token);
        state.* = .{ .gpa = engine.gpa, .manager = null };
        _ = c.JS_SetOpaque(token, state);
        return .{ .engine = engine, .token = token, .token_class = class };
    }
    pub fn attach(self: *Manager) void {
        const state: *Token = @ptrCast(@alignCast(c.JS_GetOpaque(self.token, self.token_class).?));
        state.manager = self;
    }
    pub fn deinit(self: *Manager) void {
        self.owners.clearRetainingCapacity();
        while (self.entries.items.len > 0) self.retire(0);
        const state: *Token = @ptrCast(@alignCast(c.JS_GetOpaque(self.token, self.token_class).?));
        state.manager = null;
        self.entries.deinit(self.engine.gpa);
        self.owners.deinit(self.engine.gpa);
        self.engine.freeValue(self.token);
    }
    pub fn addOwner(self: *Manager, owner: u64) !void {
        try self.owners.put(self.engine.gpa, owner, {});
    }
    pub fn removeOwner(self: *Manager, owner: u64) void {
        _ = self.owners.remove(owner);
        var index: usize = 0;
        while (index < self.entries.items.len) {
            if (self.entries.items[index].owner == owner) self.retire(index) else index += 1;
        }
    }
    fn publish(self: *Manager, entry: Entry, frame: ?components.Frame) !void {
        return self.publishWidth(entry, frame, self.width);
    }
    fn publishWidth(self: *Manager, entry: Entry, frame: ?components.Frame, width: usize) !void {
        self.sequence += 1;
        if (self.record_fn) |sink| try sink(self.record_context, .{ .gpa = self.engine.gpa, .owner_generation = self.owner_generation, .generation = entry.generation, .sequence = self.sequence, .key = entry.key, .placement = entry.placement, .width = width, .frame = frame, .slot = entry.slot });
    }
    fn remove(self: *Manager, index: usize) !void {
        // Like upstream, a throwing explicit replacement/clear leaves the old
        // map entry retained. Owner retirement is a separate cleanup boundary.
        const current = self.entries.items[index];
        if (try components.callMethod(self.engine, current.component, "dispose", &.{}, true)) |value| self.engine.freeValue(value);
        try self.removeDisposed(index);
    }
    fn removeDisposed(self: *Manager, index: usize) !void {
        const entry = self.entries.orderedRemove(index);
        defer self.engine.gpa.free(entry.key);
        defer self.engine.freeValue(entry.component);
        try self.publish(entry, null);
    }
    fn retire(self: *Manager, index: usize) void {
        const entry = self.entries.orderedRemove(index);
        defer self.engine.gpa.free(entry.key);
        defer self.engine.freeValue(entry.component);
        // Teardown releases the retained root even if its user cleanup throws.
        if (components.callMethod(self.engine, entry.component, "dispose", &.{}, true) catch null) |value| self.engine.freeValue(value);
        self.publish(entry, null) catch {};
    }
    pub fn clear(self: *Manager) !void {
        if (self.busy) return error.NativeWidgetCallbackReentry;
        self.busy = true;
        defer self.busy = false;
        // Original reset disposes every component before clearing either map.
        // A failed callback retains all roots and suppresses subsequent ones.
        inline for (.{ protocol.Placement.aboveEditor, protocol.Placement.belowEditor }) |placement| {
            for (self.entries.items) |entry| if (entry.placement == placement) {
                if (try components.callMethod(self.engine, entry.component, "dispose", &.{}, true)) |value| self.engine.freeValue(value);
            };
        }
        while (self.entries.pop()) |entry| {
            defer self.engine.gpa.free(entry.key);
            defer self.engine.freeValue(entry.component);
            try self.publish(entry, null);
        }
    }
    fn function(self: *Manager, generation: u64, method: Method) !c.JSValue {
        var data = [_]c.JSValue{ self.token, c.JS_NewInt64(self.engine.context, self.token_class), c.JS_NewInt64(self.engine.context, @intCast(generation)) };
        defer self.engine.freeValue(data[1]);
        defer self.engine.freeValue(data[2]);
        return self.engine.checked(c.JS_NewCFunctionData2(self.engine.context, call, @tagName(method), 0, @intFromEnum(method), data.len, &data));
    }
    fn call(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
        const engine = engine_mod.Engine.fromContext(context.?);
        var class: i64 = 0;
        var generation: i64 = 0;
        if (c.JS_ToInt64(context, &class, data[1]) < 0 or c.JS_ToInt64(context, &generation, data[2]) < 0) return engine.throwCaptured();
        const token: *Token = @ptrCast(@alignCast(c.JS_GetOpaque(data[0], @intCast(class)) orelse return c.pi_js_undefined()));
        const self = token.manager orelse return c.pi_js_undefined();
        const method: Method = @enumFromInt(magic);
        switch (method) {
            .columns => return c.JS_NewInt64(context, @intCast(self.width)),
            .rows => return c.JS_NewInt64(context, @intCast(self.height)),
            .requestRender => {
                const live = for (self.entries.items) |entry| {
                    if (entry.generation == generation) break true;
                } else false;
                if (live) for (self.entries.items) |*entry| {
                    entry.dirty = entry.mounted;
                };
                return c.pi_js_undefined();
            },
        }
    }
    fn put(self: *Manager, object: c.JSValue, name: [:0]const u8, value: c.JSValue) !void {
        if (c.JS_DefinePropertyValueStr(self.engine.context, object, name, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
    fn arrayComponent(self: *Manager, array: c.JSValue, theme: c.JSValue) !c.JSValue {
        try @import("native_tui.zig").install(self.engine);
        const exports = self.engine.native_module_values.get("@earendil-works/pi-tui").?;
        const container_constructor = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, exports, "Container"));
        defer self.engine.freeValue(container_constructor);
        const text_constructor = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, exports, "Text"));
        defer self.engine.freeValue(text_constructor);
        const container = try self.engine.checked(c.JS_CallConstructor(self.engine.context, container_constructor, 0, null));
        errdefer self.engine.freeValue(container);
        const length_value = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, array, "length"));
        defer self.engine.freeValue(length_value);
        var length: i64 = 0;
        if (c.JS_ToInt64(self.engine.context, &length, length_value) < 0) return error.JavaScriptException;
        const count: usize = @intCast(@min(@max(length, 0), 10));
        for (0..count + @as(usize, @intFromBool(length > 10))) |index| {
            const line = if (index < count) try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, array, @intCast(index))) else blk: {
                const muted = try self.engine.checked(c.JS_NewString(self.engine.context, "muted"));
                defer self.engine.freeValue(muted);
                const label = try self.engine.checked(c.JS_NewString(self.engine.context, "... (widget truncated)"));
                defer self.engine.freeValue(label);
                var args = [_]c.JSValue{ muted, label };
                break :blk (try components.callMethod(self.engine, theme, "fg", &args, false)).?;
            };
            defer self.engine.freeValue(line);
            var args = [_]c.JSValue{ line, c.JS_NewInt32(self.engine.context, 1), c.JS_NewInt32(self.engine.context, 0) };
            const text = try self.engine.checked(c.JS_CallConstructor(self.engine.context, text_constructor, args.len, &args));
            defer self.engine.freeValue(text);
            var child = [_]c.JSValue{text};
            if (try components.callMethod(self.engine, container, "addChild", &child, false)) |value| self.engine.freeValue(value);
        }
        return container;
    }
    pub fn set(self: *Manager, owner: u64, key: []const u8, factory: c.JSValue, placement: protocol.Placement, theme: c.JSValue) !void {
        return self.setSlot(owner, key, factory, placement, theme, .widget, c.pi_js_undefined());
    }
    pub fn setSlot(self: *Manager, owner: u64, key: []const u8, factory: c.JSValue, placement: protocol.Placement, theme: c.JSValue, slot: protocol.Slot, footer_data: c.JSValue) !void {
        if (!self.owners.contains(owner)) return error.StaleNativeExtensionOwner;
        if (self.busy) return error.NativeWidgetCallbackReentry;
        self.busy = true;
        defer self.busy = false;
        var replace_index: ?usize = null;
        var index: usize = 0;
        while (index < self.entries.items.len) {
            if (self.entries.items[index].slot == slot and std.mem.eql(u8, self.entries.items[index].key, key)) {
                if (slot == .widget) try self.remove(index) else {
                    const previous = self.entries.items[index];
                    if (try components.callMethod(self.engine, previous.component, "dispose", &.{}, true)) |value| self.engine.freeValue(value);
                    replace_index = index;
                    // Footer clears its Container before the factory call;
                    // header replacement retains its current child on throw.
                    if (slot == .footer) {
                        self.entries.items[index].mounted = false;
                        self.entries.items[index].dirty = false;
                        // A present empty frame keeps the footer Container
                        // empty; null restores the built-in footer instead.
                        try self.publish(previous, .{ .gpa = self.engine.gpa, .lines = &.{}, .bytes = 0 });
                    }
                    break;
                }
            } else index += 1;
        }
        if (c.JS_IsUndefined(factory) or c.JS_IsNull(factory)) {
            if (replace_index) |previous| try self.removeDisposed(previous);
            return;
        }
        if (!c.JS_IsFunction(self.engine.context, factory) and (slot != .widget or !c.JS_IsArray(factory))) return error.InvalidNativeWidgetFactory;
        if ((self.entries.items.len >= 256 and replace_index == null) or key.len > 65536) return error.NativeWidgetLimit;
        self.generation += 1;
        const generation = self.generation;
        const tui = try self.engine.checked(c.JS_NewObject(self.engine.context));
        defer self.engine.freeValue(tui);
        try self.put(tui, "requestRender", try self.function(generation, .requestRender));
        const terminal = try self.engine.checked(c.JS_NewObject(self.engine.context));
        defer self.engine.freeValue(terminal);
        inline for (.{ .{ "columns", Method.columns }, .{ "rows", Method.rows } }) |field| {
            const atom = c.JS_NewAtom(self.engine.context, field[0]);
            defer c.JS_FreeAtom(self.engine.context, atom);
            if (c.JS_DefinePropertyGetSet(self.engine.context, terminal, atom, try self.function(generation, field[1]), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return error.JavaScriptException;
        }
        try self.put(tui, "terminal", c.JS_DupValue(self.engine.context, terminal));
        var args = [_]c.JSValue{ tui, theme, footer_data };
        const component = if (c.JS_IsArray(factory)) try self.arrayComponent(factory, theme) else try self.engine.checked(c.JS_Call(self.engine.context, factory, c.pi_js_undefined(), if (slot == .footer) 3 else 2, &args));
        var transferred = false;
        errdefer if (!transferred) {
            const original = if (self.engine.captured_exception) |value| c.JS_DupValue(self.engine.context, value) else null;
            if (components.callMethod(self.engine, component, "dispose", &.{}, true) catch null) |value| self.engine.freeValue(value);
            self.engine.freeValue(component);
            if (original) |value| {
                if (self.engine.captured_exception) |previous| self.engine.freeValue(previous);
                self.engine.captured_exception = value;
            }
        };
        if (!c.JS_IsObject(component)) return error.InvalidNativeWidgetComponent;
        const render = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, component, "render"));
        defer self.engine.freeValue(render);
        if (!c.JS_IsFunction(self.engine.context, render)) return error.InvalidNativeWidgetComponent;
        if (!self.owners.contains(owner)) return error.StaleNativeExtensionOwner;
        const owned_key = try self.engine.gpa.dupe(u8, key);
        errdefer self.engine.gpa.free(owned_key);
        const replacement: Entry = .{ .key = owned_key, .owner = owner, .generation = generation, .component = component, .placement = placement, .slot = slot };
        if (replace_index) |previous| {
            const old = self.entries.items[previous];
            self.entries.items[previous] = replacement;
            self.engine.gpa.free(old.key);
            self.engine.freeValue(old.component);
        } else try self.entries.append(self.engine.gpa, replacement);
        transferred = true;
    }
    pub fn pumpDirty(self: *Manager) !bool {
        if (self.busy) return false;
        self.busy = true;
        defer self.busy = false;
        if (self.invalidate_pending) {
            self.invalidate_pending = false;
            for (self.entries.items) |entry| {
                if (try components.callMethod(self.engine, entry.component, "invalidate", &.{}, true)) |value| self.engine.freeValue(value);
            }
        }
        var changed = false;
        for (self.entries.items) |*entry| {
            if (!entry.dirty or !entry.mounted) continue;
            entry.dirty = false;
            const held = c.JS_DupValue(self.engine.context, entry.component);
            defer self.engine.freeValue(held);
            const rendered_width = self.width;
            var args = [_]c.JSValue{c.JS_NewInt64(self.engine.context, @intCast(rendered_width))};
            defer self.engine.freeValue(args[0]);
            const result = (try components.callMethod(self.engine, held, "render", &args, false)).?;
            defer self.engine.freeValue(result);
            var frame = try components.normalize(self.engine, result);
            defer frame.deinit();
            try self.publishWidth(entry.*, frame, rendered_width);
            changed = true;
        }
        return changed;
    }
    pub fn resize(self: *Manager, width: usize, height: usize) !void {
        self.dimensions_controlled = true;
        self.width = @min(width, 16384);
        self.height = @min(height, 16384);
        self.invalidate_pending = true;
        for (self.entries.items) |*entry| {
            entry.dirty = true;
        }
        _ = try self.pumpDirty();
    }
};

fn slotFailureTrace(engine: *engine_mod.Engine) !void {
    const error_value = engine.captured_exception orelse return error.MissingOriginalSlotError;
    const message = try engine.checked(c.JS_GetPropertyStr(engine.context, error_value, "message"));
    defer engine.freeValue(message);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const trace = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "slotTrace"));
    defer engine.freeValue(trace);
    const push = try engine.checked(c.JS_GetPropertyStr(engine.context, trace, "push"));
    defer engine.freeValue(push);
    var args = [_]c.JSValue{message};
    const result = try engine.checked(c.JS_Call(engine.context, push, trace, 1, &args));
    engine.freeValue(result);
}
test "native persistent header footer replay original dispose retry factory throw visibility retained roots and clear" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var capture = try std.json.parseFromSlice(std.json.Value, engine.gpa, @embedFile("fixtures/persistent-slots-original-7fb.json"), .{});
    defer capture.deinit();
    const Capture = struct {
        latest: ?protocol.Record = null,
        fn receive(raw: ?*anyopaque, value: protocol.Record) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            const owned = try value.clone(std.testing.allocator);
            if (self.latest) |*previous| previous.deinit();
            self.latest = owned;
        }
        fn deinit(self: *@This()) void {
            if (self.latest) |*value| value.deinit();
        }
    };
    inline for (.{ protocol.Slot.header, protocol.Slot.footer }) |slot| {
        var records: Capture = .{};
        defer records.deinit();
        var manager = try Manager.init(engine);
        manager.attach();
        defer manager.deinit();
        manager.record_context = &records;
        manager.record_fn = Capture.receive;
        try manager.addOwner(1);
        const factories = try engine.eval("globalThis.slotTrace=[];globalThis.slotThrows=true;globalThis.oldSlot={name:'old',render(){return ['old']},dispose(){slotTrace.push('dispose-old');if(slotThrows){slotThrows=false;throw Error('dispose-once')}}};({old(...args){slotTrace.push('factory-old:'+args.length);return oldSlot},bad(){slotTrace.push('factory-throw');throw Error('factory-original')},replacement(){slotTrace.push('factory-new');return {name:'new',render(){return ['new']},dispose(){slotTrace.push('dispose-new')}}}})", "persistent-source-factories.js", c.JS_EVAL_TYPE_GLOBAL);
        defer engine.freeValue(factories);
        const expected = capture.value.object.get("observations").?.object.get(@tagName(slot)).?.array.items;
        for (expected, 0..) |step, index| {
            const factory = if (index == 4) c.pi_js_undefined() else try engine.checked(c.JS_GetPropertyStr(engine.context, factories, switch (index) {
                0 => "old",
                1, 2 => "bad",
                else => "replacement",
            }));
            defer engine.freeValue(factory);
            if (index == 1 or index == 2) {
                try std.testing.expectError(error.JavaScriptException, manager.setSlot(1, "", factory, .aboveEditor, c.pi_js_undefined(), slot, c.pi_js_undefined()));
                try slotFailureTrace(engine);
            } else try manager.setSlot(1, "", factory, .aboveEditor, c.pi_js_undefined(), slot, c.pi_js_undefined());
            if (index == 0 or index == 3) _ = try manager.pumpDirty();
            if (slot == .footer and index == 2) {
                try std.testing.expect(records.latest.?.frame != null);
                try std.testing.expectEqual(@as(usize, 0), records.latest.?.frame.?.lines.len);
            }
            if (index == 4) try std.testing.expect(records.latest.?.frame == null);
            c.JS_RunGC(engine.runtime);
            const observed = try engine.eval("slotTrace", "persistent-source-trace.js", c.JS_EVAL_TYPE_GLOBAL);
            defer engine.freeValue(observed);
            const actual = try engine.stringify(observed);
            defer engine.gpa.free(actual);
            var filtered: std.ArrayList(std.json.Value) = .empty;
            defer filtered.deinit(engine.gpa);
            for (step.object.get("events").?.array.items) |event| if (!std.mem.eql(u8, event.string, "render")) try filtered.append(engine.gpa, event);
            const encoded = try std.json.Stringify.valueAlloc(engine.gpa, filtered.items, .{});
            defer engine.gpa.free(encoded);
            try std.testing.expectEqualStrings(encoded, actual);
            const visible = step.object.get("visible").?.array.items;
            if (index == 4) {
                try std.testing.expectEqual(@as(usize, 0), manager.entries.items.len);
                try std.testing.expectEqualStrings("builtin", visible[0].string);
            } else {
                try std.testing.expectEqual(@as(usize, 1), manager.entries.items.len);
                const entry = manager.entries.items[0];
                const name = try engine.checked(c.JS_GetPropertyStr(engine.context, entry.component, "name"));
                defer engine.freeValue(name);
                const retained = try engine.toString(name);
                defer engine.gpa.free(retained);
                try std.testing.expectEqualStrings(step.object.get("retained").?.string, retained);
                try std.testing.expectEqual(visible.len > 0, entry.mounted);
                if (entry.mounted) try std.testing.expectEqualStrings(visible[0].string, retained);
            }
        }
    }
}

test "native retained widgets reproduce authentic upstream factory width replace clear and disposal outcomes" {
    const gpa = std.testing.allocator;
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    var manager = try Manager.init(engine);
    manager.attach();
    defer manager.deinit();
    try manager.addOwner(7);
    const Receiver = struct {
        records: std.ArrayList(protocol.Record) = .empty,
        fn record(raw: ?*anyopaque, value: protocol.Record) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            var owned = try value.clone(std.testing.allocator);
            errdefer owned.deinit();
            try self.records.append(std.testing.allocator, owned);
        }
    };
    var received: Receiver = .{};
    defer {
        for (received.records.items) |*record| record.deinit();
        received.records.deinit(gpa);
    }
    manager.record_context = &received;
    manager.record_fn = Receiver.record;
    manager.width = 55;
    manager.height = 20;
    var fixture = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/widget-original-7fb.json"), .{});
    defer fixture.deinit();
    const setup = try engine.eval("globalThis.trace=[];globalThis.theme={name:'fixture-theme',fg:(token,text)=>'<'+token+'>'+text+'</'+token+'>'}", "widget-capture-setup.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(setup);
    const source = try gpa.dupeZ(u8, fixture.value.object.get("factory").?.string);
    defer gpa.free(source);
    const evaluated = try engine.eval(source, "widget-authentic-factory.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(evaluated);
    const factory = try engine.eval("widgetFactory", "widget-factory.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(factory);
    const theme = try engine.eval("theme", "widget-theme.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(theme);
    try manager.set(7, "counter", factory, .belowEditor, theme);
    c.JS_RunGC(engine.runtime);
    _ = try manager.pumpDirty();
    const change = try engine.eval("changeWidget()", "widget-change.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(change);
    _ = try manager.pumpDirty();
    try manager.resize(31, 20);
    try manager.set(7, "counter", factory, .aboveEditor, theme);
    _ = try manager.pumpDirty();
    try manager.set(7, "counter", c.pi_js_undefined(), .aboveEditor, theme);
    c.JS_RunGC(engine.runtime);
    const actual_value = try engine.eval("trace", "widget-trace.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(actual_value);
    const actual = try engine.stringify(actual_value);
    defer gpa.free(actual);
    var expected: std.Io.Writer.Allocating = .init(gpa);
    defer expected.deinit();
    try std.json.Stringify.value(fixture.value.object.get("trace").?, .{}, &expected.writer);
    // requestRender is deferred onto the owner thread; original host captures
    // its call explicitly whereas native manager marks a dirty retained root.
    const replaced_trace = try std.mem.replaceOwned(u8, gpa, expected.written(), ",[\"requestRender\"]", "");
    defer gpa.free(replaced_trace);
    try std.testing.expectEqualStrings(replaced_trace, actual);
    try std.testing.expectEqual(@as(usize, 0), manager.entries.items.len);
    try std.testing.expectEqual(@as(usize, 6), received.records.items.len);
    inline for (.{ .{ 0, "first" }, .{ 1, "changed" }, .{ 2, "resized" }, .{ 4, "replaced" } }) |item| {
        try std.testing.expectEqualStrings(fixture.value.object.get(item[1]).?.array.items[0].string, received.records.items[item[0]].frame.?.lines[0]);
    }
    try std.testing.expect(received.records.items[0].placement == .belowEditor and received.records.items[4].placement == .aboveEditor);
    try std.testing.expect(received.records.items[3].frame == null and received.records.items[5].frame == null);
}

fn widgetOwnershipCase(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    var manager = try Manager.init(engine);
    manager.attach();
    defer manager.deinit();
    try manager.addOwner(1);
    const factory = try engine.eval("(tui,theme)=>{globalThis.requestWidgetRender=tui.requestRender;return {render(width){return ['owned:'+width]},invalidate(){},dispose(){}}}", "widget-allocation.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(factory);
    const theme = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(theme);
    try manager.set(1, "owned", factory, .aboveEditor, theme);
    _ = try manager.pumpDirty();
    try manager.resize(31, 20);
    manager.removeOwner(1);
    c.JS_RunGC(engine.runtime);
    const late = try engine.eval("requestWidgetRender()", "widget-stale.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(late);
    try std.testing.expectEqual(@as(usize, 0), manager.entries.items.len);
}
test "native retained widget roots terminal getters replacement and stale callbacks release all host allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, widgetOwnershipCase, .{});
}

test "native widget factory render and dispose preserve original exception identity" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var manager = try Manager.init(engine);
    manager.attach();
    defer manager.deinit();
    try manager.addOwner(1);
    const factory = try engine.eval("globalThis.originalWidgetError={owned:true};(tui)=>({render(){throw originalWidgetError},dispose(){throw originalWidgetError}})", "widget-original-exception.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(factory);
    try manager.set(1, "throws", factory, .aboveEditor, c.pi_js_undefined());
    try std.testing.expectError(error.JavaScriptException, manager.pumpDirty());
    const original = try engine.eval("originalWidgetError", "widget-error-identity.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(original);
    _ = engine.throwCaptured();
    const thrown = c.JS_GetException(engine.context);
    defer engine.freeValue(thrown);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, thrown));
    try std.testing.expectError(error.JavaScriptException, manager.set(1, "throws", c.pi_js_undefined(), .aboveEditor, c.pi_js_undefined()));
    _ = engine.throwCaptured();
    const disposal = c.JS_GetException(engine.context);
    defer engine.freeValue(disposal);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, disposal));
    try std.testing.expectEqual(@as(usize, 1), manager.entries.items.len);
    manager.removeOwner(1);
    try std.testing.expectEqual(@as(usize, 0), manager.entries.items.len);
}

test "native widget throw once retry replace clear and reset retain original map roots and exceptions" {
    const gpa = std.testing.allocator;
    var fixture = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/widget-original-7fb.json"), .{});
    defer fixture.deinit();
    for (fixture.value.object.get("throws").?.array.items) |expected| {
        const engine = try engine_mod.Engine.init(gpa, .{});
        defer engine.deinit();
        var manager = try Manager.init(engine);
        manager.attach();
        defer manager.deinit();
        try manager.addOwner(1);
        const setup = try engine.eval("globalThis.attempts=0;globalThis.nextFactories=0;globalThis.reason={};globalThis.throwComponent={render(){return ['retained']},dispose(){attempts++;if(attempts===1)throw reason}};globalThis.nextFactory=()=>{nextFactories++;return {render(){return ['replacement']},dispose(){}}};()=>throwComponent", "widget-retry-setup.js", c.JS_EVAL_TYPE_GLOBAL);
        defer engine.freeValue(setup);
        const replacement = try engine.eval("nextFactory", "widget-retry-next.js", c.JS_EVAL_TYPE_GLOBAL);
        defer engine.freeValue(replacement);
        const component = try engine.eval("throwComponent", "widget-retained-root.js", c.JS_EVAL_TYPE_GLOBAL);
        defer engine.freeValue(component);
        const reason = try engine.eval("reason", "widget-retained-error.js", c.JS_EVAL_TYPE_GLOBAL);
        defer engine.freeValue(reason);
        try manager.set(1, "throws", setup, .aboveEditor, c.pi_js_undefined());
        const operation = expected.object.get("operation").?.string;
        const reset = std.mem.eql(u8, operation, "reset");
        const replace = std.mem.eql(u8, operation, "replace");
        if (reset) try std.testing.expectError(error.JavaScriptException, manager.clear()) else try std.testing.expectError(error.JavaScriptException, manager.set(1, "throws", if (replace) replacement else c.pi_js_undefined(), .aboveEditor, c.pi_js_undefined()));
        _ = engine.throwCaptured();
        const thrown = c.JS_GetException(engine.context);
        defer engine.freeValue(thrown);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, thrown) == expected.object.get("identity").?.bool);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, component, manager.entries.items[0].component) == expected.object.get("retained").?.bool);
        c.JS_RunGC(engine.runtime);
        _ = try manager.pumpDirty();
        if (reset) try manager.clear() else try manager.set(1, "throws", if (replace) replacement else c.pi_js_undefined(), .aboveEditor, c.pi_js_undefined());
        const counters = try engine.eval("[attempts,nextFactories]", "widget-retry-counters.js", c.JS_EVAL_TYPE_GLOBAL);
        defer engine.freeValue(counters);
        const encoded = try engine.stringify(counters);
        defer gpa.free(encoded);
        const wanted = try std.fmt.allocPrint(gpa, "[{d},{d}]", .{ expected.object.get("attempts").?.integer, expected.object.get("nextFactories").?.integer });
        defer gpa.free(wanted);
        try std.testing.expectEqualStrings(wanted, encoded);
        try std.testing.expectEqual(@as(usize, @intCast(expected.object.get("remaining").?.integer)), manager.entries.items.len);
    }
}

test "native widget resize during frame publication defers callbacks and retains exact rendered width" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var manager = try Manager.init(engine);
    manager.attach();
    defer manager.deinit();
    try manager.addOwner(1);
    const Receiver = struct {
        manager: *Manager,
        count: usize = 0,
        fn record(raw: ?*anyopaque, value: protocol.Record) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (value.frame == null) return;
            self.count += 1;
            if (self.count == 1) {
                try std.testing.expectEqual(@as(usize, 80), value.width);
                try std.testing.expectEqualStrings("render:80", value.frame.?.lines[0]);
                try self.manager.resize(31, 20);
            } else {
                try std.testing.expectEqual(@as(usize, 31), value.width);
                try std.testing.expectEqualStrings("render:31", value.frame.?.lines[0]);
            }
        }
    };
    var received: Receiver = .{ .manager = &manager };
    manager.record_context = &received;
    manager.record_fn = Receiver.record;
    const factory = try engine.eval("()=>({render(width){return ['render:'+width]},invalidate(){}})", "widget-deferred-resize.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(factory);
    try manager.set(1, "resize", factory, .aboveEditor, c.pi_js_undefined());
    _ = try manager.pumpDirty();
    _ = try manager.pumpDirty();
    try std.testing.expectEqual(@as(usize, 2), received.count);
}
