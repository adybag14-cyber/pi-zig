# Actual four readline callbacks consumed by TTY

This separate source unit implements Node v24.14.0
`lib/internal/readline/callbacks.js`, using the actual retained CSI tag algorithm
and constants from `lib/internal/readline/utils.js`. The original sources and
existing Node license remain retained as authority. No compiler, AST, Node,
native test, generator or original capture ran. Main, shared C/header/Engine,
frozen TTY/utility files, Source20/14 and historical proofs are unchanged.

`native_node_readline_callbacks.create` returns the actual carrier with
clearLine, clearScreenDown, cursorTo and moveCursor in Source property order.
They are ordinary function declarations with their actual lengths and
constructibility. The leaf does not advertise Interface, promises, terminal
input editing or other unimplemented readline APIs.

Validation occurs in Source order before cursorTo's callback overload and
NaN checks. Only Source's null/no-op branches call the live global process
object's actual nextTick(callback,null). Other branches select the live write
method after constructing the real CSI string and return its actual result,
including false backpressure. No extra tick or fake completion is inserted.

Direction comparisons use the actual VM relational operators independently.
Negative movement performs actual ToNumeric again and typed multiplication by
-1, preserving Number/BigInt numeric negation using existing linked VM APIs.
This uses the existing native-port negation pattern; it adds no C ABI helper.
Positive movement gives the original raw argument to CSI's += concatenation,
so its later default-hint coercion is not replaced with the previous numeric
comparison result. ClearLine also repeats its comparisons as Source does.

`native_node_readline_errors` constructs the shared error bundle ONCE. Its
number-message branch delegates to the frozen actual TTY message function;
the additional Function/callback profile follows the real validateFunction
argument ('Function', not a fabricated lowercase caller value). It supplies
one registered ERR_INVALID_ARG_TYPE base class and ONE genuine
HideStackFramesError subclass for the validators in TTY, util and readline.
Their distinct prototypes and current constructor getters follow Source;
they share the private Node marker and the same real TypeError ancestry.
There is no flattened base/subclass alias or Error+code relabeling.

The Hide constructor performs the live Error.stackTraceLimit writable check,
save/zero/super/restore sequence, including Source's lack of finally if super
throws. Readline's actual hideStackFrames callable wrapper retains its
withoutStackTrace function, transfers ordinary handled reasons before further
getters, bypasses current native fatal events, and uses the captured genuine
Error.captureStackTrace function already provided by the linked runtime.
Existing TTY/util validator-wrapper and V8-versus-native stack formatting
qualification limits are not silently claimed closed by this new unit.
The existing native Error.stackTraceLimit setter also overwrites its owned
context value without releasing the old value (current retained C source at
js_error_set_stackTraceLimit). This concrete raw-C-accessor dependency was
reported to Root for separate C ownership review; no C workaround or edit is
included. Root's native_error_stack.install replaces that accessor with an
ordinary data property in fatal-lease workers, so the source finding is not an
observed leak in that installed profile. Raw-accessor lifetime qualification
must remain distinct until its separate closure.

The new validation catch has a leaf-local cleanup reducer. It takes the actual
unwinding event outside pending/captured slots before releasing every temporary
root. The first current cleanup fatal can promote over an ordinary error, and
a selected fatal survives later cleanup events. Current generation/tag checks
exclude captured history. Shared Scope/Engine/utility helpers are unchanged.
`native_node_readline_validation_cleanup_control.run` requires the actual
Root-composed bundle validator and captured Error class. A legal native getter
throws a sole-owned opaque holder A, installs a live stack-limit getter that
throws B, and A's real native finalizer raises ordinary C or a fresh actual
native OOM. This causally distinguishes protected B from a lost reason and
actual cleanup-fatal promotion. It is prepared, has no standalone fake require
or namespace and has not been compiled/run.

The new registrations implement actual ERR_INVALID_ARG_VALUE for cursorTo's
NaN rejection and the static ERR_INVALID_CURSOR_POS message. They use real
construct-only native NodeError classes, ordinary class-field code definition,
captured Base constructor getters, lexical code toString and actual private
inspect for value diagnostics. Broader internal/errors registrations and
alternative constructor variants are not advertised by this finite bundle.

Root composition must create this bundle instead of separately creating two
TTY/error groups. Give bundle.tty to the existing Windows TTY factory, but
bundle.util to the util installer. The former has the actual Hide range class
for validateInteger; the latter retains the BASE ERR_OUT_OF_RANGE for util's
explicit negative/safe-integer branch. Both use the SAME Hide argument class.
The registered bases remain separately retained in bundle.codes. Give its
validate_function/invalid_arg_value/invalid_cursor_pos to
the callbacks factory. Register/cache the returned real readline carrier in
the actual builtin assembler used by the SAME require function already passed
to TTY. Named/default imports must wrap that same carrier. Replacing a public
readline export remains visible through TTY's cached module object.

These are owner-thread JavaScript algorithms, not native ReadConsole input
workers. They do not acquire or release the Windows output SRW lock. A real
TTY write subsequently enters the canonical synchronous output hook, whose
lock acquisition and release stay paired on the same thread. The libuv input
cancellation semaphore's cross-thread handoff is not copied into this unit.

`original-readline-callbacks.mjs` contains genuine public Node calls without
opening any descriptor: lengths/constructibility; callback/NaN/cursor error
ordering; stream.write getter/receiver/result; ordinary and BigInt movements;
number-versus-default coercion traces; exact thrown identity; the four TTY
prototype delegates; base/Hide prototype and class identity, distinct range
variants and actual live stack-limit constructor window; cached-module/live-export behavior; and real nextTick
callback order on null/no-op branches. Expected output is absent and every
control is prepared/unrun.

Independent source review, Root builtin/require assembly review and authorized
original/native controls remain required. The private-console legacy output
packet and utility receipt remain separate; this new unit does not transfer
their review or claim whole frontend/runtime qualification.
