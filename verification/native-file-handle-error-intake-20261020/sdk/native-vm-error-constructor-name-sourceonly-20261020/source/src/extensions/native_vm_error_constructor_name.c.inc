/* Selected native Error constructor provenance and GetConstructorName slice.
 * Included once at the end of quickjs.c, after its real private types/helpers.
 *
 * Pinned V8 GetConstructorHelper first prefers actual native map constructor
 * provenance when new.target is the base and the receiver is not a prototype.
 * Its fallback reads data properties only; the receiver's own constructor is
 * deliberately skipped. No guest getter, Proxy trap or mutable function.name
 * is consulted by this implementation.
 *
 * The original general map/new-target and SharedFunctionInfo::DebugName owners
 * do not yet exist in this VM. Different-new-target construction, unrecorded
 * Error creation, Proxy/exotic prototype storage and nonintrinsic function
 * constructor names return UNSUPPORTED. This result is not a negative stack
 * overflow classification, and this primitive does not install hook policy.
 */

static JSValue js_pi_intrinsic_error_constructor(JSContext *ctx, int kind)
{
    assert(kind >= 0 && kind <= JS_PLAIN_ERROR);
    return kind == JS_PLAIN_ERROR ? ctx->error_ctor
                                : ctx->pi_native_error_constructor[kind];
}

/* Called only before a just-created intrinsic constructor is published.
 * The real initial data property already contains its native builtin name.
 * Retain that value separately from the mutable public property.
 * A partial intrinsic-allocation failure leaves this name unsupported; this
 * helper performs no allocation, guest call or exception replacement.
 */
static void js_pi_cache_error_constructor(JSContext *ctx, int kind,
                                          JSValueConst constructor)
{
    JSObject *function;
    JSProperty *property;
    JSShapeProperty *shape_property;
    assert(kind >= 0 && kind <= JS_PLAIN_ERROR);
    assert(JS_IsUndefined(ctx->pi_error_constructor_name[kind]));
    if (kind != JS_PLAIN_ERROR) {
        assert(JS_IsUndefined(ctx->pi_native_error_constructor[kind]));
        ctx->pi_native_error_constructor[kind] = js_dup(constructor);
    }
    if (!JS_IsObject(constructor))
        return;
    function = JS_VALUE_GET_OBJ(constructor);
    shape_property = find_own_property(&property, function, JS_ATOM_name);
    if (!shape_property ||
        (shape_property->flags & JS_PROP_TMASK) != JS_PROP_NORMAL ||
        !JS_IsString(property->u.value))
        return;
    ctx->pi_error_constructor_name[kind] = js_dup(property->u.value);
}

/* Source's derived maps still retain the actual base constructor. Keep that
 * real native edge for known intrinsic construction, even when the selected
 * name algorithm must report the different-new-target slice unsupported.
 */
static void js_pi_record_error_constructor(JSContext *ctx, JSValueConst error,
                                           int kind, JSValueConst constructor,
                                           JSValueConst new_target)
{
    JSObject *object;
    JSValue base, name;
    if (!JS_IsError(error))
        return;
    assert(kind >= 0 && kind <= JS_PLAIN_ERROR);
    object = JS_VALUE_GET_OBJ(error);
    assert(JS_IsUndefined(object->u.native_error.constructor));
    assert(JS_IsUndefined(object->u.native_error.constructor_name));
    base = js_pi_intrinsic_error_constructor(ctx, kind);
    name = ctx->pi_error_constructor_name[kind];
    if (!JS_IsObject(base) || !JS_IsObject(constructor) ||
        JS_VALUE_GET_OBJ(base) != JS_VALUE_GET_OBJ(constructor) ||
        !JS_IsString(name))
        return;
    object->u.native_error.constructor = js_dup(base);
    object->u.native_error.constructor_name = js_dup(name);
    object->u.native_error.constructor_provenance =
        JS_IsObject(new_target) &&
        JS_VALUE_GET_OBJ(new_target) == JS_VALUE_GET_OBJ(base)
            ? 1 : 2;
}

static void js_pi_record_intrinsic_error(JSContext *ctx, JSValueConst error,
                                          int kind)
{
    JSValue constructor = js_pi_intrinsic_error_constructor(ctx, kind);
    js_pi_record_error_constructor(ctx, error, kind, constructor, constructor);
}

/* 1 = supported physical own-data lookup (possibly undefined);
 * 0 = native storage whose precise original lookup owner remains unported.
 * Neither path executes guest code, allocates or touches current_exception.
 */
static int js_pi_constructor_own_data(JSObject *object, JSAtom key,
                                      JSValue *value)
{
    JSProperty *property;
    JSShapeProperty *shape_property;
    *value = JS_UNDEFINED;
    if (object->is_exotic)
        return 0;
    shape_property = find_own_property(&property, object, key);
    if (!shape_property)
        return 1;
    switch (shape_property->flags & JS_PROP_TMASK) {
    case JS_PROP_NORMAL:
        *value = property->u.value;
        return 1;
    case JS_PROP_GETSET:
        /* Original GetDataProperty does not call an accessor. */
        return 1;
    default:
        /* Variable-reference and autoinit/native storage are not materialized
         * or silently treated as missing by this bounded primitive. */
        return 0;
    }
}

/* 1 = an exact nonempty, non-Object native function DebugName was found;
 * 0 = value is not an eligible JSFunction or is the intrinsic Object;
 * -1 = an eligible function's native DebugName owner is still missing.
 * Bound functions and proxies are not V8 JSFunction and are skipped.
 */
static int js_pi_constructor_debug_name(JSContext *ctx, JSValueConst value,
                                        JSValue *name)
{
    JSObject *function;
    JSContext *realm;
    int kind;
    *name = JS_UNDEFINED;
    if (!JS_IsObject(value))
        return 0;
    function = JS_VALUE_GET_OBJ(value);
    if (function->class_id == JS_CLASS_BOUND_FUNCTION ||
        function->class_id == JS_CLASS_PROXY)
        return 0;
    if (function->class_id == JS_CLASS_C_FUNCTION) {
        realm = function->u.cfunc.realm;
        if (realm) {
            for (kind = 0; kind <= JS_PLAIN_ERROR; kind++) {
                JSValue candidate = js_pi_intrinsic_error_constructor(realm, kind);
                if (JS_IsObject(candidate) &&
                    JS_VALUE_GET_OBJ(candidate) == function) {
                    JSValue stored = realm->pi_error_constructor_name[kind];
                    if (!JS_IsString(stored))
                        return -1;
                    *name = stored;
                    return 1;
                }
            }
        }
        /* This is the VM's actual immutable intrinsic native function body.
         * Its original DebugName is Object, regardless of public name edits. */
        if (function->u.cfunc.c_function.generic == js_object_constructor)
            return 0;
    }
    return JS_IsFunction(ctx, value) ? -1 : 0;
}

JSPiNativeErrorConstructorNameStatus JS_PiGetNativeErrorConstructorName(
    JSContext *ctx, JSValueConst error, JSValue *owned_name)
{
    JSObject *receiver, *current;
    JSValue value, name;
    int found;
    assert(ctx != NULL && owned_name != NULL);
    *owned_name = JS_UNDEFINED;
    if (!JS_IsError(error))
        return JS_PI_ERROR_CONSTRUCTOR_NAME_NOT_NATIVE_ERROR;
    receiver = JS_VALUE_GET_OBJ(error);
    if (receiver->u.native_error.constructor_provenance != 1)
        return JS_PI_ERROR_CONSTRUCTOR_NAME_UNSUPPORTED;

    if (!receiver->is_prototype) {
        assert(JS_IsString(receiver->u.native_error.constructor_name));
        *owned_name = js_dup(receiver->u.native_error.constructor_name);
        return JS_PI_ERROR_CONSTRUCTOR_NAME_FOUND;
    }

    /* The original prototype-map restriction suppresses the retained base
     * constructor fast path. Walk physical prototype links only. */
    for (current = receiver; current != NULL; current = current->shape->proto) {
        if (!js_pi_constructor_own_data(current, JS_ATOM_Symbol_toStringTag,
                                         &value))
            return JS_PI_ERROR_CONSTRUCTOR_NAME_UNSUPPORTED;
        if (JS_IsString(value)) {
            *owned_name = js_dup(value);
            return JS_PI_ERROR_CONSTRUCTOR_NAME_FOUND;
        }
        if (current == receiver)
            continue;
        if (!js_pi_constructor_own_data(current, JS_ATOM_constructor, &value))
            return JS_PI_ERROR_CONSTRUCTOR_NAME_UNSUPPORTED;
        found = js_pi_constructor_debug_name(ctx, value, &name);
        if (found < 0)
            return JS_PI_ERROR_CONSTRUCTOR_NAME_UNSUPPORTED;
        if (found > 0) {
            *owned_name = js_dup(name);
            return JS_PI_ERROR_CONSTRUCTOR_NAME_FOUND;
        }
    }
    /* Exact native JSError class_name fallback. The protected intrinsic Error
     * name is already a real string, so this remains allocation-free. */
    name = ctx->pi_error_constructor_name[JS_PLAIN_ERROR];
    if (!JS_IsString(name))
        return JS_PI_ERROR_CONSTRUCTOR_NAME_UNSUPPORTED;
    *owned_name = js_dup(name);
    return JS_PI_ERROR_CONSTRUCTOR_NAME_FOUND;
}
