//! Focused controls for the canonical Module's real watch-reporting owner.
//! These do not publish a public loader, open an IPC transport, or run Node.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const c = a.c;
const core = @import("extensions/native_node_commonjs_module_core.zig");
const modules = @import("extensions/native_node_module_constructor.zig");
const watch = @import("extensions/native_node_commonjs_watch.zig");

const Fixture = struct {
    engine: *a.v.em.Engine,
    environment: std.process.Environ.Map,
    module: ?c.JSValue = null,
    graph: ?c.JSValue = null,

    fn init(self: *Fixture) !void {
        self.* = .{ .engine = undefined, .environment = .init(std.testing.allocator) };
        errdefer self.environment.deinit();
        self.engine = try a.v.em.Engine.init(std.testing.allocator, .{});
        errdefer self.engine.deinit();
        try @import("extensions/timers.zig").install(self.engine, std.testing.io);
        try @import("extensions/native_process.zig").install(self.engine, std.testing.io,
            &self.environment, &.{"actual-commonjs-watch-controls"});
        try @import("extensions/node_path.zig").install(self.engine, std.testing.io);
        try @import("extensions/node_url.zig").install(self.engine);
        const process = (try self.engine.requireBuiltin("node:process")) orelse
            return error.ActualWatchProcessRequired;
        defer self.engine.freeValue(process);
        try @import("extensions/node_fs.zig").installWithStreams(self.engine, std.testing.io, process);
        self.module = try core.create(self.engine);
    }
    fn complete(self: *Fixture) !void {
        self.graph = try watch.acquire(self.engine, self.module.?);
        _ = try a.expression(self.engine, publish, .{self.module.?, self.graph.?});
    }
    fn publish(s: *a.Scope, module: c.JSValue, graph: c.JSValue) !c.JSValue {
        const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
        try s.define(global, "actualReportRequired", try s.get(graph, "reportModuleToWatchMode"), c.JS_PROP_C_W_E);
        try s.define(global, "actualReportMissing", try s.get(graph, "reportModuleNotFoundToWatchMode"), c.JS_PROP_C_W_E);
        try s.define(global, "actualWatchPaths", try s.own(try modules.pathObject(s.engine, module)), c.JS_PROP_C_W_E);
        return c.pi_js_undefined();
    }
    fn run(self: *Fixture, source: []const u8) !void {
        const result = try self.engine.eval(source, "actual-commonjs-watch-control.js", c.JS_EVAL_TYPE_GLOBAL);
        self.engine.freeValue(result);
    }
    fn deinit(self: *Fixture) void {
        if (self.graph) |value| self.engine.freeValue(value);
        if (self.module) |value| self.engine.freeValue(value);
        self.engine.deinit();
        self.environment.deinit();
    }
};

test "native actual CommonJS watch shares one authenticated graph without publishing public Module" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.complete();
    const same = try watch.acquire(f.engine, f.module.?); defer f.engine.freeValue(same);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, same, f.graph.?));
    try std.testing.expect(!f.engine.native_module_names.contains("node:module"));
    try f.run(
        \\if(actualReportRequired.name!=="reportModuleToWatchMode"||actualReportRequired.length!==1||!Object.hasOwn(actualReportRequired,"prototype"))throw Error("required declaration");
        \\if(actualReportMissing.name!=="reportModuleNotFoundToWatchMode"||actualReportMissing.length!==2||!Object.hasOwn(actualReportMissing,"prototype"))throw Error("missing declaration");
    );
    const foreign = try f.engine.checked(c.JS_NewObject(f.engine.context)); defer f.engine.freeValue(foreign);
    if (watch.acquire(f.engine, foreign)) |unexpected| {
        f.engine.freeValue(unexpected);
        return error.ForeignWatchModuleAccepted;
    } else |_| {}
}

test "native actual CommonJS watch reads environment lazily once and shares the value between reporters" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.run(
        \\globalThis.watchEnvReads=0;globalThis.watchFlagReads=0;globalThis.watchMessages=[];globalThis.watchFlag="enabled";
        \\Object.defineProperty(process,"env",{configurable:true,get(){watchEnvReads++;return {get WATCH_REPORT_DEPENDENCIES(){watchFlagReads++;return watchFlag}}}});
        \\process.send=function(message){if(this!==process)throw Error("process receiver");watchMessages.push(message)};
    );
    try f.complete();
    try f.run(
        \\if(watchEnvReads!==0||watchFlagReads!==0)throw Error("eager environment read");
        \\actualReportRequired("/original.cjs");watchFlag="";actualReportMissing("/missing",[".js",".json"]);
        \\if(watchEnvReads!==1||watchFlagReads!==1||watchMessages.length!==2)throw Error("shared lazy cell");
        \\if(watchMessages[0]["watch:require"][0]!=="/original.cjs"||watchMessages[1]["watch:require"][0]!==actualWatchPaths.resolve("/missing.js")||watchMessages[1]["watch:require"][1]!==actualWatchPaths.resolve("/missing.json"))throw Error("actual path results");
    );
}

test "native actual CommonJS watch caches an undefined flag and never reads send on the disabled path" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.complete();
    try f.run(
        \\let reads=0,flag;Object.defineProperty(process,"env",{value:{get WATCH_REPORT_DEPENDENCIES(){reads++;return flag}},configurable:true});
        \\Object.defineProperty(process,"send",{get(){throw Error("disabled send read")},configurable:true});
        \\actualReportRequired("first");flag="enabled";actualReportMissing({toString(){throw Error("disabled coercion")}},null);
        \\if(reads!==1)throw Error("undefined was not cached");
    );
}

test "native actual CommonJS watch retries a throwing lazy initializer and preserves its exact reason" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.complete();
    try f.run(
        \\const reason={initial:true};let reads=0,sent=0;
        \\Object.defineProperty(process,"env",{get(){if(++reads===1)throw reason;return {WATCH_REPORT_DEPENDENCIES:"yes"}},configurable:true});
        \\process.send=function(){sent++};let caught;try{actualReportRequired("first")}catch(error){caught=error}
        \\if(caught!==reason||sent!==0)throw Error("initializer abrupt identity");
        \\actualReportMissing("/next",[".js"]);actualReportRequired("last");
        \\if(reads!==2||sent!==2)throw Error("initializer retry or cache");
    );
}

test "native actual CommonJS watch outer successful initialization replaces a reentrant inner value" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.complete();
    try f.run(
        \\let reads=0;const sent=[];process.env={get WATCH_REPORT_DEPENDENCIES(){if(++reads===1){actualReportRequired("nested-disabled");return "outer-enabled"}return ""}};
        \\process.send=function(message){sent.push(message)};
        \\actualReportRequired("outer");actualReportMissing("/after",[".cjs"]);
        \\if(reads!==2||sent.length!==2||sent[0]["watch:require"][0]!=="outer")throw Error("reentrant outer assignment");
    );
}

test "native actual CommonJS watch throwing outer initialization keeps a completed reentrant inner cache" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.complete();
    try f.run(
        \\let reads=0;const reason={outer:true},sent=[];process.env={get WATCH_REPORT_DEPENDENCIES(){if(++reads===1){actualReportRequired("inner");throw reason}return "inner-enabled"}};
        \\process.send=function(message){sent.push(message)};let caught;try{actualReportRequired("outer")}catch(error){caught=error}
        \\if(caught!==reason||sent.length!==1||sent[0]["watch:require"][0]!=="inner")throw Error("inner completion");
        \\actualReportMissing("/after",[".js"]);if(reads!==2||sent.length!==2)throw Error("inner cache rolled back");
    );
}

test "native actual CommonJS watch performs two live send reads and keeps uncoerced filename identity" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.complete();
    try f.run(
        \\process.env={WATCH_REPORT_DEPENDENCIES:"yes"};let reads=0,observed;const filename={toString(){throw Error("filename coercion")}};
        \\Object.defineProperty(process,"send",{configurable:true,get(){reads++;if(reads===1)return {truthy:true};return function(message){if(this!==process)throw Error("send receiver");observed=message}}});
        \\actualReportRequired(filename);
        \\if(reads!==2||observed["watch:require"][0]!==filename)throw Error("callee or filename identity");
        \\if(Object.getPrototypeOf(observed)!==Object.prototype||Object.keys(observed).join(",")!=="watch:require")throw Error("ordinary message object");
    );
}

test "native actual CommonJS watch defines message literals without inherited setters" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.complete();
    try f.run(
        \\process.env={WATCH_REPORT_DEPENDENCIES:"yes"};let observed;process.send=function(message){observed=message};
        \\Object.defineProperty(Object.prototype,"watch:require",{configurable:true,set(){throw Error("object literal setter")}});
        \\Object.defineProperty(Array.prototype,"0",{configurable:true,set(){throw Error("array literal setter")}});
        \\try{actualReportRequired("own")}finally{delete Object.prototype["watch:require"];delete Array.prototype["0"]}
        \\const field=Object.getOwnPropertyDescriptor(observed,"watch:require"),element=Object.getOwnPropertyDescriptor(field.value,"0");
        \\if(!field.enumerable||!field.configurable||!field.writable||!element.enumerable||!element.configurable||!element.writable||element.value!=="own")throw Error("literal descriptors");
    );
}

test "native actual CommonJS watch uses captured map with sparse inherited elements and real species semantics" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.run(
        \\globalThis.watchOriginalMap=Array.prototype.map;Array.prototype.map=function(){throw Error("guest replaced map")};
    );
    try f.complete();
    try f.run(
        \\try{process.env={WATCH_REPORT_DEPENDENCIES:"yes"};let observed;process.send=message=>{observed=message};
        \\class Result extends Array{};const extensions=[".js"];extensions.length=4;const inherited=Object.create(Array.prototype);inherited[2]=".json";Object.setPrototypeOf(extensions,inherited);
        \\Object.defineProperty(extensions,"constructor",{value:{[Symbol.species]:Result}});
        \\actualReportMissing("/candidate",extensions);const mapped=observed["watch:require"];
        \\if(!(mapped instanceof Result)||mapped.length!==4||(1 in mapped)||(3 in mapped)||mapped[0]!==actualWatchPaths.resolve("/candidate.js")||mapped[2]!==actualWatchPaths.resolve("/candidate.json"))throw Error("map species holes inherited");
        \\}finally{Array.prototype.map=watchOriginalMap}
    );
}

test "native actual CommonJS watch resolves each path callee before template coercions after the selected send" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.complete();
    try f.run(
        \\process.env={WATCH_REPORT_DEPENDENCIES:"yes"};const events=[];let sendReads=0,observed;
        \\Object.defineProperty(process,"send",{configurable:true,get(){events.push("send"+(++sendReads));return function(message){events.push("emit");observed=message}}});
        \\const second=function(value){if(this!==actualWatchPaths)throw Error("second receiver");events.push("second");return "second:"+value};
        \\Object.defineProperty(actualWatchPaths,"resolve",{configurable:true,get(){events.push("resolve");return function(value){if(this!==actualWatchPaths)throw Error("first receiver");events.push("first");return "first:"+value}}});
        \\const base={toString(){events.push("base");return "root"}},ext={toString(){events.push("ext");Object.defineProperty(actualWatchPaths,"resolve",{value:second,writable:true,configurable:true});return ".a"}};
        \\const extensions={get length(){events.push("length");return 2},0:ext,1:".b"};
        \\actualReportMissing(base,extensions);
        \\if(events.join(",")!=="send1,send2,length,resolve,base,ext,first,base,second,emit")throw Error("lookup/coercion order "+events);
        \\if(observed["watch:require"].join(",")!=="first:root.a,second:root.b")throw Error("per-element path result");
    );
}

test "native actual CommonJS watch propagates map and send exceptions while retaining the initialized flag" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); try f.complete();
    try f.run(
        \\let flagReads=0,sends=0;const mapReason={map:true},sendReason={send:true};
        \\process.env={get WATCH_REPORT_DEPENDENCIES(){flagReads++;return "yes"}};process.send=function(){sends++};
        \\let caught;try{actualReportMissing("/bad",{length:1,get 0(){throw mapReason}})}catch(error){caught=error}
        \\if(caught!==mapReason||sends!==0)throw Error("map abrupt completion");
        \\process.send=function(){throw sendReason};caught=undefined;try{actualReportRequired("send-failure")}catch(error){caught=error}
        \\if(caught!==sendReason)throw Error("send abrupt identity");
        \\process.env={get WATCH_REPORT_DEPENDENCIES(){throw Error("flag reread")}};process.send=function(){sends++};actualReportRequired("after");
        \\if(flagReads!==1||sends!==1)throw Error("abrupt completion discarded lazy flag");
    );
}
