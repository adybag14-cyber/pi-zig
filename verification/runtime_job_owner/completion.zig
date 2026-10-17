//! Shared production completion-side clock checks. No injected/test clock.
const w = @import("win32.zig");
pub const Site = enum { worker_node, supervisor_node, supervisor_worker, persistence_poll, persistence_ack };
pub fn requireBefore(comptime site: Site, end_ms: u64) !void {
    if (w.GetTickCount64() < end_ms) return;
    return switch (site) {
        .worker_node => error.NodeLateCompletion,
        .supervisor_node => error.SupervisorNodeLateCompletion,
        .supervisor_worker => error.WorkerLateCompletion,
        .persistence_poll => error.PersistenceAckDeadline,
        .persistence_ack => error.PersistenceAckLateObservation,
    };
}
