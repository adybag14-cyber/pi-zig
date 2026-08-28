# Checkpoint 180 — extension-defined provider method preservation

This checkpoint closes the manifest-boundary loss where JavaScript function-valued members of extension-defined providers were omitted by JSON serialization.

## Implemented

- `src/extensions/js_bridge.mjs` now recursively encodes callable provider members before the provider registration crosses the V8 manifest boundary.
- Function objects remain resident in the extension callback registry; the manifest carries stable JSON descriptors containing callback id, kind, and member path.
- Nested provider methods, OAuth method groups, and functions inside arrays are preserved without serializing function source or leaking closure data.
- `src/provider_method_ref.zig` defines and validates the Zig-side `ProviderMethodRef` descriptor contract.
- `checkpoint-tests/provider-method-manifest-bridge.mjs` exercises nested methods, closure preservation, JSON round-trip, and callback invocation.
- `checkpoint-tests/check-provider-method-production-integration.py` guards the production integration markers.

## Descriptor contract

```json
{
  "__pi_callback_id": "provider:<name>:<path>:<ordinal>",
  "__pi_callback_kind": "provider_method",
  "__pi_callback_path": "oauth.refreshToken"
}
```

## Verification in this checkpoint

The required focused gates pass with the supplied Zig 0.16 toolchain: Zig formatting checks, runtime AST validation, standalone `ProviderMethodRef` tests, exact injected-JavaScript syntax validation, the closure/receiver/callback invocation regression, production-marker integration checking, build-graph loading, and any narrowly named provider/extension/V8 verification steps exposed by the build graph.

The generic full build and full test lanes were intentionally not used for this continuation, following the established rewrite instruction to use focused checks rather than full-build tests. `CHECKPOINT-180-VERIFICATION.json` records every command, duration, exit status, and log name.

## Remaining parity work

The next slice should route each provider subsystem call site through these descriptors end-to-end (including cancellation/error mapping and OAuth credential refresh persistence) wherever a call site still assumes data-only provider definitions. The manifest no longer destroys the callable members, so that work can proceed without changing the wire contract again.
