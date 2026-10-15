# Anthropic and OpenRouter OAuth source checkpoint

This checkpoint implements the actual `anthropicOAuth` and `openRouterOAuth`
facades from immutable Source `ae7b16d43b7c78c5b6fa3213fdd1215bb339729d`.
Both exclusive modules expose `create(engine)!ownedJSValue` and retain all guest
interaction, callback, signal, fetch and Response objects on the VM owner thread.

Anthropic preserves its select prompt, browser versus copy-code methods, module
callback-host capture, preferred-port/free-port/manual fallback, verifier-state
validation, JSON token requests, actual Response text consumption, nested error
details, five-minute expiry skew, regular refresh-arrow synchronous credential
getter, and async toAuth getter rejection.

OpenRouter preserves per-login callback-host lookup, random callback path,
complete-before-browser-page exchange, manual redirect parsing, its distinct
headers and request body, exchange abort listener and timer, cancellation and
timeout normalization, HTTP error detail priority, permanent-key credentials,
and original credential identity for refresh.

Required shared bodies are actual native `native_ai_oauth_pkce.generate`,
`native_ai_oauth_callback_server.start/waitForCallbackOrManualInput`,
`native_ai_oauth_http.captureFetch/requestWithFetch`, `auth_helpers.asyncArrow`,
and the genuine Response/Body/ReadableStream graph. No alternate provider flow,
generated guest implementation, worker access to JS values, or substitute
Response is installed here.

The prepared genuine Source24 corpus records full raw request URLs, methods,
functional header entries, bodies, original Response method receivers, prompt
and notification getter order, async callable metadata, synchronous versus
async errors, issued credentials, and cancellation. OpenRouter loopback origin
binding is normalized only in comparison rows; all original full URL/request
strings remain in `rawRows`. Result errors pass a declared stack/parser-message
normalizer before both row sets are built; full original Error diagnostics were
not separately captured. Its actual Source driver imports original modules directly, with
the ae7 observation preload and exact caller controls. The bounded owner requires
successful termination, the full `1968/31064/1774` pre/post inventories, all 84
historical absences, and zero control drift before publishing the expected JSON.

The native harness has a Source24 replay and a separate GC test retaining an
in-flight fetch plus credential/access identities. Build targets are
`build-native-ai-oauth-anthropic-openrouter` and
`test-native-ai-oauth-anthropic-openrouter`.

Pinned Zig 0.16.0 formatting and AST checks pass. Under the explicit Root LIGHT5
grant the genuine Source24 capture passed on Node PID 73648, exit zero, with
full zero-drift posthash complete at `2026-10-15T20:24:01.2578565Z`. Source,
runtime and Node inventories remain `1968/31064/1774`, all 84 historical absences
remain absent, and 12 native control files match their frozen pre-capture hashes.
PID absence was independently verified. Expected JSON was created only after
successful termination and full posthash; its SHA256 is
`CBBC24227FA4719A581111EF6AA9B99AA7BD83BED6D39648738082E42CCA6301`.
The qualified packet retains all 24 raw observations as well as comparison rows.

**Native semantic compilation, native runtime qualification, raw HTTP origin
qualification, full Pi and public activation remain false.** Native work requires
the actual shared Response/Body/ReadableStream owner checkpoints and a separate
Root native grant. Source24 verifies the original-source observations; it does
not establish that the authored native implementation passes them.
