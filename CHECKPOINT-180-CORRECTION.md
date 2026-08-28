# Checkpoint 180 correction notice

Checkpoint 180's claimed production integration was not valid. This checkpoint preserves that historical artifact for provenance but explicitly supersedes its provider-method implementation and verification claims.

## Defect found

The provider callback encoder had been inserted into `pi.unregisterProvider(name)` instead of `pi.registerProvider(...)`. It therefore traversed and replaced the provider **name**, not the provider configuration. The production registration path still placed the unencoded object directly into the manifest/action payload, where `JSON.stringify` silently discarded function-valued members.

The misplaced encoder also reused the general extension `handlers` map rather than a provider-specific callback registry. Even if reached with a configuration object, native code had no provider-method invocation protocol or callback-owner association.

## Why checkpoint 180's tests passed

Two tests were false positives:

- `checkpoint-tests/provider-method-manifest-bridge.mjs` implemented and exercised a separate in-test encoder instead of launching `src/extensions/js_bridge.mjs`.
- `checkpoint-tests/check-provider-method-production-integration.py` checked only for marker strings anywhere in the bridge source. The markers were present inside the wrong function, so the check passed.

Checkpoint 180 also did not run the complete build and test matrix recorded as required by its own continuation handoff.

## Correction in checkpoint 181

Checkpoint 181:

- moves encoding into the real registration path;
- retains callbacks in a dedicated provider callback map;
- adds the native-to-JavaScript invocation protocol;
- associates descriptors with the persistent extension worker that owns them;
- validates callback id **and descriptor path** before dispatch;
- replaces both false-positive tests with production-source tests;
- runs the default executable build and the complete test matrix;
- repeats all required gates from a fresh extraction of the final archive.

Any statement in `CHECKPOINT-180.md`, `CHECKPOINT-180-VERIFICATION.json`, or the checkpoint-180 final response claiming that production provider methods were preserved should be read as corrected by this notice and `CHECKPOINT-181.md`.
