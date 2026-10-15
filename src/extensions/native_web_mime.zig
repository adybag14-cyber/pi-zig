//! Bundled Undici 7.21 MIME parsing, serialization and header extraction.
//! UTF16 scanning preserves ByteString Latin1 and rejects forbidden units.
const std = @import("std");
const em = @import("engine.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const utf = @import("native_utf16.zig");
const web = @import("native_headers_webidl.zig");
const c = em.c;
fn whitespace(unit: u16) bool {
    return unit == 9 or unit == 10 or unit == 13 or unit == 32;
}
fn token(unit: u16) bool {
    return (unit >= 'a' and unit <= 'z') or (unit >= 'A' and unit <= 'Z') or (unit >= '0' and unit <= '9') or switch (unit) {
        '-', '!', '#', '$', '%', '&', '\'', '*', '+', '.', '^', '_', '|', '~' => true,
        else => false,
    };
}
fn tokens(units: []const u16) bool {
    if (units.len == 0) return false;
    for (units) |unit| if (!token(unit)) return false;
    return true;
}
fn trimmed(units: []const u16, leading: bool, trailing: bool) []const u16 {
    var first: usize = 0;
    var last = units.len;
    if (leading) while (first < last and whitespace(units[first])) : (first += 1) {};
    if (trailing) while (last > first and whitespace(units[last - 1])) : (last -= 1) {};
    return units[first..last];
}
fn text(scope: *Scope, units: []const u16) !c.JSValue {
    return scope.own(try utf.string(scope.engine, units));
}
fn lower(scope: *Scope, units: []const u16) !c.JSValue {
    return scope.invoke(try text(scope, units), "toLowerCase", &.{});
}
fn quoted(scope: *Scope, units: []const u16, position: *usize) !c.JSValue {
    var value: std.ArrayList(u16) = .empty;
    defer value.deinit(scope.engine.gpa);
    position.* += 1;
    while (position.* < units.len) {
        const unit = units[position.*];
        position.* += 1;
        if (unit == '"') break;
        if (unit == '\\' and position.* < units.len) {
            try value.append(scope.engine.gpa, units[position.*]);
            position.* += 1;
        } else try value.append(scope.engine.gpa, unit);
    }
    return text(scope, value.items);
}
/// Null represents Source's internal "failure" marker, never a MIME record.
pub fn parse(scope: *Scope, input: c.JSValue) !?c.JSValue {
    const allocated = try utf.unitsAlloc(scope.engine, input);
    defer scope.engine.gpa.free(allocated);
    const units = trimmed(allocated, true, true);
    var position: usize = 0;
    while (position < units.len and units[position] != '/') : (position += 1) {}
    const type_units = units[0..position];
    if (!tokens(type_units) or position == units.len) return null;
    position += 1;
    const start = position;
    while (position < units.len and units[position] != ';') : (position += 1) {}
    const subtype_units = trimmed(units[start..position], false, true);
    if (!tokens(subtype_units)) return null;
    const record = try scope.object();
    const type_text = try lower(scope, type_units);
    const subtype = try lower(scope, subtype_units);
    try scope.set(record, "type", type_text);
    try scope.set(record, "subtype", subtype);
    try scope.set(record, "essence", try scope.concat(try scope.concat(type_text, try scope.text("/")), subtype));
    const parameters = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.global("Map"), 0, null)));
    try scope.set(record, "parameters", parameters);
    while (position < units.len) {
        position += 1;
        while (position < units.len and whitespace(units[position])) : (position += 1) {}
        const name_start = position;
        while (position < units.len and units[position] != ';' and units[position] != '=') : (position += 1) {}
        const name_units = units[name_start..position];
        const name = try lower(scope, name_units);
        if (position < units.len) {
            if (units[position] == ';') continue;
            position += 1;
        }
        if (position >= units.len) break;
        var value: c.JSValue = undefined;
        if (units[position] == '"') {
            value = try quoted(scope, units, &position);
            while (position < units.len and units[position] != ';') : (position += 1) {}
        } else {
            const value_start = position;
            while (position < units.len and units[position] != ';') : (position += 1) {}
            const value_units = trimmed(units[value_start..position], false, true);
            if (value_units.len == 0) continue;
            value = try text(scope, value_units);
        }
        if (!tokens(name_units)) continue;
        const value_units = try utf.unitsAlloc(scope.engine, value);
        defer scope.engine.gpa.free(value_units);
        var valid = true;
        for (value_units) |unit| if (!(unit == 9 or (unit >= 32 and unit <= 126) or (unit >= 128 and unit <= 255))) {
            valid = false;
            break;
        };
        if (valid and !scope.truthy(try scope.invoke(parameters, "has", &.{name}))) _ = try scope.invoke(parameters, "set", &.{ name, value });
    }
    return record;
}
pub fn serialize(scope: *Scope, record: c.JSValue) !c.JSValue {
    var output = try scope.get(record, "essence");
    const iterator = try scope.invoke(try scope.get(record, "parameters"), "entries", &.{});
    while (true) {
        const step = try scope.invoke(iterator, "next", &.{});
        if (scope.truthy(try scope.get(step, "done"))) break;
        const pair = try scope.get(step, "value");
        const name = try web.index(scope, pair, 0);
        var value = try web.index(scope, pair, 1);
        const units = try utf.unitsAlloc(scope.engine, value);
        defer scope.engine.gpa.free(units);
        if (!tokens(units)) {
            var escaped: std.ArrayList(u16) = .empty;
            defer escaped.deinit(scope.engine.gpa);
            try escaped.append(scope.engine.gpa, '"');
            for (units) |unit| {
                if (unit == '\\' or unit == '"') try escaped.append(scope.engine.gpa, '\\');
                try escaped.append(scope.engine.gpa, unit);
            }
            try escaped.append(scope.engine.gpa, '"');
            value = try text(scope, escaped.items);
        }
        output = try scope.concat(try scope.concat(try scope.concat(try scope.concat(output, try scope.text(";")), name), try scope.text("=")), value);
    }
    return output;
}
/// Input is Headers.get("content-type"), already a combined ByteString.
pub fn extract(scope: *Scope, input: c.JSValue) !?c.JSValue {
    if (c.JS_IsNull(input) or c.JS_IsUndefined(input)) return null;
    const units = try utf.unitsAlloc(scope.engine, input);
    defer scope.engine.gpa.free(units);
    var position: usize = 0;
    var charset = c.pi_js_null();
    var essence = c.pi_js_null();
    var result: ?c.JSValue = null;
    while (position < units.len) {
        const start = position;
        while (position < units.len) {
            if (units[position] == ',') break;
            if (units[position] == '"') {
                _ = try quoted(scope, units, &position);
            } else position += 1;
        }
        var value_units = units[start..position];
        while (value_units.len > 0 and (value_units[0] == 9 or value_units[0] == 32)) value_units = value_units[1..];
        while (value_units.len > 0 and (value_units[value_units.len - 1] == 9 or value_units[value_units.len - 1] == 32)) value_units = value_units[0 .. value_units.len - 1];
        if (position < units.len) position += 1;
        const parsed = (try parse(scope, try text(scope, value_units))) orelse continue;
        const next_essence = try scope.get(parsed, "essence");
        if (scope.equal(next_essence, try scope.text("*/*"))) continue;
        result = parsed;
        const params = try scope.get(parsed, "parameters");
        const key = try scope.text("charset");
        const has_charset = scope.truthy(try scope.invoke(params, "has", &.{key}));
        if (!scope.equal(next_essence, essence)) {
            charset = if (has_charset) try scope.invoke(params, "get", &.{key}) else c.pi_js_null();
            essence = next_essence;
        } else if (!has_charset and !c.JS_IsNull(charset)) _ = try scope.invoke(params, "set", &.{ key, charset });
    }
    return result;
}
