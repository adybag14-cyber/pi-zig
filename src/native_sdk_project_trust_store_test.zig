//! Focused actual-VM and physical filesystem controls for ProjectTrustStore.
//! Source-only declarations: this packet has not been parsed/compiled/executed.
const std = @import("std");
const em = @import("extensions/engine.zig");
const h = @import("extensions/native_sdk_session_locals.zig");
const v = h.v;
const c = em.c;
const trust = @import("extensions/native_sdk_project_trust_store.zig");
const gpa = std.testing.allocator;

const Fixture = struct {
    temporary: std.testing.TmpDir,
    root: []u8,
    environment: std.process.Environ.Map,
    engine: *em.Engine = undefined,
    engine_alive: bool = false,
    utilities: ?c.JSValue = null,
    text_utilities: ?c.JSValue = null,
    lockfile: ?c.JSValue = null,
    inputs: trust.Inputs = undefined,

    fn init(self: *Fixture) !void { return self.initWithAllocator(gpa); }
    fn initWithAllocator(self: *Fixture, allocator: std.mem.Allocator) !void {
        var temporary = std.testing.tmpDir(.{});
        var transferred = false;
        errdefer if (!transferred) temporary.cleanup();
        var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const length = try temporary.dir.realPath(std.testing.io, &buffer);
        const root_path = try gpa.dupe(u8, buffer[0..length]);
        self.* = .{ .temporary = temporary, .root = root_path, .environment = .init(gpa) };
        transferred = true;
        errdefer self.deinit();
        try self.temporary.dir.createDirPath(std.testing.io, "project/child");
        try self.environment.put("HOME", root_path);
        try self.environment.put("USERPROFILE", root_path);
        self.engine = try em.Engine.init(allocator, .{ .interrupt_budget = 1_000_000 });
        self.engine_alive = true;
        self.engine.native_io = std.testing.io;
        try @import("extensions/timers.zig").install(self.engine, std.testing.io);
        try @import("extensions/native_process.zig").install(self.engine, std.testing.io, &self.environment, &.{"trust-store-controls"});
        try @import("extensions/node_path.zig").install(self.engine, std.testing.io);
        try @import("extensions/node_url.zig").install(self.engine);
        try @import("extensions/node_fs.zig").install(self.engine, std.testing.io);
        const filesystem = self.engine.native_module_values.get("node:fs") orelse return error.ActualFilesystemRequired;
        const paths = self.engine.native_module_values.get("node:path") orelse return error.ActualPathsRequired;
        self.utilities = try @import("extensions/native_sdk_path_utilities_namespace.zig").create(self.engine, filesystem);
        self.text_utilities = try @import("extensions/native_sdk_text_helpers.zig").create(self.engine);
        self.lockfile = try @import("extensions/native_auth_directory_lock.zig").create(self.engine);
        self.inputs = .{ .filesystem = filesystem, .paths = paths, .path_utilities = self.utilities.?,
            .text_utilities = self.text_utilities.?, .lockfile = self.lockfile.? };
        try self.expose("trustFS", filesystem);
        try self.expose("trustPath", paths);
        try self.expose("trustUtils", self.utilities.?);
        try self.expose("trustText", self.text_utilities.?);
        try self.expose("trustLock", self.lockfile.?);
        try self.text("trustRoot", root_path);
        try self.run(
            \\globalThis.trustAgent=trustPath.join(trustRoot,'agent');
            \\globalThis.trustCwd=trustPath.join(trustRoot,'project','child');
            \\globalThis.trustFile=trustPath.join(trustAgent,'trust.json');
            \\globalThis.trustOriginalFS={existsSync:trustFS.existsSync,mkdirSync:trustFS.mkdirSync,
            \\readFileSync:trustFS.readFileSync,writeFileSync:trustFS.writeFileSync};
        );
    }
    fn deinit(self: *Fixture) void {
        if (self.engine_alive) {
            if (self.lockfile) |value| self.engine.freeValue(value);
            if (self.text_utilities) |value| self.engine.freeValue(value);
            if (self.utilities) |value| self.engine.freeValue(value);
            self.engine.deinit();
            self.engine_alive = false;
        }
        self.environment.deinit();
        gpa.free(self.root);
        self.temporary.cleanup();
    }
    fn exposeBody(s: *v.Scope, name: [*:0]const u8, value: c.JSValue) !void {
        const global = try v.own(s, c.JS_GetGlobalObject(s.engine.context));
        try v.put(s, global, name, value);
    }
    fn expose(self: *Fixture, name: [*:0]const u8, value: c.JSValue) !void {
        return h.statement(self.engine, exposeBody, .{ name, value });
    }
    fn text(self: *Fixture, name: [*:0]const u8, bytes: []const u8) !void {
        const value = try h.text(self.engine, bytes);
        defer self.engine.freeValue(value);
        return self.expose(name, value);
    }
    fn start(self: *Fixture) !void {
        const constructor_value = try trust.create(self.engine, self.inputs);
        defer self.engine.freeValue(constructor_value);
        try self.expose("ProjectTrustStore", constructor_value);
    }
    fn run(self: *Fixture, source: []const u8) !void {
        const result = try self.engine.eval(source, "actual-trust-store-control.js", c.JS_EVAL_TYPE_GLOBAL);
        self.engine.freeValue(result);
    }
    fn expect(self: *Fixture, source: []const u8) !void {
        const result = try self.engine.eval(source, "actual-trust-store-assertion.js", c.JS_EVAL_TYPE_GLOBAL);
        defer self.engine.freeValue(result);
        try std.testing.expect(c.JS_ToBool(self.engine.context, result) == 1);
    }
    fn collect(self: *Fixture) void {
        self.engine.finishJob();
        c.JS_RunGC(self.engine.runtime);
    }
};

test "native project trust store owns one complete ordinary class per exact import graph" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    const again = try trust.create(f.engine, f.inputs); defer f.engine.freeValue(again);
    try f.expose("trustAgain", again);
    try f.expect(
        \\ProjectTrustStore===trustAgain && ProjectTrustStore.name==='ProjectTrustStore' &&
        \\ProjectTrustStore.length===1 &&
        \\Object.getOwnPropertyNames(ProjectTrustStore.prototype).join(',')==='constructor,get,getEntry,set,setMany' &&
        \\Object.keys(ProjectTrustStore.prototype).length===0 &&
        \\['get','getEntry','setMany'].every(name=>ProjectTrustStore.prototype[name].length===1) &&
        \\ProjectTrustStore.prototype.set.length===2 &&
        \\['get','getEntry','set','setMany'].every(name=>!Object.hasOwn(ProjectTrustStore.prototype[name],'prototype'))
    );
    try std.testing.expect(!f.engine.native_module_names.contains("pi-private:actual-sdk-project-trust-store"));
}
test "native project trust store constructor resolves the original own trustPath field" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.expect(
        \\(()=>{let inherited=0;
        \\Object.defineProperty(ProjectTrustStore.prototype,'trustPath',{set(){inherited++;},configurable:true});
        \\try{const s=new ProjectTrustStore(trustAgent);
        \\const d=Object.getOwnPropertyDescriptor(s,'trustPath');
        \\let plain=false;try{ProjectTrustStore(trustAgent)}catch(e){plain=e instanceof TypeError}
        \\return inherited===0 && d.value===trustFile && d.enumerable && d.writable && d.configurable && plain;
        \\}finally{delete ProjectTrustStore.prototype.trustPath;}})()
    );
}
test "native project trust store missing reads acquire and release the file-specific directory lock" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.run(
        \\globalThis.trustTrace=[];
        \\trustFS.existsSync=function(p){trustTrace.push([p,trustOriginalFS.existsSync(trustFile+'.lock')]);return trustOriginalFS.existsSync(p);};
    );
    try f.start();
    try f.expect(
        \\(()=>{const s=new ProjectTrustStore(trustAgent),a=s.getEntry(trustCwd),b=s.get(trustCwd);
        \\return a===null && b===null && trustOriginalFS.existsSync(trustAgent) &&
        \\!trustOriginalFS.existsSync(trustFile) && !trustOriginalFS.existsSync(trustFile+'.lock') &&
        \\!trustOriginalFS.existsSync(trustAgent+'.lock') &&
        \\trustTrace.length===2 && trustTrace.every(r=>r[0]===trustFile&&r[1]);})()
    );
}
test "native project trust store writes canonical sorted decisions with original utf8 newline format" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.expect(
        \\(()=>{const s=new ProjectTrustStore(trustAgent);
        \\const child=trustUtils.canonicalizePath(trustUtils.resolvePath(trustCwd));
        \\const parent=trustPath.dirname(child);
        \\s.setMany([{path:child,decision:false},{path:parent,decision:true}]);
        \\const expected={};for(const k of [child,parent].sort())expected[k]=k===child?false:true;
        \\return trustFS.readFileSync(trustFile,'utf-8')===JSON.stringify(expected,null,2)+'\n' &&
        \\s.get(child)===false && s.get(parent)===true && !trustFS.existsSync(trustFile+'.lock');})()
    );
}
test "native project trust store nearest ancestor fallback follows null deletion and false overrides" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.expect(
        \\(()=>{const s=new ProjectTrustStore(trustAgent),child=trustFS.realpathSync(trustCwd),parent=trustPath.dirname(child);
        \\s.set(parent,true);s.set(child,false);const first=s.getEntry(child);
        \\s.set(child,null);const second=s.getEntry(child),data=JSON.parse(trustFS.readFileSync(trustFile,'utf-8'));
        \\return first.path===child && first.decision===false && second.path===parent &&
        \\second.decision===true && !Object.hasOwn(data,child) && data[parent]===true &&
        \\Object.keys(second).join(',')==='path,decision';})()
    );
}
test "native project trust store reads BOM and skips stored null while preserving the file" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.expect(
        \\(()=>{const child=trustFS.realpathSync(trustCwd),parent=trustPath.dirname(child),data={};
        \\data[parent]=false;data[child]=null;const raw='\ufeff'+JSON.stringify(data);
        \\trustFS.mkdirSync(trustAgent,{recursive:true});trustFS.writeFileSync(trustFile,raw,'utf-8');
        \\const row=new ProjectTrustStore(trustAgent).getEntry(child);
        \\return row.path===parent && row.decision===false && trustFS.readFileSync(trustFile,'utf-8')===raw;})()
    );
}
test "native project trust store wraps malformed JSON and releases the acquired directory" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.expect(
        \\(()=>{trustFS.mkdirSync(trustAgent,{recursive:true});trustFS.writeFileSync(trustFile,'{bad','utf-8');
        \\let reason;try{new ProjectTrustStore(trustAgent).get(trustCwd)}catch(e){reason=e}
        \\return reason instanceof Error && reason.message.startsWith('Failed to read trust store '+trustFile+': ') &&
        \\!trustFS.existsSync(trustFile+'.lock') && trustFS.readFileSync(trustFile,'utf-8')==='{bad';})()
    );
}
test "native project trust store rejects every original invalid parsed top-level kind" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.expect(
        \\(()=>{trustFS.mkdirSync(trustAgent,{recursive:true});trustFS.writeFileSync(trustFile,'{}','utf-8');
        \\const parse=JSON.parse,s=new ProjectTrustStore(trustAgent);
        \\try{return [null,[],true,false,0,'x',undefined,()=>{}].every(value=>{
        \\JSON.parse=()=>value;try{s.get(trustCwd);return false;}catch(e){
        \\return e.message==='Invalid trust store '+trustFile+': expected an object';}});
        \\}finally{JSON.parse=parse;}})()
    );
}
test "native project trust store rejects invalid entry decisions with the original quoted-key message" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.expect(
        \\(()=>{trustFS.mkdirSync(trustAgent,{recursive:true});trustFS.writeFileSync(trustFile,'{}','utf-8');
        \\const parse=JSON.parse,s=new ProjectTrustStore(trustAgent),key='odd "key"';
        \\try{return [undefined,0,1,'true',{},[]].every(value=>{
        \\JSON.parse=()=>({[key]:value});try{s.get(trustCwd);return false;}catch(e){
        \\return e.message==='Invalid trust store '+trustFile+': value for '+JSON.stringify(key)+' must be true, false, or null';}});
        \\}finally{JSON.parse=parse;}})()
    );
}
test "native project trust store plain data preserves inherited lookup and proto assignment" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.expect(
        \\(()=>{const cwd=trustFS.realpathSync(trustCwd),s=new ProjectTrustStore(trustAgent);
        \\Object.defineProperty(Object.prototype,cwd,{value:true,writable:true,configurable:true});
        \\try{const inherited=s.get(cwd);
        \\trustFS.writeFileSync(trustFile,'{"__proto__":null}','utf-8');
        \\const nulled=s.get(cwd);return inherited===true&&nulled===null;
        \\}finally{delete Object.prototype[cwd];}})()
    );
}
test "native project trust store get preserves virtual dispatch and nullish decision semantics" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.expect(
        \\(()=>{const method=ProjectTrustStore.prototype.get,values=[null,undefined,{decision:null},{decision:undefined},{decision:false},{decision:0},{decision:''}];
        \\const expected=[null,null,null,null,false,0,''];let calls=0;
        \\return values.every((row,i)=>method.call({getEntry(cwd){calls++;if(cwd!==trustCwd)throw Error('cwd');return row;}},trustCwd)===expected[i])&&calls===7;})()
    );
}
test "native project trust store set looks up the live method before constructing its fresh update" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.expect(
        \\(()=>{let gets=0,calls=0,last;
        \\const receiver={get setMany(){gets++;return function(rows){calls++;if(this!==receiver)throw Error('receiver');last=rows;return 91;};}};
        \\const result=ProjectTrustStore.prototype.set.call(receiver,trustCwd,false),first=last;
        \\ProjectTrustStore.prototype.set.call(receiver,trustCwd,null);
        \\return result===undefined&&gets===2&&calls===2&&first!==last&&first[0]!==last[0]&&
        \\first.length===1&&first[0].path===trustCwd&&first[0].decision===false&&last[0].decision===null&&
        \\Object.keys(first[0]).join(',')==='path,decision';})()
    );
}

test "native project trust store rereads trustPath for lock read and final write" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.expect(
        \\(()=>{trustFS.mkdirSync(trustAgent,{recursive:true});
        \\const paths=['a.json','b.json','c.json'].map(x=>trustPath.join(trustAgent,x));
        \\trustFS.writeFileSync(paths[1],'{}','utf-8');let reads=0,selected,releaseCount=0;
        \\const lockSync=trustLock.lockSync;
        \\trustLock.lockSync=function(dir,options){selected=options.lockfilePath;const release=lockSync.call(this,dir,options);
        \\return()=>{releaseCount++;release();};};
        \\try{ProjectTrustStore.prototype.setMany.call({get trustPath(){return paths[reads++];}},[]);
        \\return reads===3 && selected===paths[0]+'.lock' && releaseCount===1 &&
        \\trustFS.readFileSync(paths[2],'utf-8')==='{}\n' && !trustFS.existsSync(paths[0]) &&
        \\!trustFS.existsSync(paths[0]+'.lock');}finally{trustLock.lockSync=lockSync;}})()
    );
}
test "native project trust store retains named imports while reading lockSync live per use" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.run(
        \\globalThis.writeCalls=0;globalThis.lockReads=0;
        \\trustFS.writeFileSync=function(...args){writeCalls++;return trustOriginalFS.writeFileSync(...args);};
    );
    try f.start();
    try f.expect(
        \\(()=>{const original=trustLock.lockSync;
        \\Object.defineProperty(trustLock,'lockSync',{configurable:true,get(){lockReads++;return original;}});
        \\trustFS.writeFileSync=()=>{throw Error('foreign late named function');};
        \\const s=new ProjectTrustStore(trustAgent);s.set(trustCwd,true);
        \\return writeCalls===1 && lockReads===1 && s.get(trustCwd)===true;})()
    );
}
test "native project trust store reads the JSON parse callee before captured file and BOM calls" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.run(
        \\globalThis.parseOrder=[];const strip=trustText.stripBom;
        \\trustFS.readFileSync=function(...args){parseOrder.push('read');return trustOriginalFS.readFileSync(...args);};
        \\trustText.stripBom=function(value){parseOrder.push('bom');return strip(value);};
        \\trustOriginalFS.mkdirSync(trustAgent,{recursive:true});trustOriginalFS.writeFileSync(trustFile,'{}','utf-8');
    );
    try f.start();
    try f.expect(
        \\(()=>{const descriptor=Object.getOwnPropertyDescriptor(JSON,'parse');
        \\Object.defineProperty(JSON,'parse',{configurable:true,get(){parseOrder.push('parse-get');
        \\return function(value){parseOrder.push('parse-call');if(this!==JSON)throw Error('JSON receiver');return descriptor.value(value);};}});
        \\try{new ProjectTrustStore(trustAgent).get(trustCwd);
        \\return parseOrder.join(',')==='parse-get,read,bom,parse-call';}
        \\finally{Object.defineProperty(JSON,'parse',descriptor);}})()
    );
}
test "native project trust store keeps exists errors outside the read formatting catch" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.run(
        \\globalThis.existsReason={kind:'exists'};globalThis.readReason={toString(){return 'read marker';}};
        \\globalThis.readMode='exists';
        \\trustFS.existsSync=function(path){if(readMode==='exists')throw existsReason;return trustOriginalFS.existsSync(path);};
        \\trustFS.readFileSync=function(){throw readReason;};
        \\trustOriginalFS.mkdirSync(trustAgent,{recursive:true});trustOriginalFS.writeFileSync(trustFile,'{}','utf-8');
    );
    try f.start();
    try f.expect(
        \\(()=>{const s=new ProjectTrustStore(trustAgent);let first,second;
        \\try{s.get(trustCwd)}catch(e){first=e}readMode='read';try{s.get(trustCwd)}catch(e){second=e}
        \\return first===existsReason && second instanceof Error &&
        \\second.message==='Failed to read trust store '+trustFile+': read marker' &&
        \\!trustOriginalFS.existsSync(trustFile+'.lock');})()
    );
}
test "native project trust store Error message getter supersedes the read failure before release" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.run(
        \\globalThis.messageReason={message:'getter'};globalThis.readReason=new Error('old');
        \\Object.defineProperty(readReason,'message',{get(){throw messageReason;}});
        \\trustFS.readFileSync=function(){throw readReason;};
        \\trustOriginalFS.mkdirSync(trustAgent,{recursive:true});trustOriginalFS.writeFileSync(trustFile,'{}','utf-8');
    );
    try f.start();
    try f.expect(
        \\(()=>{let reason;try{new ProjectTrustStore(trustAgent).get(trustCwd)}catch(e){reason=e}
        \\return reason===messageReason&&!trustOriginalFS.existsSync(trustFile+'.lock');})()
    );
}
test "native project trust store Array validation is short circuited for nonobjects" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.expect(
        \\(()=>{trustFS.mkdirSync(trustAgent,{recursive:true});trustFS.writeFileSync(trustFile,'{}','utf-8');
        \\const parse=JSON.parse,descriptor=Object.getOwnPropertyDescriptor(Array,'isArray'),marker={};
        \\let reads=0,first,second;JSON.parse=()=>()=>{};
        \\Object.defineProperty(Array,'isArray',{configurable:true,get(){reads++;throw marker;}});
        \\try{const s=new ProjectTrustStore(trustAgent);try{s.get(trustCwd)}catch(e){first=e}
        \\JSON.parse=()=>({});try{s.get(trustCwd)}catch(e){second=e}
        \\return first.message==='Invalid trust store '+trustFile+': expected an object'&&second===marker&&reads===1;
        \\}finally{JSON.parse=parse;Object.defineProperty(Array,'isArray',descriptor);}})()
    );
}
test "native project trust store entries use two actual binding steps and normal inner close" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.expect(
        \\(()=>{trustFS.mkdirSync(trustAgent,{recursive:true});trustFS.writeFileSync(trustFile,'{}','utf-8');
        \\const entries=Object.entries,key=trustFS.realpathSync(trustCwd);
        \\let innerSteps=0,innerCloses=0,outerSteps=0;
        \\const row={[Symbol.iterator](){return{next(){innerSteps++;return{done:false,value:innerSteps===1?key:true};},
        \\return(){innerCloses++;return{};}};}};
        \\Object.entries=()=>({[Symbol.iterator](){return{next(){return ++outerSteps===1?{done:false,value:row}:{done:true};}};}});
        \\try{const found=new ProjectTrustStore(trustAgent).getEntry(trustCwd);
        \\return found.path===key&&found.decision===true&&innerSteps===2&&innerCloses===1&&outerSteps===2;}
        \\finally{Object.entries=entries;}})()
    );
}
test "native project trust store malformed normal inner close closes the outer iterator" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.expect(
        \\(()=>{trustFS.mkdirSync(trustAgent,{recursive:true});trustFS.writeFileSync(trustFile,'{}','utf-8');
        \\const entries=Object.entries,key=trustFS.realpathSync(trustCwd);let count=0,outerClose=0;
        \\const row={[Symbol.iterator](){return{next(){return{done:false,value:++count===1?key:true};},return(){return 1;}};}};
        \\Object.entries=()=>({[Symbol.iterator](){return{next(){return{done:false,value:row};},return(){outerClose++;return{};}};}});
        \\try{let reason;try{new ProjectTrustStore(trustAgent).get(trustCwd)}catch(e){reason=e}
        \\return reason instanceof TypeError&&count===2&&outerClose===1&&!trustFS.existsSync(trustFile+'.lock');}
        \\finally{Object.entries=entries;}})()
    );
}
test "native project trust store validation throw wins over ordinary outer close failure" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.expect(
        \\(()=>{trustFS.mkdirSync(trustAgent,{recursive:true});trustFS.writeFileSync(trustFile,'{}','utf-8');
        \\const entries=Object.entries,closeReason={};let closes=0;
        \\Object.entries=()=>({[Symbol.iterator](){return{next(){return{done:false,value:['bad',91]};},
        \\return(){closes++;throw closeReason;}};}});
        \\try{let reason;try{new ProjectTrustStore(trustAgent).get(trustCwd)}catch(e){reason=e}
        \\return reason instanceof Error&&reason!==closeReason&&closes===1&&
        \\reason.message==='Invalid trust store '+trustFile+': value for "bad" must be true, false, or null'&&
        \\!trustFS.existsSync(trustFile+'.lock');}finally{Object.entries=entries;}})()
    );
}
test "native project trust store update bindings precede original normalization and persistence" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.run(
        \\globalThis.updateOrder=[];const resolve=trustUtils.resolvePath,canonical=trustUtils.canonicalizePath;
        \\trustUtils.resolvePath=function(value){updateOrder.push('resolve');return resolve(value);};
        \\trustUtils.canonicalizePath=function(value){updateOrder.push('canonical');return canonical(value);};
        \\trustFS.writeFileSync=function(...args){updateOrder.push('write');return trustOriginalFS.writeFileSync(...args);};
    );
    try f.start();
    try f.expect(
        \\(()=>{const s=new ProjectTrustStore(trustAgent);updateOrder.length=0;
        \\s.setMany([{get path(){updateOrder.push('path');return trustCwd;},
        \\get decision(){updateOrder.push('decision');return false;}}]);
        \\return updateOrder.join(',')==='path,decision,resolve,canonical,write';})()
    );
}
test "native project trust store abrupt decision getter closes the iterator before release" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.expect(
        \\(()=>{const marker={},closeReason={},events=[],lockSync=trustLock.lockSync;
        \\trustLock.lockSync=function(...args){const release=lockSync.apply(this,args);return()=>{events.push('release');release();};};
        \\const row={path:trustCwd,get decision(){events.push('decision');throw marker;}};
        \\const updates={[Symbol.iterator](){return{next(){return{done:false,value:row};},
        \\return(){events.push('close');throw closeReason;}};}};
        \\try{let reason;try{new ProjectTrustStore(trustAgent).setMany(updates)}catch(e){reason=e}
        \\return reason===marker&&events.join(',')==='decision,close,release'&&!trustFS.existsSync(trustFile);}
        \\finally{trustLock.lockSync=lockSync;}})()
    );
}
test "native project trust store iterator step failure releases without an invented close" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.expect(
        \\(()=>{const marker={},events=[],lockSync=trustLock.lockSync;
        \\trustLock.lockSync=function(...args){const release=lockSync.apply(this,args);return()=>{events.push('release');release();};};
        \\const updates={[Symbol.iterator](){return{next(){events.push('next');throw marker;},
        \\return(){events.push('close');return{};}};}};
        \\try{let reason;try{new ProjectTrustStore(trustAgent).setMany(updates)}catch(e){reason=e}
        \\return reason===marker&&events.join(',')==='next,release'&&!trustFS.existsSync(trustFile);}
        \\finally{trustLock.lockSync=lockSync;}})()
    );
}

test "native project trust store write uses the live key sort iterable and filters untyped updates" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.expect(
        \\(()=>{const s=new ProjectTrustStore(trustAgent),keys=Object.keys;
        \\const a=trustPath.join(trustRoot,'alpha'),b=trustPath.join(trustRoot,'beta'),bad=trustPath.join(trustRoot,'bad');
        \\let sorts=0;Object.keys=function(data){const result=keys(data);
        \\result.sort=function(){sorts++;return [b,a,bad];};return result;};
        \\try{s.setMany([{path:a,decision:true},{path:b,decision:false},{path:bad,decision:91}]);
        \\const expected={};expected[b]=false;expected[a]=true;
        \\return sorts===1&&trustFS.readFileSync(trustFile,'utf-8')===JSON.stringify(expected,null,2)+'\n';}
        \\finally{Object.keys=keys;}})()
    );
}
test "native project trust store retries ELOCKED exactly ten times with nine live Date waits" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.expect(
        \\(()=>{const lockSync=trustLock.lockSync,now=Date.now,marker={code:{toString(){return'ELOCKED';}}};
        \\let attempts=0,ticks=0;Date.now=function(){if(this!==Date)throw Error('Date receiver');return ++ticks*20;};
        \\trustLock.lockSync=function(dir,options){attempts++;if(this!==trustLock||dir!==trustAgent||
        \\options.realpath!==false||options.lockfilePath!==trustFile+'.lock')throw Error('lock inputs');throw marker;};
        \\try{let reason;try{new ProjectTrustStore(trustAgent).get(trustCwd)}catch(e){reason=e}
        \\return reason===marker&&attempts===10&&ticks===18&&!trustFS.existsSync(trustFile);}
        \\finally{trustLock.lockSync=lockSync;Date.now=now;}})()
    );
}
test "native project trust store retry success keeps fresh options and releases the actual third lease" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.expect(
        \\(()=>{const lockSync=trustLock.lockSync,now=Date.now,seen=[];let ticks=0,releases=0;
        \\Date.now=()=>++ticks*20;
        \\trustLock.lockSync=function(dir,options){seen.push(options);if(seen.length<3)throw{code:'ELOCKED'};
        \\const release=lockSync.call(this,dir,options);return()=>{releases++;release();};};
        \\try{const result=new ProjectTrustStore(trustAgent).get(trustCwd);
        \\return result===null&&seen.length===3&&new Set(seen).size===3&&ticks===4&&releases===1&&
        \\seen.every(row=>Object.keys(row).join(',')==='realpath,lockfilePath')&&!trustFS.existsSync(trustFile+'.lock');}
        \\finally{trustLock.lockSync=lockSync;Date.now=now;}})()
    );
}
test "native project trust store retries only object ELOCKED and does not inherit auth EPERM policy" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.expect(
        \\(()=>{const lockSync=trustLock.lockSync,now=Date.now;let attempts=0,ticks=0;
        \\const callable=()=>{};callable.code='ELOCKED';const markers=[{code:'EPERM'},{code:'ENOENT'},null,'ELOCKED',callable];
        \\Date.now=()=>{ticks++;return 0;};
        \\try{const s=new ProjectTrustStore(trustAgent);
        \\const ok=markers.every(marker=>{trustLock.lockSync=()=>{attempts++;throw marker;};
        \\try{s.get(trustCwd);return false;}catch(e){return e===marker;}});
        \\return ok&&attempts===markers.length&&ticks===0;}
        \\finally{trustLock.lockSync=lockSync;Date.now=now;}})()
    );
}
test "native project trust store lock error has String lookup and code getter preserve original order" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.expect(
        \\(()=>{const lockSync=trustLock.lockSync,descriptor=Object.getOwnPropertyDescriptor(globalThis,'String'),marker={},events=[];
        \\const reason=new Proxy({},{has(target,key){events.push('has:'+key);return true;},
        \\get(target,key){events.push('get:'+key);if(key==='code')throw marker;}});
        \\trustLock.lockSync=()=>{throw reason;};
        \\Object.defineProperty(globalThis,'String',{configurable:true,get(){events.push('String');return descriptor.value;}});
        \\try{let caught;try{new ProjectTrustStore(trustAgent).get(trustCwd)}catch(e){caught=e}
        \\return caught===marker&&events.join(',')==='has:code,String,get:code';}
        \\finally{trustLock.lockSync=lockSync;Object.defineProperty(globalThis,'String',descriptor);}})()
    );
}
test "native project trust store release failure supersedes either a return or ordinary body throw" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.expect(
        \\(()=>{const lockSync=trustLock.lockSync,releaseReason={},bodyReason={};let releases=0;
        \\trustLock.lockSync=function(...args){const release=lockSync.apply(this,args);return()=>{release();releases++;throw releaseReason;};};
        \\try{const s=new ProjectTrustStore(trustAgent);let first,second;
        \\try{s.get(trustCwd)}catch(e){first=e}
        \\const updates={[Symbol.iterator](){throw bodyReason;}};
        \\try{s.setMany(updates)}catch(e){second=e}
        \\return first===releaseReason&&second===releaseReason&&releases===2&&!trustFS.existsSync(trustFile+'.lock');}
        \\finally{trustLock.lockSync=lockSync;}})()
    );
}
test "native project trust store invokes a falsy acquired release after the body" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.run(
        \\globalThis.existsCalls=0;trustFS.existsSync=function(path){existsCalls++;return trustOriginalFS.existsSync(path);};
    );
    try f.start();
    try f.expect(
        \\(()=>{const lockSync=trustLock.lockSync;trustLock.lockSync=()=>false;
        \\try{let reason;try{new ProjectTrustStore(trustAgent).get(trustCwd)}catch(e){reason=e}
        \\return reason instanceof TypeError&&existsCalls===1;}finally{trustLock.lockSync=lockSync;}})()
    );
}
test "native project trust store pending entry cannot read imports or publish the class" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.run(
        \\globalThis.importGets=0;const original=trustFS.existsSync;
        \\Object.defineProperty(trustFS,'existsSync',{configurable:true,get(){importGets++;return original;}});
    );
    const reason = try f.engine.checked(c.JS_NewError(f.engine.context));
    defer f.engine.freeValue(reason);
    _ = c.JS_Throw(f.engine.context, c.JS_DupValue(f.engine.context, reason));
    try std.testing.expectError(error.JavaScriptException, trust.create(f.engine, f.inputs));
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, reason,
        f.engine.captured_exception orelse return error.ActualTrustStorePendingReasonRequired));
    try std.testing.expect(!f.engine.native_module_values.contains("pi-private:actual-sdk-project-trust-store"));
    try f.expect("importGets===0");
    try f.start();
    try f.expect("importGets===1");
}

fn pendingRead(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue,
    magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const engine = em.Engine.fromContext(context.?);
    if (magic == 1) _ = engine.throwNativeOutOfMemoryFatal()
    else _ = c.JS_Throw(context, c.JS_DupValue(context, roots[0]));
    return c.JS_DupValue(context, roots[1]);
}
fn installPendingRead(f: *Fixture, fatal: bool) !void {
    const reason = try f.engine.checked(c.JS_NewError(f.engine.context));
    defer f.engine.freeValue(reason);
    const text_value = try h.text(f.engine, "{}");
    defer f.engine.freeValue(text_value);
    var roots = [_]c.JSValue{ reason, text_value };
    const callback = try f.engine.checked(c.JS_NewCFunctionData2(f.engine.context, pendingRead,
        "readFileSync", 2, if (fatal) 1 else 0, roots.len, &roots));
    defer f.engine.freeValue(callback);
    try h.assign(f.engine, f.inputs.filesystem, "readFileSync", callback);
    try f.expose("pendingReadReason", reason);
    try f.run(
        \\pendingReadReason.message='actual read producer';globalThis.bomCalls=0;globalThis.parseCalls=0;globalThis.releaseCalls=0;
        \\const strip=trustText.stripBom,parse=JSON.parse,lockSync=trustLock.lockSync;
        \\trustText.stripBom=function(value){bomCalls++;return strip(value);};
        \\JSON.parse=function(value){parseCalls++;return parse(value);};
        \\trustLock.lockSync=function(...args){const release=lockSync.apply(this,args);return()=>{releaseCalls++;release();};};
        \\trustOriginalFS.mkdirSync(trustAgent,{recursive:true});trustOriginalFS.writeFileSync(trustFile,'{}','utf-8');
    );
}
test "native project trust store successful read value with pending ordinary exception stops downstream calls" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try installPendingRead(&f, false); try f.start();
    try f.expect(
        \\(()=>{let reason;try{new ProjectTrustStore(trustAgent).get(trustCwd)}catch(e){reason=e}
        \\return reason instanceof Error&&reason!==pendingReadReason&&
        \\reason.message==='Failed to read trust store '+trustFile+': actual read producer'&&
        \\bomCalls===0&&parseCalls===0&&releaseCalls===1&&!trustOriginalFS.existsSync(trustFile+'.lock');})()
    );
}
test "native project trust store fatal read producer bypasses formatting and ordinary finally" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try installPendingRead(&f, true); try f.start();
    try std.testing.expectError(error.JavaScriptException, f.run("new ProjectTrustStore(trustAgent).get(trustCwd)"));
    const reason = f.engine.captured_exception orelse return error.ActualTrustStoreFatalReasonRequired;
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(f.engine.native_fatal_invocation == null);
    c.JS_ClearUncatchableError(f.engine.context, reason);
    try f.expect("bomCalls===0&&parseCalls===0&&releaseCalls===0&&trustOriginalFS.existsSync(trustFile+'.lock')");
}
var active_fixture: ?*Fixture = null;
var creation_reentries: usize = 0;
fn reenterCreate(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue,
    _: []const c.JSValue) !c.JSValue
{
    const current = active_fixture orelse return error.ActualTrustStoreReentryFixtureRequired;
    if (engine != current.engine) return error.ActualTrustStoreReentryEngineRequired;
    creation_reentries += 1;
    try std.testing.expect(!engine.native_module_values.contains("pi-private:actual-sdk-project-trust-store"));
    return trust.create(engine, current.inputs);
}
test "native project trust store cold getter reentry cannot publish a partial class" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    active_fixture = &f; defer active_fixture = null; creation_reentries = 0;
    const callback = try v.function.create(f.engine, "reenterStoreCreation", 0, reenterCreate, &.{});
    defer f.engine.freeValue(callback);
    try f.expose("reenterStoreCreation", callback);
    try f.run(
        \\globalThis.reentryRejected=false;const original=trustFS.existsSync;
        \\Object.defineProperty(trustFS,'existsSync',{configurable:true,get(){
        \\try{reenterStoreCreation()}catch(e){reentryRejected=e instanceof TypeError&&e.message.includes('ActualProjectTrustStoreCreationReentry');}
        \\return original;}});
    );
    try f.start();
    try std.testing.expectEqual(@as(usize, 1), creation_reentries);
    try f.expect("reentryRejected&&new ProjectTrustStore(trustAgent).get(trustCwd)===null");
}
test "native project trust store genuine allocation failure leaves no cached partial constructor" {
    var failing = std.testing.FailingAllocator.init(gpa, .{});
    var f: Fixture = undefined; try f.initWithAllocator(failing.allocator()); defer f.deinit();
    failing.fail_index = failing.alloc_index;
    const attempted = trust.create(f.engine, f.inputs);
    failing.fail_index = std.math.maxInt(usize);
    try std.testing.expectError(error.JavaScriptException, attempted);
    const reason = f.engine.captured_exception orelse return error.ActualTrustStoreAllocationReasonRequired;
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(f.engine.native_fatal_invocation == null);
    try std.testing.expect(!f.engine.native_module_values.contains("pi-private:actual-sdk-project-trust-store"));
    c.JS_ClearUncatchableError(f.engine.context, reason);
    try f.start();
    try f.expect("new ProjectTrustStore(trustAgent).get(trustCwd)===null");
}

test "native project trust store object binding boxes a primitive once for both strict getters" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.start();
    try f.expect(
        \\(()=>{const s=new ProjectTrustStore(trustAgent),receivers=[],order=[];
        \\const pathDescriptor=Object.getOwnPropertyDescriptor(Number.prototype,'path');
        \\const decisionDescriptor=Object.getOwnPropertyDescriptor(Number.prototype,'decision');
        \\Object.defineProperty(Number.prototype,'path',{configurable:true,get:function(){'use strict';
        \\order.push('path');receivers.push(this);return trustCwd;}});
        \\Object.defineProperty(Number.prototype,'decision',{configurable:true,get:function(){'use strict';
        \\order.push('decision');receivers.push(this);return true;}});
        \\try{s.setMany([7]);const saved=JSON.parse(trustFS.readFileSync(trustFile,'utf-8'));
        \\return order.join(',')==='path,decision'&&receivers.length===2&&typeof receivers[0]==='object'&&
        \\receivers[0]===receivers[1]&&receivers[0].valueOf()===7&&saved[trustFS.realpathSync(trustCwd)]===true;
        \\}finally{if(pathDescriptor)Object.defineProperty(Number.prototype,'path',pathDescriptor);else delete Number.prototype.path;
        \\if(decisionDescriptor)Object.defineProperty(Number.prototype,'decision',decisionDescriptor);else delete Number.prototype.decision;}})()
    );
}
