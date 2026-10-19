# Current descriptors during property copying

This source correction fixes the V17 inspector failure in the shared linked VM. The unchanged Node inspect.defaultOptions setter calls its captured Object.assign. Its first input getter deletes the later colors property. The old ordinary-source path kept an enumerable-only key snapshot and then read that deleted key without checking its current descriptor, overwriting the existing default with undefined.

JS_CopyDataProperties now snapshots all own string and symbol keys and checks each current own descriptor after the real exclusion operation, before reading its value. This also retains an initially nonenumerable key that an earlier getter or target setter makes enumerable. Keys created after the snapshot remain absent from the copy.

## Operation and ownership

The original Get operation, target Set for Object.assign, own data definition for spread/rest, and atom-table success/error cleanup remain unchanged. The original inspector owner, Source setter, observer and assertions are unchanged. The complete old/new C definition, exact comparison to the failing Main body, original consumer excerpt and selected ECMAScript 2025 references are retained in production-delta.json.

The authoritative operations are [Object.assign, section 20.1.2.1](https://tc39.es/ecma262/2025/multipage/fundamental-objects.html#sec-object.assign) and [CopyDataProperties, section 7.3.25](https://tc39.es/ecma262/2025/multipage/abstract-operations.html#sec-copydataproperties). Both read the current descriptor of each snapshotted key; rest performs its exclusions first.

## Controls

src/native_vm_copy_data_properties_test.zig declares 13 controls over actual Object.assign, object spread and object rest. They cover deleted properties without inherited fallback; enumerability changes in both directions; replacement values versus later-added keys; numeric, string and symbol ordering; proxy descriptor/Get/Set order; string and symbol exclusions; changes made by target setters; and own data definitions that bypass prototype setters.

The ordinary abrupt controls retain the exact reason and already copied target fields. The flagged DATA control returns and copies the original value. A separate actual guest throw runs in fresh runtimes and checks a record retained before the operation to prove no later getter, catch or finally ran. Raw VM results and retained roots retire on both normal and assertion-failure paths.

The six-line build addition uses the existing shared QuickJS library and creates only the install target build-native-vm-copy-data-properties. No build, native execution, Node run or generator was performed for this unit. Source review and authored controls are not runtime qualification.
