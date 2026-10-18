# Kimi OAuth and provider environment source unit

The application acceptance target is Pi c268154ca1171c2f9eefe75d3d7372a68aada2d5. This unit is source implementation and authored controls; it has not executed a native build, metadata query or runtime.

## Production

- native_ai_oauth_kimi.zig replaces the legacy manual flow with genuine linked-VM async bodies for login, refresh, toAuth, readJson, device authorization, token polling and retry continuations. The shared device polling and ordinary sleep implementations are the real native dependencies.
- native_provider_env.zig preserves the ordinary constructible lookup, live process and Object.keys calls, scoped overrides, real empty fallback catch, iterator acquisition/close and persistent fallback cache.
- Guest operations use the shared AF33 boundary and C435 completion owner. Caller-stable invocation records never cross Await. Ordinary private error DATA remains separate from a current native fatal event.
- Source expression producers retire constructors and method/receiver temporaries before subsequent guest getters and coercions. Refresh preserves the linked VM's actual body/catch slot lifetime, including the caught network error across successful retries. Completed environment-owner publication preserves a reentrant owner after factory cleanup.

## Authority

kimi-provider-env-authority/manifest.json records exact c268 Git bytes, physical reference bytes and the accepted source map's sourcesContent equality. The original accepted JavaScript and source maps are retained, with original source comments/licenses.

The provider-env Source fixture is byte-for-byte accepted JavaScript. The Kimi fixture changes only its three static imports to bindings supplied by the actual compiled provider-env, sleep and device-code Source modules. Its implementation body remains byte-identical.

## Authored controls

| Install-only target | Root | Declared behavioral tests |
|---|---|---:|
| build-native-ai-oauth-kimi-genuine-af | src/native_ai_oauth_kimi_genuine_af_test.zig | 10 |
| build-native-provider-env | src/native_provider_env_test.zig | 7 |

The two Source comparison tests execute 31 controlled Kimi routes: login/polling, response validation, trusted URL checks, cancellation, refresh retries/backoff, authorization failure and rejected/synchronously thrown inputs. Expected observations are obtained by executing the preserved upstream modules, not written as passing output rows.

Additional genuine VM controls inspect immediate zero-Await fulfillment, intrinsic Promise use, string coercion, native private DATA/current fatal priority, constructor and Date-call temporary retirement, and the retained catch binding. Seven environment controls cover real Source traces, lookup/keys temporaries, failed-read cache semantics and empty-catch DATA/fatal behavior.

The OAuth response and timer inputs are explicitly controlled guest ambient functions. They establish no live network, real browser login, full SDK startup, application, portable platform or release acceptance.

VM and SDK peers reviewed the bounded production changes and actual controls without finding a remaining concrete blocker. Actual metadata must establish each emitted test list before a separately granted runtime. All old negatives and artifact evidence remain unchanged.

The identical native_public_values.zig dependency is already integrated in Main at SHA256 31178ADB24033B123C8DE22CFD7EE3981F8B993E8C2F4CA6563510A5E66FA1AD and is deliberately excluded from this commit.
