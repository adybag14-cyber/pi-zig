# Native TTY binding continuation proposal

No backend selection or native execution is authorized by this document. Root
authorized source-only implementation after this finite proposal. No shared C,
header or Engine ABI modification is proposed in the initial unit.

## Identity, admission and ownership

Native binding Provider has one Engine, one actual canonical Socket.Provider,
and a fixed native TTY holder class. Its native function captures retain the
Provider holder. Each TTY object is that exact class, with its own native endpoint
and Engine identity. Register the known class through addHandleAdopter before
exposing the namespace. Never obtain a cast class ID from public metadata.

TTY(fd, ctx) admits a native descriptor through the actual descriptor provider.
On Windows, fd is a CRT integer, never a numeric HANDLE or a registry token.
The real CRT `_get_osfhandle` is borrowed until transfer/duplication succeeds;
invalid-descriptor handling must not invoke the CRT process-abort handler.
Primary libuv uv_tty_init duplicates fd0-2's underlying OS handle specifically
to avoid closing stdio; fd>=3 retains actual CRT ownership. Those distinctions
must remain explicit, including checked close without uncertain retry. Probe
uses real GetFileType/GetConsoleMode and console input/output queries. A pipe,
file or missing descriptor is not a TTY. Failure populates actual ctx error
fields for the existing Source ERR_TTY_INIT_FAILED path.

Remote/frontend descriptors require authenticated capability admission. Existing
FrontendBridge is a generation-checked process-stream lease but does not carry a
native fd mapping. A proposed provider extends host capability wiring with
explicit descriptor identity and retained endpoint operations, bound to that
lease/Engine/generation. A TTY fd0/1/2 may map to its authenticated frontend only
when the host supplies that actual mapping. Otherwise worker CRT descriptors
retain their true native kinds (normally pipes). No bool/dimension hydration is
converted into native handle ownership. Local embedded stdio has actual console
handles owned by native_stdio_frontend, which may export a retained endpoint
capability without lending its File close responsibility to the TTY.

## Operations and IO/lifetime boundary

Native TTY exposes actual getWindowSize, setRawMode, setBlocking and stream
endpoint Hooks. Windows dimensions follow libuv's screen-buffer width and
visible-window height, preserving zero values and real errors. RAW_VT requests
WINDOW_INPUT plus VIRTUAL_TERMINAL_INPUT, with Source fallback only where its
actual input translator is present. A partial implementation must not silently
claim raw VT support on an incapable console. The actual console mode authority
must coordinate multiple holders and restore owned state during native host
retirement; it cannot restore another frontend's mode speculatively.

Canonical Socket Hooks preserve owned input/output demand, copied native write
segments, actual accepted-byte completion, separate final/endpoint retirement,
and native ref/unref. Kernel callbacks retain only native packets and the shared
native_owner_wake.Ref. IO completion, cancellation and quarantine are actual
terminal states, not nextTick surrogates. Keep existing wake detached-admission
contract: all worker entitlements are retained before launch/admission, notify
after detach is a no-op, native packet refs survive until acknowledged or held
by bounded detached retirement. Reuse the filesystem lane's scheduler/wake;
do not invent a second scheduler or retain Engine pointers in worker packets.

Direct synchronous console calls must preserve Source blocking behavior where
it applies; calls capable of indefinite blocking require exact native ownership
and cancellation/retirement. ANSI processing and cross-write/read UTF conversion
must follow real console/libuv semantics, including invalid input/carry, before
those operations are selected. No UTF8 or key-event translation approximation
is qualified by the color-only controls.

## Primary authorities

* Node24.14 src/tty_wrap.cc: native constructor ctx, uv_guess_handle, raw VT.
* Node24.14 deps/uv/src/win/handle.c: genuine CRT fd-to-handle/type check.
* Node24.14 deps/uv/src/win/tty.c: stdio duplication/ownership, raw-mode flags,
  console window dimensions and native write/read processing.
* Microsoft `_get_osfhandle` descriptor/HANDLE ownership and invalid parameter
  behavior: https://learn.microsoft.com/en-us/cpp/c-runtime-library/reference/get-osfhandle
* Microsoft DuplicateHandle ownership: https://learn.microsoft.com/en-us/windows/win32/api/handleapi/nf-handleapi-duplicatehandle
* Microsoft console mode API: https://learn.microsoft.com/en-us/windows/console/setconsolemode

These are source/API authorities, not runtime evidence. The original code
references are retained and hash sealed with the unit. Root/peer review is
required before any new shared ABI or backend selection.

## Authored continuation checkpoint

`native_node_tty_windows_console.zig` now contains real CRT descriptor lookup
with scoped thread-local invalid-parameter handling, exact isTTY native type
probe, input/output initialization probes, actual window dimensions, and an
unselected Console admission/ownership implementation. It reserves native close
uncertainty and shared close-worker wake entitlements before taking ownership.
fd0-2 are duplicated; their native direct-CloseHandle pool reserves16 tickets
and both canonical wake entitlements before duplication. One bounded native
worker retires the actual HANDLE only after IO acknowledgement. No extra CRT fd
or non-Source EMFILE failure is introduced. The original stdio CRT descriptor
remains borrowed. This supersedes the earlier unselected private-CRT-association
proposal retained in023ae619; that commit is not selected or rewritten.
fd>=3 transfers the real fd only after successful native checks/reservations and
uses the existing canonical reviewed CRT close pool, not the direct HANDLE pool.
A fixed16-slot native failed-rollback registry retains uncertain CloseHandle
failures without retry. Native handle IO admission/retirement and close methods
delegate the reviewed CRT lease/close pool rather than closing a borrowed File.
The close pool and wake types must be the one canonical FS instances.

`native_node_tty_binding.zig` now authors the actual native holder classes,
immutable captures, Engine/class checks before casts, traced native provider and
endpoint lifetime, native TTY object creation, real native isTTY/window/raw/
blocking methods, and canonical Socket adopter registration. The native owner
type is deliberately concrete at composition; no fake Endpoint/Callback inputs
are provided. Native endpoint creation supplies actual error context or an owned
endpoint. Failed native init releases the unused host holder allocation.

These two new leaves are not independently reviewed or compiled and are not
imports/selection. The actual bounded console read/write owner, complete native
UV error mapping, Source internal-handle descriptor parity, global console mode
coordination/restoration, legacy key translator, UTF carry, and authenticated
frontend capability exporter remain incomplete. No linked ownership guard is
removed. They must be finished and reviewed before constructing the namespace
with production native bindings. This continuation does not alter the separately
source-closed three-leaf TTY/color unit at356558e0.

The subsequent source continuation now also has the actual synchronous VT-output
algorithm and ReadConsole worker tickets, followed by a fixed16 native console
lease registry, source raw key-event/WTF8 translator and native String dispatch
calculator. The lease registry is the concrete Lifetime interface consumed by
the read pool; its tokens contain only slot/generation. Worker retirement drops
the exact in-flight read before the final native reference can transfer CRT close
to the existing canonical pool. There is no Engine/JS/Io/allocator pointer in
either registry or worker records. Registry/worker generics must be instantiated
once with the same canonical ClosePool/Wake types.

Raw key state preserves Source alt-compose filtering, keyup exception, function
key modifiers, UTF16 surrogate carry, unsigned repeat count and partial delivery.
Normal line reads use per-read WTF8 conversion without a raw-key carry cell, as
the original uv_utf16_to_wtf8 helper does. Original idna.c is retained authority.
Output retains actual WriteConsoleW counts, including an unexpected partial
successful call as a separate diagnostic; Source's BOOL-based accepted byte
count is not conflated with the conservative confirmed native prefix.

native_node_tty_dispatch.plan computes Source native String StorageSize and
small-string fast-path classification before the actual console lock. Recognized
native encoding labels are EXACT Source switch labels; uppercase/default labels
take the real Buffer.from/writeBuffer path. Small String failures count the
actual Source synchronously-written shortcut0, whereas Buffer/large String
increments total before native try-write. The separately authored canonical
Socket accepts source/encoding metadata and distinct dispatch/accepted counters;
its independent source status is not transferred by this packet.

Actual VM endpoint/Hub owner composition, UV error mapping, native raw-mode
retirement/restart, shared original-mode restoration, input/resize aggregation,
native-handle descriptor parity, and authenticated frontend capability export
still require completion/review. Nothing is selected or qualified. This remains
a source implementation in progress, not a claim that all controls pass.

The actual Windows VM owner is now authored in native_node_tty_windows_owner.
It clones the canonical Socket provider/adopter registry, keeps idle sockets
weak, marks pending-operation roots once through the provider, uses the real
Hub Resource.poll/referenced/stop/stopped seam, and separates native-only token
retirement from VM object lifetime. Whole-call synchronous output uses the
actual Source counter plan. Writable TTY shutdown clears native writability
and queues the actual native no-op request for owner-checkpoint completion
(win/stream.c203); only nonwritable/already-shutting/closing handles take the
synchronous ENOTCONN branch. Close acknowledgement remains independent.

Mode transitions cancel the exact read ticket, retain its old epoch until the
actual syscall returns, and only restart in the new mode afterward. Unfinished
raw key bytes remain retained but are not delivered in normal line mode. A
failed mode change leaves reading stopped as Source does. Real data demand
queues another native read before the owner goes idle; pending decoded bytes
use a genuine buffered-read resubmission wake, never a Promise/timer stand-in.

native_node_tty_frontend_mode now supplies an actual EMBEDDED frontend capability:
it verifies Engine/thread/active state, the real process-stream lease/generation,
and exact CRTfd0-to-native-stdin handle identity, then copies the original mode
captured by the genuine frontend Console owner. A hydrated TTY boolean/dimension
cannot satisfy this check. No Frontend pointer enters native workers or the
process-mode authority. No existing frontend/Engine source file is edited.

native_node_tty_windows_modes owns the real CONIN$ original-mode snapshot/reset,
one bounded process-lifetime handle like libuv's global console authority. It
uses the validated embedded original snapshot when available and resets only
after the last provider stops, so closing one TTY wrapper cannot undo another
live provider's raw mode. Failed initialization/reset is retained as native
diagnostic state; unknown mode is never replaced with a guessed value. Remote
framed workers remain genuine pipes unless a real frontend operation provider
exists; no cross-process console handle transfer or falseTTY is introduced.

The shared SystemError registry/adapter is a separate proposal at77310673, still
under review; TTY-specific error registrations and full legacy output/resize/
internal-handle surface qualification remain explicit. All backend source is
uncompiled/unrun/unselected and does not inherit the356558 finite source closure.
