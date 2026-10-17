# Prepared actual VM controls and remaining gates

The fourteen named tests are prepared source, not execution receipts:

1. Ordinary compiled module: repeated query and GC do not run its body; scratch
   allocation count is reclaimed; real later evaluation and namespace work.
2. Unreachable syntactic root await differs from await in a nested async function.
3. Actual diamond imports reach a TLA leaf without new loader/body calls.
4. Actual synchronous cycle terminates with false.
5. Actual cycle with unreachable dependency TLA terminates with true.
6. Dynamic import and unrelated context TLA do not become static edges.
7. Real serialized unresolved module and failed partial resolve both fail,
   including a root with TLA; the query never repairs the missing edge.
8. A genuine foreign-context token, wrong tag and NULL output fail; output is
   unchanged and a subsequent healthy local query succeeds.
9. Actual pending ordinary reason is returned with identical ownership/identity.
10. Actual fresh privately tagged host fatal, flagged by the test's trusted host,
    remains exactly that pending reason without new tag/generation.
11. A historical captured flagged error without a current VM exception is ignored.
12. Actual VM scratch-allocation refusal leaves output unchanged and permits reuse.
    Existing OOM may be null; the test does not infer native fatal identity from it.
13. An actual C-module dependency is inspected without running its init callback;
    later actual evaluation runs the callback and root body.
14. With 12001 context modules, the actual existing Engine budget fails after
    scratch allocation during table initialization; subsequent reset/GC/requery
    exercises cleanup and reuse. No synthetic timer or guest callback drives it.

The 12000 extra native modules are real context-owned definitions and intentionally
unreachable from the root. They test context membership cost, not a guessed fake
module-pointer graph. The test uses the existing 10000-step C interrupt cadence
and Engine budget callback, not a new test hook in production.

Remaining gates include independent C ownership/loop review, actual compiler and
metadata, runtime resource admission/protocol, allocation-position accounting,
broader graph sizes/collision distributions, partial graph retry ownership and
future private-module graph composition. There is no test-only setter for
ModuleDef fields, no byte patching, no C struct cast from guest data, no automatic
binding link or module loader fallback, and no added ABI for those tests.

The original Node24 sixteen-row sync ESM caller remains a separate unexecuted
input in the Core source proposal. Its missing/ambiguous export plus TLA cases
are caller-policy gates; these query controls do not establish Node error
precedence. Existing Source captures and earlier C3/C2 native proofs remain
unchanged, with their original exact heads and scope.
