# Native well-known symbol accessors

QuickJS-NG remains pinned to v0.17.0, commit6d46d07d04041b40f4f49eaa7fdebe44c314c699.

The SDK's native spread and addition operations need the same immutable
Symbol.iterator and Symbol.toPrimitive identities as the VM's bytecodes.
Reading guest globalThis.Symbol is observable and can return unrelated values.
Both accessors return JS_AtomToValue(ctx, JS_ATOM_Symbol_...) using existing
well-known atoms. The caller receives an owned value and releases it normally.
No VM algorithms, allocation policies or guest globals change.

The iterator accessor is the same five-line source addition as the separately
frozen6c84e40c6cd5bbc9fdc83c2b6c126fb20498467a prerequisite. Core also adds the
corresponding toPrimitive accessor for Source indexOf-result + 1 semantics.
This Core composition is source only and uncompiled. The standalone iterator
prerequisite's qualification must not be attributed to this further addition.
