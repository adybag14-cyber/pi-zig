# Actual TTY assembly qualification target (prepared, unrun)

This is an explicit Windows-only target. The `native-tty-assembly-controls`
build option defaults to false. Neither its test step nor its artifact install
step is attached to ordinary test/install or frontend startup. This packet has
no execution grant. Source declarations are not observed test metadata.

The fixture creates an actual Engine, real inherited environment/process/timers,
the real CommonJS node:module implementation, native node:os, actual classic
streams, and an active embedded Frontend. Its stable caller-owned Frontend is
not copied after binding. Bootstrap captures actual console-mode authority and
pristine dependencies before the controls admit guest getters. The canonical
Socket provider/net carrier come only from the shared dependency facade's
`canonical.acquire`; the fixture never manufactures compatible fake providers.
Shutdown stops the actual Hub resources while Frontend and Engine remain alive,
then retires bootstrap/frontend/fixture roots before Engine teardown.

The nineteen declared tests cover canonical namespace/CJS identities, actual
linked default-loader paths, replaced user loader delegation, initialization
reentry/retry, ordinary and fatal pending-owned cleanup, trusted GPA failure,
lazy OS getters, immutable publication failure, existing real net records,
frontend process getters, and successful consuming property definitions that
capture a current fatal with an empty VM exception slot. The active-frame and
unframed profiles are separate genuine calls within the final control. Prepared
expected names are extracted from source solely to constrain a later metadata
audit; no observed query output or pass count exists.

The exact shared filesystem dependency packet must be independently closed and
composed before compilation. It supplies the real Socket/adopter/synchronous
TTY metadata routing, canonical provider/cache, Hub resource polling, common
native completion wake, and the single qualification-aware CRT close pool.
At preparation time these files are absent from this worktree; their later
exact intake must receive its own manifest and source review. RootBfb actual
NativeInvocation/producer semantics and the two Root02a syntax fixes are
prerequisites, preserved by this branch. No older whole Engine/Hub copy is
authorized by this target.

After Root's separate resource/ownership grant and complete preflight, the
prospective compile/install step is `build-native-tty-assembly-artifact` with
`-Dnative-tty-assembly-controls=true`; `test-native-tty-assembly` is a distinct
runtime step. Root must bind the sealed candidate/compiler/driver/control
closure, fresh admission, raw artifact roles, metadata names and full pre/post
absence through the current bounded owner. These names are preparation data,
not permission to run either step.

This target deliberately keeps `qualification_admission=false`: it exercises
real assembly and publication without opening a physical console endpoint.
It does not qualify Console read/write/cancel/CRT retirement, legacy native
output, frontend interaction, the default application graph, full node:net or
full node:util. Those require separate actual-capability cases and original
Node24.14 observations. Original input files, Source20/14, old captures and
historical authority manifests remain unchanged. No goldens were created.
