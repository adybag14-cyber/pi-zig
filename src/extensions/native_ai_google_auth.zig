//! Google API-key/Vertex project, endpoint and native ADC resolution.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
fn env(scope: *Scope, dependencies: c.JSValue, options: c.JSValue, name: []const u8) !c.JSValue {
    return scope.invoke(try scope.get(dependencies, "env"), "getProviderEnvValue", &.{ try scope.text(name), try v.optional(scope, options, "env") });
}
pub fn key(scope: *Scope, options: c.JSValue) !c.JSValue {
    const value = try v.optional(scope, options, "apiKey");
    if (v.nullish(value)) return c.pi_js_undefined();
    const trimmed = try scope.invoke(value, "trim", &.{});
    if (!scope.truthy(trimmed) or try v.eq(scope, trimmed, "gcp-vertex-credentials")) return c.pi_js_undefined();
    const regex = try scope.own(try v.js.builtin(scope.engine, "RegExp", &.{try scope.text("^<[^>]+>$")}));
    return if (scope.truthy(try scope.invoke(regex, "test", &.{trimmed}))) c.pi_js_undefined() else trimmed;
}
pub fn resolve(scope: *Scope, dependencies: c.JSValue, model: c.JSValue, options: c.JSValue, vertex: bool) !c.JSValue {
    const result = try scope.object();
    const api_key = if (vertex) try key(scope, options) else try v.optional(scope, options, "apiKey");
    if (!vertex and !scope.truthy(api_key)) return v.errorText(scope, try scope.concat(try scope.text("No API key for provider: "), try scope.stringify(try scope.get(model, "provider"))));
    try scope.put(result, "apiKey", api_key);
    var base = try scope.get(model, "baseUrl");
    if (vertex) {
        if (!scope.truthy(base) or scope.truthy(try scope.invoke(base, "includes", &.{try scope.text("{location}")}))) base = c.pi_js_undefined() else base = try scope.invoke(base, "trim", &.{});
        if (!scope.truthy(api_key)) {
            var project = try v.optional(scope, options, "project");
            if (!scope.truthy(project)) project = try env(scope, dependencies, options, "GOOGLE_CLOUD_PROJECT");
            if (!scope.truthy(project)) project = try env(scope, dependencies, options, "GCLOUD_PROJECT");
            if (!scope.truthy(project)) return v.errorText(scope, try scope.text("Vertex AI requires a project ID. Set GOOGLE_CLOUD_PROJECT/GCLOUD_PROJECT or pass project in options."));
            var location = try v.optional(scope, options, "location");
            if (!scope.truthy(location)) location = try env(scope, dependencies, options, "GOOGLE_CLOUD_LOCATION");
            if (!scope.truthy(location)) return v.errorText(scope, try scope.text("Vertex AI requires a location. Set GOOGLE_CLOUD_LOCATION or pass location in options."));
            const standard = !scope.truthy(base);
            if (standard) {
                base = if (try v.eq(scope, location, "global")) try scope.text("https://aiplatform.googleapis.com/v1") else try scope.concat(try scope.concat(try scope.text("https://"), try scope.stringify(location)), try scope.text("-aiplatform.googleapis.com/v1"));
            } else base = try versioned(scope, base);
            if (standard) {
                base = try scope.concat(try scope.concat(base, try scope.text("/projects/")), try scope.stringify(project));
                base = try scope.concat(try scope.concat(base, try scope.text("/locations/")), try scope.stringify(location));
            }
            try scope.put(result, "base", base);
            try scope.put(result, "adc", c.pi_js_bool(scope.engine.context, 1));
            return result;
        }
        if (!scope.truthy(base)) base = try scope.text("https://aiplatform.googleapis.com/v1") else base = try versioned(scope, base);
    } else if (!scope.truthy(base)) base = try scope.text("https://generativelanguage.googleapis.com/v1beta");
    try scope.put(result, "base", base);
    try scope.put(result, "adc", c.pi_js_bool(scope.engine.context, 0));
    return result;
}
fn versioned(scope: *Scope, base: c.JSValue) !c.JSValue {
    const regex = try scope.own(try v.js.builtin(scope.engine, "RegExp", &.{try scope.text("(?:^|/)v\\d+(?:beta\\d*)?(?:/|$)")}));
    return if (scope.truthy(try scope.invoke(regex, "test", &.{base}))) base else scope.concat(base, try scope.text("/v1"));
}
pub fn adc(scope: *Scope, dependencies: c.JSValue, options: c.JSValue, auth: c.JSValue) !void {
    const engine = scope.engine;
    const io = engine.native_io orelse return error.NativeGoogleADCRequiresIo;
    var environment: std.process.Environ.Map = .init(engine.gpa);
    defer environment.deinit();
    inline for (.{ "GOOGLE_APPLICATION_CREDENTIALS", "HOME", "USERPROFILE" }) |name| {
        const value = try env(scope, dependencies, options, name);
        if (scope.truthy(value)) {
            const bytes = try engine.toString(value);
            defer engine.gpa.free(bytes);
            try environment.put(name, bytes);
        }
    }
    var credential = (try @import("../ai/google_adc.zig").load(engine.gpa, io, &environment)) orelse return error.GoogleApplicationDefaultCredentialsNotFound;
    defer credential.deinit(engine.gpa);
    var token = switch (credential.kind) {
        .authorized_user => try @import("../ai/google_adc.zig").refreshAuthorizedUser(engine.gpa, io, &credential),
        .service_account => try @import("../ai/google_adc.zig").refreshServiceAccount(engine.gpa, io, &credential),
    };
    defer token.deinit(engine.gpa);
    try scope.put(auth, "bearer", try scope.text(token.token));
    if (credential.quota_project_id) |project| try scope.put(auth, "quota", try scope.text(project));
}
