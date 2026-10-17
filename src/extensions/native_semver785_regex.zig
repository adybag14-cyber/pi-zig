//! Exact strict/default patterns used by node-semver7.8.5 internal/re.js.
//! Patterns execute in the existing native VM; no semver JavaScript is loaded.
const em = @import("engine.zig");
const Scope = @import("native_semver785_scope.zig").Scope;
const ops = @import("native_semver785_ops.zig");
const c = em.c;
const numeric = "0|[1-9]\\d{0,256}";
const nonnumeric = "\\d{0,256}[a-zA-Z-][a-zA-Z0-9-]{0,250}";
const identifier = "(?:" ++ nonnumeric ++ "|" ++ numeric ++ ")";
const prerelease = "(?:-(" ++ identifier ++ "(?:\\." ++ identifier ++ ")*))";
const build_safe = "(?:\\+([a-zA-Z0-9-]{1,250}(?:\\.[a-zA-Z0-9-]{1,250})*))";
const build_raw = "(?:\\+([a-zA-Z0-9-]+(?:\\.[a-zA-Z0-9-]+)*))";
const full_plain = "v?(" ++ numeric ++ ")\\.(" ++ numeric ++ ")\\.(" ++ numeric ++ ")" ++ prerelease ++ "?" ++ build_safe ++ "?";
const loose_prerelease_identifier = "(?:" ++ nonnumeric ++ "|\\d{1,256})";
const loose_prerelease = "(?:-?(" ++ loose_prerelease_identifier ++ "(?:\\." ++ loose_prerelease_identifier ++ ")*))";
const loose_plain = "[v=\\s]*(\\d{1,256})\\.(\\d{1,256})\\.(\\d{1,256})" ++ loose_prerelease ++ "?" ++ build_safe ++ "?";
const xrange_identifier = numeric ++ "|x|X|\\*";
const xrange_plain = "[v=\\s]*(" ++ xrange_identifier ++ ")(?:\\.(" ++ xrange_identifier ++ ")(?:\\.(" ++ xrange_identifier ++ ")(?:" ++ prerelease ++ ")?" ++ build_safe ++ "?)?)?";
const gtlt = "((?:<|>)?=?)";
pub fn create(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    errdefer |err| scope.failed(err);
    const result = try scope.plain();
    inline for (.{
        .{ "FULL", "^" ++ full_plain ++ "$", "" },
        .{ "NUMERIC", "^[0-9]+$", "" },
        .{ "SPACE", "\\s+", "g" },
        .{ "SPLIT_SPACE", "\\s+", "" },
        .{ "BUILDSTRIP", build_raw, "g" },
        .{ "BUILD", build_safe, "" },
        .{ "HYPHEN", "^\\s{0,1}(" ++ xrange_plain ++ ")\\s{1,1}-\\s{1,1}(" ++ xrange_plain ++ ")\\s{0,1}$", "" },
        .{ "COMPARATORTRIM", "(\\s{0,1})" ++ gtlt ++ "\\s{0,1}(" ++ loose_plain ++ "|" ++ xrange_plain ++ ")", "g" },
        .{ "TILDETRIM", "(\\s{0,1})(?:~>?)\\s{1,1}", "g" },
        .{ "CARETTRIM", "(\\s{0,1})(?:\\^)\\s{1,1}", "g" },
        .{ "CARET", "^(?:\\^)" ++ xrange_plain ++ "$", "" },
        .{ "TILDE", "^(?:~>?)" ++ xrange_plain ++ "$", "" },
        .{ "XRANGE", "^" ++ gtlt ++ "\\s{0,1}" ++ xrange_plain ++ "$", "" },
        .{ "STAR", "(<|>)?=?\\s{0,1}\\*", "" },
        .{ "GTE0", "^\\s{0,1}>=\\s{0,1}0\\.0\\.0\\s{0,1}$", "" },
        .{ "COMPARATOR", "^" ++ gtlt ++ "\\s{0,1}(" ++ full_plain ++ ")$|^$", "" },
    }) |entry| {
        const regex = try scope.builtin("RegExp", &.{ try scope.text(entry[1]), try scope.text(entry[2]) });
        try ops.put(&scope, result, entry[0], regex);
    }
    return c.JS_DupValue(engine.context, result);
}
