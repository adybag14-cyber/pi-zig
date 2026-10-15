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

The tee implementation acquires the real source reader, performs serialized
reads, clones each byte chunk before either branch enqueue transfers storage,
closes/errors the actual branch controllers and combines both cancellation
reasons before canceling the real source. Its callback state is a rooted native
record, and error propagation uses the actual source promises. This first byte
tee still uses a default reader; the Source byte tee's dynamic BYOB-reader
switching and detached replacement-buffer ownership remain outstanding.

The core intrinsic helpers inspect native stream/reader/controller classes and
invoke real state operations without consulting mutable public methods. Public
isReadableStream/isDisturbed/isErrored/closeController use the same private
binding root. The per-binding class IDs have not yet been unified for streams
created by a private FileHandle assembly before public bootstrap.

The underlying byte core's earlier unchanged candidate passed actual Source12
and FileHandle Source8 comparators:24 actual tests,0 skips, compile233/233 and
runtime235/235, common frozen SHA256
D8832699489C26956E3A6DBAB8094A0426C56C449B12D7644ED55D8F52DFDCF1.
That qualification does not extend to these new public/composition changes.
Genuine public graph Source9 subsequently captured all9 cases with full post0;
batch SHA256 DB0777CAD8CB59E957F51C0BFD79DDB95EC19392D9F95A0BBC59A426A385DEF7.

Generic/default stream queues and size algorithms, the complete shared reader/
controller/request constructor/prototype graph, source-compatible branding and
metadata, byte tee BYOB switching, public async iteration, pipe behavior and
allocation sweeps still need implementation and genuine native gates. Current
install supports the genuine byte subset; it must not be presented as complete
public or Body/Response qualification. The next phase must retain the existing
Source12/FileHandle8 regression targets while adding graph and consumer gates.
