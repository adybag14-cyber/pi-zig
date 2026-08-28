//! Evaluation harness.
const std = @import("std");
pub const harness = @import("harness.zig");
pub const EvalCase = harness.EvalCase;
pub const EvalResult = harness.EvalResult;
pub const runCase = harness.runCase;
test {
    std.testing.refAllDecls(@This());
}
