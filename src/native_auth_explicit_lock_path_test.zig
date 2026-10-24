//! Actual native proper-lockfile explicit path controls over owned directories.
//! This selected supplier consumes the original realpath:false String paths.
//! No source in this packet has been compiled, queried or executed.
const std = @import("std");
const em = @import("extensions/engine.zig");
const v = @import("extensions/native_public_values.zig");
const h = @import("extensions/native_sdk_session_locals.zig");
const c = em.c;
const lock = @import("extensions/native_auth_directory_lock.zig");
const allocator = std.testing.allocator;

const Fixture = struct {
    temporary: std.testing.TmpDir,
    root: []u8,
    target: []u8,
    explicit: []u8,
    fallback: []u8,
    second: []u8,
    other_target: []u8,
    environment: std.process.Environ.Map,
    engine: *em.Engine = undefined,
    engine_alive: bool = false,

    fn init(self: *Fixture) !void {
        var temporary = std.testing.tmpDir(.{});
        errdefer temporary.cleanup();
        var scratch: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const length = try temporary.dir.realPath(std.testing.io, &scratch);
        const root_path = try allocator.dupe(u8, scratch[0..length]); errdefer allocator.free(root_path);
        const target_path = try std.fs.path.join(allocator, &.{root_path, "agent"}); errdefer allocator.free(target_path);
        const custom_path = try std.fs.path.join(allocator, &.{target_path, "trust.json.lock"}); errdefer allocator.free(custom_path);
        const default_path = try std.fmt.allocPrint(allocator, "{s}.lock", .{target_path}); errdefer allocator.free(default_path);
        const second_path = try std.fs.path.join(allocator, &.{target_path, "second.lock"}); errdefer allocator.free(second_path);
        const other_path = try std.fs.path.join(allocator, &.{root_path, "other"}); errdefer allocator.free(other_path);
        var environment: std.process.Environ.Map = .init(allocator); errdefer environment.deinit();
        try environment.put("HOME", root_path);
        try environment.put("USERPROFILE", root_path);
        self.* = .{ .temporary = temporary, .root = root_path, .target = target_path,
            .explicit = custom_path, .fallback = default_path, .second = second_path,
            .other_target = other_path, .environment = environment };
        try self.temporary.dir.createDirPath(std.testing.io, "agent");
        try self.temporary.dir.createDirPath(std.testing.io, "other");
        const engine = try em.Engine.init(allocator, .{ .host_await_timeout_ms = 5000, .interrupt_budget = 1_000_000 });
        errdefer engine.deinit();
        engine.native_io = std.testing.io;
        try @import("extensions/native_process.zig").install(engine, std.testing.io, &self.environment, &.{"actual-explicit-lock-path-control"});
        try @import("extensions/timers.zig").install(engine, std.testing.io);
        try @import("extensions/node_path.zig").install(engine, std.testing.io);
        self.engine = engine;
        const api = try lock.create(engine); defer engine.freeValue(api);
        try self.expose("actualDirectoryLock", api);
        try self.text("actualLockTarget", self.target);
        try self.text("actualExplicitLockPath", self.explicit);
        try self.text("actualSecondLockPath", self.second);
        try self.text("actualOtherLockTarget", self.other_target);
        self.engine_alive = true;
    }
    fn closeEngine(self: *Fixture) void {
        std.debug.assert(self.engine_alive);
        self.engine.deinit();
        self.engine_alive = false;
    }
    fn deinit(self: *Fixture) void {
        if (self.engine_alive) self.closeEngine();
        self.environment.deinit();
        allocator.free(self.other_target); allocator.free(self.second);
        allocator.free(self.fallback); allocator.free(self.explicit);
        allocator.free(self.target); allocator.free(self.root);
        self.temporary.cleanup();
    }
    fn exposeBody(s: *v.Scope, name: [*:0]const u8, value: c.JSValue) !void {
        const global = try v.own(s, c.JS_GetGlobalObject(s.engine.context));
        try v.put(s, global, name, value);
    }
    fn expose(self: *Fixture, name: [*:0]const u8, value: c.JSValue) !void {
        return h.statement(self.engine, exposeBody, .{name, value});
    }
    fn text(self: *Fixture, name: [*:0]const u8, bytes: []const u8) !void {
        const value = try h.text(self.engine, bytes); defer self.engine.freeValue(value);
        try self.expose(name, value);
    }
    fn run(self: *Fixture, source: []const u8) !void {
        const result = try self.engine.eval(source, "actual-explicit-lock-path.js", c.JS_EVAL_TYPE_GLOBAL);
        self.engine.freeValue(result);
    }
    fn expect(self: *Fixture, source: []const u8) !void {
        const result = try self.engine.eval(source, "actual-explicit-lock-path-assertion.js", c.JS_EVAL_TYPE_GLOBAL);
        defer self.engine.freeValue(result);
        try std.testing.expect(c.JS_ToBool(self.engine.context, result) == 1);
    }
    fn awaitStatement(self: *Fixture, source: []const u8) !void {
        const pending = try self.engine.eval(source, "actual-explicit-lock-path-await.js", c.JS_EVAL_TYPE_GLOBAL);
        defer self.engine.freeValue(pending);
        const result = try self.engine.awaitValue(pending);
        defer self.engine.freeValue(result);
        try std.testing.expect(c.JS_ToBool(self.engine.context, result) == 1);
    }
};
fn exists(path: []const u8) !bool {
    std.Io.Dir.cwd().access(std.testing.io, path, .{}) catch |err| {
        if (err == error.FileNotFound) return false;
        return err;
    };
    return true;
}
fn acquireExplicit(fixture: *Fixture) !void {
    try fixture.run("globalThis.explicitRelease=actualDirectoryLock.lockSync(actualLockTarget,{realpath:false,lockfilePath:actualExplicitLockPath});");
}
fn releaseExplicit(fixture: *Fixture) !void {
    try fixture.run("explicitRelease();globalThis.explicitRelease=undefined;");
}

test "native auth explicit lock path selects the trust file sibling and ordinary release" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    try acquireExplicit(&fixture);
    try std.testing.expect(try exists(fixture.explicit));
    try std.testing.expect(!try exists(fixture.fallback));
    try std.testing.expect(try exists(fixture.target));
    try fixture.expect("typeof explicitRelease==='function'&&explicitRelease.length===0&&!Object.hasOwn(explicitRelease,'prototype')");
    try releaseExplicit(&fixture);
    try std.testing.expect(!try exists(fixture.explicit));
    try std.testing.expect(try exists(fixture.target));
}
test "native auth explicit lock path preserves the original absent option default" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    try fixture.run("globalThis.explicitRelease=actualDirectoryLock.lockSync(actualLockTarget,{realpath:false});");
    try std.testing.expect(try exists(fixture.fallback));
    try std.testing.expect(!try exists(fixture.explicit));
    try releaseExplicit(&fixture);
    try std.testing.expect(!try exists(fixture.fallback));
}
test "native auth explicit lock path uses the default for every supplied falsy value" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    inline for (.{ "undefined", "null", "false", "0", "-0", "NaN", "0n", "''" }) |input| {
        try fixture.run("globalThis.explicitRelease=actualDirectoryLock.lockSync(actualLockTarget,{realpath:false,lockfilePath:" ++ input ++ "});");
        try std.testing.expect(try exists(fixture.fallback));
        try std.testing.expect(!try exists(fixture.explicit));
        try releaseExplicit(&fixture);
        try std.testing.expect(!try exists(fixture.fallback));
    }
}
test "native auth explicit lock path does not append a suffix to a nondefault spelling" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    const exact_path = try std.fs.path.join(allocator, &.{fixture.target, "selected directory with spaces"}); defer allocator.free(exact_path);
    const wrong_suffix = try std.fmt.allocPrint(allocator, "{s}.lock", .{exact_path}); defer allocator.free(wrong_suffix);
    try fixture.text("exactExplicitPath", exact_path);
    try fixture.run("globalThis.explicitRelease=actualDirectoryLock.lockSync(actualLockTarget,{realpath:false,lockfilePath:exactExplicitPath});");
    try std.testing.expect(try exists(exact_path));
    try std.testing.expect(!try exists(wrong_suffix));
    try std.testing.expect(!try exists(fixture.fallback));
    try releaseExplicit(&fixture);
    try std.testing.expect(!try exists(exact_path));
}
test "native auth explicit lock path retains relative spelling through acquire and release" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try std.Io.Dir.cwd().realPath(std.testing.io, &buffer);
    const relative_path = try std.fs.path.relative(allocator, buffer[0..count], fixture.explicit); defer allocator.free(relative_path);
    try fixture.text("relativeExplicitPath", relative_path);
    try fixture.run("globalThis.explicitRelease=actualDirectoryLock.lockSync(actualLockTarget,{realpath:false,lockfilePath:relativeExplicitPath});");
    try std.testing.expect(try exists(fixture.explicit));
    try std.testing.expect(!try exists(fixture.fallback));
    try releaseExplicit(&fixture);
    try std.testing.expect(!try exists(fixture.explicit));
}
test "native auth explicit lock path contention reports the canonical target rather than lock path" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    try acquireExplicit(&fixture);
    try fixture.expect(
        \\(()=>{let failure;try{actualDirectoryLock.lockSync(actualOtherLockTarget,{realpath:false,lockfilePath:actualExplicitLockPath})}catch(error){failure=error}
        \\return failure?.code==="ELOCKED"&&failure.file===actualOtherLockTarget})()
    );
    try std.testing.expect(try exists(fixture.explicit));
    try std.testing.expect(!try exists(fixture.fallback));
    try releaseExplicit(&fixture);
    try std.testing.expect(!try exists(fixture.explicit));
}
test "native auth explicit lock path missing parent preserves its actual mkdir failure path" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    const missing = try std.fs.path.join(allocator, &.{fixture.target, "absent", "custom.lock"}); defer allocator.free(missing);
    try fixture.text("missingExplicitParent", missing);
    try fixture.expect(
        \\(()=>{let failure;try{actualDirectoryLock.lockSync(actualLockTarget,{realpath:false,lockfilePath:missingExplicitParent})}catch(error){failure=error}
        \\return failure?.code==="ENOENT"&&failure.syscall==="mkdir"&&failure.path===missingExplicitParent})()
    );
    try std.testing.expect(!try exists(fixture.fallback));
    try std.testing.expect(!try exists(fixture.explicit));
}
test "native auth explicit lock path stale recovery replaces only the selected directory" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    try std.Io.Dir.cwd().createDir(std.testing.io, fixture.explicit, .default_dir);
    try @import("extensions/native_auth_file_io.zig").setTimestamp(allocator, std.testing.io, fixture.explicit, .{ .nanoseconds = 0 });
    try acquireExplicit(&fixture);
    try std.testing.expect(try exists(fixture.explicit));
    try std.testing.expect(!try exists(fixture.fallback));
    try releaseExplicit(&fixture);
    try std.testing.expect(!try exists(fixture.explicit));
}
test "native auth explicit lock path copies the selected option before later option mutation" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    try std.Io.Dir.cwd().createDir(std.testing.io, fixture.second, .default_dir);
    try fixture.run(
        \\globalThis.lockOptions={realpath:false,lockfilePath:actualExplicitLockPath};
        \\globalThis.explicitRelease=actualDirectoryLock.lockSync(actualLockTarget,lockOptions);
        \\lockOptions.lockfilePath=actualSecondLockPath;
    );
    try std.testing.expect(try exists(fixture.explicit));
    try std.testing.expect(try exists(fixture.second));
    try releaseExplicit(&fixture);
    try std.testing.expect(!try exists(fixture.explicit));
    try std.testing.expect(try exists(fixture.second));
}
test "native auth explicit lock path throwing option stops every physical side effect" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    try fixture.expect(
        \\(()=>{const reason={tag:"actual-option"};let caught,reads=0;
        \\try{actualDirectoryLock.lockSync(actualLockTarget,{realpath:false,get lockfilePath(){reads++;throw reason}})}catch(error){caught=error}
        \\return caught===reason&&reads===1})()
    );
    try std.testing.expect(!try exists(fixture.explicit));
    try std.testing.expect(!try exists(fixture.fallback));
}
test "native auth explicit lock path nonempty release error preserves foreign contents" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    try acquireExplicit(&fixture);
    try fixture.temporary.dir.writeFile(std.testing.io, .{ .sub_path = "agent/trust.json.lock/foreign.txt", .data = "preserve\n" });
    try fixture.expect(
        \\(()=>{let first,second;try{explicitRelease()}catch(error){first=error}try{explicitRelease()}catch(error){second=error}
        \\return first?.code==="ENOTEMPTY"&&first.path===actualExplicitLockPath&&second?.code==="ERELEASED"})()
    );
    const child_path = try std.fs.path.join(allocator, &.{fixture.explicit, "foreign.txt"}); defer allocator.free(child_path);
    try std.testing.expect(try exists(child_path));
    try std.testing.expect(!try exists(fixture.fallback));
}
test "native auth explicit lock path genuine async adapter keeps its selected lease until release" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    try fixture.awaitStatement(
        \\(async()=>{globalThis.explicitRelease=await actualDirectoryLock.lock(actualLockTarget,{realpath:false,lockfilePath:actualExplicitLockPath});
        \\return Object.getPrototypeOf(actualDirectoryLock)===Object.getPrototypeOf(async function(){})&&
        \\Object.getPrototypeOf(explicitRelease)===Function.prototype&&!Object.hasOwn(explicitRelease,"prototype")})()
    );
    try std.testing.expect(try exists(fixture.explicit));
    try std.testing.expect(!try exists(fixture.fallback));
    try fixture.awaitStatement("(async()=>{await explicitRelease();globalThis.explicitRelease=undefined;return true})()");
    try std.testing.expect(!try exists(fixture.explicit));
}
test "native auth explicit lock path actual heartbeat refreshes the selected lease" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    try fixture.run("globalThis.explicitRelease=actualDirectoryLock.lockSync(actualLockTarget,{realpath:false,lockfilePath:actualExplicitLockPath,stale:2000,update:1000});");
    const before = try std.Io.Dir.cwd().statFile(std.testing.io, fixture.explicit, .{});
    try fixture.awaitStatement("(async()=>{await new Promise(resolve=>setTimeout(resolve,2200));return true})()");
    const after = try std.Io.Dir.cwd().statFile(std.testing.io, fixture.explicit, .{});
    try std.testing.expect(after.mtime.toMilliseconds() > before.mtime.toMilliseconds());
    try std.testing.expect(!try exists(fixture.fallback));
    try releaseExplicit(&fixture);
    try std.testing.expect(!try exists(fixture.explicit));
}
test "native auth explicit lock path realm cleanup leaves an unrelated default directory intact" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    try std.Io.Dir.cwd().createDir(std.testing.io, fixture.fallback, .default_dir);
    try fixture.temporary.dir.writeFile(std.testing.io, .{ .sub_path = "agent.lock/foreign.txt", .data = "unrelated\n" });
    try acquireExplicit(&fixture);
    try std.testing.expect(try exists(fixture.explicit));
    fixture.closeEngine();
    try std.testing.expect(!try exists(fixture.explicit));
    try std.testing.expect(try exists(fixture.fallback));
    const child_path = try std.fs.path.join(allocator, &.{fixture.fallback, "foreign.txt"}); defer allocator.free(child_path);
    try std.testing.expect(try exists(child_path));
}
