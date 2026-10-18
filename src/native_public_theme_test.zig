//! Source-bound public Theme helper controls and actual syntax owner readiness.
//! Shared native Theme/syntax dependencies establish helper semantics; they do
//! not stand in for an independent upstream syntax grammar equivalence run.
const std = @import("std");
const v = @import("extensions/native_public_values.zig");
const theme = @import("extensions/native_public_theme.zig");
const high = @import("extensions/native_sdk_themed_highlight.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const c = v.c;

fn install(engine: *v.em.Engine) !void {
    try @import("extensions/native_tui.zig").install(engine);
    const source = try engine.eval(@embedFile("extensions/fixtures/public-theme-c268-source.mjs"), "c268-public-theme-source.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(source);
    var s: v.Scope = .{ .engine = engine };
    try v.owned.finishVoid(&s, installBody(&s));
    const linked = try engine.eval(
        \\globalThis.publicThemeSource=makePublicThemeSource(publicThemeNative.theme,publicThemeSyntax.supportsLanguage,publicThemeSyntax.highlight);
    , "c268-public-theme-link.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(linked);
}
fn installBody(s: *v.Scope) !void {
    const global = try v.own(s, c.JS_GetGlobalObject(s.engine.context));
    try v.put(s, global, "publicThemeNative", try v.own(s, try theme.create(s.engine)));
    try v.put(s, global, "publicThemeSyntax", try v.own(s, try theme.syntax(s.engine)));
    try v.put(s, global, "themeHooks", try v.own(s, try retirement.createNativeRetirementHooks(s.engine)));
    try v.put(s, global, "makeNativeHighlightPair", try v.ordinary(s, "makeNativeHighlightPair", 2, createPair, &.{}));
}
fn createPair(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, pairBody(&s, v.arg(args, 0), v.arg(args, 1)));
}
fn pairBody(s: *v.Scope, syntax: c.JSValue, runtime: c.JSValue) !c.JSValue {
    // Explicit observer inputs exercise the same production helper bodies.
    const state = try v.own(s, try high.createState(s.engine, syntax, runtime));
    const pair = try v.object(s);
    try v.put(s, pair, "public", try v.ordinary(s, "highlightCode", 2, publicCode, &.{state}));
    try v.put(s, pair, "markdown", try v.arrow(s, "highlightCode", 2, markdownCode, &.{state}));
    return v.duplicate(s, pair);
}
fn publicCode(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return high.highlightState(engine, roots[0], v.arg(args, 0), v.arg(args, 1), false);
}
fn markdownCode(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return high.highlightState(engine, roots[0], v.arg(args, 0), v.arg(args, 1), true);
}
fn rawGlobal(engine: *v.em.Engine, name: [*:0]const u8) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    return engine.checked(c.JS_GetPropertyStr(engine.context, global, name));
}
fn execute(engine: *v.em.Engine, source: []const u8) !void {
    const result = try engine.eval(source, "actual-public-theme-setup.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
}
fn check(engine: *v.em.Engine, source: []const u8) !void {
    const result = try engine.eval(source, "actual-public-theme-control.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    try std.testing.expectEqual(@as(c_int, 1), c.JS_ToBool(engine.context, result));
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    try std.testing.expect(!c.JS_HasException(engine.context));
}

test "Public Theme actual original actor identities and ordinary helper shapes" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try install(engine);
    const original = engine.native_module_values.get("pi-coding-agent").?;
    const original_class = try engine.checked(c.JS_GetPropertyStr(engine.context, original, "Theme")); defer engine.freeValue(original_class);
    const actual = try theme.create(engine); defer engine.freeValue(actual);
    const exported_class = try engine.checked(c.JS_GetPropertyStr(engine.context, actual, "Theme")); defer engine.freeValue(exported_class);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, original_class, exported_class));
    const again = try theme.create(engine); defer engine.freeValue(again);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, again));
    try check(engine,
        \\(() => {
        \\ const n=publicThemeNative,s=publicThemeSource;
        \\ const shape=f=>[f.name,f.length,Object.hasOwn(f,"prototype"),Object.getPrototypeOf(f)===Function.prototype];
        \\ for(const name of ["getLanguageFromPath","getMarkdownTheme","getSelectListTheme","getSettingsListTheme","highlightCode"])
        \\   if(JSON.stringify(shape(n[name]))!==JSON.stringify(shape(s[name])))throw Error("ordinary shape "+name);
        \\ if(n.initTheme.name!=="initTheme"||n.initTheme.length!==1||!Object.hasOwn(n.initTheme,"prototype"))throw Error("real initializer shape");
        \\ for(const name of ["getMarkdownTheme","getSelectListTheme"]){
        \\   const left=n[name](),right=n[name](),expected=s[name]();
        \\   if(left===right||Object.keys(left).join()!==Object.keys(expected).join())throw Error("fresh helper mapping");
        \\   for(const key of Object.keys(left)){
        \\     if(left[key]===right[key]||JSON.stringify(shape(left[key]))!==JSON.stringify(shape(expected[key])))throw Error("fresh arrow "+key);
        \\   }
        \\ }
        \\ return true;
        \\})()
    );
}
test "Public Theme actual class descriptors arities and declaration order preserve identity" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try install(engine);
    try check(engine,
        \\(() => {
        \\ const Theme=publicThemeNative.Theme;
        \\ const name=Object.getOwnPropertyDescriptor(Theme,"name"),length=Object.getOwnPropertyDescriptor(Theme,"length");
        \\ if(name.value!=="Theme"||name.enumerable||name.writable||!name.configurable)throw Error("class name descriptor");
        \\ if(length.value!==3||length.enumerable||length.writable||!length.configurable)throw Error("constructor arity descriptor");
        \\ const expected=["constructor","appearance","colors","style","fg","bg","bold","italic","underline","inverse","strikethrough","getFgAnsi","getBgAnsi","getColorMode","getThinkingBorderColor","getBashModeBorderColor"];
        \\ if(Object.getOwnPropertyNames(Theme.prototype).join()!==expected.join())throw Error("class declaration order");
        \\ const arities={style:2,fg:2,bg:2,bold:1,italic:1,underline:1,inverse:1,strikethrough:1,getFgAnsi:1,getBgAnsi:1,getColorMode:0,getThinkingBorderColor:1,getBashModeBorderColor:0};
        \\ for(const [key,arity] of Object.entries(arities)){
        \\   const d=Object.getOwnPropertyDescriptor(Theme.prototype,key);
        \\   if(d.enumerable||!d.writable||!d.configurable||d.value.name!==key||d.value.length!==arity||Object.hasOwn(d.value,"prototype"))throw Error("class method "+key);
        \\ }
        \\ for(const key of ["appearance","colors"]){
        \\   const d=Object.getOwnPropertyDescriptor(Theme.prototype,key);
        \\   if(d.enumerable||!d.configurable||d.set!==undefined||d.get.name!=="get "+key||d.get.length!==0)throw Error("class getter "+key);
        \\ }
        \\ if(Theme.prototype.constructor!==Theme)throw Error("same original constructor");
        \\ return true;
        \\})()
    );
}
test "Public Theme actual frozen helper output over the genuine eager syntax owner" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try install(engine);
    try check(engine,
        \\(() => {
        \\ publicThemeNative.initTheme("dark");
        \\ const n=publicThemeNative,s=publicThemeSource;
        \\ for(const [code,lang] of [["const value = 7;\n","javascript"],["{\"ok\":true}","json"],["plain words\nnext",undefined],["plain words\nnext","not-a-language"]]){
        \\   for(const markdown of [false,true]){
        \\     const actual=(markdown?n.getMarkdownTheme().highlightCode:n.highlightCode)(code,lang);
        \\     const expected=(markdown?s.getMarkdownTheme().highlightCode:s.highlightCode)(code,lang);
        \\     if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error("actual syntax lines "+lang);
        \\   }
        \\ }
        \\ for(const name of ["getMarkdownTheme","getSelectListTheme","getSettingsListTheme"]){
        \\   const actual=n[name](),expected=s[name]();
        \\   if(Object.keys(actual).join()!==Object.keys(expected).join())throw Error("mapping key order");
        \\   for(const key of Object.keys(actual)){
        \\     if(key==="highlightCode")continue;
        \\     const a=typeof actual[key]==="function"?actual[key]("text",true):actual[key];
        \\     const b=typeof expected[key]==="function"?expected[key]("text",true):expected[key];
        \\     if(a!==b)throw Error(name+"."+key);
        \\   }
        \\ }
        \\ const object={};if(n.getSettingsListTheme().label(object,false)!==object)throw Error("unselected label identity");
        \\ return true;
        \\})()
    );
}
test "Public Theme actual extension lookup preserves optional access and inherited mapping" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try install(engine);
    try check(engine,
        \\(() => {
        \\ const n=publicThemeNative.getLanguageFromPath,s=publicThemeSource.getLanguageFromPath;
        \\ const paths=["file.TS","file.tsx","a.cxx","a.ps1","file.yaml","Dockerfile","folder/file.unknown","file.constructor","file.toString","","a."];
        \\ for(const path of paths)if(n(path)!==s(path))throw Error("path "+path);
        \\ for(const absent of [null,undefined]){
        \\   const path={split(separator){if(separator!==".")throw Error("separator");return {pop(){return absent}}}};
        \\   if(n(path)!==undefined||s(path)!==undefined)throw Error("optional pop");
        \\ }
        \\ const inherited=()=>({split(){return {pop(){return {toLowerCase(){return {[Symbol.toPrimitive](hint){if(hint!=="string")throw Error("key hint");return "constructor"}}}}}}}});
        \\ if(n(inherited())!==Object||s(inherited())!==Object)throw Error("fresh ordinary mapping prototype");
        \\ return true;
        \\})()
    );
}
test "Public Theme actual highlight catch boundaries and distinct Markdown fallback" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try install(engine);
    try check(engine,
        \\(() => {
        \\ function observe(native,mode,markdown){
        \\   const trace=[],failure={mode};let priorTheme;
        \\   const runtime={theme:{get fg(){trace.push("get fg");return function(token,line){trace.push(["fg",this===runtime.theme,token,line]);return token+":"+line}}}};
        \\   const syntax={
        \\     supportsLanguage:function(lang){"use strict";trace.push(["supports",this===undefined,lang]);if(mode==="supports-throw")throw failure;return mode!=="unsupported"},
        \\     highlight:function(code,options){"use strict";trace.push(["highlight",this===undefined,Object.keys(options),options.language,options.ignoreIllegals,priorTheme===undefined||priorTheme===options.theme]);priorTheme=options.theme;
        \\       if(mode==="highlight-throw")throw failure;
        \\       if(mode==="result-split-throw")return {get split(){trace.push("result split");throw failure}};
        \\       return {get split(){trace.push("result split");return function(separator){trace.push(["result split call",separator]);return ["highlighted"]}}};
        \\     }
        \\   };
        \\   const code={get split(){trace.push("code split");return function(separator){trace.push(["code split call",separator]);return {get map(){trace.push("get map");return function(callback){trace.push(["callback",callback.name,callback.length,Object.hasOwn(callback,"prototype")]);return [callback("line")]}}}}}};
        \\   const source=makePublicThemeSource(runtime.theme,syntax.supportsLanguage,syntax.highlight);
        \\   const pair=native?makeNativeHighlightPair(syntax,runtime):{public:source.highlightCode,markdown:source.getMarkdownTheme().highlightCode};
        \\   try{trace.push(["return",pair[markdown?"markdown":"public"](code,"some-language")]);if(mode==="success")trace.push(["again",pair[markdown?"markdown":"public"](code,"some-language")])}
        \\   catch(reason){trace.push(["throw",reason===failure])}
        \\   return JSON.stringify(trace);
        \\ }
        \\ for(const mode of ["success","unsupported","supports-throw","highlight-throw","result-split-throw"])for(const markdown of [false,true]){
        \\   const expected=observe(false,mode,markdown),actual=observe(true,mode,markdown);
        \\   if(actual!==expected)throw Error(mode+" "+markdown+"\n"+expected+"\n"+actual);
        \\ }
        \\ return true;
        \\})()
    );
}
test "Public Theme actual path method temporaries retire at the next source expression" {
    inline for (.{ false, true }) |native| {
        const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try install(engine);
        try execute(engine, if (native) "globalThis.selectedThemePath=publicThemeNative.getLanguageFromPath" else "globalThis.selectedThemePath=publicThemeSource.getLanguageFromPath");
        try check(engine,
            \\(() => {
            \\ let split,segments,pop,last,lower;
            \\ const key={[Symbol.toPrimitive](hint){if(hint!=="string"||themeHooks.count(2)!==1||themeHooks.count(4)!==1)throw Error("lower result expression retained");return "ts"}};
            \\ lower=function(){return key};lower.holder=themeHooks.make(2);
            \\ last={holder:themeHooks.make(4),get toLowerCase(){if(themeHooks.count(1)!==1||themeHooks.count(3)!==1)throw Error("pop expression retained");const value=lower;lower=undefined;return value}};
            \\ pop=function(){const value=last;last=undefined;return value};pop.holder=themeHooks.make(1);
            \\ segments={holder:themeHooks.make(3),get pop(){if(themeHooks.count(0)!==1)throw Error("split callee retained");const value=pop;pop=undefined;return value}};
            \\ split=function(separator){if(separator!==".")throw Error("split argument");const value=segments;segments=undefined;return value};split.holder=themeHooks.make(0);
            \\ const path={get split(){const value=split;split=undefined;return value}};
            \\ if(selectedThemePath(path)!=="typescript")throw Error("actual result");
            \\ for(let i=0;i<5;i++)if(themeHooks.count(i)!==1)throw Error("actual retirement "+i);
            \\ return true;
            \\})()
        );
    }
}
test "Public Theme actual same-operation private DATA stays ordinary through source catch" {
    inline for (.{ false, true }) |highlight_case| {
        const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try install(engine);
        if (highlight_case) try check(engine,
            \\(() => {
            \\ let original;
            \\ const syntax={supportsLanguage(){return true},highlight(){original=themeHooks.freshPrivateData();throw original}};
            \\ const pair=makeNativeHighlightPair(syntax,{theme:{fg(token,line){return line}}});
            \\ const result=pair.public("plain\nlines","language");
            \\ if(result.join("|")!=="plain|lines"||!themeHooks.isUnmarkedPrivateData(original))throw Error("ordinary catch DATA");
            \\ return true;
            \\})()
        ) else try check(engine,
            \\(() => {
            \\ let original,seen=false;
            \\ const path={get split(){original=themeHooks.freshPrivateData();throw original}};
            \\ try{publicThemeNative.getLanguageFromPath(path)}catch(reason){if(reason!==original)throw Error("DATA identity");seen=true}
            \\ if(!seen||!themeHooks.isUnmarkedPrivateData(original))throw Error("ordinary getter DATA");
            \\ return true;
            \\})()
        );
    }
}
test "Public Theme actual current fatal bypasses the ordinary highlighting catch" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try install(engine);
    const hooks = try rawGlobal(engine, "themeHooks"); defer engine.freeValue(hooks);
    const record = try engine.checked(c.JS_GetPropertyStr(engine.context, hooks, "record")); defer engine.freeValue(record);
    try execute(engine,
        \\globalThis.fatalThemePair=makeNativeHighlightPair({
        \\ supportsLanguage(){return true},
        \\ highlight(){themeHooks.freshPrivateData();try{themeHooks.raiseNativeFatal()}catch(error){themeHooks.record.guestReached=true}themeHooks.record.guestReached=true;return "bad"}
        \\},{theme:{fg(){themeHooks.record.guestReached=true;return "bad"}}});
        \\globalThis.fatalThemeCode={get split(){themeHooks.record.guestReached=true;return function(){return []}}};
    );
    try std.testing.expectError(error.JavaScriptException, engine.eval("fatalThemePair.public(fatalThemeCode,'language')", "actual-theme-fatal.js", c.JS_EVAL_TYPE_GLOBAL));
    try retirement.verifyRecordedActualNativeFatal(engine, record);
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
test "Public Theme actual callee retirement producer stops the next path getter" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try install(engine);
    const hooks = try rawGlobal(engine, "themeHooks"); defer engine.freeValue(hooks);
    const record = try engine.checked(c.JS_GetPropertyStr(engine.context, hooks, "record")); defer engine.freeValue(record);
    try execute(engine,
        \\let pathSplit=function(){return {get pop(){themeHooks.visit(2);return function(){return "ts"}}}};
        \\pathSplit.holder=themeHooks.make(0);
        \\globalThis.fatalThemePath={get split(){const value=pathSplit;pathSplit=undefined;return value}};
        \\themeHooks.armFatal(0);
    );
    try std.testing.expectError(error.JavaScriptException, engine.eval("publicThemeNative.getLanguageFromPath(fatalThemePath)", "actual-theme-retirement.js", c.JS_EVAL_TYPE_GLOBAL));
    try retirement.verifyActualRetirementFatal(engine, record, 0);
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
test "Public Theme actual complete191 owner retains lazy import and distinct readiness" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try @import("extensions/native_tui.zig").install(engine);
    const eager = try @import("extensions/native_syntax_highlight.zig").createEager(engine); defer eager.deinit(engine);
    const original = engine.native_module_values.get("pi-coding-agent").?;
    try high.install(engine, eager.syntax, original);
    const legacy = c.JS_DupValue(engine.context, engine.native_module_values.get("pi-native:themed-highlight").?); defer engine.freeValue(legacy);
    try install(engine);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, legacy, engine.native_module_values.get("pi-native:themed-highlight").?));
    const syntax = try theme.syntax(engine); defer engine.freeValue(syntax);
    const ready = try theme.readiness(engine); defer engine.freeValue(ready);
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, ready));
    const load = try engine.checked(c.JS_GetPropertyStr(engine.context, syntax, "loadAllHighlightLanguages")); defer engine.freeValue(load);
    const pending = try engine.checked(c.JS_Call(engine.context, load, c.pi_js_undefined(), 0, null)); defer engine.freeValue(pending);
    const namespace = try engine.awaitValue(pending); defer engine.freeValue(namespace);
    const actual_ready = try engine.awaitValue(ready); defer engine.freeValue(actual_ready);
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, ready));
    try check(engine, "publicThemeSyntax.supportsLanguage('erlang')&&publicThemeSyntax.supportsLanguage('ocaml')");
}
