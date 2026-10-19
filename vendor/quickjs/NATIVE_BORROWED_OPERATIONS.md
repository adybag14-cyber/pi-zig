# Borrowed native VM operations

This unit adds four narrow entry points to the current linked QuickJS C source.
The existing VM algorithms are unchanged. The parent C source is
`F51688A26C8D1B976F55435849E6B8EFE996D163C928E39A2B42C16A1698928F`;
the parent header is
`E6390B37426D242064C111CEBD3A192934784904605351C2136C456CF64E857A`.

| Entry point | Existing operation | Ownership |
| --- | --- | --- |
| `JS_PiGetObjectPrototypeFromConstructor` | The property and function-realm selection in `js_create_from_ctor`, fixed to `JS_CLASS_OBJECT` | Borrows the constructor; returns one owned prototype. Actual native class allocation remains a separate caller operation. |
| `JS_PiForInStart` | `js_for_in_start` / `build_for_in_iterator` | Borrows input; the builder consumes one VM duplicate and the returned private iterator owns that root. |
| `JS_PiForInNext` | `js_for_in_next` | Borrows the iterator; returns an owned key or undefined. The non-null done output is meaningful only on normal return. |
| `JS_PiCallArray` | `js_function_apply` with magic 0 | Borrows callable, receiver and array-like input; the existing argument-list builder, actual call and list cleanup produce the owned result. |

Each entry checks the actual pending exception before starting work. Each can
perform guest operations and must run inside the caller's established guest
boundary. No broad native-allocation generation inference is added. The
prototype bridge does not substitute a custom native class prototype or the
caller realm for the actual Object fallback. CallArray performs the ordinary
array-like apply operation; a caller modeling spread must first perform the
actual separate spread expression.

The install-only target `build-native-vm-borrowed-bridges` filters
`VM borrowed bridges` in `src/native_vm_borrowed_bridges_test.zig`. Its 17
authored declarations cover live prototype reads, foreign bound/proxy function
realms, revoked/throwing constructors, primitive and inherited for-in keys,
snapshot deletion, proxy operations, later inherited has failures, borrowed
iterator ownership, callable-before-length ordering, array-like coercion and
indices, the real argument cap, argument-list retirement, private DATA,
current fatal events, cleanup fatal events and preexisting pending guards.
The Source branches execute actual language/standard-library operations in
the same linked C runtime. The foreign-realm controls create a real separate
context on that runtime and retain it through all owned values.

These are source-authored controls and finite source reviews. This document
does not claim compilation, execution, metadata acceptance, full HTTP
composition or whole-application qualification. Root owns the separately
granted changed-vendor build and runtime gates.
