//! Additive unrun original comparison. No replacement of the frozen313 input
//! or original five native controls, and no authored expected JSON.
const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const c = em.c;
test "native jiti pathe compares six additional original literal order and iterator observations" {
    const expected = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "src/extensions/fixtures/jiti-pathe-2.0.3-supplement.json", std.testing.allocator, .limited(1024 * 1024)); defer std.testing.allocator.free(expected);
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const bindings = try @import("extensions/native_pathe.zig").create(engine); defer engine.freeValue(bindings);
    const subject = try js.object(engine); defer engine.freeValue(subject);
    try js.define(engine, subject, "path", c.JS_DupValue(engine.context, bindings)); try js.define(engine, subject, "utils", c.JS_DupValue(engine.context, bindings));
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    try js.define(engine, global, "nativePatheSubject", c.JS_DupValue(engine.context, subject));
    const terminated = try engine.gpa.dupeZ(u8, expected); defer engine.gpa.free(terminated);
    try js.define(engine, global, "originalPatheSupplement", try engine.checked(c.JS_ParseJSON(engine.context, terminated.ptr, expected.len, "actual-pathe-supplement.json")));
    const value = try engine.evalModule(@embedFile("extensions/fixtures/jiti-pathe-2.0.3-supplement.input.mjs") ++
        \\if(nativePatheSupplementObservation.count!==6||originalPatheSupplement.count!==6)throw Error('Full supplemental census required');for(let i=0;i<6;i++)if(JSON.stringify(nativePatheSupplementObservation.rows[i])!==JSON.stringify(originalPatheSupplement.rows[i]))throw Error(JSON.stringify({index:i,actual:nativePatheSupplementObservation.rows[i],original:originalPatheSupplement.rows[i]}));
    , "native-jiti-pathe-supplement.mjs"); engine.freeValue(value);
}
