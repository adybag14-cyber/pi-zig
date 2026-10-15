Native public auth helpers are implemented in
`src/extensions/native_ai_auth_helpers.zig`: actual `envApiKeyAuth` and
`lazyOAuth` JS-value facades, plus `defaultProviderAuthContext`. The async
functions retain real callback receivers, raw failure and abort values,
credential/env identity, live getters, iterator close behavior, and VM-visible
roots. Lazy delegation tail-adopts the actual method result after awaiting the
cached load value. The imported filesystem dependency is independent of a
mutable global `require`.

`native_ai_oauth_device_code.zig` ports the shared actual Source polling and
abortable sleep bodies. It retains live Date/Math calls, first-poll delay,
default/minimum intervals, server `slow_down` intervals and cancellation/error
semantics. OAuth provider facades consume these shared bodies.

The actual immutable authority for this gate is
`ae7b16d43b7c78c5b6fa3213fdd1215bb339729d`, using Source `auth/helpers.ts`,
`auth/context.ts`, and `auth/oauth/device-code.ts`. The guest fixture supplies
only owned inputs and observations; it is not a host implementation.

Root granted LIGHT6. Owned Node PID 40064 exited 0 at 20:24:08 UTC; the complete
posthash finished at 20:24:25 UTC with zero drift across Source 1,968 / runtime
31,064 / Node tools 1,774 files, all five preparation controls, all extra caller
controls, and all 84 retained absent dependencies. The 16 original Source rows
were copied byte-for-byte into `src/extensions/fixtures/ai-auth-helpers-ae7-source16.json`
only after terminal pass and posthash. Both raw output and copied fixture SHA256
are `F875997C4477DB71DFD2B49B59CF4871DB7656E1B609F24915D9A4F9FBF33C9B`.

Two independent native tests are prepared: strict replay of all 16 actual Source
observations using owned temporary files, and actual GC retention of auth/lazy
callback/pending-value graphs. No native test has run at this checkpoint.
`Run-AuthHelpersNativePair-20261015.ps1` requires an explicit Root native grant,
exact clean HEAD, full source and 19,546-file pinned compiler manifests,
16 GiB normal admission before compile and runtime, Zig 0.16.0 with LLVM/-j1,
10 second per-test/host-await bounds, and terminal posthash in a finally phase.

The central OAuth loader, PKCE, and HTTP source modules are separate components.
The loader dispatches actual native provider factories and retains the canonical
Copilot catalog; it does not substitute empty flow objects. Their complete
qualification still requires the actual provider, WebCrypto, callback server,
Response, and native stream graphs being developed by their owners. The helper
gate does not qualify the complete OAuth graph, Pi facade, factory, or release.
