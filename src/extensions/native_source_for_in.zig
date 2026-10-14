//! Original Node observed for-in order, independent of guest VM opcode behavior.
//! Private ordinary/proxy prototype snapshots with live presence filtering. Broad exotic and legacy function metadata qualification remains pending.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const c = em.c;
pub const Iterator = struct {
    engine: *em.Engine,
    source: c.JSValue,
    seen: std.AutoHashMapUnmanaged(c.JSAtom, void) = .empty,
    keys: std.ArrayList(c.JSAtom) = .empty,
    position: usize = 0,
    native_steps: usize = 0,

    pub fn init(engine: *em.Engine, input: c.JSValue) !Iterator {
        var self: Iterator = .{ .engine = engine, .source = c.pi_js_undefined() };
        errdefer self.deinit();
        if (c.JS_IsNull(input) or c.JS_IsUndefined(input)) return self;
        self.source = try engine.checked(c.JS_ToObject(engine.context, input));
        var current = c.JS_DupValue(engine.context, self.source);
        defer engine.freeValue(current);
        while (!c.JS_IsNull(current)) {
            try self.tick();
            var names: [*c]c.JSPropertyEnum = null;
            var count: u32 = 0;
            const proxy = c.JS_IsProxy(current);
            const flags: c_int = c.JS_GPN_STRING_MASK | (if (proxy) @as(c_int, 0) else c.JS_GPN_SET_ENUM);
            if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, current, flags) < 0) return js.capture(engine);
            defer c.JS_FreePropertyEnum(engine.context, names, count);
            for (names[0..count]) |entry| {
                try self.tick();
                const atom = c.JS_DupAtom(engine.context, entry.atom);
                const slot = self.seen.getOrPut(engine.gpa, atom) catch |err| {
                    c.JS_FreeAtom(engine.context, atom);
                    return err;
                };
                if (slot.found_existing) {
                    c.JS_FreeAtom(engine.context, atom);
                } else if (proxy or entry.is_enumerable) {
                    try self.keys.append(engine.gpa, atom);
                }
            }
            const parent = try engine.checked(c.JS_GetPrototype(engine.context, current));
            engine.freeValue(current);
            current = parent;
        }
        return self;
    }
    pub fn deinit(self: *Iterator) void {
        var atoms = self.seen.keyIterator();
        while (atoms.next()) |atom| c.JS_FreeAtom(self.engine.context, atom.*);
        self.keys.deinit(self.engine.gpa);
        self.seen.deinit(self.engine.gpa);
        self.engine.freeValue(self.source);
    }
    pub fn next(self: *Iterator) !?c.JSValue {
        try self.tick();
        while (self.position < self.keys.items.len) {
            const atom = self.keys.items[self.position];
            self.position += 1;
            if (try self.presentNow(atom)) return self.engine.checked(c.JS_AtomToValue(self.engine.context, atom));
        }
        return null;
    }
    fn presentNow(self: *Iterator, atom: c.JSAtom) !bool {
        var traversed_proxy = false;
        var current = c.JS_DupValue(self.engine.context, self.source);
        defer self.engine.freeValue(current);
        while (!c.JS_IsNull(current)) {
            try self.tick();
            if (c.JS_IsProxy(current)) traversed_proxy = true;
            var descriptor: c.JSPropertyDescriptor = undefined;
            const found = c.JS_GetOwnProperty(self.engine.context, &descriptor, current, atom);
            if (found < 0) return js.capture(self.engine);
            if (found != 0) {
                defer self.engine.freeValue(descriptor.value);
                defer self.engine.freeValue(descriptor.getter);
                defer self.engine.freeValue(descriptor.setter);
                return !traversed_proxy or descriptor.flags & c.JS_PROP_ENUMERABLE != 0;
            }
            const parent = try self.engine.checked(c.JS_GetPrototype(self.engine.context, current));
            self.engine.freeValue(current);
            current = parent;
        }
        return false;
    }
    fn tick(self: *Iterator) !void {
        self.native_steps +|= 1;
        if (self.engine.cancelled.load(.acquire) or (self.native_steps % 256 == 0 and blk: {
            self.engine.interrupts +|= 1;
            break :blk self.engine.interrupts > self.engine.options.interrupt_budget;
        })) {
            _ = try self.engine.checked(c.JS_ThrowInternalError(self.engine.context, "interrupted"));
            unreachable;
        }
    }
};
