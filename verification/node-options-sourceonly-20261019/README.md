# Actual Node options source unit

This unit supplies the selected native startup configuration, native serializers, and original lazy JavaScript declarations required by the active CommonJS and ESM loader work. It is source-only. The twenty named controls have not been compiled, queried, or executed as part of this unit, and no original Node reference run is claimed.

## Original source and version

The selected authority is Node **v24.14.0**, commit `f657bb8ed86365ff3fdbe32e27563e778b41486a`, matching the existing CommonJS loader authority. The complete original `node_options.h`, `node_options.cc`, and `node_options-inl.h` are retained beside their v24.13.0 counterparts and the complete HTTP byte receipts under `../node-commonjs-loader-chain-sourceonly-20261019/authority/options/`. The original `internal/options.js` is retained in the adjacent authority directory.

This selection is intentional. The filesystem, URL, libuv, and FileHandle owners retain their distinct v24.13.0 authority. The meaningful selected default drift is `strip_types`: v24.13 initializes it to true, while v24.14 uses the real `HAVE_AMARO` build value. `FeatureDefaults.strip_types` therefore remains explicitly unknown until the embedding host supplies its admitted value. The two retained `node_options-inl.h` files are byte-identical. This unit does not infer a v24.14 feature profile from the v24.13 filesystem dependency.

The original credential/environment admission is retained separately in `safe-environment-source-evidence.json`. The exact original bootstrap error macros and environment flag body are in `env-and-bootstrap-error-source.json`. Their source byte hashes, full-document versus excerpt status, and all current implementation hashes are in `manifest.json`.

## Configuration and ownership

`Engine.Options.node_options` is an optional typed native input. Its original strings, list elements, and execution-option tokens are deep-copied into an independently charged Config owner before Engine initialization returns. The input is distinct from Pi command arguments and `process.argv`.

The actual process installer creates or acquires that Config, captures the native environment before guest process publication, and marks bootstrap complete only after both actual module registrations succeed. Capture stages a new arena, applies the selected environment settings, then `NODE_OPTIONS`, then the explicitly supplied execution-option tokens. A failure retires the staged arena and leaves the prior owner available for a real retry. Normal Config retirement follows runtime teardown and precedes release of the charged memory owner.

Every native environment lookup uses the original admission predicate. Its Windows branch performs no credential mutation. Its Linux branch uses the actual credential IDs, permitted capability mask, and once-cached `AT_SECURE` value before reading the environment map. The C leaf joins the existing single `pi-node-network` static library.

The selected parser preserves the original ASCII-space/double-quote/backslash tokenizer, underscore normalization, selected aliases and negations, Boolean equals behavior, ordered list appends, transform implications, and the distinction between an empty following argument and an empty equals argument. Unsupported parser inputs fail explicitly. This is not a claim of complete Node command-line admission.

## Actual private JavaScript imports

`native_node_options_binding.create` returns the two actual private native callables for the selected original serializers. `native_node_options.acquire` completes one cached private record under `pi-native:private/node-options-values`, retaining the original lazy cells and four original callable exports: `getOptionValue`, `getEmbedderOptions`, `refreshOptions`, and `getAllowUnauthorized`.

The lazy declarations preserve nullish initialization, selected dictionary ownership across computed-key reentry, independent embedder caching, and the live TLS warning sequence. The warning flag changes before the live warning getter/call. The implementation consumes the actual process owner; it does not provide a replacement warning implementation or publish a partial public `internalBinding` namespace.

The selected native serializer creates fresh null-prototype own-data records. The bootstrap error uses the intrinsic Error and actual nonthrowing native Set for `code`: ordinary false assignment is accepted, and an actual pending exception is checked. The original C THROW helper is void, so `GetCLIOptionsValues` sets its native serialized flag after raising the bootstrap reason. `GetEmbedderOptions` has no such flag write. Control 6 observes these two cases independently.

## Source controls and finite review

The selected Source fixture contains five exact function declarations from the original `internal/options.js`, with only a test factory supplying their actual native binding imports. `selected-source-declarations.json` records every original byte range. Source and native branches use fresh Engines, the same genuine process/native configuration route, and the real private owner. This selected linked-engine comparison is not an original Node/V8 execution.

Twenty named declarations cover native copying and rollback, tokenizer and parser behavior, selected serializers and bootstrap state, ordinary function shape, lazy cells, computed-key reentry, live warning order, actual C-holder retirement, ordinary private DATA, successful flagged DATA, recorded fatal events, pending entry, and completed owner identity. Fatal controls retain their known own-data progress records before invocation and inspect them without new guest evaluation. Probe storage outlives Engine teardown; fatal injection is disabled before retained reasons are released.

The finite source reviews are divided as follows:

| Reviewer | Closed source slice | Control declarations |
| --- | --- | --- |
| Root | Tokenizer/parser/selected defaults and exact original registration comparison | 1, 3, 5 |
| VM Foundation | Config/native lifecycle, credential admission, actual Fixture/Probe, and additive build wiring | 2, 4, 17–20 |
| SDK Owners | Native selected serializers, lazy/TLS declarations, flags-0 code Set, and final serialized continuation delta | 6–16 |

SDK's final bootstrap review is pinned to binding `80761DEB` and root `D46AE836`. Its exact `options-native-continuation-proof.json` is copied unchanged here at `EE76DEEBD36A85B080BDC571FB254F5E1A0195038DF7A676CCE75FB1769FCA00`. The packet proves that the successful original intrinsic native tail does not clear the ordinary reason. It does not claim that the omitted allocation tail was executed by this adapter.

## Build and integration

The install-only target is `build-native-node-options`; its root is `src/native_node_options_test.zig`, its filter is `native actual Node options`, and its installed artifact is `native-node-options.exe` on Windows. The source declares twenty names. Actual compiler metadata and runtime counts remain unknown.

`build-intake.patch` contains exactly sixteen added build lines and one C-library membership line. It preserves the canonical cached test executable name, the existing transitive QuickJS/network library, and platform gates. It adds no run step.

The Engine and build snapshots in this worktree precede newer unrelated Main changes. Intake must merge the narrow additive Engine/config and build/library deltas into current Main, preserving those newer owners. Do not replace current Main files wholesale. `native-lifecycle-draft.json` records the original inspected contexts; its historical length fields count JavaScript string characters, while `manifest.json` records verified raw file byte counts.

## Required continuation and limits

This source commit is a bounded prerequisite, not full options or Module qualification. The immediate next correction must perform the original native output allocation/serialization tail after the bootstrap throw while preserving its ordinary reason and recording actual newly produced fatal failures. The current correction models the externally visible serialized flag but skips that native allocation tail. Its allocation/OOM behavior and the original V8 throwing-setter `.Check()` fatal assertion policy remain open implementation work.

Full CLI schema/metadata and unsupported option parsing, final host feature admission, complete public options namespace, genuine warning integration, complete Module/ESM/TS composition, original Node reference capture, and runtime qualification remain separate required work. The finite reviews above do not close those boundaries.
