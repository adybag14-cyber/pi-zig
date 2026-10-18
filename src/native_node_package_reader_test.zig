//! Actual package reader, native files and primordial SafeMap control graph.
//! Production receives the installed node:path object and genuine std.Io.
//! No module-loader substitute, spawned process or prefilled package cache.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
const js = @import("extensions/native_js_values.zig");
const reader = @import("extensions/native_node_package_json_reader.zig");
const collections = @import("extensions/native_node_fs_collections.zig");
comptime { _ = @import("native_node_package_native_test.zig"); }
const gpa = std.testing.allocator;
fn publish(engine: *em.Engine, name: [:0]const u8, value: c.JSValue) !void {
    const global = try engine.checked(c.JS_GetGlobalObject(engine.context));
    defer engine.freeValue(global);
    if (c.JS_SetPropertyStr(engine.context, global, name, c.JS_DupValue(engine.context, value)) < 0)
        return error.ActualPackageControlPublicationFailed;
}
fn publishText(engine: *em.Engine, name: [:0]const u8, value: []const u8) !void {
    const string = try engine.checked(c.JS_NewStringLen(engine.context, value.ptr, value.len));
    defer engine.freeValue(string);
    try publish(engine, name, string);
}
fn evaluate(engine: *em.Engine, source: []const u8) !void {
    const value = try engine.eval(source, "native-package-observer.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(value);
}
fn check(engine: *em.Engine, source: []const u8) !void {
    const value = try engine.eval(source, "native-package-observer.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(value);
    try std.testing.expect(c.JS_ToBool(engine.context, value) == 1);
}
fn clearCaptured(engine: *em.Engine) void {
    if (engine.captured_exception) |value| {
        engine.captured_exception = null;
        engine.freeValue(value);
    }
}
fn actualPaths(engine: *em.Engine) !c.JSValue {
    try @import("extensions/node_path.zig").install(engine, std.testing.io);
    const module = engine.native_module_values.get("node:path") orelse return error.ActualPathModuleRequired;
    return js.get(engine, module, "default");
}
fn installReader(engine: *em.Engine, permission: reader.Permission) !void {
    const paths = try actualPaths(engine);
    defer engine.freeValue(paths);
    const actual = try reader.create(engine, paths, permission);
    defer engine.freeValue(actual);
    try publish(engine, "actualPaths", paths);
    try publish(engine, "actualReader", actual);
}
fn temporaryRoot(temporary: *std.testing.TmpDir) ![]u8 {
    var bytes: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try temporary.dir.realPath(std.testing.io, &bytes);
    return gpa.dupe(u8, bytes[0..count]);
}
fn file(temporary: *std.testing.TmpDir, path: []const u8, contents: []const u8) !void {
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = path, .data = contents });
}
test "native package SafeMap retains genuine Map and frozen safe iterator identities" {
    const engine = try em.Engine.init(gpa, .{});
    defer engine.deinit();
    const safe = try collections.acquireSafeMap(engine);
    defer engine.freeValue(safe);
    const again = try collections.acquireSafeMap(engine);
    defer engine.freeValue(again);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, safe, again));
    try publish(engine, "ActualSafeMap", safe);
    try check(engine,
        \\(() => {
        \\  const value = new ActualSafeMap([['x', 4]]);
        \\  const iterator = value.entries();
        \\  return Object.isFrozen(ActualSafeMap) &&
        \\    Object.isFrozen(ActualSafeMap.prototype) &&
        \\    Object.getPrototypeOf(ActualSafeMap.prototype) === null &&
        \\    value.get('x') === 4 && iterator[Symbol.iterator]() === iterator &&
        \\    Object.isFrozen(Object.getPrototypeOf(iterator)) &&
        \\    Object.getPrototypeOf(Object.getPrototypeOf(iterator)) === null &&
        \\    iterator.next().value[1] === 4 && iterator.next().done === true;
        \\})()
    );
}
test "native package SafeMap probes twice for first iterator and shares captured next" {
    const engine = try em.Engine.init(gpa, .{});
    defer engine.deinit();
    try evaluate(engine,
        \\globalThis.probeLog = [];
        \\Object.defineProperty(Map.prototype, 'entries', {
        \\  configurable: true, writable: true, value: function entries() {
        \\    probeLog.push('entries');
        \\    return { [Symbol.iterator]() { return this; },
        \\      get next() { probeLog.push('next'); return function() { return {done:true}; }; } };
        \\  }
        \\});
        \\Object.defineProperty(Map.prototype, 'keys', {
        \\  configurable: true, writable: true, value: function keys() {
        \\    probeLog.push('keys');
        \\    return { [Symbol.iterator]() { return this; },
        \\      get next() { throw new Error('a second next capture'); } };
        \\  }
        \\});
    );
    const safe = try collections.acquireSafeMap(engine);
    defer engine.freeValue(safe);
    try check(engine, "JSON.stringify(probeLog)==='[\"entries\",\"entries\",\"next\",\"keys\"]'");
}
test "native package SafeMap skips dummy construction without inherited iterator" {
    const engine = try em.Engine.init(gpa, .{});
    defer engine.deinit();
    try evaluate(engine,
        \\globalThis.mapConstructions = 0;
        \\delete Map.prototype[Symbol.iterator];
        \\globalThis.Map = new Proxy(Map, {
        \\  construct(target, args, newTarget) {
        \\    mapConstructions++;
        \\    return Reflect.construct(target, args, newTarget);
        \\  }
        \\});
    );
    const safe = try collections.acquireSafeMap(engine);
    defer engine.freeValue(safe);
    try check(engine, "mapConstructions===0");
}
test "native package failed SafeMap probe leaves no published owner and supports real retry" {
    const engine = try em.Engine.init(gpa, .{});
    defer engine.deinit();
    try evaluate(engine,
        \\globalThis.savedEntries = Map.prototype.entries;
        \\Map.prototype.entries = function entries() { return 7; };
    );
    const attempted = collections.acquireSafeMap(engine);
    if (attempted) |unexpected| {
        engine.freeValue(unexpected);
        return error.ExpectedActualPrimitiveInFailure;
    } else |err| try std.testing.expectEqual(error.JavaScriptException, err);
    try std.testing.expect(!engine.native_module_values.contains("\x00native.fs.SafeMap"));
    const reason = engine.captured_exception orelse return error.ExpectedActualPrimitiveInReason;
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
    try publish(engine, "actualFailure", reason);
    clearCaptured(engine);
    try check(engine, "actualFailure instanceof TypeError && actualFailure.message===\"invalid 'in' operand\"");
    try evaluate(engine, "Map.prototype.entries = savedEntries");
    const retried = try collections.acquireSafeMap(engine);
    defer engine.freeValue(retried);
    try std.testing.expect(engine.native_module_values.contains("\x00native.fs.SafeMap"));
}
test "native package reader retains one live public resolve and native binding paths" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(std.testing.io, "pkg/lib");
    try file(&temporary, "pkg/package.json", "{\"name\":\"actual-package\",\"type\":\"module\",\"main\":\"main.js\"}");
    const root = try temporaryRoot(&temporary);
    defer gpa.free(root);
    const engine = try em.Engine.init(gpa, .{});
    defer engine.deinit();
    try installReader(engine, .{});
    try publishText(engine, "fixtureRoot", root);
    try check(engine,
        \\(() => {
        \\  let resolveReads = 0;
        \\  const resolve = actualPaths.resolve;
        \\  Object.defineProperty(actualPaths, 'resolve', {get() {resolveReads++; return resolve;}});
        \\  for (const name of ['dirname', 'basename', 'join', 'toNamespacedPath']) {
        \\    Object.defineProperty(actualPaths, name, {get() {throw new Error('public path '+name);}});
        \\  }
        \\  const value = actualReader.readPackage(fixtureRoot + '/pkg');
        \\  const nearest = actualReader.getNearestParentPackageJSON(fixtureRoot + '/pkg/lib/entry.js');
        \\  return resolveReads===1 && value.exists && value.name==='actual-package' &&
        \\    nearest.exists && nearest.data.type==='module' &&
        \\    Object.getPrototypeOf(value)===null && Object.getPrototypeOf(nearest.data)===null;
        \\})()
    );
}
test "native package reader native file cache and nearest object identity survive file changes" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(std.testing.io, "pkg/lib");
    try file(&temporary, "pkg/package.json", "{\"name\":\"before\",\"exports\":{\".\":\"./before.js\"}}");
    const root = try temporaryRoot(&temporary);
    defer gpa.free(root);
    const engine = try em.Engine.init(gpa, .{});
    defer engine.deinit();
    try installReader(engine, .{});
    try publishText(engine, "fixtureRoot", root);
    try evaluate(engine,
        \\globalThis.firstPackage = actualReader.getNearestParentPackageJSON(fixtureRoot + '/pkg/lib/a.js');
        \\globalThis.firstExports = firstPackage.data.exports;
    );
    try file(&temporary, "pkg/package.json", "{\"name\":\"after\",\"exports\":{\".\":\"./after.js\"}}");
    try check(engine,
        \\(() => {
        \\  const second = actualReader.getNearestParentPackageJSON(fixtureRoot + '/pkg/lib/b.js');
        \\  const descriptor = Object.getOwnPropertyDescriptor(second.data, 'exports');
        \\  const read = actualReader.readPackage(fixtureRoot + '/pkg');
        \\  return second===firstPackage && second.data.name==='before' &&
        \\    second.data.exports===firstExports && firstExports['.']==='./before.js' &&
        \\    descriptor.value===firstExports && !descriptor.writable && !descriptor.configurable &&
        \\    read.name==='before';
        \\})()
    );
}
test "native package reader caches native read failure and retries invalid JSON" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(std.testing.io, "missing");
    try temporary.dir.createDirPath(std.testing.io, "invalid");
    try file(&temporary, "invalid/package.json", "{\"name\":7}");
    const root = try temporaryRoot(&temporary);
    defer gpa.free(root);
    const engine = try em.Engine.init(gpa, .{});
    defer engine.deinit();
    try installReader(engine, .{});
    try publishText(engine, "fixtureRoot", root);
    try check(engine,
        \\(() => {
        \\  const missing = actualReader.readPackage(fixtureRoot+'/missing');
        \\  let code;
        \\  try { actualReader.readPackage(fixtureRoot+'/invalid'); } catch(error) { code=error.code; }
        \\  return !missing.exists && code==='ERR_INVALID_PACKAGE_CONFIG';
        \\})()
    );
    try file(&temporary, "missing/package.json", "{\"name\":\"new file\"}");
    try file(&temporary, "invalid/package.json", "{\"name\":\"repaired\"}");
    try check(engine, "!actualReader.readPackage(fixtureRoot+'/missing').exists && actualReader.readPackage(fixtureRoot+'/invalid').name==='repaired'");
}
const Denied = struct {
    calls: usize = 0,
    fn canRead(context: ?*anyopaque, _: []const u8) !bool {
        const self: *Denied = @ptrCast(@alignCast(context.?));
        self.calls += 1;
        return false;
    }
};
test "native package reader real permission callback precedes file access and upward search" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(std.testing.io, "pkg/lib");
    try file(&temporary, "pkg/package.json", "{\"name\":\"unread\"}");
    const root = try temporaryRoot(&temporary);
    defer gpa.free(root);
    var denied: Denied = .{};
    const engine = try em.Engine.init(gpa, .{});
    defer engine.deinit();
    try installReader(engine, .{ .context = &denied, .can_read = Denied.canRead });
    try publishText(engine, "fixtureRoot", root);
    try check(engine,
        \\(() => {
        \\  let denied;
        \\  try { actualReader.readPackage(fixtureRoot+'/pkg'); } catch(error) { denied=error; }
        \\  const nearest = actualReader.getNearestParentPackageJSON(fixtureRoot+'/pkg/lib/a.js');
        \\  return denied.code==='ERR_ACCESS_DENIED' && denied.permission==='FileSystemRead' &&
        \\    denied.resource===actualPaths.resolve(fixtureRoot+'/pkg', 'package.json') &&
        \\    !nearest.exists && nearest.path===fixtureRoot+'/pkg/lib/a.js';
        \\})()
    );
    try std.testing.expectEqual(@as(usize, 2), denied.calls);
}
test "native package reader keeps two SafeMaps and literal empty-string index checks" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(std.testing.io, "pkg");
    try file(&temporary, "pkg/package.json", "{\"exports\":\"\"}");
    const root = try temporaryRoot(&temporary);
    defer gpa.free(root);
    const engine = try em.Engine.init(gpa, .{});
    defer engine.deinit();
    try evaluate(engine,
        \\globalThis.mapConstructions = 0;
        \\globalThis.firstIndexReads = 0;
        \\globalThis.Map = new Proxy(Map, {
        \\  construct(target, args, newTarget) {
        \\    mapConstructions++;
        \\    return Reflect.construct(target, args, newTarget);
        \\  }
        \\});
        \\Object.defineProperty(String.prototype, '0', {
        \\  configurable:true, get() { firstIndexReads++; return undefined; }
        \\});
    );
    try installReader(engine, .{});
    try publishText(engine, "fixtureRoot", root);
    try check(engine,
        \\(() => {
        \\  const value = actualReader.readPackage(fixtureRoot+'/pkg');
        \\  return mapConstructions===3 && value.exports==='' && firstIndexReads===2;
        \\})()
    );
}

fn reenterSafeMap(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return collections.acquireSafeMap(engine);
}
test "native package SafeMap reentry returns the actual completed cache owner" {
    const engine = try em.Engine.init(gpa, .{});
    defer engine.deinit();
    const reenter = try @import("extensions/native_node_module_callable.zig").create(engine, "reenterSafeMap", 0, true, reenterSafeMap, &.{});
    defer engine.freeValue(reenter);
    try publish(engine, "reenterSafeMap", reenter);
    try evaluate(engine,
        \\globalThis.reenterOnce = true;
        \\globalThis.realEntries = Map.prototype.entries;
        \\Map.prototype.entries = function entries() {
        \\  if (reenterOnce) { reenterOnce = false; globalThis.innerSafeMap = reenterSafeMap(); }
        \\  return Reflect.apply(realEntries, this, []);
        \\};
    );
    const outer = try collections.acquireSafeMap(engine);
    defer engine.freeValue(outer);
    try publish(engine, "outerSafeMap", outer);
    try check(engine, "outerSafeMap === innerSafeMap");
    const cached = try collections.acquireSafeMap(engine);
    defer engine.freeValue(cached);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, outer, cached));
}
