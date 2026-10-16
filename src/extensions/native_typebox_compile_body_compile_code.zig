//! Direct native bodies from pinned typebox@1.3.27. Source-only pending qualification.
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const o = @import("native_typebox_compile_ops.zig");
const ordinary = @import("native_node_function.zig");
const class = @import("native_class.zig");
const sdk = @import("native_sdk.zig");
const c = js.c;
const Engine = js.Engine;
pub fn prepare(e: *Engine, graph: c.JSValue) !void {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const modules = try s.get(graph, "modules");
    const namespace = try s.get(modules, "compile/code.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "compile/code.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "compile/code.mjs", bindings);
    const v10 = try s.own(try ordinary.create(e, "TsIgnore", 0, body8, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1", v10);
    const v13 = try s.own(try ordinary.create(e, "Separator", 0, body11, &.{ graph, frame }));
    try o.assign(&s, frame, "binding2", v13);
    const v42 = try s.own(try ordinary.create(e, "ImportSection", 1, body14, &.{ graph, frame }));
    try o.assign(&s, frame, "binding3", v42);
    const v75 = try s.own(try ordinary.create(e, "ExternalSection", 1, body43, &.{ graph, frame }));
    try o.assign(&s, frame, "binding4", v75);
    const v106 = try s.own(try ordinary.create(e, "FunctionSection", 1, body76, &.{ graph, frame }));
    try o.assign(&s, frame, "binding5", v106);
    const v147 = try s.own(try ordinary.create(e, "ExportSection", 1, body107, &.{ graph, frame }));
    try o.assign(&s, frame, "binding6", v147);
    const v217 = try s.own(try ordinary.create(e, "Code", 0, body148, &.{ graph, frame }));
    try o.assign(&s, frame, "binding7", v217);
    const v218 = try o.lookup(&s, frame, "binding7");
    try s.put(namespace, "Code", v218);
    const v219 = try o.lookup(&s, frame, "binding7");
    try s.put(namespace, "Code", v219);
    try s.put(bindings, "Code", try s.text("binding7"));
}
fn body8(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v9 = try s.text("// @ts-ignore");
    return c.JS_DupValue(e.context, v9);
}
fn body11(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v12 = try s.text("");
    return c.JS_DupValue(e.context, v12);
}
fn body14(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v20 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding15", v20);
    const v25 = try o.lookup(&s, frame, "binding15");
    const v26 = try s.text("UseUnevaluated");
    const v27 = try s.own(try js.getKey(e, v25, v26));
    const v28 = try s.call(v27, v25, &.{});
    const v30 = conditional29: {
        if (s.truthy(v28)) {
            const v31 = try s.array();
            const v32 = try s.text("import { CheckContext } from \"typebox/schema\"");
            try o.append(&s, v31, v32);
            break :conditional29 v31;
        } else {
            const v33 = try s.array();
            break :conditional29 v33;
        }
    };
    try o.assign(&s, frame, "binding21", v30);
    const v34 = try s.text("import { Hashing } from \"typebox/system\"");
    try o.assign(&s, frame, "binding22", v34);
    const v35 = try s.text("import { Format } from \"typebox/format\"");
    try o.assign(&s, frame, "binding23", v35);
    const v36 = try s.text("import { Guard } from \"typebox/guard\"");
    try o.assign(&s, frame, "binding24", v36);
    const v37 = try s.array();
    const v38 = try o.lookup(&s, frame, "binding21");
    try o.spreadArray(&s, v37, v38);
    const v39 = try o.lookup(&s, frame, "binding22");
    try o.append(&s, v37, v39);
    const v40 = try o.lookup(&s, frame, "binding23");
    try o.append(&s, v37, v40);
    const v41 = try o.lookup(&s, frame, "binding24");
    try o.append(&s, v37, v41);
    return c.JS_DupValue(e.context, v37);
}
fn body43(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v46 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding44", v46);
    const v48 = try o.lookup(&s, frame, "binding44");
    const v49 = try s.text("External");
    const v50 = try s.own(try js.getKey(e, v48, v49));
    const v51 = try s.call(v50, v48, &.{});
    const v52 = try s.text("identifier");
    const v53 = try s.own(try js.getKey(e, v51, v52));
    try o.assign(&s, frame, "binding47", v53);
    const v54 = try s.array();
    const v55 = try o.lookup(&s, frame, "binding2");
    const v56 = try s.call(v55, c.pi_js_undefined(), &.{});
    try o.append(&s, v54, v56);
    const v57 = try o.lookup(&s, frame, "binding1");
    const v58 = try s.call(v57, c.pi_js_undefined(), &.{});
    try o.append(&s, v54, v58);
    const v59 = try s.text("let ");
    const v60 = try o.lookup(&s, frame, "binding47");
    const v61 = try s.stringify(v60);
    const v62 = try s.concat(v59, v61);
    const v63 = try s.text(" = []");
    const v64 = try s.concat(v62, v63);
    try o.append(&s, v54, v64);
    const v65 = try o.lookup(&s, frame, "binding2");
    const v66 = try s.call(v65, c.pi_js_undefined(), &.{});
    try o.append(&s, v54, v66);
    const v67 = try o.lookup(&s, frame, "binding1");
    const v68 = try s.call(v67, c.pi_js_undefined(), &.{});
    try o.append(&s, v54, v68);
    const v69 = try s.text("export function SetExternal(external) { ");
    const v70 = try o.lookup(&s, frame, "binding47");
    const v71 = try s.stringify(v70);
    const v72 = try s.concat(v69, v71);
    const v73 = try s.text(" = external.variables }");
    const v74 = try s.concat(v72, v73);
    try o.append(&s, v54, v74);
    return c.JS_DupValue(e.context, v54);
}
fn body85(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v88 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding87", v88);
    const v89 = try s.array();
    const v90 = try o.lookup(&s, frame, "binding2");
    const v91 = try s.call(v90, c.pi_js_undefined(), &.{});
    try o.append(&s, v89, v91);
    const v92 = try o.lookup(&s, frame, "binding1");
    const v93 = try s.call(v92, c.pi_js_undefined(), &.{});
    try o.append(&s, v89, v93);
    const v94 = try s.text("");
    const v95 = try o.lookup(&s, frame, "binding87");
    const v96 = try s.stringify(v95);
    const v97 = try s.concat(v94, v96);
    const v98 = try s.text(";");
    const v99 = try s.concat(v97, v98);
    try o.append(&s, v89, v99);
    const v100 = try s.text("join");
    const v101 = try s.own(try js.getKey(e, v89, v100));
    const v102 = try s.text("\n");
    const v103 = try s.call(v101, v89, &.{v102});
    return c.JS_DupValue(e.context, v103);
}
fn body85C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body85(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body76(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v78 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding77", v78);
    const v79 = try o.lookup(&s, frame, "binding77");
    const v80 = try s.text("Functions");
    const v81 = try s.own(try js.getKey(e, v79, v80));
    const v82 = try s.call(v81, v79, &.{});
    const v83 = try s.text("map");
    const v84 = try s.own(try js.getKey(e, v82, v83));
    const v104 = try o.arrow(&s, "", 1, body85C, &.{ graph, frame });
    const v105 = try s.call(v84, v82, &.{v104});
    return c.JS_DupValue(e.context, v105);
}
fn body107(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v110 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding108", v110);
    const v112 = try o.lookup(&s, frame, "binding108");
    const v113 = try s.text("UseUnevaluated");
    const v114 = try s.own(try js.getKey(e, v112, v113));
    const v115 = try s.call(v114, v112, &.{});
    const v117 = conditional116: {
        if (s.truthy(v115)) {
            const v118 = try s.text("const context = new CheckContext({}, {}); return ");
            const v119 = try o.lookup(&s, frame, "binding108");
            const v120 = try s.text("Entry");
            const v121 = try s.own(try js.getKey(e, v119, v120));
            const v122 = try s.call(v121, v119, &.{});
            const v123 = try s.stringify(v122);
            const v124 = try s.concat(v118, v123);
            const v125 = try s.text("");
            const v126 = try s.concat(v124, v125);
            break :conditional116 v126;
        } else {
            const v127 = try s.text("return ");
            const v128 = try o.lookup(&s, frame, "binding108");
            const v129 = try s.text("Entry");
            const v130 = try s.own(try js.getKey(e, v128, v129));
            const v131 = try s.call(v130, v128, &.{});
            const v132 = try s.stringify(v131);
            const v133 = try s.concat(v127, v132);
            const v134 = try s.text("");
            const v135 = try s.concat(v133, v134);
            break :conditional116 v135;
        }
    };
    try o.assign(&s, frame, "binding111", v117);
    const v136 = try s.array();
    const v137 = try o.lookup(&s, frame, "binding2");
    const v138 = try s.call(v137, c.pi_js_undefined(), &.{});
    try o.append(&s, v136, v138);
    const v139 = try o.lookup(&s, frame, "binding1");
    const v140 = try s.call(v139, c.pi_js_undefined(), &.{});
    try o.append(&s, v136, v140);
    const v141 = try s.text("export function Check(value) { ");
    const v142 = try o.lookup(&s, frame, "binding111");
    const v143 = try s.stringify(v142);
    const v144 = try s.concat(v141, v143);
    const v145 = try s.text(" }");
    const v146 = try s.concat(v144, v145);
    try o.append(&s, v136, v146);
    return c.JS_DupValue(e.context, v136);
}
fn body165(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v169 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding167", v169);
    const v170 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding168", v170);
    const v171 = try s.array();
    const v172 = try o.lookup(&s, frame, "binding167");
    try o.append(&s, v171, v172);
    const v173 = try o.lookup(&s, frame, "binding168");
    try o.append(&s, v171, v173);
    return c.JS_DupValue(e.context, v171);
}
fn body165C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body165(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body176(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v179 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding178", v179);
    const v180 = try s.array();
    const v181 = try s.object();
    try o.append(&s, v180, v181);
    const v182 = try o.lookup(&s, frame, "binding178");
    try o.append(&s, v180, v182);
    return c.JS_DupValue(e.context, v180);
}
fn body176C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body176(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body148(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v154 = try o.rest(&s, args, 0);
    try o.assign(&s, frame, "binding149", v154);
    const v159 = try o.importValue(&s, graph, "system/arguments/index.mjs", "Arguments");
    const v160 = try s.text("Match");
    const v161 = try s.own(try js.getKey(e, v159, v160));
    const v162 = try o.lookup(&s, frame, "binding149");
    const v163 = try s.object();
    const v164 = try s.text("2");
    const v174 = try o.arrow(&s, "2", 2, body165C, &.{ graph, frame });
    try o.defineKey(&s, v163, v164, v174);
    const v175 = try s.text("1");
    const v183 = try o.arrow(&s, "1", 1, body176C, &.{ graph, frame });
    try o.defineKey(&s, v163, v175, v183);
    const v184 = try s.call(v161, v159, &.{ v162, v163 });
    var destructure185 = try o.iterator(e, v184);
    defer destructure185.deinit();
    errdefer destructure185.closePreserving();
    const v186 = try s.own(if (destructure185.closed) c.pi_js_undefined() else (try destructure185.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding155", v186);
    const v187 = try s.own(if (destructure185.closed) c.pi_js_undefined() else (try destructure185.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding156", v187);
    try destructure185.close();
    const v188 = try o.importValue(&s, graph, "schema/index.mjs", "Build");
    const v189 = try o.lookup(&s, frame, "binding155");
    const v190 = try o.lookup(&s, frame, "binding156");
    const v191 = try s.call(v188, c.pi_js_undefined(), &.{ v189, v190 });
    try o.assign(&s, frame, "binding157", v191);
    const v192 = try s.array();
    const v193 = try o.lookup(&s, frame, "binding3");
    const v194 = try o.lookup(&s, frame, "binding157");
    const v195 = try s.call(v193, c.pi_js_undefined(), &.{v194});
    try o.spreadArray(&s, v192, v195);
    const v196 = try o.lookup(&s, frame, "binding4");
    const v197 = try o.lookup(&s, frame, "binding157");
    const v198 = try s.call(v196, c.pi_js_undefined(), &.{v197});
    try o.spreadArray(&s, v192, v198);
    const v199 = try o.lookup(&s, frame, "binding5");
    const v200 = try o.lookup(&s, frame, "binding157");
    const v201 = try s.call(v199, c.pi_js_undefined(), &.{v200});
    try o.spreadArray(&s, v192, v201);
    const v202 = try o.lookup(&s, frame, "binding6");
    const v203 = try o.lookup(&s, frame, "binding157");
    const v204 = try s.call(v202, c.pi_js_undefined(), &.{v203});
    try o.spreadArray(&s, v192, v204);
    const v205 = try s.text("join");
    const v206 = try s.own(try js.getKey(e, v192, v205));
    const v207 = try s.text("\n");
    const v208 = try s.call(v206, v192, &.{v207});
    try o.assign(&s, frame, "binding158", v208);
    const v209 = try s.object();
    const v210 = try s.text("External");
    const v211 = try o.lookup(&s, frame, "binding157");
    const v212 = try s.text("External");
    const v213 = try s.own(try js.getKey(e, v211, v212));
    const v214 = try s.call(v213, v211, &.{});
    try o.defineKey(&s, v209, v210, v214);
    const v215 = try s.text("Code");
    const v216 = try o.lookup(&s, frame, "binding158");
    try o.defineKey(&s, v209, v215, v216);
    return c.JS_DupValue(e.context, v209);
}
