//! Actual config.ts getAgentDir/expandTildePath bodies. Selected Source4954
//! package.json has APP_NAME="pi", CONFIG_DIR_NAME=".pi". Embedders with genuine
//! alternate package metadata may supply those captured constants explicitly.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
pub const Configuration = struct { app_name: []const u8 = "pi", config_dir: []const u8 = ".pi" };
pub fn create(engine: *v.em.Engine, configuration: Configuration) !c.JSValue {
    if (!engine.native_module_values.contains("node:path")) try @import("node_path.zig").install(engine, engine.native_io orelse return error.NativeAgentDirectoryRequiresIo);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const env_name = try scope.concat(try scope.invoke(try scope.text(configuration.app_name), "toUpperCase", &.{}), try scope.text("_CODING_AGENT_DIR"));
    const join = try scope.get(engine.native_module_values.get("node:path").?, "join");
    return @import("native_node_function.zig").create(engine, "getAgentDir", 0, get, &.{ env_name, try scope.text(configuration.config_dir), join });
}
fn get(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const env = try scope.get(try scope.global("process"), "env");
    const value = try scope.own(try v.js.getKey(engine, env, roots[0]));
    if (scope.truthy(value)) return @import("native_sdk_source_paths.zig").normalize(engine, value, c.pi_js_undefined());
    const home = try scope.own(try @import("native_home.zig").get(engine));
    return c.JS_DupValue(engine.context, try scope.call(roots[2], c.pi_js_undefined(), &.{ home, roots[1], try scope.text("agent") }));
}
