//! Actual highlight.js 10.7.3 static keyword inputs; native factory follows.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "hsp", build);
}
pub fn build(e: *b.Engine, h: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const l = try s.object();
    try s.put(l, "name", try s.text("HSP"));
    try s.put(l, "case_insensitive", b.boolean(&s, true));
    const kw = try s.object();
    try s.put(kw, "$pattern", try b.rx(&s, "[\\w._]+"));
    try s.put(kw, "keyword", try s.text(source_keyword));
    try s.put(l, "keywords", kw);
    const a = try b.list(&s, &.{ try s.get(h, "C_LINE_COMMENT_MODE"), try s.get(h, "C_BLOCK_COMMENT_MODE"), try s.get(h, "QUOTE_STRING_MODE"), try s.get(h, "APOS_STRING_MODE") });
    const multiline = try b.mode(&s, "string");
    try s.put(multiline, "begin", try b.rx(&s, "\\{\""));
    try s.put(multiline, "end", try b.rx(&s, "\"\\}"));
    try s.put(multiline, "contains", try b.list(&s, &.{try s.get(h, "BACKSLASH_ESCAPE")}));
    try s.index(a, 4, multiline);
    const f = try s.get(h, "COMMENT");
    const cb = try s.text(";");
    const ce = try s.text("$");
    const opt = try s.object();
    try s.put(opt, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.index(a, 5, try s.call(f, h, &.{ cb, ce, opt }));
    const meta = try b.mode(&s, "meta");
    try s.put(meta, "begin", try s.text("#"));
    try s.put(meta, "end", try s.text("$"));
    const mk = try s.object();
    try s.put(mk, "meta-keyword", try s.text("addion cfunc cmd cmpopt comfunc const defcfunc deffunc define else endif enum epack func global if ifdef ifndef include modcfunc modfunc modinit modterm module pack packopt regcmd runtime undef usecom uselib"));
    try s.put(meta, "keywords", mk);
    const inherit = try s.get(h, "inherit");
    const quote = try s.get(h, "QUOTE_STRING_MODE");
    const changes = try s.object();
    try s.put(changes, "className", try s.text("meta-string"));
    try s.put(meta, "contains", try b.list(&s, &.{ try s.call(inherit, h, &.{ quote, changes }), try s.get(h, "NUMBER_MODE"), try s.get(h, "C_NUMBER_MODE"), try s.get(h, "C_LINE_COMMENT_MODE"), try s.get(h, "C_BLOCK_COMMENT_MODE") }));
    try s.index(a, 6, meta);
    const label = try b.mode(&s, "symbol");
    try s.put(label, "begin", try s.text("^\\*(\\w+|@)"));
    try s.index(a, 7, label);
    try s.index(a, 8, try s.get(h, "NUMBER_MODE"));
    try s.index(a, 9, try s.get(h, "C_NUMBER_MODE"));
    try s.put(l, "contains", a);
    return b.c.JS_DupValue(e.context, l);
}
const source_keyword = "goto gosub return break repeat loop continue wait await dim sdim foreach dimtype dup dupptr end stop newmod delmod mref run exgoto on mcall assert logmes newlab resume yield onexit onerror onkey onclick oncmd exist delete mkdir chdir dirlist bload bsave bcopy memfile if else poke wpoke lpoke getstr chdpm memexpand memcpy memset notesel noteadd notedel noteload notesave randomize noteunsel noteget split strrep setease button chgdisp exec dialog mmload mmplay mmstop mci pset pget syscolor mes print title pos circle cls font sysfont objsize picload color palcolor palette redraw width gsel gcopy gzoom gmode bmpsave hsvcolor getkey listbox chkbox combox input mesbox buffer screen bgscr mouse objsel groll line clrobj boxf objprm objmode stick grect grotate gsquare gradf objimage objskip objenable celload celdiv celput newcom querycom delcom cnvstow comres axobj winobj sendmsg comevent comevarg sarrayconv callfunc cnvwtos comevdisp libptr system hspstat hspver stat cnt err strsize looplev sublev iparam wparam lparam refstr refdval int rnd strlen length length2 length3 length4 vartype gettime peek wpeek lpeek varptr varuse noteinfo instr abs limit getease str strmid strf getpath strtrim sin cos tan atan sqrt double absf expf logf limitf powf geteasef mousex mousey mousew hwnd hinstance hdc ginfo objinfo dirinfo sysinfo thismod __hspver__ __hsp30__ __date__ __time__ __line__ __file__ _debug __hspdef__ and or xor not screen_normal screen_palette screen_hide screen_fixedsize screen_tool screen_frame gmode_gdi gmode_mem gmode_rgb0 gmode_alpha gmode_rgb0alpha gmode_add gmode_sub gmode_pixela ginfo_mx ginfo_my ginfo_act ginfo_sel ginfo_wx1 ginfo_wy1 ginfo_wx2 ginfo_wy2 ginfo_vx ginfo_vy ginfo_sizex ginfo_sizey ginfo_winx ginfo_winy ginfo_mesx ginfo_mesy ginfo_r ginfo_g ginfo_b ginfo_paluse ginfo_dispx ginfo_dispy ginfo_cx ginfo_cy ginfo_intid ginfo_newid ginfo_sx ginfo_sy objinfo_mode objinfo_bmscr objinfo_hwnd notemax notesize dir_cur dir_exe dir_win dir_sys dir_cmdline dir_desktop dir_mydoc dir_tv font_normal font_bold font_italic font_underline font_strikeout font_antialias objmode_normal objmode_guifont objmode_usefont gsquare_grad msgothic msmincho do until while wend for next _break _continue switch case default swbreak swend ddim ldim alloc m_pi rad2deg deg2rad ease_linear ease_quad_in ease_quad_out ease_quad_inout ease_cubic_in ease_cubic_out ease_cubic_inout ease_quartic_in ease_quartic_out ease_quartic_inout ease_bounce_in ease_bounce_out ease_bounce_inout ease_shake_in ease_shake_out ease_shake_inout ease_loop";
