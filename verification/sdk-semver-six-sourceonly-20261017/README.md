This is a source-only private SDK semver supplier, based on Root Main
93f768cb60d45486ab63dc7bf4d6eb47482e4e24. It reuses the genuine six-export
implementation from historical clean semver c64aa31cb8726b9da66afea2c76aed34f626a402.
That historical tree, its controls and its unexecuted capture plans remain
unchanged. No Node, compiler, Zig parser/formatter, native or metadata job ran.

API: native_semver785.create(engine) returns an owned VM object with named
valid, validRange, satisfies, gt, maxSatisfying and rcompare functions. The SDK
assembly must create one namespace for its module graph and pass it as its
actual semver input, sharing function/cache identities across managers. This
does not register a global/default module named semver, alias a user's import,
or expose substitute SemVer/Range/Comparator classes.

The actual c268154ca1171c2f9eefe75d3d7372a68aada2d5 PackageManager imports these
six functions and supplies no options. Its source is byte-identical to the
historical consumed caller: SHA61BB2F0B...099310. Strict/default behavior is the
contract. Falsy options retain it; truthy loose/includePrerelease options fail
explicitly instead of approximating an unused contract. Full npm semver class,
all-export/reflection and arbitrary public-class/prototype mutation parity are
not claimed.

The original is npm-semver7.8.5, ISC. Package metadata SHA7C94CB7F...B1776;
c268's package-lock records the official semver-7.8.5.tgz SRI. Every one of the
53 installed semver files matches the original historical pinned package.
semver-original53.json records their exact bytes and paths. Inert original
source/license copies and the exact consumer are under authority; they are
never evaluated as the production implementation.

The source reference is the restored full31064 directory explicitly accepted
by Root, joined to acceptance EFEC9629...C11CF0. The workspace pointer activation
is current-byte reference authority only; it does not rehabilitate the old
reproduction lifecycle negatives or authorize a new capture job.

The genuine native algorithms retain strict UTF16 length/version grammar,
MAX_SAFE_INTEGER and prerelease number/string ordering, build stripping,
caret/tilde/x/hyphen expansion order, conjunctive/disjunctive ranges, prerelease
tuple eligibility, comparator deduplication/ANY/null-set reductions and the
original1000-entry LRU. Regex/string/array/map operations execute in the actual
VM. gt preserves left-to-right constructors; rcompare preserves reversed
constructors; maximum uses the actual live forEach and returns the original
first matching maximum/tie candidate. Retained callback state is GC-marked.

The current-boundary successor uses Root's actual native_node_function entry
and NativeInvocation machinery. The public factory guards a pending entry and
owns its own invocation. Forgiving Source catches consult actual pending or
current invocation failures, rather than an enclosing old generation snapshot.
The semver-local temporary scope transfers ordinary primary completion
ownership, publishes direct OOM before cleanup, observes each owned release,
and retains the first actual fatal. Captured history/diagnostics are DATA.
Native traversal polling observes cancellation and a bounded host quota; it
does not claim identical Node instruction counts. Shared Engine/C/helpers are
unchanged. These new ownership/cancellation bodies are uncompiled/unrun and
require independent source review and actual qualification.

Original controls: unchanged327-row input plus the separate unchanged5-row
supplement, no expected JSON. capture-original.mjs imports the real accepted
original semver package, checks its53 files and consumer/input pins, and writes
only a fresh owner-provided output leaf. Its templates are false. A Root job
must separately own Node, full source/runtime/tool/control inventories,
environment, memory/serial admission, deadlines and process absence.

package-manager-callers.input.mjs invokes the actual original class and real
SettingsManager over fresh physical package.json fixtures. It replaces no
class, method, settings or semver function. Those caller controls cover real
valid/validRange/satisfies paths only; the standalone original input covers
all six functions. No npm-view network/transport, full PackageManager or whole
SDK success is fabricated. capture-package-manager-callers.mjs is prepared,
unrun and requires its own Root release; expected output remains absent.

Native targets are install-only and default-off:
build-native-sdk-semver-six contains the private namespace/pending entry,
captured DATA, explicit options boundary and real native-finalizer controls.
build-native-sdk-semver-original contains genuine original-row comparison,
retained-callback GC and actual fatal-source controls. The comparison still
fails when its qualified original JSON is absent. There is no fallback golden,
run step, modified default test suite or guessed compiled metadata count.

All native controls and original programs are UNRUN. GPA/C malloc sweeps and
full mutated-builtin/class/host-finalizer coverage are not qualified. No source,
native, full SDK, whole Pi or public activation pass is asserted by this unit.
