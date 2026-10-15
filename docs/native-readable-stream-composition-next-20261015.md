This source-only checkpoint provides a concrete native_readable_stream module
for dependent Body/Response/OAuth modules. It has not been compiled or executed.
It does not qualify or activate the complete public ReadableStream graph.

install(engine) owns its private bindings in a dedicated Engine JSValue root,
freed during Engine teardown. It installs the genuine existing native byte
constructor with shared getReader/cancel/locked/tee methods and toStringTag.
These calls use native state/class checks; no stream, controller, reader,
promise result, network response or expected packet is fabricated.

fromBytes(engine,copiedUint8Array) retains actual copied storage and drives the
real byte controller through pull/enqueue and a later EOF response. The public
fromAsyncIterator(engine,iterator) captures the actual iterator.next method,
awaits it on the VM owner, copies genuine ArrayBufferView chunks into byte
storage, skips empty chunks, closes at actual EOF and calls the actual optional
iterator.return(reason) on cancellation. Promise and raw rejection identities
flow through native continuations. It creates no extra transport worker and
uses the captured native constructor rather than a mutable global constructor.

The public constructor also creates genuine default streams. Their queue roots
actual JavaScript values, calls the captured size algorithm only for queued
chunks, tracks measured backpressure, and retains zero-sized queued values until
read. Pending reads preserve chunk identity. Cancellation, reader release,
errors and queue-drained close use the same native promise/state owner. Strategy
getters run before source.type, following the actual Node constructor ordering.

The tee implementation acquires the real source reader, performs serialized
reads, preserves default value identity across branches, clones each byte chunk
before either branch enqueue transfers storage,
closes/errors the actual branch controllers and combines both cancellation
reasons before canceling the real source. Its callback state is a rooted native
record, and error propagation uses the actual source promises. This first byte
tee now switches between actual default and BYOB source readers according to
the pulling branch's live request. It passes that branch's destination to the
source, clones the other branch before transfer, returns the replacement view
to the original request, and forwards only the current reader's close failure.
The pull-into descriptor retains its original full backing length so detached
destination validation uses the original ownership boundary. EOF closes real
branches and commits retained zero-length BYOB results. This new path is
source-only and needs a genuine tee probe and native regression gate.

The core intrinsic helpers inspect native stream/reader/controller classes and
invoke real state operations without consulting mutable public methods. Public
isReadableStream/isDisturbed/isErrored/closeController use the same private
binding root. Stream/reader/controller class IDs are registered once per engine
and reused by private FileHandle and public bindings, including FileHandle
streams created before public bootstrap. Public reader/controller/request
prototypes dispatch through native class/state checks. Reader constructors
acquire the genuine stream lock; controller and BYOB request constructors reject
external creation.

The underlying byte core's earlier unchanged candidate passed actual Source12
and FileHandle Source8 comparators:24 actual tests,0 skips, compile233/233 and
runtime235/235, common frozen SHA256
D8832699489C26956E3A6DBAB8094A0426C56C449B12D7644ED55D8F52DFDCF1.
That qualification does not extend to these new public/composition changes.
Genuine public graph Source9 subsequently captured all9 cases with full post0;
batch SHA256 DB0777CAD8CB59E957F51C0BFD79DDB95EC19392D9F95A0BBC59A426A385DEF7.

The complete source-compatible graph metadata and constructor validation,
byte tee/iteration qualification, pipe behavior and
allocation sweeps still need implementation and genuine native gates. Current
install supports genuine byte and default queues; it must not be presented as complete
public or Body/Response qualification. The next phase must retain the existing
Source12/FileHandle8 regression targets while adding graph and consumer gates.

The new strict test-native-readable-public-source target replays the unchanged
genuine Source9 body against actual native constructors and compares every
captured property and error. Its expected fixture was assembled only after
verifying all nine accepted output/post hashes and zero-drift post receipts;
fixture SHA256 C1A253AFA6F495E8E309EAD4D6E3B4B3D95D306E277170661E25AB3D054F60D9.
No metadata is removed from those packets. Missing Node-private state views,
inspection/transfer symbols, iteration and pipe methods remain explicit gaps;
this strict target has not run and is expected to expose those gaps.

values()/Symbol.asyncIterator now use a real custom Web iterator over the native
reader, matching Node's distinct iterator implementation rather than an async
generator. Each next/return operation queues after either outcome of the prior
promise; the first next is delayed by a microtask. EOF/error release the genuine
reader lock. Return cancels with the original reason and releases before waiting
for cancellation, while preventCancel only releases. Chunk thenables remain
inside the result value rather than being awaited. The iterator inherits the
actual QuickJS AsyncIteratorPrototype and roots all continuation state. This
new implementation has only static checks and still needs genuine Source cases.
