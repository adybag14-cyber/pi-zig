/* Private opt-in namespace ordering. Included after ExportedNameEntry. */
typedef struct JSPiLinkSort {
    size_t initialized;
    JSValue *keys;
    size_t *order;
    size_t *auxiliary;
} JSPiLinkSort;

static void js_pi_link_sort_free(JSContext *ctx, JSPiLinkSort *sort)
{
    size_t i;
    if (!sort)
        return;
    for (i = 0; i < sort->initialized; i++)
        JS_FreeValue(ctx, sort->keys[i]);
    js_free(ctx, sort);
}

static int js_pi_link_key_compare(JSContext *ctx, JSValueConst a,
                                  JSValueConst b, int *comparison)
{
    JSString *left = JS_VALUE_GET_STRING(a), *right = JS_VALUE_GET_STRING(b);
    size_t i, count = min_int(left->len, right->len);
    for (i = 0; i < count; i++) {
        uint32_t x, y;
        if (js_pi_link_poll(ctx))
            return -1;
        x = left->is_wide_char ? left->u.str16[i] : left->u.str8[i];
        y = right->is_wide_char ? right->u.str16[i] : right->u.str8[i];
        if (x != y) {
            *comparison = x < y ? -1 : 1;
            return 0;
        }
    }
    *comparison = (left->len > right->len) - (left->len < right->len);
    return 0;
}

static int js_pi_link_sort_exports(JSContext *ctx, ExportedNameEntry *entries,
                                    size_t count, JSPiLinkSort **output,
                                    size_t **ordered)
{
    JSPiLinkSort *sort;
    size_t offset, key_bytes, index_bytes, total, i, width;
    size_t *source, *target;
    *output = NULL;
    *ordered = NULL;
    if (!count)
        return 0;
    if (count > SIZE_MAX / sizeof(JSValue) ||
        count > SIZE_MAX / sizeof(size_t))
        goto overflow;
    key_bytes = count * sizeof(JSValue);
    index_bytes = count * sizeof(size_t);
    if (sizeof(*sort) > SIZE_MAX - (_Alignof(JSValue) - 1))
        goto overflow;
    offset = (sizeof(*sort) + _Alignof(JSValue) - 1) & ~(_Alignof(JSValue) - 1);
    if (offset > SIZE_MAX - key_bytes)
        goto overflow;
    total = offset + key_bytes;
    if (total > SIZE_MAX - (_Alignof(size_t) - 1))
        goto overflow;
    total = (total + _Alignof(size_t) - 1) & ~(_Alignof(size_t) - 1);
    if (index_bytes > (SIZE_MAX - total) / 2)
        goto overflow;
    sort = js_malloc(ctx, total + index_bytes * 2);
    if (!sort)
        return -1;
    sort->initialized = 0;
    sort->keys = (JSValue *)((uint8_t *)sort + offset);
    sort->order = (size_t *)((uint8_t *)sort + total);
    sort->auxiliary = sort->order + count;
    *output = sort;
    for (i = 0; i < count; i++) {
        JSValue key;
        if (js_pi_link_poll(ctx))
            return -1;
        key = JS_AtomToString(ctx, entries[i].export_name);
        if (JS_IsException(key) || JS_HasException(ctx)) {
            js_pi_link_failure_free(ctx, key);
            return -1;
        }
        sort->keys[sort->initialized++] = key;
        sort->order[i] = i;
    }
    source = sort->order;
    target = sort->auxiliary;
    for (width = 1; width < count;) {
        size_t base = 0;
        while (base < count) {
            size_t middle = base + (width < count - base ? width : count - base);
            size_t end = middle + (width < count - middle ? width : count - middle);
            size_t left = base, right = middle, index = base;
            while (left < middle && right < end) {
                int comparison;
                if (js_pi_link_poll(ctx) ||
                    js_pi_link_key_compare(ctx, sort->keys[source[left]],
                                           sort->keys[source[right]], &comparison))
                    return -1;
                target[index++] = comparison <= 0 ? source[left++] : source[right++];
            }
            while (left < middle) {
                if (js_pi_link_poll(ctx))
                    return -1;
                target[index++] = source[left++];
            }
            while (right < end) {
                if (js_pi_link_poll(ctx))
                    return -1;
                target[index++] = source[right++];
            }
            base = end;
        }
        { size_t *swap = source; source = target; target = swap; }
        if (width >= count - width)
            break;
        width *= 2;
    }
    *ordered = source;
    return 0;
overflow:
    JS_ThrowOutOfMemory(ctx);
    return -1;
}
