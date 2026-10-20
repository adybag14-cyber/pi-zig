# Consuming operand retirement

This source-only unit closes three distinct bytecode retirement boundaries: the four consuming Boolean branches, OP_to_propkey, and OP_drop. It uses the already closed property86e4 completed-result/operand helper. Actual pending completion is reduced across finalizable retirement before further dispatch; returned flagged Error data is not promoted to an event.

Boolean conversion retains the original operand during the existing non-guest JS_ToBool calculation, then pops and clears its stack owner before actual retirement. Immediate fast cases are unchanged. OP_to_propkey publishes the actual conversion result before operand retirement, including failed conversion. OP_drop pops its operand before the same clear/reduce/release operation.

The production packets apply in order: branch-production-delta.json (four edits), property-key-production-delta.json (one), drop-production-delta.json (one), after property commit86e4be1ae0455ed0aec42856cca6129e8ee7a6fd. Their exact inverse recreates that C byte-for-byte. They are independent of Main private-setter and lazy ordinary-prototype additions. No header, call-entry, local-store, OP_to_propkey2, or JS_GetPropertyValue internal conversion change is included.

Actual compiler source corrects the original Helpers key attribution: a computed object literal evaluates its value, defines via a duplicated key, then drops its original key. Helpers condition selects the Boolean branch; Helpers literal selects OP_drop. Separate assignment controls select OP_to_propkey before the right-hand value expression. No claim credits the conversion opcode with fixing the literal route.

The root has 25 declared controls with real raw VM bytecode and sole-holder native finalizers. Short and long forward/backward branches use actual observable bodies; assignment and literal controls assert different value-evaluation counts. Ordinary catch, first fatal reason, flagged data, private termination, conversion receiver/string hint, and no-allocation Boolean success are distinct observations. Plain progress is retained before entry and read directly after failure; native probe storage outlives runtime teardown.

The six-line build packet installs build-native-vm-consuming-operands using actual root/filter and one shared QuickJS link. There is no run edge. All assigned production/control/build peers are source-closed. No native build, test, Node execution, formatter or generator was performed.
