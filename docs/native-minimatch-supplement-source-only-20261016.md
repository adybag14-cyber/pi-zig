This source-only follow-up supersedes the line-break and astral-class rejection
boundaries described by the d849736a packet. It does not supersede its lack of
runtime qualification. No Zig, formatter, AST command, C compiler, Node control,
or native job has run for this follow-up. The current serial lease belongs to
the Models17 work. No C, Engine, shared helper, build graph, or loader
registration changed.

The original 92 inputs, original oracle runner, and original source-only receipt
from d849736a remain byte-for-byte unchanged. New inputs are separate:

- 44 line-break/globstar cases: literal LF, CR, CRLF, LS and PS; nocase; wildcard
  suffixes; UTF16 question-mark lengths; classes, extglobs and braces; escaped
  versus unescaped whitespace; terminal globstar versus zero middle segments.
- 14 astral-class cases: paired and lone-surrogate inputs, separate surrogate
  class members, class ranges, negation, singleton classes, and POSIX classes
  that activate Unicode regex mode.
- 10 peer regression cases: Windows UNC root wildcards, escaped extglob
  operators, sequential extglobs, nested adoption, and original numeric
  precision behavior. This last corpus is original observation input only;
  nested adoption remains unresolved and unsafe integer ranges are explicitly
  outside the candidate's admitted contract.

The supplementary oracle imports the same pinned original minimatch 10.2.6
closure and verifies every source hash from the original packet before running.
It verifies the new case hashes from the supplementary receipt, records Node
and platform identity, captures either a boolean or the original exception name,
and writes evidence only through exclusive file creation. It has not run.
All three supplementary expected files are ABSENT. The new differential tests
require original expected files for the first two corpora and remain outside
the build graph. They do not generate expected values.

The blanket line-break rejection was removed. Literal regex data now follows
the original AST's distinction between broad `regExpEscape` for ordinary
characters and the narrower `reSpecials` set after a backslash. The broad path
includes the ECMAScript whitespace set, including LS/PS, and the literal dash,
comma and hash characters. The escaped path preserves the original handling of
these characters. This distinction also preserves any original RegExp
constructor error when POSIX classes select Unicode mode; the source oracle
captures such errors instead of assuming every valid glob returns a boolean.

String transport in the namespace now uses the existing public linked-C APIs
`JS_ToCStringLenUTF16`, `JS_NewStringUTF16`, and `JS_FreeCStringUTF16`. Internal
text keeps each UTF16 code unit in WTF8 form. Native literal equality, suffix
tests and length checks therefore operate on stable code-unit data, including
lone surrogates, and VM calls reconstruct the same UTF16 string. This avoids
assuming that ordinary UTF8 conversion preserves every string round trip.

Only the class parser was changed to operate on UTF16 units. It also retains
byte offsets so the surrounding glob parser can consume the correct input
slice. Surrogate units in regex classes are emitted as `\uXXXX` data. Endpoint
ordering follows the original `charAt` units, so an astral range is not silently
reinterpreted as a Unicode scalar range. The regex `u` flag remains controlled
by the original POSIX-class requirements. The linked VM executes those class
units and any Unicode-mode surrogate pairing. The receipt records the exact
QuickJS header, implementation and regex source hashes inspected for this work.

The terminal-globstar source change requires a remaining segment, including an
empty segment from a trailing slash: the candidate now distinguishes `a` from
`a/` for `a/**`. Middle globstars can still consume zero segments. Windows
nocase UNC roots now remain literal only under the original no-magic condition;
wildcard servers or shares retain matching behavior. The extglob end scanner
now respects an escaped operator before `(`. Sequential extglobs no longer
consume the nesting counter through their tails, and ordinary path segments
are matched iteratively.

Numeric brace endpoints and steps outside JavaScript's safe-integer interval
now throw `MinimatchRangePrecisionUnsupported`; the candidate does not claim to
reproduce JavaScript Number rounding for those values. Existing explicit
option, nesting, brace expansion and numeric-overflow limits remain. The
original AST's default `maxExtglobRecursion ?? 2`, its adoption/flattening maps,
and malformed grammar are not yet fully reproduced. The peer corpus exposes
those boundaries for a later original control. Globstar recursion/interrupt
limits, allocation failures, class-suffix allocation cost, source prototype
observations, and cross-platform execution also remain unqualified.

Whitespace checks and source JSON parsing are the only validation performed.
The implementation is an uncompiled candidate. Runtime differential results,
all supported platform results, original PackageManager caller assembly, and
full Pi qualification remain absent.
