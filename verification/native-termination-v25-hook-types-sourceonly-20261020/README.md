# V25 Promise-hook expectation types

The actual V25 compile reported that std.testing.expectEqual inferred c_int from the C enum constant while HookEvent.kind is the actual c.JSPromiseHookType (c_uint in that translation). The paired AFTER assertions have the same shape.

Exactly four expected operands now explicitly use c.JSPromiseHookType. No actual value, observation, lifetime, assertion, declaration name, production source or build target changes. The complete original root and original stderr are retained. The exact four-edit packet reverses byte-for-byte to Main164F8DCA.

A bounded scan of all owned src/*.zig found no other expectEqual call containing a JS_PROMISE_HOOK_* constant. Other hook comparisons and callback signatures require no change. The 30-control target remains build-native-vm-execution-termination with its existing VM termination filter.

Modules independently closed all four casts against the actual header/field/callback type and complete original root. This unit is source-only. No native build, metadata query, test, Node, formatter or generator was run. The original V25 negative remains a negative; this correction carries no runtime acceptance.

Main intake is the single source root plus this verification directory. The source-delta.json preimage is the exact Main164F8DCA fixture; do not replace shared C/H/build files.
