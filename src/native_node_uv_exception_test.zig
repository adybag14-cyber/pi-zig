//! Actual native Node UVException controls. These invoke the real helper and
//! admitted libuv mappings; no JavaScript recreation of the C++ error factory
//! serves as the implementation or reference. Original-source assertions are
//! scoped to the selected Node v24.13 UVException contract.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const Scope = a.Scope;
const c = a.c;
const functions = @import("extensions/native_node_module_callable.zig");
const uv_error = @import("extensions/native_node_uv_exception.zig");
const uv = @cImport({ @cInclude("uv.h"); });
const Engine = a.v.em.Engine;

const ordinary: uv_error.Input = .{
    .code = uv.UV_EINVAL,
    .syscall = "read",
    .message = "selected failure",
    .path = "/source",
    .dest = "/destination",
};
fn makeOrdinary(engine: *Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return uv_error.create(engine, ordinary);
}
fn makeEncoding(engine: *Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return uv_error.create(engine, .{
        .code = uv.UV_EINVAL, .syscall = "\xe9x\x00ignored",
        .message = "\xf1description\x00ignored",
        .path = "/utf-\xc3\xa9\x00ignored",
        .dest = "/dest-\xc3\xb1\x00ignored",
    });
}
fn makeFallback(engine: *Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return uv_error.create(engine, .{
        .code = uv.UV_EINVAL, .syscall = "read", .message = "\x00ignored",
    });
}
fn flagError(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    std.debug.assert(args.len == 1 and c.JS_IsError(args[0]));
    c.JS_SetUncatchableError(engine.context, args[0]);
    return c.pi_js_undefined();
}
fn isFlagged(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    std.debug.assert(args.len == 1);
    return c.JS_NewBool(engine.context, c.JS_IsUncatchableError(args[0]));
}
fn publish(s: *Scope, global: c.JSValue, name: [*:0]const u8, callback: functions.Callback) !void {
    const callable = try s.own(try functions.create(s.engine, name, 0, false, callback, &.{}));
    try s.define(global, name, callable, c.JS_PROP_C_W_E);
}
fn installBody(s: *Scope) !c.JSValue {
    const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
    try s.define(global, "actualUVEINVAL", c.JS_NewInt32(s.engine.context, uv.UV_EINVAL), 0);
    try publish(s, global, "actualUVException", makeOrdinary);
    try publish(s, global, "actualUVEncoding", makeEncoding);
    try publish(s, global, "actualUVFallback", makeFallback);
    try publish(s, global, "actualUVFlag", flagError);
    try publish(s, global, "actualUVIsFlagged", isFlagged);
    return c.pi_js_undefined();
}
fn install(engine: *Engine) !void {
    var scope = Scope.init(engine);
    const result = try scope.finish(installBody(&scope));
    engine.freeValue(result);
}
fn run(source: []const u8, name: []const u8) !void {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const result = try engine.evalModule(source, name);
    engine.freeValue(result);
    try engine.checkNativeEntry();
}

test "native UVException preserves intrinsic Error and ordered own field descriptors" {
    try run(
        \\const OriginalError=Error;
        \\const original=Object.getOwnPropertyDescriptor(globalThis,"Error");
        \\Object.defineProperty(globalThis,"Error",{configurable:true,get(){throw "public Error selected";}});
        \\let value;
        \\try { value=actualUVException(); }
        \\finally { Object.defineProperty(globalThis,"Error",original); }
        \\if (!(value instanceof OriginalError) ||
        \\    value.message!=="EINVAL: selected failure, read '/source' -> '/destination'" ||
        \\    value.errno!==actualUVEINVAL || value.code!=="EINVAL" || value.syscall!=="read" ||
        \\    value.path!=="/source" || value.dest!=="/destination")
        \\  throw new OriginalError("actual UVException fields");
        \\if (Object.keys(value).join(",")!=="errno,code,syscall,path,dest")
        \\  throw new OriginalError("actual UVException field order");
        \\const message=Object.getOwnPropertyDescriptor(value,"message");
        \\if (!message || message.enumerable || !message.configurable || !message.writable)
        \\  throw new OriginalError("intrinsic message descriptor");
        \\for (const key of ["errno","code","syscall","path","dest"]) {
        \\  const descriptor=Object.getOwnPropertyDescriptor(value,key);
        \\  if (!descriptor || !descriptor.enumerable || !descriptor.configurable || !descriptor.writable ||
        \\      !Object.hasOwn(descriptor,"value")) throw new OriginalError("actual own data field "+key);
        \\}
    , "actual-uv-error-fields.mjs");
}

test "native UVException nonthrowing Set preserves inherited readonly and getter-only fields" {
    try run(
        \\const keys=["errno","code","syscall","path","dest"];
        \\const originals=keys.map(key=>Object.getOwnPropertyDescriptor(Error.prototype,key));
        \\for (const mode of ["readonly","getter"]) {
        \\  let reads=0;
        \\  try {
        \\    for (const key of keys) Object.defineProperty(Error.prototype,key,mode==="readonly"?
        \\      {value:"inherited "+key,writable:false,configurable:true}:
        \\      {get(){++reads;return "inherited "+key;},configurable:true});
        \\    const value=actualUVException();
        \\    if (!(value instanceof Error) ||
        \\        value.message!=="EINVAL: selected failure, read '/source' -> '/destination'" ||
        \\        reads!==0) throw new Error("normal failed native Set must not throw or read getter");
        \\    for (const key of keys)
        \\      if (Object.hasOwn(value,key) || value[key]!=="inherited "+key)
        \\        throw new Error("normal failed native Set must preserve inherited field "+key);
        \\  } finally {
        \\    for (let index=0;index<keys.length;++index) {
        \\      if (originals[index]) Object.defineProperty(Error.prototype,keys[index],originals[index]);
        \\      else delete Error.prototype[keys[index]];
        \\    }
        \\  }
        \\}
    , "actual-uv-error-readonly.mjs");
}

test "native UVException invokes each inherited setter with the actual Error in source order" {
    try run(
        \\const keys=["errno","code","syscall","path","dest"];
        \\const originals=keys.map(key=>Object.getOwnPropertyDescriptor(Error.prototype,key));
        \\const trace=[];let receiver;
        \\try {
        \\  for (const key of keys) Object.defineProperty(Error.prototype,key,{configurable:true,
        \\    set(value){
        \\      if (receiver===undefined) receiver=this;
        \\      if (this!==receiver || !(this instanceof Error) ||
        \\          this.message!=="EINVAL: selected failure, read '/source' -> '/destination'")
        \\        throw new Error("wrong actual native setter receiver");
        \\      trace.push([key,value]);return {ignored:true};
        \\    }});
        \\  const value=actualUVException();
        \\  if (value!==receiver || JSON.stringify(trace)!==
        \\      JSON.stringify([["errno",actualUVEINVAL],["code","EINVAL"],["syscall","read"],["path","/source"],["dest","/destination"]]))
        \\    throw new Error("actual native setter order");
        \\  for (const key of keys) if (Object.hasOwn(value,key)) throw new Error("setter was replaced by own definition");
        \\} finally {
        \\  for (let index=0;index<keys.length;++index) {
        \\    if (originals[index]) Object.defineProperty(Error.prototype,keys[index],originals[index]);
        \\    else delete Error.prototype[keys[index]];
        \\  }
        \\}
    , "actual-uv-error-setters.mjs");
}

test "native UVException normal false assignment still reaches the remaining actual setters" {
    try run(
        \\const keys=["errno","code","syscall","path","dest"];
        \\const originals=keys.map(key=>Object.getOwnPropertyDescriptor(Error.prototype,key));
        \\const trace=[];
        \\try {
        \\  for (const key of keys) Object.defineProperty(Error.prototype,key,key==="code"?
        \\    {value:"readonly code",writable:false,configurable:true}:
        \\    {configurable:true,set(value){trace.push([key,value]);}});
        \\  const value=actualUVException();
        \\  if (!(value instanceof Error) || value.code!=="readonly code" ||
        \\      Object.hasOwn(value,"code") || JSON.stringify(trace)!==
        \\      JSON.stringify([["errno",actualUVEINVAL],["syscall","read"],["path","/source"],["dest","/destination"]]))
        \\    throw new Error("normal false native assignment skipped a later field");
        \\} finally {
        \\  for (let index=0;index<keys.length;++index) {
        \\    if (originals[index]) Object.defineProperty(Error.prototype,keys[index],originals[index]);
        \\    else delete Error.prototype[keys[index]];
        \\  }
        \\}
    , "actual-uv-error-false-continuation.mjs");
}

test "native UVException retains OneByteString C-string and UTF8 path distinctions" {
    try run(
        \\const value=actualUVEncoding();
        \\if (value.syscall!=="\u00e9x" || value.path!=="/utf-\u00e9" || value.dest!=="/dest-\u00f1" ||
        \\    value.message!=="EINVAL: \u00f1description, \u00e9x '/utf-\u00e9' -> '/dest-\u00f1'")
        \\  throw new Error("actual native error string encodings");
        \\const fallback=actualUVFallback();
        \\if (fallback.message!=="EINVAL: invalid argument, read" ||
        \\    Object.hasOwn(fallback,"path") || Object.hasOwn(fallback,"dest"))
        \\  throw new Error("NUL-first message must select genuine uv_strerror");
    , "actual-uv-error-encodings.mjs");
}

test "native UVException successfully constructed flagged Error remains returned DATA" {
    try run(
        \\const original=Object.getOwnPropertyDescriptor(Error.prototype,"code");
        \\let marked;
        \\try {
        \\  Object.defineProperty(Error.prototype,"code",{configurable:true,set(value){
        \\    marked=this;actualUVFlag(this);
        \\  }});
        \\  const value=actualUVException();
        \\  if (value!==marked || !actualUVIsFlagged(value) ||
        \\      value.syscall!=="read" || value.path!=="/source" || value.dest!=="/destination")
        \\    throw new Error("successful flagged intrinsic Error was not returned as DATA");
        \\} finally {
        \\  if (original) Object.defineProperty(Error.prototype,"code",original);
        \\  else delete Error.prototype.code;
        \\}
    , "actual-uv-error-returned-data.mjs");
}
