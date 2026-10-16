# Source-only ownership correction after7b2762

Independent review rejected the ownership preparation at7b2762 for execution.
That commit remains immutable. No capture was launched from it. Original caller,
96BE owner and accepted273 bytes remain unchanged. This successor still requires
independent review and a fresh Root grant before any launch.

Every new process now goes through the shared retained-child function. Immediately
after Start returns it registers the actual process object in the owner's children
registry, then registers a partial PID/expected-parent/intended-argv record before
StartTime, CIM or validation probes. A launch ledger is written before those probes.
After a successful start, validation and ledger errors return the registered child
as a negative; they do not throw away its handle. The owner keeps its bounded wait
even if an observation fails. The original96BE implementation remains unchanged;
its separate outer bound and Node ready/original-kernel reconciliation remain.

The supervisor establishes its config/self/context before its first Git process.
Seal workers establish their own context before Git. Git uses the same explicitly
cleared PSI, per-child fresh16GiB admission, immediate handle/partial launch ledger,
bounded pipes,20s wait and verified settlement. Its launch records survive every
failure and are included in the final ownership union.

Root approved one narrowly scoped terminal-only proof for short read-only Git.
Only exact rev-parse HEAD/HEAD^{tree}, ls-files and status --porcelain with optional
--untracked-files=no are allowed, and only in the assigned candidate or Source698.
Every invocation adds --no-pager, --no-optional-locks, core.fsmonitor=false and an
owned empty core.hooksPath. The pinned executable SHA is recorded before launch
and rechecked afterward. If live CIM is unavailable solely because the retained
Git kernel handle is already terminal, only zero exit, bounded pipes and a fresh
independent PID/creation absence check permit its read-only output. The record
explicitly says live CIM argv unavailable and grants no kill authority. A full CIM
identity conflict never takes this exception. Node and all other phases still
require complete live parent and intended-argv reconciliation.

Full direct launch identities now require exact expected parent and a pure Windows
CRT command-line parse equal to the intended executable/PSI argv. Subsequent
identity comparisons include parent PID. The Node start fence additionally checks
ready.argv and ready.execArgv against the intended node-command arguments, as well
as actual live CIM argv, original96BE creation/argv/executable hash and parent.

Absence is established only by no row or a different trusted creation time. A full
same-kernel row with conflicting exe, parent or argv is present/conflicting. Missing
creation or other incomplete live fields stay unknown and never grant a kill.

The launcher's complete journal is the exact contained sibling <run>.launcher,
created without creating/replaying the future capture run. It records itself and
the hidden supervisor, and observes descendants throughout its bounded wait.
The union reads only that exact journal and run, never a prefix-selected sibling
run. Every individual launch, full/partial identity, self identity, original96BE
Node record and ready PID is included. Internal absence excludes only the current
owner and its still-live launcher; the independent external check excludes none.
Even an early preflight negative without a supervisor terminal gets an external
absence/artifact packet, with missing metadata retained as a negative.

Full Source1970/Node1774 and tracked candidate/control/accepted273 seals, all160
ordered IDs, exact four observed modules, attempts0 and no-runtime-read policy are
unchanged. No new semantic expected output, Source fallback, host implementation,
native job or global hold lift is introduced.
