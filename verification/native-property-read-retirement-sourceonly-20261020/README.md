# Property result and receiver retirement

This source-only unit corrects the actual `OP_get_field` and `OP_get_array_el` completion boundary observed by the original inspector receiver controls. It publishes the selected lookup result before releasing the consumed receiver, normalizes the consumed computed-key stack slot, and reduces only actual pending events across receiver and result retirement before further bytecode dispatch. A flagged Error returned as a value remains data.

Failed lookup also retires its actual receiver before dispatch. The unchanged pending reducer retains the first actual fatal reason while allowing a later actual fatal reason to replace an ordinary one. The result slot is cleared before failed-result retirement.

The three exact production edits are in `production-delta.json`. Apply them after the termination unit ce0981538962d96c8d79f0e526ed024e538c305b; they are independent of Main's private-property setter. The header is unchanged. `selected-source.json` retains the relevant original opcode, getter, fast-array, pending-reducer and exception-dispatch source.

The independent root contains 20 declared controls. They use real raw QuickJS bytecode calls, sole receiver and result owners, actual native class finalizers, inherited getters, fast Array/typed-array/arguments paths, original ordinary catch behavior, actual private termination and precompiled allocation-free success. Failure paths retain progress before entry and inspect only its known primitive own data fields. Probe storage outlives all runtime retirement.

`build-intake.json` adds six lines for the actual root/filter and one shared QuickJS link, exposing only `build-native-vm-property-retirement` installation. There is no execution edge.

Scope is limited to these two property-read opcodes. Consuming Boolean branches, property-key conversion, call entry, local stores and internal key conversion in `JS_GetPropertyValue` are not changed by this unit. Original inspector and Helpers observers/assertions remain in their independent units. No native build, test execution, Node run, formatter or generator was performed.
