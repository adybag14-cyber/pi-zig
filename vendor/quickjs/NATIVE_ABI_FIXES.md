# Native C callback correction

The pinned QuickJS source is preserved except for a narrow allocator adapter in
`quickjs.c`. The original file SHA256 before this change is
`9FD0E0E68856D165E2872140AC38889845B53EB1BC55150F8598A53EB86948F5`.

`js_string_normalize` passed `js_realloc_rt(JSRuntime *, void *, size_t)` through
a cast to `DynBufReallocFunc(void *, void *, size_t)`. Zig 0.16.0 ReleaseSafe C
indirect-call type checks correctly trap this incompatible function-pointer call
on Windows and Linux. `js_unicode_normalize_realloc` has the exact declared
callback type and explicitly converts the opaque pointer to `JSRuntime *` before
calling the allocator. Allocation behavior and normalization results are unchanged.

All occurrences of `js_realloc_rt`, `js_realloc`, and `DynBufReallocFunc` in this
file were audited. This was the sole cast of `js_realloc_rt` to a callback type.
The two normalization calls in `String.localeCompare` had the same incompatible
cast from `js_realloc(JSContext *, void *, size_t)`. They now use the existing
correctly typed `js_dbuf_realloc` adapter. The existing regexp allocator wrappers
already have correctly typed opaque-pointer callbacks.
No sanitizer checks or safety options are disabled.
