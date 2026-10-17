//! Runtime selector for existing genuine Jiti/Agent/CommonJS controls.
//! No compile-only sentinel, Anchor ABI, replacement Subject or completed
//! application graph is introduced. Full owner/reference gates stay separate.
comptime {
    _ = @import("native_jiti_public_factory_test.zig");
    _ = @import("native_agent_af_correction_test.zig");
    _ = @import("native_node_commonjs_script_test.zig");
    _ = @import("native_node_commonjs_load_failure_test.zig");
    _ = @import("native_node_commonjs_converted_module_test.zig");
}
