# Meta OAuth source port

The production implementation in `src/extensions/native_ai_oauth_meta.zig` follows the exact Pi source at `c268154ca1171c2f9eefe75d3d7372a68aada2d5`. The preserved TypeScript bytes match both the Git object and the accepted JavaScript source map. Original files and their hashes are in `meta-authority/`.

The native VM owns the actual nested async functions, Await reactions and return adoption. Device authorization, polling and key minting retain their separate responses and JSON waits. Login retains the actual catch boundary and three Await steps. `refresh` remains an ordinary arrow returning `mintApiKey`; `toAuth` is a genuine async method with zero Await operations and preserves access-value identity.

The error-detail loop uses the live Array iterator and actual property keys, keeps the previous head through next/done/value, and keeps uncaptured loop bindings until function exit. Normal early return performs IteratorClose with result-object validation, while abrupt close preserves ordinary DATA and current native fatal events. Request constructors, temporary arguments, URL constructors, Date receivers and callees retire at the corresponding Source expression boundaries.

The install-only target `build-native-ai-oauth-meta-genuine-af` contains 17 authored controls. It compares 26 login/device routes and 13 mint routes against the actual preserved Source module in the same linked C VM, plus ordinary/async declarations, immediate completion, failure identity and causal C-holder lifetime checks. The only Source fixture transformation replaces the exact DeviceCode import with a test dependency binding; that dependency is itself the real Source DeviceCode module. HTTP responses and timer delivery are explicitly controlled inputs, not live provider authentication evidence.

The production source passed a finite peer review with no concrete blocker. The authored controls still require compilation, actual metadata discovery, independent audit and bounded execution. This source unit does not establish whole-application or release qualification.

The retained first 15 controls include the completed fetch argument and finite
predicate retirement cases. The sixteenth compares actual Source/native cached
next retirement during normal IteratorClose: the next method owns a C holder,
and the return getter must observe its finalizer before close proceeds. The
normal close helper clears and retires next_function before looking up return,
matching OP_iterator_close; final iterator cleanup cannot release it twice.
This narrow successor completed a finite VM source/control peer on production
41967A3A978A113F361BE41AAA415D1F53F6B9F29A74DF0D1B74C33B5018EF2B
and root4C6B2629D2D96690D2B65C00340B993932AB7B76532399C4AE348DE169A59EA2.
The shared abrupt-close owner is a separate pending correction.

The seventeenth retained control establishes the corresponding abrupt body-throw
case: cached next retires before return lookup while the exact original throw
survives ordinary cleanup. The shared native_public_values.Iterator correction
selects that Throw in C435 before clearing/retiring next. Exhaustion and failed
next/done/value keep their original receiver-before-next cleanup and do not call
return. Finite VM peer closed on shared0B1BB422A9C89E7CE8146B32413B27E42D8DFB65285C3245B89EED8AF222022E
and Meta root4757715E598279ABDA7D2C8B03ABABEB3BB8236062E88D25716127D3DD657422.
The earlier separate abrupt-close dependency is now source-corrected, with no
execution or whole-application acceptance inferred.
