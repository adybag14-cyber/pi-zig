# Genuine typed-array inspector source unit

This successor supplies the actual typed-array path used by the retained Node inspector. The two filesystem path-helper failures in the V9 diagnostic reached ERR_INVALID_ARG_VALUE with a Uint8Array; the old inspector stopped at its explicit unsupported exotic-layout boundary. The error classes and path validators remain unchanged.

## Actual implementation

The inspector's genuine early bootstrap now retains the original typed-array length and tag getters, typed constructors, Array constructor and required primordial methods. Its existing thirteen captured classifier roots remain unchanged; the new private typed-array owner is stored in the existing lexical owner.

The selected implementation covers Node's getPrefix path, null-prototype reconstruction, intrinsic size versus repeated live length reads, numeric/BigInt formatter selection, a real Array(maxLength), indexed [[Set]], remaining-count text, non-index own properties and the ungrouped reduction through actual internal/util.join. Its length calculation selects ctx.colors on every iteration and calls the genuine removeColors algorithm with the retained original String.replace and exact color RegExp. Temporary second-prefix receiver/callee and output-item receivers finish before the subsequent comparison or addition.

Grouped arrays, sorted output, showHidden and other inspector exotic layouts retain explicit remaining limits. This source unit does not qualify the whole public util namespace, its primitive numeric internals or those remaining layouts.

## Declared controls and capture entry

- Existing target: build-native-node-inspect-entry.
- Root: src/native_node_inspect_entry_test.zig.
- Filter: native actual inspect.
- Installed Windows artifact: native-node-inspect-entry.exe.
- Twenty-four declarations: original thirteen plus six shared ordinary observers and five native typed-array ownership/DATA controls.
- Sixteen ordinary functions are listed in the retained Node v24.13.0 capture entrypoint. Its authority hash and original ten functions are preserved.
- Native controls use actual C sole holders, retained own-data progress and actual allocation-fatal producers. They check first-length operand retirement, exact first fatal preemption, ordinary private DATA identity, second-prefix receiver/callee retirement, and output-item retirement before coercion of its length.

No build target or install semantics changed. Node capture, compilation, metadata acceptance and actual runtime are separate Root-authorized steps; none was executed for this source unit.

## Provenance and finite review

The full original inspector authority is retained at ../node-inspect-entry-sourceonly-20261018/authority/inspect.js, SHA-256 380AA09FAE68E3279D0FB2469A24D75931A8098C84354347BF7130A38852B597 (92,944 bytes). Original Node v24.13.0 internal/util.js is EBD5E67C4B31E484B157239F7A7E38CBE29F175AFB53D2B95E19ACC2520D43B5 (28,384 bytes); exact selected join/color declarations and bounded native web evidence are retained under authority.

SDK's finite source peer closed helper F2C1CE24, test root 9A78028E and observer 011F1E69 for prefix/elements/ungrouped join and declarations 14–19, 22–24, including its two causal lifetime findings and color calculation correction. VM's independent finite source peer closed helper F2C1CE24, main inspector 5300C18A, root 9A78028E and observer 011F1E69 for capture/create/main ownership, the unchanged genuine Fixture and TypedProbe declarations 20–21. The actual thirteen-root inspector ABI is preserved, and the first-fatal controls observe only retained own-data progress after failure. Neither finite review is a runtime result.
