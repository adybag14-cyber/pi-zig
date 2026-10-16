//! Actual highlight.js 10.7.3 static keyword inputs; native factory follows.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "sas", build);
}
pub fn build(e: *b.Engine, h: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const l = try s.object();
    try s.put(l, "name", try s.text("SAS"));
    try s.put(l, "case_insensitive", b.boolean(&s, true));
    const kw = try s.object();
    try s.put(kw, "literal", try s.text("null missing _all_ _automatic_ _character_ _infile_ _n_ _name_ _null_ _numeric_ _user_ _webout_"));
    try s.put(kw, "meta", try s.text(source_text));
    try s.put(l, "keywords", kw);
    const a = try s.array();
    const statement = try b.mode(&s, "keyword");
    try s.put(statement, "begin", try b.rx(&s, "^\\s*(proc [\\w\\d_]+|data|run|quit)[\\s;]"));
    try s.index(a, 0, statement);
    const variable = try b.mode(&s, "variable");
    try s.put(variable, "begin", try b.rx(&s, "&[a-zA-Z_&][a-zA-Z0-9_]*\\.?"));
    try s.index(a, 1, variable);
    const data = try b.mode(&s, "emphasis");
    try s.put(data, "begin", try b.rx(&s, "^\\s*datalines|cards.*;"));
    try s.put(data, "end", try b.rx(&s, "^\\s*;\\s*$"));
    try s.index(a, 2, data);
    const macro = try b.mode(&s, "built_in");
    try s.put(macro, "begin", try s.text("%(" ++ source_SAS_MACRO_FUN ++ ")"));
    try s.index(a, 3, macro);
    const user = try b.mode(&s, "name");
    try s.put(user, "begin", try b.rx(&s, "%[a-zA-Z_][a-zA-Z_0-9]*"));
    try s.index(a, 4, user);
    const fun = try b.mode(&s, "meta");
    try s.put(fun, "begin", try s.text("[^%](" ++ source_SAS_FUN ++ ")[\\(]"));
    try s.index(a, 5, fun);
    const str = try b.mode(&s, "string");
    try s.put(str, "variants", try b.list(&s, &.{ try s.get(h, "APOS_STRING_MODE"), try s.get(h, "QUOTE_STRING_MODE") }));
    try s.index(a, 6, str);
    const cf = try s.get(h, "COMMENT");
    const cb = try s.text("\\*");
    const ce = try s.text(";");
    try s.index(a, 7, try s.call(cf, h, &.{ cb, ce }));
    try s.index(a, 8, try s.get(h, "C_BLOCK_COMMENT_MODE"));
    try s.put(l, "contains", a);
    return b.c.JS_DupValue(e.context, l);
}
const source_text = "do if then else end until while abort array attrib by call cards cards4 catname continue datalines datalines4 delete delim delimiter display dm drop endsas error file filename footnote format goto in infile informat input keep label leave length libname link list lostcard merge missing modify options output out page put redirect remove rename replace retain return select set skip startsas stop title update waitsas where window x systask add and alter as cascade check create delete describe distinct drop foreign from group having index insert into in key like message modify msgtype not null on or order primary references reset restrict select set table unique update validate view where";
const source_SAS_FUN = "abs|addr|airy|arcos|arsin|atan|attrc|attrn|band|betainv|blshift|bnot|bor|brshift|bxor|byte|cdf|ceil|cexist|cinv|close|cnonct|collate|compbl|compound|compress|cos|cosh|css|curobs|cv|daccdb|daccdbsl|daccsl|daccsyd|dacctab|dairy|date|datejul|datepart|datetime|day|dclose|depdb|depdbsl|depdbsl|depsl|depsl|depsyd|depsyd|deptab|deptab|dequote|dhms|dif|digamma|dim|dinfo|dnum|dopen|doptname|doptnum|dread|dropnote|dsname|erf|erfc|exist|exp|fappend|fclose|fcol|fdelete|fetch|fetchobs|fexist|fget|fileexist|filename|fileref|finfo|finv|fipname|fipnamel|fipstate|floor|fnonct|fnote|fopen|foptname|foptnum|fpoint|fpos|fput|fread|frewind|frlen|fsep|fuzz|fwrite|gaminv|gamma|getoption|getvarc|getvarn|hbound|hms|hosthelp|hour|ibessel|index|indexc|indexw|input|inputc|inputn|int|intck|intnx|intrr|irr|jbessel|juldate|kurtosis|lag|lbound|left|length|lgamma|libname|libref|log|log10|log2|logpdf|logpmf|logsdf|lowcase|max|mdy|mean|min|minute|mod|month|mopen|mort|n|netpv|nmiss|normal|note|npv|open|ordinal|pathname|pdf|peek|peekc|pmf|point|poisson|poke|probbeta|probbnml|probchi|probf|probgam|probhypr|probit|probnegb|probnorm|probt|put|putc|putn|qtr|quote|ranbin|rancau|ranexp|rangam|range|rank|rannor|ranpoi|rantbl|rantri|ranuni|repeat|resolve|reverse|rewind|right|round|saving|scan|sdf|second|sign|sin|sinh|skewness|soundex|spedis|sqrt|std|stderr|stfips|stname|stnamel|substr|sum|symget|sysget|sysmsg|sysprod|sysrc|system|tan|tanh|time|timepart|tinv|tnonct|today|translate|tranwrd|trigamma|trim|trimn|trunc|uniform|upcase|uss|var|varfmt|varinfmt|varlabel|varlen|varname|varnum|varray|varrayx|vartype|verify|vformat|vformatd|vformatdx|vformatn|vformatnx|vformatw|vformatwx|vformatx|vinarray|vinarrayx|vinformat|vinformatd|vinformatdx|vinformatn|vinformatnx|vinformatw|vinformatwx|vinformatx|vlabel|vlabelx|vlength|vlengthx|vname|vnamex|vtype|vtypex|weekday|year|yyq|zipfips|zipname|zipnamel|zipstate";
const source_SAS_MACRO_FUN = "bquote|nrbquote|cmpres|qcmpres|compstor|datatyp|display|do|else|end|eval|global|goto|if|index|input|keydef|label|left|length|let|local|lowcase|macro|mend|nrbquote|nrquote|nrstr|put|qcmpres|qleft|qlowcase|qscan|qsubstr|qsysfunc|qtrim|quote|qupcase|scan|str|substr|superq|syscall|sysevalf|sysexec|sysfunc|sysget|syslput|sysprod|sysrc|sysrput|then|to|trim|unquote|until|upcase|verify|while|window";
