//! Actual highlight.js 10.7.3 static keyword inputs; native factory follows.
const b = @import("native_highlight_lazy_batch3_values.zig");
const re = @import("native_highlight_regex.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "llvm", build);
}
pub fn build(e: *b.Engine, h: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const ident = try b.rx(&s, "([-a-zA-Z$._][\\w$.-]*)");
    const type_mode = try b.mode(&s, "type");
    try s.put(type_mode, "begin", try b.rx(&s, "\\bi\\d+(?=\\s|\\b)"));
    const operator = try b.mode(&s, "operator");
    try s.put(operator, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.put(operator, "begin", try b.rx(&s, "="));
    const punctuation = try b.mode(&s, "punctuation");
    try s.put(punctuation, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.put(punctuation, "begin", try b.rx(&s, ","));
    const num = try b.mode(&s, "number");
    const nv = try s.array();
    for ([_][]const u8{ "0[xX][a-fA-F0-9]+", "-?\\d+(?:[.]\\d+)?(?:[eE][-+]?\\d+(?:[.]\\d+)?)?" }, 0..) |p, i| {
        const m = try s.object();
        try s.put(m, "begin", try b.rx(&s, p));
        try s.index(nv, @intCast(i), m);
    }
    try s.put(num, "variants", nv);
    try s.put(num, "relevance", b.c.JS_NewInt32(e.context, 0));
    const label = try b.mode(&s, "symbol");
    const lm = try s.object();
    try s.put(lm, "begin", try b.rx(&s, "^\\s*[a-z]+:"));
    try s.put(label, "variants", try b.list(&s, &.{lm}));
    try s.put(label, "relevance", b.c.JS_NewInt32(e.context, 0));
    const variable = try b.mode(&s, "variable");
    const vv = try s.array();
    const v1 = try s.object();
    const percent = try b.rx(&s, "%");
    try s.put(v1, "begin", try s.own(try re.concat(e, try b.list(&s, &.{ percent, ident }))));
    try s.index(vv, 0, v1);
    for ([_][]const u8{ "%\\d+", "#\\d+" }, 1..) |p, i| {
        const m = try s.object();
        try s.put(m, "begin", try b.rx(&s, p));
        try s.index(vv, @intCast(i), m);
    }
    try s.put(variable, "variants", vv);
    const function = try b.mode(&s, "title");
    const fv = try s.array();
    const f1 = try s.object();
    const at = try b.rx(&s, "@");
    try s.put(f1, "begin", try s.own(try re.concat(e, try b.list(&s, &.{ at, ident }))));
    try s.index(fv, 0, f1);
    const f2 = try s.object();
    try s.put(f2, "begin", try b.rx(&s, "@\\d+"));
    try s.index(fv, 1, f2);
    for ([_][]const u8{ "!", "!\\d+" }, 2..) |p, i| {
        const m = try s.object();
        const prefix = try b.rx(&s, p);
        try s.put(m, "begin", try s.own(try re.concat(e, try b.list(&s, &.{ prefix, ident }))));
        try s.index(fv, @intCast(i), m);
    }
    const f5 = try s.object();
    try s.put(f5, "begin", try b.rx(&s, "!\\d+"));
    try s.index(fv, 4, f5);
    try s.put(function, "variants", fv);
    const l = try s.object();
    try s.put(l, "name", try s.text("LLVM IR"));
    try s.put(l, "keywords", try s.text(source_text));
    const a = try b.list(&s, &.{type_mode});
    const c1 = try s.get(h, "COMMENT");
    const b1 = try b.rx(&s, ";\\s*$");
    const o1 = try s.object();
    try s.put(o1, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.index(a, 1, try s.call(c1, h, &.{ b1, b.c.pi_js_null(), o1 }));
    const c2 = try s.get(h, "COMMENT");
    const b2 = try b.rx(&s, ";");
    const e2 = try b.rx(&s, "$");
    try s.index(a, 2, try s.call(c2, h, &.{ b2, e2 }));
    try s.index(a, 3, try s.get(h, "QUOTE_STRING_MODE"));
    const str = try b.mode(&s, "string");
    const sm = try s.object();
    try s.put(sm, "begin", try b.rx(&s, "\""));
    try s.put(sm, "end", try b.rx(&s, "[^\\\\]\""));
    try s.put(str, "variants", try b.list(&s, &.{sm}));
    try s.index(a, 4, str);
    try s.index(a, 5, function);
    try s.index(a, 6, punctuation);
    try s.index(a, 7, operator);
    try s.index(a, 8, variable);
    try s.index(a, 9, label);
    try s.index(a, 10, num);
    try s.put(l, "contains", a);
    return b.c.JS_DupValue(e.context, l);
}
const source_text = "begin end true false declare define global constant private linker_private internal available_externally linkonce linkonce_odr weak weak_odr appending dllimport dllexport common default hidden protected extern_weak external thread_local zeroinitializer undef null to tail target triple datalayout volatile nuw nsw nnan ninf nsz arcp fast exact inbounds align addrspace section alias module asm sideeffect gc dbg linker_private_weak attributes blockaddress initialexec localdynamic localexec prefix unnamed_addr ccc fastcc coldcc x86_stdcallcc x86_fastcallcc arm_apcscc arm_aapcscc arm_aapcs_vfpcc ptx_device ptx_kernel intel_ocl_bicc msp430_intrcc spir_func spir_kernel x86_64_sysvcc x86_64_win64cc x86_thiscallcc cc c signext zeroext inreg sret nounwind noreturn noalias nocapture byval nest readnone readonly inlinehint noinline alwaysinline optsize ssp sspreq noredzone noimplicitfloat naked builtin cold nobuiltin noduplicate nonlazybind optnone returns_twice sanitize_address sanitize_memory sanitize_thread sspstrong uwtable returned type opaque eq ne slt sgt sle sge ult ugt ule uge oeq one olt ogt ole oge ord uno ueq une x acq_rel acquire alignstack atomic catch cleanup filter inteldialect max min monotonic nand personality release seq_cst singlethread umax umin unordered xchg add fadd sub fsub mul fmul udiv sdiv fdiv urem srem frem shl lshr ashr and or xor icmp fcmp phi call trunc zext sext fptrunc fpext uitofp sitofp fptoui fptosi inttoptr ptrtoint bitcast addrspacecast select va_arg ret br switch invoke unwind unreachable indirectbr landingpad resume malloc alloca free load store getelementptr extractelement insertelement shufflevector getresult extractvalue insertvalue atomicrmw cmpxchg fence argmemonly double";
