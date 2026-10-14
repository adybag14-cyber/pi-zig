//! Complete Source highlight.js10.7.3 Swift factory; source-only draft.
const std = @import("std");
const em = @import("engine.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const ordinary = @import("native_legacy_function.zig");
const c = em.c;
const Token = struct { regex: bool, text: []const u8 };
// Actual Source Swift module constants; generated native literals from unchanged Source.
const dotKeywords = [_]Token{
    .{ .regex = false, .text = "Protocol" },
    .{ .regex = false, .text = "Type" },
};
const optionalDotKeywords = [_]Token{
    .{ .regex = false, .text = "init" },
    .{ .regex = false, .text = "self" },
};
const keywordTypes = [_]Token{
    .{ .regex = false, .text = "Any" },
    .{ .regex = false, .text = "Self" },
};
const keywords = [_]Token{
    .{ .regex = false, .text = "associatedtype" },
    .{ .regex = false, .text = "async" },
    .{ .regex = false, .text = "await" },
    .{ .regex = true, .text = "as\\?" },
    .{ .regex = true, .text = "as!" },
    .{ .regex = false, .text = "as" },
    .{ .regex = false, .text = "break" },
    .{ .regex = false, .text = "case" },
    .{ .regex = false, .text = "catch" },
    .{ .regex = false, .text = "class" },
    .{ .regex = false, .text = "continue" },
    .{ .regex = false, .text = "convenience" },
    .{ .regex = false, .text = "default" },
    .{ .regex = false, .text = "defer" },
    .{ .regex = false, .text = "deinit" },
    .{ .regex = false, .text = "didSet" },
    .{ .regex = false, .text = "do" },
    .{ .regex = false, .text = "dynamic" },
    .{ .regex = false, .text = "else" },
    .{ .regex = false, .text = "enum" },
    .{ .regex = false, .text = "extension" },
    .{ .regex = false, .text = "fallthrough" },
    .{ .regex = true, .text = "fileprivate\\(set\\)" },
    .{ .regex = false, .text = "fileprivate" },
    .{ .regex = false, .text = "final" },
    .{ .regex = false, .text = "for" },
    .{ .regex = false, .text = "func" },
    .{ .regex = false, .text = "get" },
    .{ .regex = false, .text = "guard" },
    .{ .regex = false, .text = "if" },
    .{ .regex = false, .text = "import" },
    .{ .regex = false, .text = "indirect" },
    .{ .regex = false, .text = "infix" },
    .{ .regex = true, .text = "init\\?" },
    .{ .regex = true, .text = "init!" },
    .{ .regex = false, .text = "inout" },
    .{ .regex = true, .text = "internal\\(set\\)" },
    .{ .regex = false, .text = "internal" },
    .{ .regex = false, .text = "in" },
    .{ .regex = false, .text = "is" },
    .{ .regex = false, .text = "lazy" },
    .{ .regex = false, .text = "let" },
    .{ .regex = false, .text = "mutating" },
    .{ .regex = false, .text = "nonmutating" },
    .{ .regex = true, .text = "open\\(set\\)" },
    .{ .regex = false, .text = "open" },
    .{ .regex = false, .text = "operator" },
    .{ .regex = false, .text = "optional" },
    .{ .regex = false, .text = "override" },
    .{ .regex = false, .text = "postfix" },
    .{ .regex = false, .text = "precedencegroup" },
    .{ .regex = false, .text = "prefix" },
    .{ .regex = true, .text = "private\\(set\\)" },
    .{ .regex = false, .text = "private" },
    .{ .regex = false, .text = "protocol" },
    .{ .regex = true, .text = "public\\(set\\)" },
    .{ .regex = false, .text = "public" },
    .{ .regex = false, .text = "repeat" },
    .{ .regex = false, .text = "required" },
    .{ .regex = false, .text = "rethrows" },
    .{ .regex = false, .text = "return" },
    .{ .regex = false, .text = "set" },
    .{ .regex = false, .text = "some" },
    .{ .regex = false, .text = "static" },
    .{ .regex = false, .text = "struct" },
    .{ .regex = false, .text = "subscript" },
    .{ .regex = false, .text = "super" },
    .{ .regex = false, .text = "switch" },
    .{ .regex = false, .text = "throws" },
    .{ .regex = false, .text = "throw" },
    .{ .regex = true, .text = "try\\?" },
    .{ .regex = true, .text = "try!" },
    .{ .regex = false, .text = "try" },
    .{ .regex = false, .text = "typealias" },
    .{ .regex = true, .text = "unowned\\(safe\\)" },
    .{ .regex = true, .text = "unowned\\(unsafe\\)" },
    .{ .regex = false, .text = "unowned" },
    .{ .regex = false, .text = "var" },
    .{ .regex = false, .text = "weak" },
    .{ .regex = false, .text = "where" },
    .{ .regex = false, .text = "while" },
    .{ .regex = false, .text = "willSet" },
};
const literals = [_]Token{
    .{ .regex = false, .text = "false" },
    .{ .regex = false, .text = "nil" },
    .{ .regex = false, .text = "true" },
};
const precedencegroupKeywords = [_]Token{
    .{ .regex = false, .text = "assignment" },
    .{ .regex = false, .text = "associativity" },
    .{ .regex = false, .text = "higherThan" },
    .{ .regex = false, .text = "left" },
    .{ .regex = false, .text = "lowerThan" },
    .{ .regex = false, .text = "none" },
    .{ .regex = false, .text = "right" },
};
const numberSignKeywords = [_]Token{
    .{ .regex = false, .text = "#colorLiteral" },
    .{ .regex = false, .text = "#column" },
    .{ .regex = false, .text = "#dsohandle" },
    .{ .regex = false, .text = "#else" },
    .{ .regex = false, .text = "#elseif" },
    .{ .regex = false, .text = "#endif" },
    .{ .regex = false, .text = "#error" },
    .{ .regex = false, .text = "#file" },
    .{ .regex = false, .text = "#fileID" },
    .{ .regex = false, .text = "#fileLiteral" },
    .{ .regex = false, .text = "#filePath" },
    .{ .regex = false, .text = "#function" },
    .{ .regex = false, .text = "#if" },
    .{ .regex = false, .text = "#imageLiteral" },
    .{ .regex = false, .text = "#keyPath" },
    .{ .regex = false, .text = "#line" },
    .{ .regex = false, .text = "#selector" },
    .{ .regex = false, .text = "#sourceLocation" },
    .{ .regex = false, .text = "#warn_unqualified_access" },
    .{ .regex = false, .text = "#warning" },
};
const builtIns = [_]Token{
    .{ .regex = false, .text = "abs" },
    .{ .regex = false, .text = "all" },
    .{ .regex = false, .text = "any" },
    .{ .regex = false, .text = "assert" },
    .{ .regex = false, .text = "assertionFailure" },
    .{ .regex = false, .text = "debugPrint" },
    .{ .regex = false, .text = "dump" },
    .{ .regex = false, .text = "fatalError" },
    .{ .regex = false, .text = "getVaList" },
    .{ .regex = false, .text = "isKnownUniquelyReferenced" },
    .{ .regex = false, .text = "max" },
    .{ .regex = false, .text = "min" },
    .{ .regex = false, .text = "numericCast" },
    .{ .regex = false, .text = "pointwiseMax" },
    .{ .regex = false, .text = "pointwiseMin" },
    .{ .regex = false, .text = "precondition" },
    .{ .regex = false, .text = "preconditionFailure" },
    .{ .regex = false, .text = "print" },
    .{ .regex = false, .text = "readLine" },
    .{ .regex = false, .text = "repeatElement" },
    .{ .regex = false, .text = "sequence" },
    .{ .regex = false, .text = "stride" },
    .{ .regex = false, .text = "swap" },
    .{ .regex = false, .text = "swift_unboxFromSwiftValueWithType" },
    .{ .regex = false, .text = "transcode" },
    .{ .regex = false, .text = "type" },
    .{ .regex = false, .text = "unsafeBitCast" },
    .{ .regex = false, .text = "unsafeDowncast" },
    .{ .regex = false, .text = "withExtendedLifetime" },
    .{ .regex = false, .text = "withUnsafeMutablePointer" },
    .{ .regex = false, .text = "withUnsafePointer" },
    .{ .regex = false, .text = "withVaList" },
    .{ .regex = false, .text = "withoutActuallyEscaping" },
    .{ .regex = false, .text = "zip" },
};
const availabilityKeywords = [_]Token{
    .{ .regex = false, .text = "iOS" },
    .{ .regex = false, .text = "iOSApplicationExtension" },
    .{ .regex = false, .text = "macOS" },
    .{ .regex = false, .text = "macOSApplicationExtension" },
    .{ .regex = false, .text = "macCatalyst" },
    .{ .regex = false, .text = "macCatalystApplicationExtension" },
    .{ .regex = false, .text = "watchOS" },
    .{ .regex = false, .text = "watchOSApplicationExtension" },
    .{ .regex = false, .text = "tvOS" },
    .{ .regex = false, .text = "tvOSApplicationExtension" },
    .{ .regex = false, .text = "swift" },
};
const operatorHeadRanges = [_]Token{
    .{ .regex = true, .text = "[/=\\-+!*%<>&|^~?]" },
    .{ .regex = true, .text = "[\\u00A1-\\u00A7]" },
    .{ .regex = true, .text = "[\\u00A9\\u00AB]" },
    .{ .regex = true, .text = "[\\u00AC\\u00AE]" },
    .{ .regex = true, .text = "[\\u00B0\\u00B1]" },
    .{ .regex = true, .text = "[\\u00B6\\u00BB\\u00BF\\u00D7\\u00F7]" },
    .{ .regex = true, .text = "[\\u2016-\\u2017]" },
    .{ .regex = true, .text = "[\\u2020-\\u2027]" },
    .{ .regex = true, .text = "[\\u2030-\\u203E]" },
    .{ .regex = true, .text = "[\\u2041-\\u2053]" },
    .{ .regex = true, .text = "[\\u2055-\\u205E]" },
    .{ .regex = true, .text = "[\\u2190-\\u23FF]" },
    .{ .regex = true, .text = "[\\u2500-\\u2775]" },
    .{ .regex = true, .text = "[\\u2794-\\u2BFF]" },
    .{ .regex = true, .text = "[\\u2E00-\\u2E7F]" },
    .{ .regex = true, .text = "[\\u3001-\\u3003]" },
    .{ .regex = true, .text = "[\\u3008-\\u3020]" },
    .{ .regex = true, .text = "[\\u3030]" },
};
const operatorCharacterRanges = [_]Token{
    .{ .regex = true, .text = "[\\u0300-\\u036F]" },
    .{ .regex = true, .text = "[\\u1DC0-\\u1DFF]" },
    .{ .regex = true, .text = "[\\u20D0-\\u20FF]" },
    .{ .regex = true, .text = "[\\uFE00-\\uFE0F]" },
    .{ .regex = true, .text = "[\\uFE20-\\uFE2F]" },
};
const identifierHeadRanges = [_]Token{
    .{ .regex = true, .text = "[a-zA-Z_]" },
    .{ .regex = true, .text = "[\\u00A8\\u00AA\\u00AD\\u00AF\\u00B2-\\u00B5\\u00B7-\\u00BA]" },
    .{ .regex = true, .text = "[\\u00BC-\\u00BE\\u00C0-\\u00D6\\u00D8-\\u00F6\\u00F8-\\u00FF]" },
    .{ .regex = true, .text = "[\\u0100-\\u02FF\\u0370-\\u167F\\u1681-\\u180D\\u180F-\\u1DBF]" },
    .{ .regex = true, .text = "[\\u1E00-\\u1FFF]" },
    .{ .regex = true, .text = "[\\u200B-\\u200D\\u202A-\\u202E\\u203F-\\u2040\\u2054\\u2060-\\u206F]" },
    .{ .regex = true, .text = "[\\u2070-\\u20CF\\u2100-\\u218F\\u2460-\\u24FF\\u2776-\\u2793]" },
    .{ .regex = true, .text = "[\\u2C00-\\u2DFF\\u2E80-\\u2FFF]" },
    .{ .regex = true, .text = "[\\u3004-\\u3007\\u3021-\\u302F\\u3031-\\u303F\\u3040-\\uD7FF]" },
    .{ .regex = true, .text = "[\\uF900-\\uFD3D\\uFD40-\\uFDCF\\uFDF0-\\uFE1F\\uFE30-\\uFE44]" },
    .{ .regex = true, .text = "[\\uFE47-\\uFEFE\\uFF00-\\uFFFD]" },
};
const identifierCharacterRanges = [_]Token{
    .{ .regex = true, .text = "\\d" },
    .{ .regex = true, .text = "[\\u0300-\\u036F\\u1DC0-\\u1DFF\\u20D0-\\u20FF\\uFE20-\\uFE2F]" },
};
const js = @import("native_js_values.zig");
extern "c" fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
fn list(s: *Scope, values: []const c.JSValue) !c.JSValue {
    const result = try s.array();
    for (values, 0..) |value, index| try s.index(result, @intCast(index), value);
    return result;
}
fn literal(s: *Scope, text: []const u8) !c.JSValue {
    var args = [_]c.JSValue{try s.text(text)};
    return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, args.len, &args)));
}
fn mode(s: *Scope, name: []const u8) !c.JSValue {
    const result = try s.object();
    try s.put(result, "className", try s.text(name));
    return result;
}
fn tokens(s: *Scope, values: []const Token) !c.JSValue {
    const result = try s.array();
    for (values, 0..) |value, index| try s.index(result, @intCast(index), if (value.regex) try literal(s, value.text) else try s.text(value.text));
    return result;
}
fn sourceCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return @import("native_highlight_regex.zig").source(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_sdk.zig").fail(engine, err);
}
fn joined(s: *Scope, args: []const c.JSValue, separator: []const u8) !c.JSValue {
    const values = try list(s, args);
    const fn_value = try s.own(try s.engine.checked(c.JS_NewCFunction(s.engine.context, sourceCallback, "", 1)));
    return s.invoke(try s.invoke(values, "map", &.{fn_value}), "join", &.{try s.text(separator)});
}
fn concat(s: *Scope, args: []const c.JSValue) !c.JSValue {
    return joined(s, args, "");
}
fn either(s: *Scope, args: []const c.JSValue) !c.JSValue {
    return s.concat(try s.concat(try s.text("("), try joined(s, args, "|")), try s.text(")"));
}
fn append(s: *Scope, result: c.JSValue, index: *u32, value: c.JSValue) !void {
    try s.index(result, index.*, value);
    index.* += 1;
}
fn spread(s: *Scope, result: c.JSValue, index: *u32, value: c.JSValue) !void {
    const symbol = try s.own(try s.engine.checked(JS_GetIteratorSymbol(s.engine.context)));
    var iterator = try js.Iterator.init(s.engine, value, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |item| {
        defer s.engine.freeValue(item);
        try append(s, result, index, item);
    }
}
fn eitherSpread(s: *Scope, value: c.JSValue) !c.JSValue {
    const values = try s.array();
    var count: u32 = 0;
    try spread(s, values, &count, value);
    const args = try s.engine.gpa.alloc(c.JSValue, count);
    defer s.engine.gpa.free(args);
    for (args, 0..) |*slot, index| slot.* = try s.own(try s.engine.checked(c.JS_GetPropertyUint32(s.engine.context, values, @intCast(index))));
    return either(s, args);
}
fn combine(s: *Scope, a: c.JSValue, b: c.JSValue) !c.JSValue {
    const result = try s.array();
    var index: u32 = 0;
    try spread(s, result, &index, a);
    try spread(s, result, &index, b);
    return result;
}
fn keywordCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return wrapKeyword(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_sdk.zig").fail(engine, err);
}
fn wrapKeyword(engine: *em.Engine, value: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const starts = try literal(&s, "\\b");
    const matched = try s.invoke(try literal(&s, "\\w$"), "test", &.{value});
    const end = try literal(&s, if (s.truthy(matched)) "\\b" else "\\B");
    return c.JS_DupValue(engine.context, try concat(&s, &.{ starts, value, end }));
}
fn filterCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    return c.pi_js_bool(context, @intFromBool(c.JS_IsString(if (argc > 0) argv[0] else c.pi_js_undefined()) == (magic == 0)));
}
fn findInterpol(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return findInterpolValue(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_sdk.zig").fail(engine, err);
}
fn findInterpolValue(engine: *em.Engine, value: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    return c.pi_js_bool(engine.context, @intFromBool(s.equal(try s.get(value, "label"), try s.text("interpol"))));
}
fn rangesEither(s: *Scope, ranges: []const Token, head: ?c.JSValue) !c.JSValue {
    const values = try tokens(s, ranges);
    const args = try s.engine.gpa.alloc(c.JSValue, ranges.len + @as(usize, if (head != null) 1 else 0));
    defer s.engine.gpa.free(args);
    var offset: usize = 0;
    if (head) |value| {
        args[0] = value;
        offset = 1;
    }
    for (ranges, 0..) |_, index| args[offset + index] = try s.own(try s.engine.checked(c.JS_GetPropertyUint32(s.engine.context, values, @intCast(index))));
    return either(s, args);
}
fn moduleState(s: *Scope) !c.JSValue {
    const state = try s.object();
    const wrapper = try s.own(try s.engine.checked(c.JS_NewCFunction(s.engine.context, keywordCallback, "keywordWrapper", 1)));
    try s.put(state, "dotKeywords", try s.invoke(try tokens(s, &dotKeywords), "map", &.{wrapper}));
    try s.put(state, "optionalDotKeywords", try s.invoke(try tokens(s, &optionalDotKeywords), "map", &.{wrapper}));
    try s.put(state, "keywordTypes", try tokens(s, &keywordTypes));
    try s.put(state, "keywords", try tokens(s, &keywords));
    try s.put(state, "literals", try tokens(s, &literals));
    try s.put(state, "precedencegroupKeywords", try tokens(s, &precedencegroupKeywords));
    try s.put(state, "numberSignKeywords", try tokens(s, &numberSignKeywords));
    try s.put(state, "builtIns", try tokens(s, &builtIns));
    const op_head = try rangesEither(s, &operatorHeadRanges, null);
    const op_chars = try rangesEither(s, &operatorCharacterRanges, op_head);
    try s.put(state, "operatorCharacter", op_chars);
    try s.put(state, "operator", try concat(s, &.{ op_head, op_chars, try s.text("*") }));
    const id_head = try rangesEither(s, &identifierHeadRanges, null);
    const id_chars = try rangesEither(s, &identifierCharacterRanges, id_head);
    try s.put(state, "identifierCharacter", id_chars);
    try s.put(state, "identifier", try concat(s, &.{ id_head, id_chars, try s.text("*") }));
    try s.put(state, "typeIdentifier", try concat(s, &.{ try literal(s, "[A-Z]"), id_chars, try s.text("*") }));
    const attrs = try s.array();
    try s.index(attrs, 0, try s.text("autoclosure"));
    try s.index(attrs, 1, try concat(s, &.{ try literal(s, "convention\\("), try either(s, &.{ try s.text("swift"), try s.text("block"), try s.text("c") }), try literal(s, "\\)") }));
    const names = [_][]const u8{ "discardableResult", "dynamicCallable", "dynamicMemberLookup", "escaping", "frozen", "GKInspectable", "IBAction", "IBDesignable", "IBInspectable", "IBOutlet", "IBSegueAction", "inlinable", "main", "nonobjc", "NSApplicationMain", "NSCopying", "NSManaged" };
    for (names, 0..) |name, index| try s.index(attrs, @intCast(index + 2), try s.text(name));
    try s.index(attrs, 19, try concat(s, &.{ try literal(s, "objc\\("), try s.get(state, "identifier"), try literal(s, "\\)") }));
    const tail = [_][]const u8{ "objc", "objcMembers", "propertyWrapper", "requires_stored_property_inits", "testable", "UIApplicationMain", "unknown", "usableFromInline" };
    for (tail, 0..) |name, index| try s.index(attrs, @intCast(index + 20), try s.text(name));
    try s.put(state, "keywordAttributes", attrs);
    try s.put(state, "availabilityKeywords", try tokens(s, &availabilityKeywords));
    try s.put(state, "keywordWrapper", wrapper);
    return state;
}
pub fn create(engine: *em.Engine) !c.JSValue {
    const module = "pi-native:highlight-swift-module";
    if (!engine.native_module_values.contains(module)) {
        var s: Scope = .{ .engine = engine };
        defer s.deinit();
        const state = try moduleState(&s);
        const Adapter = struct {
            fn invoke(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
                return build(host, if (args.len > 0) args[0] else c.pi_js_undefined(), roots[0]);
            }
        };
        const exports = try s.object();
        try s.put(exports, "factory", try s.own(try ordinary.create(engine, "swift", 1, Adapter.invoke, &.{state})));
        try engine.registerValueModule(module, exports);
    }
    return @import("native_sdk.zig").get(engine, engine.native_module_values.get(module).?, "factory");
}
fn escapeCharacter(s: *Scope, raw: c.JSValue) !c.JSValue {
    const result = try mode(s, "subst");
    const one = try s.object();
    try s.put(one, "match", try concat(s, &.{ try literal(s, "\\\\"), raw, try literal(s, "[0\\\\tnr\"']") }));
    const two = try s.object();
    try s.put(two, "match", try concat(s, &.{ try literal(s, "\\\\"), raw, try literal(s, "u\\{[0-9a-fA-F]{1,8}\\}") }));
    try s.put(result, "variants", try list(s, &.{ one, two }));
    return result;
}
fn stringVariant(s: *Scope, raw: c.JSValue, multiline: bool) !c.JSValue {
    const result = try s.object();
    try s.put(result, "begin", try concat(s, &.{ raw, try literal(s, if (multiline) "\"\"\"" else "\"") }));
    try s.put(result, "end", try concat(s, &.{ try literal(s, if (multiline) "\"\"\"" else "\""), raw }));
    const children = try s.array();
    try s.index(children, 0, try escapeCharacter(s, raw));
    var index: u32 = 1;
    if (multiline) {
        const newline = try mode(s, "subst");
        try s.put(newline, "match", try concat(s, &.{ try literal(s, "\\\\"), raw, try literal(s, "[\\t ]*(?:[\\r\\n]|\\r\\n)") }));
        try s.index(children, index, newline);
        index += 1;
    }
    const interpol = try mode(s, "subst");
    try s.put(interpol, "label", try s.text("interpol"));
    try s.put(interpol, "begin", try concat(s, &.{ try literal(s, "\\\\"), raw, try literal(s, "\\(") }));
    try s.put(interpol, "end", try literal(s, "\\)"));
    try s.index(children, index, interpol);
    try s.put(result, "contains", children);
    return result;
}
pub fn build(engine: *em.Engine, hljs: c.JSValue, state: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const whitespace = try s.object();
    try s.put(whitespace, "match", try literal(&s, "\\s+"));
    try s.put(whitespace, "relevance", c.JS_NewInt32(engine.context, 0));
    const comment_fn = try s.get(hljs, "COMMENT");
    const comment_options = try s.object();
    try s.put(comment_options, "contains", try list(&s, &.{try s.text("self")}));
    const block_comment = try s.call(comment_fn, hljs, &.{ try s.text("/\\*"), try s.text("\\*/"), comment_options });
    const comments = try list(&s, &.{ try s.get(hljs, "C_LINE_COMMENT_MODE"), block_comment });
    const dot = try mode(&s, "keyword");
    try s.put(dot, "begin", try concat(&s, &.{ try literal(&s, "\\."), try concat(&s, &.{ try s.text("(?="), try eitherSpread(&s, try combine(&s, try s.get(state, "dotKeywords"), try s.get(state, "optionalDotKeywords"))), try s.text(")") }) }));
    try s.put(dot, "end", try eitherSpread(&s, try combine(&s, try s.get(state, "dotKeywords"), try s.get(state, "optionalDotKeywords"))));
    try s.put(dot, "excludeBegin", c.pi_js_bool(engine.context, 1));
    const keyword_guard = try s.object();
    try s.put(keyword_guard, "match", try concat(&s, &.{ try literal(&s, "\\."), try eitherSpread(&s, try s.get(state, "keywords")) }));
    try s.put(keyword_guard, "relevance", c.JS_NewInt32(engine.context, 0));
    const plain_filter = try s.own(try engine.checked(c.pi_js_function_magic(engine.context, filterCallback, "", 1, 0)));
    const regex_filter = try s.own(try engine.checked(c.pi_js_function_magic(engine.context, filterCallback, "", 1, 1)));
    const plain = try s.invoke(try s.invoke(try s.get(state, "keywords"), "filter", &.{plain_filter}), "concat", &.{try list(&s, &.{try s.text("_|0")})});
    const regex_keywords = try s.invoke(try s.invoke(try s.invoke(try s.get(state, "keywords"), "filter", &.{regex_filter}), "concat", &.{try s.get(state, "keywordTypes")}), "map", &.{try s.get(state, "keywordWrapper")});
    const keyword = try s.object();
    const keyword_variant = try mode(&s, "keyword");
    try s.put(keyword_variant, "match", try eitherSpread(&s, try combine(&s, regex_keywords, try s.get(state, "optionalDotKeywords"))));
    try s.put(keyword, "variants", try list(&s, &.{keyword_variant}));
    const keywords_value = try s.object();
    try s.put(keywords_value, "$pattern", try either(&s, &.{ try literal(&s, "\\b\\w+"), try literal(&s, "#\\w+") }));
    try s.put(keywords_value, "keyword", try s.invoke(plain, "concat", &.{try s.get(state, "numberSignKeywords")}));
    try s.put(keywords_value, "literal", try s.get(state, "literals"));
    const keyword_modes = try list(&s, &.{ dot, keyword_guard, keyword });
    const builtin_guard = try s.object();
    try s.put(builtin_guard, "match", try concat(&s, &.{ try literal(&s, "\\."), try eitherSpread(&s, try s.get(state, "builtIns")) }));
    try s.put(builtin_guard, "relevance", c.JS_NewInt32(engine.context, 0));
    const builtin = try mode(&s, "built_in");
    try s.put(builtin, "match", try concat(&s, &.{ try literal(&s, "\\b"), try eitherSpread(&s, try s.get(state, "builtIns")), try literal(&s, "(?=\\()") }));
    const builtins = try list(&s, &.{ builtin_guard, builtin });
    const operator_guard = try s.object();
    try s.put(operator_guard, "match", try literal(&s, "->"));
    try s.put(operator_guard, "relevance", c.JS_NewInt32(engine.context, 0));
    const operator_mode = try mode(&s, "operator");
    try s.put(operator_mode, "relevance", c.JS_NewInt32(engine.context, 0));
    const op1 = try s.object();
    try s.put(op1, "match", try s.get(state, "operator"));
    const op2 = try s.object();
    try s.put(op2, "match", try s.concat(try s.concat(try s.text("\\.(\\.|"), try s.stringify(try s.get(state, "operatorCharacter"))), try s.text(")+")));
    try s.put(operator_mode, "variants", try list(&s, &.{ op1, op2 }));
    const operators = try list(&s, &.{ operator_guard, operator_mode });
    const decimal = "([0-9]_*)+";
    const hex = "([0-9a-fA-F]_*)+";
    const number = try mode(&s, "number");
    try s.put(number, "relevance", c.JS_NewInt32(engine.context, 0));
    const number_variants = try s.array();
    const decimal_mode = try s.object();
    try s.put(decimal_mode, "match", try s.text("\\b(" ++ decimal ++ ")(\\.(" ++ decimal ++ "))?([eE][+-]?(" ++ decimal ++ "))?\\b"));
    try s.index(number_variants, 0, decimal_mode);
    const hex_mode = try s.object();
    try s.put(hex_mode, "match", try s.text("\\b0x(" ++ hex ++ ")(\\.(" ++ hex ++ "))?([pP][+-]?(" ++ decimal ++ "))?\\b"));
    try s.index(number_variants, 1, hex_mode);
    inline for (.{ "\\b0o([0-7]_*)+\\b", "\\b0b([01]_*)+\\b" }, 0..) |pattern, index| {
        const variant = try s.object();
        try s.put(variant, "match", try literal(&s, pattern));
        try s.index(number_variants, index + 2, variant);
    }
    try s.put(number, "variants", number_variants);
    const string = try mode(&s, "string");
    const variants = try s.array();
    inline for (.{ "", "#", "##", "###" }, 0..) |raw, index| try s.index(variants, index, try stringVariant(&s, try s.text(raw), true));
    inline for (.{ "", "#", "##", "###" }, 0..) |raw, index| try s.index(variants, index + 4, try stringVariant(&s, try s.text(raw), false));
    try s.put(string, "variants", variants);
    const quoted_identifier = try s.object();
    try s.put(quoted_identifier, "match", try concat(&s, &.{ try literal(&s, "`"), try s.get(state, "identifier"), try literal(&s, "`") }));
    const implicit = try mode(&s, "variable");
    try s.put(implicit, "match", try literal(&s, "\\$\\d+"));
    const projection = try mode(&s, "variable");
    try s.put(projection, "match", try s.concat(try s.concat(try s.text("\\$"), try s.stringify(try s.get(state, "identifierCharacter"))), try s.text("+")));
    const identifiers = try list(&s, &.{ quoted_identifier, implicit, projection });
    const available = try s.object();
    try s.put(available, "match", try literal(&s, "(@|#)available"));
    try s.put(available, "className", try s.text("keyword"));
    const available_starts = try s.object();
    const available_parens = try s.object();
    try s.put(available_parens, "begin", try literal(&s, "\\("));
    try s.put(available_parens, "end", try literal(&s, "\\)"));
    try s.put(available_parens, "keywords", try s.get(state, "availabilityKeywords"));
    const availability_contains = try s.array();
    var index: u32 = 0;
    try spread(&s, availability_contains, &index, operators);
    try append(&s, availability_contains, &index, number);
    try append(&s, availability_contains, &index, string);
    try s.put(available_parens, "contains", availability_contains);
    try s.put(available_starts, "contains", try list(&s, &.{available_parens}));
    try s.put(available, "starts", available_starts);
    const keyword_attribute = try mode(&s, "keyword");
    try s.put(keyword_attribute, "match", try concat(&s, &.{ try literal(&s, "@"), try eitherSpread(&s, try s.get(state, "keywordAttributes")) }));
    const user_attribute = try mode(&s, "meta");
    try s.put(user_attribute, "match", try concat(&s, &.{ try literal(&s, "@"), try s.get(state, "identifier") }));
    const attributes = try list(&s, &.{ available, keyword_attribute, user_attribute });
    const type_mode = try s.object();
    try s.put(type_mode, "match", try concat(&s, &.{ try s.text("(?="), try literal(&s, "\\b[A-Z]"), try s.text(")") }));
    try s.put(type_mode, "relevance", c.JS_NewInt32(engine.context, 0));
    const type_contains = try s.array();
    const apple = try mode(&s, "type");
    try s.put(apple, "match", try concat(&s, &.{ try literal(&s, "(AV|CA|CF|CG|CI|CL|CM|CN|CT|MK|MP|MTK|MTL|NS|SCN|SK|UI|WK|XC)"), try s.get(state, "identifierCharacter"), try s.text("+") }));
    try s.index(type_contains, 0, apple);
    const type_identifier = try mode(&s, "type");
    try s.put(type_identifier, "match", try s.get(state, "typeIdentifier"));
    try s.put(type_identifier, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(type_contains, 1, type_identifier);
    inline for (.{ "[?!]+", "\\.\\.\\." }, 0..) |pattern, i| {
        const part = try s.object();
        try s.put(part, "match", try literal(&s, pattern));
        try s.put(part, "relevance", c.JS_NewInt32(engine.context, 0));
        try s.index(type_contains, i + 2, part);
    }
    const composition = try s.object();
    try s.put(composition, "match", try concat(&s, &.{ try literal(&s, "\\s+&\\s+"), try concat(&s, &.{ try s.text("(?="), try s.get(state, "typeIdentifier"), try s.text(")") }) }));
    try s.put(composition, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(type_contains, 4, composition);
    try s.put(type_mode, "contains", type_contains);
    const generic = try s.object();
    try s.put(generic, "begin", try literal(&s, "<"));
    try s.put(generic, "end", try literal(&s, ">"));
    try s.put(generic, "keywords", keywords_value);
    const generic_contains = try s.array();
    index = 0;
    try spread(&s, generic_contains, &index, comments);
    try spread(&s, generic_contains, &index, keyword_modes);
    try spread(&s, generic_contains, &index, attributes);
    try append(&s, generic_contains, &index, operator_guard);
    try append(&s, generic_contains, &index, type_mode);
    try s.put(generic, "contains", generic_contains);
    _ = try s.invoke(try s.get(type_mode, "contains"), "push", &.{generic});
    const tuple_name = try s.object();
    try s.put(tuple_name, "match", try concat(&s, &.{ try s.get(state, "identifier"), try literal(&s, "\\s*:") }));
    try s.put(tuple_name, "keywords", try s.text("_|0"));
    try s.put(tuple_name, "relevance", c.JS_NewInt32(engine.context, 0));
    const tuple = try s.object();
    try s.put(tuple, "begin", try literal(&s, "\\("));
    try s.put(tuple, "end", try literal(&s, "\\)"));
    try s.put(tuple, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.put(tuple, "keywords", keywords_value);
    const tuple_contains = try s.array();
    index = 0;
    try append(&s, tuple_contains, &index, try s.text("self"));
    try append(&s, tuple_contains, &index, tuple_name);
    try spread(&s, tuple_contains, &index, comments);
    try spread(&s, tuple_contains, &index, keyword_modes);
    try spread(&s, tuple_contains, &index, builtins);
    try spread(&s, tuple_contains, &index, operators);
    try append(&s, tuple_contains, &index, number);
    try append(&s, tuple_contains, &index, string);
    try spread(&s, tuple_contains, &index, identifiers);
    try spread(&s, tuple_contains, &index, attributes);
    try append(&s, tuple_contains, &index, type_mode);
    try s.put(tuple, "contains", tuple_contains);
    return finish(&s, hljs, state, whitespace, comments, keyword_modes, builtins, operators, operator_guard, number, string, identifiers, attributes, type_mode, tuple, quoted_identifier, keywords_value);
}
fn finish(s: *Scope, hljs: c.JSValue, state: c.JSValue, whitespace: c.JSValue, comments: c.JSValue, keyword_modes: c.JSValue, builtins: c.JSValue, operators: c.JSValue, operator_guard: c.JSValue, number: c.JSValue, string: c.JSValue, identifiers: c.JSValue, attributes: c.JSValue, type_mode: c.JSValue, tuple: c.JSValue, quoted_identifier: c.JSValue, keywords_value: c.JSValue) !c.JSValue {
    const engine = s.engine;
    const func_title = try s.object();
    try s.put(func_title, "beginKeywords", try s.text("func"));
    const function_title = try mode(s, "title");
    try s.put(function_title, "match", try either(s, &.{ try s.get(quoted_identifier, "match"), try s.get(state, "identifier"), try s.get(state, "operator") }));
    try s.put(function_title, "endsParent", c.pi_js_bool(engine.context, 1));
    try s.put(function_title, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.put(func_title, "contains", try list(s, &.{ function_title, whitespace }));
    const generics = try s.object();
    try s.put(generics, "begin", try literal(s, "<"));
    try s.put(generics, "end", try literal(s, ">"));
    const generic_children = try s.array();
    var index: u32 = 0;
    try spread(s, generic_children, &index, comments);
    try append(s, generic_children, &index, type_mode);
    try s.put(generics, "contains", generic_children);
    const parameter_name = try s.object();
    try s.put(parameter_name, "begin", try either(s, &.{ try concat(s, &.{ try s.text("(?="), try concat(s, &.{ try s.get(state, "identifier"), try literal(s, "\\s*:") }), try s.text(")") }), try concat(s, &.{ try s.text("(?="), try concat(s, &.{ try s.get(state, "identifier"), try literal(s, "\\s+"), try s.get(state, "identifier"), try literal(s, "\\s*:") }), try s.text(")") }) }));
    try s.put(parameter_name, "end", try literal(s, ":"));
    try s.put(parameter_name, "relevance", c.JS_NewInt32(engine.context, 0));
    const wildcard = try mode(s, "keyword");
    try s.put(wildcard, "match", try literal(s, "\\b_\\b"));
    const name = try mode(s, "params");
    try s.put(name, "match", try s.get(state, "identifier"));
    try s.put(parameter_name, "contains", try list(s, &.{ wildcard, name }));
    const params = try s.object();
    try s.put(params, "begin", try literal(s, "\\("));
    try s.put(params, "end", try literal(s, "\\)"));
    try s.put(params, "keywords", keywords_value);
    const param_children = try s.array();
    index = 0;
    try append(s, param_children, &index, parameter_name);
    try spread(s, param_children, &index, comments);
    try spread(s, param_children, &index, keyword_modes);
    try spread(s, param_children, &index, operators);
    try append(s, param_children, &index, number);
    try append(s, param_children, &index, string);
    try spread(s, param_children, &index, attributes);
    try append(s, param_children, &index, type_mode);
    try append(s, param_children, &index, tuple);
    try s.put(params, "contains", param_children);
    try s.put(params, "endsParent", c.pi_js_bool(engine.context, 1));
    try s.put(params, "illegal", try literal(s, "[\"']"));
    const function = try mode(s, "function");
    try s.put(function, "match", try concat(s, &.{ try s.text("(?="), try literal(s, "\\bfunc\\b"), try s.text(")") }));
    try s.put(function, "contains", try list(s, &.{ func_title, generics, params, whitespace }));
    try s.put(function, "illegal", try list(s, &.{ try literal(s, "\\["), try literal(s, "%") }));
    const init = try mode(s, "function");
    try s.put(init, "match", try literal(s, "\\b(subscript|init[?!]?)\\s*(?=[<(])"));
    const init_keywords = try s.object();
    try s.put(init_keywords, "keyword", try s.text("subscript init init? init!"));
    try s.put(init_keywords, "$pattern", try literal(s, "\\w+[?!]?"));
    try s.put(init, "keywords", init_keywords);
    try s.put(init, "contains", try list(s, &.{ generics, params, whitespace }));
    try s.put(init, "illegal", try literal(s, "\\[|%"));
    const operator_declaration = try s.object();
    try s.put(operator_declaration, "beginKeywords", try s.text("operator"));
    try s.put(operator_declaration, "end", try s.get(hljs, "MATCH_NOTHING_RE"));
    const operator_title = try mode(s, "title");
    try s.put(operator_title, "match", try s.get(state, "operator"));
    try s.put(operator_title, "endsParent", c.pi_js_bool(engine.context, 1));
    try s.put(operator_title, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.put(operator_declaration, "contains", try list(s, &.{operator_title}));
    const precedence = try s.object();
    try s.put(precedence, "beginKeywords", try s.text("precedencegroup"));
    try s.put(precedence, "end", try s.get(hljs, "MATCH_NOTHING_RE"));
    const precedence_title = try mode(s, "title");
    try s.put(precedence_title, "match", try s.get(state, "typeIdentifier"));
    try s.put(precedence_title, "relevance", c.JS_NewInt32(engine.context, 0));
    const precedence_body = try s.object();
    try s.put(precedence_body, "begin", try literal(s, "{"));
    try s.put(precedence_body, "end", try literal(s, "}"));
    try s.put(precedence_body, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.put(precedence_body, "endsParent", c.pi_js_bool(engine.context, 1));
    try s.put(precedence_body, "keywords", try combine(s, try s.get(state, "precedencegroupKeywords"), try s.get(state, "literals")));
    try s.put(precedence_body, "contains", try list(s, &.{type_mode}));
    try s.put(precedence, "contains", try list(s, &.{ precedence_title, precedence_body }));
    // Real for-of interleaves each variant's find/mutation with iterator.next.
    const symbol = try s.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
    var iterator = try js.Iterator.init(engine, try s.get(string, "variants"), symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |variant| {
        defer engine.freeValue(variant);
        const predicate = try s.own(try engine.checked(c.JS_NewCFunction(engine.context, findInterpol, "", 1)));
        const interpolation = try s.invoke(try s.get(variant, "contains"), "find", &.{predicate});
        try s.set(interpolation, "keywords", keywords_value);
        const submodes = try s.array();
        index = 0;
        try spread(s, submodes, &index, keyword_modes);
        try spread(s, submodes, &index, builtins);
        try spread(s, submodes, &index, operators);
        try append(s, submodes, &index, number);
        try append(s, submodes, &index, string);
        try spread(s, submodes, &index, identifiers);
        const interpolation_children = try s.array();
        index = 0;
        try spread(s, interpolation_children, &index, submodes);
        const nested = try s.object();
        try s.put(nested, "begin", try literal(s, "\\("));
        try s.put(nested, "end", try literal(s, "\\)"));
        const nested_children = try s.array();
        var nested_index: u32 = 0;
        try append(s, nested_children, &nested_index, try s.text("self"));
        try spread(s, nested_children, &nested_index, submodes);
        try s.put(nested, "contains", nested_children);
        try append(s, interpolation_children, &index, nested);
        try s.set(interpolation, "contains", interpolation_children);
    }
    const language = try s.object();
    try s.put(language, "name", try s.text("Swift"));
    try s.put(language, "keywords", keywords_value);
    const contains = try s.array();
    index = 0;
    try spread(s, contains, &index, comments);
    try append(s, contains, &index, function);
    try append(s, contains, &index, init);
    const class_mode = try mode(s, "class");
    try s.put(class_mode, "beginKeywords", try s.text("struct protocol class extension enum"));
    try s.put(class_mode, "end", try s.text("\\{"));
    try s.put(class_mode, "excludeEnd", c.pi_js_bool(engine.context, 1));
    try s.put(class_mode, "keywords", keywords_value);
    const class_children = try s.array();
    var class_index: u32 = 0;
    const inherit = try s.get(hljs, "inherit");
    const title_base = try s.get(hljs, "TITLE_MODE");
    const changes = try s.object();
    try s.put(changes, "begin", try literal(s, "[A-Za-z$_][\\u00C0-\\u02B80-9A-Za-z$_]*"));
    try append(s, class_children, &class_index, try s.call(inherit, hljs, &.{ title_base, changes }));
    try spread(s, class_children, &class_index, keyword_modes);
    try s.put(class_mode, "contains", class_children);
    try append(s, contains, &index, class_mode);
    try append(s, contains, &index, operator_declaration);
    try append(s, contains, &index, precedence);
    const import = try s.object();
    try s.put(import, "beginKeywords", try s.text("import"));
    try s.put(import, "end", try literal(s, "$"));
    const import_children = try s.array();
    var import_index: u32 = 0;
    try spread(s, import_children, &import_index, comments);
    try s.put(import, "contains", import_children);
    try s.put(import, "relevance", c.JS_NewInt32(engine.context, 0));
    try append(s, contains, &index, import);
    try spread(s, contains, &index, keyword_modes);
    try spread(s, contains, &index, builtins);
    try spread(s, contains, &index, operators);
    try append(s, contains, &index, number);
    try append(s, contains, &index, string);
    try spread(s, contains, &index, identifiers);
    try spread(s, contains, &index, attributes);
    try append(s, contains, &index, type_mode);
    try append(s, contains, &index, tuple);
    try s.put(language, "contains", contains);
    return c.JS_DupValue(engine.context, language);
}
