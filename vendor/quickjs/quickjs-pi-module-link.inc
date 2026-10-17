/* Private synchronous link transaction; included immediately after js_link_module.
   The host contract forbids graph mutation/reentry and requires capture-only
   Error stacks. ModuleDefs remain owned by the live context throughout. */
typedef struct JSPiLinkMember {
    JSModuleDef *module;
    size_t record_plus_one;
} JSPiLinkMember;

typedef struct JSPiLinkRecord {
    JSModuleDef *module;
    JSValue original_function;
    JSModuleDef *original_stack;
    int original_index, original_ancestor;
    bool fresh, touched;
} JSPiLinkRecord;

typedef struct JSPiLinkFrame {
    size_t record;
    int next_request;
} JSPiLinkFrame;

typedef struct JSPiLinkAttempt {
    size_t capacity, count, used;
    JSPiLinkMember *members;
    JSPiLinkRecord *records;
    JSPiLinkFrame *frames;
} JSPiLinkAttempt;

static size_t js_pi_link_pointer_hash(JSModuleDef *module)
{
    uintptr_t value = (uintptr_t)module;
    value ^= value >> 4;
    value *= (uintptr_t)0x9e3779b1U;
    value ^= value >> 16;
    return (size_t)value;
}

/* Neither the lookup key nor a failed lookup is dereferenced. */
static JSPiLinkMember *js_pi_link_member(JSContext *ctx, JSPiLinkAttempt *attempt,
                                        JSModuleDef *module)
{
    size_t probe, slot = js_pi_link_pointer_hash(module) & (attempt->capacity - 1);
    for (probe = 0; probe < attempt->capacity; probe++) {
        JSPiLinkMember *entry;
        if (js_pi_link_poll(ctx))
            return NULL;
        entry = &attempt->members[slot];
        if (!entry->module || entry->module == module)
            return entry;
        slot = (slot + 1) & (attempt->capacity - 1);
    }
    JS_ThrowInternalError(ctx, "module link membership table is full");
    return NULL;
}

static int js_pi_link_admission_error(JSContext *ctx, const char *message)
{
    /* Before the capture-only callback has been admitted, do not enter the
       legacy eager Error.prepareStackTrace path even for an admission error. */
    JSValue object, text;
    object = JS_NewObjectProtoClass(ctx, ctx->native_error_proto[JS_TYPE_ERROR],
                                    JS_CLASS_ERROR);
    if (JS_IsException(object) || JS_HasException(ctx)) {
        js_pi_link_failure_free(ctx, object);
        return -1;
    }
    text = JS_NewString(ctx, message);
    if (JS_IsException(text) || JS_HasException(ctx)) {
        JSValue first = JS_HasException(ctx) ? JS_GetException(ctx) : JS_NULL;
        JS_FreeValue(ctx, text);
        JS_FreeValue(ctx, object);
        JS_Throw(ctx, first);
        return -1;
    }
    if (JS_DefinePropertyValue(ctx, object, JS_ATOM_message, text,
                              JS_PROP_WRITABLE | JS_PROP_CONFIGURABLE) < 0 ||
        JS_HasException(ctx)) {
        js_pi_link_failure_free(ctx, object);
        return -1;
    }
    JS_Throw(ctx, object);
    return -1;
}

static int js_pi_link_validate_node(JSContext *ctx, JSPiLinkAttempt *attempt,
                                     JSModuleDef *module)
{
    int i, variables = 0;
    bool fresh = module->status == JS_MODULE_STATUS_UNLINKED;
    JSFunctionBytecode *bytecode = NULL;
    switch (module->status) {
    case JS_MODULE_STATUS_UNLINKED:
    case JS_MODULE_STATUS_LINKED:
    case JS_MODULE_STATUS_EVALUATING_ASYNC:
    case JS_MODULE_STATUS_EVALUATED:
        break;
    default:
        goto invalid;
    }
    if (!module->resolved || (!fresh && !module->func_created) ||
        module->req_module_entries_count < 0 || module->export_entries_count < 0 ||
        module->import_entries_count < 0 || module->star_export_entries_count < 0 ||
        (module->req_module_entries_count && !module->req_module_entries) ||
        (module->export_entries_count && !module->export_entries) ||
        (module->import_entries_count && !module->import_entries) ||
        (module->star_export_entries_count && !module->star_export_entries))
        goto invalid;
    if (fresh) {
        if (module->func_created || !JS_IsUndefined(module->module_ns) ||
            !JS_IsUndefined(module->promise) || module->eval_has_exception ||
            module->async_evaluation || module->pending_async_dependencies)
            goto invalid;
        if (!module->init_func) {
            if (JS_VALUE_GET_TAG(module->func_obj) != JS_TAG_FUNCTION_BYTECODE)
                goto invalid;
            bytecode = JS_VALUE_GET_PTR(module->func_obj);
            if (bytecode->realm != ctx || bytecode->native_async_body)
                goto invalid;
            variables = bytecode->closure_var_count;
        }
    }
    for (i = 0; i < module->req_module_entries_count; i++) {
        JSPiLinkMember *target;
        if (js_pi_link_poll(ctx))
            return -1;
        target = js_pi_link_member(ctx, attempt, module->req_module_entries[i].module);
        if (!target)
            return -1;
        if (!target->module)
            goto invalid;
        if (!fresh && target->module->status == JS_MODULE_STATUS_UNLINKED)
            goto invalid;
    }
    for (i = 0; i < module->export_entries_count; i++) {
        JSExportEntry *entry = &module->export_entries[i];
        if (js_pi_link_poll(ctx))
            return -1;
        if (entry->export_type == JS_EXPORT_TYPE_LOCAL) {
            if (!fresh && !entry->u.local.var_ref)
                goto invalid;
            if (fresh && (entry->u.local.var_ref ||
                (!module->init_func && (entry->u.local.var_idx < 0 ||
                                        entry->u.local.var_idx >= variables))))
                goto invalid;
        } else if (entry->export_type == JS_EXPORT_TYPE_INDIRECT) {
            if (entry->u.req_module_idx < 0 ||
                entry->u.req_module_idx >= module->req_module_entries_count)
                goto invalid;
        } else {
            goto invalid;
        }
    }
    for (i = 0; i < module->import_entries_count; i++) {
        const JSImportEntry *entry = &module->import_entries[i];
        if (js_pi_link_poll(ctx))
            return -1;
        if (entry->req_module_idx < 0 ||
            entry->req_module_idx >= module->req_module_entries_count ||
            (fresh && !module->init_func &&
             (entry->var_idx < 0 || entry->var_idx >= variables)))
            goto invalid;
    }
    for (i = 0; i < module->star_export_entries_count; i++) {
        int index = module->star_export_entries[i].req_module_idx;
        if (js_pi_link_poll(ctx))
            return -1;
        if (index < 0 || index >= module->req_module_entries_count)
            goto invalid;
    }
    return 0;
invalid:
    JS_ThrowTypeError(ctx, "module graph is not a clean resolved link candidate");
    return -1;
}

static int js_pi_link_record(JSContext *ctx, JSPiLinkAttempt *attempt,
                              JSPiLinkMember *member, size_t *index)
{
    JSPiLinkRecord *record;
    if (js_pi_link_poll(ctx))
        return -1;
    if (attempt->used >= attempt->count) {
        JS_ThrowInternalError(ctx, "module link ledger capacity exceeded");
        return -1;
    }
    *index = attempt->used;
    record = &attempt->records[attempt->used];
    record->module = member->module;
    record->original_function = JS_UNDEFINED;
    record->original_stack = member->module->stack_prev;
    record->original_index = member->module->dfs_index;
    record->original_ancestor = member->module->dfs_ancestor_index;
    record->fresh = member->module->status == JS_MODULE_STATUS_UNLINKED;
    record->touched = false;
    /* Publish initialized cleanup bounds before any further fallible work. */
    member->record_plus_one = ++attempt->used;
    if (record->fresh)
        record->original_function = JS_DupValue(ctx, member->module->func_obj);
    return js_pi_link_validate_node(ctx, attempt, member->module);
}

static void js_pi_link_attempt_free(JSContext *ctx, JSPiLinkAttempt *attempt,
                                    bool failed)
{
    size_t i;
    for (i = 0; i < attempt->used; i++) {
        JSPiLinkRecord *record = &attempt->records[i];
        JSModuleDef *module = record->module;
        if (failed && record->touched && record->fresh &&
            module->status == JS_MODULE_STATUS_UNLINKED) {
            int j;
            JSValue function = module->func_obj, ns = module->module_ns;
            module->module_ns = JS_UNDEFINED;
            module->func_obj = record->original_function;
            record->original_function = JS_UNDEFINED; /* ownership transferred */
            module->func_created = false;
            module->dfs_index = record->original_index;
            module->dfs_ancestor_index = record->original_ancestor;
            module->stack_prev = record->original_stack;
            for (j = 0; j < module->export_entries_count; j++) {
                JSExportEntry *entry = &module->export_entries[j];
                if (entry->export_type == JS_EXPORT_TYPE_LOCAL && entry->u.local.var_ref) {
                    JSVarRef *reference = entry->u.local.var_ref;
                    entry->u.local.var_ref = NULL;
                    free_var_ref(ctx->rt, reference);
                }
            }
            JS_FreeValue(ctx, ns);
            JS_FreeValue(ctx, function);
        }
        JS_FreeValue(ctx, record->original_function);
    }
    js_free(ctx, attempt);
}

int JS_PiLinkModuleGraph(JSContext *ctx, JSValueConst compiled_module)
{
    struct list_head *entry;
    JSPiLinkAttempt *attempt = NULL;
    JSPiLinkMember *root;
    size_t count = 0, capacity = 2, offset, member_bytes, record_bytes, frame_bytes;
    size_t i, depth = 0, root_index;
    JSValue first;
    if (JS_HasException(ctx))
        return -1; /* Entry reason remains in the actual VM slot untouched. */
    if (ctx->pi_link_preparing || !ctx->rt->native_error_stack_hook ||
        ctx->rt->native_error_stack_hook_active)
        return js_pi_link_admission_error(ctx, "capture-only native Error stack owner required");
    if (JS_VALUE_GET_TAG(compiled_module) != JS_TAG_MODULE)
        return js_pi_link_admission_error(ctx, "compiled module token required");
    ctx->pi_link_preparing = true;
    list_for_each(entry, &ctx->loaded_modules) {
        if (js_pi_link_poll(ctx))
            goto fail;
        if (count >= INT_MAX || count == SIZE_MAX)
            goto overflow;
        count++;
    }
    if (count > SIZE_MAX / 2)
        goto overflow;
    while (capacity < count * 2) {
        if (js_pi_link_poll(ctx))
            goto fail;
        if (capacity > SIZE_MAX / 2)
            goto overflow;
        capacity *= 2;
    }
    if (capacity > SIZE_MAX / sizeof(JSPiLinkMember) ||
        count > SIZE_MAX / sizeof(JSPiLinkRecord) ||
        count > SIZE_MAX / sizeof(JSPiLinkFrame))
        goto overflow;
    member_bytes = capacity * sizeof(JSPiLinkMember);
    record_bytes = count * sizeof(JSPiLinkRecord);
    frame_bytes = count * sizeof(JSPiLinkFrame);
    if (sizeof(*attempt) > SIZE_MAX - (_Alignof(JSPiLinkMember) - 1))
        goto overflow;
    offset = (sizeof(*attempt) + _Alignof(JSPiLinkMember) - 1) & ~(_Alignof(JSPiLinkMember) - 1);
    if (member_bytes > SIZE_MAX - offset)
        goto overflow;
    member_bytes += offset;
    if (member_bytes > SIZE_MAX - (_Alignof(JSPiLinkRecord) - 1))
        goto overflow;
    member_bytes = (member_bytes + _Alignof(JSPiLinkRecord) - 1) & ~(_Alignof(JSPiLinkRecord) - 1);
    if (record_bytes > SIZE_MAX - member_bytes)
        goto overflow;
    record_bytes += member_bytes;
    if (record_bytes > SIZE_MAX - (_Alignof(JSPiLinkFrame) - 1))
        goto overflow;
    record_bytes = (record_bytes + _Alignof(JSPiLinkFrame) - 1) & ~(_Alignof(JSPiLinkFrame) - 1);
    if (frame_bytes > SIZE_MAX - record_bytes)
        goto overflow;
    attempt = js_malloc(ctx, record_bytes + frame_bytes);
    if (!attempt)
        goto fail;
    attempt->capacity = capacity;
    attempt->count = count;
    attempt->used = 0;
    attempt->members = (JSPiLinkMember *)((uint8_t *)attempt + offset);
    attempt->records = (JSPiLinkRecord *)((uint8_t *)attempt + member_bytes);
    attempt->frames = (JSPiLinkFrame *)((uint8_t *)attempt + record_bytes);
    for (i = 0; i < capacity; i++) {
        if (js_pi_link_poll(ctx))
            goto fail;
        attempt->members[i].module = NULL;
        attempt->members[i].record_plus_one = 0;
    }
    list_for_each(entry, &ctx->loaded_modules) {
        JSModuleDef *module = list_entry(entry, JSModuleDef, link);
        JSPiLinkMember *member = js_pi_link_member(ctx, attempt, module);
        if (!member)
            goto fail;
        member->module = module;
    }
    root = js_pi_link_member(ctx, attempt, JS_VALUE_GET_PTR(compiled_module));
    if (!root)
        goto fail;
    if (!root->module) {
        JS_ThrowTypeError(ctx, "compiled module does not belong to this context");
        goto fail;
    }
    if (js_pi_link_record(ctx, attempt, root, &root_index))
        goto fail;
    attempt->frames[depth++] = (JSPiLinkFrame){ root_index, 0 };
    while (depth) {
        JSPiLinkFrame *frame = &attempt->frames[depth - 1];
        JSModuleDef *module = attempt->records[frame->record].module;
        JSPiLinkMember *child;
        size_t index;
        if (js_pi_link_poll(ctx))
            goto fail;
        if (frame->next_request == module->req_module_entries_count) {
            depth--;
            continue;
        }
        child = js_pi_link_member(ctx, attempt,
                                 module->req_module_entries[frame->next_request++].module);
        if (!child)
            goto fail;
        /* validate_node already proved target membership before dereference. */
        if (!child->module) {
            JS_ThrowTypeError(ctx, "module graph edge is no longer a context member");
            goto fail;
        }
        if (child->record_plus_one)
            continue;
        if (js_pi_link_record(ctx, attempt, child, &index))
            goto fail;
        if (depth >= count) {
            JS_ThrowInternalError(ctx, "module link traversal capacity exceeded");
            goto fail;
        }
        attempt->frames[depth++] = (JSPiLinkFrame){ index, 0 };
    }
    for (i = 0; i < attempt->used; i++) {
        JSPiLinkRecord *record = &attempt->records[i];
        if (js_pi_link_poll(ctx))
            goto fail;
        if (!record->fresh)
            continue;
        record->touched = true; /* local creation can fail before func_created */
        if (js_create_module_function_local(ctx, record->module) < 0 || JS_HasException(ctx))
            goto fail;
    }
    if (js_link_module(ctx, root->module) < 0 || JS_HasException(ctx))
        goto fail;
    js_pi_link_attempt_free(ctx, attempt, false);
    ctx->pi_link_preparing = false;
    return 0;
overflow:
    JS_ThrowOutOfMemory(ctx);
fail:
    first = JS_HasException(ctx) ? JS_GetException(ctx) : JS_NULL;
    if (attempt)
        js_pi_link_attempt_free(ctx, attempt, true);
    ctx->pi_link_preparing = false;
    JS_Throw(ctx, first);
    return -1;
}
