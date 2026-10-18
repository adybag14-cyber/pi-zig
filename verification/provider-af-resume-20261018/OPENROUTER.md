# Actual OpenRouter OAuth bodies

This unit ports the pinned c268154c provider to Zig using the linked C runtime.
The finite source reviews are complete. Build, runtime, full public login and
application qualification remain separate gates.

## Authority and composition

The exact Git TypeScript, accepted JavaScript and source map are retained under
openrouter-authority/. The Git source equals the map's sourcesContent.

- TypeScript: 3D90D1955672B64E3039E760C41B4FF1C43F5B3FC6FCBE7F80FA6F552997893A
- Accepted JavaScript: B69E807ED855095AA17B2C0D1A15F350C77E3A49F2A66853F227916DAACB4703
- Source map: EEC62AC5370B8CDA7478463D8301CDE27A2AA6CBBA3C56525247E8A9A25E0EA7
- Private fixture: 9038E3525923F8A2BC2EAEECB978E6F6D1BF0C56D6BA8AE66D24B378CA2254FE

The fixture blanks the three imports and exports the actual private exchange,
parser and error-detail functions. Every actual body, including the public
zero-Await methods, remains unchanged. These controls do not invoke login or
provide a callback success stub. Full public login must be compared using the
actual PKCE, provider environment, callback and HTTP/page import composition.

## Actual behavior

The exchange has two genuine Awaits. Pre-abort, AbortController construction,
listener registration and timer setup occur before its try. Fetch errors enter
the named outer catch; JSON errors enter the separate empty catch. Timeout
clearing precedes listener removal in finally. Ordinary cleanup failure replaces
a pending return or throw; an actual native fatal preempts catch and cleanup.
Response and token getters after finally remain outside both catches.

Request construction retires JSON call operands before reading controller.signal
and completes the init argument before guest fetch. Temporary header/body roots
are absent when fetch deletes the corresponding properties. Named catch and
parsed-array locals retain their actual Source lifetime through cleanup.

Login has four genuine Awaits, one ToObject for the PKCE destructuring pattern,
and its Source try/finally starts only after callback startup resolves. The
existing callback owner entry points are used directly; their genuine HTTP
composition remains an explicit dependency. Refresh is a genuine zero-Await
method preserving credential identity, and toAuth preserves access identity.

The ordinary parser and error-detail bodies retain live lookup, catch boundaries,
repeated properties, coercion and receiver/callee ordering. Temporary URL and
URLSearchParams receivers retire before selected get methods. Live Error
construction selects its constructor before status/template evaluation.

## Controls and review

Install-only target: build-native-ai-oauth-openrouter-genuine-af.
Artifact: native-ai-oauth-openrouter-genuine-af.exe on Windows.
Root: src/native_ai_oauth_openrouter_genuine_af_test.zig.

There are 17 authored controls. Actual Source/native observers compare 41 exchange,
19 parser and 16 error-detail routes with controlled ambient operations. Additional
controls cover intrinsic Promise and zero-Await identity, real private DATA,
actual native fatal precedence, request/catch/finally retirement, and ordinary
cleanup replacement. The final control uses real C holder finalizers to record
params-receiver retirement before its selected get callee on both parser paths.

Production 6C9B1D48AC67AF041B48C4F6DC0E879B56335211A8CBCDF89B899A1404E93AE8
completed the split SDK common/synchronous and VM async/finally reviews.
Root 2D3E6BF2, support 8B93871D, observer 7EC5BEA4 and fixture 9038E352
completed their finite control reviews. The two concrete peer corrections were
the temporary params/callee lifetime and the single PKCE BindingPattern ToObject.
All earlier 16 controls remain unchanged; the added order probe records the
actual C retirement sequence. These are authored controls, with no execution
or public-login acceptance claimed by this document.
