//! Actual highlight.js 10.7.3 factory operations; source-only until separately qualified.
const b = @import("native_highlight_lazy_batch3_values.zig");
const h = @import("native_highlight_lazy_batch9_helpers.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "irpf90", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const v1 = try s.object();
    const v2 = try s.text("params");
    try s.put(v1, "className", v2);
    const v3 = try s.text("\\(");
    try s.put(v1, "begin", v3);
    const v4 = try s.text("\\)");
    try s.put(v1, "end", v4);
    const v5 = try b.rx(&s, "(_[a-z_\\d]+)?");
    const v6 = try b.rx(&s, "([de][+-]?\\d+)?");
    const v7 = try s.object();
    const v8 = try s.text("number");
    try s.put(v7, "className", v8);
    const v9 = try s.array();
    var v10: u32 = 0;
    const v11 = try s.object();
    const v13 = try b.rx(&s, "\\b\\d+");
    const v14 = try b.rx(&s, "\\.(\\d*)");
    const v17 = try b.list(&s, &.{
        v13,
        v14,
        v6,
        v5,
    });
    const v12 = try s.own(try @import("native_highlight_regex.zig").concat(e, v17));
    try s.put(v11, "begin", v12);
    try s.index(v9, v10, v11);
    v10 += 1;
    const v18 = try s.object();
    const v20 = try b.rx(&s, "\\b\\d+");
    const v23 = try b.list(&s, &.{
        v20,
        v6,
        v5,
    });
    const v19 = try s.own(try @import("native_highlight_regex.zig").concat(e, v23));
    try s.put(v18, "begin", v19);
    try s.index(v9, v10, v18);
    v10 += 1;
    const v24 = try s.object();
    const v26 = try b.rx(&s, "\\.\\d+");
    const v29 = try b.list(&s, &.{
        v26,
        v6,
        v5,
    });
    const v25 = try s.own(try @import("native_highlight_regex.zig").concat(e, v29));
    try s.put(v24, "begin", v25);
    try s.index(v9, v10, v24);
    v10 += 1;
    _ = &v10;
    try s.put(v7, "variants", v9);
    const v30 = b.c.JS_NewInt32(e.context, 0);
    try s.put(v7, "relevance", v30);
    const v31 = try s.object();
    const v32 = try s.text(".False. .True.");
    try s.put(v31, "literal", v32);
    const v75 = try s.text("kind do while private call intrinsic where elsewhere type endtype endmodule endselect endinterface end enddo endif if forall endforall only contains default return stop then public subroutine|10 function program .and. .or. .not. .le. .eq. .ge. .gt. .lt. goto save else use module select case access blank direct exist file fmt form formatted iostat name named nextrec number opened rec recl sequential status unformatted unit continue format pause cycle exit c_null_char c_alert c_backspace c_form_feed flush wait decimal round iomsg synchronous nopass non_overridable pass protected volatile abstract extends import non_intrinsic value deferred generic final enumerator class associate bind enum c_int c_short c_long c_long_long c_signed_char c_size_t c_int8_t c_int16_t c_int32_t c_int64_t c_int_least8_t c_int_least16_t c_int_least32_t c_int_least64_t c_int_fast8_t c_int_fast16_t c_int_fast32_t c_int_fast64_t c_intmax_t C_intptr_t c_float c_double c_long_double c_float_complex c_double_complex c_long_double_complex c_bool c_char c_null_ptr c_null_funptr c_new_line c_carriage_return c_horizontal_tab c_vertical_tab iso_c_binding c_loc c_funloc c_associated  c_f_pointer c_ptr c_funptr iso_fortran_env character_storage_size error_unit file_storage_size input_unit iostat_end iostat_eor numeric_storage_size output_unit c_f_procpointer ieee_arithmetic ieee_support_underflow_control ieee_get_underflow_mode ieee_set_underflow_mode newunit contiguous recursive pad position action delim readwrite eor advance nml interface procedure namelist include sequence elemental pure integer real character complex logical dimension allocatable|10 parameter external implicit|10 none double precision assign intent optional pointer target in out common equivalence data begin_provider &begin_provider end_provider begin_shell end_shell begin_template end_template subst assert touch soft_touch provide no_dep free irp_if irp_else irp_endif irp_write irp_read");
    try s.put(v31, "keyword", v75);
    const v112 = try s.text("alog alog10 amax0 amax1 amin0 amin1 amod cabs ccos cexp clog csin csqrt dabs dacos dasin datan datan2 dcos dcosh ddim dexp dint dlog dlog10 dmax1 dmin1 dmod dnint dsign dsin dsinh dsqrt dtan dtanh float iabs idim idint idnint ifix isign max0 max1 min0 min1 sngl algama cdabs cdcos cdexp cdlog cdsin cdsqrt cqabs cqcos cqexp cqlog cqsin cqsqrt dcmplx dconjg derf derfc dfloat dgamma dimag dlgama iqint qabs qacos qasin qatan qatan2 qcmplx qconjg qcos qcosh qdim qerf qerfc qexp qgamma qimag qlgama qlog qlog10 qmax1 qmin1 qmod qnint qsign qsin qsinh qsqrt qtan qtanh abs acos aimag aint anint asin atan atan2 char cmplx conjg cos cosh exp ichar index int log log10 max min nint sign sin sinh sqrt tan tanh print write dim lge lgt lle llt mod nullify allocate deallocate adjustl adjustr all allocated any associated bit_size btest ceiling count cshift date_and_time digits dot_product eoshift epsilon exponent floor fraction huge iand ibclr ibits ibset ieor ior ishft ishftc lbound len_trim matmul maxexponent maxloc maxval merge minexponent minloc minval modulo mvbits nearest pack present product radix random_number random_seed range repeat reshape rrspacing scale scan selected_int_kind selected_real_kind set_exponent shape size spacing spread sum system_clock tiny transpose trim ubound unpack verify achar iachar transfer dble entry dprod cpu_time command_argument_count get_command get_command_argument get_environment_variable is_iostat_end ieee_arithmetic ieee_support_underflow_control ieee_get_underflow_mode ieee_set_underflow_mode is_iostat_eor move_alloc new_line selected_char_kind same_type_as extends_type_of acosh asinh atanh bessel_j0 bessel_j1 bessel_jn bessel_y0 bessel_y1 bessel_yn erf erfc erfc_scaled gamma log_gamma hypot norm2 atomic_define atomic_ref execute_command_line leadz trailz storage_size merge_bits bge bgt ble blt dshiftl dshiftr findloc iall iany iparity image_index lcobound ucobound maskl maskr num_images parity popcnt poppar shifta shiftl shiftr this_image IRP_ALIGN irp_here");
    try s.put(v31, "built_in", v112);
    const v113 = try s.object();
    const v114 = try s.text("IRPF90");
    try s.put(v113, "name", v114);
    const v115 = b.boolean(&s, true);
    try s.put(v113, "case_insensitive", v115);
    try s.put(v113, "keywords", v31);
    const v117 = try b.rx(&s, "\\/\\*");
    try s.put(v113, "illegal", v117);
    const v118 = try s.array();
    var v119: u32 = 0;
    const v121 = try s.get(hljs, "inherit");
    const v123 = try s.get(hljs, "APOS_STRING_MODE");
    const v124 = try s.object();
    const v125 = try s.text("string");
    try s.put(v124, "className", v125);
    const v126 = b.c.JS_NewInt32(e.context, 0);
    try s.put(v124, "relevance", v126);
    const v127 = try s.call(v121, hljs, &.{
        v123,
        v124,
    });
    try s.index(v118, v119, v127);
    v119 += 1;
    const v129 = try s.get(hljs, "inherit");
    const v131 = try s.get(hljs, "QUOTE_STRING_MODE");
    const v132 = try s.object();
    const v133 = try s.text("string");
    try s.put(v132, "className", v133);
    const v134 = b.c.JS_NewInt32(e.context, 0);
    try s.put(v132, "relevance", v134);
    const v135 = try s.call(v129, hljs, &.{
        v131,
        v132,
    });
    try s.index(v118, v119, v135);
    v119 += 1;
    const v136 = try s.object();
    const v137 = try s.text("function");
    try s.put(v136, "className", v137);
    const v138 = try s.text("subroutine function program");
    try s.put(v136, "beginKeywords", v138);
    const v139 = try s.text("[${=\\n]");
    try s.put(v136, "illegal", v139);
    const v140 = try s.array();
    var v141: u32 = 0;
    const v143 = try s.get(hljs, "UNDERSCORE_TITLE_MODE");
    try s.index(v140, v141, v143);
    v141 += 1;
    try s.index(v140, v141, v1);
    v141 += 1;
    _ = &v141;
    try s.put(v136, "contains", v140);
    try s.index(v118, v119, v136);
    v119 += 1;
    const v146 = try s.get(hljs, "COMMENT");
    const v147 = try s.text("!");
    const v148 = try s.text("$");
    const v149 = try s.object();
    const v150 = b.c.JS_NewInt32(e.context, 0);
    try s.put(v149, "relevance", v150);
    const v151 = try s.call(v146, hljs, &.{
        v147,
        v148,
        v149,
    });
    try s.index(v118, v119, v151);
    v119 += 1;
    const v153 = try s.get(hljs, "COMMENT");
    const v154 = try s.text("begin_doc");
    const v155 = try s.text("end_doc");
    const v156 = try s.object();
    const v157 = b.c.JS_NewInt32(e.context, 10);
    try s.put(v156, "relevance", v157);
    const v158 = try s.call(v153, hljs, &.{
        v154,
        v155,
        v156,
    });
    try s.index(v118, v119, v158);
    v119 += 1;
    try s.index(v118, v119, v7);
    v119 += 1;
    _ = &v119;
    try s.put(v113, "contains", v118);
    return b.c.JS_DupValue(e.context, v113);
}
