/* Included after js_parse_init. No outer program or concatenated body parser. */
_Static_assert(PI_COMPILER_CATEGORY_NONE == JS_PI_CJS_NO_SYNTAX_CATEGORY &&
               PI_COMPILER_CATEGORY_ORDINARY == JS_PI_CJS_ORDINARY_SYNTAX &&
               PI_COMPILER_CATEGORY_DIRECT_MODULE == JS_PI_CJS_DIRECT_MODULE_SYNTAX &&
               PI_COMPILER_CATEGORY_ESM_PROBE == JS_PI_CJS_ESM_PARSE_REQUIRED,
               "native compiler diagnostic protocol");

static JSValue js_pi_compiler_admission_error(JSContext *ctx, const char *text)
{
    JSValue object = JS_NewObjectProtoClass(ctx, ctx->native_error_proto[JS_TYPE_ERROR],
                                           JS_CLASS_ERROR);
    JSValue message;
    if (JS_IsException(object) || JS_HasException(ctx))
        return js_pi_compiler_fail_owned(ctx, object);
    message = JS_NewString(ctx, text);
    if (JS_IsException(message) || JS_HasException(ctx)) {
        js_pi_compiler_fail_owned(ctx, message);
        return js_pi_compiler_fail_owned(ctx, object);
    }
    if (JS_DefinePropertyValue(ctx, object, JS_ATOM_message, message,
                               JS_PROP_WRITABLE | JS_PROP_CONFIGURABLE) < 0 ||
        JS_HasException(ctx))
        return js_pi_compiler_fail_owned(ctx, object);
    return JS_Throw(ctx, object); /* No eager legacy prepareStackTrace lookup. */
}

static bool js_pi_compiler_operational(JSPiCompilerDiagnostic *diagnostic)
{
    return diagnostic->allocation_failed || diagnostic->stack_failed ||
        diagnostic->interrupted || diagnostic->capacity_failed;
}

static int js_pi_compiler_inputs(JSContext *ctx, JSValueConst source,
                                  JSValueConst origin, const char **body,
                                  size_t *body_length, const char **filename)
{
    size_t filename_length;
    if (!JS_IsString(source) || !JS_IsString(origin)) {
        js_pi_compiler_admission_error(ctx, "compiler source and physical filename must be primitive strings");
        return -1;
    }
    *body = JS_ToCStringLen(ctx, body_length, source);
    if (!*body || JS_HasException(ctx))
        return -1;
    *filename = JS_ToCStringLen(ctx, &filename_length, origin);
    if (!*filename || JS_HasException(ctx))
        return -1;
    if (memchr(*filename, 0, filename_length)) {
        js_pi_compiler_admission_error(ctx, "compiler physical filename containing NUL is unsupported");
        return -1;
    }
    return 0;
}

static bool js_pi_compiler_admitted(JSContext *ctx)
{
    return !ctx->pi_compiler_diagnostic && ctx->rt->native_error_stack_hook &&
        !ctx->rt->native_error_stack_hook_active;
}

static JSValue js_pi_compile_cjs_function(JSContext *ctx, JSValueConst source,
                                JSValueConst physical_filename,
                                JSPiCJSParseCategory *category,
                                JSValue *source_url, JSValue *source_map_url)
{
    static const char *const parameters[5] = {
        "exports", "require", "module", "__filename", "__dirname"
    };
    static const char prefix[] = "function (exports, require, module, __filename, __dirname) {\n";
    static const char suffix[] = "\n}";
    JSPiCompilerDiagnostic diagnostic = {
        .requested_category = PI_COMPILER_CATEGORY_ORDINARY, .line = 1, .column = 1,
        .collect_source_metadata = true
    };
    JSParseState state;
    JSFunctionDef *parent = NULL, *function = NULL;
    JSValue bytecode = JS_UNDEFINED, result = JS_UNDEFINED, first;
    JSValue url = JS_UNDEFINED, map = JS_UNDEFINED;
    const char *body = NULL, *filename = NULL;
    size_t body_length = 0, presentation_length;
    bool parser_ready = false;
    int i;
    if (category)
        *category = JS_PI_CJS_NO_SYNTAX_CATEGORY;
    if (JS_HasException(ctx))
        return JS_EXCEPTION;
    if (!category || !js_pi_compiler_admitted(ctx))
        return js_pi_compiler_admission_error(ctx, "compiler diagnostic output and capture-only native Error owner required");
    ctx->pi_compiler_diagnostic = &diagnostic;
    if (js_pi_compiler_inputs(ctx, source, physical_filename, &body, &body_length, &filename))
        goto fail;
    diagnostic.filename = filename;
    js_parse_init(ctx, &state, body, body_length, filename, 1);
    parser_ready = true;
    if (skip_shebang_with_context(ctx, &state.buf_ptr, state.buf_end))
        goto fail; /* actual VM entry lexer policy, opted-in polling */
    parent = js_new_function_def(ctx, NULL, true, false, filename, 1, 1);
    if (!parent || JS_HasException(ctx))
        goto fail;
    parent->eval_type = JS_EVAL_TYPE_GLOBAL;
    parent->is_global_var = true;
    parent->has_this_binding = true;
    parent->arguments_allowed = true;
    state.cur_func = parent;
    state.allow_html_comments = true;
    if (push_scope(&state) < 0 || JS_HasException(ctx))
        goto fail;
    parent->body_scope = parent->scope_level;
    function = js_new_function_def(ctx, parent, false, false, filename, 1, 1);
    if (!function || JS_HasException(ctx))
        goto fail;
    state.cur_func = function;
    diagnostic.root_definition = function;
    function->func_name = JS_DupAtom(ctx, JS_ATOM_empty_string);
    function->func_kind = JS_FUNC_NORMAL;
    function->func_type = JS_PARSE_FUNC_EXPR;
    function->has_prototype = true;
    function->has_simple_parameter_list = true;
    function->has_arguments_binding = true;
    function->has_this_binding = true;
    function->new_target_allowed = true;
    function->arguments_allowed = true;
    function->in_function_body = true;
    for (i = 0; i < 5; i++) {
        JSAtom atom;
        if (JS_HasException(ctx) || js_poll_interrupts(ctx) || JS_HasException(ctx))
            goto fail;
        atom = JS_NewAtom(ctx, parameters[i]);
        if (atom == JS_ATOM_NULL)
            goto fail;
        int index = add_arg(ctx, function, atom);
        JS_FreeAtom(ctx, atom);
        if (index < 0 || JS_HasException(ctx))
            goto fail;
    }
    function->defined_arg_count = 5;
    if (push_scope(&state) < 0 || JS_HasException(ctx))
        goto fail;
    function->body_scope = function->scope_level;
    if (next_token(&state) ||
        js_parse_ordinary_function_body(&state, function, function->func_name,
                                        TOK_EOF, state.buf_start, false) ||
        JS_HasException(ctx))
        goto fail;
    /* This retained presentation is never parsed or executed. Parser/debug
       coordinates are over the original body, without a synthetic prefix. */
    if (body_length > INT_MAX - (sizeof(prefix) - 1) - (sizeof(suffix) - 1)) {
        diagnostic.capacity_failed = true;
        JS_ThrowInternalError(ctx, "compiled function source presentation is too large");
        goto fail;
    }
    presentation_length = sizeof(prefix) - 1 + body_length + sizeof(suffix) - 1;
    function->source = js_malloc(ctx, presentation_length + 1);
    if (!function->source)
        goto fail;
    memcpy(function->source, prefix, sizeof(prefix) - 1);
    memcpy(function->source + sizeof(prefix) - 1, body, body_length);
    memcpy(function->source + sizeof(prefix) - 1 + body_length, suffix, sizeof(suffix));
    function->source_len = (int)presentation_length;
    {
        JSFunctionDef *consumed = function;
        function = NULL;
        diagnostic.root_definition = NULL;
        bytecode = js_create_function(ctx, consumed); /* consumes FD on every exit */
    }
    if (JS_IsException(bytecode) || JS_HasException(ctx) || js_pi_compiler_operational(&diagnostic))
        goto fail;
    /* The bookkeeping parent contains no user declarations or local bindings.
       A real free name must resolve through the VM's global environment. */
    if (((JSFunctionBytecode *)JS_VALUE_GET_PTR(bytecode))->closure_var_count) {
        JS_ThrowInternalError(ctx, "native CJS compiler unexpectedly captured bookkeeping parent");
        goto fail;
    }
    {
        JSValue consumed = bytecode;
        bytecode = JS_UNDEFINED;
        result = js_closure(ctx, consumed, NULL, NULL); /* consumes raw bytecode */
    }
    if (JS_IsException(result) || JS_HasException(ctx) || js_pi_compiler_operational(&diagnostic))
        goto fail;
    if (source_url) {
        url = diagnostic.source_url_length ?
            JS_NewStringLen(ctx, (const char *)diagnostic.source_url, diagnostic.source_url_length) :
            JS_DupValue(ctx, physical_filename);
        if (JS_IsException(url) || JS_HasException(ctx))
            goto fail;
        if (diagnostic.source_map_url_length) {
            map = JS_NewStringLen(ctx, (const char *)diagnostic.source_map_url, diagnostic.source_map_url_length);
            if (JS_IsException(map) || JS_HasException(ctx))
                goto fail;
        }
    }
    free_token(&state, &state.token);
    js_free_function_def(ctx, parent);
    JS_FreeCString(ctx, body);
    JS_FreeCString(ctx, filename);
    ctx->pi_compiler_diagnostic = NULL;
    if (source_url) {
        *source_url = url;
        *source_map_url = map;
    }
    return result;
fail:
    first = JS_HasException(ctx) ? JS_GetException(ctx) : JS_NULL;
    if (parser_ready)
        free_token(&state, &state.token);
    if (function)
        js_free_function_def(ctx, function);
    if (parent)
        js_free_function_def(ctx, parent);
    JS_FreeValue(ctx, bytecode);
    JS_FreeValue(ctx, result);
    JS_FreeValue(ctx, url);
    JS_FreeValue(ctx, map);
    JS_FreeCString(ctx, body);
    JS_FreeCString(ctx, filename);
    if (!js_pi_compiler_operational(&diagnostic))
        *category = (JSPiCJSParseCategory)diagnostic.completed_category;
    ctx->pi_compiler_diagnostic = NULL;
    return JS_Throw(ctx, first);
}

JSValue JS_PiCompileCJSFunction(JSContext *ctx, JSValueConst source,
                                JSValueConst physical_filename,
                                JSPiCJSParseCategory *category)
{
    return js_pi_compile_cjs_function(ctx, source, physical_filename, category, NULL, NULL);
}

JSValue JS_PiCompileCJSFunctionInfo(JSContext *ctx, JSValueConst source,
                                    JSValueConst physical_filename,
                                    JSPiCJSParseCategory *category,
                                    JSValue *source_url, JSValue *source_map_url)
{
    if (category)
        *category = JS_PI_CJS_NO_SYNTAX_CATEGORY;
    if (JS_HasException(ctx))
        return JS_EXCEPTION;
    if (!source_url || !source_map_url || source_url == source_map_url)
        return js_pi_compiler_admission_error(ctx, "owned compiler metadata outputs required");
    return js_pi_compile_cjs_function(ctx, source, physical_filename, category,
                                      source_url, source_map_url);
}

JSValue JS_PiCompileCommonJSScriptInfo(JSContext *ctx, JSValueConst source,
                                       JSValueConst physical_filename,
                                       JSValue *source_url, JSValue *source_map_url)
{
    JSPiCompilerDiagnostic diagnostic = {
        .requested_category = PI_COMPILER_CATEGORY_ORDINARY, .line = 1, .column = 1,
        .collect_source_metadata = true,
    };
    JSValue bytecode = JS_UNDEFINED, url = JS_UNDEFINED, map = JS_UNDEFINED, first;
    const char *body = NULL, *filename = NULL;
    size_t length = 0;
    JSEvalOptions options;
    if (JS_HasException(ctx))
        return JS_EXCEPTION;
    if (!source_url || !source_map_url || source_url == source_map_url || !js_pi_compiler_admitted(ctx))
        return js_pi_compiler_admission_error(ctx, "owned script metadata outputs and capture-only native Error owner required");
    ctx->pi_compiler_diagnostic = &diagnostic;
    if (js_pi_compiler_inputs(ctx, source, physical_filename, &body, &length, &filename))
        goto fail;
    diagnostic.filename = filename;
    memset(&options, 0, sizeof(options));
    options.version = JS_EVAL_OPTIONS_VERSION;
    options.eval_flags = JS_EVAL_TYPE_GLOBAL | JS_EVAL_FLAG_COMPILE_ONLY;
    options.filename = filename;
    options.line_num = 1;
    bytecode = JS_Eval2(ctx, body, length, &options);
    if (JS_IsException(bytecode) || JS_HasException(ctx) || js_pi_compiler_operational(&diagnostic))
        goto fail;
    url = diagnostic.source_url_length ?
        JS_NewStringLen(ctx, (const char *)diagnostic.source_url, diagnostic.source_url_length) :
        JS_DupValue(ctx, physical_filename);
    if (JS_IsException(url) || JS_HasException(ctx))
        goto fail;
    if (diagnostic.source_map_url_length) {
        map = JS_NewStringLen(ctx, (const char *)diagnostic.source_map_url, diagnostic.source_map_url_length);
        if (JS_IsException(map) || JS_HasException(ctx))
            goto fail;
    }
    JS_FreeCString(ctx, body);
    JS_FreeCString(ctx, filename);
    ctx->pi_compiler_diagnostic = NULL;
    *source_url = url;
    *source_map_url = map;
    return bytecode;
 fail:
    first = JS_HasException(ctx) ? JS_GetException(ctx) : JS_NULL;
    JS_FreeValue(ctx, bytecode);
    JS_FreeValue(ctx, url);
    JS_FreeValue(ctx, map);
    JS_FreeCString(ctx, body);
    JS_FreeCString(ctx, filename);
    ctx->pi_compiler_diagnostic = NULL;
    return JS_Throw(ctx, first);
}

int JS_PiParseModuleSyntax(JSContext *ctx, JSValueConst source,
                            JSValueConst physical_filename, unsigned *syntax_flags,
                            JSPiModuleParseDiagnostic *completion)
{
    JSPiCompilerDiagnostic diagnostic = {
        .requested_category = PI_COMPILER_CATEGORY_ORDINARY, .line = 1, .column = 1,
        .module_probe = true
    };
    JSParseState state;
    JSFunctionDef *function = NULL;
    JSModuleDef *module = NULL;
    JSValue bytecode = JS_UNDEFINED, first;
    const char *body = NULL, *filename = NULL;
    size_t length = 0;
    bool parser_ready = false;
    int status;
    if (completion)
        *completion = JS_PI_MODULE_NO_SYNTAX_DIAGNOSTIC;
    if (JS_HasException(ctx))
        return -1;
    if (!completion || !syntax_flags || !js_pi_compiler_admitted(ctx)) {
        js_pi_compiler_admission_error(ctx, "probe outputs and capture-only native Error owner required");
        return -1;
    }
    ctx->pi_compiler_diagnostic = &diagnostic;
    if (js_pi_compiler_inputs(ctx, source, physical_filename, &body, &length, &filename))
        goto fail;
    diagnostic.filename = filename;
    {
        JSAtom atom = JS_NewAtom(ctx, filename);
        if (atom == JS_ATOM_NULL)
            goto fail;
        module = js_new_module_def(ctx, atom); /* consumes name atom */
    }
    if (!module)
        goto fail;
    /* Constructor publishes only at its end. Detach before any next allocation
       or callback, and leave a self-link compatible with ordinary module free. */
    list_del(&module->link);
    init_list_head(&module->link);
    js_parse_init(ctx, &state, body, length, filename, 1);
    parser_ready = true;
    if (skip_shebang_with_context(ctx, &state.buf_ptr, state.buf_end))
        goto fail;
    function = js_new_function_def(ctx, NULL, true, false, filename, 1, 1);
    if (!function || JS_HasException(ctx))
        goto fail;
    state.cur_func = function;
    state.is_module = true;
    function->eval_type = JS_EVAL_TYPE_MODULE;
    function->module = module;
    function->has_this_binding = true;
    function->arguments_allowed = true;
    function->is_strict_mode = true;
    function->func_name = JS_DupAtom(ctx, JS_ATOM__eval_);
    function->func_kind = JS_FUNC_ASYNC;
    function->in_function_body = true;
    if (push_scope(&state) < 0 || JS_HasException(ctx))
        goto fail;
    function->body_scope = function->scope_level;
    if (js_parse_program(&state) || JS_HasException(ctx))
        goto fail;
    module->has_tla = function->has_await;
    if (module->has_tla)
        diagnostic.syntax_flags |= JS_PI_MODULE_TOP_LEVEL_AWAIT;
    {
        JSFunctionDef *consumed = function;
        function = NULL;
        bytecode = js_create_function(ctx, consumed); /* real semantic passes */
    }
    if (JS_IsException(bytecode) || JS_HasException(ctx) || js_pi_compiler_operational(&diagnostic))
        goto fail;
    module->func_obj = bytecode;
    bytecode = JS_UNDEFINED;
    free_token(&state, &state.token);
    js_free_module_def(ctx, module); /* detached, no sweep of other modules */
    JS_FreeCString(ctx, body);
    JS_FreeCString(ctx, filename);
    *syntax_flags = diagnostic.syntax_flags;
    ctx->pi_compiler_diagnostic = NULL;
    return 0;
fail:
    first = JS_HasException(ctx) ? JS_GetException(ctx) : JS_NULL;
    if (parser_ready)
        free_token(&state, &state.token);
    if (function)
        js_free_function_def(ctx, function);
    JS_FreeValue(ctx, bytecode);
    if (module)
        js_free_module_def(ctx, module);
    JS_FreeCString(ctx, body);
    JS_FreeCString(ctx, filename);
    status = !js_pi_compiler_operational(&diagnostic) && diagnostic.completed_category ? 1 : -1;
    if (status == 1)
        *completion = JS_PI_MODULE_ORDINARY_SYNTAX;
    ctx->pi_compiler_diagnostic = NULL;
    JS_Throw(ctx, first);
    return status;
}
