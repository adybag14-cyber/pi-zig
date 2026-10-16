# Actual raw binding test composition, source-only

Root assigned independent source review of SDK checkpoint
0d546939997f916e597183395d450be598f0950d. Review closed with no blocker before
this permitted isolated preparation. The exact 19-line binding and its two
prepared entrypoints are copied byte-for-byte; no SDK assembler, Engine or vendor
file is copied. This tree supplies its already reviewed DA14/A79 vendor source,
which has not been compiled or qualified. SDK's original isolated tree still
has its explicitly unavailable-symbol admission boundary.

The seven queued-import controls now install the actual ordinary binding rather
than a local test forwarding function. Their deliberate direct C calls remain:
the absent-frame input-owner/GC control and foreign-context execution-marker
control exercise the ABI itself. All other bound calls use the actual SDK leaf.
Two additional thin test roots invoke the owner's prepared entrypoints with an
actual registered TLA source module and invalid-base JS input, respectively.
No substitute importer, namespace, Promise or production host implementation is
introduced. Test source executes only through the linked C VM.

The exact binding factory uses JS_NewCFunction with JS_CFUNC_generic, producing
ordinary name importModule, length 2 and no constructor flag. The callback has
no Engine capture or host record. It forwards borrowed arguments (missing
arguments become undefined; receiver and additional arguments are ignored) and
returns the C API's owned Promise or JS_EXCEPTION directly. It does not inspect
or capture a pending reason, add adoption, perform coercion, or infer a fatal
from data. The manual extern C signature is ABI-identical to the reviewed
JSValueConst-by-value header declaration.

The prospective build snippets remain unselected. There are seven plus two
named source test declarations; actual compiler metadata and any imported
anonymous entries must be observed under Root's later grant. Neither these
unrun controls nor the source review qualify current inherited dynamic-import
enqueue, loader, INIT or allocation-fatal policies. Actual SDK cached-selector
identity, complete jiti/virtual authorities, and Graph2 caller isolation remain
their separate integration gates. Default selection and assembler are untouched.

Only git diff --check and read-only source/hash checks were performed. No Zig,
formatter/AST, native test, Node reference, generator or main edit occurred.
