# Private SDK consumed Chalk6 supplier — source only

The real ResourceLoader warning path reads `chalk.yellow` and calls it with the
Chalk receiver. The SDK assembler already accepts `chalk_default` unchanged.
No real Chalk default provider was found in `native_theme.zig` or the retained
terminal-theme, theme-components and theme-constructor worktrees. Those theme
helpers implement modifier rendering for a different API.

This checkpoint supplies the consumed native dependency through
`extensions/native_sdk_chalk.zig.createDefault(engine)`. Call it after the real
platform bootstrap installs `node:process` and `node:os`, retain the returned
owned `JSValue` for the assembler invocation, and pass it as `chalk_default`.
The same Engine returns the same cached callable. The private cache key does not
register an importable `chalk` module or a global variable. Product consumer and
resource assembly files are unchanged.

The implemented surface consists of the default rest-argument callable, lazy
`yellow` builders including yellow chaining, and root/builder level accessors.
It uses actual VM calls, properties, symbols, coercions and exceptions. Enabled
yellow applies ESC[33m/ESC[39m, reopens embedded closing codes and closes/reopens
at LF/CRLF. Disabling color preserves the original argument-coercion boundary.
The style cache descriptor, generator symbol level and live public builder level
are distinct as in the primary source. This is not a complete Chalk namespace:
other color/modifier/model styles, named exports, `visible` and stderr Chalk
callables are outside the ResourceLoader dependency scope.

Color initialization ports the installed Chalk6 vendored detector and evaluates
its stdout and stderr decisions in order. It reads the actual installed native
process/environment/argv and OS provider. Its private TTY input queries real
stdio descriptors 1 and 2 using `_get_osfhandle` plus `GetConsoleMode` on Windows
and `isatty` on POSIX; it changes no console mode and creates no `node:tty` shim.
The Windows implementation therefore requires the normal CRT and kernel32 links
already used by the executable. The installed source's disable flags,
`FORCE_COLOR` exact/boolean behavior and non-TTY policy are preserved. The
installed Chalk6 detector does not inspect `NO_COLOR`; the authored policy inputs
make that fact observable rather than silently adding a new policy.

Primary authority is the six original-manifest-exact Chalk6 files listed in
`primary-provenance.json`, plus the official Pi4dd ResourceLoader consumer.
They belong to the restored original31064 current-byte reference accepted by
EFEC9629751FA119BE0B311D206A7F8A10A5A9E31213482FBBF647C6B6C11CF0.
This authority is separate from the preserved negative recovery lifecycle.
The exact upstream MIT license is retained in `LICENSE-chalk6.txt`.

`chalk-consumed-callers.mjs` and the native embedded input are byte identical.
The authored corpus plans 86 observations over ANSI/no-color, zero/single/two/
many arguments, nested yellow, LF/CRLF, existing escapes, UTF16, live levels,
descriptors, four option getter reads, raw throws and live String methods.
`capture-primary.mjs` imports the actual installed Chalk default after checking
the resolver's accepted byte authority and the six exact primary hashes.
`color-policy-callers.mjs` contains 22 environment/argv inputs, each requiring a
separate fresh owned Node process for module initialization. They are inputs,
not expected outputs. No expected Source JSON has been authored.

`src/native_sdk_chalk_test.zig` is the standalone native root. The extension
control checks native identity, real ANSI/no-color, raw thrown values, option
evaluation, cache descriptors and GC retention. `build-snippet.zig.txt` prepares
canonical install/run registration without editing the shared build file.
Actual compiled metadata is unknown; the source contains one named semantic
test and a root import test. No compilation, formatting/AST command, Node run,
source capture or native test has run. Static source and Git whitespace checks
do not establish functional parity or whole SDK qualification.

Any future genuine capture needs Root's separate exact-head ownership/resource
grant, bounded owner and process absence, fresh 16GiB admission, sealed complete
original runtime/Node/control inventories, cleared fixture-only environment and
network denial. The false config template is not an execution grant. Complete
Source/native observation equality remains a later gate; the native semantic
control alone does not claim that comparison.
