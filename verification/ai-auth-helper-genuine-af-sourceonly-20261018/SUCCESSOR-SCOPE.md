# Successor to negative 5d25 source preparation

The exact published predecessor is
`5d25cf89acddf3c4484961d4228711dc7572753f`. Its original manifest remains
unchanged at SHA256
`5897505DD4B02E161DE96E76D75E7CCB740E80B33D289C4A1C23913D8F030357`.
The old manifest's product-member hashes describe that Git head, not the current
successor worktree. The predecessor and its claims are not rehabilitated.

Async's finite source review found these concrete negative cases in 5d25:

1. One guest getter/call/coercion can create successful private DATA A and later
   throw A during that same operation. A private-generation span incorrectly
   promoted that ordinary throw to fatal.
2. A successful key conversion can leave a real pending event or B1. The next
   actual environment property getter was entered without normalization.
3. Direct host factory APIs had no stable NativeInvocation covering the body.
   A raw input getter could internally capture actual fatal B, return normally,
   and lose B1 before the next getter.
4. Abort callee/signal/ignored-result temporaries and IteratorStep result/done
   temporaries remained rooted through later Source callbacks. Previous envVar
   bindings also remained in private state into the next step or abrupt close.

The successor is local to the same three product files. Guest operations no
longer inspect private birth tags or promote them by generation. Their exits
normalize actual pending/current invocation authority through nativeCallbackResult
before root retirement. Captured-only flags remain DATA. Direct entries now
retain a stable stack NativeInvocation through body, owned cleanup and final
leave, preserving actual B1 without interpreting diagnostic flags. Successful
key conversion checks actual entry before entering the later getter.

Short synchronous scopes now retire abort(signal lookup, callee, ignored result),
IteratorRecord assembly temporaries, propertyTruth(done), and IteratorStep/Value
results before the next Source callback. Only the IteratorRecord and current
envVar survive as lexical state. envVar ends before the next IteratorStep or
IteratorClose; successful result.source independently retains its returned name.
These phases add no Await and use the unchanged C435 completion/ownRoot helper.

Six additional prepared tests cover:

- SAME getter, call and coercion private DATA A followed by ordinary throw A.
- The same three operations with a distinct actual current fatal B1, exact B
  identity and B != A after guest code also throws A.
- Direct host lazyOAuth with internally captured actual B1 versus captured-only
  flagged private DATA; next getter count and suppression/frame balance.
- Successful native key coercion returning a valid key with actual pending A;
  the actual environment getter must remain unentered and exact A must surface.
- Prior-job WeakRef controls for IteratorStep result, abort signal/callee/result,
  previous envVar before next step, and rejected envVar before close.
- A sole real native IteratorStep-result carrier whose finalizer publishes
  actual fatal B during retirement, before ctx.env or a guest catch can run.

The predecessor's fresh raw getter control is corrected to use the trusted
actual `throwNativeOutOfMemoryFatal` producer. An unmarked private birth alone
does not provide current fatal authority. The old control bytes remain in 5d25.
There are eleven authored native tests in the successor root plus the separately
parameterized genuine Graph0 context control; actual imported metadata is unknown.

The actual physical-URL Graph0 route and two/three Source Await structure are
unchanged. Source authorities, published-map bindings, Source16 fixtures,
historical proofs, external legacy asyncArrow callers and no-URL legacy
fileExists remain as recorded. No C/H, Engine, shared Scope, C435, native AF ABI,
build activation or accepted reference bytes change. C354/H0DBC, Promise
forwarding, G2, actual AI-owner wiring and runtime/application qualification
remain separate external requirements.

No compiler, source parser, AST, formatter, native, Node, CI, metadata or process
probe job ran. All controls remain unrun. Static source review is requested on
the separately sealed successor; it conveys no syntax or runtime qualification.
