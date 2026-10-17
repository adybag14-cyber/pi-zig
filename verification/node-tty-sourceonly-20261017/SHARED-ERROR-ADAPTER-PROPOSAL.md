# Shared actual SystemError parent — proposed adapter, source only

Body confirmed no general registered Node error constructor registry exists and
cleared a separate genuine TTY error registration. Body's existing95192884
SystemError delta adds fromContext(engine, context) and changes the private cache
key to static storage; both interfaces/ownership fixes must be preserved.

New native_node_error_class.zig implements construct-only native classes with
genuine intrinsic FunctionProto, charged/traced roots, actual dynamic declared
superclass/new.target semantics, direct pending boundaries and the existing fresh
allocation/ordinary exception transfer helper. It does not edit shared native_class
or Engine, introduce C annotations, or invent executable JavaScript source.

New native_node_system_errors.zig retains ONE private, unregistered Engine cache
of the SystemError parent, kIsNodeError marker and two registered NodeError
classes: ERR_SYSTEM_ERROR and ERR_TTY_INIT_FAILED. The context getter/setter,
message field-read order, ordinary code assignment, path/dest reloads and
Buffer.from callee-before-toString match the captured actual Node source and the
already reviewed writer corrections. Constant cache key adds no GPA key leak.
This preserves the old writer's stated stack/custom-inspection limitations;
those are not silently expanded into a general internal/errors qualification.

Prepared adapter patch changes ONLY the existing fs helper's private constructor
to Scope-own the actual shared registry constructor. It preserves the actual
install/retryFailure APIs, Body's fromContext and static-key delta. It is a
proposal for Root+Body source review; no fs helper or Main file is edited here.
Whole historical file overwrite and unrelated Body edits are excluded.

native_node_system_error_identity_test.zig is prepared/unrun, not build-selected.
It causally checks parent/marker identity across real native classes, registered
TTY message/context/descriptors, context setter, ordinary class rejection, late
Function poison, exact ctx getter throw identity and suppression/slot cleanup.
Existing writer retry SystemError tests must also run after an eventual grant.

The other TTY error classes/ErrnoException registration and complete actual
native endpoint/frontend owner composition are still being authored. No fake
errors, namespace or always-false capability are selected in their place.
