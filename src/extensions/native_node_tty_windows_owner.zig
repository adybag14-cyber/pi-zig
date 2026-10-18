//! Actual VM-owner TTY endpoint assembly. Kernel workers retain ONLY fixed
//! native lease/wake tokens; classes/callbacks remain on this owner thread.
//! Unselected source; canonical modules are injected once by Root assembly.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const h = @import("native_node_tty_values.zig");
const consoles = @import("native_node_tty_windows_console.zig");
const leases = @import("native_node_tty_windows_leases.zig");
const reads = @import("native_node_tty_windows_input_worker.zig");
const keys = @import("native_node_tty_windows_keys.zig");
const dispatch = @import("native_node_tty_dispatch.zig");
const uv = @import("native_node_tty_windows_errors.zig");
const mode_authority = @import("native_node_tty_windows_modes.zig");
/// Hub/Scheduler/Wake/Socket are the ACTUAL FS modules, not compatible dummy
/// records. This generic avoids importing an unrelated old scheduler snapshot.
pub fn Owner(comptime Socket: type, comptime Hub: type, comptime Scheduler: type, comptime Wake: type, comptime ClosePool: type) type {
    return struct {
        const Registry = leases.Registry(ClosePool, Wake);
        const ReadPool = reads.Pool(Wake, Registry);
        pub const Admission = union(enum) { endpoint: *Endpoint, failure: consoles.Failure };
        pub const Inputs = struct {
            /// Genuine captured internal/errors ErrnoException constructor.
            errno_exception: c.JSValue,
            /// Actual process object for genuine console resize signal delivery.
            process: c.JSValue,
            /// Actual authenticated EMBEDDED frontend capture, when present.
            /// Remote worker pipe hydration is not admitted as this capability.
            frontend_mode: ?@import("native_node_tty_frontend_mode.zig").Snapshot = null,
            /// Host-owned isolated qualification opt-in, never worker metadata.
            qualification_admission: bool = false,
        };
        pub const Provider = struct {
            engine: *v.em.Engine, hub: *Hub.Hub,
            socket: Socket.Provider,
            wake: Wake.Ref,
            errno_exception: c.JSValue, process: c.JSValue,
            references: usize = 1, stopping: bool = false,
            qualification_admission: bool = false,
            endpoints: [leases.maximum_leases]?*Endpoint = .{null} ** leases.maximum_leases,
            pub fn create(engine: *v.em.Engine, canonical_socket: *const Socket.Provider, inputs: Inputs) !*Provider {
                engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
                try h.pending(engine);
                if (!c.JS_IsFunction(engine.context, inputs.errno_exception) or !c.JS_IsObject(inputs.process)) return error.RequiredActualTtyOwnerDependencies;
                const hub = try Hub.get(engine); try hub.assertOwner();
                try mode_authority.attach(engine, inputs.frontend_mode);
                var mode_attached = true; defer if (mode_attached) mode_authority.release();
                const cloned = try canonical_socket.clone(engine);
                var clone_owned = true;
                defer if (clone_owned) { engine.freeValue(cloned.constructor); engine.freeValue(cloned.states); };
                const wake = try Scheduler.acquireNativeWake(engine); errdefer Wake.release(wake);
                if (c.pi_js_native_memory_reserve(engine.native_memory_owner, @sizeOf(Provider)) == 0) return error.OutOfMemory;
                var attached = false; errdefer if (!attached) c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Provider));
                const self = try engine.gpa.create(Provider); errdefer if (!attached) engine.gpa.destroy(self);
                self.* = .{ .engine = engine, .hub = hub, .socket = cloned, .wake = wake,
                    .errno_exception = c.JS_DupValue(engine.context, inputs.errno_exception), .process = c.JS_DupValue(engine.context, inputs.process), .qualification_admission = inputs.qualification_admission };
                var values_owned = true;
                defer if (values_owned) { engine.freeValue(self.errno_exception); engine.freeValue(self.process); };
                try hub.addResource(.{ .raw = self, .stop = stop, .stopped = stopped, .poll = poll, .referenced = referenced });
                self.retain(); // Hub resource survives until real owner teardown.
                clone_owned = false; values_owned = false; attached = true; mode_attached = false; return self;
            }
            pub fn retain(self: *Provider) void { self.references += 1; }
            /// Only the unpublished assembler may invoke this rollback. It
            /// removes the real resource and drops its native ownership once;
            /// caller/binding references remain valid through their deinit.
            pub fn rollbackUnpublished(self: *Provider) void {
                if (self.stopping) return;
                self.hub.removeResource(self);
                stop(self); stopped(self);
            }
            pub fn release(self: *Provider) void {
                std.debug.assert(self.references != 0); self.references -= 1;
                if (self.references != 0) return;
                for (self.endpoints) |entry| std.debug.assert(entry == null);
                const engine = self.engine;
                // May run from a native holder finalizer while the runtime is
                // freeing its context; no stale JSContext is dereferenced.
                c.JS_FreeValueRT(engine.runtime, self.socket.constructor);
                c.JS_FreeValueRT(engine.runtime, self.socket.states);
                c.JS_FreeValueRT(engine.runtime, self.errno_exception);
                c.JS_FreeValueRT(engine.runtime, self.process);
                Wake.release(self.wake);
                engine.gpa.destroy(self); c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Provider));
            }
            pub fn mark(self: *Provider, runtime: ?*c.JSRuntime, visitor: ?*const c.JS_MarkFunc) void {
                c.JS_MarkValue(runtime, self.socket.constructor, visitor);
                c.JS_MarkValue(runtime, self.socket.states, visitor);
                c.JS_MarkValue(runtime, self.errno_exception, visitor);
                c.JS_MarkValue(runtime, self.process, visitor);
                // These values have ONE owning mark edge, here. Handle.mark
                // must not mark the same native-held references a second time.
                for (self.endpoints) |entry| if (entry) |endpoint| endpoint.markOwned(runtime, visitor);
            }
            pub fn isTTY(self: *Provider, fd: c_int) bool { return !self.stopping and consoles.isTTY(fd); }
            pub fn acquire(self: *Provider, fd: c_int) !Admission {
                try self.hub.assertOwner(); if (self.stopping) return error.NativeTtyOwnerStopped;
                var index: ?usize = null;
                for (self.endpoints, 0..) |entry, i| if (entry == null) { index = i; break; };
                const slot = index orelse return error.NativeTtyEndpointCapacity;
                const engine = self.engine;
                if (c.pi_js_native_memory_reserve(engine.native_memory_owner, @sizeOf(Endpoint)) == 0) return error.OutOfMemory;
                var attached = false; defer if (!attached) c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Endpoint));
                const endpoint = try engine.gpa.create(Endpoint); defer if (!attached) engine.gpa.destroy(endpoint);
                const admitted = if (self.qualification_admission) try Registry.admitForQualification(fd, self.wake) else try Registry.admit(fd, self.wake);
                const native = switch (admitted) { .reference => |value| value, .failure => |failure| return .{ .failure = failure } };
                // No fallible allocation follows actual native ownership.
                endpoint.* = .{ .provider = self, .native = native, .table_index = slot, .references = 2, .writable = (Registry.kind(native) catch unreachable) == .output, .weak_socket = c.pi_js_undefined() }; // table + returned handle
                self.retain(); self.endpoints[slot] = endpoint; attached = true; return .{ .endpoint = endpoint };
            }
            pub fn installFailure(self: *Provider, engine: *v.em.Engine, context: c.JSValue, failure: consoles.Failure) !void {
                if (self.engine != engine) return error.NativeTtyProviderEngine;
                if (!c.JS_IsObject(context)) return; // Source CollectUVExceptionInfo.
                var s: v.Scope = .{ .engine = engine }; defer s.deinit();
                const number = switch (failure) { .windows => |code| uv.fromWindows(code), .crt => @intFromEnum(uv.Code.EBADF), .not_tty => @intFromEnum(uv.Code.EBADF) };
                const code = std.Enums.fromInt(uv.Code, number) orelse return error.RequiredUnknownNativeUvErrorFormatting;
                // Actual env.cc CollectExceptionInfo order: errno, code,
                // message, optional path/dest, then syscall.
                try contextSet(&s, context, "errno", c.JS_NewInt32(engine.context, number));
                try contextSet(&s, context, "code", try s.text(@tagName(code)));
                try contextSet(&s, context, "message", try s.text(uv.message(code)));
                try contextSet(&s, context, "syscall", try s.text("uv_tty_init"));
            }
            fn contextSet(s: *v.Scope, target: c.JSValue, name: []const u8, value: c.JSValue) !void {
                const key = try s.text(name);
                // env.cc Object::Set does not request strict assignment. An
                // ordinary false result is ignored; an actual setter throw is
                // still normalized before any subsequent context operation.
                if (c.JS_SetPropertyValue(s.engine.context, target, c.JS_DupValue(s.engine.context, key), c.JS_DupValue(s.engine.context, value), 0) < 0) return v.js.capture(s.engine);
                try h.pending(s.engine);
            }
            fn stop(raw: *anyopaque) void {
                const self: *Provider = @ptrCast(@alignCast(raw)); if (self.stopping) return;
                self.stopping = true;
                for (self.endpoints) |entry| if (entry) |endpoint| endpoint.stopNative();
                mode_authority.release();
            }
            fn stopped(raw: *anyopaque) void {
                const self: *Provider = @ptrCast(@alignCast(raw));
                for (&self.endpoints) |*entry| if (entry.*) |endpoint| { entry.* = null; endpoint.release(); };
                self.release();
            }
            fn referenced(raw: *anyopaque) bool {
                const self: *Provider = @ptrCast(@alignCast(raw)); if (self.stopping) return false;
                for (self.endpoints) |entry| if (entry) |endpoint| if ((!endpoint.closed and endpoint.closing) or endpoint.final_token != null or (endpoint.referenced and (endpoint.read_ticket != null or endpoint.demand))) return true;
                return false;
            }
            fn poll(raw: *anyopaque) !bool {
                const self: *Provider = @ptrCast(@alignCast(raw));
                const engine = self.engine;
                engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
                try h.pending(engine); try self.hub.assertOwner();
                if (self.stopping) return false;
                // One observable guest delivery per resource checkpoint. The
                // Hub's real pending-job gate drains microtasks before reentry.
                for (self.endpoints) |entry| if (entry) |endpoint| if (try endpoint.drive()) return true;
                return false;
            }
        };
        pub const Endpoint = struct {
            provider: *Provider, native: Registry.Ref, table_index: usize,
            references: usize,
            weak_socket: c.JSValue,
            strong: ?Socket.Owned = null,
            bound: bool = false, referenced: bool = true, demand: bool = false, read_ended: bool = false,
            closing: bool = false, closed: bool = false, detached: bool = false,
            writable: bool = false, final_token: ?u64 = null,
            read_ticket: ?ReadPool.Ticket = null, read_epoch: u64 = 0,
            mode_epoch: u64 = 0, destroy_token: ?u64 = null,
            key_state: keys.State = .{}, bytes: [8192]u8 = undefined,
            last_errno: i32 = @intFromEnum(uv.Code.EIO), last_syscall: []const u8 = "read",
            pub fn fd(self: *Endpoint) c_int { return if (self.closed) @intFromEnum(uv.Code.EINVAL) else Registry.requestedFd(self.native) catch @intFromEnum(uv.Code.EINVAL); }
            pub fn mark(_: *Endpoint, _: ?*c.JSRuntime, _: ?*const c.JS_MarkFunc) void {} // Provider owns exactly one edge.
            fn markOwned(self: *Endpoint, runtime: ?*c.JSRuntime, visitor: ?*const c.JS_MarkFunc) void {
                c.JS_MarkValue(runtime, self.weak_socket, visitor);
                if (self.strong) |owned| { c.JS_MarkValue(runtime, owned.socket, visitor); c.JS_MarkValue(runtime, owned.holder, visitor); }
            }
            pub fn release(self: *Endpoint) void {
                std.debug.assert(self.references != 0); self.references -= 1;
                if (self.references == 1 and !self.provider.stopping and !self.closed) { self.closing = true; self.cancelRead(); _ = Registry.requestClose(self.native) catch false; }
                if (self.references != 0) return;
                const owner = self.provider; const engine = owner.engine;
                std.debug.assert(self.read_ticket == null);
                self.dropStrong(); c.JS_FreeValueRT(engine.runtime, self.weak_socket);
                Registry.release(self.native);
                engine.gpa.destroy(self); c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Endpoint)); owner.release();
            }
            fn retain(self: *Endpoint) void { self.references += 1; }
            pub fn bindSocket(self: *Endpoint, engine: *v.em.Engine, actual: *Socket.Provider, receiver: c.JSValue) !void {
                if (engine != self.provider.engine or actual != &self.provider.socket or self.bound or self.closing) return error.NativeTtyEndpointBinding;
                var s: v.Scope = .{ .engine = engine }; defer s.deinit();
                const weak = try h.construct(&s, engine.native_weak_ref_constructor.?, &.{receiver});
                self.weak_socket = c.JS_DupValue(engine.context, weak); self.bound = true;
            }
            fn socket(self: *Endpoint) !?Socket.Owned {
                if (self.strong) |owned| return owned.clone();
                if (!self.bound or self.detached) return null;
                const engine = self.provider.engine; var s: v.Scope = .{ .engine = engine }; defer s.deinit();
                const actual = try h.call(&s, engine.native_weak_ref_deref.?, self.weak_socket, &.{});
                if (c.JS_IsUndefined(actual)) return null;
                return try self.provider.socket.own(actual);
            }
            fn holdStrong(self: *Endpoint) !void {
                if (self.strong != null) return;
                self.strong = try self.socket() orelse return error.NativeTtySocketCollected;
            }
            fn dropStrong(self: *Endpoint) void {
                if (self.strong) |owned| {
                    self.strong = null; const runtime = self.provider.engine.runtime;
                    c.JS_FreeValueRT(runtime, owned.socket); c.JS_FreeValueRT(runtime, owned.holder);
                }
            }
            fn cancelRead(self: *Endpoint) void { self.demand = false; if (self.read_ticket) |ticket| ReadPool.requestCancel(ticket) catch {}; }
            fn startRead(self: *Endpoint) !void {
                if (!self.demand or self.read_ended or self.closing or self.detached or self.read_ticket != null) return;
                const raw_mode = try Registry.rawMode(self.native);
                // Source retains unfinished raw key bytes across mode changes,
                // but normal line mode does not consume those raw-key bytes.
                if (raw_mode and self.key_state.pending()) return;
                if (try Registry.kind(self.native) != .input) { self.last_errno = @intFromEnum(uv.Code.EINVAL); self.last_syscall = "read"; return error.NativeTtyNativeFailure; }
                try self.holdStrong();
                const ticket = try ReadPool.reserve(self.provider.wake, self.native);
                var submitted = false; defer if (!submitted) ReadPool.releaseUnsubmitted(ticket) catch {};
                try ReadPool.submit(ticket, if (raw_mode) .raw_records else .line);
                self.read_epoch = self.mode_epoch; self.read_ticket = ticket; submitted = true;
            }
            pub fn getWindowSize(self: *Endpoint) union(enum) { size: consoles.Size, failed: i32 } {
                const result = Registry.getWindowSize(self.native) catch return .{ .failed = @intFromEnum(uv.Code.EBADF) };
                return switch (result) { .size => |size| .{ .size = size }, .failed => |failure| .{ .failed = uv.fromWindows(failure) } };
            }
            pub fn setBlocking(self: *Endpoint, flag: bool) !i32 { try Registry.setBlocking(self.native, flag); return 0; }
            pub fn setRawMode(self: *Endpoint, flag: bool) !i32 {
                // Native uv_tty_set_mode checks the genuine readable flag
                // BEFORE its unchanged-mode fast path, even for flag=false.
                if (try Registry.kind(self.native) != .input or self.closed) return @intFromEnum(uv.Code.EINVAL);
                if (self.mode_epoch == std.math.maxInt(u64)) return error.NativeTtyModeEpochExhausted;
                if (try Registry.rawMode(self.native) == flag) return 0;
                if (flag) mode_authority.markRawVtAttempt();
                if (self.read_ticket) |ticket| if (try ReadPool.cancelNow(ticket)) |failure| { self.demand = false; return uv.fromWindows(failure); };
                if (try Registry.applyRawModeAfterCancelRequest(self.native, flag)) |failure| { self.demand = false; return uv.fromWindows(failure); }
                self.mode_epoch += 1;
                return 0;
            }
            fn writeSync(raw: *anyopaque, bytes: []const u8, metadata: Socket.SyncWriteMetadata) !Socket.SyncWriteResult {
                const self: *Endpoint = @ptrCast(@alignCast(raw));
                const plan = try dispatch.plan(self.provider.engine, metadata.source, metadata.encoding, bytes.len);
                if (plan.too_large) { self.last_errno = @intFromEnum(uv.Code.ENOBUFS); self.last_syscall = "write"; return .{ .acceptedBytes = 0, .dispatchedBytes = 0, .failure = error.NativeTtyNativeFailure }; }
                if (self.closing or !self.writable) {
                    self.last_errno = if (self.closing) @intFromEnum(uv.Code.EBADF) else @intFromEnum(uv.Code.EPIPE); self.last_syscall = "write";
                    return .{ .acceptedBytes = 0, .dispatchedBytes = plan.dispatchedBytes(true), .failure = error.NativeTtyNativeFailure };
                }
                // No VM or guest entry occurs inside the native console lock.
                const result = Registry.writeBlocking(self.native, bytes) catch |err| {
                    // Only an actual nonwritable native endpoint maps to the
                    // Source UV write failure. Missing translator/protocol/
                    // resource failures must never pretend to be Win32 EBADF.
                    if (err != error.NativeTtyWriteAdmission and err != error.NativeTtyNotWritable) return err;
                    self.last_errno = @intFromEnum(uv.Code.EPIPE);
                    self.last_syscall = "write";
                    return .{ .acceptedBytes = 0, .dispatchedBytes = plan.dispatchedBytes(true), .failure = error.NativeTtyNativeFailure };
                };
                if (result.failure) |failure| {
                    self.last_errno = uv.fromWindows(failure); self.last_syscall = "write";
                    return .{ .acceptedBytes = result.confirmed_bytes, .dispatchedBytes = plan.dispatchedBytes(true), .failure = error.NativeTtyNativeFailure };
                }
                return .{ .acceptedBytes = result.accepted_bytes.?, .dispatchedBytes = plan.dispatchedBytes(false) };
            }
            fn read(raw: *anyopaque) !void { const self: *Endpoint = @ptrCast(@alignCast(raw)); if (self.read_ended) return; self.demand = true; try self.startRead(); }
            fn write(_: *anyopaque, _: []const u8, _: u64) !void { return error.NativeTtyRequiresSynchronousWriteDispatch; }
            fn finish(raw: *anyopaque, token: u64) !bool {
                const self: *Endpoint = @ptrCast(@alignCast(raw));
                // win/stream.c203: only an already nonwritable/shutting/closing
                // native handle returns synchronous ENOTCONN. A writable TTY
                // clears its writable flag and inserts a native pending req;
                // it performs NO pipe FlushFileBuffers or endpoint close.
                if (!self.writable or self.closing) return true;
                try self.holdStrong();
                self.writable = false; self.final_token = token;
                Wake.notify(self.provider.wake); return false;
            }
            fn destroy(raw: *anyopaque, token: u64) !bool {
                const self: *Endpoint = @ptrCast(@alignCast(raw));
                if (self.destroy_token != null) return error.NativeTtyDestroyAlreadyPending;
                self.destroy_token = token; self.closing = true; self.cancelRead(); try self.holdStrong();
                _ = try Registry.requestClose(self.native); return false;
            }
            fn referencedHook(raw: *anyopaque, value: bool) !void { const self: *Endpoint = @ptrCast(@alignCast(raw)); self.referenced = value; }
            fn errorValue(raw: *anyopaque, engine: *v.em.Engine, failure: anyerror) !c.JSValue {
                const self: *Endpoint = @ptrCast(@alignCast(raw));
                if (engine != self.provider.engine) return error.NativeTtyEndpointEngine;
                if (failure != error.NativeTtyNativeFailure) return failure;
                var s: v.Scope = .{ .engine = engine }; defer s.deinit();
                return c.JS_DupValue(engine.context, try h.construct(&s, self.provider.errno_exception, &.{ c.JS_NewInt32(engine.context, self.last_errno), try s.text(self.last_syscall) }));
            }
            fn retainHook(raw: *anyopaque) void { const self: *Endpoint = @ptrCast(@alignCast(raw)); self.retain(); }
            fn releaseHook(raw: *anyopaque) void { const self: *Endpoint = @ptrCast(@alignCast(raw)); self.release(); }
            fn abandon(raw: *anyopaque) void { const self: *Endpoint = @ptrCast(@alignCast(raw)); self.closing = true; self.cancelRead(); _ = Registry.requestClose(self.native) catch false; }
            pub fn hooks(self: *Endpoint) Socket.Hooks { return .{ .context = self, .read = read, .write = write, .write_sync = writeSync, .finish = finish, .destroy = destroy, .referenced = referencedHook, .error_value = errorValue, .retain = retainHook, .abandon = abandon, .release = releaseHook }; }
            fn stopNative(self: *Endpoint) void {
                if (self.detached) return;
                self.detached = true; self.closing = true; self.demand = false;
                self.final_token = null; self.destroy_token = null;
                if (self.read_ticket) |ticket| { self.read_ticket = null; ReadPool.detach(ticket) catch {}; }
                Registry.detach(self.native) catch {};
                self.dropStrong();
                c.JS_FreeValueRT(self.provider.engine.runtime, self.weak_socket); self.weak_socket = c.pi_js_undefined();
            }
            fn drive(self: *Endpoint) !bool {
                if (self.detached) return false;
                if (self.final_token) |token| {
                    self.final_token = null; // consume before the real callback.
                    var owned = try self.socket() orelse { self.dropStrong(); self.closing = true; return true; }; defer owned.deinit();
                    if (!self.closing and self.read_ticket == null and !self.demand) self.dropStrong();
                    try owned.completeFinal(token, c.pi_js_null()); return true;
                }
                if (self.read_ticket) |ticket| if (try ReadPool.poll(ticket)) |completion| {
                    var count: usize = 0; var resize = false;
                    if (!completion.cancellation_requested and self.read_epoch == self.mode_epoch and !self.closing) switch (completion.outcome) {
                        .line => count = try keys.lineBytes(try ReadPool.lineUnits(ticket), &self.bytes),
                        .record => |records| if (records != 0) { resize = (try self.key_state.feed(try ReadPool.inputRecord(ticket))) == .resize; },
                        .failed => |failure| { self.last_errno = uv.fromWindows(failure); self.last_syscall = "read"; },
                        .cancelled_before_call => {},
                    };
                    self.read_ticket = null; try ReadPool.releaseCompleted(ticket);
                    if (completion.outcome == .failed and !completion.cancellation_requested and !self.closing) {
                        var owned = try self.socket() orelse { self.closing = true; return true; }; defer owned.deinit();
                        if (self.last_errno == @intFromEnum(uv.Code.EOF)) {
                            // Actual libuv UV_EOF is the readable terminal
                            // event, not ErrnoException('EOF') destruction.
                            // Publish once before guest push(null), so a
                            // throwing/reentrant callback cannot replay EOF.
                            self.read_ended = true; self.demand = false; self.dropStrong();
                            try owned.eof(); return true;
                        }
                        const reason = try errorValue(self, self.provider.engine, error.NativeTtyNativeFailure); defer self.provider.engine.freeValue(reason);
                        var s: v.Scope = .{ .engine = self.provider.engine }; defer s.deinit();
                        _ = try h.invoke(&s, owned.socket, "destroy", &.{reason}); return true;
                    }
                    if (count == 0 and self.key_state.pending() and self.demand and try Registry.rawMode(self.native)) count = self.key_state.drain(&self.bytes);
                    if (count != 0 and self.demand and !self.closing) {
                        var owned = try self.socket() orelse { self.closing = true; return true; }; defer owned.deinit();
                        self.demand = try owned.push(self.bytes[0..count]);
                        if (!self.demand) self.dropStrong() else {
                            try self.startRead();
                            if (self.key_state.pending() and !self.closing and try Registry.rawMode(self.native)) Wake.notify(self.provider.wake);
                        }
                        return true;
                    }
                    if (resize) {
                        // This is a real native WINDOW_BUFFER_SIZE_EVENT.
                        // Actual signal/resize ordering remains a qualification
                        // gate with the existing frontend/process signal owner.
                        var s: v.Scope = .{ .engine = self.provider.engine }; defer s.deinit();
                        _ = try h.invoke(&s, self.provider.process, "emit", &.{try s.text("SIGWINCH")}); return true;
                    }
                };
                if (self.closing and self.read_ticket == null and !self.closed) {
                    _ = try Registry.requestClose(self.native);
                    if (try Registry.pollClose(self.native)) |result| {
                        if (result == .failed) return error.NativeTtyCloseRetained;
                        self.closed = true;
                        if (self.destroy_token) |token| {
                            self.destroy_token = null;
                            var owned = try self.socket() orelse {
                                self.dropStrong(); self.provider.endpoints[self.table_index] = null; self.release(); return true;
                            }; defer owned.deinit();
                            self.dropStrong();
                            self.provider.endpoints[self.table_index] = null; self.release();
                            try owned.completeDestroy(token, c.pi_js_null()); return true;
                        }
                        self.dropStrong();
                        self.provider.endpoints[self.table_index] = null; self.release(); return true;
                    }
                }
                if (self.demand and self.key_state.pending() and !self.closing and try Registry.rawMode(self.native)) {
                    const count = self.key_state.drain(&self.bytes);
                    if (count != 0) {
                        var owned = try self.socket() orelse { self.closing = true; return true; }; defer owned.deinit();
                        self.demand = try owned.push(self.bytes[0..count]);
                        if (!self.demand) self.dropStrong() else {
                            try self.startRead();
                            if (self.key_state.pending() and !self.closing and try Registry.rawMode(self.native)) Wake.notify(self.provider.wake);
                        }
                        return true;
                    }
                }
                try self.startRead();
                if (!self.demand and !self.closing and self.read_ticket == null and self.final_token == null) self.dropStrong();
                return false;
            }
        };
    };
}
