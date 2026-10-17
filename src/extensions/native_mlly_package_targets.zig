//! import-meta-resolve4.2 package target/exports policy, including its actual
//! imports-pattern prefix rule. R is the native resolver, not a guest hook.
const m = @import("native_mlly_values.zig");
const e = @import("native_mlly_errors.zig");
const c = m.c;
const Scope = m.Scope;
pub const Request = struct {
    package_url: c.JSValue, target: c.JSValue, subpath: c.JSValue, match: c.JSValue,
    base: c.JSValue, conditions: c.JSValue,
    pattern: bool = false, internal: bool = false, path_map: bool = false,
};
fn yes(s: *Scope, value: c.JSValue, method: [*:0]const u8, arg: c.JSValue) !bool { return s.truthy(try s.invoke(value, method, &.{arg})); }
fn length(s: *Scope, value: c.JSValue) !c.JSValue { return s.get(value, "length"); }
fn slice(s: *Scope, value: c.JSValue, start: c.JSValue, end: ?c.JSValue) !c.JSValue { return s.invoke(value, "slice", if (end) |last| &.{start,last} else &.{start}); }
fn keys(s: *Scope, value: c.JSValue) !c.JSValue { return s.invoke(try s.global("Object"), "getOwnPropertyNames", &.{value}); }
fn isArray(s: *Scope, value: c.JSValue) !bool { return s.truthy(try s.invoke(try s.global("Array"), "isArray", &.{value})); }
fn replacement(engine: *m.v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { return c.JS_DupValue(engine.context, roots[0]); }
fn replacer(s: *Scope, value: c.JSValue) !c.JSValue { return s.own(try m.functions.createArrow(s.engine, "", 0, replacement, &.{value})); }
fn replacePattern(context: m.Context, s: *Scope, target: c.JSValue, subpath: c.JSValue) !c.JSValue {
    const function = try context.get(s, "regexpReplace"); const call = try s.get(function, "call");
    const pattern = try context.get(s, "pattern"); const callback = try replacer(s, subpath);
    return s.call(call, function, &.{ pattern, target, callback });
}
fn segmentSlice(context:m.Context,s:*Scope,name:[*:0]const u8,value:c.JSValue) !bool {
    const regex=try context.get(s,name);const exec=try s.get(regex,"exec");
    const tail=try s.invoke(value,"slice",&.{m.integer(s,2)});
    return !c.JS_IsNull(try s.call(exec,regex,&.{tail}));
}
fn requestName(s: *Scope, request: Request) !c.JSValue {
    if (!request.pattern) return s.concat(request.match, request.subpath);
    const replace = try s.get(request.match, "replace");
    return s.call(replace, request.match, &.{ try s.text("*"), try replacer(s, request.subpath) });
}
fn invalidTarget(context: m.Context, s: *Scope, request: Request) !c.JSValue {
    // typeof object includes arrays, excludes functions, as in the actual clone.
    const target = if (m.object(request.target, s.engine)) try s.invoke(try s.global("JSON"), "stringify", &.{ request.target, c.pi_js_null(), try s.text("") }) else try s.stringify(request.target);
    const package_path = try context.file(s, try context.url(s, try s.text("."), request.package_url));
    const base = if (s.truthy(request.base)) try context.file(s, request.base) else request.base;
    return e.create(context, s, .ERR_INVALID_PACKAGE_TARGET, &.{ package_path, request.match, target, c.pi_js_bool(s.engine.context, @intFromBool(request.internal)), base });
}
fn invalidSubpath(context: m.Context, s: *Scope, request: Request, name: c.JSValue) !c.JSValue {
    const reason = try e.template(s, &.{ try s.text("request is not a valid match in pattern \""), request.match, try s.text("\" for the \""), try s.text(if (request.internal) "imports" else "exports"), try s.text("\" resolution of "), try context.file(s, request.package_url) });
    return e.create(context, s, .ERR_INVALID_MODULE_SPECIFIER, &.{ name, reason, if (s.truthy(request.base)) try context.file(s, request.base) else request.base });
}
fn emitInvalid(context: m.Context, s: *Scope, request: Request, target: c.JSValue, name: c.JSValue, is_target: bool) !void {
    const process = try context.get(s, "process"); if (s.truthy(try s.get(process, "noDeprecation"))) return;
    const path = try context.file(s, request.package_url);
    const double = try context.regexExec(s, "doubleSlash", if (is_target) target else name);
    const emit = try s.get(process, "emitWarning");
    var text = try e.template(s, &.{ try s.text("Use of deprecated "), try s.text(if (double) "double slash" else "leading or trailing slash matching"), try s.text(" resolving \""), target, try s.text("\" for module ") });
    text = try s.concat(text, try e.template(s, &.{ try s.text("request \""), name, try s.text("\" ") }));
    if (!s.equal(name, request.match)) text = try s.concat(text, try e.template(s, &.{ try s.text("matched to \""), request.match, try s.text("\" ") }));
    text = try s.concat(text, try e.template(s, &.{ try s.text("in the \""), try s.text(if (request.internal) "imports" else "exports"), try s.text("\" field module resolution of the package at "), path }));
    if (s.truthy(request.base)) text = try s.concat(text, try e.template(s, &.{ try s.text(" imported from "), try context.file(s, request.base) }));
    text = try s.concat(text, try s.text("."));
    _ = try s.call(emit, process, &.{ text, try s.text("DeprecationWarning"), try s.text("DEP0166") });
}
fn emitTrailing(context: m.Context, s: *Scope, name: c.JSValue, package_url: c.JSValue, base: c.JSValue) !void {
    const process = try context.get(s, "process"); if (s.truthy(try s.get(process, "noDeprecation"))) return;
    const path = try context.file(s, package_url); const emitted = try context.get(s, "emittedWarnings");
    if (s.truthy(try s.invoke(emitted, "has", &.{try e.template(s, &.{path, try s.text("|"), name})}))) return;
    _ = try s.invoke(emitted, "add", &.{try e.template(s, &.{path, try s.text("|"), name})});
    const emit = try s.get(process, "emitWarning");
    var text = try e.template(s, &.{try s.text("Use of deprecated trailing slash pattern mapping \""), name, try s.text("\" in the ")});
    text = try s.concat(text, try e.template(s, &.{try s.text("\"exports\" field module resolution of the package at "), path}));
    if (s.truthy(base)) text = try s.concat(text, try e.template(s, &.{try s.text(" imported from "), try context.file(s, base)}));
    text = try s.concat(text, try s.text(". Mapping specifiers ending in \"/\" is no longer supported."));
    _ = try s.call(emit, process, &.{text, try s.text("DeprecationWarning"), try s.text("DEP0155")});
}
pub fn Policy(comptime R: type) type { return struct {
    pub fn target(resolver: *R, s: *Scope, request: Request) anyerror!c.JSValue {
        const generation = s.engine.native_allocation_generation;
        return targetBody(resolver, s, request) catch |err| return m.exact(s.engine, err, generation);
    }
    fn targetBody(resolver: *R, s: *Scope, request: Request) anyerror!c.JSValue {
        try m.budget(s.engine, &resolver.steps);
        const context = resolver.context;
        if (c.JS_IsString(request.target)) return stringTarget(resolver, s, request);
        if (try isArray(s, request.target)) {
            if (s.equal(try length(s, request.target), m.integer(s, 0))) return c.pi_js_null();
            var last = c.pi_js_undefined(); defer s.engine.freeValue(last);
            var i: i64 = 0;
            while (s.truthy(try m.binary(s, 4, m.integer(s, i), try length(s, request.target)))) : (i += 1) {
                try m.budget(s.engine, &resolver.steps);
                var step: Scope = .{ .engine = s.engine }; defer step.deinit();
                var child = request; child.target = try m.at(&step, request.target, m.integer(&step, i));
                const generation = s.engine.native_allocation_generation;
                const value = target(resolver, &step, child) catch |err| {
                    const exception = try m.caught(&step, err, generation);
                    s.engine.freeValue(last); last = c.JS_DupValue(s.engine.context, exception);
                    if (try m.equal(&step, try step.get(exception, "code"), "ERR_INVALID_PACKAGE_TARGET")) continue;
                    return m.throwReason(s.engine, exception);
                };
                if (c.JS_IsUndefined(value)) continue;
                if (c.JS_IsNull(value)) { s.engine.freeValue(last); last = c.pi_js_null(); continue; }
                return s.own(c.JS_DupValue(s.engine.context, value));
            }
            if (m.v.nullish(last)) return c.pi_js_null();
            return m.throwReason(s.engine, last);
        }
        if (m.object(request.target, s.engine)) {
            const names = try keys(s, request.target);
            var i: i64 = 0;
            while (s.truthy(try m.binary(s, 4, m.integer(s, i), try length(s, names)))) : (i += 1) {
                try m.budget(s.engine, &resolver.steps);
                var step: Scope = .{ .engine = s.engine }; defer step.deinit();
                const key = try m.at(&step, names, m.integer(&step, i));
                const number = try step.call(try step.global("Number"), c.pi_js_undefined(), &.{key});
                if (!step.equal(try step.stringify(number), key)) continue;
                if (step.truthy(try m.binary(&step, 7, number, m.integer(&step, 0))) and step.truthy(try m.binary(&step, 4, number, m.integer(&step, 0xffffffff)))) {
                    const failure = try e.create(context, &step, .ERR_INVALID_PACKAGE_CONFIG, &.{try context.file(&step, request.package_url), request.base, try step.text("\"exports\" cannot contain numeric property keys.")});
                    return m.throwReason(s.engine, failure);
                }
            }
            i = 0;
            while (s.truthy(try m.binary(s, 4, m.integer(s, i), try length(s, names)))) : (i += 1) {
                try m.budget(s.engine, &resolver.steps);
                var step: Scope = .{ .engine = s.engine }; defer step.deinit();
                const key = try m.at(&step, names, m.integer(&step, i));
                if (try m.equal(&step, key, "default") or (step.truthy(request.conditions) and step.truthy(try step.invoke(request.conditions, "has", &.{key})))) {
                    var child = request; child.target = try m.at(&step, request.target, key);
                    const value = try target(resolver, &step, child);
                    if (c.JS_IsUndefined(value)) continue;
                    return s.own(c.JS_DupValue(s.engine.context, value));
                }
            }
            return c.pi_js_null();
        }
        if (c.JS_IsNull(request.target)) return c.pi_js_null();
        return m.throwReason(s.engine, try invalidTarget(context, s, request));
    }
    fn stringTarget(resolver: *R, s: *Scope, request: Request) anyerror!c.JSValue {
        const context = resolver.context; const value = request.target;
        if (!try m.equal(s, request.subpath, "") and !request.pattern) {
            if (!try m.equal(s, try m.at(s, value, try m.binary(s, 1, try length(s, value), m.integer(s, 1))), "/")) return m.throwReason(s.engine, try invalidTarget(context, s, request));
        }
        if (!try yes(s, value, "startsWith", try s.text("./"))) {
            if (request.internal and !try yes(s, value, "startsWith", try s.text("../")) and !try yes(s, value, "startsWith", try s.text("/"))) {
                const generation = s.engine.native_allocation_generation;
                const as_url: ?c.JSValue = context.url(s, value, null) catch |err| blk: { _ = try m.caught(s, err, generation); break :blk null; };
                if (as_url == null) return resolver.packageResolve(s, if (request.pattern) try replacePattern(context, s, value, request.subpath) else try s.concat(value, request.subpath), request.package_url, request.conditions);
            }
            return m.throwReason(s.engine, try invalidTarget(context, s, request));
        }
        if (try segmentSlice(context,s,"invalidSegment",value)) {
            if (!try segmentSlice(context,s,"deprecatedInvalidSegment",value)) {
                if (!request.path_map) {
                    const name = try requestName(s, request);
                    const resolved_target = if (request.pattern) try replacePattern(context, s, value, request.subpath) else value;
                    try emitInvalid(context, s, request, resolved_target, name, true);
                }
            } else return m.throwReason(s.engine, try invalidTarget(context, s, request));
        }
        const resolved = try context.url(s, value, request.package_url);
        const resolved_path = try s.get(resolved, "pathname");
        const package_path = try s.get(try context.url(s, try s.text("."), request.package_url), "pathname");
        if (!try yes(s, resolved_path, "startsWith", package_path)) return m.throwReason(s.engine, try invalidTarget(context, s, request));
        if (try m.equal(s, request.subpath, "")) return resolved;
        if (try context.regexExec(s, "invalidSegment", request.subpath)) {
            const name = try requestName(s, request);
            if (!try context.regexExec(s, "deprecatedInvalidSegment", request.subpath)) {
                if (!request.path_map) try emitInvalid(context, s, request, if (request.pattern) try replacePattern(context, s, value, request.subpath) else value, name, false);
            } else return m.throwReason(s.engine, try invalidSubpath(context, s, request, name));
        }
        if (request.pattern) {
            const constructor = try s.global("URL");
            const replaced = try replacePattern(context, s, try s.get(resolved, "href"), request.subpath);
            return context.constructURL(s, constructor, &.{replaced});
        }
        return context.url(s, request.subpath, resolved);
    }
    fn sugar(resolver: *R, s: *Scope, value: c.JSValue, package_url: c.JSValue, base: c.JSValue) anyerror!bool {
        if (c.JS_IsString(value) or try isArray(s, value)) return true;
        if (!m.object(value, s.engine)) return false;
        const names = try keys(s, value); var first = true; var previous = false; var i: i64 = 0;
        while (s.truthy(try m.binary(s, 4, m.integer(s, i), try length(s, names)))) : (i += 1) {
            try m.budget(s.engine, &resolver.steps);
            var step: Scope = .{ .engine = s.engine }; defer step.deinit();
            const key = try m.at(&step, names, m.integer(&step, i));
            const current = try m.equal(&step, key, "") or !try m.equal(&step, try m.at(&step, key, m.integer(&step, 0)), ".");
            if (first) { previous = current; first = false; } else if (previous != current) {
                const failure = try e.create(resolver.context, &step, .ERR_INVALID_PACKAGE_CONFIG, &.{try resolver.context.file(&step, package_url), base, try step.text("\"exports\" cannot contain some keys starting with '.' and some not. The exports object must either be an object of package subpath keys or an object of main entry condition name keys only.")});
                return m.throwReason(s.engine, failure);
            }
        }
        return previous;
    }
    pub fn exportsNotFound(resolver: *R, s: *Scope, subpath: c.JSValue, package_url: c.JSValue, base: c.JSValue) !c.JSValue {
        const context = resolver.context;
        const path = try context.file(s, try context.url(s, try s.text("."), package_url));
        return e.create(context, s, .ERR_PACKAGE_PATH_NOT_EXPORTED, &.{ path, subpath, if (s.truthy(base)) try context.file(s, base) else base });
    }
    pub fn exportsResolve(resolver: *R, s: *Scope, package_url: c.JSValue, subpath: c.JSValue, config: c.JSValue, base: c.JSValue, conditions: c.JSValue) anyerror!c.JSValue {
        const generation = s.engine.native_allocation_generation;
        return exportsBody(resolver, s, package_url, subpath, config, base, conditions) catch |err| return m.exact(s.engine, err, generation);
    }
    fn exportsBody(resolver: *R, s: *Scope, package_url: c.JSValue, subpath: c.JSValue, config: c.JSValue, base: c.JSValue, conditions: c.JSValue) anyerror!c.JSValue {
        var exports = try s.get(config, "exports");
        if (try sugar(resolver, s, exports, package_url, base)) { const wrapped = try s.object(); try m.define(s, wrapped, ".", exports); exports = wrapped; }
        if (try resolver.context.own(s, exports, subpath) and !try yes(s, subpath, "includes", try s.text("*")) and !try yes(s, subpath, "endsWith", try s.text("/"))) {
            const resolved = try target(resolver, s, .{.package_url=package_url,.target=try m.at(s,exports,subpath),.subpath=try s.text(""),.match=subpath,.base=base,.conditions=conditions});
            if (m.v.nullish(resolved)) return m.throwReason(s.engine, try exportsNotFound(resolver, s, subpath, package_url, base));
            return resolved;
        }
        const best = try bestMatch(resolver, s, exports, subpath, false, package_url, base);
        if (s.truthy(best.key)) {
            const resolved = try target(resolver, s, .{.package_url=package_url,.target=try m.at(s,exports,best.key),.subpath=best.subpath,.match=best.key,.base=base,.conditions=conditions,.pattern=true,.path_map=try yes(s,subpath,"endsWith",try s.text("/"))});
            if (m.v.nullish(resolved)) return m.throwReason(s.engine, try exportsNotFound(resolver, s, subpath, package_url, base));
            return resolved;
        }
        return m.throwReason(s.engine, try exportsNotFound(resolver, s, subpath, package_url, base));
    }
    const Match = struct { key: c.JSValue, subpath: c.JSValue };
    pub fn bestMatch(resolver: *R, s: *Scope, mapping: c.JSValue, name: c.JSValue, internal: bool, package_url: c.JSValue, base: c.JSValue) anyerror!Match {
        var best: Match = .{ .key=try s.text(""),.subpath=try s.text("") }; const names=try keys(s,mapping); var i:i64=0;
        while (s.truthy(try m.binary(s,4,m.integer(s,i),try length(s,names)))) : (i+=1) {
            try m.budget(s.engine,&resolver.steps);
            var step:Scope=.{.engine=s.engine}; defer step.deinit();
            const key=try m.at(&step,names,m.integer(&step,i)); const index=try step.invoke(key,"indexOf",&.{try step.text("*")});
            if (step.equal(index,m.integer(&step,-1))) continue;
            // Deliberately preserve this cloned resolver's actual imports rule.
            const starts=try step.get(name,"startsWith");
            const prefix=try slice(&step,key,m.integer(&step,0),if(internal)m.integer(&step,-1) else index);
            if (!step.truthy(try step.call(starts,name,&.{prefix}))) continue;
            if (!internal and try yes(&step,name,"endsWith",try step.text("/"))) try emitTrailing(resolver.context,&step,name,package_url,base);
            const slice_key=try step.get(key,"slice");
            const trailer=try step.call(slice_key,key,&.{try m.binary(&step,0,index,m.integer(&step,1))});
            if (!step.truthy(try m.binary(&step,7,try length(&step,name),try length(&step,key)))) continue;
            if (!try yes(&step,name,"endsWith",trailer)) continue;
            if (try patternKeyCompare(&step,best.key,key)!=1) continue;
            if (!step.equal(try step.invoke(key,"lastIndexOf",&.{try step.text("*")}),index)) continue;
            const slice_name=try step.get(name,"slice");
            const sub=try step.call(slice_name,name,&.{index,try m.binary(&step,1,try length(&step,name),try length(&step,trailer))});
            best=.{.key=try s.own(c.JS_DupValue(s.engine.context,key)),.subpath=try s.own(c.JS_DupValue(s.engine.context,sub))};
        }
        return best;
    }
}; }
pub fn patternKeyCompare(s:*Scope,a:c.JSValue,b:c.JSValue) !i32 {
    const ai=try s.invoke(a,"indexOf",&.{try s.text("*")}); const bi=try s.invoke(b,"indexOf",&.{try s.text("*")});
    const al=if(s.equal(ai,m.integer(s,-1)))try length(s,a) else try m.binary(s,0,ai,m.integer(s,1));
    const bl=if(s.equal(bi,m.integer(s,-1)))try length(s,b) else try m.binary(s,0,bi,m.integer(s,1));
    if(s.truthy(try m.binary(s,6,al,bl)))return -1; if(s.truthy(try m.binary(s,6,bl,al)))return 1;
    if(s.equal(ai,m.integer(s,-1)))return 1; if(s.equal(bi,m.integer(s,-1)))return -1;
    if(s.truthy(try m.binary(s,6,try length(s,a),try length(s,b))))return -1;
    if(s.truthy(try m.binary(s,6,try length(s,b),try length(s,a))))return 1; return 0;
}
