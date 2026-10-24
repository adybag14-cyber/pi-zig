# Shared SettingsManager defaults and complete affected accessors

This source-only successor reconciles the existing genuine SettingsManager with the retained 4954d76 settings-manager.ts and the shared SETTINGS_DEFAULTS owner already accepted with project-trust resolution. It selects forty-one original default-bearing, compound, and compaction-token getter methods, and adds the missing original session-share getter/setter pair to the existing owner. It preserves the actual SettingsManager constructor, native backing data, storage/save queue, and all other existing accessor implementations.

The old per-instance 6fb2e78 JSON fallback is removed from the selected owner. Its exact source and original asset remain archived. Every simple getter consults the shared object only when its original nullish or truthy expression selects the fallback. Validation getters retain their actual lexical values while evaluating the fallback. Global-only cache/trust reads, strict accepted alternatives, optional settings versus required default parents, repeated compound parent Gets, live instance method calls, Number/Math/Array/String/Error evaluation, and actual argument/local retirement follow the original runtime bodies.

The original CACHE_WARMING_MODES is a mutable array retained by one private module-import owner. The original two compaction token defaults are captured once, in their separate original parent/Get order, while all ordinary SETTINGS_DEFAULTS fallbacks remain live. The capsule is internal implementation state, not a new or partial public module namespace. A future complete settings-manager module publisher can obtain the same retained modes array; this packet does not invent a publisher.

## Selected source and tests

The packet has six selected target paths: a complete new accessor owner; the finite existing Settings owner successor; one actual-VM test root; two test-only JavaScript fixtures; and an insertion-only build projection. Twelve sequential existing-owner hunks reverse exactly to the 42,856-byte donor. No public constructor or unrelated namespace is substituted.

The test-only Source class is a method-definition container and is never instantiated. Its forty-one original getter bodies are byte-exact after explicit signature/type erasures. Those original methods run on genuine actual native SettingsManager instances, with test-only field mappings to their retained native backing data. Both Source and native subjects execute in separate fresh actual Engines. This avoids a replacement manager or contaminated reference method calls.

Forty-three controls are declared: thirty-seven Source/native observations plus three actual current-fatal/retirement/cancellation boundaries and three cold/warm import-capture/pending controls. Behavioral coverage includes every simple path, shared mutation across actual managers, session-share storage, unrelated accessors avoiding defaults, live validation/compound evaluation, original error messages, optional/key/coercion order, actual VM lifetime traces, and repair after failed module capture. Counts are source declarations only. No formatter, parser, compiler, metadata, runtime, Node reference, or test execution was performed.

## Integration

The exact shared defaults prerequisite is the accepted Resolver packet's native_sdk_settings_defaults.zig, 5,116 bytes / 864B545AC2B47BB4DDD9DE32986C5549E2D259C2791EC3143CA914797CE77687. Root acceptance is root-project-trust-resolution-source-acceptance-20261024.json, 8,112 bytes / 3DC14275F069FCA548939412F28D2305EDDBCB76908A937FDB25E591DB277796. This packet neither alters nor re-emits that owner.

Apply the complete Settings successor only to its exact donor. Add the other new source files. Compose only the isolated build insertion into Root's current build; the projected full build starts at d3a9 and intentionally excludes separately pending additions. The install-only target is build-native-sdk-settings-shared-defaults, filter native settings shared defaults. It uses default test.exe/test.pdb artifact names. No C ABI change is introduced.

## Explicit remaining work

This is the full affected defaults/accessor table, not complete SettingsManager or application qualification. Unrelated pre-existing non-default accessors/setters, storage behavior, and the complete public module publisher retain their prior status. The remaining original SETTINGS_DEFAULTS imports in settings-schema.ts, extensions/codemode/tool.ts, extensions/codemode/index.ts, and modes/interactive/components/settings-selector.ts still need their own genuine integration. The resolver and these Settings accessors share the accepted live object; that fact does not complete all import sites or the production createRuntime assembly.

Main was not changed. Sealed predecessors remain byte-exact. All actual native qualification and intake execution belong to Root.
