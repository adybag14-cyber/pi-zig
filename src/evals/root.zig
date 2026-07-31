//! Evals package root: harness + generated case catalogs.
const std = @import("std");

pub const harness = @import("harness.zig");
pub const generated = @import("generated_root.zig");
pub const product = @import("product.zig");

pub const EvalCase = harness.EvalCase;
pub const EvalResult = harness.EvalResult;
pub const runCase = harness.runCase;

test {
    std.testing.refAllDecls(@This());
}
