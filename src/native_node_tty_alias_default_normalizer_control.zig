//! Prepared differential caller control: linked C DEFAULT normalizer first,
//! then actual alias-aware normalization on the SAME registered user inputs.
//! Requires fresh real Engine/private TTY exports; no replacement builtin.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
fn token(engine: *v.em.Engine, source: []const u8, filename: [:0]const u8) !c.JSValue {
    const namespace = try engine.evalModule(source, filename); defer engine.freeValue(namespace);
    return engine.checked(c.JS_GetPropertyStr(engine.context, namespace, "actual"));
}
pub fn run(engine: *v.em.Engine, actual_tty_exports: c.JSValue) !void {
    try std.testing.expect(engine.source_loader == null and engine.native_builtin_aliases.count() == 0);
    try engine.registerModule("fixture/leaf.mjs", "export const actual = 'genuine-parent-user-input';");
    try engine.registerModule("fixture/deep/nested/../leaf.mjs", "export const actual = 'genuine-leading-only-user-input';");
    const parent_source = "export { actual } from '../leaf.mjs';";
    const leading_only_source = "export { actual } from './nested/../leaf.mjs';";
    const before_parent = try token(engine, parent_source, "fixture/deep/before-parent.mjs"); defer engine.freeValue(before_parent);
    const before_internal = try token(engine, leading_only_source, "fixture/deep/before-internal.mjs"); defer engine.freeValue(before_internal);
    try engine.registerValueModule("node:tty", actual_tty_exports);
    try engine.registerBuiltinAlias("tty", "node:tty");
    const after_parent = try token(engine, parent_source, "fixture/deep/after-parent.mjs"); defer engine.freeValue(after_parent);
    const after_internal = try token(engine, leading_only_source, "fixture/deep/after-internal.mjs"); defer engine.freeValue(after_internal);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, before_parent, after_parent));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, before_internal, after_internal));
    const namespaces = try engine.evalModule("import * as a from 'tty'; import * as b from 'node:tty'; export const same = a === b;", "fixture/alias-after-default.mjs"); defer engine.freeValue(namespaces);
    const same = try engine.checked(c.JS_GetPropertyStr(engine.context, namespaces, "same")); defer engine.freeValue(same);
    try std.testing.expect(c.JS_ToBool(engine.context, same) == 1);
}
