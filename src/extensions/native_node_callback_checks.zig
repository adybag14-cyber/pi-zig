//! Native assertion dispatch for the actual callback/request owners.
//! These operations terminate the host process through the direct C owner.
//! A failed Maybe and an internal assertion retain their distinct diagnostics.
const callbacks = @import("native_node_callback_scope.zig");
const failure = @import("native_node_check_failure.zig");
const Environment = callbacks.Environment;
const Check = callbacks.Check;

fn assertion(message: [*:0]const u8, file: [*:0]const u8,
    function: [*:0]const u8) failure.AssertionInfo
{
    return .{ .message = message, .file_line = file, .function = function };
}

/// The location names the selected source operation or, for additional native
/// port invariants, its actual port owner. No guest property is inspected here.
fn description(site: Check) failure.AssertionInfo {
    return switch (site) {
        .invalid_resource => assertion("valid object resource and typed init handle",
            "src/extensions/native_node_callback_scope.zig", "callback resource invariant"),
        .invalid_async_id => assertion("async_id >= -1 && trigger_async_id >= -1",
            "src/extensions/native_node_callback_scope.zig", "pushAsyncContext"),
        .missing_hook_function => assertion("actual hook function is installed",
            "src/extensions/native_node_callback_scope.zig", "async hook binding"),
        .missing_tick_callback => assertion("!tick_callback.IsEmpty()",
            "src/api/callback.cc", "InternalCallbackScope::Close"),
        .outer_execution_id => assertion("(env_->execution_async_id()) == (0)",
            "src/api/callback.cc", "InternalCallbackScope::Close"),
        .outer_trigger_id => assertion("(env_->trigger_async_id()) == (0)",
            "src/api/callback.cc", "InternalCallbackScope::Close"),
        .callback_scope_order => assertion("environment.callback_scope == self && environment.callback_depth != 0",
            "src/extensions/native_node_callback_scope.zig", "Scope::deinit"),
        .invalid_provider => assertion("provider != PROVIDER_NONE",
            "src/extensions/native_node_async_wrap_state.zig", "AsyncWrap provider invariant"),
        .invalid_wrap_brand => assertion("valid native AsyncWrap identity and reference count",
            "src/extensions/native_node_async_wrap_state.zig", "AsyncWrap identity invariant"),
        .unfinished_live_fs_request => assertion("!(!finished_) || (!env()->can_call_into_js())",
            "src/node_file-inl.h", "FSReqPromise::~FSReqPromise"),
        .request_before_bootstrap => assertion("env->has_run_bootstrapping_code()",
            "src/req_wrap-inl.h", "ReqWrapBase::ReqWrapBase"),
        .negative_waiting_requests => assertion("(request_waiting_) >= (0)",
            "src/env-inl.h", "Environment::DecreaseWaitingRequestCounter"),
        .waiting_requests_after_io_join => assertion("environment.requests.waiting == 0",
            "src/extensions/native_node_request_state.zig", "Registry::requireNoWaiting"),
        .request_queue_during_disarm => assertion("environment.requests.head == null && environment.requests.tail == null",
            "src/extensions/native_node_request_state.zig", "Registry::requireEmpty"),
        .callback_argument_count => assertion("callback argument count fits the native Call ABI",
            "src/extensions/native_node_make_callback.zig", "InternalMakeCallback"),
        .callback_argument_buffer => assertion("(ret) != nullptr",
            "src/util-inl.h", "UncheckedRealloc"),
        .binding_data_slot_occupied => assertion("!binding_data_store_[binding_index]",
            "src/node_realm-inl.h", "Realm::AddBindingData"),
        .fs_read_argument_count => assertion("(argc) >= (5)",
            "src/node_file.cc", "Read"),
        .fs_read_fd => assertion("args[0]->IsInt32()",
            "src/node_file.cc", "Read"),
        .fs_read_buffer => assertion("Buffer::HasInstance(args[1])",
            "src/node_file.cc", "Read"),
        .fs_read_offset_integer => assertion("IsSafeJsInt(args[2])",
            "src/node_file.cc", "Read"),
        .fs_read_offset_nonnegative => assertion("(off_64) >= (0)",
            "src/node_file.cc", "Read"),
        .fs_read_offset_bounds => assertion("(static_cast<uint64_t>(off_64)) < (buffer_length)",
            "src/node_file.cc", "Read"),
        .fs_read_length => assertion("args[3]->IsInt32()",
            "src/node_file.cc", "Read"),
        .fs_read_range => assertion("Buffer::IsWithinBounds(off, len, buffer_length)",
            "src/node_file.cc", "Read"),
        .fs_read_position => assertion("IsSafeJsInt(args[4]) || args[4]->IsBigInt()",
            "src/node_file.cc", "Read"),
        .fs_read_request => assertion("(req_wrap_async) != nullptr",
            "src/node_file.cc", "Read"),
        .async_stack_binding_set, .promise_property_settle,
        .binding_data_property_set => unreachable,
    };
}

pub fn fail(environment: *Environment, site: Check) anyerror {
    // The Environment entitlement remains live through a failed operation.
    // A violated lifetime is itself a native invariant, even without a VM.
    const engine = environment.engine orelse failure.assertion(null,
        assertion("environment.engine != null",
            "src/extensions/native_node_callback_checks.zig", "fail"));
    switch (site) {
        .async_stack_binding_set, .promise_property_settle,
        .binding_data_property_set => failure.maybeCheck(engine, null),
        else => failure.assertion(engine, description(site)),
    }
}

/// The genuine Environment options owner supplies abort_on_uncaught. This
/// operation reads the actual current execution ID before native diagnostics.
pub fn corruptedStack(environment: *Environment, expected: f64,
    abort_on_uncaught: bool) anyerror
{
    const engine = environment.engine orelse failure.assertion(null,
        assertion("environment.engine != null",
            "src/extensions/native_node_callback_checks.zig", "corruptedStack"));
    failure.corruptedAsyncStack(engine, environment.executionAsyncId(),
        expected, abort_on_uncaught);
}
