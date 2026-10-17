# Source-only explicit-receiver Get composition on reviewed7c

This is an INERT two-file proposal for Root/Min/Async review. No Main, Min
worktree, donor vendor, C/H, Engine, build or selector file has been edited.
No compiler, parser, formatter, Node, generator or native execution occurred.

Base is exactly7cfcf0513efa89390910bfb1e60a9b3c34cb053a, the independently
source-closed Min composition (all runtime gates still unrun): qualifiedC3
Graph0 API +C4 readonly HasTLA +C5 GetAsyncIterator +CallSite328 +explicit
optin LinkModuleGraph and its exact sort/link includes. Source default graph0
policy and ordinary Engine behavior remain that base's unchanged behavior.

Original receiver-Get prerequisite2028 retains patchSHA725AEFE4EE587C8EBB2FAC06CDBB2BDCC87BE5D12A8F626CDCAA84E44AC4ED05.
That patch was applied ONLY to a private Git index initialized from exact7c.
Only quickjs.c/h changed. Reversing the newly derived union patch restored the
ENTIRE exact7c tree, not just selected hashes. All other7c paths remain identical,
including link/sort includes, controls and provenance. Physical7c C/H match raw
Git blobs and remain unchanged. This is not a replacement of MainC3 with an old
vendor file, nor a whole-branch merge.

## Exact API and ownership

JSValue JS_PiGetPropertyReceiver(JSContext *ctx, JSValueConst base,
                               JSAtom prop, JSValueConst receiver)

All arguments are borrowed; the result is one owned Get completion. The only
body is return JS_GetPropertyInternal(ctx,base,prop,receiver,false). Thus the
actual accessor or Proxy trap receives the actual receiver independently of
the lookup base, with the existing VM getter/error/Proxy behavior. The public
JS_GetProperty entrypoint and all other existing bodies remain byte unchanged.
There is no Promise, coercion shim, Reflect call, wrapper allocation, module
lookup, ambient graph, callback cache or new state/lifetime mechanism.

The declaration is additive in the existing public property API section.
The implementation is additive adjacent to JS_GetProperty:7C lines and2header
lines. The Cloudflare adapter's superGet captures actual home.prototype and
passes its actual receiver through this ABI; no FS/Durable/namespace surrogate
is accepted as that internal Get operation. Caller roots its real JS values.

## Controls and gates

The exact original4 named raw controls are retained adjacent for review:
ordinary accessor actualreceiver/livebase; actualProxy target/key/receiver;
ordinary/Proxy exactthrowreason withoutdiagnosticcoercion; and successful native
return withactualpending event normalization bythecaller. They are prepared,
uncompiled and unrun. No count is inferred from native artifact metadata.

This patch alone does not wire those controls into a build or qualify the
Cloudflare adapter. Receiver C/H union, raw4 runtime/ownership/allocation/GC,
actual Cloudflare realstorage, Node/directC/mkdir, currentc268 shared graph and
all default application gates remain separate. The API-owned futureAF.THROW
DATA correction is EXCLUDED and must be composed/reviewed separately without
reverting this union or any7c feature.

proposal-manifest.json pins before/after C/H SHA256, exact private trees and
patchSHA. Root/Min own any future actual source commit/composition and serial
execution grants after independent Async closure. The Cloudflare25path source
intake is separate and includes ONLY an inert historical receiver patch.
