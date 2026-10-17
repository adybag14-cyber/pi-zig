# Native-only production host - unselected source candidate

Baseline14775669ca4ad1155957114fec9bdd40b659ca3c. SOURCE ONLY: not compiled, executed, selected, merged or released. Main is untouched. This branch intentionally implements the requested end state; building/selecting it for production is prohibited until Root accepts the exact parity and activation gates in ACTIVATION-GATES.md. No feature-readiness claim follows from removing a fallback.

## Actual production boundary

Main parseExtensionBackend now accepts absent/native and rejects legacy, node, malformed/case/whitespace/unknown values. Host and Runtime use a single native backend value. Host.loadScript always delegates to the existing real native group loader. PI_JS_RUNTIME and js_runtime_program are removed from production selection and reload. The linked C engine still executes user JS/TS extensions; node: compatibility module imports and explicit user process execution remain their real native services.

Runtime no longer embeds or materializes js_bridge.mjs, launches Node, keeps Node-program/temporary-bridge storage, or removes generated bridge files at teardown. Runtime.start is a three-argument native convenience; startNative/startNativeGroup and actual NativeOptions remain. std.process.Child, worker pipes, framing, grouped owner/view identities, process IO, UI/editor/widget/renderer services, session context, metadata ordering, deadlines, cancellation, authenticated fatal handling and exact-child retirement remain the actual existing native path. The native executable argument is owned until spawn completes; there is no persistent unused program/bridge allocation. No Engine/C/H/native-worker implementation changes are included.

## Tests remain real and required

All existing affected fixture bodies and behavioral assertions are retained. Thirty-seven Node-availability skip guards are removed across Runtime, Host, provider/OAuth/stream/registry and slash tests. Their starts now launch the actual standalone native worker. Missing artifacts or missing native semantics fail; no success placeholder or new skip substitutes for them. A Node-free environment is a meaningful gate, not an availability probe.

Build runners that execute these tests wait for the real install step and pass the exact b.getInstallPath artifact through PI_NATIVE_TEST_EXECUTABLE. The common test-only resolver requires an absolute configured path, including custom install prefixes; it never falls back to a stale zig-out image or test runner. Production's compile-time branch selects its current standalone executable and does not read this test variable. Existing native process fixtures use the same owned path and a cleared child environment with PATH restricted to that executable directory.

The native Host discovery test now exercises its actual default. Existing CLI late registration/tool execution/session persistence test now omits PI_EXTENSION_BACKEND and poisons PI_JS_RUNTIME. A bounded real CLI subprocess control requires legacy rejection before worker startup/version output. Main's selector unit covers null/native, removed legacy and malformed values; structural runtime checks require no Node/bridge fields or legacy spawn declaration. Former missing-node struct-field controls now supply the owned ignored PI_JS_RUNTIME poison instead. The old bridge_path-empty check becomes field-absence checks while filesystem no-generated-bridge checks remain.

Static inventory in this packet is source accounting, not runtime results. Original test declarations are retained (two new tests); there is no test execution, assertion sampling, skipped failed case or changed original expected/golden data. Existing unrelated platform-specific tests/skip policy are not represented as new cross-platform passes.

## Retired source versus genuine reference tooling

The old src/extensions/js_bridge.mjs is preserved BYTE-FOR-BYTE as retired-host-source/js_bridge.mjs.txt, with its original Git blob pinned. It is our historical host implementation, NOT upstream Pi authority and not an executable production/development fallback. No product import/embed/build install references it. It is retained solely for historical review/negative comparison. Original upstream Node collectors, packages, fixtures, expected data and receipts elsewhere remain unchanged and require their own explicit execution grants; they are not shipped as the application host.

Generated FILES.sha256 / ARTIFACT-MANIFEST.json and hosted workflows are deliberately unchanged. Their official regeneration/verification and exact-head hosted native qualification are activation gates, not handwritten updates or presumed success. The current CI Setup Node step must not be treated as evidence of Node-free production operation. Node may remain only in separately controlled original-reference tooling. No workflow was dispatched.

## Boundaries and readiness

This unit removes a production dependency; it does not fill VM/loader/Jiti/default-transform/SDK/Agent/provider/TUI gaps by alias or fallback. Their independently reviewed and actually qualified implementations must compose first. Unsupported syntax/modules/capabilities must remain honest failures until implemented. All commands in ACTIVATION-GATES.md are prospective and resource/ownership gated; this packet contains no job grant.
