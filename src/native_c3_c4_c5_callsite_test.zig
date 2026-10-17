//! Combined real VM controls. Importing these retains their original assertions.
//! Metadata and execution require separate Root grants; no result is assumed.
comptime {
    _ = @import("native_module_graph_tla_query_test.zig");
    _ = @import("native_async_iterator_api_test.zig");
    _ = @import("native_callsite_visibility_test.zig");
}
