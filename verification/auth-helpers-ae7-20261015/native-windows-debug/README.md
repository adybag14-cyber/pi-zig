Public native auth helpers are Debug-qualified at exact code
`95e4ba746780a9b8bfaa7c708646299ffb6dd986` against the 16 actual observations
from immutable Source `ae7b16d43b7c78c5b6fa3213fdd1215bb339729d`.

Owned pinned Zig 0.16.0 compile PID 38752 exited 0 with 155/155 build steps.
After matching immutable checks and fresh normal 16 GiB runtime admission,
owned runtime PID 64844 exited 0 with 156/156 steps and 3/3 tests. The two
authored helper tests cover strict equality of all Source16 observations and
actual GC retention of callbacks, captured inputs and pending promises. The
retention test also checks Source's mutable globalThis binding for auth context.
The third test is the automatic declaration test included by the native imports.

The final posthash completed at 20:55:45 UTC with zero drift across all 6,550
candidate/vendor files, 19,546 compiler inputs and eight runner controls.
Before, between and after the pair, all 1,968 immutable Source files, 31,064
runtime dependencies, 1,774 Node tools, five preparation controls, 84 retained
absences and the actual Source16 fixture remained unchanged.

The tested binary SHA256 is
`58DE1D79656E398AAD90B6C253FB945DA344D4BDAE0D87B804B812ECDCDD3C75`.
Its original cache path and byte size are recorded in the qualification proof.
This checkpoint retains source and evidence; it does not publish that binary.

The exact original candidate remained clean and frozen for the entire pair.
An externally controlled runner extended the prepared candidate runner with
the required immutable cohort checks without editing the granted source head.
Both runners and their actual owner freeze hashes are retained here.

This gate qualifies envApiKeyAuth, lazyOAuth, defaultProviderAuthContext and
the shared OAuth device-code helper bodies on the tested Debug component.
The complete OAuth loader/provider/HTTP graph, other profiles, full Pi factory,
main branch merge, release and public activation remain separate gates.
