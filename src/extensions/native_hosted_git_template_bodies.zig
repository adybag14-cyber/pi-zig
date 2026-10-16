//! Native transcriptions of the pinned hosted-git-info template arrows.
const h = @import("native_hosted_git_template_values.zig");
const v = h.v; const c = v.c; const Scope = v.Scope;
pub fn template0(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_domain = try s.get(input, "domain");
    const field_user = try s.get(input, "user");
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    var result = try s.text("");
    result = try s.concat(result, try s.text("git@"));
    result = try s.concat(result, try s.stringify(field_domain));
    result = try s.concat(result, try s.text(":"));
    result = try s.concat(result, try s.stringify(field_user));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_project));
    result = try s.concat(result, try s.text(".git"));
    const temporary1 = try h.join(&s, &.{ try s.text("#"), field_committish });
    result = try s.concat(result, try s.stringify(temporary1));
    return c.JS_DupValue(engine.context, result);
}
pub fn template1(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_domain = try s.get(input, "domain");
    const field_user = try s.get(input, "user");
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    var result = try s.text("");
    result = try s.concat(result, try s.text("git+ssh://git@"));
    result = try s.concat(result, try s.stringify(field_domain));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_user));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_project));
    result = try s.concat(result, try s.text(".git"));
    const temporary1 = try h.join(&s, &.{ try s.text("#"), field_committish });
    result = try s.concat(result, try s.stringify(temporary1));
    return c.JS_DupValue(engine.context, result);
}
pub fn template2(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_domain = try s.get(input, "domain");
    const field_user = try s.get(input, "user");
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    const field_editpath = try s.get(input, "editpath");
    const field_path = try s.get(input, "path");
    var result = try s.text("");
    result = try s.concat(result, try s.text("https://"));
    result = try s.concat(result, try s.stringify(field_domain));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_user));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_project));
    const temporary1 = if (s.truthy(field_committish)) field_committish else try s.text("HEAD");
    const temporary2 = try h.encode(&s, temporary1);
    const temporary3 = try h.join(&s, &.{ try s.text("/"), field_editpath, try s.text("/"), temporary2, try s.text("/"), field_path });
    result = try s.concat(result, try s.stringify(temporary3));
    return c.JS_DupValue(engine.context, result);
}
pub fn template3(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_domain = try s.get(input, "domain");
    const field_user = try s.get(input, "user");
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    const field_treepath = try s.get(input, "treepath");
    var result = try s.text("");
    result = try s.concat(result, try s.text("https://"));
    result = try s.concat(result, try s.stringify(field_domain));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_user));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_project));
    const temporary1 = try h.encode(&s, field_committish);
    const temporary2 = try h.join(&s, &.{ try s.text("/"), field_treepath, try s.text("/"), temporary1 });
    result = try s.concat(result, try s.stringify(temporary2));
    return c.JS_DupValue(engine.context, result);
}
pub fn template4(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_domain = try s.get(input, "domain");
    const field_user = try s.get(input, "user");
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    const field_treepath = try s.get(input, "treepath");
    const field_path = try s.get(input, "path");
    const field_fragment = try s.get(input, "fragment");
    const field_hashformat = try s.get(input, "hashformat");
    var result = try s.text("");
    result = try s.concat(result, try s.text("https://"));
    result = try s.concat(result, try s.stringify(field_domain));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_user));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_project));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_treepath));
    result = try s.concat(result, try s.text("/"));
    const temporary1 = if (s.truthy(field_committish)) field_committish else try s.text("HEAD");
    const temporary2 = try h.encode(&s, temporary1);
    result = try s.concat(result, try s.stringify(temporary2));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_path));
    const temporary3 = if (s.truthy(field_fragment)) field_fragment else try s.text("");
    const temporary4 = try s.call(field_hashformat, c.pi_js_undefined(), &.{ temporary3 });
    const temporary5 = try h.join(&s, &.{ try s.text("#"), temporary4 });
    result = try s.concat(result, try s.stringify(temporary5));
    return c.JS_DupValue(engine.context, result);
}
pub fn template5(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_domain = try s.get(input, "domain");
    const field_user = try s.get(input, "user");
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    const field_blobpath = try s.get(input, "blobpath");
    const field_path = try s.get(input, "path");
    const field_fragment = try s.get(input, "fragment");
    const field_hashformat = try s.get(input, "hashformat");
    var result = try s.text("");
    result = try s.concat(result, try s.text("https://"));
    result = try s.concat(result, try s.stringify(field_domain));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_user));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_project));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_blobpath));
    result = try s.concat(result, try s.text("/"));
    const temporary1 = if (s.truthy(field_committish)) field_committish else try s.text("HEAD");
    const temporary2 = try h.encode(&s, temporary1);
    result = try s.concat(result, try s.stringify(temporary2));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_path));
    const temporary3 = if (s.truthy(field_fragment)) field_fragment else try s.text("");
    const temporary4 = try s.call(field_hashformat, c.pi_js_undefined(), &.{ temporary3 });
    const temporary5 = try h.join(&s, &.{ try s.text("#"), temporary4 });
    result = try s.concat(result, try s.stringify(temporary5));
    return c.JS_DupValue(engine.context, result);
}
pub fn template6(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_domain = try s.get(input, "domain");
    const field_user = try s.get(input, "user");
    const field_project = try s.get(input, "project");
    const field_treepath = try s.get(input, "treepath");
    const field_committish = try s.get(input, "committish");
    var result = try s.text("");
    result = try s.concat(result, try s.text("https://"));
    result = try s.concat(result, try s.stringify(field_domain));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_user));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_project));
    const temporary1 = try h.encode(&s, field_committish);
    const temporary2 = try h.join(&s, &.{ try s.text("/"), field_treepath, try s.text("/"), temporary1 });
    result = try s.concat(result, try s.stringify(temporary2));
    result = try s.concat(result, try s.text("#readme"));
    return c.JS_DupValue(engine.context, result);
}
pub fn template7(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_auth = try s.get(input, "auth");
    const field_domain = try s.get(input, "domain");
    const field_user = try s.get(input, "user");
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    var result = try s.text("");
    result = try s.concat(result, try s.text("git+https://"));
    const temporary1 = try h.join(&s, &.{ field_auth, try s.text("@") });
    result = try s.concat(result, try s.stringify(temporary1));
    result = try s.concat(result, try s.stringify(field_domain));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_user));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_project));
    result = try s.concat(result, try s.text(".git"));
    const temporary2 = try h.join(&s, &.{ try s.text("#"), field_committish });
    result = try s.concat(result, try s.stringify(temporary2));
    return c.JS_DupValue(engine.context, result);
}
pub fn template8(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_domain = try s.get(input, "domain");
    const field_user = try s.get(input, "user");
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    const field_path = try s.get(input, "path");
    var result = try s.text("");
    result = try s.concat(result, try s.text("https://"));
    result = try s.concat(result, try s.stringify(field_domain));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_user));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_project));
    result = try s.concat(result, try s.text("/raw/"));
    const temporary1 = if (s.truthy(field_committish)) field_committish else try s.text("HEAD");
    const temporary2 = try h.encode(&s, temporary1);
    result = try s.concat(result, try s.stringify(temporary2));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_path));
    return c.JS_DupValue(engine.context, result);
}
pub fn template9(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_type = try s.get(input, "type");
    const field_user = try s.get(input, "user");
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    var result = try s.text("");
    result = try s.concat(result, try s.stringify(field_type));
    result = try s.concat(result, try s.text(":"));
    result = try s.concat(result, try s.stringify(field_user));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_project));
    const temporary1 = try h.join(&s, &.{ try s.text("#"), field_committish });
    result = try s.concat(result, try s.stringify(temporary1));
    return c.JS_DupValue(engine.context, result);
}
pub fn template10(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_user = try s.get(input, "user");
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    var result = try s.text("");
    result = try s.concat(result, try s.stringify(field_user));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_project));
    const temporary1 = try h.join(&s, &.{ try s.text("#"), field_committish });
    result = try s.concat(result, try s.stringify(temporary1));
    return c.JS_DupValue(engine.context, result);
}
pub fn template11(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_domain = try s.get(input, "domain");
    const field_user = try s.get(input, "user");
    const field_project = try s.get(input, "project");
    var result = try s.text("");
    result = try s.concat(result, try s.text("https://"));
    result = try s.concat(result, try s.stringify(field_domain));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_user));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_project));
    result = try s.concat(result, try s.text("/issues"));
    return c.JS_DupValue(engine.context, result);
}
pub fn template12(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_auth = try s.get(input, "auth");
    const field_user = try s.get(input, "user");
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    const field_path = try s.get(input, "path");
    var result = try s.text("");
    result = try s.concat(result, try s.text("https://"));
    const temporary1 = try h.join(&s, &.{ field_auth, try s.text("@") });
    result = try s.concat(result, try s.stringify(temporary1));
    result = try s.concat(result, try s.text("raw.githubusercontent.com/"));
    result = try s.concat(result, try s.stringify(field_user));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_project));
    result = try s.concat(result, try s.text("/"));
    const temporary2 = if (s.truthy(field_committish)) field_committish else try s.text("HEAD");
    const temporary3 = try h.encode(&s, temporary2);
    result = try s.concat(result, try s.stringify(temporary3));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_path));
    return c.JS_DupValue(engine.context, result);
}
pub fn template13(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_auth = try s.get(input, "auth");
    const field_domain = try s.get(input, "domain");
    const field_user = try s.get(input, "user");
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    var result = try s.text("");
    result = try s.concat(result, try s.text("git://"));
    const temporary1 = try h.join(&s, &.{ field_auth, try s.text("@") });
    result = try s.concat(result, try s.stringify(temporary1));
    result = try s.concat(result, try s.stringify(field_domain));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_user));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_project));
    result = try s.concat(result, try s.text(".git"));
    const temporary2 = try h.join(&s, &.{ try s.text("#"), field_committish });
    result = try s.concat(result, try s.stringify(temporary2));
    return c.JS_DupValue(engine.context, result);
}
pub fn template14(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_domain = try s.get(input, "domain");
    const field_user = try s.get(input, "user");
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    var result = try s.text("");
    result = try s.concat(result, try s.text("https://codeload."));
    result = try s.concat(result, try s.stringify(field_domain));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_user));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_project));
    result = try s.concat(result, try s.text("/tar.gz/"));
    const temporary1 = if (s.truthy(field_committish)) field_committish else try s.text("HEAD");
    const temporary2 = try h.encode(&s, temporary1);
    result = try s.concat(result, try s.stringify(temporary2));
    return c.JS_DupValue(engine.context, result);
}
pub fn template15(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_domain = try s.get(input, "domain");
    const field_user = try s.get(input, "user");
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    const field_treepath = try s.get(input, "treepath");
    const field_path = try s.get(input, "path");
    const field_editpath = try s.get(input, "editpath");
    var result = try s.text("");
    result = try s.concat(result, try s.text("https://"));
    result = try s.concat(result, try s.stringify(field_domain));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_user));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_project));
    const temporary1 = if (s.truthy(field_committish)) field_committish else try s.text("HEAD");
    const temporary2 = try h.encode(&s, temporary1);
    const temporary3 = try h.join(&s, &.{ try s.text("/"), field_treepath, try s.text("/"), temporary2, try s.text("/"), field_path, field_editpath });
    result = try s.concat(result, try s.stringify(temporary3));
    return c.JS_DupValue(engine.context, result);
}
pub fn template16(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_domain = try s.get(input, "domain");
    const field_user = try s.get(input, "user");
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    var result = try s.text("");
    result = try s.concat(result, try s.text("https://"));
    result = try s.concat(result, try s.stringify(field_domain));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_user));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_project));
    result = try s.concat(result, try s.text("/get/"));
    const temporary1 = if (s.truthy(field_committish)) field_committish else try s.text("HEAD");
    const temporary2 = try h.encode(&s, temporary1);
    result = try s.concat(result, try s.stringify(temporary2));
    result = try s.concat(result, try s.text(".tar.gz"));
    return c.JS_DupValue(engine.context, result);
}
pub fn template17(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_domain = try s.get(input, "domain");
    const field_user = try s.get(input, "user");
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    var result = try s.text("");
    result = try s.concat(result, try s.text("https://"));
    result = try s.concat(result, try s.stringify(field_domain));
    result = try s.concat(result, try s.text("/api/v4/projects/"));
    const temporary1 = try s.concat(field_user, try s.text("/"));
    const temporary2 = try s.concat(temporary1, field_project);
    const temporary3 = try h.encode(&s, temporary2);
    result = try s.concat(result, try s.stringify(temporary3));
    result = try s.concat(result, try s.text("/repository/archive.tar.gz?sha="));
    const temporary4 = if (s.truthy(field_committish)) field_committish else try s.text("HEAD");
    const temporary5 = try h.encode(&s, temporary4);
    result = try s.concat(result, try s.stringify(temporary5));
    return c.JS_DupValue(engine.context, result);
}
pub fn template18(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_domain = try s.get(input, "domain");
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    var result = try s.text("");
    result = try s.concat(result, try s.text("git@"));
    result = try s.concat(result, try s.stringify(field_domain));
    result = try s.concat(result, try s.text(":"));
    result = try s.concat(result, try s.stringify(field_project));
    result = try s.concat(result, try s.text(".git"));
    const temporary1 = try h.join(&s, &.{ try s.text("#"), field_committish });
    result = try s.concat(result, try s.stringify(temporary1));
    return c.JS_DupValue(engine.context, result);
}
pub fn template19(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_domain = try s.get(input, "domain");
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    var result = try s.text("");
    result = try s.concat(result, try s.text("git+ssh://git@"));
    result = try s.concat(result, try s.stringify(field_domain));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_project));
    result = try s.concat(result, try s.text(".git"));
    const temporary1 = try h.join(&s, &.{ try s.text("#"), field_committish });
    result = try s.concat(result, try s.stringify(temporary1));
    return c.JS_DupValue(engine.context, result);
}
pub fn template20(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_domain = try s.get(input, "domain");
    const field_user = try s.get(input, "user");
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    const field_editpath = try s.get(input, "editpath");
    var result = try s.text("");
    result = try s.concat(result, try s.text("https://"));
    result = try s.concat(result, try s.stringify(field_domain));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_user));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_project));
    const temporary1 = try h.encode(&s, field_committish);
    const temporary2 = try h.join(&s, &.{ try s.text("/"), temporary1 });
    result = try s.concat(result, try s.stringify(temporary2));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_editpath));
    return c.JS_DupValue(engine.context, result);
}
pub fn template21(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_domain = try s.get(input, "domain");
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    var result = try s.text("");
    result = try s.concat(result, try s.text("https://"));
    result = try s.concat(result, try s.stringify(field_domain));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_project));
    const temporary1 = try h.encode(&s, field_committish);
    const temporary2 = try h.join(&s, &.{ try s.text("/"), temporary1 });
    result = try s.concat(result, try s.stringify(temporary2));
    return c.JS_DupValue(engine.context, result);
}
pub fn template22(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_domain = try s.get(input, "domain");
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    const field_path = try s.get(input, "path");
    const field_hashformat = try s.get(input, "hashformat");
    var result = try s.text("");
    result = try s.concat(result, try s.text("https://"));
    result = try s.concat(result, try s.stringify(field_domain));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_project));
    const temporary1 = try h.encode(&s, field_committish);
    const temporary2 = try h.join(&s, &.{ try s.text("/"), temporary1 });
    result = try s.concat(result, try s.stringify(temporary2));
    const temporary3 = try s.call(field_hashformat, c.pi_js_undefined(), &.{ field_path });
    const temporary4 = try h.join(&s, &.{ try s.text("#"), temporary3 });
    result = try s.concat(result, try s.stringify(temporary4));
    return c.JS_DupValue(engine.context, result);
}
pub fn template23(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_domain = try s.get(input, "domain");
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    const field_path = try s.get(input, "path");
    const field_hashformat = try s.get(input, "hashformat");
    var result = try s.text("");
    result = try s.concat(result, try s.text("https://"));
    result = try s.concat(result, try s.stringify(field_domain));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_project));
    const temporary1 = try h.encode(&s, field_committish);
    const temporary2 = try h.join(&s, &.{ try s.text("/"), temporary1 });
    result = try s.concat(result, try s.stringify(temporary2));
    const temporary3 = try s.call(field_hashformat, c.pi_js_undefined(), &.{ field_path });
    const temporary4 = try h.join(&s, &.{ try s.text("#"), temporary3 });
    result = try s.concat(result, try s.stringify(temporary4));
    return c.JS_DupValue(engine.context, result);
}
pub fn template24(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_domain = try s.get(input, "domain");
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    var result = try s.text("");
    result = try s.concat(result, try s.text("https://"));
    result = try s.concat(result, try s.stringify(field_domain));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_project));
    const temporary1 = try h.encode(&s, field_committish);
    const temporary2 = try h.join(&s, &.{ try s.text("/"), temporary1 });
    result = try s.concat(result, try s.stringify(temporary2));
    return c.JS_DupValue(engine.context, result);
}
pub fn template25(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_domain = try s.get(input, "domain");
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    var result = try s.text("");
    result = try s.concat(result, try s.text("git+https://"));
    result = try s.concat(result, try s.stringify(field_domain));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_project));
    result = try s.concat(result, try s.text(".git"));
    const temporary1 = try h.join(&s, &.{ try s.text("#"), field_committish });
    result = try s.concat(result, try s.stringify(temporary1));
    return c.JS_DupValue(engine.context, result);
}
pub fn template26(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_user = try s.get(input, "user");
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    const field_path = try s.get(input, "path");
    var result = try s.text("");
    result = try s.concat(result, try s.text("https://gist.githubusercontent.com/"));
    result = try s.concat(result, try s.stringify(field_user));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_project));
    result = try s.concat(result, try s.text("/raw"));
    const temporary1 = try h.encode(&s, field_committish);
    const temporary2 = try h.join(&s, &.{ try s.text("/"), temporary1 });
    result = try s.concat(result, try s.stringify(temporary2));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_path));
    return c.JS_DupValue(engine.context, result);
}
pub fn template27(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_type = try s.get(input, "type");
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    var result = try s.text("");
    result = try s.concat(result, try s.stringify(field_type));
    result = try s.concat(result, try s.text(":"));
    result = try s.concat(result, try s.stringify(field_project));
    const temporary1 = try h.join(&s, &.{ try s.text("#"), field_committish });
    result = try s.concat(result, try s.stringify(temporary1));
    return c.JS_DupValue(engine.context, result);
}
pub fn template28(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    var result = try s.text("");
    result = try s.concat(result, try s.stringify(field_project));
    const temporary1 = try h.join(&s, &.{ try s.text("#"), field_committish });
    result = try s.concat(result, try s.stringify(temporary1));
    return c.JS_DupValue(engine.context, result);
}
pub fn template29(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_domain = try s.get(input, "domain");
    const field_project = try s.get(input, "project");
    var result = try s.text("");
    result = try s.concat(result, try s.text("https://"));
    result = try s.concat(result, try s.stringify(field_domain));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_project));
    return c.JS_DupValue(engine.context, result);
}
pub fn template30(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_domain = try s.get(input, "domain");
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    var result = try s.text("");
    result = try s.concat(result, try s.text("git://"));
    result = try s.concat(result, try s.stringify(field_domain));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_project));
    result = try s.concat(result, try s.text(".git"));
    const temporary1 = try h.join(&s, &.{ try s.text("#"), field_committish });
    result = try s.concat(result, try s.stringify(temporary1));
    return c.JS_DupValue(engine.context, result);
}
pub fn template31(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    var result = try s.text("");
    result = try s.concat(result, try s.text("https://codeload.github.com/gist/"));
    result = try s.concat(result, try s.stringify(field_project));
    result = try s.concat(result, try s.text("/tar.gz/"));
    const temporary1 = if (s.truthy(field_committish)) field_committish else try s.text("HEAD");
    const temporary2 = try h.encode(&s, temporary1);
    result = try s.concat(result, try s.stringify(temporary2));
    return c.JS_DupValue(engine.context, result);
}
pub fn template32(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_domain = try s.get(input, "domain");
    const field_user = try s.get(input, "user");
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    const field_path = try s.get(input, "path");
    var result = try s.text("");
    result = try s.concat(result, try s.text("https://"));
    result = try s.concat(result, try s.stringify(field_domain));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_user));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_project));
    result = try s.concat(result, try s.text("/blob/"));
    const temporary1 = try h.encode(&s, field_committish);
    const temporary2 = if (s.truthy(temporary1)) temporary1 else try s.text("HEAD");
    result = try s.concat(result, try s.stringify(temporary2));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_path));
    return c.JS_DupValue(engine.context, result);
}
pub fn template33(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_domain = try s.get(input, "domain");
    const field_user = try s.get(input, "user");
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    var result = try s.text("");
    result = try s.concat(result, try s.text("https://"));
    result = try s.concat(result, try s.stringify(field_domain));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_user));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_project));
    const temporary1 = try h.join(&s, &.{ try s.text("#"), field_committish });
    result = try s.concat(result, try s.stringify(temporary1));
    return c.JS_DupValue(engine.context, result);
}
pub fn template34(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);
    const field_domain = try s.get(input, "domain");
    const field_user = try s.get(input, "user");
    const field_project = try s.get(input, "project");
    const field_committish = try s.get(input, "committish");
    var result = try s.text("");
    result = try s.concat(result, try s.text("https://"));
    result = try s.concat(result, try s.stringify(field_domain));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_user));
    result = try s.concat(result, try s.text("/"));
    result = try s.concat(result, try s.stringify(field_project));
    result = try s.concat(result, try s.text("/archive/"));
    const temporary1 = try h.encode(&s, field_committish);
    const temporary2 = if (s.truthy(temporary1)) temporary1 else try s.text("HEAD");
    result = try s.concat(result, try s.stringify(temporary2));
    result = try s.concat(result, try s.text(".tar.gz"));
    return c.JS_DupValue(engine.context, result);
}
