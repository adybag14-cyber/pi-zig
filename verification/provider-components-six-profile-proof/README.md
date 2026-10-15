# Native provider checkpoint: terminal failed cohort

The overall provider cohort is **not qualified**. All six jobs of [run 38797102262](https://github.com/adybag14-cyber/pi-zig/actions/runs/38797102262) reached terminal failure at exact CI head `373ae068491053eeeb1743baa0a09cd16e842262`. Its product source, vendor files, build definitions and goldens are unchanged from integrated Root head `4b6d46d4226c8f49fec120132847c0904786ebbc`; the candidate adds only two CI files.

The matrix is Windows and Linux, each in Debug, ReleaseSafe and ReleaseFast, with Zig 0.16.0. The workflow uses pinned actions, read-only repository token permissions, its exact checkpoint branch trigger, and at most three concurrent profiles. No funded provider request was made.

| Selected component target | Tests per profile | Passed profiles | Failed profiles | Not reached |
|---|---:|---:|---:|---:|
| Headers189 and selected operation allocation failures | 5 | 6 | 0 | 0 |
| Pi messages Source22 and complete host ownership sweep | 5 | 6 | 0 | 0 |
| Responses Source18 and complete factory ownership sweep | 4 | 6 | 0 | 0 |
| Anthropic Source25 request / 22 owned HTTP wire controls and retained owner tests | 5 | 6 | 0 | 0 |
| Anthropic exhaustive request and pending callback ownership sweeps | 3 | 0 | 6 | 0 |
| Native C generator functional / selected JSON and stream contracts | 19 | 0 | 0 | 6 |
| Native generator complete host allocation sweep | 2 | 0 | 0 | 6 |

There were 43 planned selected tests per profile: 35 substantive tests and eight declaration/import tests. Each profile executed 22 selected tests before the Anthropic allocation gate failed. Across six profiles, 132 selected tests executed: 120 passed and 12 failed; 126 planned generator executions were not reached. These counts include the declaration tests. The generator targets have no hosted qualification from this cohort.

Both named Anthropic allocation tests failed in every profile. Debug logs expose `SwallowedOutOfMemoryError` in the request-owner sweep and an unclassified `JavaScriptException` in the pending callback sweep. Optimized runners report the same named test failures without the Debug error detail. Separate diagnostic checkpoint `f9ada04e5e9fca034824a996c5df17cea776b31b`, [run 38800086916](https://github.com/adybag14-cyber/pi-zig/actions/runs/38800086916), retains the complete 0/1 allocation universe and adds exact failing-index and boundary diagnostics; it is separate from this frozen cohort.

The independent audit verifies all six terminal job states and raw ZIP digests against GitHub's artifact index. It then checks every selected executable's SHA256 receipt and the raw metadata-only Zig 0.16 protocol (`query_test_metadata=4`, server tags 0/3, string-byte length before test count), exact selected names, actual runtime summaries, owned process identities and exit statuses, and complete source/tool inventories before and after execution. Every hosted source file matches the exact candidate Git archive; no source/compiler path or hash drift was found.

`independent-audit.json` contains each profile's artifact ID/digest, executable hashes, selected names and scoped outcome. `artifacts.json` and `run.json` retain the authority responses. The six raw ZIPs are retained here so the verifier remains usable after GitHub's artifact expiry. No native product executes during this audit.

To repeat the retained-byte audit from this repository clone:

```powershell
python verification/provider-components-six-profile-proof/audit_provider_ci.py 38797102262 373ae068491053eeeb1743baa0a09cd16e842262 . verification/provider-components-six-profile-proof --expect-failure --offline
```

Without `--offline`, the verifier refreshes the GitHub authority responses and downloads any missing archives. Without `--expect-failure`, it requires a successful cohort and rejects this failed run. Offline mode audits the retained authority snapshot and ZIP bytes; it does not claim a fresh GitHub state check.

Full factory integration, full Pi, public activation, default Responses WebSocket behavior, Anthropic query/beta behavior, fresh Linux recapture of the original Node fixtures, and full-engine exhaustive Headers OOM qualification remain false or outside this cohort. Responses runtime metadata follows the existing explicit comparator boundary: the actual host is Zig/QuickJS, while historical Node SDK runtime metadata is excluded. Existing Source goldens and semantic assertions were preserved.
