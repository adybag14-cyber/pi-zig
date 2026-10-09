//! Direct kernel gate: the legacy CLI read gate does not import this module.
test {
    _ = @import("durable/tool_read.zig");
}
