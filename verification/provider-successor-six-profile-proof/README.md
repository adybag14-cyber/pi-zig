# Repaired integrated provider components: six-profile qualification

[Run 38806198483](https://github.com/adybag14-cyber/pi-zig/actions/runs/38806198483) is terminal **success** in all six profiles at exact candidate `087858aad7c3425dab083ec2dc0a3dda5f93835f`. The independent online audit passed, followed by a separate offline replay against the retained ZIP bytes.

The complete product tree is identical to published integrated Root head `c629f791976fa117aafd0cc449e2d13971d1bb1c`. The candidate adds exactly two reviewed CI files: `.github/workflows/native-provider-successor-candidate.yml` and `tools/ci/qualify_native_provider_successor.ps1`. The independent verifier checks this whole-tree diff, not just selected source directories.

| Profile | Actually executed selected tests | Outcome |
|---|---:|---|
| Windows Debug | 43 / 43 | Passed |
| Windows ReleaseSafe | 43 / 43 | Passed |
| Windows ReleaseFast | 43 / 43 | Passed |
| Linux Debug | 43 / 43 | Passed |
| Linux ReleaseSafe | 43 / 43 | Passed |
| Linux ReleaseFast | 43 / 43 | Passed |

All **258 selected executions passed**, with zero failed, skipped or unreached selected tests. Each profile comprises 35 substantive tests and eight declaration/import tests: 210 substantive and 48 declaration/import executions across the matrix. Compile-only steps and metadata queries are not counted as tests.

| Selected artifact | Tests per profile | Scope exercised in every profile |
|---|---:|---|
| Headers | 5 | Original Node24 Source189 rows, actual GC/live iterator behavior, native identity/guard helpers and five selected operation allocation offsets |
| Pi messages | 5 | Original Source22: 18 supplied-fetch controls, four owned-loopback default-fetch wire controls, retained functions and the complete host request-owner allocation sweep |
| Responses | 4 | Original Source18 request/callback/event/consumer snapshots and aliases, actual branded Headers and zstd body adaptation, retained graph and complete factory-owner allocation sweep |
| Anthropic functional | 5 | Original Source25 request controls, 22 owned HTTP wire controls, exact request/Bedrock byte observations and pending/retained owner behavior |
| Anthropic allocation | 3 | Both complete measured request and pending-callback host allocation universes |
| Native C generator functional/imported contracts | 19 | Eight generator functional tests, six selected JSON contracts, four stream contracts and one declaration test; intrinsic branding, queues, await, raw errors, realms, GC, targeted VM OOM and retirement |
| Native generator host GPA | 2 | Complete host allocation sweep and the imported declaration test |

Every profile independently measures **226 request-owner** and **162 pending-callback** host allocations, then executes every failure index in the full 0/1 ranges. Baseline, range, ordered begin/complete indices and final complete markers are required, with zero gaps or duplicates. Across six profiles, 2,328 Anthropic host allocation failure indices are covered. The generator GPA test retains its complete standard-library allocation sweep; no exhaustive C-malloc qualification is claimed.

The original failures were retained rather than weakened. The six-profile negative cohort is preserved at `b43b8cd70faf0eab10b0fef00e6aeb67c4c483dc`, two-host failing-index diagnostics at `f9237bd6c06db343b9e16a82be50035f59ad03c6`, and the minimal two-host Debug repair proof at `3bc254f376bd04ffb738c66f8ade51570b022603`. Root integrated the exact minimal callback/Anthropic OOM repairs and unchanged-name complete diagnostics before this successor was frozen.

The final audit verifies:

- All six terminal successful jobs and the exact six artifact names, head and OS/mode identities.
- Every raw ZIP SHA256 against the retained GitHub artifact digest.
- Actual selected executable SHA256 receipts and raw metadata-only Zig 0.16 protocol tags 0/3; string-byte length is parsed before test count, and exact selected names are derived from this candidate's current source.
- Actual test-execution summaries and owned compile/query/runtime identities and exit states.
- All 6,701 candidate input files byte for byte against the exact Git archive, with zero checkout newline conversions, source path/hash drift or compiler path/hash drift.
- All 19,546 compiler-distribution files before/after each profile, plus identical distribution hashes within each OS across the three modes.
- Every complete measured Anthropic allocation range and ordered index on every profile.

The C primitive remains pinned to `vendor/quickjs/quickjs.c` SHA256 `ED1F3A59AD13DE57B32CCA164FC42D347C463632F0B8A1921DC79621E79DE69E` and `quickjs.h` SHA256 `91A39801056D4B4DA6A1B357AD09A20BA61AD3C669D3EEE219F781B4A56ACA28`. Zig remains 0.16.0 with LLVM enabled. Actions are pinned, the repository token is read-only, the push trigger is limited to this checkpoint branch, and at most three profiles run concurrently. No local native build or funded provider request was performed in this lane.

`independent-audit.json` contains every artifact digest, executable hash, exact selected test array and measured allocation receipt. The six raw ZIPs, GitHub run/artifact snapshots and verifier are retained here, so artifact expiry does not remove the retained-byte evidence. With the exact candidate Git object present, repeat the offline audit:

```powershell
python verification/provider-successor-six-profile-proof/audit_successor.py 38806198483 087858aad7c3425dab083ec2dc0a3dda5f93835f . verification/provider-successor-six-profile-proof --offline
```

For a shallow clone, fetch exact candidate `087858aad7c3425dab083ec2dc0a3dda5f93835f` first. Omit `--offline` to refresh GitHub authority responses and download missing ZIPs. Offline mode validates retained snapshots and bytes, not current GitHub state.

**Qualification is limited to these seven selected artifacts on Root `c629f791…`.** Entire integrated Root, all provider families, full factory/application integration, full Pi and public activation remain unqualified. Default Responses WebSocket, Anthropic query/beta, fresh Linux recapture of original Node fixtures and full-engine exhaustive Headers OOM are outside this cohort. Those scope flags do not override separate component proofs. Historical SDK Node runtime metadata remains outside the explicit request-codec comparator; the actual host here is Zig/QuickJS. Root's additional Env/Bash, ordinary-class, catalog and limited Google source intake is not certified merely by being present in this tree. No main merge, release or activation was performed.
