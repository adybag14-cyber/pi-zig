//! Actual loader.ts getAliases body over real path/fs/url/createRequire imports.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
pub const Inputs = struct { paths: c.JSValue, filesystem: c.JSValue, url: c.JSValue, node_module: c.JSValue, import_meta: c.JSValue };
fn put(engine: *v.em.Engine, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void { try v.js.define(engine, target, name, c.JS_DupValue(engine.context, value)); }
pub fn create(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const owner = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.JS_NULL)));
    try put(engine, owner, "aliases", c.JS_NULL);
    try put(engine, owner, "path", inputs.paths);
    try put(engine, owner, "fs", inputs.filesystem);
    try put(engine, owner, "meta", inputs.import_meta);
    const file_url_to_path = try s.get(inputs.url, "fileURLToPath");
    const create_require = try s.get(inputs.node_module, "createRequire");
    if (!c.JS_IsFunction(engine.context, file_url_to_path) or !c.JS_IsFunction(engine.context, create_require)) return error.RequiredActualAliasImports;
    try put(engine, owner, "fileURLToPath", file_url_to_path);
    // Source top-level const require is evaluated once, before getAliases.
    try put(engine, owner, "require", try s.call(create_require, c.pi_js_undefined(), &.{try s.get(inputs.import_meta, "url")}));
    return @import("native_node_function.zig").create(engine, "getAliases", 0, getAliases, &.{owner});
}
fn fromUrl(s: *Scope, owner: c.JSValue, url: c.JSValue) !c.JSValue { return s.call(try s.get(owner, "fileURLToPath"), c.pi_js_undefined(), &.{url}); }
fn workspaceOrImport(s: *Scope, owner: c.JSValue, packages_root: c.JSValue, relative: []const u8, specifier: []const u8) !c.JSValue {
    const path = try s.invoke(try s.get(owner, "path"), "join", &.{ packages_root, try s.text(relative) });
    if (s.truthy(try s.invoke(try s.get(owner, "fs"), "existsSync", &.{path}))) return path;
    return fromUrl(s, owner, try s.invoke(try s.get(owner, "meta"), "resolve", &.{try s.text(specifier)}));
}
fn getAliases(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const owner = roots[0];
    const cached = try s.get(owner, "aliases");
    if (s.truthy(cached)) return c.JS_DupValue(engine.context, cached);
    const path = try s.get(owner, "path");
    // Capture dirname callee before evaluating the nested URL conversion.
    const dirname = try s.get(path, "dirname");
    const directory = try s.call(dirname, path, &.{try fromUrl(&s, owner, try s.get(try s.get(owner, "meta"), "url"))});
    const sdk = try s.invoke(path, "resolve", &.{ directory, try s.text("../.."), try s.text("index.js") });
    const require = try s.get(owner, "require");
    const typebox = try s.invoke(require, "resolve", &.{try s.text("typebox")});
    const compile = try s.invoke(require, "resolve", &.{try s.text("typebox/compile")});
    const value = try s.invoke(require, "resolve", &.{try s.text("typebox/value")});
    const packages = try s.invoke(path, "resolve", &.{ directory, try s.text("../../../../") });
    const core = try workspaceOrImport(&s, owner, packages, "agent/dist/index.js", "@earendil-works/pi-agent-core");
    const tui = try workspaceOrImport(&s, owner, packages, "tui/dist/index.js", "@earendil-works/pi-tui");
    const compat = try workspaceOrImport(&s, owner, packages, "ai/dist/compat.js", "@earendil-works/pi-ai/compat");
    const oauth = try workspaceOrImport(&s, owner, packages, "ai/dist/oauth.js", "@earendil-works/pi-ai/oauth");
    const providers = try workspaceOrImport(&s, owner, packages, "ai/dist/providers/all.js", "@earendil-works/pi-ai/providers/all");
    const result = try s.object();
    inline for (.{ .{ "@earendil-works/pi-coding-agent", sdk }, .{ "@earendil-works/pi-agent-core", core }, .{ "@earendil-works/pi-tui", tui }, .{ "@earendil-works/pi-ai/providers/all", providers }, .{ "@earendil-works/pi-ai/compat", compat }, .{ "@earendil-works/pi-ai/oauth", oauth }, .{ "@earendil-works/pi-ai", compat }, .{ "@mariozechner/pi-coding-agent", sdk }, .{ "@mariozechner/pi-agent-core", core }, .{ "@mariozechner/pi-tui", tui }, .{ "@mariozechner/pi-ai/providers/all", providers }, .{ "@mariozechner/pi-ai/compat", compat }, .{ "@mariozechner/pi-ai/oauth", oauth }, .{ "@mariozechner/pi-ai", compat }, .{ "typebox", typebox }, .{ "typebox/compile", compile }, .{ "typebox/value", value }, .{ "@sinclair/typebox", typebox }, .{ "@sinclair/typebox/compile", compile }, .{ "@sinclair/typebox/value", value } }) |entry| try put(engine, result, entry[0], entry[1]);
    try put(engine, owner, "aliases", result);
    return c.JS_DupValue(engine.context, result);
}
