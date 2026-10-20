// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Actual FileHandle transfer state over the reviewed concrete native Handle.
//! The descriptor packet has its own native allocation and may outlive the
//! sending Engine. It never retains a JS value, Environment or UV service.
//!
//! Deserialization consumes the packet just like Source's unique_ptr parameter.
//! The actual full FileHandle template and worker message broker remain
//! required production assembly. No reduced constructor or fake receiver is
//! supplied here; the selected Handle.create absent-object path is unchanged.
const a = @import("native_node_argument_values.zig");
const native = @import("native_node_async_wrap_state.zig");
const binding = @import("native_node_fs_binding_data.zig");
const owner = @import("native_node_file_handle_owner.zig");
const check = @import("native_node_check_failure.zig");
const c = a.c;
const Scope = a.Scope;
const Native = opaque {};

/// Function addresses only: the actual process tracing owner supplies both.
/// They must remain callable after sender/receiver teardown and must perform
/// the original global trace operations. No no-op default is installed.
pub const Trace = extern struct {
    begin_sync_close: *const fn () callconv(.c) void,
    end_sync_close: *const fn () callconv(.c) void,
};
extern fn pi_node_file_handle_transfer_data_create(
    ?*c.JSContext, *anyopaque, c_int, *const Trace) *Native;
extern fn pi_node_file_handle_transfer_data_delete(
    ?*c.JSContext, ?*Native) void;
extern fn pi_node_file_handle_transfer_data_descriptor(
    ?*c.JSContext, *const Native) c_int;
extern fn pi_node_file_handle_transfer_data_take_descriptor(
    ?*c.JSContext, *Native) c_int;

pub const TransferMode = enum(u32) {
    disallow_clone_and_transfer = 0,
    transferable = 1,
};

/// Only these original live members govern admission. A stopped read's
/// current_read_ pointer alone does not add a new transfer prohibition.
pub fn getTransferMode(handle: *const owner.Handle) TransferMode {
    const state = &handle.read_state;
    return if (state.reading or state.closing or state.closed)
        .disallow_clone_and_transfer else .transferable;
}

/// Move-only by caller discipline, like the original unique_ptr. move() and
/// deserialize() clear the old slot before releasing or invoking another owner.
pub const Owned = struct {
    packet: ?*Native = null,

    pub fn move(self: *Owned) Owned {
        const result = self.*;
        self.packet = null;
        return result;
    }

    pub fn descriptor(self: *const Owned, context: ?*c.JSContext) ?c_int {
        const actual = self.packet orelse return null;
        return pi_node_file_handle_transfer_data_descriptor(context, actual);
    }

    /// May run without an Engine after cross-thread message abandonment.
    /// Supply a context only while that exact caller's entry is still alive.
    pub fn deinit(self: *Owned, context: ?*c.JSContext) void {
        const actual = self.packet orelse return;
        self.packet = null;
        pi_node_file_handle_transfer_data_delete(context, actual);
    }

    /// FileHandle::TransferData::Deserialize. A real missing BindingData
    /// consumes this packet and lets its native destructor close fd > 0.
    /// With BindingData, fd_ becomes -1 BEFORE actual template allocation;
    /// Source does not restore or close it if that later construction fails.
    pub fn deserialize(self: *Owned, s: *Scope, registry: *native.Registry,
        inputs: owner.Inputs) !?StrongHandle
    {
        const actual = self.packet orelse return error.ActualFileHandleTransferPacketRequired;
        self.packet = null;
        defer pi_node_file_handle_transfer_data_delete(s.engine.context, actual);
        if ((try registry.environment.requireEngine()) != s.engine)
            return error.ActualFileHandleTransferReceiverEnvironmentMismatch;
        const data = binding.get(registry) orelse return null;
        const descriptor_value = pi_node_file_handle_transfer_data_take_descriptor(
            s.engine.context, actual);
        const handle = try owner.Handle.create(s, data, descriptor_value,
            null, null, null, inputs);
        // Original BaseObjectPtr<BaseObject>{FileHandle::New(...)} strengthens
        // this SAME weak persistent before the caller's HandleScope retires.
        try handle.wrap.retainNative();
        return StrongHandle{ .handle = handle };
    }
};

/// The returned native BaseObjectPtr edge uses the existing State's actual
/// strong-persistent/refcount owner; no JS proxy or parallel lifetime is made.
pub const StrongHandle = struct {
    handle: ?*owner.Handle = null,

    pub fn get(self: *const StrongHandle) ?*owner.Handle { return self.handle; }

    pub fn move(self: *StrongHandle) StrongHandle {
        const result = self.*;
        self.handle = null;
        return result;
    }

    pub fn clone(self: *const StrongHandle) !StrongHandle {
        if (self.handle) |handle| try handle.wrap.retainNative();
        return self.*;
    }

    pub fn deinit(self: *StrongHandle) !void {
        const handle = self.handle orelse return;
        self.handle = null;
        // The last release can destroy the real native FileHandle.
        try handle.wrap.releaseNative();
    }
};

/// FileHandle::TransferForMessaging. Native allocation must finish before the
/// sender's sole closed_ transition. No AfterClose/EOF, descriptor reset,
/// close syscall, context-frame transfer or BindingData change is introduced.
pub fn transferForMessaging(s: *Scope, handle: *owner.Handle, trace: Trace) !Owned {
    if ((try handle.wrap.registry.environment.requireEngine()) != s.engine)
        return error.ActualFileHandleTransferSenderEnvironmentMismatch;
    if (getTransferMode(handle) == .disallow_clone_and_transfer)
        check.assertion(s.engine, .{
            .file_line = "src/node_file.cc:305",
            .message = "(GetTransferMode()) != (TransferMode::kDisallowCloneAndTransfer)",
            .function = "node::fs::FileHandle::TransferForMessaging",
        });
    const actual = pi_node_file_handle_transfer_data_create(
        s.engine.context, s.engine.native_memory_owner, handle.getFD(), &trace);
    handle.read_state.closed = true;
    return .{ .packet = actual };
}
