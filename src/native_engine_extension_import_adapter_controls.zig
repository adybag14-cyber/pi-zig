//! Prepared physical component controls. Caller supplies the actual worker
//! loader and all twenty real composed namespace authorities in a fresh Engine.
//! No collaborator is fabricated here. Files are retained for owner receipts.
const std = @import("std");
const em = @import("extensions/engine.zig");
const adapter = @import("extensions/native_extension_import_adapter.zig");
const js = @import("extensions/native_js_values.zig");
const c = em.c;
const Files = struct {
    engine: *em.Engine,
    inputs: adapter.Inputs,
    root: []const u8,
    fn path(self: Files, relative: []const u8) ![]u8 { return std.fs.path.join(self.engine.gpa, &.{self.root, relative}); }
    fn write(self: Files, relative: []const u8, source: []const u8) !void {
        const target = try self.path(relative); defer self.engine.gpa.free(target);
        if (std.fs.path.dirname(target)) |parent| try std.Io.Dir.cwd().createDirPath(self.inputs.io, parent);
        try std.Io.Dir.cwd().writeFile(self.inputs.io, .{ .sub_path = target, .data = source });
    }
    fn load(self: Files, relative: []const u8) !c.JSValue {
        const target = try self.path(relative); defer self.engine.gpa.free(target);
        const session = try self.engine.createExtensionImportSession(self.inputs);
        const pending = try self.engine.startExtensionImport(session, target, target, c.pi_js_undefined());
        defer self.engine.freeValue(pending);
        return self.engine.awaitValue(pending);
    }
};
fn integer(engine: *em.Engine, value: c.JSValue) !i32 {
    var result: i32 = 0;
    if (c.JS_ToInt32(engine.context, &result, value) < 0) return js.capture(engine);
    return result;
}
fn value(engine: *em.Engine, namespace: c.JSValue) !i32 {
    const result = try js.get(engine, namespace, "value"); defer engine.freeValue(result);
    return integer(engine, result);
}
fn read(engine: *em.Engine, namespace: c.JSValue) !i32 {
    const pending = try js.invoke(engine, namespace, "read", &.{}); defer engine.freeValue(pending);
    const result = try engine.awaitValue(pending); defer engine.freeValue(result);
    return integer(engine, result);
}
fn returned(engine: *em.Engine, namespace: c.JSValue) !c.JSValue {
    const function = try js.get(engine, namespace, "default"); defer engine.freeValue(function);
    return js.call(engine, function, c.pi_js_undefined(), &.{});
}
fn checkDirect(files: Files, relative: []const u8, first: []const u8, edited: []const u8) !void {
    try files.write(relative, first);
    const a = try files.load(relative); defer files.engine.freeValue(a);
    try files.write(relative, edited);
    const b = try files.load(relative); defer files.engine.freeValue(b);
    try std.testing.expect(c.JS_IsStrictEqual(files.engine.context, a, b));
    const f1 = try js.get(files.engine, a, "default"); defer files.engine.freeValue(f1);
    const f2 = try js.get(files.engine, b, "default"); defer files.engine.freeValue(f2);
    try std.testing.expect(c.JS_IsStrictEqual(files.engine.context, f1, f2));
    const result = try returned(files.engine, b); defer files.engine.freeValue(result);
    try std.testing.expectEqual(@as(i32, 1), try integer(files.engine, result));
}
/// Requires a new, admitted absolute physical evidence directory. This function
/// refuses to overwrite an existing directory and intentionally never removes it.
/// It is a component control, not complete Source48/39 oracle replay or a test
/// of jiti's unimplemented default/Proxy/JSON-self-default/error fallback edges.
pub fn verify(engine: *em.Engine, inputs: adapter.Inputs, owned_directory: []const u8) !void {
    if (!std.fs.path.isAbsolute(owned_directory)) return error.RequiredAbsoluteOwnedControlDirectory;
    if (std.Io.Dir.cwd().statFile(inputs.io, owned_directory, .{})) |_| return error.OwnedControlDirectoryAlreadyExists else |err| switch (err) {
        error.FileNotFound => {}, else => return err,
    }
    try std.Io.Dir.cwd().createDirPath(inputs.io, owned_directory);
    const files: Files = .{ .engine = engine, .inputs = inputs, .root = owned_directory };
    try files.write("dep.ts", "export const version:number=1;\n");
    try files.write("static.ts", "import {version} from './dep.ts';export const value:number=version;\n");
    const old_static = try files.load("static.ts"); defer engine.freeValue(old_static);
    try files.write("dep.ts", "export const version:number=2;\n");
    const new_static = try files.load("static.ts"); defer engine.freeValue(new_static);
    try std.testing.expectEqual(@as(i32, 1), try value(engine, old_static));
    try std.testing.expectEqual(@as(i32, 2), try value(engine, new_static));
    try files.write("dynamic.ts", "export async function read(){return(await import('./dep.ts')).version}\n");
    const seeded = try files.load("dynamic.ts"); defer engine.freeValue(seeded);
    const late = try files.load("dynamic.ts"); defer engine.freeValue(late);
    try std.testing.expectEqual(@as(i32, 2), try read(engine, seeded));
    try files.write("dep.ts", "export const version:number=3;\n");
    const fresh = try files.load("dynamic.ts"); defer engine.freeValue(fresh);
    try std.testing.expectEqual(@as(i32, 3), try read(engine, fresh));
    try std.testing.expectEqual(@as(i32, 2), try read(engine, seeded));
    try std.testing.expectEqual(@as(i32, 3), try read(engine, late));
    try checkDirect(files, "direct.mjs", "export default()=>1;\n", "export default()=>2;\n");
    try checkDirect(files, "direct.cjs", "module.exports=()=>1;\n", "module.exports=()=>2;\n");
    try files.write("esm/package.json", "{\"type\":\"module\"}\n");
    try checkDirect(files, "esm/root.js", "export default()=>1;\n", "export default()=>2;\n");
    try files.write("no-type/package.json", "{}\n");
    try checkDirect(files, "no-type/root.js", "module.exports=()=>1;\n", "module.exports=()=>2;\n");
    try files.write("transition/package.json", "{\"type\":\"commonjs\"}\n");
    try files.write("transition/root.js", "module.exports=()=>1;\n");
    const before_type = try files.load("transition/root.js"); defer engine.freeValue(before_type);
    try files.write("transition/package.json", "{\"type\":\"module\"}\n");
    try files.write("transition/root.js", "export default()=>2;\n");
    const after_type = try files.load("transition/root.js"); defer engine.freeValue(after_type);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, before_type, after_type));
    const type_value = try returned(engine, after_type); defer engine.freeValue(type_value);
    try std.testing.expectEqual(@as(i32, 1), try integer(engine, type_value));
    try files.write("data.json", "{\"value\":1}\n");
    try files.write("json-root.ts", "import data from './data.json';export default()=>data;\n");
    const json_before = try files.load("json-root.ts"); defer engine.freeValue(json_before);
    const object_before = try returned(engine, json_before); defer engine.freeValue(object_before);
    try files.write("data.json", "{\"value\":2}\n");
    const json_after = try files.load("json-root.ts"); defer engine.freeValue(json_after);
    const object_after = try returned(engine, json_after); defer engine.freeValue(object_after);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, object_before, object_after));
    const json_value = try js.get(engine, object_after, "value"); defer engine.freeValue(json_value);
    try std.testing.expectEqual(@as(i32, 1), try integer(engine, json_value));
    try files.write("virtual.ts", "import * as a from 'typebox';import * as b from '@sinclair/typebox';export const same=a===b;export const typeSame=a.Type===b.Type;export const actualType=a.Type;export const url=import.meta.url;export function nested(){return()=>import.meta.filename}\n");
    const virtual = try files.load("virtual.ts"); defer engine.freeValue(virtual);
    const same = try js.get(engine, virtual, "same"); defer engine.freeValue(same);
    const type_same = try js.get(engine, virtual, "typeSame"); defer engine.freeValue(type_same);
    try std.testing.expect(c.JS_ToBool(engine.context, same) != 0 and c.JS_ToBool(engine.context, type_same) != 0);
    const actual_type = try js.get(engine, virtual, "actualType"); defer engine.freeValue(actual_type);
    try std.testing.expect(c.JS_IsObject(actual_type));
    for (inputs.namespaces) |binding| if (std.mem.eql(u8, binding.specifier, "typebox")) {
        const authority_type = try js.get(engine, binding.exports_authority, "Type"); defer engine.freeValue(authority_type);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, authority_type, actual_type));
    };
    const physical = try files.path("virtual.ts"); defer engine.gpa.free(physical);
    const expected_url = try @import("extensions/file_urls.zig").fromPath(engine.gpa, physical, @import("builtin").os.tag == .windows); defer engine.gpa.free(expected_url);
    const url = try js.get(engine, virtual, "url"); defer engine.freeValue(url);
    const actual_url = try engine.toString(url); defer engine.gpa.free(actual_url);
    try std.testing.expectEqualStrings(expected_url, actual_url);
    const nested = try js.invoke(engine, virtual, "nested", &.{}); defer engine.freeValue(nested);
    const filename = try js.call(engine, nested, c.pi_js_undefined(), &.{}); defer engine.freeValue(filename);
    const actual_filename = try engine.toString(filename); defer engine.gpa.free(actual_filename);
    const platform_path = try engine.gpa.dupe(u8, physical); defer engine.gpa.free(platform_path);
    if (@import("builtin").os.tag == .windows) for (platform_path) |*byte| { if (byte.* == '/') byte.* = '\\'; };
    try std.testing.expectEqualStrings(platform_path, actual_filename);
    try files.write("unobserved.mts", "export const value=1;\n");
    try std.testing.expectError(error.JavaScriptException, files.load("unobserved.mts"));
    try files.write("unobserved.cts", "module.exports=()=>1;\n");
    const probe_source = "import value from './unobserved.cts';export const same=typeof value==='function';\n";
    try files.write("ordinary-probe.mjs", probe_source);
    const probe_path = try files.path("ordinary-probe.mjs"); defer engine.gpa.free(probe_path);
    const probe_z = try engine.gpa.dupeZ(u8, probe_path); defer engine.gpa.free(probe_z);
    const ordinary = try engine.evalModule(probe_source, probe_z); defer engine.freeValue(ordinary);
    const probe_ok = try js.get(engine, ordinary, "same"); defer engine.freeValue(probe_ok);
    try std.testing.expect(c.JS_ToBool(engine.context, probe_ok) != 0);
    try std.testing.expectError(error.JavaScriptException, files.load("unobserved.cts"));
    const virtual_root_session = try engine.createExtensionImportSession(inputs);
    const virtual_root = try engine.startExtensionImport(virtual_root_session, physical, "typebox", c.pi_js_undefined()); defer engine.freeValue(virtual_root);
    try std.testing.expectError(error.JavaScriptException, engine.awaitValue(virtual_root));
    const invalid: *adapter.Session = @ptrFromInt(1);
    try std.testing.expectError(error.InvalidExtensionImportSession, engine.startExtensionImport(invalid, physical, physical, c.pi_js_undefined()));
}
