# Actual patched script compilation basis

native_node_commonjs_script implements the real linked VM script compile/run
path required after a patched live Module.wrap returns its script. prepare uses
actual JS_Eval2 GLOBAL|COMPILE_ONLY with the supplied physical filename and line
one. run uses actual JS_EvalFunction and returns its owned raw result, including
the same Promise value. Compilation never runs the script. A script can return
an arbitrary real VM function; its CJS body is executed later by the caller.

The leaf owns only the actual compiled bytecode value. VM string conversions and
bytecode/filename atoms are handled through existing charged VM allocation, not
uncharged copied host buffers. The host keeps Engine/context alive through
Prepared.deinit. Incoming pending failures are captured before parsing; success
with pending failure owns that actual reason before result cleanup. Existing
fresh private classification is used without a new tag or shared helper change.

This is not the unpatched Node CJS compiler. Arbitrary script execution is
intentional only for the patched Module.wrap result. It must not be used to
validate a concatenated untrusted CJS function body. Nonprimitive internal inputs
and NUL-containing filename origins are explicit unsupported boundaries rather
than coercions/truncated filenames or claimed Node-compatible diagnostics.

No fake canParseAsESM, sourceURL/sourceMapURL or cachedDataRejected result is
returned. The missing real function-body compile, parse-only ESM diagnostic and
Node comment/cache metadata primitives are described separately. The complete
wrapSafe adapter and default bootstrap are unselected until those exist.

Four prepared direct native controls use real VM compilation/run and arbitrary
body grammar, this/parameters/return, physical syntax-error origin, no execution
before compilation, raw Promise and raw throw identity. They remain uncompiled
and unrun; no runtime metadata count or full Node/V8 equivalence is claimed.
