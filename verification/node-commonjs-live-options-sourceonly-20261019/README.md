# Genuine live pending-deprecation options in the Module owner

This source unit binds the existing actual Module constructor to the completed internal/options declaration. It adds four causal controls to the existing 26-control Module root; the search-path root retains all 20 declarations.

No compilation, metadata query, Node process, native test execution, or runtime qualification is claimed by this source commit. The preceding diagnostic results remain unchanged.

## Why this change is needed

Node v24.14 internal/util.js does not freeze the pending-deprecation options when it creates a deprecated wrapper. Its isPendingDeprecation function invokes the retained getOptionValue('--pending-deprecation') at the actual warning occurrence, then invokes getOptionValue('--no-deprecation') only when the first result is truthy. The outer warning closure first checks its own warned binding.

The prior Module bootstrap accepted two Boolean values and retained them in its private record. That prevented the existing wrapper from observing a refreshed actual options dictionary and could not reproduce getter or retirement effects at the two original predicate reads.

The unchanged authority is `verification/node-module-constructor-sourceonly-20261016/authority/lib__internal__util.js.txt`, SHA A6A3FED1D2DE1050CB8B119A2D792246E37ABDEA4099D90D6994D894F506C429, 28980 bytes. The selected original functions are getDeprecationWarningEmitter, isPendingDeprecation, and pendingDeprecate. This is the retained Node v24.14 CJS/util basis; it does not relabel the Node v24.13 filesystem, URL, or physical libuv owners.

## Production composition

The actual Module core now obtains internal/options through native_node_options.acquire and retains its real getOptionValue declaration. The Module constructor owns that callable in the same private environment as the original process, paths, warning-code Set, and captured ReflectApply. Search-path construction consumes the same core without a separate frozen options input.

The warning path calls the retained declaration only after the original !warned test succeeds. The first call completes in its own Node expression scope; its callee and result retire before the conditional second call. The second result is converted to the negated truth value within its own expression. Both operations finish before warned is set.

The previous emission and deduplication algorithm remains: warned is stored before the live process.emitWarning selection, and the warning-code Set is updated after the call. The actual rest array, captured original ReflectApply, Module constructor identity, path cache, namespace record, and public accessor descriptor behavior are unchanged.

## Controls

The old 26 Module declarations and all 20 search-path declarations remain. Fixture initialization now supplies the existing Engine's actual native node_options input, with explicit selected build features strip_types=true and quic=false. This is test admission for the retained Node v24.14 basis.

The new test-only exposeOptions helper obtains the genuine options record and the original getOptionValue capture. It calls that original getCLIOptionsFromBinding declaration to expose its real cached dictionary for causal observation. It does not construct a replacement getOptionValue, native binding, or options cache.

The four appended declarations are:

1. The same Module wrapper observes a native pending-deprecation value after the real refreshOptions operation, then preserves its once-only warning state.
2. The first option read short-circuits the second, and poisoning the later public getOptionValue export does not replace the previously captured declaration.
3. A sole actual C-finalized truthy first-option result retires before the second option getter.
4. An actual allocation fatal from that retirement prevents the second option getter, warning callback, and guest catch. The original progress object is retained before invocation and inspected afterward through known own numeric data properties only; exact first reason and released native invocation are checked.

All four run through the actual Module parent accessor and real options owner. The original functional observers remain unchanged. Their separate original-Node execution contract and the full process warning implementation are not replaced by these internal causal controls.

## Finite source review

SDK closed the production delta on core34300937, constructor92B12A8F, and search88FC8BD7 against actual utilA6A3FED1. The review covers real options import identity, original short-circuit order, expression retirement, warned publication, and preservation of the same Module owner.

VM closed Fixture/exposeOptions and declarations 27–30 at root 9D3172E5 against the actual options2277/core3430 owners and retained util declarations. The review confirms real serializer refresh, retention of the original callable, both short-circuit gates, sole first-option retirement before the second getter, and exact fatal identity with pre-retained own-data progress. Existing constructor, rest, public accessor, and prior 26-control reviews remain restricted to their previously accepted bytes.

## Intake and remaining work

There is no build.zig change. Root retains the existing build-native-node-module-creation and build-native-node-module-search-paths targets and obtains fresh actual metadata for the expanded Module root in its next authorized batch. Source intake preserves the distinct original diagnostic negatives.

The genuine private CJS helpers/conditions, filesystem/package/resolve graph, ESM and Jiti composition, and the actual process warning implementation are subsequent work. This private owner correction does not publish a completed public loader namespace.
