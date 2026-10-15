The native implementation is `src/extensions/native_ai_anthropic_federation.zig`.
The JavaScript fixture supplies guest inputs, fake token responses, clock control,
and observations. It is never a host implementation.

Authority inspected without execution:

- Immutable upstream `5ab7fe74c400097b386662205cd93900695b8a71`,
  `packages/ai/src/api/anthropic-messages.ts`: `PiAnthropic`,
  `getAnthropicFederation`, singleton config/fetch client ownership.
- Installed SDK `0.129.0`, `core/credentials.mjs`,
  `lib/credentials/credential-chain.mjs`, `identity-token.mjs`,
  `oidc-federation.mjs`, `token-cache.mjs`, `types.mjs`, and `client.mjs`.

Pi disables the SDK default credential chain. The public Pi path does not read
profile files, static identity-token environment values, or disk access-token
caches. This lane preserves that boundary. The explicit config has the required
organization, federation rule and token file, plus optional workspace/service
account fields. The JWT is reread on every exchange, not every request. Workspace
scope belongs to the exchange JSON body. The issued bearer token requires
`oauth-2025-04-20` on subsequent Anthropic API requests.

Source-only checkpoint checks: pinned Zig 0.16.0 formatting, AST checking, and
`git diff --check`. Native tests and Node captures have not been executed until
Root grants their bounded validation slots. No completion or parity claim is
made by preparing an observer.

After Root grants a Source slot, execute `source-observer.mjs` with the actual
SDK directory, a newly owned fixture directory and an output receipt path,
using the pinned actual Node executable. Root's immutable Source/dependency/Node
pre/post controls must surround the process. The observer creates fake JWTs and
IDs, exercises the actual SDK token cache and credential bodies, then captures
an actual owned loopback POST. It does not fabricate expected records or rewrite
captured request bodies. The adapter's singleton ownership is test scaffolding;
SDK captures alone do not qualify the public Pi facade.

Native tests cover scoped environment precedence, real owned temporary token
files, concurrent mandatory refresh, advisory refresh and error backoff, a
mandatory caller joining failed advisory refresh, invalidation/rotation,
configuration replacement, secure-endpoint rejection, redacted 401 errors,
empty/oversized assertions, unsupported token types, and actual native HTTP on
an owned loopback listener. Test execution is pending.
