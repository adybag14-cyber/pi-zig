# Native Immediate check-phase prerequisite

`native_immediates.install(engine)` installs actual native `setImmediate` and
`clearImmediate` globals and an independent check queue. Installation is
idempotent. `timers.install(engine, io)` invokes it before registering its real
`node:timers`/`timers` namespace, so both namespaces retain global function
identity. Direct loader harnesses may install only the Immediate queue.

The scheduler uses Node's linked Immediate fields and live `_onImmediate` and
`_argv` values. The callback's receiver is its actual handle. Class and method
metadata, `ref`, `unref`, `hasRef`, cancellation, `Symbol.dispose`, and ordinary
function constructor behavior follow the required Node surface. The native
handle owns and marks its captured private async scope; VM properties own its
callback and arguments. Pending handle roots are released at VM shutdown.

The engine has unique `native_immediate_state`, `native_immediate_pump`,
`native_immediate_pending`, `native_immediate_referenced` and
`native_immediate_cleanup` hooks. The separate `native_immediate_before_poll`
hook finishes the preceding check/timer boundary before fresh I/O is dispatched;
`native_immediate_timer_ready` borrows the real timer scheduler's nonblocking
ready callback. A check batch starts only after the microtask
checkpoint, detaches its original queue, and drains microtasks between sibling
callbacks. Nested immediates wait for the next batch, with a timer/poll yield
between batches. Existing unrelated control hooks are preserved. Timer waiting
does not sleep past a pending Immediate. The direct stdio loop checks referenced
liveness before entering a check phase, so an unref-only queue cannot keep a
plain script alive, while unref callbacks may run alongside referenced work.

Source31 executes genuine pinned Node24.14.0, binary SHA256
`63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088`.
All368 source bodies in retained packet
`0CD86676BB2A46A4E772D1FD8BB3D00FCA658383BC388846DCC796547DC79263`
are compared byte for byte inside the child. Its369th live natives entry,
non-source `configs`, is explicitly excluded. No PiSDK or external dependency
execution is claimed: the caller imports only Node fs/vm/net/crypto.

Three controls use actual127.0.0.1 TCP data callbacks, establishing poll/check
ordering, sibling FIFO/microtasks, nested next-batch behavior, and the guaranteed
check-before-timer relationship when both are scheduled in a poll callback.
No arbitrary top-level timer/I/O ordering is asserted. The native harness uses
a caller-owned real kernel loopback byte exchange followed by owner-thread
poll-record dispatch after a microtask checkpoint; it does not claim to port
general `node:net`.

Actual Source child PID70908 was created `2026-10-15T21:14:35.7020074Z`, exited0,
and was independently verified absent. Full posthash at21:14:41Z passed6933
candidate files,1774 scoped Node files, six controls, and both file inventories.
The expected fixture was published only afterward, SHA256
`998FA2F426746FB3CC2406AC4A375C4777EDE4A3F6485A2C6E4C5CEA09FF5F27`.
Source owner SHA256 is
`BAF421D9C6A2A6E50424E2303E4437FF57FABF5962E6AAB333165ED1B2D92615`.

Dedicated build/test targets are `build-native-immediates` and
`test-native-immediates`. The gate also retains the affected existing timer,
timer allocation, and microtask regressions. New native tests cover actual
stdio ref/unref liveness, namespace identity, exception identity and outstanding
batch resumption, GC, VM shutdown, and Immediate host allocator failures.

Native compilation/runtime are pending Root admission. The191-language loader
must still intake and qualify this actual engine/installer integration before
default-loader readiness is claimed. Async-hooks numeric IDs and custom
promisification metadata are outside this prerequisite. ReleaseSafe, hosted
profiles, full Pi, release and public activation remain false.

The first native candidate `abaab4bdc58eb4d17886c023fef46bfd71a2d435` passed
155/155 compile steps and156/156 runtime steps,20/20 tests. Its full posthash
passed6949 candidate files,19546 compiler files,1774 scoped Node files and nine
controls, including all file inventories. Owned PIDs51320 and70728 exited0 and
were independently verified absent. This proves that retained cohort only;
review then identified a completed-check flag that could survive into fresh I/O.

An additional genuine Node Source1 first completes a check phase, receives
actual TCP bytes, schedules an Immediate and timer in the poll callback, and
holds that callback8ms on the real clock so its timer is already due. The actual
Node trace is `check,timer`. Source child PID51740, created
`2026-10-15T21:45:45.1181696Z`, exited0 and was independently verified absent.
Full posthash passed6951 candidate files,1774 Node files, six controls and both
inventories at21:45:52Z. Supplement expected SHA256 is
`B50F6ACD8B89FB76A14F0204FC836BB5375E831EF0AC78DEF09FB1F78A448A1F`;
the original Source31 input and expected JSON remain unchanged.

The correction consumes the completed check boundary before dispatching fresh
poll records, instead of lazily consuming it inside the newly scheduled check.
Its native retry must match both Source31 and Source1 before readiness is
promoted. The Source1 probe and old passing cohort are retained independently.
