//! Actual c268 module export composition. No synthetic database or host bridge.
const v = @import("native_ai_provider_values.zig");
const q = @import("native_chord_sqlite_values.zig");
const c = v.c;
const cache_key = "#pi-native:chord-sqlite-c268";
pub const Inputs = struct {
    // Carriers returned by the genuine native Node and Cloudflare factories.
    node_exports: c.JSValue,
    cloudflare_exports: c.JSValue,
};
pub const Graph = struct {
    portable: c.JSValue,
    node: c.JSValue,
    cloudflare: c.JSValue,
    pub fn deinit(self: Graph, engine: *v.em.Engine) void {
        engine.freeValue(self.portable); engine.freeValue(self.node); engine.freeValue(self.cloudflare);
    }
};
fn duplicate(s: *v.Scope, owner: c.JSValue) !Graph {
    const portable = try q.get(s, owner, "portable");
    const node = try q.get(s, owner, "node");
    const cloudflare = try q.get(s, owner, "cloudflare");
    return .{
        .portable = c.JS_DupValue(s.engine.context, portable),
        .node = c.JS_DupValue(s.engine.context, node),
        .cloudflare = c.JS_DupValue(s.engine.context, cloudflare),
    };
}
fn required(s: *v.Scope, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const function = try q.get(s, object, name);
    if (!c.JS_IsFunction(s.engine.context, function)) return error.RequiredActualChordSqliteExport;
    return function;
}
/// Exactly one completed module graph per Engine. Caller must supply REAL
/// adapter exports, including the direct-C DatabaseSync-backed Node adapter.
pub fn create(engine: *v.em.Engine, actual: Inputs) !Graph {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var captures = try q.Captures.enter(engine); defer captures.deinit();
    try q.pending(engine);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    if (engine.native_module_values.get(cache_key)) |owner| {
        if (!s.equal(try q.get(&s, owner, "ready"), c.pi_js_bool(engine.context, 1))) return error.ChordSqliteInitializationReentry;
        if (!s.equal(try q.get(&s, owner, "nodeInput"), actual.node_exports) or !s.equal(try q.get(&s, owner, "cloudflareInput"), actual.cloudflare_exports)) return error.ChordSqliteModuleImportsChanged;
        return duplicate(&s, owner);
    }
    try engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1);
    const owner = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    engine.native_module_values.putAssumeCapacity(cache_key, c.JS_DupValue(engine.context, owner));
    errdefer if (engine.native_module_values.fetchRemove(cache_key)) |removed| engine.freeValue(removed.value);
    const node_class = try required(&s, actual.node_exports, "NodeSqliteDatabase");
    const node_open = try required(&s, actual.node_exports, "openNodeSqliteDatabase");
    const cloudflare_class = try required(&s, actual.cloudflare_exports, "DurableObjectSqliteDatabase");
    const validate = try s.own(try q.success(engine, try @import("native_chord_sqlite_schema.zig").create(engine)));
    const migrate = try s.own(try q.success(engine, try @import("native_chord_sqlite_migrations.zig").create(engine, validate)));
    const portable = try s.object();
    try q.put(engine, portable, "applySqliteMigrations", migrate);
    try q.put(engine, portable, "validateSqliteSchemaPrefix", validate);
    const node = try s.object();
    try q.put(engine, node, "NodeSqliteDatabase", node_class);
    try q.put(engine, node, "openNodeSqliteDatabase", node_open);
    const cloudflare = try s.object();
    try q.put(engine, cloudflare, "DurableObjectSqliteDatabase", cloudflare_class);
    try q.put(engine, owner, "portable", portable);
    try q.put(engine, owner, "node", node);
    try q.put(engine, owner, "cloudflare", cloudflare);
    try q.put(engine, owner, "nodeInput", actual.node_exports);
    try q.put(engine, owner, "cloudflareInput", actual.cloudflare_exports);
    try q.put(engine, owner, "ready", c.pi_js_bool(engine.context, 1));
    return duplicate(&s, owner);
}
/// Add genuine ESM modules through the existing C module loader. Registration
/// is context-owned and not transactional: partial registration is NOT retried
/// as an atomic new graph. No default selector calls this source-only seam.
pub fn install(engine: *v.em.Engine, actual: Inputs) !void {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var captures = try q.Captures.enter(engine); defer captures.deinit();
    try q.pending(engine);
    const graph = try create(engine, actual); defer graph.deinit(engine);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const owner = engine.native_module_values.get(cache_key) orelse return error.MissingChordSqliteOwner;
    const phase = try q.get(&s, owner, "installPhase");
    if (s.equal(phase, c.JS_NewInt32(engine.context, 1))) return error.ChordSqlitePartialRegistration;
    try q.put(engine, owner, "installPhase", c.JS_NewInt32(engine.context, 1));
    const names = .{ "@earendil-works/chord/sqlite", "@earendil-works/chord/sqlite/node", "@earendil-works/chord/sqlite/cloudflare" };
    const exports = .{ graph.portable, graph.node, graph.cloudflare };
    inline for (names, exports) |name, carrier| {
        if (engine.native_module_values.get(name)) |existing| {
            if (!c.JS_IsStrictEqual(engine.context, existing, carrier)) return error.ChordSqliteNamespaceIdentityChanged;
        } else try engine.registerValueModule(name, carrier);
        try q.pending(engine);
    }
    try q.put(engine, owner, "installPhase", c.JS_NewInt32(engine.context, 2));
}
/// Called while Durable's REAL node export carrier is being built, BEFORE
/// registration. Its preexisting openNodeSqliteStorage declaration is retained.
/// Reexports use the SAME two values as chord/sqlite/node, not new wrappers.
pub fn addDurableNodeReexports(engine: *v.em.Engine, durable_exports: c.JSValue) !void {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var captures = try q.Captures.enter(engine); defer captures.deinit();
    try q.pending(engine);
    if (engine.native_module_names.contains("@earendil-works/pi-durable/storage/sqlite/node")) return error.DurableSqliteReexportAfterRegistration;
    const node = engine.native_module_values.get("@earendil-works/chord/sqlite/node") orelse return error.RequiredActualChordNodeSqliteModule;
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    _ = try required(&s, durable_exports, "openNodeSqliteStorage");
    inline for (.{ "NodeSqliteDatabase", "openNodeSqliteDatabase" }) |name| try q.put(engine, durable_exports, name, try required(&s, node, name));
}
/// A genuine Durable Cloudflare storage opener is REQUIRED. No empty facade
/// is created if the existing storage class/opening implementation is absent.
pub fn addDurableCloudflareReexports(engine: *v.em.Engine, durable_exports: c.JSValue) !void {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var captures = try q.Captures.enter(engine); defer captures.deinit();
    try q.pending(engine);
    if (engine.native_module_names.contains("@earendil-works/pi-durable/storage/sqlite/cloudflare")) return error.DurableSqliteReexportAfterRegistration;
    const cloudflare = engine.native_module_values.get("@earendil-works/chord/sqlite/cloudflare") orelse return error.RequiredActualChordCloudflareSqliteModule;
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    _ = try required(&s, durable_exports, "openDurableObjectSqliteStorage");
    try q.put(engine, durable_exports, "DurableObjectSqliteDatabase", try required(&s, cloudflare, "DurableObjectSqliteDatabase"));
}
