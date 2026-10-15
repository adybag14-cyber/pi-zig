//! Actual highlight.js 10.7.3 factory operations; source-only until separately qualified.
const b = @import("native_highlight_lazy_batch3_values.zig");
const h = @import("native_highlight_lazy_batch9_helpers.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "handlebars", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const v1 = try s.object();
    const v2 = try s.array();
    var v3: u32 = 0;
    const v4 = try s.text("action");
    try s.index(v2, v3, v4);
    v3 += 1;
    const v5 = try s.text("bindattr");
    try s.index(v2, v3, v5);
    v3 += 1;
    const v6 = try s.text("collection");
    try s.index(v2, v3, v6);
    v3 += 1;
    const v7 = try s.text("component");
    try s.index(v2, v3, v7);
    v3 += 1;
    const v8 = try s.text("concat");
    try s.index(v2, v3, v8);
    v3 += 1;
    const v9 = try s.text("debugger");
    try s.index(v2, v3, v9);
    v3 += 1;
    const v10 = try s.text("each");
    try s.index(v2, v3, v10);
    v3 += 1;
    const v11 = try s.text("each-in");
    try s.index(v2, v3, v11);
    v3 += 1;
    const v12 = try s.text("get");
    try s.index(v2, v3, v12);
    v3 += 1;
    const v13 = try s.text("hash");
    try s.index(v2, v3, v13);
    v3 += 1;
    const v14 = try s.text("if");
    try s.index(v2, v3, v14);
    v3 += 1;
    const v15 = try s.text("in");
    try s.index(v2, v3, v15);
    v3 += 1;
    const v16 = try s.text("input");
    try s.index(v2, v3, v16);
    v3 += 1;
    const v17 = try s.text("link-to");
    try s.index(v2, v3, v17);
    v3 += 1;
    const v18 = try s.text("loc");
    try s.index(v2, v3, v18);
    v3 += 1;
    const v19 = try s.text("log");
    try s.index(v2, v3, v19);
    v3 += 1;
    const v20 = try s.text("lookup");
    try s.index(v2, v3, v20);
    v3 += 1;
    const v21 = try s.text("mut");
    try s.index(v2, v3, v21);
    v3 += 1;
    const v22 = try s.text("outlet");
    try s.index(v2, v3, v22);
    v3 += 1;
    const v23 = try s.text("partial");
    try s.index(v2, v3, v23);
    v3 += 1;
    const v24 = try s.text("query-params");
    try s.index(v2, v3, v24);
    v3 += 1;
    const v25 = try s.text("render");
    try s.index(v2, v3, v25);
    v3 += 1;
    const v26 = try s.text("template");
    try s.index(v2, v3, v26);
    v3 += 1;
    const v27 = try s.text("textarea");
    try s.index(v2, v3, v27);
    v3 += 1;
    const v28 = try s.text("unbound");
    try s.index(v2, v3, v28);
    v3 += 1;
    const v29 = try s.text("unless");
    try s.index(v2, v3, v29);
    v3 += 1;
    const v30 = try s.text("view");
    try s.index(v2, v3, v30);
    v3 += 1;
    const v31 = try s.text("with");
    try s.index(v2, v3, v31);
    v3 += 1;
    const v32 = try s.text("yield");
    try s.index(v2, v3, v32);
    v3 += 1;
    _ = &v3;
    try s.put(v1, "builtin-name", v2);
    const v33 = try s.object();
    const v34 = try s.array();
    var v35: u32 = 0;
    const v36 = try s.text("true");
    try s.index(v34, v35, v36);
    v35 += 1;
    const v37 = try s.text("false");
    try s.index(v34, v35, v37);
    v35 += 1;
    const v38 = try s.text("undefined");
    try s.index(v34, v35, v38);
    v35 += 1;
    const v39 = try s.text("null");
    try s.index(v34, v35, v39);
    v35 += 1;
    _ = &v35;
    try s.put(v33, "literal", v34);
    const v40 = try b.rx(&s, "\"\"|\"[^\"]+\"");
    const v41 = try b.rx(&s, "''|'[^']+'");
    const v42 = try b.rx(&s, "\\[\\]|\\[[^\\]]+\\]");
    const v43 = try b.rx(&s, "[^\\s!\"#%&'()*+,.\\/;<=>@\\[\\\\\\]^`{|}~]+");
    const v44 = try b.rx(&s, "(\\.|\\/)");
    const v50 = try b.list(&s, &.{
        v40,
        v41,
        v42,
        v43,
    });
    const v45 = try s.own(try @import("native_highlight_regex.zig").either(e, v50));
    const v53 = try b.rx(&s, "\\.|\\.\\/|\\/");
    const v54 = try b.list(&s, &.{
        try s.text("("),
        v53,
        try s.text(")?"),
    });
    const v52 = try s.own(try @import("native_highlight_regex.zig").concat(e, v54));
    const v60 = try b.list(&s, &.{
        v44,
        v45,
    });
    const v57 = try s.own(try @import("native_highlight_regex.zig").concat(e, v60));
    const v61 = try b.list(&s, &.{
        try s.text("("),
        v57,
        try s.text(")*"),
    });
    const v56 = try s.own(try @import("native_highlight_regex.zig").concat(e, v61));
    const v62 = try b.list(&s, &.{
        v52,
        v45,
        v56,
    });
    const v51 = try s.own(try @import("native_highlight_regex.zig").concat(e, v62));
    const v64 = try s.text("(");
    const v66 = try s.text("|");
    const v68 = try s.text(")(?==)");
    const v69 = try b.list(&s, &.{
        v64,
        v42,
        v66,
        v43,
        v68,
    });
    const v63 = try s.own(try @import("native_highlight_regex.zig").concat(e, v69));
    const v70 = try s.object();
    try s.put(v70, "begin", v51);
    const v72 = try b.rx(&s, "[\\w.\\/]+");
    try s.put(v70, "lexemes", v72);
    const v74 = try s.get(hljs, "inherit");
    const v76 = try s.object();
    try s.put(v76, "keywords", v33);
    const v78 = try s.call(v74, hljs, &.{
        v70,
        v76,
    });
    const v79 = try s.object();
    const v80 = try b.rx(&s, "\\(");
    try s.put(v79, "begin", v80);
    const v81 = try b.rx(&s, "\\)");
    try s.put(v79, "end", v81);
    const v82 = try s.object();
    const v83 = try s.text("attr");
    try s.put(v82, "className", v83);
    try s.put(v82, "begin", v63);
    const v85 = b.c.JS_NewInt32(e.context, 0);
    try s.put(v82, "relevance", v85);
    const v86 = try s.object();
    const v87 = try b.rx(&s, "=");
    try s.put(v86, "begin", v87);
    const v88 = try b.rx(&s, "=");
    try s.put(v86, "end", v88);
    const v89 = try s.object();
    const v90 = try s.array();
    var v91: u32 = 0;
    const v93 = try s.get(hljs, "NUMBER_MODE");
    try s.index(v90, v91, v93);
    v91 += 1;
    const v95 = try s.get(hljs, "QUOTE_STRING_MODE");
    try s.index(v90, v91, v95);
    v91 += 1;
    const v97 = try s.get(hljs, "APOS_STRING_MODE");
    try s.index(v90, v91, v97);
    v91 += 1;
    try s.index(v90, v91, v78);
    v91 += 1;
    try s.index(v90, v91, v79);
    v91 += 1;
    _ = &v91;
    try s.put(v89, "contains", v90);
    try s.put(v86, "starts", v89);
    try s.put(v82, "starts", v86);
    const v100 = try s.object();
    const v101 = try b.rx(&s, "as\\s+\\|");
    try s.put(v100, "begin", v101);
    const v102 = try s.object();
    const v103 = try s.text("as");
    try s.put(v102, "keyword", v103);
    try s.put(v100, "keywords", v102);
    const v104 = try b.rx(&s, "\\|");
    try s.put(v100, "end", v104);
    const v105 = try s.array();
    var v106: u32 = 0;
    const v107 = try s.object();
    const v108 = try b.rx(&s, "\\w+");
    try s.put(v107, "begin", v108);
    try s.index(v105, v106, v107);
    v106 += 1;
    _ = &v106;
    try s.put(v100, "contains", v105);
    const v109 = try s.object();
    const v110 = try s.array();
    var v111: u32 = 0;
    const v113 = try s.get(hljs, "NUMBER_MODE");
    try s.index(v110, v111, v113);
    v111 += 1;
    const v115 = try s.get(hljs, "QUOTE_STRING_MODE");
    try s.index(v110, v111, v115);
    v111 += 1;
    const v117 = try s.get(hljs, "APOS_STRING_MODE");
    try s.index(v110, v111, v117);
    v111 += 1;
    try s.index(v110, v111, v100);
    v111 += 1;
    try s.index(v110, v111, v82);
    v111 += 1;
    try s.index(v110, v111, v78);
    v111 += 1;
    try s.index(v110, v111, v79);
    v111 += 1;
    _ = &v111;
    try s.put(v109, "contains", v110);
    const v122 = b.boolean(&s, true);
    try s.put(v109, "returnEnd", v122);
    const v124 = try s.get(hljs, "inherit");
    const v126 = try s.object();
    const v127 = try s.text("name");
    try s.put(v126, "className", v127);
    try s.put(v126, "keywords", v1);
    const v130 = try s.get(hljs, "inherit");
    const v132 = try s.object();
    const v133 = try b.rx(&s, "\\)");
    try s.put(v132, "end", v133);
    const v134 = try s.call(v130, hljs, &.{
        v109,
        v132,
    });
    try s.put(v126, "starts", v134);
    const v135 = try s.call(v124, hljs, &.{
        v70,
        v126,
    });
    const v136 = try s.array();
    var v137: u32 = 0;
    try s.index(v136, v137, v135);
    v137 += 1;
    _ = &v137;
    try s.set(v79, "contains", v136);
    const v140 = try s.get(hljs, "inherit");
    const v142 = try s.object();
    try s.put(v142, "keywords", v1);
    const v144 = try s.text("name");
    try s.put(v142, "className", v144);
    const v146 = try s.get(hljs, "inherit");
    const v148 = try s.object();
    const v149 = try b.rx(&s, "\\}\\}");
    try s.put(v148, "end", v149);
    const v150 = try s.call(v146, hljs, &.{
        v109,
        v148,
    });
    try s.put(v142, "starts", v150);
    const v151 = try s.call(v140, hljs, &.{
        v70,
        v142,
    });
    const v153 = try s.get(hljs, "inherit");
    const v155 = try s.object();
    try s.put(v155, "keywords", v1);
    const v157 = try s.text("name");
    try s.put(v155, "className", v157);
    const v158 = try s.call(v153, hljs, &.{
        v70,
        v155,
    });
    const v160 = try s.get(hljs, "inherit");
    const v162 = try s.object();
    const v163 = try s.text("name");
    try s.put(v162, "className", v163);
    try s.put(v162, "keywords", v1);
    const v166 = try s.get(hljs, "inherit");
    const v168 = try s.object();
    const v169 = try b.rx(&s, "\\}\\}");
    try s.put(v168, "end", v169);
    const v170 = try s.call(v166, hljs, &.{
        v109,
        v168,
    });
    try s.put(v162, "starts", v170);
    const v171 = try s.call(v160, hljs, &.{
        v70,
        v162,
    });
    const v172 = try s.object();
    const v173 = try b.rx(&s, "\\\\\\{\\{");
    try s.put(v172, "begin", v173);
    const v174 = b.boolean(&s, true);
    try s.put(v172, "skip", v174);
    const v175 = try s.object();
    const v176 = try b.rx(&s, "\\\\\\\\(?=\\{\\{)");
    try s.put(v175, "begin", v176);
    const v177 = b.boolean(&s, true);
    try s.put(v175, "skip", v177);
    const v178 = try s.object();
    const v179 = try s.text("Handlebars");
    try s.put(v178, "name", v179);
    const v180 = try s.array();
    var v181: u32 = 0;
    const v182 = try s.text("hbs");
    try s.index(v180, v181, v182);
    v181 += 1;
    const v183 = try s.text("html.hbs");
    try s.index(v180, v181, v183);
    v181 += 1;
    const v184 = try s.text("html.handlebars");
    try s.index(v180, v181, v184);
    v181 += 1;
    const v185 = try s.text("htmlbars");
    try s.index(v180, v181, v185);
    v181 += 1;
    _ = &v181;
    try s.put(v178, "aliases", v180);
    const v186 = b.boolean(&s, true);
    try s.put(v178, "case_insensitive", v186);
    const v187 = try s.text("xml");
    try s.put(v178, "subLanguage", v187);
    const v188 = try s.array();
    var v189: u32 = 0;
    try s.index(v188, v189, v172);
    v189 += 1;
    try s.index(v188, v189, v175);
    v189 += 1;
    const v193 = try s.get(hljs, "COMMENT");
    const v194 = try b.rx(&s, "\\{\\{!--");
    const v195 = try b.rx(&s, "--\\}\\}");
    const v196 = try s.call(v193, hljs, &.{
        v194,
        v195,
    });
    try s.index(v188, v189, v196);
    v189 += 1;
    const v198 = try s.get(hljs, "COMMENT");
    const v199 = try b.rx(&s, "\\{\\{!");
    const v200 = try b.rx(&s, "\\}\\}");
    const v201 = try s.call(v198, hljs, &.{
        v199,
        v200,
    });
    try s.index(v188, v189, v201);
    v189 += 1;
    const v202 = try s.object();
    const v203 = try s.text("template-tag");
    try s.put(v202, "className", v203);
    const v204 = try b.rx(&s, "\\{\\{\\{\\{(?!\\/)");
    try s.put(v202, "begin", v204);
    const v205 = try b.rx(&s, "\\}\\}\\}\\}");
    try s.put(v202, "end", v205);
    const v206 = try s.array();
    var v207: u32 = 0;
    try s.index(v206, v207, v151);
    v207 += 1;
    _ = &v207;
    try s.put(v202, "contains", v206);
    const v209 = try s.object();
    const v210 = try b.rx(&s, "\\{\\{\\{\\{\\/");
    try s.put(v209, "end", v210);
    const v211 = b.boolean(&s, true);
    try s.put(v209, "returnEnd", v211);
    const v212 = try s.text("xml");
    try s.put(v209, "subLanguage", v212);
    try s.put(v202, "starts", v209);
    try s.index(v188, v189, v202);
    v189 += 1;
    const v213 = try s.object();
    const v214 = try s.text("template-tag");
    try s.put(v213, "className", v214);
    const v215 = try b.rx(&s, "\\{\\{\\{\\{\\/");
    try s.put(v213, "begin", v215);
    const v216 = try b.rx(&s, "\\}\\}\\}\\}");
    try s.put(v213, "end", v216);
    const v217 = try s.array();
    var v218: u32 = 0;
    try s.index(v217, v218, v158);
    v218 += 1;
    _ = &v218;
    try s.put(v213, "contains", v217);
    try s.index(v188, v189, v213);
    v189 += 1;
    const v220 = try s.object();
    const v221 = try s.text("template-tag");
    try s.put(v220, "className", v221);
    const v222 = try b.rx(&s, "\\{\\{#");
    try s.put(v220, "begin", v222);
    const v223 = try b.rx(&s, "\\}\\}");
    try s.put(v220, "end", v223);
    const v224 = try s.array();
    var v225: u32 = 0;
    try s.index(v224, v225, v151);
    v225 += 1;
    _ = &v225;
    try s.put(v220, "contains", v224);
    try s.index(v188, v189, v220);
    v189 += 1;
    const v227 = try s.object();
    const v228 = try s.text("template-tag");
    try s.put(v227, "className", v228);
    const v229 = try b.rx(&s, "\\{\\{(?=else\\}\\})");
    try s.put(v227, "begin", v229);
    const v230 = try b.rx(&s, "\\}\\}");
    try s.put(v227, "end", v230);
    const v231 = try s.text("else");
    try s.put(v227, "keywords", v231);
    try s.index(v188, v189, v227);
    v189 += 1;
    const v232 = try s.object();
    const v233 = try s.text("template-tag");
    try s.put(v232, "className", v233);
    const v234 = try b.rx(&s, "\\{\\{(?=else if)");
    try s.put(v232, "begin", v234);
    const v235 = try b.rx(&s, "\\}\\}");
    try s.put(v232, "end", v235);
    const v236 = try s.text("else if");
    try s.put(v232, "keywords", v236);
    try s.index(v188, v189, v232);
    v189 += 1;
    const v237 = try s.object();
    const v238 = try s.text("template-tag");
    try s.put(v237, "className", v238);
    const v239 = try b.rx(&s, "\\{\\{\\/");
    try s.put(v237, "begin", v239);
    const v240 = try b.rx(&s, "\\}\\}");
    try s.put(v237, "end", v240);
    const v241 = try s.array();
    var v242: u32 = 0;
    try s.index(v241, v242, v158);
    v242 += 1;
    _ = &v242;
    try s.put(v237, "contains", v241);
    try s.index(v188, v189, v237);
    v189 += 1;
    const v244 = try s.object();
    const v245 = try s.text("template-variable");
    try s.put(v244, "className", v245);
    const v246 = try b.rx(&s, "\\{\\{\\{");
    try s.put(v244, "begin", v246);
    const v247 = try b.rx(&s, "\\}\\}\\}");
    try s.put(v244, "end", v247);
    const v248 = try s.array();
    var v249: u32 = 0;
    try s.index(v248, v249, v171);
    v249 += 1;
    _ = &v249;
    try s.put(v244, "contains", v248);
    try s.index(v188, v189, v244);
    v189 += 1;
    const v251 = try s.object();
    const v252 = try s.text("template-variable");
    try s.put(v251, "className", v252);
    const v253 = try b.rx(&s, "\\{\\{");
    try s.put(v251, "begin", v253);
    const v254 = try b.rx(&s, "\\}\\}");
    try s.put(v251, "end", v254);
    const v255 = try s.array();
    var v256: u32 = 0;
    try s.index(v255, v256, v171);
    v256 += 1;
    _ = &v256;
    try s.put(v251, "contains", v255);
    try s.index(v188, v189, v251);
    v189 += 1;
    _ = &v189;
    try s.put(v178, "contains", v188);
    return b.c.JS_DupValue(e.context, v178);
}
