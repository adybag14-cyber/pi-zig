# Native lifetime, model consumer and catalogue integration

Pinned Zig 0.16.0 Windows Debug, default backend: 131/131 tests and 193/193 build steps passed. The owned process exited successfully; post-verification found no drift across 4,211 source and 19,546 tool files.

The controlled CodeMode owner now releases retained JavaScript values through the runtime supplied to its C finalizer. A real registered finalizer regression destroys its context before releasing the owner; the prior implementation crashed on that test. The repaired implementation passes. This addresses the context-lifetime mechanism observed in hosted macOS finalization crashes; hosted repair qualification remains required.

The genuine upstream default CodeMode model catalogue program runs against the native query/availability registry. Consumer tests cover internal tool routing, hidden rows, usage, structured error values and nine classifier requests with four concurrent slots. Caller-supplied typed-service callbacks are used for these consumer tests. The complete native typed Models service/auth bridge remains separate unfinished work.

The catalogue refresh is generated from immutable latest-source provenance in docs/catalog-19cb534.md. The fatal editor tests continue to require exact diagnostics, exit status and physical restoration; they no longer require a transient text paint after fatal shutdown begins.

No native-default activation, legacy host removal, full Pi compatibility claim or cross-platform qualification is implied by this local gate.
