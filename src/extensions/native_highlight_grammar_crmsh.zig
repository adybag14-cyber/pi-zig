//! Actual highlight.js 10.7.3 crmsh factory; source-only, unqualified.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "crmsh", build);
}
pub fn build(e: *b.Engine, h: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const commands = try s.text("group clone ms master location colocation order fencing_topology rsc_ticket acl_target acl_group user role tag xml");
    const l = try s.object();
    try s.put(l, "name", try s.text("crmsh"));
    try s.put(l, "aliases", try b.list(&s, &.{ try s.text("crm"), try s.text("pcmk") }));
    try s.put(l, "case_insensitive", b.boolean(&s, true));
    const kw = try s.object();
    try s.put(kw, "keyword", try s.text("params meta operations op rule attributes utilization read write deny defined not_defined in_range date spec in ref reference attribute type xpath version and or lt gt tag lte gte eq ne \\ number string"));
    try s.put(kw, "literal", try s.text("Master Started Slave Stopped start promote demote stop monitor true false"));
    try s.put(l, "keywords", kw);
    const a = try b.list(&s, &.{try s.get(h, "HASH_COMMENT_MODE")});
    const node = try s.object();
    try s.put(node, "beginKeywords", try s.text("node"));
    const ns = try s.object();
    try s.put(ns, "end", try s.text("\\s*([\\w_-]+:)?"));
    const nt = try b.mode(&s, "title");
    try s.put(nt, "end", try s.text("\\s*[\\$\\w_][\\w_-]*"));
    try s.put(ns, "starts", nt);
    try s.put(node, "starts", ns);
    try s.index(a, 1, node);
    const res = try s.object();
    try s.put(res, "beginKeywords", try s.text("primitive rsc_template"));
    const rs = try b.mode(&s, "title");
    try s.put(rs, "end", try s.text("\\s*[\\$\\w_][\\w_-]*"));
    const rr = try s.object();
    try s.put(rr, "end", try s.text("\\s*@?[\\w_][\\w_\\.:-]*"));
    try s.put(rs, "starts", rr);
    try s.put(res, "starts", rs);
    try s.index(a, 2, res);
    const command = try s.object();
    const split = try s.invoke(commands, "split", &.{try s.text(" ")});
    const joined = try s.invoke(split, "join", &.{try s.text("|")});
    try s.put(command, "begin", try s.concat(try s.concat(try s.text("\\b("), joined), try s.text(")\\s+")));
    try s.put(command, "keywords", commands);
    const cs = try b.mode(&s, "title");
    try s.put(cs, "end", try s.text("[\\$\\w_][\\w_-]*"));
    try s.put(command, "starts", cs);
    try s.index(a, 3, command);
    const prop = try s.object();
    try s.put(prop, "beginKeywords", try s.text("property rsc_defaults op_defaults"));
    const ps = try b.mode(&s, "title");
    try s.put(ps, "end", try s.text("\\s*([\\w_-]+:)?"));
    try s.put(prop, "starts", ps);
    try s.index(a, 4, prop);
    try s.index(a, 5, try s.get(h, "QUOTE_STRING_MODE"));
    for ([_][2][]const u8{ .{ "meta", "(ocf|systemd|service|lsb):[\\w_:-]+" }, .{ "number", "\\b\\d+(\\.\\d+)?(ms|s|h|m)?" }, .{ "literal", "[-]?(infinity|inf)" } }, 6..) |p, i| {
        const m = try b.mode(&s, p[0]);
        try s.put(m, "begin", try s.text(p[1]));
        try s.put(m, "relevance", b.c.JS_NewInt32(e.context, 0));
        try s.index(a, @intCast(i), m);
    }
    const attr = try b.mode(&s, "attr");
    try s.put(attr, "begin", try b.rx(&s, "([A-Za-z$_#][\\w_-]+)="));
    try s.put(attr, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.index(a, 9, attr);
    const tag = try b.mode(&s, "tag");
    try s.put(tag, "begin", try s.text("</?"));
    try s.put(tag, "end", try s.text("/?>"));
    try s.put(tag, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.index(a, 10, tag);
    try s.put(l, "contains", a);
    return b.c.JS_DupValue(e.context, l);
}
