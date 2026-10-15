//! Actual whole-loader host gate; unchanged genuine Source419+13+13 caller.
const std = @import("std");
const em = @import("extensions/engine.zig");
const subject = @import("native_highlight_complete191_test.zig");
fn install(engine: *em.Engine) !void {
    try @import("extensions/native_immediates.zig").install(engine);
}
test "native actual complete191 host unchanged genuine Source419 real Immediate registration and private readiness" {
    try subject.exerciseSource(std.testing.allocator, install, "success", @embedFile("extensions/fixtures/sdk-highlight-complete191-10_7_3.success.json"));
}
test "native actual complete191 host unchanged genuine Source13 import failure public void and private failure" {
    try subject.exerciseSource(std.testing.allocator, install, "lookup_failure", @embedFile("extensions/fixtures/sdk-highlight-complete191-10_7_3.lookup_failure.json"));
}
test "native actual complete191 host unchanged genuine Source13 factory fallback public success and private failure" {
    try subject.exerciseSource(std.testing.allocator, install, "safe_factory_failure", @embedFile("extensions/fixtures/sdk-highlight-complete191-10_7_3.safe_factory_failure.json"));
}
