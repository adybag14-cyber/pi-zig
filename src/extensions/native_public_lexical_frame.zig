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
        async_owner: bool = false,
        sync_owner: bool = false,
        captures_closed: bool = false,
        const Self = @This();
        const Cell = struct {
            engine: *Engine,
            activation: c.JSValue,
            lease: c.JSValue,
            value: c.JSValue,
            ready: bool,
            position: usize,
            name: [*:0]const u8,
            immutable_argument: bool,
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
        /// Install owner as the genuine AF state before capturing a binding.
        /// Async capture slots are borrowed, like JSStackFrame.var_refs: an
        /// unescaped callback must not be kept alive by this lookup table.
        pub fn createAsync(s: *Scope) !*Self {
            const self = try create(s);
            self.async_owner = true;
            return self;
        }
        /// Opted-in synchronous activations use a borrowed capture lookup.
        /// The C argument owner detaches captures before copied formals retire,
        /// then closes original locals through its separate terminal hook.
        pub fn createSync(s: *Scope) !*Self {
            const self = try create(s);
            self.sync_owner = true;
            return self;
        }
        fn borrowedCaptures(self: *const Self) bool { return self.async_owner or self.sync_owner; }
        pub fn from(value: c.JSValue) *Self {
            return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
        }
        fn finalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
            const self: *Self = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
            for (self.values) |root| c.JS_FreeValueRT(runtime, root);
            if (!self.borrowedCaptures()) {
                for (self.captures) |root| c.JS_FreeValueRT(runtime, root);
            }
            const engine = self.engine;
            engine.gpa.destroy(self);
            c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Self));
        }
        fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
            const self: *Self = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
            for (self.values) |root| c.JS_MarkValue(runtime, root, visit);
            if (!self.borrowedCaptures()) {
                for (self.captures) |root| c.JS_MarkValue(runtime, root, visit);
            }
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
            return self.captureBinding(s, name, source_name, false, c.pi_js_undefined());
        }
        /// A read-only Source parameter already lives in the genuine C argv.
        /// Its escaped cell owns the captured value; no original local slot is
        /// added, so unrelated arguments still retire in their original order.
        /// Use a dedicated Names slot, never take/copy/assign that binding, and
        /// install this async owner before calling the capture operation.
        pub fn captureImmutableArgument(self: *Self, s: *Scope, comptime name: Names, source_name: [*:0]const u8, value: c.JSValue) !c.JSValue {
            if (!self.async_owner) return error.ImmutableArgumentRequiresActualAsyncFrame;
            return self.captureBinding(s, name, source_name, true, value);
        }
        fn captureBinding(self: *Self, s: *Scope, comptime name: Names, source_name: [*:0]const u8, immutable_argument: bool, value: c.JSValue) !c.JSValue {
            const position = @intFromEnum(name);
            if (!c.JS_IsUndefined(self.captures[position])) return v.own(s, c.JS_DupValue(self.engine.context, self.captures[position]));
            var class_id: c.JSClassID = 0;
            if (c.JS_NewClassID(self.engine.runtime, &class_id) == 0) return error.OutOfMemory;
            const definition: c.JSClassDef = .{ .class_name = "Private public lexical binding", .finalizer = cellFinalizer, .gc_mark = cellMark };
            if (c.JS_NewClass(self.engine.runtime, class_id, &definition) < 0) return error.OutOfMemory;
            const owner = try v.objectClass(s, class_id);
            const lease = if (self.async_owner) try retainAsyncActivation(s, self.owner) else c.pi_js_undefined();
            if (c.pi_js_native_memory_reserve(self.engine.native_memory_owner, @sizeOf(Cell)) == 0) return error.OutOfMemory;
            errdefer c.pi_js_native_memory_release(self.engine.native_memory_owner, @sizeOf(Cell));
            const cell = try self.engine.gpa.create(Cell);
            cell.* = .{ .engine = self.engine, .activation = c.JS_DupValue(self.engine.context, self.owner), .lease = c.JS_DupValue(self.engine.context, lease), .value = if (immutable_argument) c.JS_DupValue(self.engine.context, value) else c.pi_js_undefined(), .ready = immutable_argument, .position = position, .name = source_name, .immutable_argument = immutable_argument };
            _ = c.JS_SetOpaque(owner, cell);
            self.captures[position] = if (self.borrowedCaptures()) owner else c.JS_DupValue(self.engine.context, owner);
            return owner;
        }
        fn retainAsyncActivation(s: *Scope, state: c.JSValue) !c.JSValue {
            var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
            // Exact non-guest allocation operation, using the same pending/
            // fresh-producer check as native_public_values allocation helpers.
            const generation = s.engine.native_allocation_generation;
            const value = c.JS_PiRetainNativeAsyncActivation(s.engine.context, state);
            _ = s.engine.nativeCallbackResult(c.pi_js_undefined());
            if (c.JS_HasException(s.engine.context)) {
                const reason = c.JS_GetException(s.engine.context);
                const tag = c.pi_js_native_allocation_error_generation(reason);
                const distance = tag -% generation;
                if (tag != 0 and distance != 0 and distance <= s.engine.native_allocation_generation -% generation)
                    c.JS_SetUncatchableError(s.engine.context, reason);
                _ = c.JS_Throw(s.engine.context, reason);
                var completion = v.owned.Completion.initValue(s.engine, @as(anyerror!c.JSValue, error.JavaScriptException));
                if (!c.JS_IsException(value)) completion.release(value);
                return boundary.finishValue(s, completion.finishValue());
            }
            return boundary.finishValue(s, value);
        }
        fn cellFrom(value: c.JSValue) *Cell {
            return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
        }
        fn cellFinalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
            const cell: *Cell = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
            const engine = cell.engine;
            const activation = cell.activation;
            const lease = cell.lease;
            cell.activation = c.pi_js_undefined(); cell.lease = c.pi_js_undefined();
            if (c.JS_IsLiveObject(runtime, activation)) {
                const parent = from(activation);
                if (parent.borrowedCaptures() and c.JS_IsStrictEqual(engine.context, parent.captures[cell.position], value))
                    parent.captures[cell.position] = c.pi_js_undefined();
            }
            c.JS_FreeValueRT(runtime, cell.value);
            c.JS_FreeValueRT(runtime, activation);
            // This can drop the invocation's final actual reference. The
            // borrowed lookup entry and both cell links are already detached.
            c.JS_FreeValueRT(runtime, lease);
            engine.gpa.destroy(cell);
            c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Cell));
        }
        fn cellMark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
            const cell: *Cell = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
            c.JS_MarkValue(runtime, cell.value, visit);
            c.JS_MarkValue(runtime, cell.activation, visit);
            c.JS_MarkValue(runtime, cell.lease, visit);
        }
        pub fn read(s: *Scope, binding: c.JSValue) !c.JSValue {
            const cell = cellFrom(binding);
            const activation = if (cell.immutable_argument or c.JS_IsUndefined(cell.activation)) null else from(cell.activation);
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
        /// Opt in with af.createResumable[Arrow]WithClose. The C terminal owner
        /// calls this after settlement and arguments, while state is borrowed.
        pub fn closeAtAsyncTerminal(engine: *Engine, owner: c.JSValue) !void {
            // A failed START can leave undefined; GC can already have finalized
            // an unreachable state before its coroutine's reaction finalizer.
            if (!c.JS_IsLiveObject(engine.runtime, owner)) return;
            const raw = c.JS_GetOpaque(owner, c.JS_GetClassID(owner)) orelse return;
            const self: *Self = @ptrCast(@alignCast(raw));
            var completion = v.owned.Completion.initVoid(engine, {});
            self.close(&completion);
            return completion.finishVoid();
        }
        /// Close one Source lexical binding at its scope exit. The original
        /// local remains in this activation until its next initialization or
        /// terminal retirement. A later capture creates a fresh cell.
        /// All lookup and cell links are cleared before releasing either
        /// activation edge; other open bindings keep their own actual leases.
        pub fn detach(self: *Self, comptime name: Names, completion: *v.owned.Completion) void {
            const position = @intFromEnum(name);
            const root = self.captures[position];
            const borrowed = self.borrowedCaptures();
            self.captures[position] = c.pi_js_undefined();
            if (c.JS_IsUndefined(root)) return;
            if (c.JS_IsLiveObject(self.engine.runtime, root)) {
                const cell = cellFrom(root);
                if (!cell.immutable_argument) {
                    cell.value = c.JS_DupValue(self.engine.context, self.values[position]);
                    cell.ready = self.ready[position];
                }
                const activation = cell.activation;
                const lease = cell.lease;
                cell.activation = c.pi_js_undefined(); cell.lease = c.pi_js_undefined();
                completion.release(activation);
                completion.release(lease);
            }
            if (!borrowed) completion.release(root);
        }
        /// No allocation or guest call is permitted while closing an activation.
        /// A cell retains just its binding after return, like a closed JSVarRef.
        pub fn detachCaptures(self: *Self, completion: *v.owned.Completion) void {
            if (self.captures_closed) return;
            self.captures_closed = true;
            for (self.captures, 0..) |root, position| {
                if (c.JS_IsUndefined(root) or !c.JS_IsLiveObject(self.engine.runtime, root)) continue;
                const cell = cellFrom(root);
                if (!cell.immutable_argument) {
                    cell.value = c.JS_DupValue(self.engine.context, self.values[position]);
                    cell.ready = self.ready[position];
                }
                const activation = cell.activation;
                const lease = cell.lease;
                cell.activation = c.pi_js_undefined(); cell.lease = c.pi_js_undefined();
                if (self.borrowedCaptures()) self.captures[position] = c.pi_js_undefined();
                completion.release(activation);
                completion.release(lease);
            }
            for (&self.captures) |*root| {
                const value = root.*; root.* = c.pi_js_undefined();
                if (!self.borrowedCaptures()) completion.release(value);
            }
        }
        pub fn close(self: *Self, completion: *v.owned.Completion) void {
            if (self.closed) return;
            self.closed = true;
            self.detachCaptures(completion);
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
