//! Truthful native adaptation of coding-agent/utils/pi-user-agent.ts.
const std = @import("std");
const builtin = @import("builtin");
const v = @import("native_ai_provider_values.zig");
pub fn create(engine: *v.em.Engine) !v.c.JSValue {
    const Adapter = struct {
        fn call(host: *v.em.Engine, _: v.c.JSValue, args: []const v.c.JSValue, _: []const v.c.JSValue) !v.c.JSValue {
            var scope: v.Scope = .{ .engine = host };
            defer scope.deinit();
            return v.c.JS_DupValue(host.context, try value(&scope, if (args.len > 0) args[0] else v.c.pi_js_undefined()));
        }
    };
    return @import("native_node_function.zig").create(engine, "getPiUserAgent", 1, Adapter.call, &.{});
}
pub fn value(scope: *v.Scope, version: v.c.JSValue) !v.c.JSValue {
    // These are the actual linked runtime and target identities. Do not read a
    // simulated process.versions.node/bun or manufacture a JavaScript SDK UA.
    const suffix = try std.fmt.allocPrint(scope.engine.gpa, " ({s}; zig/{s}; quickjs-ng/{s}; {s})", .{ @tagName(builtin.os.tag), builtin.zig_version_string, std.mem.span(v.c.JS_GetVersion()), @tagName(builtin.cpu.arch) });
    defer scope.engine.gpa.free(suffix);
    return scope.concat(try scope.concat(try scope.text("pi/"), try scope.stringify(version)), try scope.text(suffix));
}
