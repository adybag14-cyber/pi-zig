# Native management HTTP source checkpoint

Authority is immutable latest Pi Source
`4954d760504c11df9b2cbdc040346107b6a8153d`, specifically coding-agent utilities
`management-http.ts` and `pi-user-agent.ts`. The isolated base is Root
`4e128e2c8f33f5ef7aa299475adfe4b1e8e84f2b`; image proof99b9b075 is unchanged.

`native_management_http.create(engine)` returns actual native functions
`fetchWithRetry(input, init, options)` and `getPiUserAgent(version)`. Both have
the original callable arity1; fetch is a nonconstructible async declaration
with AsyncFunction prototype, while the UA declaration is ordinary and
constructible. The namespace can be supplied directly to the remote catalog
owner as borrowed dependencies. No OAuth substitute or transport worker is
introduced. Fetch is the actual live global binding on every attempt; default
networking requires the environment owner's actual fetch facade.

The port retains the private actual Set of retryable statuses408/425/429/500/
502/503/504, immediate retries, max-retry getter/floor/coercion order, cached
retry flags and caller signal, overall and per-attempt timeouts, optional signal
filter/composition, fetch-before-init-spread order, response/status getter
boundaries and awaited body cancellation. Guest cancellation failures are
ignored. Prechecks and signal construction remain outside the fetch catch;
synchronous fetch failures use a bounded-stack native loop. Original thrown
values remain unchanged, and AbortError retry behavior depends on actual Error
membership, strict attempt-signal aborted=true and overall/caller cancellation.

Native host OOM remains a terminal, tagged native allocation failure. It is not
silently retried or swallowed by the discard-body catch. Only errors tagged to
this helper invocation receive that native ownership treatment; guest errors
and older error values retain their source behavior.

The UA is an explicit native runtime adaptation:
`pi/<version> (<actual OS>; zig/<actual Zig>; quickjs-ng/<linked C version>; <actual architecture>)`.
It does not fabricate Node/Bun identity or consult simulated process versions.
Version interpolation retains the guest's ordinary string coercion. The fetch
helper neither sets nor rewrites User-Agent: explicit caller headers and header
object identity survive the original init/signal-spread rules. Genuine Source
capture will preserve original Node UA strings separately, with this adaptation
compared by its actual native identity rather than blanket normalization.

The shared control input prepares51 genuine-original observations: status and
transport retries, discarded bodies, actual and deterministic signals, timeout
and caller abort distinctions, live getter/constructor/callee order, raw error
identity, async prolog failures, function metadata and UA version coercion.
Retained-GC and exhaustive host-GPA tests are also prepared. They do not inject
the separate native HTTP worker allocator or qualify every environment fetch
implementation. Tests are new files only; central build registration is pending.

This is source-only. Formatting and AST checks pass. Source capture awaits a
LIGHT reservation; expected JSON is not fabricated. Native compilation/runtime
have no grant and have not run. Full factory/application/release/activation
remain unqualified/inactive.
