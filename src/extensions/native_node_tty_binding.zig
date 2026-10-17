//! Actual branded tty_wrap/Socket adoption, source-only and unselected.
//! Native is a concrete console/descriptor owner, not a guest callback table.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const f = @import("native_node_module_callable.zig");
const h = @import("native_node_tty_values.zig");
/// Compose with the canonical Socket module and the actual native endpoint
/// owner. No Socket/descriptor implementation is substituted by this binding.
/// Native.Provider API: retain/release/isTTY/acquire; Native.Endpoint API:
/// hooks/bindSocket/mark/release/getWindowSize/setRawMode/setBlocking/fd.
/// acquire returns {.endpoint=*Endpoint}|{.failure=actual native error}; the
/// Provider publishes that actual error into ctx via installFailure on owner.
pub fn Binding(comptime Socket: type, comptime Native: type) type {
    return struct {
        const Self = @This();
        const ProviderState = struct {
            engine: *v.em.Engine,
            native: *Native.Provider,
            socket: *Socket.Provider,
            socket_constructor: c.JSValue,
            tty_class: c.JSClassID,
            provider_class: c.JSClassID,
        };
        const Handle = struct { engine: *v.em.Engine, owner: c.JSValue, endpoint: *Native.Endpoint, adopted: bool = false };
        pub const Exports = struct {
            tty: c.JSValue,
            is_tty: c.JSValue,
            pub fn deinit(self: Exports, engine: *v.em.Engine) void { engine.freeValue(self.tty); engine.freeValue(self.is_tty); }
        };
        pub const Prepared = struct {
            engine: *v.em.Engine, exports: Exports, owner: c.JSValue, state: *ProviderState,
            committed: bool = false,
            pub fn deinit(self: *Prepared) void { self.exports.deinit(self.engine); self.engine.freeValue(self.owner); }
            /// Last fallible publication after the public TTY carrier has been
            /// constructed. A failed outer initializer consumes no adopter slot.
            pub fn commit(self: *Prepared) !void {
                if (self.committed) return error.NativeTtyBindingAlreadyCommitted;
                try self.state.socket.addHandleAdopter(.{ .brand = self.state.tty_class, .owner = self.owner, .context = self.state, .resolve = resolve });
                self.committed = true;
            }
        };
        fn providerFinalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
            const state: *ProviderState = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
            state.native.release();
            c.JS_FreeValueRT(runtime, state.socket_constructor);
            const engine = state.engine;
            engine.gpa.destroy(state);
            c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(ProviderState));
        }
        fn providerMark(runtime: ?*c.JSRuntime, value: c.JSValue, visitor: ?*const c.JS_MarkFunc) callconv(.c) void {
            const state: *ProviderState = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
            c.JS_MarkValue(runtime, state.socket_constructor, visitor);
            state.native.mark(runtime, visitor);
        }
        fn handleFinalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
            const state: *Handle = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
            // Native endpoint release initiates exact owned retirement. It
            // does not block, call the VM, or close an outstanding IO handle.
            state.endpoint.release();
            c.JS_FreeValueRT(runtime, state.owner);
            const engine = state.engine;
            engine.gpa.destroy(state);
            c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Handle));
        }
        fn handleMark(runtime: ?*c.JSRuntime, value: c.JSValue, visitor: ?*const c.JS_MarkFunc) callconv(.c) void {
            const state: *Handle = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
            c.JS_MarkValue(runtime, state.owner, visitor);
            state.endpoint.mark(runtime, visitor);
        }
        fn id(engine: *v.em.Engine, value: c.JSValue) !c.JSClassID {
            var number: u32 = 0;
            if (c.JS_ToUint32(engine.context, &number, value) < 0) return v.js.capture(engine);
            try h.pending(engine); return number;
        }
        fn provider(engine: *v.em.Engine, roots: []const c.JSValue) !*ProviderState {
            const expected = try id(engine, roots[1]);
            if (c.JS_GetClassID(roots[0]) != expected) return error.NativeTtyProviderBrand;
            const value: *ProviderState = @ptrCast(@alignCast(c.JS_GetOpaque(roots[0], expected) orelse return error.NativeTtyProviderBrand));
            if (value.engine != engine or value.provider_class != expected) return error.NativeTtyProviderEngine;
            return value;
        }
        fn handle(engine: *v.em.Engine, receiver: c.JSValue, state: *ProviderState) !*Handle {
            // Known immutable class selection always precedes any opaque cast.
            if (c.JS_GetClassID(receiver) != state.tty_class) return error.NativeTtyHandleBrand;
            const value: *Handle = @ptrCast(@alignCast(c.JS_GetOpaque(receiver, state.tty_class) orelse return error.NativeTtyHandleBrand));
            if (value.engine != engine or !c.JS_IsStrictEqual(engine.context, value.owner, stateOwner(state, value.owner))) return error.NativeTtyHandleEngine;
            return value;
        }
        fn stateOwner(state: *ProviderState, candidate: c.JSValue) c.JSValue {
            // candidate is a native retained holder, not a mutable module cell.
            return if (c.JS_GetOpaque(candidate, state.provider_class) == @as(?*anyopaque, @ptrCast(state))) candidate else c.pi_js_undefined();
        }
        /// socket pointer must remain at its stable owner address. Its actual
        /// constructor is traced by this holder; clone/ref semantics are the
        /// canonical provider's responsibility, never a copied empty registry.
        pub fn create(engine: *v.em.Engine, socket: *Socket.Provider, native: *Native.Provider) !Exports {
            var prepared = try prepare(engine, socket, native); defer prepared.deinit();
            try prepared.commit();
            return .{ .tty = c.JS_DupValue(engine.context, prepared.exports.tty), .is_tty = c.JS_DupValue(engine.context, prepared.exports.is_tty) };
        }
        pub fn prepare(engine: *v.em.Engine, socket: *Socket.Provider, native: *Native.Provider) !Prepared {
            engine.native_exception_diagnostics_suppressed += 1;
            defer engine.native_exception_diagnostics_suppressed -= 1;
            try h.pending(engine);
            if (socket.engine != engine) return error.NativeTtySocketEngine;
            var s: v.Scope = .{ .engine = engine }; defer s.deinit();
            var provider_class: c.JSClassID = 0;
            if (c.JS_NewClassID(engine.runtime, &provider_class) == 0) return error.OutOfMemory;
            const provider_definition: c.JSClassDef = .{ .class_name = "Native TTY Provider", .finalizer = providerFinalize, .gc_mark = providerMark };
            if (c.JS_NewClass(engine.runtime, provider_class, &provider_definition) < 0) return error.OutOfMemory;
            var tty_class: c.JSClassID = 0;
            if (c.JS_NewClassID(engine.runtime, &tty_class) == 0) return error.OutOfMemory;
            const handle_definition: c.JSClassDef = .{ .class_name = "TTY", .finalizer = handleFinalize, .gc_mark = handleMark };
            if (c.JS_NewClass(engine.runtime, tty_class, &handle_definition) < 0) return error.OutOfMemory;
            if (c.pi_js_native_memory_reserve(engine.native_memory_owner, @sizeOf(ProviderState)) == 0) return error.OutOfMemory;
            var attached = false;
            errdefer if (!attached) c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(ProviderState));
            const state = try engine.gpa.create(ProviderState);
            errdefer if (!attached) engine.gpa.destroy(state);
            const owner = try s.own(try engine.checked(c.JS_NewObjectClass(engine.context, provider_class)));
            native.retain();
            state.* = .{ .engine = engine, .native = native, .socket = socket, .socket_constructor = c.JS_DupValue(engine.context, socket.constructor), .tty_class = tty_class, .provider_class = provider_class };
            _ = c.JS_SetOpaque(owner, state); attached = true;
            const roots = [_]c.JSValue{ owner, c.JS_NewUint32(engine.context, provider_class) };
            const tty = try s.own(try f.create(engine, "TTY", 2, true, construct, &roots));
            const prototype = try h.get(&s, tty, "prototype");
            inline for (.{ .{ "getWindowSize", 1, getWindowSize }, .{ "setRawMode", 1, setRawMode }, .{ "setBlocking", 1, setBlocking } }) |entry| {
                try h.put(engine, prototype, entry[0], try s.own(try f.create(engine, entry[0], entry[1], false, entry[2], &roots)));
            }
            const fd_atom = c.JS_NewAtom(engine.context, "fd");
            if (fd_atom == c.JS_ATOM_NULL) return v.js.capture(engine);
            defer c.JS_FreeAtom(engine.context, fd_atom);
            const fd_getter = try s.own(try f.create(engine, "get fd", 0, false, getFd, &roots));
            // Source StreamBase uses ReadOnly|DontDelete|DontEnum accessor.
            // It is never a writable fd/HANDLE token installed on the instance.
            if (c.JS_DefinePropertyGetSet(engine.context, prototype, fd_atom, c.JS_DupValue(engine.context, fd_getter), c.pi_js_undefined(), c.JS_PROP_THROW) < 0) return v.js.capture(engine);
            const is_tty = try s.own(try f.create(engine, "isTTY", 1, false, isTTY, &roots));
            return .{ .engine = engine, .exports = .{ .tty = c.JS_DupValue(engine.context, tty), .is_tty = c.JS_DupValue(engine.context, is_tty) }, .owner = c.JS_DupValue(engine.context, owner), .state = state };
        }
        fn construct(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            try h.pending(engine);
            const state = try provider(engine, roots);
            // Internal Source calls always use new. Do not reproduce a V8
            // private-API CHECK abort for an invalid external ordinary call.
            if (!c.JS_IsObject(receiver)) return v.js.typeError(engine, "TTY native constructor requires new");
            var fd: i32 = 0;
            if (c.JS_ToInt32(engine.context, &fd, h.arg(args, 0)) < 0) return v.js.capture(engine);
            try h.pending(engine);
            if (fd < 0) return error.NativeTtyDescriptorRequired;
            var s: v.Scope = .{ .engine = engine }; defer s.deinit();
            const prototype = try s.own(try h.success(engine, try engine.checked(c.JS_GetPrototype(engine.context, receiver))));
            const object = try s.own(try engine.checked(c.JS_NewObjectProtoClass(engine.context, prototype, state.tty_class)));
            if (c.pi_js_native_memory_reserve(engine.native_memory_owner, @sizeOf(Handle)) == 0) return error.OutOfMemory;
            var attached = false;
            defer if (!attached) c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Handle));
            const retained = try engine.gpa.create(Handle);
            defer if (!attached) engine.gpa.destroy(retained);
            switch (try state.native.acquire(fd)) {
                .failure => |failure| {
                    // Actual OS error ctx, in Source binding order. No generic
                    // JavaScript error or fabricated descriptor replaces it.
                    try state.native.installFailure(engine, h.arg(args, 1), failure);
                    return c.JS_DupValue(engine.context, object);
                },
                .endpoint => |endpoint| {
                    retained.* = .{ .engine = engine, .owner = c.JS_DupValue(engine.context, roots[0]), .endpoint = endpoint };
                    _ = c.JS_SetOpaque(object, retained); attached = true;
                    return c.JS_DupValue(engine.context, object);
                },
            }
        }
        fn resolve(raw: *anyopaque, engine: *v.em.Engine, receiver: c.JSValue, actual_handle: c.JSValue, _: c.JSValue) !Socket.Hooks {
            const state: *ProviderState = @ptrCast(@alignCast(raw));
            if (state.engine != engine) return error.NativeTtyProviderEngine;
            const actual = try handle(engine, actual_handle, state);
            if (actual.adopted) return error.NativeTtyHandleAlreadyAdopted;
            // bindSocket retains/marks the SAME canonical receiver and native
            // owner callbacks use its genuine completions, never a dummy peer.
            try actual.endpoint.bindSocket(engine, state.socket, receiver);
            actual.adopted = true;
            return actual.endpoint.hooks();
        }
        fn isTTY(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            try h.pending(engine);
            const state = try provider(engine, roots);
            var fd: i32 = 0;
            if (c.JS_ToInt32(engine.context, &fd, h.arg(args, 0)) < 0) return v.js.capture(engine);
            try h.pending(engine);
            return c.pi_js_bool(engine.context, @intFromBool(fd >= 0 and state.native.isTTY(fd)));
        }
        fn getFd(engine: *v.em.Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            try h.pending(engine);
            const actual = handle(engine, receiver, try provider(engine, roots)) catch |err| {
                if (err == error.NativeTtyHandleBrand) return c.JS_NewInt32(engine.context, -4071); // Source UV_EINVAL on unbound native wrapper.
                return err;
            };
            return c.JS_NewInt32(engine.context, actual.endpoint.fd());
        }
        fn getWindowSize(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            try h.pending(engine);
            const actual = try handle(engine, receiver, try provider(engine, roots));
            const result = actual.endpoint.getWindowSize();
            switch (result) {
                .failed => |failure| return c.JS_NewInt32(engine.context, failure),
                .size => |size| {
                    const array = h.arg(args, 0);
                    if (!c.JS_IsArray(array)) return v.js.typeError(engine, "TTY getWindowSize requires an array");
                    // Native binding uses Set, not data-property definition.
                    if (c.JS_SetPropertyUint32(engine.context, array, 0, c.JS_NewInt32(engine.context, size.columns)) < 0) return v.js.capture(engine);
                    try h.pending(engine);
                    if (c.JS_SetPropertyUint32(engine.context, array, 1, c.JS_NewInt32(engine.context, size.rows)) < 0) return v.js.capture(engine);
                    try h.pending(engine);
                    return c.JS_NewInt32(engine.context, 0);
                },
            }
        }
        fn setRawMode(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            try h.pending(engine);
            const actual = try handle(engine, receiver, try provider(engine, roots));
            const flag = c.JS_IsBool(h.arg(args, 0)) and c.JS_ToBool(engine.context, h.arg(args, 0)) == 1;
            return c.JS_NewInt32(engine.context, try actual.endpoint.setRawMode(flag));
        }
        fn setBlocking(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            try h.pending(engine);
            const actual = try handle(engine, receiver, try provider(engine, roots));
            const flag = c.JS_IsBool(h.arg(args, 0)) and c.JS_ToBool(engine.context, h.arg(args, 0)) == 1;
            return c.JS_NewInt32(engine.context, try actual.endpoint.setBlocking(flag));
        }
    };
}
