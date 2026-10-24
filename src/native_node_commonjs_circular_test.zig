//! Focused controls for real canonical Module circular-export declarations.
//! Controlled module_wrap status values exercise this leaf's comparison; they
//! do not claim a complete ESM binding, public loader, worker or SDK bootstrap.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const c = a.c;
const core = @import("extensions/native_node_commonjs_module_core.zig");
const modules = @import("extensions/native_node_module_constructor.zig");
const circular = @import("extensions/native_node_commonjs_circular.zig");

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
            &self.environment, &.{"actual-commonjs-circular-controls"});
        try @import("extensions/node_path.zig").install(self.engine, std.testing.io);
        try @import("extensions/node_url.zig").install(self.engine);
        const process = (try self.engine.requireBuiltin("node:process")) orelse
            return error.ActualCircularProcessRequired;
        defer self.engine.freeValue(process);
        try @import("extensions/node_fs.zig").installWithStreams(self.engine, std.testing.io, process);
        self.module = try core.create(self.engine);
    }
    fn complete(self: *Fixture) !void {
        // Deliberately a controlled phase datum, not a claimed V8/VM enum.
        self.graph = try circular.create(self.engine, self.module.?, c.JS_NewInt32(self.engine.context, 71));
        _ = try a.expression(self.engine, publish, .{ self.module.?, self.graph.? });
    }
    fn publish(s: *a.Scope, module: c.JSValue, graph: c.JSValue) !c.JSValue {
        const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
        const proxy = try s.get(graph, "CircularRequirePrototypeWarningProxy");
        const marker_owner = try @import("extensions/native_node_system_errors.zig").registry(s.engine);
        try s.define(global, "ActualCircularModule", module, c.JS_PROP_C_W_E);
        try s.define(global, "actualCircularExports", try s.get(graph, "getExportsForCircularRequire"), c.JS_PROP_C_W_E);
        try s.define(global, "actualCircularProxy", proxy, c.JS_PROP_C_W_E);
        try s.define(global, "actualCircularHandler", try s.checked(c.JS_GetProxyHandler(s.engine.context, proxy)), c.JS_PROP_C_W_E);
        try s.define(global, "actualCircularRequired", try s.own(try modules.loaderKey(s.engine, module, .required_module)), c.JS_PROP_C_W_E);
        try s.define(global, "actualCircularNodeMarker", try s.get(marker_owner, "marker"), c.JS_PROP_C_W_E);
        try s.define(global, "actualCircularEvaluated", c.JS_NewInt32(s.engine.context, 71), c.JS_PROP_C_W_E);
        return c.pi_js_undefined();
    }
    fn run(self: *Fixture, source: []const u8) !void {
        const result = try self.engine.eval(source, "actual-commonjs-circular-control.js", c.JS_EVAL_TYPE_GLOBAL);
        self.engine.freeValue(result);
    }
    fn deinit(self: *Fixture) void {
        if (self.graph) |value| self.engine.freeValue(value);
        if (self.module) |value| self.engine.freeValue(value);
        self.engine.deinit();
        self.environment.deinit();
    }
};

test "native actual CommonJS circular owner creates real proxy and function without public Module publication" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    try fixture.complete();
    try std.testing.expect(!fixture.engine.native_module_names.contains("node:module"));
    const proxy = try a.field(fixture.engine, fixture.graph.?, "CircularRequirePrototypeWarningProxy");
    defer fixture.engine.freeValue(proxy);
    try std.testing.expect(c.JS_IsProxy(proxy));
    try fixture.run(
        \\if(actualCircularExports.name!=="getExportsForCircularRequire"||actualCircularExports.length!==1)throw Error("declaration metadata");
        \\if(Object.getPrototypeOf(actualCircularHandler)!==null||actualCircularHandler.get.length!==2||actualCircularHandler.getOwnPropertyDescriptor.length!==2)throw Error("actual proxy handler");
        \\const m=new ActualCircularModule("/plain.cjs");const value=m.exports;
        \\if(actualCircularExports(m)!==value||Object.getPrototypeOf(value)!==actualCircularProxy)throw Error("shared native proxy");
    );
}

test "native actual CommonJS circular warning proxy distinguishes inherited reads own descriptors and esModule" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit(); try fixture.complete();
    try fixture.run(
        \\const warnings=[];process.emitWarning=function(message){if(this!==process)throw Error("warning receiver");warnings.push(message)};
        \\if(actualCircularProxy.toString!==Object.prototype.toString||actualCircularProxy.__esModule!==undefined||Object.getOwnPropertyDescriptor(actualCircularProxy,"__esModule")!==undefined)throw Error("allowed accesses");
        \\if(warnings.length!==0)throw Error("unexpected allowed warning");
        \\actualCircularProxy.missing;Object.getOwnPropertyDescriptor(actualCircularProxy,"toString");actualCircularProxy[Symbol("observed")];
        \\Object.defineProperty(actualCircularProxy,"owned",{value:19,configurable:true});if(actualCircularProxy.owned!==19||Object.getOwnPropertyDescriptor(actualCircularProxy,"owned").value!==19)throw Error("own read");
        \\const expected=["Accessing non-existent property 'missing' of module exports inside circular dependency","Accessing non-existent property 'toString' of module exports inside circular dependency","Accessing non-existent property 'Symbol(observed)' of module exports inside circular dependency"];
        \\if(JSON.stringify(warnings)!==JSON.stringify(expected))throw Error("warning sequence "+JSON.stringify(warnings));
    );
}

test "native actual CommonJS circular exports preserves primitive proxy array class and transpiled module exclusions" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit(); try fixture.complete();
    try fixture.run(
        \\const plain={};const marked={__esModule:true};const proxied=new Proxy({},{});class SourceClass{};const values=[null,undefined,0,false,"",42,"text",[],function(){},new SourceClass(),Object.create(null),marked,proxied];
        \\for(const value of values){const m=new ActualCircularModule("/excluded.cjs");m.exports=value;const before=value!==null&&(typeof value==="object"||typeof value==="function")?Object.getPrototypeOf(value):null;
        \\if(actualCircularExports(m)!==value)throw Error("export identity");
        \\if(before!==null&&Object.getPrototypeOf(value)!==before)throw Error("excluded prototype changed")}
        \\const m=new ActualCircularModule("/plain.cjs");m.exports=plain;actualCircularExports(m);if(Object.getPrototypeOf(plain)!==actualCircularProxy)throw Error("plain prototype unchanged");
    );
}

test "native actual CommonJS circular exports rereads the Source getter at all six original occurrences" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit(); try fixture.complete();
    try fixture.run(
        \\const m=new ActualCircularModule("/getter.cjs");const rows=[{n:1},{n:2},{n:3},{n:4},{n:5},{n:6}];let reads=0;
        \\Object.defineProperty(m,"exports",{get(){return rows[reads++]},configurable:true});
        \\if(actualCircularExports(m)!==rows[5]||reads!==6)throw Error("exports occurrence count "+reads);
        \\if(Object.getPrototypeOf(rows[4])!==actualCircularProxy)throw Error("wrong fifth target");
        \\for(const i of [0,1,2,3,5])if(Object.getPrototypeOf(rows[i])!==Object.prototype)throw Error("other target changed");
    );
}

test "native actual CommonJS circular unevaluated ESM branch uses actual Node error and private last parent" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit(); try fixture.complete();
    try fixture.run(
        \\const parent=new ActualCircularModule("/parent.cjs");parent.filename="/actual/parent.cjs";
        \\const m=new ActualCircularModule("/cycle.mjs",parent);let status=0,exportsReads=0;
        \\m[actualCircularRequired]={getStatus(){status++;return actualCircularEvaluated-1}};
        \\Object.defineProperty(m,"exports",{get(){exportsReads++;throw Error("exports evaluated after cycle")},configurable:true});
        \\let caught;try{actualCircularExports(m)}catch(error){caught=error}
        \\if(!(caught instanceof Error)||caught.code!=="ERR_REQUIRE_CYCLE_MODULE"||caught[actualCircularNodeMarker]!==true||caught.constructor!==Error)throw Error("real Node error");
        \\if(caught.message!=="Cannot require() ES Module /cycle.mjs in a cycle. (from /actual/parent.cjs)"||status!==1||exportsReads!==0)throw Error("cycle message/order");
    );
}

test "native actual CommonJS circular ESM status completed and abrupt values keep original identity and order" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit(); try fixture.complete();
    try fixture.run(
        \\const m=new ActualCircularModule("/status.mjs");let reads=0;m[actualCircularRequired]={getStatus(){reads++;if(this!==m[actualCircularRequired])throw Error("status receiver");return actualCircularEvaluated}};
        \\const value=m.exports;if(actualCircularExports(m)!==value||reads!==1)throw Error("completed status");
        \\const reason={original:true};Object.defineProperty(m[actualCircularRequired],"getStatus",{get(){throw reason},configurable:true});
        \\let caught;try{actualCircularExports(m)}catch(error){caught=error}if(caught!==reason)throw Error("status throw identity");
    );
}

test "native actual CommonJS circular warning resolves emitWarning before message String coercion and stops on throws" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit(); try fixture.complete();
    try fixture.run(
        \\const events=[];let conversions=0;const property={toString(){conversions++;events.push("coerce"+conversions);if(conversions===2)Object.defineProperty(process,"emitWarning",{value(){throw Error("late callee")},writable:true,configurable:true});return "absent"}};
        \\Object.defineProperty(process,"emitWarning",{get(){events.push("callee");return function(message){if(this!==process||!message.includes("'absent'"))throw Error("call");events.push("emit")}},configurable:true});
        \\actualCircularHandler.get({},property);if(events.join(",")!=="coerce1,callee,coerce2,emit")throw Error("warning order "+events);
        \\const reason={warning:true};process.emitWarning=function(){throw reason};let caught;try{actualCircularProxy.absent}catch(error){caught=error}if(caught!==reason)throw Error("warning throw identity");
        \\const frozen=new ActualCircularModule("/frozen.cjs");frozen.exports=Object.freeze({});caught=undefined;try{actualCircularExports(frozen)}catch(error){caught=error}if(!(caught instanceof TypeError))throw Error("prototype failure");
    );
}

test "native actual CommonJS circular owner uses Module-captured primordials even when linked after guest mutation" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    try fixture.run(
        \\globalThis.circularOriginal={String,Object,getPrototypeOf:Object.getPrototypeOf,setPrototypeOf:Object.setPrototypeOf,getOwnPropertyDescriptor:Object.getOwnPropertyDescriptor,hasOwnProperty:Object.prototype.hasOwnProperty};
        \\globalThis.String=function(){throw Error("patched String")};Object.getPrototypeOf=Object.setPrototypeOf=Object.getOwnPropertyDescriptor=Object.prototype.hasOwnProperty=function(){throw Error("patched Object primitive")};
    );
    try fixture.complete();
    try fixture.run(
        \\try{const warnings=[];process.emitWarning=message=>warnings.push(message);const m=new ActualCircularModule("/captured.cjs");
        \\if(actualCircularExports(m)!==m.exports||Reflect.getPrototypeOf(m.exports)!==actualCircularProxy)throw Error("captured prototype");
        \\actualCircularProxy[Symbol("retained")];if(warnings.length!==1||!warnings[0].includes("Symbol(retained)"))throw Error("captured String");
        \\if(actualCircularHandler.getOwnPropertyDescriptor({x:1},"x").value!==1)throw Error("captured descriptor");
        \\}finally{globalThis.String=circularOriginal.String;Object.getPrototypeOf=circularOriginal.getPrototypeOf;Object.setPrototypeOf=circularOriginal.setPrototypeOf;Object.getOwnPropertyDescriptor=circularOriginal.getOwnPropertyDescriptor;Object.prototype.hasOwnProperty=circularOriginal.hasOwnProperty}
    );
}

test "native actual CommonJS circular helper rejects missing actual status and foreign Module without publication" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    try std.testing.expectError(error.ActualModuleWrapEvaluatedStatusRequired,
        circular.create(fixture.engine, fixture.module.?, c.pi_js_undefined()));
    const foreign = try fixture.engine.checked(c.JS_NewObject(fixture.engine.context));
    defer fixture.engine.freeValue(foreign);
    const attempt = circular.create(fixture.engine, foreign, c.JS_NewInt32(fixture.engine.context, 71));
    if (attempt) |value| {
        fixture.engine.freeValue(value);
        return error.ForeignModuleAccepted;
    } else |_| {}
    try std.testing.expect(!fixture.engine.native_module_names.contains("node:module"));
}
