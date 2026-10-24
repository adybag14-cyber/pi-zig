//! Actual authenticated trust-manager assembly controls; source-only.
const std = @import("std");
const em = @import("extensions/engine.zig");
const h = @import("extensions/native_sdk_session_locals.zig");
const v = h.v;
const c = em.c;
const gpa = std.testing.allocator;
const manager_key = "pi-private:actual-sdk-project-trust-manager";

fn expose(s: *v.Scope, name: [*:0]const u8, value: c.JSValue) !void {
    const global = try v.own(s, c.JS_GetGlobalObject(s.engine.context));
    try v.put(s, global, name, value);
}
fn run(s: *v.Scope, source: []const u8) !void {
    _ = try v.own(s, try s.engine.eval(source, "actual-trust-manager-control.js", c.JS_EVAL_TYPE_GLOBAL));
}
fn expect(s: *v.Scope, source: []const u8) !void {
    const value = try v.own(s, try s.engine.eval(source, "actual-trust-manager-oracle.js", c.JS_EVAL_TYPE_GLOBAL));
    try std.testing.expect(c.JS_IsStrictEqual(s.engine.context, value, c.JS_NewBool(s.engine.context, true)));
}
fn globals(s: *v.Scope, f: *ActualTrustApplication.Fixture) !void {
    inline for (.{
        .{ "__tmFS", "node:fs" }, .{ "__tmPath", "node:path" }, .{ "__tmOS", "node:os" },
        .{ "__tmUtils", "pi-private:actual-sdk-path-utilities" },
        .{ "__tmLock", "pi-native:auth-directory-lock" },
        .{ "__tmConfig", "pi-native:sdk-configuration-native-zig" },
    }) |row| try expose(s, row[0], s.engine.native_module_values.get(row[1]) orelse return error.ActualTrustManagerProviderRequired);
    const text = try v.own(s, try @import("extensions/native_sdk_text_helpers.zig").create(s.engine));
    try expose(s, "__tmText", text);
    try expose(s, "__tmRuntime", f.owner().runtime_imports);
}
fn start(s: *v.Scope, f: *ActualTrustApplication.Fixture) !c.JSValue {
    const api = try v.own(s, try f.owner().createProjectTrustManager());
    try expose(s, "__tm", api);
    return api;
}
fn physical(s: *v.Scope, disk: *Disk) !void {
    try disk.directory("project/child");
    try expose(s, "__tmRoot", try v.text(s, disk.root));
    try run(s,
        \\globalThis.__tmAgent=__tmPath.join(__tmRoot,'agent');
        \\globalThis.__tmCwd=__tmPath.join(__tmRoot,'project','child');
        \\globalThis.__tmFile=__tmPath.join(__tmAgent,'trust.json');
    );
}
fn noPartial(engine: *em.Engine) !void {
    try std.testing.expect(!engine.native_module_values.contains(manager_key));
    try std.testing.expect(!engine.native_module_values.contains("pi-private:actual-sdk-project-trust-paths"));
    try std.testing.expect(!engine.native_module_values.contains("pi-private:actual-sdk-project-trust-store"));
}

const Disk = struct {
    temporary: std.testing.TmpDir,
    root: []u8,
    fn init() !Disk {
        var temporary = std.testing.tmpDir(.{});
        errdefer temporary.cleanup();
        var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const count = try temporary.dir.realPath(std.testing.io, &buffer);
        return .{ .temporary = temporary, .root = try gpa.dupe(u8, buffer[0..count]) };
    }
    fn path(self: *Disk, relative: []const u8) ![]u8 {
        return std.fs.path.join(gpa, &.{ self.root, relative });
    }
    fn directory(self: *Disk, relative: []const u8) !void {
        try self.temporary.dir.createDirPath(std.testing.io, relative);
    }
    fn write(self: *Disk, relative: []const u8) !void {
        if (std.fs.path.dirname(relative)) |directory_name| try self.directory(directory_name);
        try self.temporary.dir.writeFile(std.testing.io, .{ .sub_path = relative, .data = "actual trust resource\n" });
    }
    fn deinit(self: *Disk) void {
        gpa.free(self.root);
        self.temporary.cleanup();
    }
};
const ActualTrustApplication = struct {
    const auth = @import("extensions/native_sdk_auth_runtime_owner.zig");
    const capture = @import("extensions/native_child_process_frontend_inputs.zig");
    const internal = @import("extensions/native_node_internal_builtin_require.zig");
    const Frontend = @import("extensions/native_stdio_frontend.zig").Frontend;
    const Fixture = struct {
        environment: std.process.Environ.Map,
        engine: *v.em.Engine,
        frontend: Frontend,
        require: c.JSValue,
        actual: ?auth.Owner = null,

        fn init(self: *Fixture) !void {
            self.actual = null;
            self.environment = .init(std.testing.allocator);
            errdefer self.environment.deinit();
            self.engine = try v.em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000, .interrupt_budget = 1_000_000 });
            errdefer self.engine.deinit();
            try @import("extensions/native_sdk_application_bootstrap.zig").installPlatform(self.engine, std.testing.io, &self.environment, &.{"actual-application-print-owner"});
            self.require = try internal.acquire(self.engine, .{ .bindings = &.{
                .{ .id = "util", .module_name = "node:util" }, .{ .id = "stream", .module_name = "node:stream" },
                .{ .id = "process", .module_name = "node:process" }, .{ .id = "timers", .module_name = "node:timers" },
            } });
            errdefer self.engine.freeValue(self.require);
            try self.frontend.init(self.engine, std.testing.io);
            errdefer {
                if (self.engine.native_env_deinit) |close| close(self.engine);
                self.frontend.deinit();
            }
            // This control's actual bootstrap explicitly has permission disabled.
            // The production method receives no policy and cannot infer a default.
            var inputs = try capture.capture(self.engine, &self.frontend, .{ .internal_require = self.require, .permission = .disabled });
            var actual = createAuth(self.engine, &inputs) catch |err| {
                var failed = v.owned.Completion.initVoid(self.engine, err);
                inputs.retireInto(&failed);
                try failed.finishVoid();
                unreachable;
            };
            var selected = v.owned.Completion.initVoid(self.engine, {});
            inputs.retireInto(&selected);
            selected.finishVoid() catch |err| {
                var failed = v.owned.Completion.initVoid(self.engine, err);
                actual.retireInto(&failed);
                try failed.finishVoid();
                unreachable;
            };
            self.actual = actual;
        }
        fn owner(self: *Fixture) *auth.Owner {
            return if (self.actual) |*actual| actual else unreachable;
        }
        fn deinit(self: *Fixture) void {
            if (self.actual) |*actual| {
                if (actual.live) actual.deinit() catch {};
            }
            self.actual = null;
            // The physical frontend and its descriptor owners remain alive through
            // every owner operation. Cached JS roots do not own this native pointer.
            if (self.engine.native_env_deinit) |close| close(self.engine);
            self.frontend.deinit();
            self.engine.freeValue(self.require);
            self.engine.deinit();
            self.environment.deinit();
        }
    };
    fn createAuth(engine: *v.em.Engine, inputs: *capture.Owned) !auth.Owner {
        const url = try engine.checked(c.JS_NewString(engine.context, "file:///C:/Users/adyba/pi-zig/upstream/pi/packages/coding-agent/src/config.ts"));
        defer engine.freeValue(url); // Primitive, so retirement cannot run guest code.
        return auth.create(engine, .{ .frontend = try inputs.view(engine), .config_module_url = url });
    }

    const Behavior = enum { retire_owner, pending_ordinary, pending_fatal };
    const Probe = struct {
        engine: *em.Engine,
        owner: *auth.Owner,
        platform: c.JSValue,
        filesystem: c.JSValue,
        reason: c.JSValue,
        behavior: Behavior,
        platform_reads: usize = 0,
        filesystem_reads: usize = 0,
    };
    fn finalizeProbe(runtime: ?*c.JSRuntime, holder: c.JSValue) callconv(.c) void {
        const probe: *Probe = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
        c.JS_FreeValueRT(runtime, probe.platform);
        c.JS_FreeValueRT(runtime, probe.filesystem);
        c.JS_FreeValueRT(runtime, probe.reason);
        probe.engine.gpa.destroy(probe);
    }
    fn markProbe(runtime: ?*c.JSRuntime, holder: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
        const probe: *Probe = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
        c.JS_MarkValue(runtime, probe.platform, marker);
        c.JS_MarkValue(runtime, probe.filesystem, marker);
        c.JS_MarkValue(runtime, probe.reason, marker);
    }
    fn readPlatform(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
        const probe: *Probe = @ptrCast(@alignCast(c.JS_GetOpaque(roots[0], c.JS_GetClassID(roots[0])).?));
        probe.platform_reads += 1;
        switch (probe.behavior) {
            .retire_owner => probe.owner.deinit() catch |err| return @import("extensions/native_sdk.zig").fail(probe.engine, err),
            .pending_ordinary => { _ = c.JS_Throw(context, c.JS_DupValue(context, probe.reason)); },
            .pending_fatal => {
                _ = probe.engine.throwNativeOutOfMemoryFatal();
                const reason = c.JS_GetException(context);
                if (c.JS_IsUndefined(probe.reason)) probe.reason = c.JS_DupValue(context, reason);
                _ = c.JS_Throw(context, reason);
            },
        }
        return c.JS_DupValue(context, probe.platform);
    }
    fn readFilesystem(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
        const probe: *Probe = @ptrCast(@alignCast(c.JS_GetOpaque(roots[0], c.JS_GetClassID(roots[0])).?));
        probe.filesystem_reads += 1;
        return c.JS_DupValue(context, probe.filesystem);
    }
    fn getter(engine: *em.Engine, object: c.JSValue, name: [*:0]const u8, function: c.JSValue) !void {
        const atom = c.JS_NewAtom(engine.context, name);
        if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
        defer c.JS_FreeAtom(engine.context, atom);
        if (c.JS_DefinePropertyGetSet(engine.context, object, atom, c.JS_DupValue(engine.context, function), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0)
            return @import("extensions/native_js_values.zig").capture(engine);
        _ = try engine.checked(c.pi_js_undefined());
    }
    fn installProbe(s: *v.Scope, actual: *auth.Owner, behavior: Behavior) !*Probe {
        const engine = s.engine;
        const platform = try v.get(s, actual.runtime_imports, "platform");
        const filesystem = try v.get(s, platform, "filesystem");
        const reason = if (behavior == .pending_fatal) c.pi_js_undefined() else try v.own(s, try engine.checked(c.JS_NewError(engine.context)));
        var class: c.JSClassID = 0;
        _ = c.JS_NewClassID(engine.runtime, &class);
        const definition: c.JSClassDef = .{ .class_name = "Actual trust provider input probe", .finalizer = finalizeProbe, .gc_mark = markProbe };
        if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
        const holder = try v.own(s, try engine.checked(c.JS_NewObjectClass(engine.context, class)));
        const probe = try engine.gpa.create(Probe);
        probe.* = .{ .engine = engine, .owner = actual, .platform = c.JS_DupValue(engine.context, platform),
            .filesystem = c.JS_DupValue(engine.context, filesystem), .reason = c.JS_DupValue(engine.context, reason), .behavior = behavior };
        _ = c.JS_SetOpaque(holder, probe);
        var roots = [_]c.JSValue{holder};
        const platform_get = try v.own(s, try engine.checked(c.JS_NewCFunctionData2(engine.context, readPlatform, "get actual platform", 0, 0, roots.len, &roots)));
        const filesystem_get = try v.own(s, try engine.checked(c.JS_NewCFunctionData2(engine.context, readFilesystem, "get actual filesystem", 0, 0, roots.len, &roots)));
        try getter(engine, actual.runtime_imports, "platform", platform_get);
        try getter(engine, platform, "filesystem", filesystem_get);
        return probe;
    }
    fn expectForeign(s: *v.Scope, actual: *auth.Owner, name: []const u8) !void {
        const count = s.engine.native_module_values.count();
        try std.testing.expectError(error.JavaScriptException, actual.createProjectTrustPaths());
        const reason = s.engine.captured_exception orelse return error.RequiredForeignTrustOwnerRejection;
        const message = try v.get(s, reason, "message");
        const included = try v.call(s, try v.get(s, message, "includes"), message, &.{try v.text(s, name)});
        try std.testing.expect(c.JS_IsStrictEqual(s.engine.context, included, c.JS_NewBool(s.engine.context, true)));
        try std.testing.expect(c.JS_IsStrictEqual(s.engine.context, try v.global(s, "__trustForeignReads"), c.JS_NewInt32(s.engine.context, 0)));
        try std.testing.expectEqual(count, s.engine.native_module_values.count());
        try std.testing.expect(!s.engine.native_module_values.contains("pi-private:actual-sdk-project-trust-paths"));
    }
    fn foreign(s: *v.Scope) !c.JSValue {
        return v.own(s, try s.engine.eval(
            \\globalThis.__trustForeignReads=0;
            \\new Proxy({}, {get(){__trustForeignReads++;throw Error("foreign trust carrier must not be read")}})
        , "actual-trust-foreign-carrier.js", c.JS_EVAL_TYPE_GLOBAL));
    }
    fn verifyPending(comptime fatal: bool) !void {
        var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
        var s: v.Scope = .{ .engine = fixture.engine }; defer s.deinit();
        const probe = try installProbe(&s, fixture.owner(), if (fatal) .pending_fatal else .pending_ordinary);
        const count = s.engine.native_module_values.count();
        const generation = s.engine.native_allocation_generation;
        const suppression = s.engine.native_exception_diagnostics_suppressed;
        const invocation = s.engine.native_fatal_invocation;
        try std.testing.expectError(error.JavaScriptException, fixture.owner().createProjectTrustPaths());
        const caught = s.engine.captured_exception orelse return error.RequiredActualTrustOwnerFailure;
        try std.testing.expect(c.JS_IsStrictEqual(s.engine.context, caught, probe.reason));
        try std.testing.expectEqual(@as(usize, 1), probe.platform_reads);
        try std.testing.expectEqual(@as(usize, 0), probe.filesystem_reads);
        try std.testing.expectEqual(count, s.engine.native_module_values.count());
        try std.testing.expectEqual(suppression, s.engine.native_exception_diagnostics_suppressed);
        try std.testing.expectEqual(invocation, s.engine.native_fatal_invocation);
        try std.testing.expect(c.JS_IsUncatchableError(caught) == fatal);
        if (fatal) try std.testing.expect(s.engine.native_allocation_generation -% generation != 0);
    }
};


test "native project trust manager shares one complete four-export evaluation between actual owner entries" {
    var f: ActualTrustApplication.Fixture = undefined; try f.init(); defer f.deinit();
    var s: v.Scope = .{ .engine = f.engine }; defer s.deinit();
    const api = try start(&s, &f);
    const from_paths = try v.own(&s, try f.owner().createProjectTrustPaths());
    const repeated = try v.own(&s, try f.owner().createProjectTrustManager());
    try std.testing.expect(c.JS_IsStrictEqual(s.engine.context, api, from_paths));
    try std.testing.expect(c.JS_IsStrictEqual(s.engine.context, api, repeated));
    try expect(&s,
        \\Object.keys(__tm).join(',')==='getProjectTrustParentPath,getProjectTrustOptions,hasTrustRequiringProjectResources,ProjectTrustStore'&&
        \\__tm.ProjectTrustStore.name==='ProjectTrustStore'&&__tm.ProjectTrustStore.length===1&&
        \\Object.getOwnPropertyNames(__tm.ProjectTrustStore.prototype).join(',')==='constructor,get,getEntry,set,setMany'
    );
    try std.testing.expect(f.engine.native_module_values.contains(manager_key));
    try std.testing.expect(!f.engine.native_module_values.contains("pi-private:actual-sdk-project-trust-paths"));
    try std.testing.expect(!f.engine.native_module_values.contains("pi-private:actual-sdk-project-trust-store"));
}
test "native project trust manager path options feed the real Store and retain physical lock ownership" {
    var f: ActualTrustApplication.Fixture = undefined; try f.init(); defer f.deinit();
    var disk = try Disk.init(); defer disk.deinit();
    var s: v.Scope = .{ .engine = f.engine }; defer s.deinit();
    try globals(&s, &f); try physical(&s, &disk); _ = try start(&s, &f);
    try expect(&s,
        \\(()=>{const store=new __tm.ProjectTrustStore(__tmAgent);
        \\const choices=__tm.getProjectTrustOptions(__tmCwd,{includeSessionOnly:true});
        \\store.setMany(choices[1].updates);
        \\const nearest=store.getEntry(__tmCwd),parent=__tm.getProjectTrustParentPath(__tmCwd);
        \\return nearest.path===parent&&nearest.decision===true&&store.get(__tmCwd)===true&&
        \\__tmFS.existsSync(__tmFile)&&!__tmFS.existsSync(__tmFile+'.lock')&&
        \\__tmFS.readFileSync(__tmFile,'utf-8').endsWith('\n');})()
    );
}
test "native project trust manager captures every shared named import once in original source order" {
    var f: ActualTrustApplication.Fixture = undefined; try f.init(); defer f.deinit();
    var s: v.Scope = .{ .engine = f.engine }; defer s.deinit();
    try globals(&s, &f);
    try run(&s,
        \\globalThis.__tmCapture=[];
        \\for(const [owner,names]of [[__tmFS,['existsSync','mkdirSync','readFileSync','writeFileSync']],
        \\[__tmOS,['homedir']],[__tmPath,['dirname','join']],[__tmConfig,['CONFIG_DIR_NAME']],
        \\[__tmUtils,['canonicalizePath','resolvePath']],[__tmText,['stripBom']]]){
        \\for(const name of names){const value=owner[name];
        \\Object.defineProperty(owner,name,{configurable:true,get(){__tmCapture.push(name);return value;}});}}
    );
    _ = try start(&s, &f);
    try expect(&s,
        \\__tmCapture.join(',')==='existsSync,mkdirSync,readFileSync,writeFileSync,homedir,dirname,join,CONFIG_DIR_NAME,canonicalizePath,resolvePath,stripBom'
    );
}
test "native project trust manager warm creation never rereads captured named import members" {
    var f: ActualTrustApplication.Fixture = undefined; try f.init(); defer f.deinit();
    var s: v.Scope = .{ .engine = f.engine }; defer s.deinit();
    try globals(&s, &f); const first = try start(&s, &f);
    try run(&s,
        \\for(const [owner,names]of [[__tmFS,['existsSync','mkdirSync','readFileSync','writeFileSync']],
        \\[__tmOS,['homedir']],[__tmPath,['dirname','join']],[__tmConfig,['CONFIG_DIR_NAME']],
        \\[__tmUtils,['canonicalizePath','resolvePath']],[__tmText,['stripBom']]])
        \\for(const name of names)Object.defineProperty(owner,name,{configurable:true,get(){throw Error('must keep captured '+name);}});
    );
    const repeated = try v.own(&s, try f.owner().createProjectTrustManager());
    const via_paths = try v.own(&s, try f.owner().createProjectTrustPaths());
    try std.testing.expect(c.JS_IsStrictEqual(s.engine.context, first, repeated));
    try std.testing.expect(c.JS_IsStrictEqual(s.engine.context, first, via_paths));
}
test "native project trust manager retains one captured filesystem function for resources and Store" {
    var f: ActualTrustApplication.Fixture = undefined; try f.init(); defer f.deinit();
    var disk = try Disk.init(); defer disk.deinit();
    var s: v.Scope = .{ .engine = f.engine }; defer s.deinit();
    try globals(&s, &f); try physical(&s, &disk);
    try run(&s,
        \\globalThis.__tmExistsCalls=0;const exists=__tmFS.existsSync;
        \\__tmFS.existsSync=function(...args){__tmExistsCalls++;return Reflect.apply(exists,this,args);};
    );
    _ = try start(&s, &f);
    try run(&s,
        \\__tmFS.existsSync=function(){throw Error('later member must not replace shared capture')};
    );
    try expect(&s,
        \\(()=>{const before=__tmExistsCalls;
        \\const resources=__tm.hasTrustRequiringProjectResources(__tmCwd);
        \\const afterResource=__tmExistsCalls;
        \\const value=new __tm.ProjectTrustStore(__tmAgent).get(__tmCwd);
        \\return typeof resources==='boolean'&&afterResource>before&&
        \\value===null&&__tmExistsCalls===afterResource+1;})()
    );
}
test "native project trust manager preserves the live default lockfile member after shared capture" {
    var f: ActualTrustApplication.Fixture = undefined; try f.init(); defer f.deinit();
    var disk = try Disk.init(); defer disk.deinit();
    var s: v.Scope = .{ .engine = f.engine }; defer s.deinit();
    try globals(&s, &f); try physical(&s, &disk); _ = try start(&s, &f);
    try expect(&s,
        \\(()=>{const descriptor=Object.getOwnPropertyDescriptor(__tmLock,'lockSync'),lock=descriptor.value;
        \\let gets=0,calls=0,releases=0;Object.defineProperty(__tmLock,'lockSync',{configurable:true,
        \\get(){gets++;return function(...args){calls++;const release=Reflect.apply(lock,this,args);
        \\return()=>{releases++;release();};};}});
        \\try{const store=new __tm.ProjectTrustStore(__tmAgent);store.get(__tmCwd);store.set(__tmCwd,true);
        \\return gets===2&&calls===2&&releases===2&&!__tmFS.existsSync(__tmFile+'.lock');}
        \\finally{Object.defineProperty(__tmLock,'lockSync',descriptor);}})()
    );
}
test "native project trust manager ordinary named mutation before capture reaches every original consumer" {
    var f: ActualTrustApplication.Fixture = undefined; try f.init(); defer f.deinit();
    var disk = try Disk.init(); defer disk.deinit();
    var s: v.Scope = .{ .engine = f.engine }; defer s.deinit();
    try globals(&s, &f); try physical(&s, &disk);
    try run(&s,
        \\globalThis.__tmResolved=[];const resolve=__tmUtils.resolvePath;
        \\__tmUtils.resolvePath=function(value){__tmResolved.push(value);return resolve(value);};
    );
    _ = try start(&s, &f);
    try expect(&s,
        \\(()=>{__tm.getProjectTrustOptions(__tmCwd);
        \\const store=new __tm.ProjectTrustStore(__tmAgent);store.set(__tmCwd,true);store.get(__tmCwd);
        \\return __tmResolved.join('|')===[__tmCwd,__tmCwd,__tmAgent,__tmCwd,__tmCwd].join('|');})()
    );
}
test "native project trust manager complete exports survive retirement of their actual host handle" {
    var f: ActualTrustApplication.Fixture = undefined; try f.init(); defer f.deinit();
    var disk = try Disk.init(); defer disk.deinit();
    var s: v.Scope = .{ .engine = f.engine }; defer s.deinit();
    try globals(&s, &f); try physical(&s, &disk); _ = try start(&s, &f);
    try f.owner().deinit();
    try std.testing.expectError(error.ActualSdkAuthOwnerRetired, f.owner().createProjectTrustManager());
    try expect(&s,
        \\(()=>{const store=new __tm.ProjectTrustStore(__tmAgent);
        \\store.setMany(__tm.getProjectTrustOptions(__tmCwd)[0].updates);
        \\return store.get(__tmCwd)===true&&!__tmFS.existsSync(__tmFile+'.lock');})()
    );
}
test "native project trust manager all genuine provider roots survive retirement inside carrier Get" {
    var f: ActualTrustApplication.Fixture = undefined; try f.init(); defer f.deinit();
    var disk = try Disk.init(); defer disk.deinit();
    var s: v.Scope = .{ .engine = f.engine }; defer s.deinit();
    try globals(&s, &f); try physical(&s, &disk);
    const probe = try ActualTrustApplication.installProbe(&s, f.owner(), .retire_owner);
    _ = try start(&s, &f);
    try std.testing.expect(!f.owner().live);
    try std.testing.expectEqual(@as(usize, 1), probe.platform_reads);
    try std.testing.expectEqual(@as(usize, 1), probe.filesystem_reads);
    try expect(&s,
        \\new __tm.ProjectTrustStore(__tmAgent).get(__tmCwd)===null&&
        \\__tm.getProjectTrustOptions(__tmCwd).length===3
    );
}
test "native project trust manager rejects a foreign runtime before getter access or publication" {
    var f: ActualTrustApplication.Fixture = undefined; try f.init(); defer f.deinit();
    var s: v.Scope = .{ .engine = f.engine }; defer s.deinit();
    const foreign = try ActualTrustApplication.foreign(&s);
    const actual = f.owner(); const previous = actual.runtime_imports;
    actual.runtime_imports = c.JS_DupValue(s.engine.context, foreign); s.engine.freeValue(previous);
    try ActualTrustApplication.expectForeign(&s, actual, "ActualSdkTrustRuntimeNamespaceChanged");
    try noPartial(f.engine);
}

test "native project trust manager rejects a foreign platform before descendant access or publication" {
    var f: ActualTrustApplication.Fixture = undefined; try f.init(); defer f.deinit();
    var s: v.Scope = .{ .engine = f.engine }; defer s.deinit();
    try v.put(&s, f.owner().runtime_imports, "platform", try ActualTrustApplication.foreign(&s));
    try ActualTrustApplication.expectForeign(&s, f.owner(), "ActualSdkTrustPlatformNamespaceChanged");
    try noPartial(f.engine);
}
test "native project trust manager authenticates every publicly mutable child module carrier" {
    inline for (.{
        .{ "filesystem", "ActualSdkTrustFilesystemNamespaceChanged", false },
        .{ "paths", "ActualSdkTrustPathsNamespaceChanged", false },
        .{ "pathUtilities", "ActualSdkTrustUtilitiesNamespaceChanged", false },
        .{ "configuration", "ActualSdkTrustConfigurationNamespaceChanged", true },
    }) |row| {
        var f: ActualTrustApplication.Fixture = undefined; try f.init(); defer f.deinit();
        var s: v.Scope = .{ .engine = f.engine }; defer s.deinit();
        const parent = if (row[2]) f.owner().runtime_imports else try v.get(&s, f.owner().runtime_imports, "platform");
        try v.put(&s, parent, row[0], try ActualTrustApplication.foreign(&s));
        try ActualTrustApplication.expectForeign(&s, f.owner(), row[1]);
        try noPartial(f.engine);
    }
}
test "native project trust manager ordinary pending carrier stops all subsequent Gets and publication" {
    try ActualTrustApplication.verifyPending(false);
}
test "native project trust manager actual fatal carrier survives provider root retirement" {
    try ActualTrustApplication.verifyPending(true);
}
test "native project trust manager ordinary named getter failure preserves reason and permits clean retry" {
    var f: ActualTrustApplication.Fixture = undefined; try f.init(); defer f.deinit();
    var s: v.Scope = .{ .engine = f.engine }; defer s.deinit();
    try globals(&s, &f);
    try run(&s,
        \\globalThis.__tmMarker={};globalThis.__tmAfterFailure=0;
        \\globalThis.__tmExistsDescriptor=Object.getOwnPropertyDescriptor(__tmFS,'existsSync');
        \\Object.defineProperty(__tmFS,'existsSync',{configurable:true,get(){throw __tmMarker;}});
        \\const mkdir=__tmFS.mkdirSync;Object.defineProperty(__tmFS,'mkdirSync',{configurable:true,
        \\get(){__tmAfterFailure++;return mkdir;}});
    );
    const reason = try v.get(&s, try v.own(&s, c.JS_GetGlobalObject(s.engine.context)), "__tmMarker");
    try std.testing.expectError(error.JavaScriptException, f.owner().createProjectTrustManager());
    try std.testing.expect(c.JS_IsStrictEqual(s.engine.context, reason,
        f.engine.captured_exception orelse return error.ActualTrustManagerNamedReasonRequired));
    try noPartial(f.engine);
    try expect(&s, "__tmAfterFailure===0");
    try run(&s, "Object.defineProperty(__tmFS,'existsSync',__tmExistsDescriptor)");
    _ = try start(&s, &f);
    try expect(&s, "__tmAfterFailure===1&&typeof __tm.ProjectTrustStore==='function'");
}

var active_fixture: ?*ActualTrustApplication.Fixture = null;
var reentry_count: usize = 0;
fn reenterManager(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue,
    _: []const c.JSValue) !c.JSValue
{
    const current = active_fixture orelse return error.ActualTrustManagerReentryFixtureRequired;
    if (engine != current.engine) return error.ActualTrustManagerReentryEngineRequired;
    reentry_count += 1;
    try noPartial(engine);
    return current.owner().createProjectTrustManager();
}
test "native project trust manager cold named getter reentry cannot publish a partial evaluation" {
    var f: ActualTrustApplication.Fixture = undefined; try f.init(); defer f.deinit();
    var s: v.Scope = .{ .engine = f.engine }; defer s.deinit();
    try globals(&s, &f);
    active_fixture = &f; defer active_fixture = null; reentry_count = 0;
    const callback = try v.own(&s, try v.function.create(f.engine, "reenterTrustManager", 0, reenterManager, &.{}));
    try expose(&s, "__tmReenter", callback);
    try run(&s,
        \\globalThis.__tmReentryRejected=false;const exists=__tmFS.existsSync;
        \\Object.defineProperty(__tmFS,'existsSync',{configurable:true,get(){
        \\try{__tmReenter()}catch(error){__tmReentryRejected=error instanceof TypeError&&
        \\error.message.includes('ActualProjectTrustManagerCreationReentry');}return exists;}});
    );
    _ = try start(&s, &f);
    try std.testing.expectEqual(@as(usize, 1), reentry_count);
    try expect(&s, "__tmReentryRejected&&typeof __tm.ProjectTrustStore==='function'");
}

fn pendingNamed(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue,
    magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const engine = em.Engine.fromContext(context.?);
    if (magic == 1) _ = engine.throwNativeOutOfMemoryFatal()
    else _ = c.JS_Throw(context, c.JS_DupValue(context, roots[0]));
    return c.JS_DupValue(context, roots[1]);
}
fn verifyPendingNamed(comptime fatal: bool) !void {
    var f: ActualTrustApplication.Fixture = undefined; try f.init(); defer f.deinit();
    var s: v.Scope = .{ .engine = f.engine }; defer s.deinit();
    try globals(&s, &f);
    const filesystem = s.engine.native_module_values.get("node:fs") orelse return error.ActualTrustManagerFilesystemRequired;
    const reason = try v.own(&s, try s.engine.checked(c.JS_NewError(s.engine.context)));
    const original = try v.get(&s, filesystem, "existsSync");
    var roots = [_]c.JSValue{ reason, original };
    const getter = try v.own(&s, try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context,
        pendingNamed, "get existsSync", 0, if (fatal) 1 else 0, roots.len, &roots)));
    try ActualTrustApplication.getter(s.engine, filesystem, "existsSync", getter);
    try run(&s,
        \\globalThis.__tmPendingLaterGets=0;const mkdir=__tmFS.mkdirSync;
        \\Object.defineProperty(__tmFS,'mkdirSync',{configurable:true,
        \\get(){__tmPendingLaterGets++;return mkdir;}});
    );
    const suppression = f.engine.native_exception_diagnostics_suppressed;
    const invocation = f.engine.native_fatal_invocation;
    const generation = f.engine.native_allocation_generation;
    try std.testing.expectError(error.JavaScriptException, f.owner().createProjectTrustManager());
    const caught = f.engine.captured_exception orelse return error.ActualTrustManagerPendingNamedReasonRequired;
    try std.testing.expect(c.JS_IsUncatchableError(caught) == fatal);
    if (fatal) {
        try std.testing.expect(f.engine.native_allocation_generation -% generation != 0);
        c.JS_ClearUncatchableError(f.engine.context, caught);
    } else try std.testing.expect(c.JS_IsStrictEqual(s.engine.context, caught, reason));
    try std.testing.expectEqual(suppression, f.engine.native_exception_diagnostics_suppressed);
    try std.testing.expectEqual(invocation, f.engine.native_fatal_invocation);
    try noPartial(f.engine);
    try expect(&s, "__tmPendingLaterGets===0");
}
test "native project trust manager normal callable value with pending exception stops named imports" {
    try verifyPendingNamed(false);
}
test "native project trust manager actual fatal named producer survives returned value retirement" {
    try verifyPendingNamed(true);
}
test "native project trust manager pending native entry cannot read a carrier or publish a module" {
    var f: ActualTrustApplication.Fixture = undefined; try f.init(); defer f.deinit();
    var s: v.Scope = .{ .engine = f.engine }; defer s.deinit();
    const probe = try ActualTrustApplication.installProbe(&s, f.owner(), .pending_ordinary);
    const reason = try v.own(&s, try s.engine.checked(c.JS_NewError(s.engine.context)));
    _ = c.JS_Throw(s.engine.context, c.JS_DupValue(s.engine.context, reason));
    try std.testing.expectError(error.JavaScriptException, f.owner().createProjectTrustManager());
    try std.testing.expect(c.JS_IsStrictEqual(s.engine.context, reason,
        f.engine.captured_exception orelse return error.ActualTrustManagerPendingEntryReasonRequired));
    try std.testing.expectEqual(@as(usize, 0), probe.platform_reads);
    try noPartial(f.engine);
}
test "native project trust manager both entries retain the one original mutable resource array" {
    var f: ActualTrustApplication.Fixture = undefined; try f.init(); defer f.deinit();
    var disk = try Disk.init(); defer disk.deinit();
    var s: v.Scope = .{ .engine = f.engine }; defer s.deinit();
    try globals(&s, &f); try physical(&s, &disk); _ = try start(&s, &f);
    const via_paths = try v.own(&s, try f.owner().createProjectTrustPaths());
    try expose(&s, "__tmViaPaths", via_paths);
    try expect(&s,
        \\(()=>{const original=Array.prototype.some,seen=[];
        \\Array.prototype.some=function(...args){seen.push(this);return Reflect.apply(original,this,args);};
        \\try{__tm.hasTrustRequiringProjectResources(__tmCwd);
        \\seen[0].push('TRUST_MANAGER_PRIVATE_RESOURCE');
        \\const config=__tmPath.join(__tmCwd,__tmConfig.CONFIG_DIR_NAME);__tmFS.mkdirSync(config,{recursive:true});
        \\__tmFS.writeFileSync(__tmPath.join(config,'TRUST_MANAGER_PRIVATE_RESOURCE'),'actual','utf-8');
        \\return __tmViaPaths.hasTrustRequiringProjectResources(__tmCwd)===true&&seen.length===2&&seen[0]===seen[1];}
        \\finally{Array.prototype.some=original;}})()
    );
}
