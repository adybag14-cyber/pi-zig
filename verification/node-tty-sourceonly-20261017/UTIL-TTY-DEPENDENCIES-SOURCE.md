# Actual utility dependency for TTY errors

This separate unit follows frozen factory 642cc78c and its reviewed-finding
successors. It is authored source only, unselected, uncompiled and unexecuted.
There is no accepted original capture, native comparison, expected packet or
whole-util qualification. No Main, C, header, Engine, old proof or protected
Source20/14 file was changed.

Official Node v24.14.0 `lib/util.js`, `lib/internal/util.js`, `src/uv.cc` and
the previously retained `lib/internal/util/inspect.js` define the algorithms.
The Node license retained beside them applies. `UV_ERRNO_MAP` and the Windows
numeric branches of `uv/errno.h` define the name map. A read-only regular
expression inventory compared all 85 authored entries against all 85 source
map entries: zero missing, extra or numeric drift. This is a source inventory,
not a runtime test or a source generator.

`native_node_util_error_name` implements validateNumber without coercion, then
the negative safe-integer condition using the actual registered error
constructors. NaN, infinities, fractions, nonnumbers and negative zero follow
those two separate checks. The internal lookup uses the original numeric key;
a negative safe integer outside int32 never wraps to a known errno. Unknown
negative values use the actual `Unknown system error ${err}` algorithm. The
current map is Windows; other platforms remain explicit dependencies.

`native_node_util_inspect_primitive` ports quote delimiter selection, C0/C1 and
unpaired surrogate escaping, UTF16 truncation, multiline string formatting,
numeric -0 and numeric-separator algorithms, and BigInt suffixes. Its string
map completes stylize calls before join coercions; it preserves the Source
exponential-number separator behavior instead of normalizing intended output.
This is separate from the event diagnostic formatter, whose proxy, custom
inspection and C1 behavior do not provide this authority.

`native_node_util_inspect` retains genuine bootstrap primordials, Source
well-known prototype records and the Source global built-in-name set. Snapshot
capture must happen before guest code. The no-color stylizer has one module
identity. Each inspection reads the same sealed mutable defaultOptions object,
applies recognized options in Object.keys order and retains unknown user
options for the actual custom-inspect spread.

Native QuickJS proxy metadata supplies the target without guest get/ownKeys/
prototype traps. Revoked proxy rendering is separate. Custom inspection reads
the actual symbol method before raw properties, checks the own constructor
prototype exclusion, passes the original receiver, actual remaining depth,
user options and the genuine inspect function. Cross-proxy/null-prototype
options lose their prototype and nonprimitive fields and get the Source
no-prototype stylize wrapper. Hook returns and exact ordinary thrown reasons
are preserved. Source catches retain fresh allocation and uncatchable errors;
handled ordinary captures are consumed before continuing.

The raw paths currently cover ordinary and null-prototype objects, descriptor
labels without evaluating getters, Source constructor/name lookup, small dense
arrays and ordinary/generator/async function labels without enumerable own
properties. Default compact layout has the Source length threshold and
multiline indentation. The static fd-error format profile performs the real
hasBuiltInToString decision, including its live getters and property-presence
checks, then String conversion or depth-0 inspection. It is not a prebuilt
error string or an event-formatter alias.

The admitted implementation does not silently format an unported case:
exotic collections/boxed objects, full class display, circular references,
array extras/sparsity/grouping, showHidden/showProxy layouts, color styling,
custom mutable stylize contexts, symbol property escaping, nondefault compact
and coercible layout options, complex prototype fallback, function own props
or object-valued function names, sorted output and evaluated-getter displays
retain explicit native capability errors. General public format specifiers
besides the actual static fd registration are also outside this unit. These
boundaries keep public activation off; they must not be relabeled successful
Source parity or replaced with canned output.

Concrete composition order is:

1. Capture genuine inspect and color primordials before guest code.
2. Create the private inspect export record with createPrivateInspect.
3. Create actual TTY message functions with that private record, then the
   actual TTY error constructors and shared SystemError registry.
4. installRequired on the real public util carrier with those constructors.
   It installs genuine inspect/format function copies and getSystemErrorName.
   Private and public carriers must differ so public property replacement does
   not rewrite internal/errors' private module properties.
5. Publish/cache the real util carrier through Root's module assembler, then
   pass actual require and the same error constructors to the TTY factory.

The install helper does not advertise unrelated util APIs, register a fake
namespace or manufacture a second require. Root must cache each module once
and preserve constructor/function identity across import forms.

`original-util-error-paths.mjs` contains actual Node API inputs for later
capture: safe-integer boundaries and unknown errno wrapping; primitive and C1/
surrogate formatting; real fd coercion, custom-inspect receiver/options/third
argument identity; proxy trap traces and revoked proxy; descriptor getters;
custom hook throw identity; string-hint conversion; and public util property
mutation versus the private internal module. All controls are prepared/unrun.

Before selection, independent source review must close this finite unit, then
Root must separately authorize actual reference and native captures. Native
host controls must exercise a pending ordinary event at direct factory entry,
fresh allocation and preexisting uncatchable errors at caught boundaries,
root-allocation failure after a custom hook returns with a pending event,
exact once disposal of descriptor fields, and GPA/module retirement. None of
those controls has been executed here.
