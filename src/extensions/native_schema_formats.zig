//! TypeBox 1.3.27 format behavior through native Zig and QuickJS's C regexp API.
//! Source regex data is generated and hash-bound; see TYPEBOX_LICENSE.txt.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const generated = @import("typebox_format_patterns.zig");
const Engine = engine_mod.Engine;
const c = engine_mod.c;
pub const Kind = enum(c_int) { date_time, date, duration, email, hostname, idn_email, idn_hostname, ipv4, ipv6, iri_reference, iri, json_pointer_uri_fragment, json_pointer, regex, relative_json_pointer, time, uri_reference, uri_template, uri, url, uuid };
pub const names = [_][]const u8{ "date-time", "date", "duration", "email", "hostname", "idn-email", "idn-hostname", "ipv4", "ipv6", "iri-reference", "iri", "json-pointer-uri-fragment", "json-pointer", "regex", "relative-json-pointer", "time", "uri-reference", "uri-template", "uri", "url", "uuid" };
pub const exported = [_][:0]const u8{ "IsDateTime", "IsDate", "IsDuration", "IsEmail", "IsHostname", "IsIdnEmail", "IsIdnHostname", "IsIPv4", "IsIPv6", "IsIriReference", "IsIri", "IsJsonPointerUriFragment", "IsJsonPointer", "IsRegex", "IsRelativeJsonPointer", "IsTime", "IsUriReference", "IsUriTemplate", "IsUri", "IsUrl", "IsUuid" };
pub fn install(engine: *Engine) !void {
    if (engine.native_module_names.contains("typebox/format")) return;
    const exports = try create(engine);
    defer engine.freeValue(exports);
    try engine.registerValueModule("typebox/format", exports);
}
pub fn patterns(engine: *Engine) !c.JSValue {
    const result = try vm.array(engine);
    errdefer engine.freeValue(result);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const constructor = try vm.get(engine, global, "RegExp");
    defer engine.freeValue(constructor);
    for (generated.patterns, 0..) |pattern, index| {
        const expression = try engine.checked(c.JS_NewStringLen(engine.context, pattern.expression.ptr, pattern.expression.len));
        defer engine.freeValue(expression);
        const flags = try engine.checked(c.JS_NewStringLen(engine.context, pattern.flags.ptr, pattern.flags.len));
        defer engine.freeValue(flags);
        var args = [_]c.JSValue{ expression, flags };
        if (c.JS_SetPropertyUint32(engine.context, result, @intCast(index), try engine.checked(c.JS_CallConstructor(engine.context, constructor, 2, &args))) < 0) return error.JavaScriptException;
    }
    inline for (.{ "RE_EUROPEAN_NUMBER", "RE_PERMITTED_CATEGORY" }, 0..) |binding, index| {
        const members: []const []const u8 = if (index == 0) &.{ "RE_ASCII_DIGIT", "RE_EXT_ARABIC_INDIC_DIGIT" } else &.{ "RE_LETTER", "RE_EUROPEAN_SEPARATOR", "RE_COMMON_SEPARATOR", "RE_NUMBER_DECIMAL", "RE_MARK_NONSPACING", "RE_MARK_SPACING_COMBINING", "RE_CONTEXTO_EXCEPTIONS", "RE_PVALID_EXCEPTIONS" };
        var pieces: std.ArrayList([]const u8) = .empty;
        defer pieces.deinit(engine.gpa);
        for (members) |member| for (generated.patterns) |pattern| if (std.mem.eql(u8, pattern.file, "idna/pattern/pattern.mjs") and std.mem.eql(u8, pattern.binding, member)) {
            try pieces.append(engine.gpa, pattern.expression);
            break;
        };
        if (pieces.items.len != members.len) return error.UnboundCompositeFormatPattern;
        const combined = try std.mem.join(engine.gpa, "|", pieces.items);
        defer engine.gpa.free(combined);
        const expression = try engine.checked(c.JS_NewStringLen(engine.context, combined.ptr, combined.len));
        defer engine.freeValue(expression);
        const flags = try engine.checked(c.JS_NewString(engine.context, "u"));
        defer engine.freeValue(flags);
        var args = [_]c.JSValue{ expression, flags };
        if (c.JS_SetPropertyUint32(engine.context, result, @intCast(generated.patterns.len + index), try engine.checked(c.JS_CallConstructor(engine.context, constructor, 2, &args))) < 0) return error.JavaScriptException;
        _ = binding;
    }
    return result;
}
pub const Context = struct {
    engine: *Engine,
    patterns: c.JSValue,
    fn expressionFor(self: Context, file: []const u8, binding: []const u8) !c.JSValue {
        for (generated.patterns, 0..) |pattern, index| if (std.mem.eql(u8, pattern.file, file) and std.mem.eql(u8, pattern.binding, binding)) return self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, self.patterns, @intCast(index)));
        if (std.mem.eql(u8, file, "idna/pattern/pattern.mjs")) inline for (.{ "RE_EUROPEAN_NUMBER", "RE_PERMITTED_CATEGORY" }, 0..) |composite, index| {
            if (std.mem.eql(u8, binding, composite)) return self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, self.patterns, @intCast(generated.patterns.len + index)));
        };
        return error.UnboundTypeBoxFormatPattern;
    }
    fn match(self: Context, file: []const u8, binding: []const u8, value: c.JSValue) !bool {
        const regexp = try self.expressionFor(file, binding);
        defer self.engine.freeValue(regexp);
        const result = try vm.invoke(self.engine, regexp, "test", &.{value});
        defer self.engine.freeValue(result);
        return c.JS_ToBool(self.engine.context, result) != 0;
    }
    fn matchText(self: Context, file: []const u8, binding: []const u8, text: []const u8) !bool {
        const value = try self.string(text);
        defer self.engine.freeValue(value);
        return self.match(file, binding, value);
    }
    fn string(self: Context, text: []const u8) !c.JSValue {
        return self.engine.checked(c.JS_NewStringLen(self.engine.context, text.ptr, text.len));
    }
    fn exec(self: Context, file: []const u8, binding: []const u8, value: c.JSValue) !c.JSValue {
        const regexp = try self.expressionFor(file, binding);
        defer self.engine.freeValue(regexp);
        return vm.invoke(self.engine, regexp, "exec", &.{value});
    }
    fn integer(self: Context, array: c.JSValue, index: u32) !i32 {
        const value = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, array, index));
        defer self.engine.freeValue(value);
        var number: i32 = 0;
        if (!c.JS_IsUndefined(value) and c.JS_ToInt32(self.engine.context, &number, value) < 0) return error.JavaScriptException;
        return number;
    }
    pub fn check(self: Context, kind: Kind, value: c.JSValue, strict_timezone: bool) !bool {
        return switch (kind) {
            .date => self.date(value),
            .time => self.time(value, strict_timezone),
            .date_time => self.dateTime(value),
            .duration => self.match("duration.mjs", "Duration", value),
            .email => self.match("email.mjs", "Email", value),
            .ipv4 => self.match("ipv4.mjs", "IPv4", value),
            .ipv6 => self.match("ipv6.mjs", "IPv6", value),
            .json_pointer_uri_fragment => self.match("json_pointer_uri_fragment.mjs", "JsonPointerUriFragment", value),
            .json_pointer => self.match("json_pointer.mjs", "JsonPointer", value),
            .relative_json_pointer => self.match("relative_json_pointer.mjs", "RelativeJsonPointer", value),
            .uri => self.match("uri.mjs", "Uri", value),
            .uri_reference => self.match("uri_reference.mjs", "UriReference", value),
            .uri_template => self.match("uri_template.mjs", "UriTemplate", value),
            .uuid => self.match("uuid.mjs", "Uuid", value),
            .idn_email => blk: {
                const form = try self.string("NFC");
                defer self.engine.freeValue(form);
                const normalized = try vm.invoke(self.engine, value, "normalize", &.{form});
                defer self.engine.freeValue(normalized);
                break :blk self.match("idn_email.mjs", "IdnEmail", normalized);
            },
            .hostname, .idn_hostname => self.hostname(value, kind == .idn_hostname),
            .url => self.url(value, null),
            .iri => self.iri(value),
            .iri_reference => self.iriReference(value),
            .regex => self.regex(value),
        };
    }
    fn date(self: Context, value: c.JSValue) !bool {
        const found = try self.exec("date.mjs", "DATE", value);
        defer self.engine.freeValue(found);
        if (c.JS_IsNull(found)) return false;
        const year = try self.integer(found, 1);
        const month = try self.integer(found, 2);
        const day = try self.integer(found, 3);
        const days = [_]i32{ 0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        if (month < 1 or month > 12 or day < 1) return false;
        return day <= if (month == 2 and @mod(year, 4) == 0 and (@mod(year, 100) != 0 or @mod(year, 400) == 0)) @as(i32, 29) else days[@intCast(month)];
    }
    fn time(self: Context, value: c.JSValue, strict: bool) !bool {
        const found = try self.exec("time.mjs", "TIME", value);
        defer self.engine.freeValue(found);
        if (c.JS_IsNull(found)) return false;
        const zone = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, found, 4));
        defer self.engine.freeValue(zone);
        const sign_value = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, found, 5));
        defer self.engine.freeValue(sign_value);
        if (strict and c.JS_IsUndefined(zone) and c.JS_IsUndefined(sign_value)) return false;
        const hr = try self.integer(found, 1);
        const minute = try self.integer(found, 2);
        const second = try self.integer(found, 3);
        if (hr > 23 or minute > 59 or second > 60) return false;
        const zone_hr = try self.integer(found, 6);
        const zone_minute = try self.integer(found, 7);
        if (!c.JS_IsUndefined(sign_value) and (zone_hr > 23 or zone_minute > 59)) return false;
        if (second < 60) return true;
        const sign = if (!c.JS_IsUndefined(sign_value)) blk: {
            const label = try self.engine.toString(sign_value);
            defer self.engine.gpa.free(label);
            break :blk if (std.mem.eql(u8, label, "-")) @as(i32, -1) else @as(i32, 1);
        } else @as(i32, 1);
        return @mod(hr * 60 + minute - sign * (zone_hr * 60 + zone_minute), 1440) == 1439;
    }
    fn dateTime(self: Context, value: c.JSValue) !bool {
        const global = c.JS_GetGlobalObject(self.engine.context);
        defer self.engine.freeValue(global);
        const constructor = try vm.get(self.engine, global, "RegExp");
        defer self.engine.freeValue(constructor);
        const pattern = try self.string("T");
        defer self.engine.freeValue(pattern);
        const flags = try self.string("i");
        defer self.engine.freeValue(flags);
        var args = [_]c.JSValue{ pattern, flags };
        const delimiter = try self.engine.checked(c.JS_CallConstructor(self.engine.context, constructor, args.len, &args));
        defer self.engine.freeValue(delimiter);
        const parts = try vm.invoke(self.engine, value, "split", &.{delimiter});
        defer self.engine.freeValue(parts);
        const length = try vm.get(self.engine, parts, "length");
        defer self.engine.freeValue(length);
        var count: f64 = 0;
        if (!c.JS_IsNumber(length)) return false;
        if (c.JS_ToFloat64(self.engine.context, &count, length) < 0) return error.JavaScriptException;
        if (count != 2) return false;
        const day = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, parts, 0));
        defer self.engine.freeValue(day);
        const clock = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, parts, 1));
        defer self.engine.freeValue(clock);
        return try self.date(day) and try self.time(clock, true);
    }
    fn url(self: Context, value: c.JSValue, base: ?c.JSValue) !bool {
        if (self.engine.url_class == 0) try @import("native_url.zig").install(self.engine);
        const global = c.JS_GetGlobalObject(self.engine.context);
        defer self.engine.freeValue(global);
        const constructor = try vm.get(self.engine, global, "URL");
        defer self.engine.freeValue(constructor);
        const result = try vm.invoke(self.engine, constructor, "canParse", if (base) |parent| &.{ value, parent } else &.{value});
        defer self.engine.freeValue(result);
        return c.JS_ToBool(self.engine.context, result) != 0;
    }
    fn iri(self: Context, value: c.JSValue) !bool {
        if (try self.match("iri.mjs", "InvalidIriChars", value) or try self.match("iri.mjs", "InvalidPercentEncoding", value)) return false;
        const size = try vm.get(self.engine, value, "length");
        defer self.engine.freeValue(size);
        var count: f64 = 0;
        if (c.JS_ToFloat64(self.engine.context, &count, size) < 0) return error.JavaScriptException;
        if (count < 2048) {
            const regexp = try self.expressionFor("iri.mjs", "IpvFutureMatch");
            defer self.engine.freeValue(regexp);
            const replacement = try self.string("[::1]");
            defer self.engine.freeValue(replacement);
            const narrowed = try vm.invoke(self.engine, value, "replace", &.{ regexp, replacement });
            defer self.engine.freeValue(narrowed);
            return self.url(narrowed, null);
        }
        return self.url(value, null);
    }
    fn iriReference(self: Context, value: c.JSValue) !bool {
        if (try self.match("iri_reference.mjs", "InvalidIriChars", value) or try self.match("iri_reference.mjs", "MalformedScheme", value)) return false;
        const base = try self.string("http://example.com");
        defer self.engine.freeValue(base);
        return self.url(value, base);
    }
    fn regex(self: Context, value: c.JSValue) !bool {
        const global = c.JS_GetGlobalObject(self.engine.context);
        defer self.engine.freeValue(global);
        const constructor = try vm.get(self.engine, global, "RegExp");
        defer self.engine.freeValue(constructor);
        const flags = try self.string("u");
        defer self.engine.freeValue(flags);
        var args = [_]c.JSValue{ value, flags };
        const result = c.JS_CallConstructor(self.engine.context, constructor, args.len, &args);
        if (c.JS_IsException(result)) {
            const failure = c.JS_GetException(self.engine.context);
            self.engine.freeValue(failure);
            return false;
        }
        self.engine.freeValue(result);
        return true;
    }
    fn patternPoint(self: Context, binding: []const u8, point: u21) !bool {
        var bytes: [4]u8 = undefined;
        const size = try std.unicode.wtf8Encode(point, &bytes);
        return self.matchText("idna/pattern/pattern.mjs", binding, bytes[0..size]);
    }
    fn european(self: Context, point: u21) !bool {
        return self.patternPoint("RE_EUROPEAN_NUMBER", point);
    }
    fn permitted(self: Context, point: u21) !bool {
        return self.patternPoint("RE_PERMITTED_CATEGORY", point);
    }
    const Bidi = enum { EN, AN, NSM, R, AL, L, ON };
    fn bidiClass(self: Context, point: u21) !Bidi {
        if (try self.european(point)) return .EN;
        if (try self.patternPoint("RE_ARABIC_INDIC_DIGIT", point)) return .AN;
        if (try self.patternPoint("RE_MARK_NONSPACING", point)) return .NSM;
        if (try self.patternPoint("RE_SCRIPT_HEBREW", point)) return .R;
        if (try self.patternPoint("RE_SCRIPT_ARABIC_LETTER", point)) return .AL;
        if (try self.patternPoint("RE_LETTER", point)) return .L;
        return .ON;
    }
    fn hasRtl(self: Context, text: []const u8) !bool {
        var iterator = (try std.unicode.Wtf8View.init(text)).iterator();
        while (iterator.nextCodepoint()) |point| switch (try self.bidiClass(point)) {
            .R, .AL, .AN => return true,
            else => {},
        };
        return false;
    }
    fn bidi(self: Context, text: []const u8) !bool {
        var first = true;
        var rtl = false;
        var saw_en = false;
        var saw_an = false;
        var iterator = (try std.unicode.Wtf8View.init(text)).iterator();
        while (iterator.nextCodepoint()) |point| {
            const class = try self.bidiClass(point);
            if (first) {
                if (class != .L and class != .R and class != .AL) return false;
                rtl = class == .R or class == .AL;
                first = false;
            }
            if ((rtl and class == .L) or (!rtl and (class == .R or class == .AL or class == .AN))) return false;
            saw_en = saw_en or class == .EN;
            saw_an = saw_an or class == .AN;
        }
        return !(rtl and saw_en and saw_an);
    }
    fn unicodeLabel(self: Context, text: []const u8) !bool {
        const points = try codepoints(self.engine.gpa, text);
        defer self.engine.gpa.free(points);
        if (points.len == 0) return false;
        var non_ascii = false;
        for (points) |point| if (point >= 128) {
            non_ascii = true;
            break;
        };
        if (non_ascii and (try encodedLength(points)) + 4 > 63) return false;
        if (try self.hasRtl(text) and !try self.bidi(text)) return false;
        if (points[0] == '-' or points[points.len - 1] == '-' or (points.len >= 4 and points[2] == '-' and points[3] == '-')) return false;
        if (try self.patternPoint("RE_COMBINING_MARK", points[0])) return false;
        var japanese = false;
        var middle_dot = false;
        for (points, 0..) |point, index| {
            if (try self.patternPoint("RE_RFC5892_DISALLOWED", point) or !try self.permitted(point)) return false;
            japanese = japanese or try self.patternPoint("RE_SCRIPT_JAPANESE", point);
            const previous = if (index > 0) points[index - 1] else 0;
            const next = if (index + 1 < points.len) points[index + 1] else 0;
            switch (point) {
                0xb7 => if (previous != 0x6c or next != 0x6c) return false,
                0x375 => if (next == 0 or !try self.patternPoint("RE_SCRIPT_GREEK", next)) return false,
                0x5f3, 0x5f4 => if (previous == 0 or !try self.patternPoint("RE_SCRIPT_HEBREW", previous)) return false,
                0x200c => if (previous == 0 or (previous < 0x80 and !try self.patternPoint("RE_VIRAMA", previous))) return false,
                0x200d => if (previous == 0 or !try self.patternPoint("RE_VIRAMA", previous)) return false,
                0x30fb => middle_dot = true,
                else => {},
            }
        }
        return !middle_dot or japanese;
    }
    fn punyLabel(self: Context, text: []const u8) !bool {
        if (!ace(text)) return false;
        const body = try self.string(text[4..]);
        defer self.engine.freeValue(body);
        const lower = try vm.invoke(self.engine, body, "toLowerCase", &.{});
        defer self.engine.freeValue(lower);
        const bytes = try self.engine.toString(lower);
        defer self.engine.gpa.free(bytes);
        if (std.mem.lastIndexOfScalar(u8, bytes, '-') == @as(?usize, 0)) return false;
        const decoded = decodePuny(self.engine.gpa, bytes) catch |err| {
            if (err == error.OutOfMemory) return err;
            return false;
        };
        defer self.engine.gpa.free(decoded);
        if (!try self.matchText("idna/pattern/pattern.mjs", "RE_NON_ASCII", decoded)) return false;
        return self.unicodeLabel(decoded);
    }
    fn hasBidiLabel(self: Context, text: []const u8) !bool {
        if (!ace(text)) return self.hasRtl(text);
        const body = try self.string(text[4..]);
        defer self.engine.freeValue(body);
        const lower = try vm.invoke(self.engine, body, "toLowerCase", &.{});
        defer self.engine.freeValue(lower);
        const bytes = try self.engine.toString(lower);
        defer self.engine.gpa.free(bytes);
        const decoded = decodePuny(self.engine.gpa, bytes) catch |err| {
            if (err == error.OutOfMemory) return err;
            return false;
        };
        defer self.engine.gpa.free(decoded);
        return self.hasRtl(decoded);
    }
    fn hostname(self: Context, value: c.JSValue, international: bool) !bool {
        const length = try vm.get(self.engine, value, "length");
        defer self.engine.freeValue(length);
        var count: f64 = 0;
        if (c.JS_ToFloat64(self.engine.context, &count, length) < 0) return error.JavaScriptException;
        if ((c.JS_IsNumber(length) and count == 0) or (!international and count > 253)) return false;
        if (international) {
            const space = try self.string(" ");
            defer self.engine.freeValue(space);
            const included = try vm.invoke(self.engine, value, "includes", &.{space});
            defer self.engine.freeValue(included);
            if (c.JS_ToBool(self.engine.context, included) != 0) return false;
        } else {
            const last = try self.engine.checked(c.JS_NewFloat64(self.engine.context, count - 1));
            defer self.engine.freeValue(last);
            const code = try vm.invoke(self.engine, value, "charCodeAt", &.{last});
            defer self.engine.freeValue(code);
            var number: f64 = 0;
            if (c.JS_IsNumber(code)) {
                if (c.JS_ToFloat64(self.engine.context, &number, code) < 0) return error.JavaScriptException;
                if (number == 46) return false;
            }
        }
        const input = try self.engine.toString(value);
        defer self.engine.gpa.free(input);
        if (input.len == 0 or (international and std.mem.indexOfScalar(u8, input, ' ') != null)) return false;
        const normalized = if (international) try self.normalizedHostname(input) else try self.engine.gpa.dupe(u8, input);
        defer self.engine.gpa.free(normalized);
        if (try std.unicode.calcWtf16LeLen(normalized) > 253) return false;
        var has_bidi = false;
        var labels = std.mem.splitScalar(u8, normalized, '.');
        if (international) while (labels.next()) |label| {
            if (try self.hasBidiLabel(label)) {
                has_bidi = true;
                break;
            }
        };
        labels = std.mem.splitScalar(u8, normalized, '.');
        while (labels.next()) |label| {
            const size = try std.unicode.calcWtf16LeLen(label);
            if (size == 0 or size > 63) return false;
            var valid = try self.punyLabel(label);
            if (!valid) valid = if (international) try self.unicodeLabel(label) else try self.matchText("idna/pattern/pattern.mjs", "RE_RULE_HYPHEN_PLACEMENT", label) and try self.matchText("idna/pattern/pattern.mjs", "RE_RULE_NOT_RESERVED_ACE", label) and try self.matchText("idna/pattern/pattern.mjs", "RE_ASCII_LDH", label);
            if (!valid or (has_bidi and !try self.bidi(label))) return false;
        }
        return true;
    }
    fn normalizedHostname(self: Context, input: []const u8) ![]u8 {
        var mapped: std.ArrayList(u8) = .empty;
        defer mapped.deinit(self.engine.gpa);
        var iterator = (try std.unicode.Wtf8View.init(input)).iterator();
        while (iterator.nextCodepoint()) |point| try appendPoint(self.engine.gpa, &mapped, if (point >= 0xff01 and point <= 0xff5e) point - 0xfee0 else point);
        const source = try self.string(mapped.items);
        defer self.engine.freeValue(source);
        const form = try self.string("NFC");
        defer self.engine.freeValue(form);
        const normalized = try vm.invoke(self.engine, source, "normalize", &.{form});
        defer self.engine.freeValue(normalized);
        const text = try self.engine.toString(normalized);
        defer self.engine.gpa.free(text);
        var output: std.ArrayList(u8) = .empty;
        errdefer output.deinit(self.engine.gpa);
        iterator = (try std.unicode.Wtf8View.init(text)).iterator();
        while (iterator.nextCodepoint()) |point| {
            if (point == 0xad or point == 0x34f or (point >= 0x180b and point <= 0x180d) or point == 0x200b or (point >= 0xfe00 and point <= 0xfe0f) or (point >= 0xe0100 and point <= 0xe01ef)) continue;
            try appendPoint(self.engine.gpa, &output, if (point == 0x3002 or point == 0xff0e or point == 0xff61) '.' else point);
        }
        return output.toOwnedSlice(self.engine.gpa);
    }
};
fn ace(value: []const u8) bool {
    return value.len >= 4 and std.ascii.eqlIgnoreCase(value[0..4], "xn--");
}
fn codepoints(gpa: std.mem.Allocator, text: []const u8) ![]u21 {
    var output: std.ArrayList(u21) = .empty;
    errdefer output.deinit(gpa);
    var iterator = (try std.unicode.Wtf8View.init(text)).iterator();
    while (iterator.nextCodepoint()) |point| try output.append(gpa, point);
    return output.toOwnedSlice(gpa);
}
fn appendPoint(gpa: std.mem.Allocator, output: *std.ArrayList(u8), point: u21) !void {
    var bytes: [4]u8 = undefined;
    const size = try std.unicode.wtf8Encode(point, &bytes);
    try output.appendSlice(gpa, bytes[0..size]);
}
fn adapt(input: u64, count: u64, first: bool) u64 {
    var delta = if (first) input / 700 else input / 2;
    delta += delta / count;
    var k: u64 = 0;
    while (delta > 455) {
        delta /= 35;
        k += 36;
    }
    return k + 36 * delta / (delta + 38);
}
fn encodedLength(points: []const u21) !usize {
    var basic: usize = 0;
    for (points) |point| {
        if (point < 128) basic += 1;
    }
    var result = basic + @intFromBool(basic > 0);
    var n: u64 = 128;
    var delta: u64 = 0;
    var bias: u64 = 72;
    var handled = basic;
    while (handled < points.len) {
        var m: u64 = std.math.maxInt(u64);
        for (points) |point| {
            if (point >= n and point < m) m = point;
        }
        delta += (m - n) * (handled + 1);
        n = m;
        for (points) |point| {
            if (point < n) delta += 1;
            if (point == n) {
                var q = delta;
                var k: u64 = 36;
                while (true) : (k += 36) {
                    const t = if (k <= bias) @as(u64, 1) else if (k >= bias + 26) @as(u64, 26) else k - bias;
                    if (q < t) break;
                    result += 1;
                    q = (q - t) / (36 - t);
                }
                result += 1;
                bias = adapt(delta, handled + 1, handled == basic);
                delta = 0;
                handled += 1;
            }
        }
        delta += 1;
        n += 1;
    }
    return result;
}
fn decodePuny(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    var points: std.ArrayList(u21) = .empty;
    defer points.deinit(gpa);
    var n: u64 = 128;
    var i: u64 = 0;
    var bias: u64 = 72;
    const delimiter = std.mem.lastIndexOfScalar(u8, input, '-');
    if (delimiter) |at| {
        if (at > 0) for (input[0..at]) |byte| {
            if (byte >= 128) return error.InvalidPunycode;
            try points.append(gpa, byte);
        };
    }
    var index = if (delimiter) |at| at + 1 else 0;
    while (index < input.len) {
        const old = i;
        var weight: u64 = 1;
        var k: u64 = 36;
        while (true) : (k += 36) {
            if (index >= input.len) return error.InvalidPunycode;
            const byte = input[index];
            index += 1;
            const digit: u64 = if (byte >= 'a' and byte <= 'z') byte - 'a' else if (byte >= '0' and byte <= '9') byte - '0' + 26 else return error.InvalidPunycode;
            i = std.math.add(u64, i, std.math.mul(u64, digit, weight) catch return error.InvalidPunycode) catch return error.InvalidPunycode;
            const t = if (k <= bias) @as(u64, 1) else if (k >= bias + 26) @as(u64, 26) else k - bias;
            if (digit < t) break;
            weight = std.math.mul(u64, weight, 36 - t) catch return error.InvalidPunycode;
        }
        const length = points.items.len + 1;
        bias = adapt(i - old, length, old == 0);
        n = std.math.add(u64, n, i / length) catch return error.InvalidPunycode;
        if (n > 0x10ffff) return error.InvalidPunycode;
        i %= length;
        try points.insert(gpa, @intCast(i), @intCast(n));
        i += 1;
    }
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(gpa);
    for (points.items) |point| try appendPoint(gpa, &output, point);
    return output.toOwnedSlice(gpa);
}

fn formatCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const owner: Context = .{ .engine = engine, .patterns = data[0] };
    const strict = argc < 2 or c.JS_IsUndefined(argv[1]) or c.JS_ToBool(context, argv[1]) != 0;
    const result = owner.check(@enumFromInt(magic), if (argc > 0) argv[0] else c.pi_js_undefined(), strict) catch |err| {
        if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
        if (err == error.JavaScriptException) return engine.throwCaptured();
        return c.JS_ThrowTypeError(context, "Native format: %s", @as([*:0]const u8, @errorName(err)));
    };
    return c.pi_js_bool(context, @intFromBool(result));
}
pub fn createFunctions(engine: *Engine) !c.JSValue {
    if (engine.url_class == 0) try @import("native_url.zig").install(engine);
    const expressions = try patterns(engine);
    defer engine.freeValue(expressions);
    const result = try vm.object(engine);
    errdefer engine.freeValue(result);
    var data = [_]c.JSValue{expressions};
    for (exported, 0..) |name, index| try vm.put(engine, result, name, try engine.checked(c.JS_NewCFunctionData2(engine.context, formatCallback, name.ptr, 1, @intCast(index), data.len, &data)));
    return result;
}
pub fn create(engine: *Engine) !c.JSValue {
    const functions = try createFunctions(engine);
    defer engine.freeValue(functions);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const constructor = try vm.get(engine, global, "Map");
    defer engine.freeValue(constructor);
    const registry = try engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null));
    defer engine.freeValue(registry);
    const defaults = try vm.array(engine);
    defer engine.freeValue(defaults);
    for (exported, 0..) |name, index| if (c.JS_SetPropertyUint32(engine.context, defaults, @intCast(index), try vm.get(engine, functions, name)) < 0) return error.JavaScriptException;
    try reset(engine, registry, defaults);
    var data = [_]c.JSValue{ registry, defaults };
    inline for (.{ "Clear", "Entries", "Set", "Has", "Get", "Test", "Reset" }, .{ 0, 0, 2, 1, 1, 2, 0 }, 0..) |name, length, index| try vm.put(engine, functions, name, try engine.checked(c.JS_NewCFunctionData2(engine.context, registryCallback, name, length, @intCast(index), data.len, &data)));
    const exports = try vm.object(engine);
    errdefer engine.freeValue(exports);
    const object = try vm.get(engine, global, "Object");
    defer engine.freeValue(object);
    const assigned = try vm.invoke(engine, object, "assign", &.{ exports, functions });
    engine.freeValue(assigned);
    const namespace = try engine.valueNamespace(functions);
    defer engine.freeValue(namespace);
    try vm.put(engine, exports, "Format", c.JS_DupValue(engine.context, namespace));
    try vm.put(engine, exports, "default", c.JS_DupValue(engine.context, namespace));
    return exports;
}
fn reset(engine: *Engine, registry: c.JSValue, defaults: c.JSValue) !void {
    const cleared = try vm.invoke(engine, registry, "clear", &.{});
    engine.freeValue(cleared);
    for (names, 0..) |name, index| {
        const label = try engine.checked(c.JS_NewStringLen(engine.context, name.ptr, name.len));
        defer engine.freeValue(label);
        const callback = try engine.checked(c.JS_GetPropertyUint32(engine.context, defaults, @intCast(index)));
        defer engine.freeValue(callback);
        const ignored = try vm.invoke(engine, registry, "set", &.{ label, callback });
        engine.freeValue(ignored);
    }
}
pub fn checkRegistry(engine: *Engine, registry: c.JSValue, name: c.JSValue, value: c.JSValue) !bool {
    const result = try testRegistry(engine, registry, name, value);
    defer engine.freeValue(result);
    return c.JS_ToBool(engine.context, result) != 0;
}
pub fn testRegistry(engine: *Engine, registry: c.JSValue, name: c.JSValue, value: c.JSValue) !c.JSValue {
    const callback = try vm.invoke(engine, registry, "get", &.{name});
    defer engine.freeValue(callback);
    if (c.JS_IsUndefined(callback) or c.JS_IsNull(callback)) return c.pi_js_bool(engine.context, 1);
    if (!c.JS_IsFunction(engine.context, callback)) return engine.checked(c.JS_ThrowTypeError(engine.context, "formats.get(...) is not a function"));
    var args = [_]c.JSValue{value};
    const result = try engine.checked(c.JS_Call(engine.context, callback, c.pi_js_undefined(), 1, &args));
    if (c.JS_IsUndefined(result) or c.JS_IsNull(result)) {
        engine.freeValue(result);
        return c.pi_js_bool(engine.context, 1);
    }
    return result;
}
fn registryCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return registryOwned(engine, argv[0..@intCast(argc)], operation, data) catch |err| {
        if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
        if (err == error.JavaScriptException) return engine.throwCaptured();
        return c.JS_ThrowTypeError(context, "Native format: %s", @as([*:0]const u8, @errorName(err)));
    };
}
fn registryOwned(engine: *Engine, args: []const c.JSValue, operation: c_int, data: [*c]c.JSValue) !c.JSValue {
    const first = if (args.len > 0) args[0] else c.pi_js_undefined();
    const second = if (args.len > 1) args[1] else c.pi_js_undefined();
    switch (operation) {
        0 => return vm.invoke(engine, data[0], "clear", &.{}),
        1 => {
            const iterator = try vm.invoke(engine, data[0], "entries", &.{});
            defer engine.freeValue(iterator);
            const global = c.JS_GetGlobalObject(engine.context);
            defer engine.freeValue(global);
            const array = try vm.get(engine, global, "Array");
            defer engine.freeValue(array);
            return vm.invoke(engine, array, "from", &.{iterator});
        },
        2 => {
            const ignored = try vm.invoke(engine, data[0], "set", &.{ first, second });
            engine.freeValue(ignored);
            return c.pi_js_undefined();
        },
        3 => return vm.invoke(engine, data[0], "has", &.{first}),
        4 => return vm.invoke(engine, data[0], "get", &.{first}),
        5 => return testRegistry(engine, data[0], first, second),
        else => {
            try reset(engine, data[0], data[1]);
            return c.pi_js_undefined();
        },
    }
}
test "native durable VM schema formats preserve all pinned format regexes IDNA Unicode bidi punycode and leap second rules" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const formats = try createFunctions(engine);
    defer engine.freeValue(formats);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try vm.put(engine, global, "Format", c.JS_DupValue(engine.context, formats));
    errdefer std.debug.print("Schema formats VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\const Format=globalThis.Format;
        \\const functions=['IsDateTime','IsDate','IsDuration','IsEmail','IsHostname','IsIdnEmail','IsIdnHostname','IsIPv4','IsIPv6','IsIriReference','IsIri','IsJsonPointerUriFragment','IsJsonPointer','IsRegex','IsRelativeJsonPointer','IsTime','IsUriReference','IsUriTemplate','IsUri','IsUrl','IsUuid'],inputs=['','foo','2024-02-29','2023-02-29','2000-02-29T23:59:60Z','23:59:60Z','00:59:60+01:00','23:59:60+01:00','12:34:56','P3Y6M4DT12H30M5S','user@example.com','user@bücher.de','bücher.de','xn--bcher-kva.de','http://example.com/a%20b','http://[v1.test]/','http://x/%xx','../a','a/a','a·a','l·l','اa','ا1١','a‍b','क्‍ष','ＡＢＣ．com','xn--abc-','xn--a','001.2.3.4','::1','{+path}','#/a~1b','0#','not[a','^\p{L}+$','مثال.123','xn--mgbh0fb.123','é.com','a­.com','a'.repeat(64)+'.com','é'.repeat(58)+'.com','http://[v1.test]/'+'a'.repeat(2048),'00000000-0000-0000-0000-000000000000'];
        \\globalThis.result=JSON.stringify({matrix:functions.map(name=>({name,values:inputs.map(value=>Format[name](value))})),looseTime:Format.IsTime('12:34:56',false)});
        \\
    , "native-schema-formats-source");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-schema-formats-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"matrix\":[{\"name\":\"IsDateTime\",\"values\":[false,false,false,false,true,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false]},{\"name\":\"IsDate\",\"values\":[false,false,true,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false]},{\"name\":\"IsDuration\",\"values\":[false,false,false,false,false,false,false,false,false,true,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false]},{\"name\":\"IsEmail\",\"values\":[false,false,false,false,false,false,false,false,false,false,true,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false]},{\"name\":\"IsHostname\",\"values\":[false,true,true,true,false,false,false,false,false,true,false,false,false,true,false,false,false,false,false,false,false,false,false,false,false,false,false,false,true,false,false,false,false,false,false,false,true,false,false,false,false,false,true]},{\"name\":\"IsIdnEmail\",\"values\":[false,false,false,false,false,false,false,false,false,false,true,true,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false]},{\"name\":\"IsIdnHostname\",\"values\":[false,true,true,true,true,true,true,true,true,true,false,false,true,true,false,false,false,false,true,false,true,false,false,false,true,true,false,false,true,true,false,false,false,false,false,false,false,true,true,false,false,false,true]},{\"name\":\"IsIPv4\",\"values\":[false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false]},{\"name\":\"IsIPv6\",\"values\":[false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,true,false,false,false,false,false,false,false,false,false,false,false,false,false]},{\"name\":\"IsIriReference\",\"values\":[true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,false,false,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,false,true]},{\"name\":\"IsIri\",\"values\":[false,false,false,false,false,false,false,false,false,false,false,false,false,false,true,true,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false]},{\"name\":\"IsJsonPointerUriFragment\",\"values\":[false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,true,false,false,false,false,false,false,false,false,false,false,false]},{\"name\":\"IsJsonPointer\",\"values\":[true,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false]},{\"name\":\"IsRegex\",\"values\":[true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,false,true,true,false,false,true,true,true,true,true,true,true,true]},{\"name\":\"IsRelativeJsonPointer\",\"values\":[false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,true,false,false,false,false,false,false,false,false,false,false]},{\"name\":\"IsTime\",\"values\":[false,false,false,false,false,true,true,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false]},{\"name\":\"IsUriReference\",\"values\":[true,true,true,true,false,false,false,false,false,true,true,false,false,true,true,true,false,true,true,false,false,false,false,false,false,false,true,true,true,false,false,true,true,false,false,false,true,false,false,true,false,true,true]},{\"name\":\"IsUriTemplate\",\"values\":[true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,false,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,false,true,true,true,true,true,true,true,true]},{\"name\":\"IsUri\",\"values\":[false,false,false,false,false,false,false,false,false,false,false,false,false,false,true,true,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,true,false]},{\"name\":\"IsUrl\",\"values\":[false,false,false,false,false,false,false,false,false,false,false,false,false,false,true,false,true,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false]},{\"name\":\"IsUuid\",\"values\":[false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,true]}],\"looseTime\":true}", text);
}

test "native durable VM format registry preserves callbacks return values errors default namespace reset and detached entries" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const formats = try create(engine);
    defer engine.freeValue(formats);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try vm.put(engine, global, "Format", c.JS_DupValue(engine.context, formats));
    errdefer std.debug.print("Format registry VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\const Format=globalThis.Format;
        \\const initial=Format.Entries(),original=Format.Get('email'),input={owned:true},returned={kept:true},events=[],callback=function(value){events.push({receiver:this===undefined,identity:value===input});return returned},set=Format.Set('fixture',callback),value=Format.Test('fixture',input),entries=Format.Entries(),pair=entries.find(([key])=>key==='fixture'),stored=Format.Get('fixture')===callback;pair[1]=()=>false;const detached=Format.Get('fixture')===callback;Format.Set('nil',()=>null);Format.Set('zero',()=>0);const nil=Format.Test('nil',input),zero=Format.Test('zero',input),pending=Promise.resolve(7);Format.Set('promise',()=>pending);const promise=Format.Test('promise',input)===pending,reason={original:true};Format.Set('throw',()=>{throw reason});let identity;try{Format.Test('throw',input)}catch(error){identity=error===reason}Format.Set('bad',17);let bad;try{Format.Test('bad',input)}catch(error){bad={name:error.name,message:error.message}}const namespace=Format.Format,descriptor=Object.getOwnPropertyDescriptor(namespace,'Test');let readonly;try{namespace.Test=()=>false}catch(error){readonly=error instanceof TypeError}const shape={readonly,tag:Object.prototype.toString.call(namespace),prototype:Object.getPrototypeOf(namespace)===null,extensible:Object.isExtensible(namespace),descriptor:{writable:descriptor.writable,enumerable:descriptor.enumerable,configurable:descriptor.configurable},functions:['Clear','Entries','Set','Has','Get','Test','Reset','IsEmail','IsTime'].map(name=>({key:name,name:namespace[name].name,length:namespace[name].length}))};const cleared=Format.Clear(),empty=Format.Entries().length,unknown=Format.Test('missing',input),missing=Format.Get('missing')===undefined,reset=Format.Reset();globalThis.result=JSON.stringify({initial:initial.map(([key])=>key),builtin:original===Format.IsEmail,shape,aliases:Format.Format===Format.default&&Format.Format.IsEmail===Format.IsEmail&&Format.Format.Format===undefined,set:set===undefined,value:value===returned,stored,detached,events,nil,zero,promise,identity,bad,clear:cleared===undefined,empty,unknown,missing,reset:reset===undefined,restored:Format.Get('email')===original&&!Format.Has('fixture')});
        \\
    , "native-schema-format-registry-source");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-schema-format-registry-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"initial\":[\"date-time\",\"date\",\"duration\",\"email\",\"hostname\",\"idn-email\",\"idn-hostname\",\"ipv4\",\"ipv6\",\"iri-reference\",\"iri\",\"json-pointer-uri-fragment\",\"json-pointer\",\"regex\",\"relative-json-pointer\",\"time\",\"uri-reference\",\"uri-template\",\"uri\",\"url\",\"uuid\"],\"builtin\":true,\"shape\":{\"readonly\":true,\"tag\":\"[object Module]\",\"prototype\":true,\"extensible\":false,\"descriptor\":{\"writable\":true,\"enumerable\":true,\"configurable\":false},\"functions\":[{\"key\":\"Clear\",\"name\":\"Clear\",\"length\":0},{\"key\":\"Entries\",\"name\":\"Entries\",\"length\":0},{\"key\":\"Set\",\"name\":\"Set\",\"length\":2},{\"key\":\"Has\",\"name\":\"Has\",\"length\":1},{\"key\":\"Get\",\"name\":\"Get\",\"length\":1},{\"key\":\"Test\",\"name\":\"Test\",\"length\":2},{\"key\":\"Reset\",\"name\":\"Reset\",\"length\":0},{\"key\":\"IsEmail\",\"name\":\"IsEmail\",\"length\":1},{\"key\":\"IsTime\",\"name\":\"IsTime\",\"length\":1}]},\"aliases\":true,\"set\":true,\"value\":true,\"stored\":true,\"detached\":true,\"events\":[{\"receiver\":true,\"identity\":true}],\"nil\":true,\"zero\":0,\"promise\":true,\"identity\":true,\"bad\":{\"name\":\"TypeError\",\"message\":\"formats.get(...) is not a function\"},\"clear\":true,\"empty\":0,\"unknown\":true,\"missing\":true,\"reset\":true,\"restored\":true}", text);
}
fn allocationExercise(gpa: std.mem.Allocator) !void {
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    const exports = try create(engine);
    defer engine.freeValue(exports);
    const expressions = try patterns(engine);
    defer engine.freeValue(expressions);
    const owner: Context = .{ .engine = engine, .patterns = expressions };
    const inputs = try engine.eval("['bücher.de','xn--bcher-kva.de','مثال.123','ＡＢＣ．com','क्‍ष','é'.repeat(58)+'.com']", "format-allocation-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(inputs);
    for (0..try vm.length(engine, inputs)) |index| {
        const input = try engine.checked(c.JS_GetPropertyUint32(engine.context, inputs, @intCast(index)));
        defer engine.freeValue(input);
        _ = try owner.check(.idn_hostname, input, true);
    }
}
test "native durable VM format registry regex construction IDNA bidi and punycode unwind every GPA allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationExercise, .{});
}

test "native durable VM schema format named functions preserve coercions and intrinsic error categories for nonstrings" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const formats = try createFunctions(engine);
    defer engine.freeValue(formats);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try vm.put(engine, global, "Format", c.JS_DupValue(engine.context, formats));
    errdefer std.debug.print("Format types VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\const Format=globalThis.Format;
        \\const functions=['IsDateTime','IsDate','IsDuration','IsEmail','IsHostname','IsIdnEmail','IsIdnHostname','IsIPv4','IsIPv6','IsIriReference','IsIri','IsJsonPointerUriFragment','IsJsonPointer','IsRegex','IsRelativeJsonPointer','IsTime','IsUriReference','IsUriTemplate','IsUri','IsUrl','IsUuid'],inputs=[undefined,null,0,true,{},[],new String('2024-02-29'),Symbol('x')];globalThis.result=JSON.stringify(functions.map(name=>({name,values:inputs.map(value=>{try{return{ok:Format[name](value)}}catch(error){return{error:error.name}}})})));
        \\
    , "native-schema-format-types-source");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-schema-format-types-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("[{\"name\":\"IsDateTime\",\"values\":[{\"error\":\"TypeError\"},{\"error\":\"TypeError\"},{\"error\":\"TypeError\"},{\"error\":\"TypeError\"},{\"error\":\"TypeError\"},{\"error\":\"TypeError\"},{\"ok\":false},{\"error\":\"TypeError\"}]},{\"name\":\"IsDate\",\"values\":[{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":true},{\"error\":\"TypeError\"}]},{\"name\":\"IsDuration\",\"values\":[{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"error\":\"TypeError\"}]},{\"name\":\"IsEmail\",\"values\":[{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"error\":\"TypeError\"}]},{\"name\":\"IsHostname\",\"values\":[{\"error\":\"TypeError\"},{\"error\":\"TypeError\"},{\"error\":\"TypeError\"},{\"error\":\"TypeError\"},{\"error\":\"TypeError\"},{\"ok\":false},{\"ok\":true},{\"error\":\"TypeError\"}]},{\"name\":\"IsIdnEmail\",\"values\":[{\"error\":\"TypeError\"},{\"error\":\"TypeError\"},{\"error\":\"TypeError\"},{\"error\":\"TypeError\"},{\"error\":\"TypeError\"},{\"error\":\"TypeError\"},{\"ok\":false},{\"error\":\"TypeError\"}]},{\"name\":\"IsIdnHostname\",\"values\":[{\"error\":\"TypeError\"},{\"error\":\"TypeError\"},{\"error\":\"TypeError\"},{\"error\":\"TypeError\"},{\"error\":\"TypeError\"},{\"ok\":false},{\"ok\":true},{\"error\":\"TypeError\"}]},{\"name\":\"IsIPv4\",\"values\":[{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"error\":\"TypeError\"}]},{\"name\":\"IsIPv6\",\"values\":[{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"error\":\"TypeError\"}]},{\"name\":\"IsIriReference\",\"values\":[{\"ok\":true},{\"ok\":true},{\"ok\":true},{\"ok\":true},{\"ok\":false},{\"ok\":true},{\"ok\":true},{\"error\":\"TypeError\"}]},{\"name\":\"IsIri\",\"values\":[{\"error\":\"TypeError\"},{\"error\":\"TypeError\"},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"error\":\"TypeError\"},{\"ok\":false},{\"error\":\"TypeError\"}]},{\"name\":\"IsJsonPointerUriFragment\",\"values\":[{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"error\":\"TypeError\"}]},{\"name\":\"IsJsonPointer\",\"values\":[{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":true},{\"ok\":false},{\"error\":\"TypeError\"}]},{\"name\":\"IsRegex\",\"values\":[{\"ok\":true},{\"ok\":true},{\"ok\":true},{\"ok\":true},{\"ok\":true},{\"ok\":true},{\"ok\":true},{\"ok\":false}]},{\"name\":\"IsRelativeJsonPointer\",\"values\":[{\"ok\":false},{\"ok\":false},{\"ok\":true},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"error\":\"TypeError\"}]},{\"name\":\"IsTime\",\"values\":[{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"error\":\"TypeError\"}]},{\"name\":\"IsUriReference\",\"values\":[{\"ok\":true},{\"ok\":true},{\"ok\":true},{\"ok\":true},{\"ok\":false},{\"ok\":true},{\"ok\":true},{\"error\":\"TypeError\"}]},{\"name\":\"IsUriTemplate\",\"values\":[{\"ok\":true},{\"ok\":true},{\"ok\":true},{\"ok\":true},{\"ok\":false},{\"ok\":true},{\"ok\":true},{\"error\":\"TypeError\"}]},{\"name\":\"IsUri\",\"values\":[{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"error\":\"TypeError\"}]},{\"name\":\"IsUrl\",\"values\":[{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"error\":\"TypeError\"}]},{\"name\":\"IsUuid\",\"values\":[{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"ok\":false},{\"error\":\"TypeError\"}]}]", text);
}
