const std = @import("std");
const engine_mod = @import("extensions/engine.zig");
const stack = @import("extensions/native_error_stack.zig");
pub const Fixture = struct {
    engine: *engine_mod.Engine,
    owner: engine_mod.c.JSValue,
    pub fn init(gpa: std.mem.Allocator, options: engine_mod.Options) !Fixture {
        const engine = try engine_mod.Engine.init(gpa, options);
        errdefer engine.deinit();
        const value = try stack.install(engine);
        return .{ .engine = engine, .owner = value };
    }
    pub fn deinit(self: Fixture) void {
        stack.uninstall(self.engine);
        self.engine.freeValue(self.owner);
        self.engine.deinit();
    }
};
