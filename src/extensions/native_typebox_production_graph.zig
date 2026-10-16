//! One owner-realm graph for actual TypeBox operators, Partial, Compile and
//! pinned provider schemas. Source proofs do not qualify native execution.
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = js.c;
pub fn create(e: *js.Engine) !c.JSValue {
    const key = "pi-native:typebox-production-graph";
    if (e.native_module_values.get(key)) |cached| return c.JS_DupValue(e.context, cached);
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const shared = try s.own(try @import("native_typebox_memory.zig").create(e));
    const types = try s.object();
    try s.put(shared, "Type", types);
    try @import("native_typebox_partial.zig").install(e, types, shared);
    try @import("native_typebox_operators_production.zig").install(e, types, shared);
    // The compiler supplies actual Codec exports before consumers construct
    // schemas. Every closure retains this same mutable Type and Settings graph.
    try s.put(shared, "Compiler", try s.own(try @import("native_typebox_compile_production.zig").create(e, shared)));
    try s.put(shared, "Schemas", try s.own(try @import("native_ai_model_schemas.zig").createGraph(e, types)));
    try e.registerValueModule(key, shared);
    return c.JS_DupValue(e.context, shared);
}
