//! Source-specific ignore7.0.8 gitwildmatch compiler. MIT kael.
//! VM strings/regexps preserve UTF16, live methods, callback and throw order.
const v = @import("native_sdk_ignore708_values.zig");
const Scope = v.Scope;
const c = v.c;
const Kind = enum { empty, trim_spaces, quoted_spaces, escape_meta, any, leading_slash, slash, leading_globstar, anchor, globstar, intermediate, trailing, unescape, literal_bracket, ending, trailing_ignore, trailing_check, restore, reduce, last_wildcard, emit_run, token };
const Step = struct { pattern: []const u8 = "", global: bool = false, direct: bool = false, required: ?[]const u8 = null, kind: Kind };
const steps = [_]Step{
    .{ .pattern = "^\\uFEFF", .kind = .empty, .required = "\xef\xbb\xbf" },
    .{ .pattern = "[\\r\\n]+$", .kind = .empty },
    .{ .pattern = "((?:\\\\\\\\)*?)(\\\\? +)$", .kind = .trim_spaces },
    .{ .pattern = "(\\\\+?) ", .global = true, .kind = .quoted_spaces },
    .{ .pattern = "[\\\\$.|*+(){^]", .global = true, .kind = .escape_meta },
    .{ .pattern = "(?!\\\\)\\?", .global = true, .kind = .any, .required = "?" },
    .{ .pattern = "^\\/", .kind = .leading_slash, .required = "/" },
    .{ .pattern = "\\/", .global = true, .kind = .slash, .required = "/" },
    .{ .pattern = "^\\^*(?:\\\\\\*\\\\\\*\\\\\\/)+", .kind = .leading_globstar, .required = "*" },
    .{ .direct = true, .kind = .anchor },
    .{ .pattern = "\\\\\\/\\\\\\*\\\\\\*(?=\\\\\\/|$)", .global = true, .kind = .globstar, .required = "*" },
    .{ .pattern = "(^|[^\\\\]+)(\\\\\\*)+(?=.+)", .global = true, .kind = .intermediate, .required = "*" },
    .{ .pattern = "(^|[^\\\\])((?:\\\\\\\\)*)\\\\\\*$", .kind = .trailing, .required = "*" },
    .{ .pattern = "\\\\\\\\\\\\(?=[$.|*+(){^])", .global = true, .kind = .unescape, .required = "\\\\" },
    .{ .pattern = "\\\\\\\\", .global = true, .kind = .unescape, .required = "\\\\" },
    .{ .pattern = "\\\\\\[([^\\]/]*?)(\\\\*)($|\\])", .global = true, .kind = .literal_bracket, .required = "[" },
    .{ .direct = true, .kind = .ending },
};
fn callbackLength(kind: Kind) c_int { return switch (kind) { .empty,.any,.leading_slash,.slash,.leading_globstar,.unescape => 0, .escape_meta,.ending,.token => 1, .quoted_spaces,.anchor,.trailing_ignore,.trailing_check,.restore,.reduce,.last_wildcard,.emit_run => 2, .trim_spaces,.globstar,.intermediate,.trailing => 3, .literal_bracket => 4 }; }
fn callback(s: *Scope, kind: Kind, owner: c.JSValue, context: c.JSValue) !c.JSValue {
    const Adapter = struct { fn invoke(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue { var scope: Scope = .{ .engine = engine }; return v.owned.finishValue(&scope, dispatch(&scope, receiver, args, roots)); } };
    const roots=&[_]c.JSValue{c.JS_NewInt32(s.engine.context,@intFromEnum(kind)),owner,context};
    return s.own(if(kind==.trailing_ignore or kind==.trailing_check) try v.f.createMethod(s.engine,if(kind==.trailing_ignore) "regex" else "checkRegex",2,Adapter.invoke,roots) else try v.f.createArrow(s.engine,"",callbackLength(kind),Adapter.invoke,roots));
}
pub fn init(s: *Scope, context: c.JSValue) !void {
    const list = try s.array();
    for (steps, 0..) |step, i| {
        const tuple = try s.array();
        try s.index(tuple, 0, if (step.direct) c.pi_js_null() else try v.literal(s, step.pattern, if (step.global) "g" else ""));
        try s.index(tuple, 1, try callback(s, step.kind, c.pi_js_undefined(), context));
        if (step.required) |required| try s.index(tuple, 2, try s.text(required));
        try s.index(list, @intCast(i), tuple);
    }
    try s.put(context, "replacers", list);
    try s.put(context, "regexLiteralSpecial", try v.literal(s, "[.*+?()[\\]{}^$|\\\\/]", ""));
    try s.put(context, "innerSlash", try v.literal(s, "\\/(?!$)", ""));
    try s.put(context, "replaceStar", try v.literal(s, "\\\\\\*", "g"));
    try s.put(context, "replaceTrailing", try v.literal(s, "(^|\\\\\\/)?\\uE000$", ""));
    try s.put(context, "restorePlaceholder", try s.construct(try s.global("RegExp"), &.{try s.text("\x00(\\d+)\x00"),try s.text("g")}));
    const trailing=try s.object();
    try s.put(trailing, "regex", try callback(s, .trailing_ignore, c.pi_js_undefined(), context));
    try s.put(trailing, "checkRegex", try callback(s, .trailing_check, c.pi_js_undefined(), context));
    try s.put(context,"trailingReplacers",trailing);
    const classes = try s.object();
    const names = .{ "alnum","alpha","blank","cntrl","digit","graph","lower","print","punct","space","upper","xdigit" };
    const bodies = .{ "0-9A-Za-z","A-Za-z"," \\t","\\x00-\\x1f\\x7f","0-9","!-.0-~","a-z"," -.0-~","!-.:-@\\[-`{-~"," \\t\\n\\r","A-Z","0-9A-Fa-f" };
    inline for (names, bodies) |name, body| try s.put(classes, name, try s.text(body));
    try s.put(context, "posixClasses", classes);
}
fn same(s: *Scope, value: c.JSValue, text: []const u8) !bool { return v.eq(s,value,text); }
fn slice(s: *Scope, value: c.JSValue, start: usize, end: usize) !c.JSValue { return s.invoke(value,"slice",&.{v.num(s,start),v.num(s,end)}); }
fn escapeMember(s: *Scope, char: c.JSValue) !c.JSValue {
    const found = try s.invoke(try s.text("\\]^-["),"indexOf",&.{char});
    return if (try s.compare(.less,found,v.num(s,0))) char else try s.concat(try s.text("\\"),char);
}
fn classSource(s: *Scope, negated: bool, body: c.JSValue) !c.JSValue {
    if (negated) return s.concat(try s.concat(try s.text("[^\\/"),try v.string(s,body)),try s.text("]"));
    const source = try s.concat(try s.concat(try s.text("["),try v.string(s,body)),try s.text("]"));
    const expression = try s.construct(try s.global("RegExp"),&.{source});
    return if (try v.testRegex(s,expression,try s.text("/"))) s.concat(try s.text("(?!\\/)"),source) else source;
}
const Bracket = struct { end: usize, source: c.JSValue };
fn scanBracket(s: *Scope, pattern: c.JSValue, start: usize, context: c.JSValue) !?Bracket {
    const length = try v.len(s,pattern); var i = start + 1; var negated = false;
    const lead = try v.at(s,pattern,i);
    if (try same(s,lead,"!") or try same(s,lead,"^")) { negated = true; i += 1; }
    var body = try s.text(""); var previous = try s.text(""); var count: usize = 0;
    while (true) {
        count +|= 1; try s.check(count); const char = try v.at(s,pattern,i);
        if (c.JS_IsUndefined(char)) return null;
        if (try same(s,char,"\\")) {
            const escaped = try v.at(s,pattern,i+1); if (c.JS_IsUndefined(escaped)) return null;
            body = try s.concat(body,try escapeMember(s,escaped)); previous = escaped; i += 1;
        } else if (try same(s,char,"-") and s.truthy(previous) and try s.compare(.less,v.num(s,i+1),length) and !try same(s,try v.at(s,pattern,i+1),"]")) {
            i += 1; var to = try v.at(s,pattern,i); if (try same(s,to,"\\")) { i += 1; to = try v.at(s,pattern,i); }
            if (try s.compare(.less_equal,previous,to)) body = try s.concat(body,try s.concat(try s.text("-"),try v.string(s,try escapeMember(s,to))));
            previous = try s.text("");
        } else if (try same(s,char,"[") and try same(s,try v.at(s,pattern,i+1),":")) {
            const name_start = i+2; var end = name_start;
            while (try s.compare(.less,v.num(s,end),length) and !try same(s,try v.at(s,pattern,end),"]")) { count +|= 1; try s.check(count); end += 1; }
            if (s.equal(v.num(s,end),length)) return null;
            if (end > name_start and try same(s,try v.at(s,pattern,end-1),":")) {
                const expanded = try s.getKey(try s.get(context,"posixClasses"),try slice(s,pattern,name_start,end-1));
                if (c.JS_IsUndefined(expanded)) return null;
                body = try s.concat(body,expanded); previous = try s.text(""); i = end;
            } else { body = try s.concat(body,try escapeMember(s,try s.text("["))); previous = try s.text("["); i = name_start-2; }
        } else { body = try s.concat(body,try escapeMember(s,char)); previous = char; }
        i += 1;
        if (try same(s,try v.at(s,pattern,i),"]")) return .{.end=i,.source=try classSource(s,negated,body)};
    }
}
fn hold(s: *Scope, sources: c.JSValue, source: c.JSValue) !c.JSValue {
    const position = try s.binary(.subtract,try s.invoke(sources,"push",&.{source}),v.num(s,1));
    return s.concat(try s.concat(try s.text("\x00"),try v.string(s,position)),try s.text("\x00"));
}
const Extracted = struct { source: c.JSValue, sources: c.JSValue };
fn extract(s: *Scope, pattern: c.JSValue, context: c.JSValue) !Extracted {
    const sources = try s.array(); const length = try v.len(s,pattern); var out = try s.text(""); var i: usize = 0; var count: usize = 0;
    while (try s.compare(.less,v.num(s,i),length)) {
        count +|= 1; try s.check(count); const char = try v.at(s,pattern,i);
        if (try same(s,char,"\\")) {
            const escaped = try v.at(s,pattern,i+1);
            if (try same(s,escaped,"*") or try same(s,escaped,"[") or try same(s,escaped," ") or try same(s,escaped,"\\")) out = try s.concat(out,try slice(s,pattern,i,i+2))
            else out = try s.concat(out,try hold(s,sources,if (try v.regex(s,context,"regexLiteralSpecial",escaped)) try s.concat(try s.text("\\"),escaped) else escaped));
            i += 2;
        } else if (try same(s,char,"\x00")) { out = try s.concat(out,try hold(s,sources,try s.text("[\x00]"))); i += 1;
        } else if (try same(s,char,"[")) {
            if (try scanBracket(s,pattern,i,context)) |scanned| { out = try s.concat(out,try hold(s,sources,scanned.source)); i = scanned.end+1;
            } else { out = try s.concat(out,try hold(s,sources,try s.text("[]"))); return .{.source=out,.sources=sources}; }
        } else { out = try s.concat(out,char); i += 1; }
    }
    return .{.source=out,.sources=sources};
}
pub fn prefix(s: *Scope, pattern: c.JSValue, context: c.JSValue) !c.JSValue {
    const extracted = try extract(s,pattern,context);
    const reducers = try s.get(context,"replacers"); const reduce = try s.get(reducers,"reduce");
    const replaced = try s.call(reduce,reducers,&.{try callback(s,.reduce,pattern,context),extracted.source});
    if (!s.truthy(try v.len(s,extracted.sources))) return replaced;
    const replace = try s.get(replaced,"replace");
    return s.call(replace,replaced,&.{try s.get(context,"restorePlaceholder"),try callback(s,.restore,extracted.sources,context)});
}
fn cleanSlashes(s: *Scope, text: c.JSValue) !c.JSValue {
    const length = try v.len(s,text); const method=try s.get(text,"slice"); const end = try s.binary(.subtract,length,try s.binary(.remainder,length,v.num(s,2)));
    return s.call(method,text,&.{v.num(s,0),end});
}
fn dispatch(s: *Scope, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var raw: i32 = 0; const generation = s.engine.native_allocation_generation;
    try s.status(c.JS_ToInt32(s.engine.context,&raw,roots[0]),generation);
    const kind: Kind = @enumFromInt(raw); const owner = roots[1]; const context = roots[2]; const first = v.arg(args,0);
    const result = switch (kind) {
        .empty => try s.text(""), .any => try s.text("[^/]"), .leading_slash => try s.text("^"), .slash => try s.text("\\/"), .leading_globstar => try s.text("^(?:.*\\/)?"), .unescape => try s.text("\\"),
        .trim_spaces => blk: { const one=v.arg(args,1); const two=v.arg(args,2); const at=try s.invoke(two,"indexOf",&.{try s.text("\\")}); break :blk try s.concat(one,try s.text(if(s.equal(at,v.num(s,0))) " " else "")); },
        .quoted_spaces => try s.concat(try cleanSlashes(s,v.arg(args,1)),try s.text(" ")),
        .escape_meta => try s.concat(try s.text("\\"),try v.string(s,first)),
        .anchor => blk: { if(!s.truthy(first) or try same(s,try v.at(s,first,0),"^")) break :blk first; break :blk try s.concat(try s.text(if(!try v.regex(s,context,"innerSlash",v.arg(args,1))) "(?:^|\\/)" else "^"),first); },
        .globstar => blk: {
            const at=v.arg(args,1); const text=v.arg(args,2); const first_offset=try s.binary(.add,at,v.num(s,6));
            if(!try s.compare(.less,first_offset,try v.len(s,text)))break :blk try s.text("\\/.+");
            const method=try s.get(text,"slice"); const suffix=try s.call(method,text,&.{try s.binary(.add,at,v.num(s,6))});
            break :blk try s.text(if(try same(s,suffix,"\\/")) "(?:\\/[^\\/]+)+" else "(?:\\/[^\\/]+)*");
        },
        .intermediate => blk: { const text=v.arg(args,2); const replace=try s.get(text,"replace"); const unescaped=try s.call(replace,text,&.{try s.get(context,"replaceStar"),try s.text("[^\\/]*")}); break :blk try s.concat(v.arg(args,1),unescaped); },
        .trailing => blk: { const slashes=v.arg(args,2); const half=try s.binary(.divide,try v.len(s,slashes),v.num(s,2)); const even=s.equal(try s.binary(.remainder,half,v.num(s,2)),v.num(s,0)); break :blk if(even) try s.concat(try s.concat(v.arg(args,1),slashes),try s.text("\xee\x80\x80")) else first; },
        .literal_bracket => try s.concat(try s.concat(try s.concat(try s.text("\\["),try v.string(s,v.arg(args,1))),try v.string(s,try cleanSlashes(s,v.arg(args,2)))),try v.string(s,v.arg(args,3))),
        .ending => blk: { const last=try s.getKey(first,try s.binary(.subtract,try v.len(s,first),v.num(s,1))); if(!s.truthy(last) or try same(s,last,"\xee\x80\x80")) break :blk first; break :blk if(try same(s,last,"/")) try s.concat(try v.string(s,first),try s.text("$")) else try s.concat(try v.string(s,first),try s.text("(?=$|\\/$)")); },
        .trailing_ignore,.trailing_check => blk: { const captured=v.arg(args,1); const chosen=if(s.truthy(captured)) try s.concat(try v.string(s,captured),try s.text(if(kind==.trailing_ignore) "[^/]+" else "[^/]*")) else try s.text("[^/]*"); break :blk try s.concat(try v.string(s,chosen),try s.text("(?=$|\\/$)")); },
        .restore => try s.getKey(owner,v.arg(args,1)),
        .reduce => blk: {
            const tuple=try v.three(s,v.arg(args,1)); const matcher=tuple[0]; const replacer=tuple[1]; const required=tuple[2];
            if(c.JS_IsNull(matcher)) break :blk try s.call(replacer,c.pi_js_undefined(),&.{first,owner});
            if(!c.JS_IsUndefined(required) and try s.compare(.less,try s.invoke(first,"indexOf",&.{required}),v.num(s,0))) break :blk first;
            if(!try v.testRegex(s,matcher,first)) break :blk first;
            const replace=try s.get(first,"replace"); const bound=try s.invoke(replacer,"bind",&.{owner}); break :blk try s.call(replace,first,&.{matcher,bound});
        },
        .last_wildcard => blk: { if(s.truthy(try s.get(first,"wildcard"))) try s.set(owner,"lastWildcard",v.arg(args,1)); break :blk c.pi_js_undefined(); },
        .emit_run => blk: {
            const wildcard=s.truthy(try s.get(first,"wildcard")); const state=try s.get(owner,"owner"); const before=try s.get(state,"out");
            const piece=if(!wildcard) try s.get(first,"single") else if(s.equal(v.arg(args,1),try s.get(owner,"lastWildcard"))) try s.text("[^\\/]*") else branch: {
                const run=try s.get(state,"run"); const next=try s.getKey(run,try s.binary(.add,v.arg(args,1),v.num(s,1))); break :branch try s.concat(try s.concat(try s.text("(?:(?!"),try v.string(s,try s.get(next,"single"))),try s.text(")[^\\/])*"));
            };
            try s.set(state,"out",try s.concat(before,piece)); break :blk c.pi_js_undefined();
        },
        .token => blk: {
            if(c.JS_IsUndefined(try s.get(first,"boundary"))) { _=try s.invoke(try s.get(owner,"run"),"push",&.{first}); break :blk c.pi_js_undefined(); }
            try flush(s,owner,context); const before=try s.get(owner,"out"); try s.set(owner,"out",try s.concat(before,try s.get(first,"boundary"))); break :blk c.pi_js_undefined();
        },
    };
    return v.dup(s,result);
}
fn flush(s: *Scope, owner: c.JSValue, context: c.JSValue) !void {
    const frame=try s.object(); try s.put(frame,"owner",owner); try s.put(frame,"lastWildcard",c.pi_js_undefined());
    const run=try s.get(owner,"run"); const scan=try s.get(run,"forEach"); _=try s.call(scan,run,&.{try callback(s,.last_wildcard,frame,context)});
    const current=try s.get(owner,"run"); const emit=try s.get(current,"forEach"); _=try s.call(emit,current,&.{try callback(s,.emit_run,frame,context)});
    try s.set(owner,"run",try s.array());
}
pub fn pin(s: *Scope, source: c.JSValue, context: c.JSValue) !c.JSValue {
    if(try s.compare(.less,try s.invoke(source,"indexOf",&.{try s.text("[^\\/]*")}),v.num(s,0))) return source;
    const tokens=try s.array(); const length=try v.len(s,source); var i:usize=0; var count:usize=0;
    const Token=enum{wildcard,single_char,single_slice,boundary_char,boundary_slice};
    while(try s.compare(.less,v.num(s,i),length)) {
        count +|= 1; try s.check(count); const char=try v.at(s,source,i); const begin=i; var kind:Token=.single_char;
        if(s.truthy(try s.invoke(source,"startsWith",&.{try s.text("[^\\/]*"),v.num(s,i)}))) { kind=.wildcard; i+=6;
        } else if(try same(s,char,"[")) { var end=i+1; if(try same(s,try v.at(s,source,end),"^"))end+=1; if(try same(s,try v.at(s,source,end),"]"))end+=1;
            while(try s.compare(.less,v.num(s,end),length) and !try same(s,try v.at(s,source,end),"]")) { count +|= 1; try s.check(count); end+=if(try same(s,try v.at(s,source,end),"\\")) @as(usize,2) else 1; }
            end+=1; kind=.single_slice; i=end;
        } else if(try same(s,char,"\\")) { kind=.single_slice; i+=2;
        } else if(try same(s,char,"(")) { var depth:isize=0; var end=i;
            while(true) { count +|= 1; try s.check(count); const at=try v.at(s,source,end); if(try same(s,at,"\\"))end+=1 else if(try same(s,at,"("))depth+=1 else if(try same(s,at,")"))depth-=1;
                end+=1; if(!try s.compare(.less,v.num(s,end),length) or depth<=0)break;
            }
            const quantifiers=try s.text("*+?"); const index_of=try s.get(quantifiers,"indexOf");
            if(try s.compare(.greater_equal,try s.call(index_of,quantifiers,&.{try v.at(s,source,end)}),v.num(s,0)))end+=1;
            kind=.boundary_slice; i=end;
        } else if(try same(s,char,"^") or try same(s,char,"$")) { kind=.boundary_char; i+=1;
        } else { i+=1; }
        const push=try s.get(tokens,"push"); const token=try s.object();
        const value=switch(kind){.wildcard=>c.pi_js_bool(s.engine.context,1),.single_char,.boundary_char=>char,.single_slice,.boundary_slice=>try slice(s,source,begin,i)};
        try s.put(token,switch(kind){.wildcard=>"wildcard",.single_char,.single_slice=>"single",.boundary_char,.boundary_slice=>"boundary"},value);
        _=try s.call(push,tokens,&.{token});
    }
    const owner=try s.object(); try s.put(owner,"out",try s.text("")); try s.put(owner,"run",try s.array());
    const each=try s.get(tokens,"forEach"); _=try s.call(each,tokens,&.{try callback(s,.token,owner,context)}); try flush(s,owner,context);
    return s.get(owner,"out");
}
