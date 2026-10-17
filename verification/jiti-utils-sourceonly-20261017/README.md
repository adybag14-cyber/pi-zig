# Actual jiti2.7 utility and consumed yoctocolors unit — source only

Base: Root675252b2bfeb95addfe20dda58755c6687ae83e5. Source: jiti2.7.0,
fd3bb289b75ed207edfb686d671ed50144f7e90f, original utils.ts C0B823DF…C954.
The retained original pnpm lock fixes yoctocolors2.1.2. Its official npm archive
matches that exact locked SHA512 and is retained with complete original package
files and MIT license. No dependency body or Source is executed during authoring.

The new namespace contains only the five assigned actual utility bodies:

| Body | Preserved behavior |
| --- | --- |
| isDir | typeof/string startsWith guard outside catch, actual lstatSync and raw stat.isDirectory() return; ordinary catch false, trusted fatal bypass |
| isWritable | Actual accessSync(filename, captured constants.W_OK), ignored return released; ordinary catch false, trusted fatal bypass |
| readNearestPackageJSON | Actual pathe.join parent traversal before each read, real readFileSync utf8, nested live JSON.parse catch; invalid found JSON stops instead of ascending |
| hash / private FIPS cache | Optional live nodeCrypto.getFips call with crypto receiver, boolean cached once including ordinary catch false; real createHash/update/digest/VM slice chain, default length8 only for undefined |
| debug / static debugMap | Fifteen real color calls at module creation even if debug later disabled; real process.cwd, log callee captured before gray arguments, rest-array live map, actual in/property lookup, JSON.stringify or live replace, iterable spread/join, log receiver and ignored result |

Actual imported FS, pathe, crypto and consumed color namespaces are required
capabilities. No successful filesystem callbacks, parser/SourceLoader alias,
identity color replacement or fake factory supplies them. The utilities are
ordinary constructible length1 functions. The native call wrapper and public
module-creation boundary suppress diagnostics until Source catch/throw behavior
has run. Ordinary caught reasons are transferred/null and freed immediately;
direct OOM, preexisting uncatchable reasons and fresh private native tags escape.
Host traversal, formatting and array-spread advances poll existing cancellation/
interrupt budgets. The namespace-local guard creates the actual interrupted
Error, marks that owned reason uncatchable before capture, and preserves guest
lookalikes. The spread advance retains next/done/value behavior without adding
IteratorClose on an abrupt step. Shared Iterator/Engine/C code is unchanged.
Optional getFips callee/result temporaries retire in a small leaf scope before
the hash chain. Each createHash/update/digest callee is released after its call;
a distinct update result retires after digest, before slice, while the actual
Source const hash local remains rooted through the function return.

native_jiti_colors.zig implements exactly gray/green/blue/yellow/cyan/red consumed
by this Source. It reads the real supplied tty?.WriteStream?.prototype?.hasColors
optional method once with the correct receiver/nullish default. Falsy capability
returns its input unchanged because that is the original body. Truthy capability
executes actual enabled ANSI formatting, live string indexOf/slice and JS +
coercion, including nested close codes and lossless UTF16. Other color exports,
full node:tty and terminal capability installation are not claimed. A real native
TTY namespace is still required for a selected native Node-compatible bootstrap;
passing an invented namespace to force a branch does not qualify that boundary.

native_jiti_crypto.zig is a SEPARATE, unqualified real MD5 primitive/dependency.
It computes MD5 with pinned Zig0.16 std.crypto.hash.Md5, incremental opaque state,
aggregate-charged allocations, finalizer release and hex output. Its SHA256 branch
delegates to the unchanged separately qualified SHA256 leaf. This additional
surface is limited to omitted createHash options, string UTF8 update and hex MD5
digest as consumed by utils.hash; unsupported broader input/encoding/algorithms
fail explicitly. It is not registered as public node:crypto and does not widen
the earlier SHA2566 proof. The compiled native backend has no FIPS provider or
enabled mode, so its real getFips reports0. This is native backend state, not a
claim about Node/OpenSSL, OS certification or an implemented setFips interface.
Required FIPS-provider support would need a separate real backend and gate.

The original caller has29 observations: function shapes, real directory/file/
missing/URL checks, physical access, parent lookup and invalid-JSON stop, actual
hashes including UTF16 edge strings and VM slice arguments, debug-off and real
console boundary, six colors/nested/UTF16 cases and raw-value color coercion.
Four separate fresh-process profiles are prepared: actual-default, controlled
guest colors-enabled, controlled guest getFips true, controlled guest getFips
throw. The latter three mutate methods of genuine imported namespaces before
module loading to reach Source branches; they are NOT physical terminal/FIPS
capability observations. Real createHash and FS execute in every profile.
The Source reference imports the official jiti reference entry and exact original
utils.ts and yoctocolors package. The whole actual dependency graph, strict owned
runner, permissions, pre/post seals and independent absence remain prerequisites.
No Source execution or expected observations exist; jiti-utils-2_7.expected.json
remains absent. No runtime-restoration claim is made.

Prepared native controls are two real MD5 vector/state/GC and exhaustive Zig
allocation tests, two direct native cancellation/quota/no-close controls, plus
three entrypoints requiring actual physical imports and an
independently accepted original caller rows array. Standard MD5/SHA256 vectors
are algorithm regressions, not invented Source goldens. The additive native-only
temporary-retirement control mutates getters on a genuine crypto namespace and
still invokes real MD5 methods; ClearKeptObjects/GC observes optional/callee and
distinct update-result roots at real subsequent callbacks. It asserts no portable
Node GC scheduling oracle and leaves the original29 Source caller unchanged.
It requires a fresh realm: restoration runs only after every probe succeeds;
any ordinary/fatal/host failure goes directly to owner teardown without guest
cleanup that could overwrite its primary reason.
No tests were compiled or
run and no build registration, C/H/Engine/Main or qualified SHA256 source changed.

Other utils.ts exports (interop, wrapModule, normalizeWindowsImportId) remain
with their existing owners. This finite unit neither invents nor replaces those
dependencies. It is not full jiti, full yoctocolors, full node:crypto or a selected
default SDK graph. Physical IO, Source comparison, native GC/GPA/private-fatal
and aggregate quota gates are still required before integration qualification.
