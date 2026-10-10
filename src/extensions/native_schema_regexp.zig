//! Source diagnostic spelling for intrinsic RegExp failures on the schema path.
//! A user-supplied RegExp constructor retains its exact thrown value.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
fn hasOpenClass(pattern: []const u8) bool {
    var open = false;
    var escaped = false;
    for (pattern) |byte| {
        if (escaped) {
            escaped = false;
            continue;
        }
        if (byte == '\\') {
            escaped = true;
            continue;
        }
        if (byte == '[') open = true;
        if (byte == ']') open = false;
    }
    return open;
}
fn reason(pattern: []const u8, message: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, message, "unexpected end")) return if (hasOpenClass(pattern)) "Unterminated character class" else "\\ at end of pattern";
    if (std.mem.eql(u8, message, "expecting ')'")) return "Unterminated group";
    if (std.mem.eql(u8, message, "extraneous characters at the end")) return "Unmatched ')'";
    if (std.mem.eql(u8, message, "nothing to repeat")) return if (std.mem.indexOf(u8, pattern, "(?=") != null or std.mem.indexOf(u8, pattern, "(?!") != null) "Invalid quantifier" else "Nothing to repeat";
    if (std.mem.eql(u8, message, "invalid repetition count")) return if (std.mem.indexOfScalar(u8, pattern, '}') != null) "numbers out of order in {} quantifier" else "Incomplete quantifier";
    if (std.mem.eql(u8, message, "syntax error")) return "Lone quantifier brackets";
    if (std.mem.eql(u8, message, "invalid class range")) return if (std.mem.indexOf(u8, pattern, "\\d") != null or std.mem.indexOf(u8, pattern, "\\D") != null or std.mem.indexOf(u8, pattern, "\\w") != null or std.mem.indexOf(u8, pattern, "\\W") != null or std.mem.indexOf(u8, pattern, "\\s") != null or std.mem.indexOf(u8, pattern, "\\S") != null or std.mem.indexOf(u8, pattern, "\\p") != null or std.mem.indexOf(u8, pattern, "\\P") != null) "Invalid character class" else "Range out of order in character class";
    if (std.mem.eql(u8, message, "invalid group")) return "Invalid group";
    if (std.mem.eql(u8, message, "duplicate group name")) return "Duplicate capture group name";
    if (std.mem.eql(u8, message, "invalid group name") or std.mem.eql(u8, message, "expecting group name")) return "Invalid capture group name";
    if (std.mem.eql(u8, message, "group name not defined")) return "Invalid named capture referenced";
    if (std.mem.eql(u8, message, "invalid escape sequence in regular expression") or std.mem.eql(u8, message, "malformed unicode char")) return if (std.mem.indexOf(u8, pattern, "\\u") != null or std.mem.indexOf(u8, pattern, "\\c") != null) "Invalid Unicode escape" else "Invalid escape";
    if (std.mem.eql(u8, message, "back reference out of range in regular expression") or std.mem.eql(u8, message, "invalid decimal escape in regular expression")) return "Invalid escape";
    if (std.mem.startsWith(u8, message, "unknown unicode") or std.mem.eql(u8, message, "expecting '{' after \\p")) return if (std.mem.indexOfScalar(u8, pattern, '[') != null) "Invalid property name in character class" else "Invalid property name";
    return null;
}
pub fn construct(engine: *Engine, constructor: c.JSValue, pattern: c.JSValue, flags: ?c.JSValue) !c.JSValue {
    var args = [_]c.JSValue{ pattern, flags orelse c.pi_js_undefined() };
    const result = c.JS_CallConstructor(engine.context, constructor, if (flags != null) 2 else 1, &args);
    if (!c.JS_IsException(result) or !c.JS_IsStrictEqual(engine.context, constructor, engine.intrinsic_regexp_constructor) or !c.JS_IsString(pattern)) return engine.checked(result);
    const failure = c.JS_GetException(engine.context);
    defer engine.freeValue(failure);
    const message_value = try vm.get(engine, failure, "message");
    defer engine.freeValue(message_value);
    const message = try engine.toString(message_value);
    defer engine.gpa.free(message);
    const input = try engine.toString(pattern);
    defer engine.gpa.free(input);
    if (reason(input, message)) |diagnostic| {
        const flag_text = if (flags) |value| try engine.toString(value) else try engine.gpa.dupe(u8, "");
        defer engine.gpa.free(flag_text);
        const full = try std.fmt.allocPrint(engine.gpa, "Invalid regular expression: /{s}/{s}: {s}", .{ input, flag_text, diagnostic });
        defer engine.gpa.free(full);
        if (c.JS_DefinePropertyValueStr(engine.context, failure, "message", c.JS_NewStringLen(engine.context, full.ptr, full.len), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
    }
    return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, failure)));
}
