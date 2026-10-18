# Session-local guest producer correction

SOURCE ONLY; base Root f49a5047581bb1346a866fc187085be9f097b79d.
No Node/native/compiler/parser/AST/formatter/reference job ran. Three new native
declarations are authored; eight declarations in this target are now static
Source input, not observed metadata. All control cases are UNRUN.

Original3b9/72FF and byte-intakeDF89 proofs remain unchanged. Their finite AF,
Source getter/callee/Await order, expression retirement, raw bytes and scope
reviews remain historical; they did not close the newly identified SAME guest
operation creating successful private DATA A and ordinarily throwing that A.
The copied additive limitation is retained verbatim; this correction makes no
historical runtime claim or proof rehabilitation.

The session values leaf now distinguishes guest operations from direct proven
no-guest allocation boundaries. raw() performs C435 actual pending/B1 completion
normalization WITHOUT looking at a generation, private tag or diagnostic bit.
Guest get/call/construct/define/set/concat/stringify check actual entry before
any effect, enter a caller-local stable NativeInvocation before the raw VM call,
keep it through normalization/ownRoot's incoming-output cleanup, then leave and
normalize the actual result. The borrowed Scope root is not passed to the
consuming invocation-leave API. Frames never move or escape across Await.
A successful raw value plus actual pending/B1 is a failed operation.

Only rawAllocation retains generation recognition for JS_NewStringLen,
JS_NewObject and the private JS_NewObjectProto(null) stage allocation. No arbitrary
guest operation, constructor or coercion uses that path. The two product callsite
changes use define/construct and explicitly select the private-stage allocator.
C435 typed append/per-free rules and all shared Engine/C/AF/Scope helpers are
unchanged. This does not qualify the separate VM allocation/GC/factory frontier.
No Error flag is cleared anywhere in the correction.

Native controls use an actual C successful DATA maker that calls the native
private-error producer and returns its unmarked Error after taking the VM
exception. In the SAME guest operation, getters/calls/constructors/setters/
defineProperty traps/string conversion/primitive coercion then throw that A.
They assert raw identity, a genuine nonzero private tag, unchanged ordinary flag,
changed generation and balanced invocation state. This is controlled DATA
creation, not an allocator exhaustion pass.

A separate actual native fatal producer is tested through get and call, both
with its pending exception and with an emptied VM slot plus normal callback
return. The latter retains actual B1; it does not clear Error flags. These are
producer-dispatch witnesses, not physical GPA exhaustion qualification. Actual
installed genuine bindExtensions get/call routes also await/catch the same DATA
and assert identity and ordinary classification.

The original caller fixture, Source snapshots, old5ab/3b9 controls, license,
build target and historical manifests remain unchanged. The existing install-only
target imports the three new tests through the selected root. No Main/default
activation or actual whole-SDK-owner qualification is performed.

Body also identified a pre-existing mechanical control ABI mismatch: the pinned
quickjs.h declares JS_IsAsyncFunction(JSValueConst) with one argument. Three
calls in two control files now use that exact ABI; names/assertions are unchanged.
Product1091 guestguard code is unchanged by this separate control-only correction.
