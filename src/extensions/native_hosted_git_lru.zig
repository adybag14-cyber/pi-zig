//! Pinned lru-cache 11.4.0 default max=1000 used lifecycle. Actual retained
//! VM Map methods remain live; numeric slots and callback ordering match Source.
//! No public/configurable/TTL/disposal/diagnostics LRU API is manufactured.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope; const c = v.c;
const data = @import("native_sdk_package_data.zig");
const arithmetic = @import("native_image_arithmetic.zig");
fn field(s: *Scope, owner: c.JSValue, name: [*:0]const u8) !c.JSValue { return s.get(owner, name); }
fn put(s: *Scope, owner: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void { try data.put(s.engine, owner, name, value); }
fn at(s: *Scope, list: c.JSValue, index: c.JSValue) !c.JSValue { return s.own(try v.js.getKey(s.engine, list, index)); }
fn assignAtom(s: *Scope, list: c.JSValue, atom: c.JSAtom, value: c.JSValue) !void { if (c.JS_SetProperty(s.engine.context, list, atom, c.JS_DupValue(s.engine.context, value)) < 0) return v.js.capture(s.engine); }
fn assign(s: *Scope, list: c.JSValue, index: c.JSValue, value: c.JSValue) !void { const atom = try v.js.atom(s.engine, index); defer c.JS_FreeAtom(s.engine.context, atom); try assignAtom(s, list, atom, value); }
fn invokeIgnored(s: *Scope, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !void { const result = try v.js.invoke(s.engine, receiver, name, args); s.engine.freeValue(result); }
fn adjust(s: *Scope, owner: c.JSValue, name: [*:0]const u8, increase: bool) !c.JSValue { const value = try s.own(try arithmetic.binary(s.engine, if (increase) .add else .subtract, try field(s, owner, name), c.JS_NewInt32(s.engine.context, 1))); try put(s, owner, name, value); return value; }
fn zero(s: *Scope, value: c.JSValue) bool { return s.equal(value, c.JS_NewInt32(s.engine.context, 0)); }
fn construct(s: *Scope, constructor: c.JSValue, args: []const c.JSValue) !c.JSValue { return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, constructor, @intCast(args.len), @constCast(args.ptr)))); }
fn list(s: *Scope) !c.JSValue { const array = try s.global("Array"); const from = try s.get(array, "from"); const length = try s.object(); try data.put(s.engine, length, "length", c.JS_NewInt32(s.engine.context, 1000)); const value = try s.call(from, array, &.{length}); return s.invoke(value, "fill", &.{c.pi_js_undefined()}); }
pub fn create(engine: *v.em.Engine) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const owner = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    // The source chooses the uint constructor before new Map, and chooses
    // again when creating the free stack after next/prev allocation.
    const uint = try s.global("Uint16Array"); const map_constructor = try s.global("Map"); const map = try construct(&s, map_constructor, &.{}); try put(&s, owner, "map", map);
    try put(&s, owner, "keys", try list(&s)); try put(&s, owner, "values", try list(&s)); var max = [_]c.JSValue{c.JS_NewInt32(engine.context, 1000)}; try put(&s, owner, "next", try construct(&s, uint, &max)); try put(&s, owner, "prev", try construct(&s, uint, &max)); try put(&s, owner, "head", c.JS_NewInt32(engine.context, 0)); try put(&s, owner, "tail", c.JS_NewInt32(engine.context, 0)); try put(&s, owner, "freeHeap", try construct(&s, try s.global("Uint16Array"), &max)); try put(&s, owner, "freeLength", c.JS_NewInt32(engine.context, 0)); try put(&s, owner, "size", c.JS_NewInt32(engine.context, 0)); return c.JS_DupValue(engine.context, owner);
}
fn connect(s: *Scope, owner: c.JSValue, previous: c.JSValue, next: c.JSValue) !void { try assign(s, try field(s, owner, "prev"), next, previous); try assign(s, try field(s, owner, "next"), previous, next); }
fn moveTail(s: *Scope, owner: c.JSValue, index: c.JSValue) !void {
    if (!s.equal(index, try field(s, owner, "tail"))) { if (s.equal(index, try field(s, owner, "head"))) try put(s, owner, "head", try at(s, try field(s, owner, "next"), index))
        else { const previous = try at(s, try field(s, owner, "prev"), index); const next = try at(s, try field(s, owner, "next"), index); try connect(s, owner, previous, next); }
        try connect(s, owner, try field(s, owner, "tail"), index); try put(s, owner, "tail", index);
    }
}
pub fn has(engine: *v.em.Engine, owner: c.JSValue, key: c.JSValue) !bool {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const index = try s.invoke(try field(&s, owner, "map"), "get", &.{key}); if (c.JS_IsUndefined(index)) return false;
    // Even though default background-fetch/TTL are absent, preserve the raw
    // array read and its property-key conversion before returning true.
    _ = try at(&s, try field(&s, owner, "values"), index); return true;
}
pub fn get(engine: *v.em.Engine, owner: c.JSValue, key: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const index = try s.invoke(try field(&s, owner, "map"), "get", &.{key}); if (c.JS_IsUndefined(index)) return c.pi_js_undefined(); const value = try at(&s, try field(&s, owner, "values"), index); try moveTail(&s, owner, index); return c.JS_DupValue(engine.context, value);
}
fn pushFree(s: *Scope, owner: c.JSValue, index: c.JSValue) !void { const heap = try field(s, owner, "freeHeap"); const length = try field(s, owner, "freeLength"); _ = try adjust(s, owner, "freeLength", true); try assign(s, heap, length, index); }
fn popFree(s: *Scope, owner: c.JSValue) !c.JSValue { const heap = try field(s, owner, "freeHeap"); const length = try adjust(s, owner, "freeLength", false); return at(s, heap, length); }
fn evict(engine: *v.em.Engine, owner: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const head = try field(&s, owner, "head"); const key = try at(&s, try field(&s, owner, "keys"), head); _ = try at(&s, try field(&s, owner, "values"), head);
    if (s.equal(try field(&s, owner, "size"), c.JS_NewInt32(engine.context, 1))) { try put(&s, owner, "head", c.JS_NewInt32(engine.context, 0)); try put(&s, owner, "tail", c.JS_NewInt32(engine.context, 0)); try put(&s, owner, "freeLength", c.JS_NewInt32(engine.context, 0)); }
    else try put(&s, owner, "head", try at(&s, try field(&s, owner, "next"), head));
    try invokeIgnored(&s, try field(&s, owner, "map"), "delete", &.{key}); _ = try adjust(&s, owner, "size", false); return c.JS_DupValue(engine.context, head);
}
fn validIndex(engine: *v.em.Engine, owner: c.JSValue, index: c.JSValue) !bool { if (c.JS_IsUndefined(index)) return false; var s: Scope = .{ .engine = engine }; defer s.deinit(); const map = try field(&s, owner, "map"); const method = try s.get(map, "get"); const key = try at(&s, try field(&s, owner, "keys"), index); return s.equal(try s.call(method, map, &.{key}), index); }
fn clear(s: *Scope, owner: c.JSValue) !void {
    // Source #rindexes validates each slot through another live Map.get,
    // including the last slot, before #clear calls Map.clear.
    if (s.truthy(try field(s, owner, "size"))) {
        var index = try field(s, owner, "head"); var steps: usize = 0;
        while (true) {
            steps +|= 1; if (s.engine.cancelled.load(.acquire) or (steps % 256 == 0 and blk: { s.engine.interrupts +|= 1; break :blk s.engine.interrupts > s.engine.options.interrupt_budget; })) { _ = try s.engine.checked(c.JS_ThrowInternalError(s.engine.context, "interrupted")); unreachable; }
            if (!try validIndex(s.engine, owner, index)) break;
            { var local: Scope = .{ .engine = s.engine }; defer local.deinit(); _ = try at(&local, try field(&local, owner, "values"), index); _ = try at(&local, try field(&local, owner, "keys"), index); }
            if (s.equal(index, try field(s, owner, "tail"))) break; index = try at(s, try field(s, owner, "next"), index);
        }
    }
    try invokeIgnored(s, try field(s, owner, "map"), "clear", &.{}); try invokeIgnored(s, try field(s, owner, "values"), "fill", &.{c.pi_js_undefined()}); try invokeIgnored(s, try field(s, owner, "keys"), "fill", &.{c.pi_js_undefined()}); try put(s, owner, "head", c.JS_NewInt32(s.engine.context, 0)); try put(s, owner, "tail", c.JS_NewInt32(s.engine.context, 0)); try put(s, owner, "freeLength", c.JS_NewInt32(s.engine.context, 0)); try put(s, owner, "size", c.JS_NewInt32(s.engine.context, 0));
}
fn remove(s: *Scope, owner: c.JSValue, key: c.JSValue) !void {
    if (zero(s, try field(s, owner, "size"))) return; const index = try s.invoke(try field(s, owner, "map"), "get", &.{key}); if (c.JS_IsUndefined(index)) return;
    if (s.equal(try field(s, owner, "size"), c.JS_NewInt32(s.engine.context, 1))) return clear(s, owner);
    _ = try at(s, try field(s, owner, "values"), index); try invokeIgnored(s, try field(s, owner, "map"), "delete", &.{key}); try assign(s, try field(s, owner, "keys"), index, c.pi_js_undefined()); try assign(s, try field(s, owner, "values"), index, c.pi_js_undefined());
    if (s.equal(index, try field(s, owner, "tail"))) try put(s, owner, "tail", try at(s, try field(s, owner, "prev"), index))
    else if (s.equal(index, try field(s, owner, "head"))) try put(s, owner, "head", try at(s, try field(s, owner, "next"), index))
    else {
        const previous = try at(s, try field(s, owner, "prev"), index);
        { const list_value = try field(s, owner, "next"); const atom = try v.js.atom(s.engine, previous); defer c.JS_FreeAtom(s.engine.context, atom); try assignAtom(s, list_value, atom, try at(s, try field(s, owner, "next"), index)); }
        const next = try at(s, try field(s, owner, "next"), index);
        { const list_value = try field(s, owner, "prev"); const atom = try v.js.atom(s.engine, next); defer c.JS_FreeAtom(s.engine.context, atom); try assignAtom(s, list_value, atom, try at(s, try field(s, owner, "prev"), index)); }
    }
    _ = try adjust(s, owner, "size", false); try pushFree(s, owner, index);
}
pub fn set(engine: *v.em.Engine, owner: c.JSValue, key: c.JSValue, value: c.JSValue) !void {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); if (c.JS_IsUndefined(value)) return remove(&s, owner, key);
    var index = if (zero(&s, try field(&s, owner, "size"))) c.pi_js_undefined() else try s.invoke(try field(&s, owner, "map"), "get", &.{key});
    if (c.JS_IsUndefined(index)) {
        index = if (zero(&s, try field(&s, owner, "size"))) try field(&s, owner, "tail") else if (!zero(&s, try field(&s, owner, "freeLength"))) try popFree(&s, owner) else if (s.equal(try field(&s, owner, "size"), c.JS_NewInt32(engine.context, 1000))) try s.own(try evict(engine, owner)) else try field(&s, owner, "size");
        try assign(&s, try field(&s, owner, "keys"), index, key); try assign(&s, try field(&s, owner, "values"), index, value);
        try invokeIgnored(&s, try field(&s, owner, "map"), "set", &.{ key, index });
        try assign(&s, try field(&s, owner, "next"), try field(&s, owner, "tail"), index);
        { const previous = try field(&s, owner, "prev"); const atom = try v.js.atom(engine, index); defer c.JS_FreeAtom(engine.context, atom); try assignAtom(&s, previous, atom, try field(&s, owner, "tail")); }
        try put(&s, owner, "tail", index); _ = try adjust(&s, owner, "size", true);
    } else { try moveTail(&s, owner, index); const previous = try at(&s, try field(&s, owner, "values"), index); if (!s.equal(value, previous)) try assign(&s, try field(&s, owner, "values"), index, value); }
}
