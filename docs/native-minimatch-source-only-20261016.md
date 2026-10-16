The minimatch component is a source-only candidate for the latest Pi
PackageManager dependency. It has not been compiled, formatted by Zig, run, or
registered as the public `minimatch` package. The active 718fb highlighter lease
prohibits Zig, C, Node, and native jobs while this packet is prepared.

The authority is Pi source commit
`4dd2b149d155d7369de16ea4dc77c84e9f5ffb24`. PackageManager imports the named
`minimatch` function and calls it with two arguments at lines 680–690: relative
file path, basename, absolute path, and corresponding parent paths for SKILL.md.
Those paths are already normalized to POSIX separators by the actual caller.
The model resolver additionally calls the same export with `{ nocase: true }`
at lines 374–375. Installed original dependencies are minimatch 10.2.6,
brace-expansion 5.0.12, and balanced-match 4.0.4. The verification JSON records
the exact original source hashes and baseline native commit.

`native_minimatch.zig` owns brace lists and numeric/alphabetic ranges, segment
wildcards and classes, POSIX character classes, nested extglobs, pattern
negation/comments, basic parent-pattern optimization, slash splitting, globstar
traversal, trailing-slash handling, and Windows drive/UNC matching. It compiles
glob segments to regex data in Zig. `native_minimatch_namespace.zig` creates
only the named function required by these callers. It invokes the directly
linked QuickJS-NG RegExp primitive through C for regex execution and Unicode
case handling. It also uses linked string primitives for the original fast
matching paths. It does not evaluate generated JS or load the JS minimatch
implementation. Literal segments use exact native string equality.

Only the default options and an own data `nocase` property are admitted by the
namespace. Other own option keys, symbols, and accessors return explicit errors.
Inherited/proxy options remain outside the qualified caller contract. This is a caller component,
not a replacement for the full package API: Minimatch/AST classes, makeRe,
filter, match, escape/unescape, defaults, exported symbols, and extension-owned
option combinations are outside this candidate. Loader registration must not
advertise those missing APIs.

Known explicit limits are brace/extglob nesting above 64, brace rewrite and
expansion resource limits, astral or ill-formed Unicode bracket endpoints, and
non-object option values. The original brace library can truncate some resource
limits; the candidate instead throws `MinimatchExpansionLimitUnsupported` when
the Cartesian product exceeds its limit. This difference must remain explicit.
Numeric brace endpoints or steps outside signed 64-bit range throw
`MinimatchRangeOverflow`. Allocation and recursion behavior under adversarial
input is unqualified. Patterns containing line breaks throw
`MinimatchPatternLineBreakUnsupported`. Test paths can contain line breaks.
Lone surrogate strings, observable option
prototypes/getters, malformed brace/extglob/class combinations, and VM RegExp
prototype mutations need further review.
The candidate must not be described as full minimatch equivalence or full Pi
qualification before those boundaries are resolved or explicitly admitted.

The 92 source control inputs cover defaults and nocase, basename/slash behavior,
dot files and traversal, nested and zero-length globstars, trailing slashes,
brace escaping and malformed brace rewrites, numeric and alphabetic ranges,
classes and Unicode POSIX classes, extglob repetition and negated suffixes,
pattern negation, Windows drives/UNC, and model ID/provider patterns. The
original dependency runner imports the pinned original package; the native
implementation cannot create expected evidence. It records the source hashes,
Node version, and platform. Its output file uses exclusive creation.

`src/extensions/fixtures/minimatch-10.2.6.expected.json` is intentionally ABSENT.
The differential test requires this file and fails if it is missing. Neither
the original oracle nor the native test has run. The test is not added to the
shared build graph in this source-only change. After the parent grants a runtime
lease, generate expected output with the original runner on the same platform,
review all source identities, register the test, and resolve every differential
failure. Repeat on the supported hosted platforms. Actual PackageManager caller
assembly and original caller controls remain a separate gate owned by the
upstream refresh work; the dependency controls do not prove that assembly.

The brace and class behavior was developed by reading the pinned original
sources. Their license notices are preserved in
`vendor/minimatch-contract-licenses`. Existing runtime and hosted proof packets
are unchanged. No process was started or stopped, and no publication or
activation occurred.
