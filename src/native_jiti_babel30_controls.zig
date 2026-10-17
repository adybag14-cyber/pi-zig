//! Verification-only original30 native observation. Actual dependency functions
//! and actual completed public profile are mandatory for their respective paths.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
const profile = @import("extensions/native_jiti_profile.zig");
const backend = @import("extensions/native_jiti_default_transform.zig");
pub const original_path = "verification/original-jiti-default-babel30-proof-20261017/original-output.json";
pub const inputs_path = "verification/jiti-default-transform-sourceonly-20261017/inputs.json";
pub const original_sha256 = "96DA1A507001E61D539E067E99203B4F35BF982BEF64D8A3A7E152B350DC5C37";
pub const inputs_sha256 = "4BD4707F127820EE482F7E9A808BCE5AAAA05E0DA3C5261CC44BF4A99E50B8FE";
// The accepted original plan supplies the physical fixture labels. No native
// expected value or output code is used to derive these names.
pub const original_fixture_root = "C:\\Users\\adyba\\pi-zig\\evidence\\root-original-babel30-20261017-145214\\fixtures";
fn parse(s: *v.Scope, bytes: []const u8, filename: [:0]const u8) !c.JSValue {
    const terminated = try s.engine.gpa.dupeZ(u8, bytes); defer s.engine.gpa.free(terminated);
    return s.own(try s.engine.checked(c.JS_ParseJSON(s.engine.context, terminated.ptr, bytes.len, filename)));
}
fn checkedBytes(io: std.Io, gpa: std.mem.Allocator, path: []const u8, expected: []const u8) ![]u8 {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(2*1024*1024)); errdefer gpa.free(bytes);
    var digest: [32]u8 = undefined; std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .upper);
    if (!std.mem.eql(u8, &hex, expected)) return error.OriginalBabel30AuthorityDrift;
    return bytes;
}
/// Returns owned raw JSON with ALL native/original code, function text and
/// diagnostic fields. A missing genuine public profile is never a parity pass.
fn collect(engine: *v.em.Engine, io: std.Io, actual_backend: c.JSValue, actual_create_jiti: ?c.JSValue) ![]u8 {
    const input = try checkedBytes(io, engine.gpa, inputs_path, inputs_sha256); defer engine.gpa.free(input);
    const original = try checkedBytes(io, engine.gpa, original_path, original_sha256); defer engine.gpa.free(original);
    var s: v.Scope = .{.engine=engine}; defer s.deinit();
    try @import("extensions/node_path.zig").install(engine,io);
    const node_path = engine.native_module_values.get("node:path") orelse return error.RequiredActualNodePath;
    const join = try s.get(node_path,"join");
    const namespace = try s.own(try engine.evalModule(@embedFile("extensions/fixtures/jiti-default-babel30-native-observer.mjs"), "native-babel30-observer.mjs"));
    const observe = try s.get(namespace, "default");
    const pending = try s.call(observe, c.pi_js_undefined(), &.{try parse(&s,input,"babel30-original-inputs.json"),try parse(&s,original,"babel30-original-output.json"),try s.text(original_fixture_root),actual_backend,actual_create_jiti orelse c.pi_js_undefined(),join});
    const report = try s.own(try engine.awaitValue(pending));
    const json = try s.global("JSON"); const text = try s.invoke(json,"stringify",&.{report});
    return engine.toString(text);
}
/// Full twelve evaluations enter through genuine lazy profile completion.
/// Root's revision2 registers the real provider without eager Module/cache or
/// parent publication. The actual createRequire/_load/_compile path must perform
/// first load; its genuine bootstrap remains a required external owner input.
pub fn collectCompleted(engine: *v.em.Engine, io: std.Io, staged: *profile.Prepared) ![]u8 {
    try verifyOriginalFixtures(engine,io);
    const namespace = try profile.complete(engine, staged); defer engine.freeValue(namespace);
    const factory = try v.js.get(engine, namespace, "createJiti"); defer engine.freeValue(factory);
    return collect(engine, io, staged.native_babel_exports, factory);
}
fn verifyOriginalFixtures(engine: *v.em.Engine, io: std.Io) !void {
    const bytes = try checkedBytes(io,engine.gpa,"verification/jiti-default-babel30-native-comparison-sourceonly-20261017/original-fixture-inventory.json","2D87AF009D38E3C2A05187C9D35ED641471615A2FF6E54B6BD2A1B3295E5AD9D"); defer engine.gpa.free(bytes);
    const parsed = try std.json.parseFromSlice(std.json.Value,engine.gpa,bytes,.{}); defer parsed.deinit();
    if (parsed.value.array.items.len != 33) return error.RequiredAllOriginalBabel33Fixtures;
    for (parsed.value.array.items) |row| {
        const value = try checkedBytes(io,engine.gpa,row.object.get("path").?.string,row.object.get("sha256").?.string); engine.gpa.free(value);
    }
}
/// Actual public owner uses this SAME comparator after supplying the genuine
/// lazy provider/bootstrap. Report is always written before comparison failure; no partial
/// row or diagnostic differences are normalized away to manufacture a pass.
pub fn verifyCompleted(engine: *v.em.Engine, io: std.Io, staged: *profile.Prepared, absolute_report_path: []const u8) !void {
    if (!std.fs.path.isAbsolute(absolute_report_path)) return error.RequiredAbsoluteOwnedBabel30ReportPath;
    const raw = try collectCompleted(engine,io,staged); defer engine.gpa.free(raw);
    const output = try std.Io.Dir.createFileAbsolute(io,absolute_report_path,.{.exclusive=true}); defer output.close(io);
    try output.writeStreamingAll(io,raw);
    const report = try std.json.parseFromSlice(std.json.Value,engine.gpa,raw,.{}); defer report.deinit();
    if (report.value.object.get("nativeRows").?.integer != 30 or report.value.object.get("evaluatedRows").?.integer != 12) return error.IncompleteActualBabel30Comparison;
    if (!report.value.object.get("fullComparisonPassed").?.bool) return error.ActualBabel30ComparisonMismatch;
}
/// Standalone backend composition uses real node:url converters, real MLLY URL
/// wrappers and actual Pathe.dirname. It does not manufacture createRequire,
/// Module, jiti public bootstrap, compiler output or filesystem collaborators.
pub fn collectBackend(engine: *v.em.Engine, io: std.Io) ![]u8 {
    try @import("extensions/node_url.zig").install(engine);
    const node_url = engine.native_module_values.get("node:url") orelse return error.RequiredActualNodeURL;
    const file = try v.js.get(engine,node_url,"fileURLToPath"); defer engine.freeValue(file);
    const path = try v.js.get(engine,node_url,"pathToFileURL"); defer engine.freeValue(path);
    const urls = try @import("extensions/native_mlly_urls.zig").create(engine,.{.file_url_to_path=file,.path_to_file_url=path}); defer engine.freeValue(urls);
    const paths = try @import("extensions/native_pathe.zig").create(engine); defer engine.freeValue(paths);
    const dirname = try v.js.get(engine,paths,"dirname"); defer engine.freeValue(dirname);
    const mlly_file = try v.js.get(engine,urls,"fileURLToPath"); defer engine.freeValue(mlly_file);
    const mlly_path = try v.js.get(engine,urls,"pathToFileURL"); defer engine.freeValue(mlly_path);
    const transform = try backend.create(engine,.{.file_url_to_path=mlly_file,.path_to_file_url=mlly_path,.dirname=dirname}); defer engine.freeValue(transform);
    return collect(engine,io,transform,null);
}
