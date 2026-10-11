//! Native translation of Node24/V8 JSLocale::StartsWithUnicodeLanguageId.
//! This checks the initial Unicode language ID; ICU must parse the full tag.
//! Upstream source: deps/v8/src/objects/js-locale.cc, BSD-3-Clause.
const std = @import("std");
fn alpha(value: []const u8, min: usize, max: usize) bool {
    if (value.len < min or value.len > max) return false;
    for (value) |byte| if (!std.ascii.isAlphabetic(byte)) return false;
    return true;
}
fn digit(value: []const u8, min: usize, max: usize) bool {
    if (value.len < min or value.len > max) return false;
    for (value) |byte| if (!std.ascii.isDigit(byte)) return false;
    return true;
}
fn alnum(value: []const u8, min: usize, max: usize) bool {
    if (value.len < min or value.len > max) return false;
    for (value) |byte| if (!std.ascii.isAlphanumeric(byte)) return false;
    return true;
}
pub fn startsWithUnicodeLanguageId(tag: []const u8) bool {
    if (tag.len == 0) return false;
    // std::getline does not produce a final empty token after a delimiter.
    const input = if (tag[tag.len - 1] == '-') tag[0 .. tag.len - 1] else tag;
    var tokens = std.mem.splitScalar(u8, input, '-');
    const language = tokens.next() orelse return false;
    if (!alpha(language, 2, 3) and !alpha(language, 5, 8)) return false;
    var token = tokens.next() orelse return true;
    if (alnum(token, 1, 1)) return true;
    if (alpha(token, 4, 4)) token = tokens.next() orelse return true;
    if (alpha(token, 2, 2) or digit(token, 3, 3)) token = tokens.next() orelse return true;
    while (true) {
        if (alnum(token, 1, 1)) return true;
        if (!alnum(token, 5, 8) and !(token.len == 4 and std.ascii.isDigit(token[0]) and alnum(token[1..], 3, 3))) return false;
        token = tokens.next() orelse return true;
    }
}
