//! Complete Source highlight.js10.7.3 _highlight scanner body, source-only draft.
//! Bindings are the real native core closures, not guest implementation shims.
//! Original21 grammar, scanner, GC and allocation qualification remain pending.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const sdk = @import("native_sdk.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const compiler = @import("native_highlight_mode_compiler.zig");
const regex = @import("native_highlight_regex.zig");
const classes = @import("native_highlight_classes.zig");
const c = em.c;
fn op(scope: *Scope, kind: c_int, a: c.JSValue, b: c.JSValue) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, kind, a, b)));
}
fn at(scope: *Scope, value: c.JSValue, index: u32) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, value, index)));
}
fn key(scope: *Scope, value: c.JSValue, index: c.JSValue) !c.JSValue {
    return scope.own(try js.getKey(scope.engine, value, index));
}
fn zero(scope: *Scope) c.JSValue {
    return c.JS_NewInt32(scope.engine.context, 0);
}
fn one(scope: *Scope) c.JSValue {
    return c.JS_NewInt32(scope.engine.context, 1);
}
fn throwValue(scope: *Scope, reason: c.JSValue) !void {
    _ = c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, reason));
    return js.capture(scope.engine);
}
fn errorValue(scope: *Scope, message: c.JSValue) !c.JSValue {
    var args = [_]c.JSValue{message};
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.global("Error"), args.len, &args)));
}
const Scanner = struct {
    scope: *Scope,
    bindings: c.JSValue,
    language_name: c.JSValue,
    code: c.JSValue,
    ignore_illegals: c.JSValue,
    language: c.JSValue,
    top: c.JSValue,
    continuations: c.JSValue,
    emitter: c.JSValue,
    buffer: c.JSValue,
    relevance: c.JSValue,
    index: c.JSValue,
    iterations: u64 = 0,
    native_steps: u64 = 0,
    resume_at_same: bool = false,
    last_match: c.JSValue,
    result: c.JSValue,
    fn tick(self: *Scanner) !void {
        const engine = self.scope.engine;
        self.native_steps +|= 1;
        if (engine.cancelled.load(.acquire) or (self.native_steps % 256 == 0 and blk: {
            engine.interrupts +|= 1;
            break :blk engine.interrupts > engine.options.interrupt_budget;
        })) {
            _ = try engine.checked(c.JS_ThrowInternalError(engine.context, "interrupted"));
            unreachable;
        }
    }
    fn core(self: *Scanner, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
        return self.scope.call(try self.scope.get(self.bindings, name), c.pi_js_undefined(), args);
    }
    fn makeResponse(self: *Scanner, mode: c.JSValue) !c.JSValue {
        var args = [_]c.JSValue{mode};
        return self.scope.own(try self.scope.engine.checked(c.JS_CallConstructor(self.scope.engine.context, try self.scope.get(self.bindings, "Response"), args.len, &args)));
    }
    fn keywordData(self: *Scanner, mode: c.JSValue, match: c.JSValue) !c.JSValue {
        const scope = self.scope;
        const text = if (scope.truthy(try scope.get(self.language, "case_insensitive"))) try scope.invoke(try at(scope, match, 0), "toLowerCase", &.{}) else try at(scope, match, 0);
        const object = try scope.global("Object");
        const has = try scope.get(try scope.get(object, "prototype"), "hasOwnProperty");
        const present = try scope.invoke(has, "call", &.{ try scope.get(mode, "keywords"), text });
        return if (scope.truthy(present)) try key(scope, try scope.get(mode, "keywords"), text) else present;
    }
    fn processKeywords(self: *Scanner) !void {
        const scope = self.scope;
        if (!scope.truthy(try scope.get(self.top, "keywords"))) {
            _ = try scope.invoke(self.emitter, "addText", &.{self.buffer});
            return;
        }
        var last_index = zero(scope);
        try scope.set(try scope.get(self.top, "keywordPatternRe"), "lastIndex", zero(scope));
        var match = try scope.invoke(try scope.get(self.top, "keywordPatternRe"), "exec", &.{self.buffer});
        var buf = try scope.text("");
        while (scope.truthy(match)) {
            try self.tick();
            buf = try scope.concat(buf, try scope.invoke(self.buffer, "substring", &.{ last_index, try scope.get(match, "index") }));
            const data = try self.keywordData(self.top, match);
            if (scope.truthy(data)) {
                // Source array-pattern binding invokes the iterator, not numeric getters.
                const pair = try destructurePair(scope, data);
                const kind = pair[0];
                const relevance = pair[1];
                _ = try scope.invoke(self.emitter, "addText", &.{buf});
                buf = try scope.text("");
                self.relevance = try op(scope, 0, self.relevance, relevance);
                if (scope.truthy(try scope.invoke(kind, "startsWith", &.{try scope.text("_")}))) {
                    buf = try scope.concat(buf, try at(scope, match, 0));
                } else {
                    const alias = try key(scope, try scope.get(self.language, "classNameAliases"), kind);
                    _ = try scope.invoke(self.emitter, "addKeyword", &.{ try at(scope, match, 0), if (scope.truthy(alias)) alias else kind });
                }
            } else {
                buf = try scope.concat(buf, try at(scope, match, 0));
            }
            last_index = try scope.get(try scope.get(self.top, "keywordPatternRe"), "lastIndex");
            match = try scope.invoke(try scope.get(self.top, "keywordPatternRe"), "exec", &.{self.buffer});
        }
        buf = try scope.concat(buf, try scope.invoke(self.buffer, "substr", &.{last_index}));
        _ = try scope.invoke(self.emitter, "addText", &.{buf});
    }
    fn processSubLanguage(self: *Scanner) !void {
        const scope = self.scope;
        if (scope.equal(self.buffer, try scope.text(""))) return;
        var result = c.pi_js_null();
        if (c.JS_IsString(try scope.get(self.top, "subLanguage"))) {
            if (!scope.truthy(try key(scope, try scope.get(self.bindings, "languages"), try scope.get(self.top, "subLanguage")))) {
                _ = try scope.invoke(self.emitter, "addText", &.{self.buffer});
                return;
            }
            result = try self.core("_highlight", &.{ try scope.get(self.top, "subLanguage"), self.buffer, c.pi_js_bool(scope.engine.context, 1), try key(scope, self.continuations, try scope.get(self.top, "subLanguage")) });
            try js.setKey(scope.engine, self.continuations, try scope.get(self.top, "subLanguage"), try scope.get(result, "top"));
        } else {
            const length = try scope.get(try scope.get(self.top, "subLanguage"), "length");
            result = try self.core("highlightAuto", &.{ self.buffer, if (scope.truthy(length)) try scope.get(self.top, "subLanguage") else c.pi_js_null() });
        }
        if (scope.truthy(try op(scope, 6, try scope.get(self.top, "relevance"), zero(scope)))) self.relevance = try op(scope, 0, self.relevance, try scope.get(result, "relevance"));
        _ = try scope.invoke(self.emitter, "addSublanguage", &.{ try scope.get(result, "emitter"), try scope.get(result, "language") });
    }
    fn processBuffer(self: *Scanner) !void {
        const sub = try self.scope.get(self.top, "subLanguage");
        if (!c.JS_IsNull(sub) and !c.JS_IsUndefined(sub)) try self.processSubLanguage() else try self.processKeywords();
        self.buffer = try self.scope.text("");
    }
    fn startNewMode(self: *Scanner, mode: c.JSValue) !void {
        const scope = self.scope;
        if (scope.truthy(try scope.get(mode, "className"))) {
            const alias = try key(scope, try scope.get(self.language, "classNameAliases"), try scope.get(mode, "className"));
            _ = try scope.invoke(self.emitter, "openNode", &.{if (scope.truthy(alias)) alias else try scope.get(mode, "className")});
        }
        const descriptors = try scope.object();
        const parent = try scope.object();
        try scope.put(parent, "value", self.top);
        try scope.put(descriptors, "parent", parent);
        self.top = try scope.invoke(try scope.global("Object"), "create", &.{ mode, descriptors });
    }
    fn endOfMode(self: *Scanner, initial: c.JSValue, match: c.JSValue, remainder: c.JSValue) !c.JSValue {
        const scope = self.scope;
        var mode = initial;
        try self.tick();
        var matched = try scope.own(try regex.startsWith(scope.engine, try scope.get(mode, "endRe"), remainder));
        if (scope.truthy(matched)) {
            if (scope.truthy(try scope.get(mode, "on:end"))) {
                const response = try self.makeResponse(mode);
                _ = try scope.invoke(mode, "on:end", &.{ match, response });
                if (scope.truthy(try scope.get(response, "isMatchIgnored"))) matched = c.pi_js_bool(scope.engine.context, 0);
            }
            if (scope.truthy(matched)) {
                while (scope.truthy(try scope.get(mode, "endsParent")) and scope.truthy(try scope.get(mode, "parent"))) {
                    try self.tick();
                    mode = try scope.get(mode, "parent");
                }
                return mode;
            }
        }
        if (scope.truthy(try scope.get(mode, "endsWithParent"))) return self.endOfMode(try scope.get(mode, "parent"), match, remainder);
        return c.pi_js_undefined();
    }
    fn doIgnore(self: *Scanner, lexeme: c.JSValue) !c.JSValue {
        const scope = self.scope;
        if (scope.equal(try scope.get(try scope.get(self.top, "matcher"), "regexIndex"), zero(scope))) {
            self.buffer = try scope.concat(self.buffer, try at(scope, lexeme, 0));
            return one(scope);
        }
        self.resume_at_same = true;
        return zero(scope);
    }
    fn makeEscaped(self: *Scanner, value: c.JSValue) !c.JSValue {
        const scope = self.scope;
        var pattern_args = [_]c.JSValue{ try scope.text("[-/\\\\^$*+?.()|[\\]{}]"), try scope.text("g") };
        const pattern = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, pattern_args.len, &pattern_args)));
        const escaped = try scope.invoke(value, "replace", &.{ pattern, try scope.text("\\$&") });
        var args = [_]c.JSValue{ escaped, try scope.text("m") };
        return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.global("RegExp"), args.len, &args)));
    }
    fn doBeginMatch(self: *Scanner, match: c.JSValue) !c.JSValue {
        const scope = self.scope;
        const lexeme = try at(scope, match, 0);
        const mode = try scope.get(match, "rule");
        const response = try self.makeResponse(mode);
        // Source eagerly reads both callbacks before invoking either of them.
        const callbacks = [_]c.JSValue{ try scope.get(mode, "__beforeBegin"), try scope.get(mode, "on:begin") };
        for (callbacks) |callback| {
            if (!scope.truthy(callback)) continue;
            _ = try scope.call(callback, c.pi_js_undefined(), &.{ match, response });
            if (scope.truthy(try scope.get(response, "isMatchIgnored"))) return self.doIgnore(lexeme);
        }
        if (scope.truthy(mode) and scope.truthy(try scope.get(mode, "endSameAsBegin"))) try scope.set(mode, "endRe", try self.makeEscaped(lexeme));
        if (scope.truthy(try scope.get(mode, "skip"))) {
            self.buffer = try scope.concat(self.buffer, lexeme);
        } else {
            if (scope.truthy(try scope.get(mode, "excludeBegin"))) self.buffer = try scope.concat(self.buffer, lexeme);
            try self.processBuffer();
            if (!scope.truthy(try scope.get(mode, "returnBegin")) and !scope.truthy(try scope.get(mode, "excludeBegin"))) self.buffer = lexeme;
        }
        try self.startNewMode(mode);
        return if (scope.truthy(try scope.get(mode, "returnBegin"))) zero(scope) else try scope.get(lexeme, "length");
    }
    fn doEndMatch(self: *Scanner, match: c.JSValue) !?c.JSValue {
        const scope = self.scope;
        const lexeme = try at(scope, match, 0);
        const remainder = try scope.invoke(self.code, "substr", &.{try scope.get(match, "index")});
        const end = try self.endOfMode(self.top, match, remainder);
        if (!scope.truthy(end)) return null;
        const origin = self.top;
        if (scope.truthy(try scope.get(origin, "skip"))) {
            self.buffer = try scope.concat(self.buffer, lexeme);
        } else {
            if (!(scope.truthy(try scope.get(origin, "returnEnd")) or scope.truthy(try scope.get(origin, "excludeEnd")))) self.buffer = try scope.concat(self.buffer, lexeme);
            try self.processBuffer();
            if (scope.truthy(try scope.get(origin, "excludeEnd"))) self.buffer = lexeme;
        }
        while (true) {
            try self.tick();
            if (scope.truthy(try scope.get(self.top, "className"))) _ = try scope.invoke(self.emitter, "closeNode", &.{});
            if (!scope.truthy(try scope.get(self.top, "skip")) and !scope.truthy(try scope.get(self.top, "subLanguage"))) self.relevance = try op(scope, 0, self.relevance, try scope.get(self.top, "relevance"));
            self.top = try scope.get(self.top, "parent");
            if (scope.equal(self.top, try scope.get(end, "parent"))) break;
        }
        if (scope.truthy(try scope.get(end, "starts"))) {
            if (scope.truthy(try scope.get(end, "endSameAsBegin"))) try scope.set(try scope.get(end, "starts"), "endRe", try scope.get(end, "endRe"));
            try self.startNewMode(try scope.get(end, "starts"));
        }
        return if (scope.truthy(try scope.get(origin, "returnEnd"))) zero(scope) else try scope.get(lexeme, "length");
    }
    fn processContinuations(self: *Scanner) !void {
        const scope = self.scope;
        const list = try scope.array();
        var current = self.top;
        while (!scope.equal(current, self.language)) {
            try self.tick();
            if (scope.truthy(try scope.get(current, "className"))) _ = try scope.invoke(list, "unshift", &.{try scope.get(current, "className")});
            current = try scope.get(current, "parent");
        }
        // The native core callback below is the original list.forEach arrow body.
        var roots = [_]c.JSValue{self.emitter};
        const callback = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, openContinuation, "", 1, 0, roots.len, &roots)));
        _ = try scope.invoke(list, "forEach", &.{callback});
    }
    fn processLexeme(self: *Scanner, before: c.JSValue, match: c.JSValue) !c.JSValue {
        const scope = self.scope;
        const lexeme = if (scope.truthy(match)) try at(scope, match, 0) else match;
        self.buffer = try scope.concat(self.buffer, before);
        if (c.JS_IsNull(lexeme) or c.JS_IsUndefined(lexeme)) {
            try self.processBuffer();
            return zero(scope);
        }
        if (scope.equal(try scope.get(self.last_match, "type"), try scope.text("begin")) and scope.equal(try scope.get(match, "type"), try scope.text("end")) and scope.equal(try scope.get(self.last_match, "index"), try scope.get(match, "index")) and scope.equal(lexeme, try scope.text(""))) {
            self.buffer = try scope.concat(self.buffer, try scope.invoke(self.code, "slice", &.{ try scope.get(match, "index"), try op(scope, 0, try scope.get(match, "index"), one(scope)) }));
            if (!scope.truthy(try scope.get(self.bindings, "safeMode"))) {
                const reason = try errorValue(scope, try scope.text("0 width match regex"));
                try scope.set(reason, "languageName", self.language_name);
                try scope.set(reason, "badRule", try scope.get(self.last_match, "rule"));
                try throwValue(scope, reason);
            }
            return one(scope);
        }
        self.last_match = match;
        if (scope.equal(try scope.get(match, "type"), try scope.text("begin"))) return self.doBeginMatch(match);
        if (scope.equal(try scope.get(match, "type"), try scope.text("illegal")) and !scope.truthy(self.ignore_illegals)) {
            const class_name = try scope.get(self.top, "className");
            const message = try scope.concat(try scope.concat(try scope.concat(try scope.concat(try scope.text("Illegal lexeme \""), lexeme), try scope.text("\" for mode \"")), if (scope.truthy(class_name)) class_name else try scope.text("<unnamed>")), try scope.text("\""));
            const reason = try errorValue(scope, message);
            try scope.set(reason, "mode", self.top);
            try throwValue(scope, reason);
        } else if (scope.equal(try scope.get(match, "type"), try scope.text("end"))) {
            if (try self.doEndMatch(match)) |processed| return processed;
        }
        if (scope.equal(try scope.get(match, "type"), try scope.text("illegal")) and scope.equal(lexeme, try scope.text(""))) return one(scope);
        if (self.iterations > 100000 and scope.truthy(try op(scope, 6, c.JS_NewFloat64(scope.engine.context, @floatFromInt(self.iterations)), try op(scope, 2, try scope.get(match, "index"), c.JS_NewInt32(scope.engine.context, 3))))) try throwValue(scope, try errorValue(scope, try scope.text("potential infinite loop, way more iterations than matches")));
        self.buffer = try scope.concat(self.buffer, lexeme);
        return scope.get(lexeme, "length");
    }
    fn run(self: *Scanner) !c.JSValue {
        const scope = self.scope;
        _ = try scope.invoke(try scope.get(self.top, "matcher"), "considerAll", &.{});
        while (true) {
            self.iterations +|= 1;
            try self.tick();
            if (self.resume_at_same) {
                self.resume_at_same = false;
            } else {
                _ = try scope.invoke(try scope.get(self.top, "matcher"), "considerAll", &.{});
            }
            try scope.set(try scope.get(self.top, "matcher"), "lastIndex", self.index);
            const match = try scope.invoke(try scope.get(self.top, "matcher"), "exec", &.{self.code});
            if (!scope.truthy(match)) break;
            const before = try scope.invoke(self.code, "substring", &.{ self.index, try scope.get(match, "index") });
            const processed = try self.processLexeme(before, match);
            self.index = try op(scope, 0, try scope.get(match, "index"), processed);
        }
        _ = try self.processLexeme(try scope.invoke(self.code, "substr", &.{self.index}), c.pi_js_undefined());
        _ = try scope.invoke(self.emitter, "closeAllNodes", &.{});
        _ = try scope.invoke(self.emitter, "finalize", &.{});
        self.result = try scope.invoke(self.emitter, "toHTML", &.{});
        const result = try scope.object();
        try scope.put(result, "relevance", try scope.invoke(try scope.global("Math"), "floor", &.{self.relevance}));
        try scope.put(result, "value", self.result);
        try scope.put(result, "language", self.language_name);
        try scope.put(result, "illegal", c.pi_js_bool(scope.engine.context, 0));
        try scope.put(result, "emitter", self.emitter);
        try scope.put(result, "top", self.top);
        return result;
    }
    fn handle(self: *Scanner, reason: c.JSValue) !c.JSValue {
        const scope = self.scope;
        const message = try scope.get(reason, "message");
        const result = try scope.object();
        if (scope.truthy(message) and scope.truthy(try scope.invoke(try scope.get(reason, "message"), "includes", &.{try scope.text("Illegal")}))) {
            try scope.put(result, "illegal", c.pi_js_bool(scope.engine.context, 1));
            const illegal = try scope.object();
            try scope.put(illegal, "msg", try scope.get(reason, "message"));
            try scope.put(illegal, "context", try scope.invoke(self.code, "slice", &.{ try op(scope, 1, self.index, c.JS_NewInt32(scope.engine.context, 100)), try op(scope, 0, self.index, c.JS_NewInt32(scope.engine.context, 100)) }));
            try scope.put(illegal, "mode", try scope.get(reason, "mode"));
            try scope.put(result, "illegalBy", illegal);
            try scope.put(result, "sofar", self.result);
            try scope.put(result, "relevance", zero(scope));
            try scope.put(result, "value", try classes.escapeHtml(scope, self.code));
            try scope.put(result, "emitter", self.emitter);
            return result;
        } else if (scope.truthy(try scope.get(self.bindings, "safeMode"))) {
            try scope.put(result, "illegal", c.pi_js_bool(scope.engine.context, 0));
            try scope.put(result, "relevance", zero(scope));
            try scope.put(result, "value", try classes.escapeHtml(scope, self.code));
            try scope.put(result, "emitter", self.emitter);
            try scope.put(result, "language", self.language_name);
            try scope.put(result, "top", self.top);
            try scope.put(result, "errorRaised", reason);
            return result;
        }
        try throwValue(scope, reason);
        unreachable;
    }
};
fn openContinuation(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    _ = scope.invoke(roots[0], "openNode", &.{if (argc > 0) argv[0] else c.pi_js_undefined()}) catch |err| return sdk.fail(engine, err);
    return c.pi_js_undefined();
}
pub fn destructurePair(scope: *Scope, value: c.JSValue) ![2]c.JSValue {
    // IteratorClose after the second element is required for custom keyword data.
    const iterator_symbol = try scope.get(try scope.global("Symbol"), "iterator");
    const iterator = try scope.call(try key(scope, value, iterator_symbol), value, &.{});
    const next = try scope.get(iterator, "next");
    var output = [_]c.JSValue{ c.pi_js_undefined(), c.pi_js_undefined() };
    var done = false;
    for (&output) |*slot| {
        if (done) continue;
        const item = try scope.call(next, iterator, &.{});
        if (!c.JS_IsObject(item)) {
            _ = try scope.engine.checked(c.JS_ThrowTypeError(scope.engine.context, "Iterator result is not an object"));
            unreachable;
        }
        done = scope.truthy(try scope.get(item, "done"));
        if (!done) slot.* = try scope.get(item, "value");
    }
    if (!done) {
        const close = try scope.get(iterator, "return");
        if (!c.JS_IsNull(close) and !c.JS_IsUndefined(close)) {
            const result = try scope.call(close, iterator, &.{});
            if (!c.JS_IsObject(result)) {
                _ = try scope.engine.checked(c.JS_ThrowTypeError(scope.engine.context, "Iterator result is not an object"));
                unreachable;
            }
        }
    }
    return output;
}
pub fn highlight(engine: *em.Engine, bindings: c.JSValue, name: c.JSValue, code: c.JSValue, ignore: c.JSValue, continuation: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const language = try scope.call(try scope.get(bindings, "getLanguage"), c.pi_js_undefined(), &.{name});
    if (!scope.truthy(language)) {
        const diagnostic = try scope.invoke(try scope.text("Could not find the language '{}', did you forget to load/include a language module?"), "replace", &.{ try scope.text("{}"), name });
        _ = try scope.call(try scope.get(bindings, "error"), c.pi_js_undefined(), &.{diagnostic});
        const reason = try errorValue(&scope, try scope.concat(try scope.concat(try scope.text("Unknown language: \""), name), try scope.text("\"")));
        try throwValue(&scope, reason);
        unreachable;
    }
    const compiler_options = try scope.object();
    try scope.put(compiler_options, "plugins", try scope.get(bindings, "plugins"));
    const mode = try scope.own(try compiler.compile(engine, language, compiler_options));
    const top = if (scope.truthy(continuation)) continuation else mode;
    const continuations = try scope.object();
    const options = try scope.get(bindings, "options");
    const emitter_constructor = try scope.get(options, "__emitter");
    var emitter_args = [_]c.JSValue{try scope.get(bindings, "options")};
    const emitter = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, emitter_constructor, emitter_args.len, &emitter_args)));
    var state: Scanner = .{ .scope = &scope, .bindings = bindings, .language_name = name, .code = code, .ignore_illegals = ignore, .language = language, .top = top, .continuations = continuations, .emitter = emitter, .buffer = try scope.text(""), .relevance = zero(&scope), .index = zero(&scope), .last_match = try scope.object(), .result = try scope.text("") };
    try state.processContinuations();
    const result = state.run() catch |err| {
        if (err != error.JavaScriptException) return err;
        // Preserve trusted native OOM identity through Source's ordinary catch.
        // The outer diagnostic generation check remains mandatory.
        const reason = engine.captured_exception orelse return err;
        return c.JS_DupValue(engine.context, try state.handle(try scope.own(c.JS_DupValue(engine.context, reason))));
    };
    return c.JS_DupValue(engine.context, result);
}
