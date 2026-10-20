# Backing-store process OOM terminal owner

This source-only additive delta implements the Node OOM callback reached after the original ArrayBuffer::NewBackingStore allocation policy fails. It records the actual process OOM site and message, permanently sets the native OOM latch, invokes the optional genuine report owner with OOMError, flushes stderr, and terminates through the existing native abort owner. The heap CALL_AND_RETRY_LAST path is byte-for-byte unchanged.

The exact original sources retain the conditional young collection, two old-space retry collections and final all-available collection policy. This terminal callback does not claim that a single QuickJS collection implements that policy. Consumer integration, nondefault report installation, original V8 pre-callback GC diagnostics and runtime qualification remain open.

The production packet is relative to the pinned current Main, not the older Root worktree base. Its four additions invert to the exact original Main bytes. Full source documents and all eight byte ranges were independently hashed; end_line in the retained source packet denotes the exclusive next line.
