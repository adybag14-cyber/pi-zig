//! Native Source fuzzyMatch/fuzzyFilter over JavaScript UTF16 strings and items.
const std = @import("std");
const engine_mod = @import("engine.zig");
const js = @import("native_js_values.zig");
const utf16 = @import("native_utf16.zig");
const input = @import("../tui/utf16_input.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
const Match = struct { matches: bool, score: f64 = 0 };
fn fail(engine: *Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native fuzzy match: %s", @as([*:0]const u8, @errorName(err)));
}
fn lowerUnits(engine: *Engine, value: c.JSValue) ![]u16 {
    const lower = try js.invoke(engine, value, "toLowerCase", &.{});
    defer engine.freeValue(lower);
    return utf16.unitsAlloc(engine, lower);
}
fn budget(engine: *Engine, steps: usize) !void {
    if (engine.cancelled.load(.acquire) or (steps % 256 == 0 and block: {
        engine.interrupts +|= 1;
        break :block engine.interrupts > engine.options.interrupt_budget;
    })) {
        _ = try engine.checked(c.JS_ThrowInternalError(engine.context, "interrupted"));
        unreachable;
    }
}
fn boundary(unit: u16) bool {
    return input.State.whitespace(unit) or unit == '-' or unit == '_' or unit == '.' or unit == '/' or unit == ':';
}
fn matchQuery(engine: *Engine, query: []const u16, text: []const u16) !Match {
    if (query.len == 0) return .{ .matches = true };
    if (query.len > text.len) return .{ .matches = false };
    var score: f64 = 0;
    var last: ?usize = null;
    var consecutive: usize = 0;
    for (query, 0..) |unit, step| {
        try budget(engine, step + 1);
        const index = std.mem.indexOfScalarPos(u16, text, if (last) |position| position + 1 else 0, unit) orelse return .{ .matches = false };
        if ((last == null and index == 0) or (last != null and last.? + 1 == index)) {
            consecutive += 1;
            score -= @as(f64, @floatFromInt(consecutive)) * 5;
        } else {
            consecutive = 0;
            if (last) |position| score += @as(f64, @floatFromInt(index - position - 1)) * 2;
        }
        if (index == 0 or boundary(text[index - 1])) score -= 10;
        score += @as(f64, @floatFromInt(index)) * 0.1;
        last = index;
    }
    if (std.mem.eql(u16, query, text)) score -= 100;
    return .{ .matches = true, .score = score };
}
fn letter(unit: u16) bool {
    return unit >= 'a' and unit <= 'z';
}
fn digit(unit: u16) bool {
    return unit >= '0' and unit <= '9';
}
fn matching(engine: *Engine, query_value: c.JSValue, text_value: c.JSValue) !Match {
    const query = try lowerUnits(engine, query_value);
    defer engine.gpa.free(query);
    const text = try lowerUnits(engine, text_value);
    defer engine.gpa.free(text);
    const primary = try matchQuery(engine, query, text);
    if (primary.matches or query.len < 2) return primary;
    const letters_first = letter(query[0]);
    if (!letters_first and !digit(query[0])) return primary;
    var split: usize = 0;
    while (split < query.len and (if (letters_first) letter(query[split]) else digit(query[split]))) : (split += 1) {}
    if (split == 0 or split == query.len) return primary;
    for (query[split..]) |unit| if (!(if (letters_first) digit(unit) else letter(unit))) return primary;
    const swapped = try engine.gpa.alloc(u16, query.len);
    defer engine.gpa.free(swapped);
    @memcpy(swapped[0 .. query.len - split], query[split..]);
    @memcpy(swapped[query.len - split ..], query[0..split]);
    const match = try matchQuery(engine, swapped, text);
    return if (match.matches) .{ .matches = true, .score = match.score + 5 } else primary;
}
fn resultValue(engine: *Engine, match: Match) !c.JSValue {
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    try js.define(engine, result, "matches", c.pi_js_bool(engine.context, @intFromBool(match.matches)));
    try js.define(engine, result, "score", c.JS_NewFloat64(engine.context, match.score));
    return result;
}
const Entry = struct { item: c.JSValue, score: f64, index: usize };
fn less(_: void, a: Entry, b: Entry) bool {
    return a.score < b.score or (a.score == b.score and a.index < b.index);
}
pub fn filter(engine: *Engine, items: c.JSValue, query: c.JSValue, get_text: c.JSValue, iterator_symbol: c.JSValue) !c.JSValue {
    const first_trim = try js.invoke(engine, query, "trim", &.{});
    defer engine.freeValue(first_trim);
    if (c.JS_ToBool(engine.context, first_trim) == 0) return c.JS_DupValue(engine.context, items);
    const second_trim = try js.invoke(engine, query, "trim", &.{});
    defer engine.freeValue(second_trim);
    const units = try utf16.unitsAlloc(engine, second_trim);
    defer engine.gpa.free(units);
    var tokens: std.ArrayList(c.JSValue) = .empty;
    defer {
        for (tokens.items) |token| engine.freeValue(token);
        tokens.deinit(engine.gpa);
    }
    var start: usize = 0;
    for (0..units.len + 1) |at| {
        if (at == units.len or input.State.whitespace(units[at]) or units[at] == '/') {
            if (at > start) {
                const token = try utf16.string(engine, units[start..at]);
                errdefer engine.freeValue(token);
                try tokens.append(engine.gpa, token);
            }
            start = at + 1;
        }
    }
    if (tokens.items.len == 0) return c.JS_DupValue(engine.context, items);
    var results: std.ArrayList(Entry) = .empty;
    defer {
        for (results.items) |entry| engine.freeValue(entry.item);
        results.deinit(engine.gpa);
    }
    var iterator = try js.Iterator.init(engine, items, iterator_symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    var index: usize = 0;
    while (try iterator.next()) |item| {
        defer engine.freeValue(item);
        const text = try js.call(engine, get_text, c.pi_js_undefined(), &.{item});
        defer engine.freeValue(text);
        var total: f64 = 0;
        var all = true;
        for (tokens.items) |token| {
            const match = try matching(engine, token, text);
            if (!match.matches) {
                all = false;
                break;
            }
            total += match.score;
        }
        if (all) {
            const owned = c.JS_DupValue(engine.context, item);
            errdefer engine.freeValue(owned);
            try results.append(engine.gpa, .{ .item = owned, .score = total, .index = index });
        }
        index += 1;
    }
    std.mem.sort(Entry, results.items, {}, less);
    const result = try js.array(engine);
    errdefer engine.freeValue(result);
    for (results.items) |entry| try js.push(engine, result, entry.item);
    return result;
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const args: []const c.JSValue = if (argc == 0) &.{} else argv[0..@intCast(argc)];
    return dispatch(engine, args, magic, data[0]) catch |err| fail(engine, err);
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn dispatch(engine: *Engine, args: []const c.JSValue, magic: c_int, symbol: c.JSValue) !c.JSValue {
    if (magic == 0) return resultValue(engine, try matching(engine, arg(args, 0), arg(args, 1)));
    return filter(engine, arg(args, 0), arg(args, 1), arg(args, 2), symbol);
}
pub fn install(engine: *Engine, exports: c.JSValue) !void {
    const symbol_type = try js.global(engine, "Symbol");
    defer engine.freeValue(symbol_type);
    const symbol = try js.get(engine, symbol_type, "iterator");
    defer engine.freeValue(symbol);
    inline for (.{ .{ "fuzzyMatch", 2, 0 }, .{ "fuzzyFilter", 3, 1 } }) |item| {
        var data = [_]c.JSValue{symbol};
        try js.define(engine, exports, item[0], try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, item[0], item[1], item[2], 1, &data)));
    }
}
test "Source6fb public SelectList fuzzy helpers match original UTF16 scores filters references and iterator cleanup" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const fixture = @embedFile("fixtures/fuzzy-original-6fb.json");
    try js.define(engine, root, "fuzzyFixture", try engine.checked(c.JS_ParseJSON(engine.context, fixture.ptr, fixture.len, "fuzzy-original-6fb.json")));
    const result = engine.evalModule(
        \\import{fuzzyMatch,fuzzyFilter}from'pi-tui';if(fuzzyMatch.length!==2||fuzzyFilter.length!==3)throw Error('fuzzy arity');for(const[index,item]of fuzzyFixture.pairs.entries()){const actual=fuzzyMatch(item.query,item.text);if(JSON.stringify(actual)!==JSON.stringify(item.result))throw Error(JSON.stringify({index,actual,expected:item}));}for(const[index,item]of fuzzyFixture.filters.entries()){const calls=[],result=fuzzyFilter(item.items,item.query,function(value){calls.push({id:value.id,receiver:this===undefined});return value.label}),actual={ids:result.map(i=>i.id),same:result===item.items,calls};if(JSON.stringify(actual)!==JSON.stringify({ids:item.ids,same:item.same,calls:item.calls}))throw Error(JSON.stringify({index,actual,expected:item}));}for(const[index,item]of fuzzyFixture.structural.entries()){let actual;try{actual=new Function('fuzzyMatch','fuzzyFilter','"use strict";'+item.script)(fuzzyMatch,fuzzyFilter)}catch(e){if(e.name===item.errorName&&e.message===item.errorMessage)continue;throw e}if(item.errorName||JSON.stringify(actual)!==JSON.stringify(item.result))throw Error(JSON.stringify({index,actual,expected:item}));}
    , "fuzzy-replay.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Fuzzy replay: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
