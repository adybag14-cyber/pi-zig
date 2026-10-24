//! Source-only controls for original trust path/resource/options helpers.
//! Real installed fs/path/process/OS and Source path utilities are used. Guest
//! wrappers below observe or mutate original public operations; they are not
//! production providers. Nothing in this file has been executed in this packet.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
const h = @import("extensions/native_sdk_session_locals.zig");
const v = h.v;
const trust = @import("extensions/native_sdk_project_trust_paths.zig");
const application = @import("extensions/native_sdk_application_owner.zig");
const gpa = std.testing.allocator;

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
const Fixture = struct {
    disk: Disk,
    environment: std.process.Environ.Map,
    engine: *em.Engine = undefined,
    engine_alive: bool = false,
    utilities: ?c.JSValue = null,
    os: ?c.JSValue = null,
    config_dir: ?c.JSValue = null,
    inputs: trust.Inputs = undefined,

    fn init(self: *Fixture) !void { return self.initWithAllocator(gpa); }
    fn initWithAllocator(self: *Fixture, allocator: std.mem.Allocator) !void {
        self.* = .{ .disk = try Disk.init(), .environment = .init(gpa) };
        errdefer self.deinit();
        try self.disk.directory("home");
        try self.disk.directory("project/child");
        const home_path = try self.disk.path("home");
        defer gpa.free(home_path);
        try self.environment.put("HOME", home_path);
        self.engine = try em.Engine.init(allocator, .{});
        self.engine_alive = true;
        try @import("extensions/timers.zig").install(self.engine, std.testing.io);
        try @import("extensions/native_process.zig").install(self.engine, std.testing.io, &self.environment, &.{"trust-path-controls"});
        try @import("extensions/node_path.zig").install(self.engine, std.testing.io);
        try @import("extensions/node_url.zig").install(self.engine);
        try @import("extensions/node_fs.zig").install(self.engine, std.testing.io);
        try @import("extensions/native_node_os.zig").install(self.engine);
        const filesystem = self.engine.native_module_values.get("node:fs") orelse return error.ActualFilesystemRequired;
        const paths = self.engine.native_module_values.get("node:path") orelse return error.ActualPathsRequired;
        const os_module = self.engine.native_module_values.get("node:os") orelse return error.ActualOSRequired;
        self.os = try h.get(self.engine, os_module, "default");
        self.utilities = try @import("extensions/native_sdk_path_utilities_namespace.zig").create(self.engine, filesystem);
        self.config_dir = try h.text(self.engine, @import("config.zig").CONFIG_DIR_NAME);
        self.inputs = .{ .filesystem = filesystem, .paths = paths, .os = self.os.?,
            .path_utilities = self.utilities.?, .config_dir = self.config_dir.? };
        try self.expose("trustFS", filesystem);
        try self.expose("trustPath", paths);
        try self.expose("trustOS", self.os.?);
        try self.expose("trustUtils", self.utilities.?);
        try self.expose("trustConfigDir", self.config_dir.?);
        try self.text("trustRoot", self.disk.root);
        try self.text("trustHome", home_path);
        const cwd_path = try self.disk.path("project/child");
        defer gpa.free(cwd_path);
        try self.text("trustCwd", cwd_path);
        try self.run("globalThis.trustOriginalProcess=process;");
    }
    fn deinit(self: *Fixture) void {
        if (self.engine_alive) {
            if (self.utilities) |value| self.engine.freeValue(value);
            if (self.os) |value| self.engine.freeValue(value);
            if (self.config_dir) |value| self.engine.freeValue(value);
            self.engine.deinit();
            self.engine_alive = false;
        }
        self.environment.deinit();
        self.disk.deinit();
    }
    fn exposeBody(s: *v.Scope, name: [*:0]const u8, value: c.JSValue) !void {
        const global = try v.own(s, c.JS_GetGlobalObject(s.engine.context));
        try v.put(s, global, name, value);
    }
    fn expose(self: *Fixture, name: [*:0]const u8, value: c.JSValue) !void {
        try h.statement(self.engine, exposeBody, .{ name, value });
    }
    fn text(self: *Fixture, name: [*:0]const u8, bytes: []const u8) !void {
        const value = try h.text(self.engine, bytes);
        defer self.engine.freeValue(value);
        try self.expose(name, value);
    }
    fn start(self: *Fixture) !void {
        const api = try trust.create(self.engine, self.inputs);
        defer self.engine.freeValue(api);
        try self.expose("trustPaths", api);
    }
    fn run(self: *Fixture, source: []const u8) !void {
        const result = try self.engine.eval(source, "actual-trust-path-control.js", c.JS_EVAL_TYPE_GLOBAL);
        self.engine.freeValue(result);
    }
    fn expect(self: *Fixture, source: []const u8) !void {
        const result = try self.engine.eval(source, "actual-trust-path-assertion.js", c.JS_EVAL_TYPE_GLOBAL);
        defer self.engine.freeValue(result);
        try std.testing.expect(c.JS_ToBool(self.engine.context, result) == 1);
    }
    fn collect(self: *Fixture) void {
        self.engine.finishJob();
        c.JS_RunGC(self.engine.runtime);
    }
};

test "native project trust paths retains actual imports and one private helper evaluation" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.start();
    const again = try trust.create(f.engine, f.inputs);
    defer f.engine.freeValue(again);
    try f.expose("trustAgain", again);
    try f.expect(
        \\trustPaths===trustAgain &&
        \\Object.keys(trustPaths).join(',')==='getProjectTrustParentPath,getProjectTrustOptions,hasTrustRequiringProjectResources' &&
        \\trustPaths.getProjectTrustParentPath.name==='getProjectTrustParentPath' &&
        \\trustPaths.getProjectTrustParentPath.length===1 &&
        \\trustPaths.getProjectTrustOptions.length===2 &&
        \\trustPaths.hasTrustRequiringProjectResources.length===1 &&
        \\Object.hasOwn(trustPaths.getProjectTrustOptions,'prototype')
    );
    try std.testing.expect(!f.engine.native_module_names.contains("pi-private:actual-sdk-project-trust-paths"));
}
test "native project trust paths returns exact ordered persistent choices and fresh update ownership" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.expect(
        \\(()=>{const a=trustPaths.getProjectTrustOptions(trustCwd);
        \\const b=trustPaths.getProjectTrustOptions(trustCwd);
        \\const current=trustFS.realpathSync(trustCwd),parent=trustPath.dirname(current);
        \\return a.length===3 && a[0].label==='Trust' && a[0].trusted===true &&
        \\a[0].savedPath===current && a[0].updates.length===1 &&
        \\a[0].updates[0].path===current && a[0].updates[0].decision===true &&
        \\a[1].label==='Trust parent folder ('+parent+')' && a[1].trusted===true &&
        \\a[1].savedPath===parent && a[1].updates.length===2 &&
        \\a[1].updates[0].path===parent && a[1].updates[0].decision===true &&
        \\a[1].updates[1].path===current && a[1].updates[1].decision===null &&
        \\a[2].label==='Do not trust' && a[2].trusted===false &&
        \\a[2].updates[0].decision===false && a[2].savedPath===current &&
        \\Object.keys(a[1]).join(',')==='label,trusted,updates,savedPath' &&
        \\Object.keys(a[1].updates[1]).join(',')==='path,decision' &&
        \\a!==b && a[0]!==b[0] && a[0].updates!==b[0].updates &&
        \\a[0].updates[0]!==b[0].updates[0];})()
    );
}
test "native project trust paths session choices have no saved path or persistent updates" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.expect(
        \\(()=>{const a=trustPaths.getProjectTrustOptions(trustCwd,{includeSessionOnly:true});
        \\return a.length===5 && a[2].label==='Trust (this session only)' &&
        \\a[2].trusted===true && a[2].updates.length===0 && !Object.hasOwn(a[2],'savedPath') &&
        \\a[3].label==='Do not trust' && a[4].label==='Do not trust (this session only)' &&
        \\a[4].trusted===false && a[4].updates.length===0 && !Object.hasOwn(a[4],'savedPath') &&
        \\a[2].updates!==a[4].updates &&
        \\Object.keys(a[2]).join(',')==='label,trusted,updates';})()
    );
}
test "native project trust paths reads includeSessionOnly twice with original reentry order" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.expect(
        \\(()=>{let reads=0,nested;
        \\const a=trustPaths.getProjectTrustOptions(trustCwd,{get includeSessionOnly(){
        \\reads++;if(reads===1){nested=trustPaths.getProjectTrustOptions(trustCwd);return true;}return false;}});
        \\return reads===2 && nested.length===3 && a.length===4 &&
        \\a[2].label==='Trust (this session only)' && a[3].label==='Do not trust';})()
    );
}
test "native project trust paths options repeats live cwd normalization rather than caching first path" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.run(
        \\globalThis.trustCwdReads=0;
        \\globalThis.process=new Proxy(trustOriginalProcess,{get(t,k,r){
        \\if(k==='cwd')return ()=>{trustCwdReads++;return trustCwdReads===1?trustRoot:trustPath.join(trustRoot,'project');};
        \\return Reflect.get(t,k,r);}});
        \\globalThis.trustDifferent=trustPaths.getProjectTrustOptions('child');
        \\globalThis.process=trustOriginalProcess;
    );
    try f.expect(
        \\trustCwdReads===2 &&
        \\trustDifferent[0].savedPath===trustPath.resolve(trustRoot,'child') &&
        \\trustDifferent[1].savedPath===trustFS.realpathSync(trustPath.join(trustRoot,'project')) &&
        \\trustDifferent[1].updates[1].path===trustPath.resolve(trustRoot,'child')
    );
}
test "native project trust paths root parent is undefined and original functions remain constructible" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.expect(
        \\(()=>{const root=trustPath.parse(trustCwd).root;
        \\const a=trustPaths.getProjectTrustOptions(root,{includeSessionOnly:true});
        \\return trustPaths.getProjectTrustParentPath(root)===undefined &&
        \\a.length===4 && a[0].label==='Trust' && a[1].label==='Trust (this session only)' &&
        \\a[2].label==='Do not trust' && a[3].label==='Do not trust (this session only)' &&
        \\Array.isArray(new trustPaths.getProjectTrustOptions(trustCwd)) &&
        \\Object.getPrototypeOf(new trustPaths.getProjectTrustParentPath(root))===trustPaths.getProjectTrustParentPath.prototype;})()
    );
}

test "native project trust paths canonicalizes actual directories and falls back on a missing target" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.expect(
        \\(()=>{const spelling=trustPath.join(trustCwd,'.','..','child');
        \\const missing=trustPath.join(trustCwd,'not-created','deeper');
        \\const actual=trustPaths.getProjectTrustOptions(spelling);
        \\const absent=trustPaths.getProjectTrustOptions(missing);
        \\return actual[0].savedPath===trustFS.realpathSync(trustCwd) &&
        \\absent[0].savedPath===trustPath.resolve(missing) &&
        \\absent[1].savedPath===trustPath.dirname(trustPath.resolve(missing));})()
    );
}
test "native project trust paths detects every original config resource using actual disk and short circuit order" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.run(
        \\globalThis.trustExistsCalls=[];
        \\globalThis.trustOriginalExists=trustFS.existsSync;
        \\trustFS.existsSync=function(value){trustExistsCalls[trustExistsCalls.length]=value;return trustOriginalExists(value);};
    );
    try f.start();
    const names = [_][]const u8{ "settings.json", "mcp.json", "extensions", "skills", "prompts", "themes", "SYSTEM.md", "APPEND_SYSTEM.md" };
    for (names, 0..) |name, index| {
        const relative = try std.fmt.allocPrint(gpa, "resource-{d}/.pi/{s}", .{ index, name });
        defer gpa.free(relative);
        try f.disk.write(relative);
        const directory = try std.fmt.allocPrint(gpa, "resource-{d}", .{index});
        defer gpa.free(directory);
        const absolute = try f.disk.path(directory);
        defer gpa.free(absolute);
        try f.text("trustCandidate", absolute);
        try f.expose("trustResourceIndex", c.JS_NewUint32(f.engine.context, @intCast(index)));
        try f.expect(
            \\(()=>{trustExistsCalls.length=0;
            \\const found=trustPaths.hasTrustRequiringProjectResources(trustCandidate);
            \\const names=['settings.json','mcp.json','extensions','skills','prompts','themes','SYSTEM.md','APPEND_SYSTEM.md'];
            \\return found===true && trustExistsCalls.length===trustResourceIndex+1 &&
            \\trustExistsCalls.every((value,index)=>value===trustPath.join(trustCandidate,'.pi',names[index]));})()
        );
    }
}
test "native project trust paths checks only the original eight config entries and only cwd config directory" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.disk.write("project/child/.pi/packages.json");
    try f.disk.directory("project/child/.pi/npm");
    try f.disk.directory("project/child/.pi/git");
    try f.disk.write("project/.pi/settings.json");
    try f.run(
        \\globalThis.trustExistsCalls=[];
        \\globalThis.trustOriginalExists=trustFS.existsSync;
        \\trustFS.existsSync=function(value){trustExistsCalls[trustExistsCalls.length]=value;return trustOriginalExists(value);};
    );
    try f.start();
    try f.run("trustPaths.hasTrustRequiringProjectResources(trustCwd);");
    try f.expect(
        \\(()=>{const config=trustPath.join(trustCwd,'.pi');
        \\const wanted=['settings.json','mcp.json','extensions','skills','prompts','themes','SYSTEM.md','APPEND_SYSTEM.md'];
        \\return trustExistsCalls.slice(0,8).every((value,index)=>value===trustPath.join(config,wanted[index])) &&
        \\trustExistsCalls.filter(value=>value.startsWith(config+trustPath.sep)).length===8 &&
        \\!trustExistsCalls.includes(trustPath.join(trustRoot,'project','.pi','settings.json'));})()
    );
}
test "native project trust paths detects actual cwd and ancestor agent skills before reaching higher parents" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.disk.directory("project/.agents/skills");
    try f.run(
        \\globalThis.trustExistsCalls=[];
        \\globalThis.trustOriginalExists=trustFS.existsSync;
        \\trustFS.existsSync=function(value){trustExistsCalls[trustExistsCalls.length]=value;return trustOriginalExists(value);};
    );
    try f.start();
    try f.expect(
        \\trustPaths.hasTrustRequiringProjectResources(trustCwd)===true &&
        \\trustExistsCalls.length===10 &&
        \\trustExistsCalls[8]===trustPath.join(trustCwd,'.agents','skills') &&
        \\trustExistsCalls[9]===trustPath.join(trustRoot,'project','.agents','skills')
    );
    try f.disk.directory("project/child/.agents/skills");
    try f.expect(
        \\(()=>{trustExistsCalls.length=0;return trustPaths.hasTrustRequiringProjectResources(trustCwd)===true &&
        \\trustExistsCalls.length===9 && trustExistsCalls[8]===trustPath.join(trustCwd,'.agents','skills');})()
    );
}
test "native project trust paths excludes the canonical user skills path without probing its existence" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.disk.directory("home/.agents/skills");
    try f.disk.directory("home/work");
    try f.run(
        \\globalThis.trustExistsCalls=[];
        \\globalThis.trustOriginalExists=trustFS.existsSync;
        \\trustFS.existsSync=function(value){trustExistsCalls[trustExistsCalls.length]=value;return trustOriginalExists(value);};
    );
    try f.start();
    try f.run("trustPaths.hasTrustRequiringProjectResources(trustPath.join(trustHome,'work'));");
    try f.expect(
        \\!trustExistsCalls.includes(trustPath.join(trustFS.realpathSync(trustHome),'.agents','skills')) &&
        \\trustExistsCalls.includes(trustPath.join(trustHome,'work','.agents','skills'))
    );
    // No assertion assumes that unrelated real host ancestors lack resources.
}
test "native project trust paths reads live HOME before cwd and invokes imported homedir only for falsy HOME" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.run(
        \\globalThis.trustHomeEvents=[];
        \\globalThis.trustOriginalHomedir=trustOS.homedir;
        \\trustOS.homedir=function(){trustHomeEvents[trustHomeEvents.length]='homedir';return trustOriginalHomedir();};
    );
    try f.start();
    try f.run(
        \\globalThis.process=new Proxy(trustOriginalProcess,{get(t,k,r){
        \\if(k==='env')return {get HOME(){trustHomeEvents[trustHomeEvents.length]='HOME';return '';}};
        \\if(k==='cwd')return ()=>{trustHomeEvents[trustHomeEvents.length]='cwd';return trustOriginalProcess.cwd();};
        \\return Reflect.get(t,k,r);}});
        \\trustPaths.hasTrustRequiringProjectResources(trustCwd);
        \\globalThis.process=trustOriginalProcess;
    );
    try f.expect("trustHomeEvents[0]==='HOME' && trustHomeEvents[1]==='homedir' && trustHomeEvents.indexOf('cwd')>1");
    try f.run(
        \\trustHomeEvents.length=0;
        \\globalThis.process=new Proxy(trustOriginalProcess,{get(t,k,r){
        \\if(k==='env')return {get HOME(){trustHomeEvents[trustHomeEvents.length]='HOME';return trustHome;}};
        \\if(k==='cwd')return ()=>{trustHomeEvents[trustHomeEvents.length]='cwd';return trustOriginalProcess.cwd();};
        \\return Reflect.get(t,k,r);}});
        \\trustPaths.hasTrustRequiringProjectResources(trustCwd);
        \\globalThis.process=trustOriginalProcess;
    );
    try f.expect("trustHomeEvents[0]==='HOME' && !trustHomeEvents.includes('homedir') && trustHomeEvents.indexOf('cwd')===1");
}
test "native project trust paths live some observes the resource array and retains an authentic arrow after return" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.disk.write("project/child/.pi/mcp.json");
    try f.start();
    try f.run(
        \\globalThis.trustOriginalSome=Array.prototype.some;
        \\globalThis.trustSomeGets=0;
        \\Object.defineProperty(Array.prototype,'some',{configurable:true,get(){
        \\trustSomeGets++;return function(callback){globalThis.trustSavedArrow=callback;
        \\globalThis.trustSavedNames=this;return false;};}});
        \\trustPaths.hasTrustRequiringProjectResources(trustCwd);
        \\Object.defineProperty(Array.prototype,'some',{configurable:true,writable:true,value:trustOriginalSome});
    );
    f.collect();
    try f.expect(
        \\trustSomeGets===1 && trustSavedNames.join(',')==='settings.json,mcp.json,extensions,skills,prompts,themes,SYSTEM.md,APPEND_SYSTEM.md' &&
        \\trustSavedArrow.name==='' && trustSavedArrow.length===1 && !Object.hasOwn(trustSavedArrow,'prototype') &&
        \\trustSavedArrow.call({ignored:true},'mcp.json')===true &&
        \\trustSavedArrow('not-present.json')===false &&
        \\(()=>{try{Reflect.construct(trustSavedArrow,['mcp.json']);return false;}catch(e){return e instanceof TypeError;}})()
    );
}
test "native project trust paths preserves mutations to the one original private resource array" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.disk.write("project/child/.pi/custom-resource");
    try f.start();
    try f.run(
        \\globalThis.trustOriginalSome=Array.prototype.some;
        \\Array.prototype.some=function(callback){globalThis.trustMutableNames=this;
        \\this[0]='custom-resource';return Reflect.apply(trustOriginalSome,this,[callback]);};
        \\globalThis.trustFoundCustom=trustPaths.hasTrustRequiringProjectResources(trustCwd);
        \\Array.prototype.some=trustOriginalSome;
    );
    f.collect();
    try f.expect(
        \\trustFoundCustom===true && trustMutableNames[0]==='custom-resource' &&
        \\trustPaths.hasTrustRequiringProjectResources(trustCwd)===true
    );
}

test "native project trust paths captures real named imports before later public replacement" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.disk.write("project/child/.pi/mcp.json");
    try f.start();
    try f.run(
        \\globalThis.trustImportPoison={};
        \\trustFS.existsSync=()=>{throw trustImportPoison;};
        \\trustPath.dirname=()=>{throw trustImportPoison;};
        \\trustUtils.resolvePath=()=>{throw trustImportPoison;};
        \\trustUtils.canonicalizePath=()=>{throw trustImportPoison;};
    );
    try f.expect(
        \\trustPaths.hasTrustRequiringProjectResources(trustCwd)===true &&
        \\trustPaths.getProjectTrustParentPath(trustCwd)===trustPath.join(trustRoot,'project') &&
        \\trustPaths.getProjectTrustOptions(trustCwd).length===3
    );
}
test "native project trust paths preserves thrown some and options getter identities without writing trust decisions" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.expect(
        \\(()=>{const reason=Object.create(null);let optionsCaught=false,someCaught=false;
        \\try{trustPaths.getProjectTrustOptions(trustCwd,{get includeSessionOnly(){throw reason;}});}catch(e){optionsCaught=e===reason;}
        \\const descriptor=Object.getOwnPropertyDescriptor(Array.prototype,'some');
        \\Object.defineProperty(Array.prototype,'some',{configurable:true,get(){throw reason;}});
        \\try{trustPaths.hasTrustRequiringProjectResources(trustCwd);}catch(e){someCaught=e===reason;}
        \\finally{Object.defineProperty(Array.prototype,'some',descriptor);}
        \\return optionsCaught && someCaught && trustPaths.getProjectTrustOptions(trustCwd).length===3 &&
        \\!trustFS.existsSync(trustPath.join(trustCwd,'.pi','trust.json'));})()
    );
}
test "native project trust paths refuses mismatched warm owners while preserving the existing helper identity" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    const impostor = try f.engine.checked(c.JS_NewObject(f.engine.context));
    defer f.engine.freeValue(impostor);
    var changed = f.inputs;
    changed.filesystem = impostor;
    try std.testing.expectError(error.ActualProjectTrustPathsImportsChanged, trust.create(f.engine, changed));
    const again = try trust.create(f.engine, f.inputs);
    defer f.engine.freeValue(again);
    try f.expose("trustAfterMismatch", again);
    try f.expect("trustAfterMismatch===trustPaths && trustPaths.getProjectTrustOptions(trustCwd).length===3");
}
test "native project trust paths pending entry wins before import Gets or private cache publication" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.run(
        \\globalThis.trustImportGets=0;
        \\globalThis.trustOriginalExists=trustFS.existsSync;
        \\Object.defineProperty(trustFS,'existsSync',{configurable:true,get(){trustImportGets++;return trustOriginalExists;}});
    );
    const reason = try f.engine.checked(c.JS_NewError(f.engine.context));
    defer f.engine.freeValue(reason);
    _ = c.JS_Throw(f.engine.context, c.JS_DupValue(f.engine.context, reason));
    try std.testing.expectError(error.JavaScriptException, trust.create(f.engine, f.inputs));
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, reason,
        f.engine.captured_exception orelse return error.ActualPendingTrustReasonRequired));
    try std.testing.expect(!f.engine.native_module_values.contains("pi-private:actual-sdk-project-trust-paths"));
    try f.expect("trustImportGets===0");
    try f.start();
    try f.expect("trustImportGets===1");
}
var active_fixture: ?*Fixture = null;
var reentry_calls: usize = 0;
fn reenterCreate(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue,
    _: []const c.JSValue) !c.JSValue
{
    const current = active_fixture orelse return error.ActualTrustReentryFixtureRequired;
    if (current.engine != engine) return error.ActualTrustReentryEngineRequired;
    try std.testing.expect(!engine.native_module_values.contains("pi-private:actual-sdk-project-trust-paths"));
    reentry_calls += 1;
    return trust.create(engine, current.inputs);
}
test "native project trust paths import getter reentry cannot publish a partial private evaluation" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    active_fixture = &f; defer active_fixture = null; reentry_calls = 0;
    const reenter = try v.function.create(f.engine, "reenterTrustCreation", 0, reenterCreate, &.{});
    defer f.engine.freeValue(reenter);
    try f.expose("reenterTrustCreation", reenter);
    try f.run(
        \\globalThis.trustOriginalExists=trustFS.existsSync;
        \\globalThis.trustCreationReentry=false;
        \\Object.defineProperty(trustFS,'existsSync',{configurable:true,get(){
        \\try{reenterTrustCreation();}catch(e){trustCreationReentry=e instanceof TypeError && e.message.includes('ActualProjectTrustPathsCreationReentry');}
        \\return trustOriginalExists;}});
    );
    try f.start();
    try std.testing.expectEqual(@as(usize, 1), reentry_calls);
    try f.expect("trustCreationReentry && trustPaths.getProjectTrustOptions(trustCwd).length===3");
}
test "native project trust paths actual application entry rejects a retired owner before reading its imports" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var retired: application.Owner = .{ .engine = f.engine, .inputs = null, .auth = null,
        .application = c.pi_js_undefined(), .live = false };
    try std.testing.expectError(error.ActualSdkApplicationOwnerRetired, retired.createProjectTrustPaths());
    try std.testing.expect(!f.engine.native_module_values.contains("pi-private:actual-sdk-project-trust-paths"));
}
test "native project trust paths genuine allocation failure publishes no cache and preserves native fatal reason" {
    var failing = std.testing.FailingAllocator.init(gpa, .{});
    var f: Fixture = undefined; try f.initWithAllocator(failing.allocator()); defer f.deinit();
    failing.fail_index = failing.alloc_index;
    const attempted = trust.create(f.engine, f.inputs);
    failing.fail_index = std.math.maxInt(usize);
    try std.testing.expectError(error.JavaScriptException, attempted);
    const reason = f.engine.captured_exception orelse return error.ActualTrustAllocationReasonRequired;
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(f.engine.native_fatal_invocation == null);
    try std.testing.expect(!f.engine.native_module_values.contains("pi-private:actual-sdk-project-trust-paths"));
    c.JS_ClearUncatchableError(f.engine.context, reason);
    try f.start();
    try f.expect("trustPaths.getProjectTrustOptions(trustCwd).length===3");
}
test "native project trust paths preserves ordinary push calls and object literal data definitions" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.expect(
        \\(()=>{const original=Object.getOwnPropertyDescriptor(Array.prototype,'push');
        \\const labels=Object.getOwnPropertyDescriptor(Object.prototype,'label');
        \\let gets=0,calls=0,sets=0;
        \\Object.defineProperty(Object.prototype,'label',{configurable:true,set(){sets++;throw new Error('wrong object assignment');}});
        \\Object.defineProperty(Array.prototype,'push',{configurable:true,get(){gets++;return function(row){calls++;
        \\return Reflect.apply(original.value,this,[row]);};}});
        \\let choices;try{choices=trustPaths.getProjectTrustOptions(trustCwd,{includeSessionOnly:true});}
        \\finally{Object.defineProperty(Array.prototype,'push',original);
        \\if(labels)Object.defineProperty(Object.prototype,'label',labels);else delete Object.prototype.label;}
        \\return gets===4 && calls===4 && sets===0 && choices.length===5 &&
        \\Object.hasOwn(choices[0],'label') && choices[0].label==='Trust';})()
    );
}

// Genuine auth/frontend fixture from the accepted application print-owner
// controls. This assembles the real runtime imports without manufacturing a
// completed application/session or canonical Module owner.
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

test "native project trust paths genuine auth owner creates one module surviving host retirement" {
    var fixture: ActualTrustApplication.Fixture = undefined; try fixture.init(); defer fixture.deinit();
    var s: v.Scope = .{ .engine = fixture.engine }; defer s.deinit();
    const api = try v.own(&s, try fixture.owner().createProjectTrustPaths());
    const repeated = try v.own(&s, try fixture.owner().createProjectTrustPaths());
    try std.testing.expect(c.JS_IsStrictEqual(s.engine.context, api, repeated));
    try fixture.owner().deinit();
    try std.testing.expectError(error.ActualSdkAuthOwnerRetired, fixture.owner().createProjectTrustPaths());
    const options = try v.call(&s, try v.get(&s, api, "getProjectTrustOptions"), c.pi_js_undefined(), &.{try v.text(&s, ".")});
    const length = try v.get(&s, options, "length");
    try std.testing.expect(!c.JS_IsUndefined(length));
    try std.testing.expect(c.JS_IsFunction(s.engine.context, try v.get(&s, api, "hasTrustRequiringProjectResources")));
}
test "native project trust paths genuine auth rejects a foreign runtime before property access" {
    var fixture: ActualTrustApplication.Fixture = undefined; try fixture.init(); defer fixture.deinit();
    var s: v.Scope = .{ .engine = fixture.engine }; defer s.deinit();
    const invalid = try ActualTrustApplication.foreign(&s);
    const actual = fixture.owner();
    const previous = actual.runtime_imports;
    actual.runtime_imports = c.JS_DupValue(s.engine.context, invalid);
    s.engine.freeValue(previous);
    try ActualTrustApplication.expectForeign(&s, actual, "ActualSdkTrustRuntimeNamespaceChanged");
}
test "native project trust paths genuine auth rejects a foreign platform before child imports" {
    var fixture: ActualTrustApplication.Fixture = undefined; try fixture.init(); defer fixture.deinit();
    var s: v.Scope = .{ .engine = fixture.engine }; defer s.deinit();
    try v.put(&s, fixture.owner().runtime_imports, "platform", try ActualTrustApplication.foreign(&s));
    try ActualTrustApplication.expectForeign(&s, fixture.owner(), "ActualSdkTrustPlatformNamespaceChanged");
}
test "native project trust paths authenticates each filesystem path utilities and config provider" {
    inline for (.{
        .{ "filesystem", "ActualSdkTrustFilesystemNamespaceChanged", false },
        .{ "paths", "ActualSdkTrustPathsNamespaceChanged", false },
        .{ "pathUtilities", "ActualSdkTrustUtilitiesNamespaceChanged", false },
        .{ "configuration", "ActualSdkTrustConfigurationNamespaceChanged", true },
    }) |entry| {
        var fixture: ActualTrustApplication.Fixture = undefined; try fixture.init(); defer fixture.deinit();
        var s: v.Scope = .{ .engine = fixture.engine }; defer s.deinit();
        const target = if (entry[2]) fixture.owner().runtime_imports else try v.get(&s, fixture.owner().runtime_imports, "platform");
        try v.put(&s, target, entry[0], try ActualTrustApplication.foreign(&s));
        try ActualTrustApplication.expectForeign(&s, fixture.owner(), entry[1]);
    }
}
test "native project trust paths actual owner preserves public member mutation before one time capture" {
    var fixture: ActualTrustApplication.Fixture = undefined; try fixture.init(); defer fixture.deinit();
    var disk = try Disk.init(); defer disk.deinit();
    var s: v.Scope = .{ .engine = fixture.engine }; defer s.deinit();
    const filesystem = s.engine.native_module_values.get("node:fs") orelse return error.RequiredActualFilesystem;
    const global = try v.own(&s, c.JS_GetGlobalObject(s.engine.context));
    try v.put(&s, global, "__trustActualFilesystem", filesystem);
    _ = try v.own(&s, try s.engine.eval(
        \\globalThis.__trustActualExistsCalls=0;
        \\{const original=__trustActualFilesystem.existsSync;
        \\__trustActualFilesystem.existsSync=function(...args){__trustActualExistsCalls++;return Reflect.apply(original,this,args)};}
    , "actual-trust-member-capture.js", c.JS_EVAL_TYPE_GLOBAL));
    const api = try v.own(&s, try fixture.owner().createProjectTrustPaths());
    _ = try v.own(&s, try s.engine.eval(
        \\__trustActualFilesystem.existsSync=function(){throw Error("captured actual member must survive later mutation")};
    , "actual-trust-after-capture.js", c.JS_EVAL_TYPE_GLOBAL));
    const result = try v.call(&s, try v.get(&s, api, "hasTrustRequiringProjectResources"), c.pi_js_undefined(), &.{try v.text(&s, disk.root)});
    try std.testing.expect(c.JS_IsBool(result));
    const checked = try v.own(&s, try s.engine.eval("__trustActualExistsCalls>=8", "actual-trust-member-count.js", c.JS_EVAL_TYPE_GLOBAL));
    try std.testing.expect(c.JS_ToBool(s.engine.context, checked) == 1);
}
test "native project trust paths actual module roots survive carrier getter owner retirement" {
    var fixture: ActualTrustApplication.Fixture = undefined; try fixture.init(); defer fixture.deinit();
    var s: v.Scope = .{ .engine = fixture.engine }; defer s.deinit();
    const probe = try ActualTrustApplication.installProbe(&s, fixture.owner(), .retire_owner);
    const api = try v.own(&s, try fixture.owner().createProjectTrustPaths());
    try std.testing.expect(!fixture.owner().live);
    try std.testing.expectEqual(@as(usize, 1), probe.platform_reads);
    try std.testing.expectEqual(@as(usize, 1), probe.filesystem_reads);
    try std.testing.expect(c.JS_IsFunction(s.engine.context, try v.get(&s, api, "getProjectTrustOptions")));
    _ = try v.call(&s, try v.get(&s, api, "getProjectTrustOptions"), c.pi_js_undefined(), &.{try v.text(&s, ".")});
}
test "native project trust paths pending carrier exception stops identity reads and private publication" {
    try ActualTrustApplication.verifyPending(false);
}
test "native project trust paths actual fatal carrier completion survives provider root retirement" {
    try ActualTrustApplication.verifyPending(true);
}
