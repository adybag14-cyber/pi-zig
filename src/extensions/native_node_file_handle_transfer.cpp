// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
// Selected original FileHandle::TransferData native descriptor lifetime.
// Only the required global trace entrypoint addresses accompany fd_; no guest
// entitlement or sending Environment is retained by this native packet.
#include "native_node_file_handle_transfer.h"
#include "native_node_check_failure.h"
#include "native_node_diagnostic_context.hpp"
#include "native_node_standard_allocator.hpp"
#include "uv.h"

#include <cassert>
#include <cstddef>

struct PiNodeFileHandleTransferData final {
    explicit PiNodeFileHandleTransferData(
        int fd, PiNodeFileHandleTransferTrace trace)
        : fd_(fd), trace_(trace) {}

    PiNodeFileHandleTransferData(const PiNodeFileHandleTransferData&) = delete;
    PiNodeFileHandleTransferData& operator=(
        const PiNodeFileHandleTransferData&) = delete;

    static void* operator new(std::size_t bytes) {
        return pi_node::allocateStandard(bytes);
    }
    static void operator delete(void* pointer) noexcept {
        pi_simd::release(pointer);
    }
    static void operator delete(void* pointer, std::size_t) noexcept {
        pi_simd::release(pointer);
    }

    ~PiNodeFileHandleTransferData() {
        // Preserve the original strict > 0 condition, including fd == 0.
        if (fd_ > 0) {
            uv_fs_t close_req;
            if (fd_ == -1) {
                static const PiNodeAssertionInfo info = {
                    "src/node_file.cc:316", "(fd_) != (-1)",
                    "node::fs::FileHandle::TransferData::~TransferData"};
                pi_node_assert_failure(pi_node_diagnostic_context_current(),
                                       &info);
            }
            trace_.begin_sync_close();
            const int result = uv_fs_close(nullptr, &close_req, fd_, nullptr);
            if (result != 0) {
                static const PiNodeAssertionInfo info = {
                    "src/node_file.cc:318",
                    "(0) == (uv_fs_close(nullptr, &close_req, fd_, nullptr))",
                    "node::fs::FileHandle::TransferData::~TransferData"};
                pi_node_assert_failure(pi_node_diagnostic_context_current(),
                                       &info);
            }
            trace_.end_sync_close();
            uv_fs_req_cleanup(&close_req);
        }
    }

    int fd_;
    const PiNodeFileHandleTransferTrace trace_;
};

static_assert(alignof(PiNodeFileHandleTransferData) <=
              alignof(std::max_align_t));

extern "C" PiNodeFileHandleTransferData*
pi_node_file_handle_transfer_data_create(
    JSContext* context, void* memory_owner, int descriptor,
    const PiNodeFileHandleTransferTrace* trace) {
    pi::node::DiagnosticContextScope diagnostic_scope(context);
    pi_node::AllocationScope allocation_scope(memory_owner);
    assert(memory_owner != nullptr && trace != nullptr);
    assert(trace->begin_sync_close != nullptr &&
           trace->end_sync_close != nullptr);
    return new PiNodeFileHandleTransferData(descriptor, *trace);
}

extern "C" void pi_node_file_handle_transfer_data_delete(
    JSContext* context, PiNodeFileHandleTransferData* packet) {
    pi::node::DiagnosticContextScope diagnostic_scope(context);
    delete packet;
}

extern "C" int pi_node_file_handle_transfer_data_descriptor(
    JSContext* context, const PiNodeFileHandleTransferData* packet) {
    pi::node::DiagnosticContextScope diagnostic_scope(context);
    assert(packet != nullptr);
    return packet->fd_;
}

extern "C" int pi_node_file_handle_transfer_data_take_descriptor(
    JSContext* context, PiNodeFileHandleTransferData* packet) {
    pi::node::DiagnosticContextScope diagnostic_scope(context);
    assert(packet != nullptr);
    const int descriptor = packet->fd_;
    packet->fd_ = -1;
    return descriptor;
}
