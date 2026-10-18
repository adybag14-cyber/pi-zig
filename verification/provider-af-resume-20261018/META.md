# Meta OAuth source port

The production implementation in `src/extensions/native_ai_oauth_meta.zig` follows the exact Pi source at `c268154ca1171c2f9eefe75d3d7372a68aada2d5`. The preserved TypeScript bytes match both the Git object and the accepted JavaScript source map. Original files and their hashes are in `meta-authority/`.

The native VM owns the actual nested async functions, Await reactions and return adoption. Device authorization, polling and key minting retain their separate responses and JSON waits. Login retains the actual catch boundary and three Await steps. `refresh` remains an ordinary arrow returning `mintApiKey`; `toAuth` is a genuine async method with zero Await operations and preserves access-value identity.

The error-detail loop uses the live Array iterator and actual property keys, keeps the previous head through next/done/value, and keeps uncaptured loop bindings until function exit. Normal early return performs IteratorClose with result-object validation, while abrupt close preserves ordinary DATA and current native fatal events. Request constructors, temporary arguments, URL constructors, Date receivers and callees retire at the corresponding Source expression boundaries.

The install-only target `build-native-ai-oauth-meta-genuine-af` contains 13 authored controls. It compares 26 login/device routes and 13 mint routes against the actual preserved Source module in the same linked C VM, plus ordinary/async declarations, immediate completion, failure identity and causal C-holder lifetime checks. The only Source fixture transformation replaces the exact DeviceCode import with a test dependency binding; that dependency is itself the real Source DeviceCode module. HTTP responses and timer delivery are explicitly controlled inputs, not live provider authentication evidence.

The production source passed a finite peer review with no concrete blocker. The authored controls still require compilation, actual metadata discovery, independent audit and bounded execution. This source unit does not establish whole-application or release qualification.
