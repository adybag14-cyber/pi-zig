//! Actual pi-ai utils/model-operations namespace over the shared ModelsError.
//! No model registry or SDK state is manufactured by these public helpers.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const functions = @import("native_node_function.zig");
const c = em.c;
const Operation = enum(c_int) {
    getModelType,
    isModelType,
    assertChatModel,
    assertImageModel,
    assertClassifierModel,
    assertClassifierInputSupported,
    imageErrorResult,
    classifierErrorResult,
};

/// The assembler supplies the same actual ModelsError constructor exported by
/// pi-ai; assertions must not create an independently branded error family.
pub fn create(engine: *em.Engine, models_error: c.JSValue) !c.JSValue {
    if (!c.JS_IsConstructor(engine.context, models_error)) return error.RequiredActualModelsError;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const exports = try scope.object();
    inline for (@typeInfo(Operation).@"enum".fields) |field| {
        const operation: Operation = @enumFromInt(field.value);
        const length: c_int = switch (operation) {
            .getModelType, .assertChatModel, .assertImageModel, .assertClassifierModel => 1,
            else => 2,
        };
        const roots = [_]c.JSValue{ models_error, c.JS_NewInt32(engine.context, field.value) };
        const function = try scope.own(try functions.create(engine, field.name, length, dispatch, &roots));
        try scope.put(exports, field.name, function);
    }
    return c.JS_DupValue(engine.context, exports);
}

fn arg(arguments: []const c.JSValue, index: usize) c.JSValue {
    return if (index < arguments.len) arguments[index] else c.pi_js_undefined();
}
fn modelType(scope: *Scope, model: c.JSValue) !c.JSValue {
    const value = try scope.get(model, "type");
    return if (temp.nullish(value)) scope.text("chat") else value;
}
fn throwProvider(scope: *Scope, constructor: c.JSValue, model: c.JSValue, suffix: []const u8) !c.JSValue {
    // Template interpolation uses ToString, in provider-then-id order, rather
    // than String(value), whose Symbol special case would change behavior.
    const provider = try scope.own(try scope.engine.checked(c.JS_ToString(scope.engine.context, try scope.get(model, "provider"))));
    const id = try scope.own(try scope.engine.checked(c.JS_ToString(scope.engine.context, try scope.get(model, "id"))));
    const message = try scope.concat(try scope.concat(try scope.concat(try scope.text("Model "), provider), try scope.text("/")), id);
    var arguments = [_]c.JSValue{ try scope.text("provider"), try scope.concat(message, try scope.text(suffix)) };
    const reason = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, arguments.len, &arguments)));
    return scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, reason)));
}
fn dispatch(engine: *em.Engine, _: c.JSValue, arguments: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var mode: i32 = 0;
    if (c.JS_ToInt32(engine.context, &mode, roots[1]) < 0) return js.capture(engine);
    const operation: Operation = @enumFromInt(mode);
    const model = arg(arguments, 0);
    switch (operation) {
        .getModelType => return c.JS_DupValue(engine.context, try modelType(&scope, model)),
        .isModelType => return c.pi_js_bool(engine.context, @intFromBool(scope.equal(try modelType(&scope, model), arg(arguments, 1)))),
        .assertChatModel, .assertImageModel, .assertClassifierModel => {
            const expected = switch (operation) {
                .assertChatModel => "chat",
                .assertImageModel => "image",
                .assertClassifierModel => "classifier",
                else => unreachable,
            };
            if (scope.equal(try modelType(&scope, model), try scope.text(expected))) return c.pi_js_undefined();
            return throwProvider(&scope, roots[0], model, switch (operation) {
                .assertChatModel => " is not a chat model",
                .assertImageModel => " is not an image model",
                .assertClassifierModel => " is not a classifier model",
                else => unreachable,
            });
        },
        .assertClassifierInputSupported => {
            const images = try scope.get(arg(arguments, 1), "images");
            if (temp.nullish(images) or !scope.truthy(try scope.get(images, "length"))) return c.pi_js_undefined();
            const input = try scope.get(model, "input");
            if (scope.truthy(try scope.invoke(input, "includes", &.{try scope.text("image")}))) return c.pi_js_undefined();
            return throwProvider(&scope, roots[0], model, " does not accept image input");
        },
        .imageErrorResult, .classifierErrorResult => {
            const result = try scope.object();
            try scope.put(result, "api", try scope.get(model, "api"));
            try scope.put(result, "provider", try scope.get(model, "provider"));
            try scope.put(result, "model", try scope.get(model, "id"));
            if (operation == .imageErrorResult) {
                try scope.put(result, "output", try scope.array());
            } else {
                try scope.put(result, "answers", try scope.object());
            }
            try scope.put(result, "stopReason", try scope.text(if (scope.truthy(arg(arguments, 2))) "aborted" else "error"));
            const reason = arg(arguments, 1);
            const is_error = c.JS_IsInstanceOf(engine.context, reason, try scope.global("Error"));
            if (is_error < 0) return js.capture(engine);
            const message = if (is_error != 0) try scope.get(reason, "message") else try scope.call(try scope.global("String"), c.pi_js_undefined(), &.{reason});
            try scope.put(result, "errorMessage", message);
            try scope.put(result, "timestamp", try scope.invoke(try scope.global("Date"), "now", &.{}));
            return c.JS_DupValue(engine.context, result);
        },
    }
}
