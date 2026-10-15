//! Actual highlight.js 10.7.3 factory operations; source-only until separately qualified.
const b = @import("native_highlight_lazy_batch3_values.zig");
const h = @import("native_highlight_lazy_batch9_helpers.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "fortran", build);
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
    const v5 = try s.object();
    const v6 = try s.array();
    var v7: u32 = 0;
    const v9 = try s.get(hljs, "COMMENT");
    const v10 = try s.text("!");
    const v11 = try s.text("$");
    const v12 = try s.object();
    const v13 = b.c.JS_NewInt32(e.context, 0);
    try s.put(v12, "relevance", v13);
    const v14 = try s.call(v9, hljs, &.{
        v10,
        v11,
        v12,
    });
    try s.index(v6, v7, v14);
    v7 += 1;
    const v16 = try s.get(hljs, "COMMENT");
    const v17 = try s.text("^C[ ]");
    const v18 = try s.text("$");
    const v19 = try s.object();
    const v20 = b.c.JS_NewInt32(e.context, 0);
    try s.put(v19, "relevance", v20);
    const v21 = try s.call(v16, hljs, &.{
        v17,
        v18,
        v19,
    });
    try s.index(v6, v7, v21);
    v7 += 1;
    const v23 = try s.get(hljs, "COMMENT");
    const v24 = try s.text("^C$");
    const v25 = try s.text("$");
    const v26 = try s.object();
    const v27 = b.c.JS_NewInt32(e.context, 0);
    try s.put(v26, "relevance", v27);
    const v28 = try s.call(v23, hljs, &.{
        v24,
        v25,
        v26,
    });
    try s.index(v6, v7, v28);
    v7 += 1;
    _ = &v7;
    try s.put(v5, "variants", v6);
    const v29 = try b.rx(&s, "(_[a-z_\\d]+)?");
    const v30 = try b.rx(&s, "([de][+-]?\\d+)?");
    const v31 = try s.object();
    const v32 = try s.text("number");
    try s.put(v31, "className", v32);
    const v33 = try s.array();
    var v34: u32 = 0;
    const v35 = try s.object();
    const v37 = try b.rx(&s, "\\b\\d+");
    const v38 = try b.rx(&s, "\\.(\\d*)");
    const v41 = try b.list(&s, &.{
        v37,
        v38,
        v30,
        v29,
    });
    const v36 = try s.own(try @import("native_highlight_regex.zig").concat(e, v41));
    try s.put(v35, "begin", v36);
    try s.index(v33, v34, v35);
    v34 += 1;
    const v42 = try s.object();
    const v44 = try b.rx(&s, "\\b\\d+");
    const v47 = try b.list(&s, &.{
        v44,
        v30,
        v29,
    });
    const v43 = try s.own(try @import("native_highlight_regex.zig").concat(e, v47));
    try s.put(v42, "begin", v43);
    try s.index(v33, v34, v42);
    v34 += 1;
    const v48 = try s.object();
    const v50 = try b.rx(&s, "\\.\\d+");
    const v53 = try b.list(&s, &.{
        v50,
        v30,
        v29,
    });
    const v49 = try s.own(try @import("native_highlight_regex.zig").concat(e, v53));
    try s.put(v48, "begin", v49);
    try s.index(v33, v34, v48);
    v34 += 1;
    _ = &v34;
    try s.put(v31, "variants", v33);
    const v54 = b.c.JS_NewInt32(e.context, 0);
    try s.put(v31, "relevance", v54);
    const v55 = try s.object();
    const v56 = try s.text("function");
    try s.put(v55, "className", v56);
    const v57 = try s.text("subroutine function program");
    try s.put(v55, "beginKeywords", v57);
    const v58 = try s.text("[${=\\n]");
    try s.put(v55, "illegal", v58);
    const v59 = try s.array();
    var v60: u32 = 0;
    const v62 = try s.get(hljs, "UNDERSCORE_TITLE_MODE");
    try s.index(v59, v60, v62);
    v60 += 1;
    try s.index(v59, v60, v1);
    v60 += 1;
    _ = &v60;
    try s.put(v55, "contains", v59);
    const v64 = try s.object();
    const v65 = try s.text("string");
    try s.put(v64, "className", v65);
    const v66 = b.c.JS_NewInt32(e.context, 0);
    try s.put(v64, "relevance", v66);
    const v67 = try s.array();
    var v68: u32 = 0;
    const v70 = try s.get(hljs, "APOS_STRING_MODE");
    try s.index(v67, v68, v70);
    v68 += 1;
    const v72 = try s.get(hljs, "QUOTE_STRING_MODE");
    try s.index(v67, v68, v72);
    v68 += 1;
    _ = &v68;
    try s.put(v64, "variants", v67);
    const v73 = try s.object();
    const v74 = try s.text(".False. .True.");
    try s.put(v73, "literal", v74);
    const v113 = try s.text("kind do concurrent local shared while private call intrinsic where elsewhere type endtype endmodule endselect endinterface end enddo endif if forall endforall only contains default return stop then block endblock endassociate public subroutine|10 function program .and. .or. .not. .le. .eq. .ge. .gt. .lt. goto save else use module select case access blank direct exist file fmt form formatted iostat name named nextrec number opened rec recl sequential status unformatted unit continue format pause cycle exit c_null_char c_alert c_backspace c_form_feed flush wait decimal round iomsg synchronous nopass non_overridable pass protected volatile abstract extends import non_intrinsic value deferred generic final enumerator class associate bind enum c_int c_short c_long c_long_long c_signed_char c_size_t c_int8_t c_int16_t c_int32_t c_int64_t c_int_least8_t c_int_least16_t c_int_least32_t c_int_least64_t c_int_fast8_t c_int_fast16_t c_int_fast32_t c_int_fast64_t c_intmax_t C_intptr_t c_float c_double c_long_double c_float_complex c_double_complex c_long_double_complex c_bool c_char c_null_ptr c_null_funptr c_new_line c_carriage_return c_horizontal_tab c_vertical_tab iso_c_binding c_loc c_funloc c_associated  c_f_pointer c_ptr c_funptr iso_fortran_env character_storage_size error_unit file_storage_size input_unit iostat_end iostat_eor numeric_storage_size output_unit c_f_procpointer ieee_arithmetic ieee_support_underflow_control ieee_get_underflow_mode ieee_set_underflow_mode newunit contiguous recursive pad position action delim readwrite eor advance nml interface procedure namelist include sequence elemental pure impure integer real character complex logical codimension dimension allocatable|10 parameter external implicit|10 none double precision assign intent optional pointer target in out common equivalence data");
    try s.put(v73, "keyword", v113);
    const v148 = try s.text("alog alog10 amax0 amax1 amin0 amin1 amod cabs ccos cexp clog csin csqrt dabs dacos dasin datan datan2 dcos dcosh ddim dexp dint dlog dlog10 dmax1 dmin1 dmod dnint dsign dsin dsinh dsqrt dtan dtanh float iabs idim idint idnint ifix isign max0 max1 min0 min1 sngl algama cdabs cdcos cdexp cdlog cdsin cdsqrt cqabs cqcos cqexp cqlog cqsin cqsqrt dcmplx dconjg derf derfc dfloat dgamma dimag dlgama iqint qabs qacos qasin qatan qatan2 qcmplx qconjg qcos qcosh qdim qerf qerfc qexp qgamma qimag qlgama qlog qlog10 qmax1 qmin1 qmod qnint qsign qsin qsinh qsqrt qtan qtanh abs acos aimag aint anint asin atan atan2 char cmplx conjg cos cosh exp ichar index int log log10 max min nint sign sin sinh sqrt tan tanh print write dim lge lgt lle llt mod nullify allocate deallocate adjustl adjustr all allocated any associated bit_size btest ceiling count cshift date_and_time digits dot_product eoshift epsilon exponent floor fraction huge iand ibclr ibits ibset ieor ior ishft ishftc lbound len_trim matmul maxexponent maxloc maxval merge minexponent minloc minval modulo mvbits nearest pack present product radix random_number random_seed range repeat reshape rrspacing scale scan selected_int_kind selected_real_kind set_exponent shape size spacing spread sum system_clock tiny transpose trim ubound unpack verify achar iachar transfer dble entry dprod cpu_time command_argument_count get_command get_command_argument get_environment_variable is_iostat_end ieee_arithmetic ieee_support_underflow_control ieee_get_underflow_mode ieee_set_underflow_mode is_iostat_eor move_alloc new_line selected_char_kind same_type_as extends_type_of acosh asinh atanh bessel_j0 bessel_j1 bessel_jn bessel_y0 bessel_y1 bessel_yn erf erfc erfc_scaled gamma log_gamma hypot norm2 atomic_define atomic_ref execute_command_line leadz trailz storage_size merge_bits bge bgt ble blt dshiftl dshiftr findloc iall iany iparity image_index lcobound ucobound maskl maskr num_images parity popcnt poppar shifta shiftl shiftr this_image sync change team co_broadcast co_max co_min co_sum co_reduce");
    try s.put(v73, "built_in", v148);
    const v149 = try s.object();
    const v150 = try s.text("Fortran");
    try s.put(v149, "name", v150);
    const v151 = b.boolean(&s, true);
    try s.put(v149, "case_insensitive", v151);
    const v152 = try s.array();
    var v153: u32 = 0;
    const v154 = try s.text("f90");
    try s.index(v152, v153, v154);
    v153 += 1;
    const v155 = try s.text("f95");
    try s.index(v152, v153, v155);
    v153 += 1;
    _ = &v153;
    try s.put(v149, "aliases", v152);
    try s.put(v149, "keywords", v73);
    const v157 = try b.rx(&s, "\\/\\*");
    try s.put(v149, "illegal", v157);
    const v158 = try s.array();
    var v159: u32 = 0;
    try s.index(v158, v159, v64);
    v159 += 1;
    try s.index(v158, v159, v55);
    v159 += 1;
    const v162 = try s.object();
    const v163 = try b.rx(&s, "^C\\s*=(?!=)");
    try s.put(v162, "begin", v163);
    const v164 = b.c.JS_NewInt32(e.context, 0);
    try s.put(v162, "relevance", v164);
    try s.index(v158, v159, v162);
    v159 += 1;
    try s.index(v158, v159, v5);
    v159 += 1;
    try s.index(v158, v159, v31);
    v159 += 1;
    _ = &v159;
    try s.put(v149, "contains", v158);
    return b.c.JS_DupValue(e.context, v149);
}
