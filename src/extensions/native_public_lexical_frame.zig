//! Native lexical slots for actual public async bodies. Open capture cells
//! retain the activation; completion closes each cell before retiring locals.
const v = @import("native_public_values.zig");
const c = v.c;
const Engine = v.em.Engine;
const Scope = v.Scope;

pub fn Frame(comptime Names: type) type {
    return struct {
        engine: *Engine,
        owner: c.JSValue,
        values: [@typeInfo(Names).@"enum".fields.len]c.JSValue,
        ready: [@typeInfo(Names).@"enum".fields.len]bool,
        captures: [@typeInfo(Names).@"enum".fields.len]c.JSValue,
        closed: bool = false,
        const Self = @This();
        const Cell = struct {
            engine: *Engine,
            activation: c.JSValue,
            value: c.JSValue,
            ready: bool,
            position: usize,
            name: [*:0]const u8,
        };
        pub fn create(s: *Scope) !*Self {
            var class_id: c.JSClassID = 0;
            if (c.JS_NewClassID(s.engine.runtime, &class_id) == 0) return error.OutOfMemory;
            const definition: c.JSClassDef = .{ .class_name = "Private public lexical activation", .finalizer = finalizer, .gc_mark = mark };
            if (c.JS_NewClass(s.engine.runtime, class_id, &definition) < 0) return error.OutOfMemory;
            const owner = try v.objectClass(s, class_id);
            if (c.pi_js_native_memory_reserve(s.engine.native_memory_owner, @sizeOf(Self)) == 0) return error.OutOfMemory;
            errdefer c.pi_js_native_memory_release(s.engine.native_memory_owner, @sizeOf(Self));
            const self = try s.engine.gpa.create(Self);
            self.* = .{ .engine = s.engine, .owner = owner, .values = @splat(c.pi_js_undefined()), .ready = @splat(false), .captures = @splat(c.pi_js_undefined()) };
            _ = c.JS_SetOpaque(owner, self);
            return self;
        }
        pub fn from(value: c.JSValue) *Self {
            return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
        }
        fn finalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
            const self: *Self = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
            for (self.values) |root| c.JS_FreeValueRT(runtime, root);
            for (self.captures) |root| c.JS_FreeValueRT(runtime, root);
            const engine = self.engine;
            engine.gpa.destroy(self);
            c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Self));
        }
        fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
            const self: *Self = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
            for (self.values) |root| c.JS_MarkValue(runtime, root, visit);
            for (self.captures) |root| c.JS_MarkValue(runtime, root, visit);
        }
        pub fn get(self: *const Self, comptime name: Names) c.JSValue { return self.values[@intFromEnum(name)]; }
        pub fn take(self: *Self, comptime name: Names, incoming: anyerror!c.JSValue) !void {
            try self.takeAt(@intFromEnum(name), incoming);
        }
        fn takeAt(self: *Self, position: usize, incoming: anyerror!c.JSValue) !void {
            const next = try incoming;
            const previous = self.values[position];
            self.values[position] = next;
            self.ready[position] = true;
            var completion = v.owned.Completion.initVoid(self.engine, {});
            completion.release(previous);
            return completion.finishVoid();
        }
        pub fn copy(self: *Self, comptime name: Names, value: c.JSValue) !void {
            return self.take(name, c.JS_DupValue(self.engine.context, value));
        }
        pub fn clear(self: *Self, comptime name: Names) !void { return self.take(name, c.pi_js_undefined()); }
        pub fn retire(self: *Self, comptime name: Names, completion: *v.owned.Completion) void {
            const position = @intFromEnum(name); const value = self.values[position];
            self.values[position] = c.pi_js_undefined(); self.ready[position] = true;
            completion.release(value);
        }
        pub fn capture(self: *Self, s: *Scope, comptime name: Names, source_name: [*:0]const u8) !c.JSValue {
            const position = @intFromEnum(name);
            if (!c.JS_IsUndefined(self.captures[position])) return v.own(s, c.JS_DupValue(self.engine.context, self.captures[position]));
            var class_id: c.JSClassID = 0;
            if (c.JS_NewClassID(self.engine.runtime, &class_id) == 0) return error.OutOfMemory;
            const definition: c.JSClassDef = .{ .class_name = "Private public lexical binding", .finalizer = cellFinalizer, .gc_mark = cellMark };
            if (c.JS_NewClass(self.engine.runtime, class_id, &definition) < 0) return error.OutOfMemory;
            const owner = try v.objectClass(s, class_id);
            if (c.pi_js_native_memory_reserve(self.engine.native_memory_owner, @sizeOf(Cell)) == 0) return error.OutOfMemory;
            errdefer c.pi_js_native_memory_release(self.engine.native_memory_owner, @sizeOf(Cell));
            const cell = try self.engine.gpa.create(Cell);
            cell.* = .{ .engine = self.engine, .activation = c.JS_DupValue(self.engine.context, self.owner), .value = c.pi_js_undefined(), .ready = false, .position = position, .name = source_name };
            _ = c.JS_SetOpaque(owner, cell);
            self.captures[position] = c.JS_DupValue(self.engine.context, owner);
            return owner;
        }
        fn cellFrom(value: c.JSValue) *Cell {
            return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
        }
        fn cellFinalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
            const cell: *Cell = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
            c.JS_FreeValueRT(runtime, cell.value);
            c.JS_FreeValueRT(runtime, cell.activation);
            const engine = cell.engine;
            engine.gpa.destroy(cell);
            c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Cell));
        }
        fn cellMark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
            const cell: *Cell = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
            c.JS_MarkValue(runtime, cell.value, visit);
            c.JS_MarkValue(runtime, cell.activation, visit);
        }
        pub fn read(s: *Scope, binding: c.JSValue) !c.JSValue {
            const cell = cellFrom(binding);
            const activation = if (c.JS_IsUndefined(cell.activation)) null else from(cell.activation);
            const initialized = if (activation) |a| a.ready[cell.position] else cell.ready;
            if (!initialized) return uninitialized(s, cell.name);
            const value = if (activation) |a| a.values[cell.position] else cell.value;
            return v.own(s, c.JS_DupValue(s.engine.context, value));
        }
        pub fn assign(binding: c.JSValue, incoming: anyerror!c.JSValue) !void {
            const cell = cellFrom(binding);
            if (!c.JS_IsUndefined(cell.activation)) return from(cell.activation).takeAt(cell.position, incoming);
            const next = try incoming;
            const previous = cell.value;
            cell.value = next; cell.ready = true;
            var completion = v.owned.Completion.initVoid(cell.engine, {});
            completion.release(previous);
            return completion.finishVoid();
        }
        /// No allocation or guest call is permitted while closing an activation.
        /// A cell retains just its binding after return, like a closed JSVarRef.
        pub fn close(self: *Self, completion: *v.owned.Completion) void {
            if (self.closed) return;
            self.closed = true;
            for (self.captures, 0..) |root, position| {
                if (c.JS_IsUndefined(root)) continue;
                const cell = cellFrom(root);
                cell.value = c.JS_DupValue(self.engine.context, self.values[position]);
                cell.ready = self.ready[position];
                const activation = cell.activation;
                cell.activation = c.pi_js_undefined();
                completion.release(activation);
            }
            for (&self.captures) |*root| { const value = root.*; root.* = c.pi_js_undefined(); completion.release(value); }
            // BCDF frees uncaptured function locals in declaration order.
            for (&self.values) |*root| { const value = root.*; root.* = c.pi_js_undefined(); completion.release(value); }
        }
    };
}
fn uninitialized(s: *Scope, name: [*:0]const u8) anyerror {
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; boundary.begin() catch |err| return err;
    const generation = s.engine.native_allocation_generation;
    const raw = c.JS_ThrowReferenceError(s.engine.context, "%s is not initialized", name);
    _ = s.engine.nativeCallbackResult(c.pi_js_undefined());
    if (c.JS_HasException(s.engine.context)) {
        const reason = c.JS_GetException(s.engine.context);
        const tag = c.pi_js_native_allocation_error_generation(reason);
        const distance = tag -% generation;
        if (tag != 0 and distance != 0 and distance <= s.engine.native_allocation_generation -% generation)
            c.JS_SetUncatchableError(s.engine.context, reason);
        _ = c.JS_Throw(s.engine.context, reason);
    }
    _ = boundary.finishValue(s, raw) catch |err| return err;
    unreachable;
}
