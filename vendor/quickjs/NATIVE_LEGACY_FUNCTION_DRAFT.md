Source-only private additive ABI draft; not compiled, qualified or approved for Root intake.

JS_PiUnmappedArguments borrows argv and delegates to existing js_build_arguments, returning a fresh owned actual VM Arguments value on each call, with existing unmapped callee poison, iterator and prototype behavior. Failure preserves the pending VM exception. No existing function/opcode/arguments implementation changes.

JS_PiObserveCallFrame reads the current existing JSStackFrame, returns an owned current function or null for absent/strict/nonobject frames, and writes an opaque uintptr identity for equality comparison only during the active call. It does not skip C/bound/apply frames or claim Node caller conformance. The native function owner must capture and restore nested frames and release every owned value on success, exceptions and native allocation failures. The identity is never a guest pointer or retained after exit.

Actual b45 Original40 demonstrates legacy inherit arguments/caller fields, first-argument identity, fresh Arguments per property/descriptor read and outer restoration after nesting. Dedicated direct strict/sloppy/call/apply/bind/constructor/nativecallback/Arguments-shape/poison/freshness references are required before broad semantic claims. A permanent null field or cached Arguments object is not a substitute.

The two helpers are additive exports only. Existing guest VM semantics, JS_CallInternal, strict native_node_function and actual for-in opcode/helpers remain unchanged. Native legacy class drafts and this ABI must pass exact source/compiler freezes, real GC, failure/cancellation and complete native/VM allocator qualification before intake. Public activation, full grammar, full class/factory/application qualification stay false.
