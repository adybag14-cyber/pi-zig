# Anthropic minimal OOM repair: two-host Debug qualification

[Run 38802701752](https://github.com/adybag14-cyber/pi-zig/actions/runs/38802701752) is terminal **success** on Windows and Linux Debug at exact candidate `86f5be0f495c776e56fb95f589ee507c019ff0cd`. The independent online audit and a separate offline replay of the retained ZIP bytes both passed.

Both profiles execute the unchanged five functional target tests, including Source25 request and 22 owned HTTP wire controls, plus all three tests in the exhaustive allocation target. Across the two hosts, all 16 selected executions passed: 12 substantive and four declaration/import executions.

| Complete measured allocation probe | Windows Debug | Linux Debug |
|---|---:|---:|
| Request owner universe | 226 / 226 | 226 / 226 |
| Pending callback owner universe | 162 / 162 | 162 / 162 |
| Missing or duplicate indices | 0 | 0 |

The auditor independently requires both measured baselines, the exact complete 0/1 ranges, every ordered begin and complete index, and each final range-complete marker. These are fresh measurements of the repaired source, not reused counts from the failed 227/161 diagnostic universes.

The exact product base is `b6589631553bf5f5d3218e47b08cef5e277dd04f`; the tested candidate changes only CI files against that base. The three reviewed original repair commits were applied cleanly without extra source intake:

- `9ae7a3bd24442d896516654d699dd3890c9ca31d` → `a379c40f`: preserve raw callback exceptions until the guest catch boundary.
- `8485d3525a3e6859bbffac87b596a4238905f02f` → `c36758ac`: retain fresh private native allocation error identity when Anthropic terminal publication fails.
- `d4576c7196962e8d434106d4a139430996dc980e` → `b6589631`: cover fallback and error-handler continuation retirement.

Against diagnostic head `f9ada04e5e9fca034824a996c5df17cea776b31b`, these repairs change exactly `native_node_function.zig`, `native_ai_anthropic_factory.zig` and the new 21-line `native_node_function_exception_test.zig` (74 additions, five deletions). The new standalone callback regression file has no target in this two-host cohort and is explicitly not claimed as executed. The two original failing exhaustive allocation tests are the regression gates exercised here. Diagnostic commit `7876af33b8a64f1a9671d1e1af76fcc60cf86ea7` is retained in the base, preserving all three allocation-target names and the full measured universe.

`independent-audit.json` records both artifact digests, actual executable SHA256s, raw metadata-only Zig 0.16 tags 0/3, exact selected names, owned process identities and exit states, source/compiler inventory hashes and complete allocation receipts. The two raw ZIPs, GitHub snapshots and portable verifier are retained here. No native product or provider executes during this audit.

With the exact candidate Git object present, repeat the retained-byte audit:

```powershell
python verification/anthropic-oom-fix-two-host-proof/audit_fix.py 38802701752 86f5be0f495c776e56fb95f589ee507c019ff0cd . verification/anthropic-oom-fix-two-host-proof --offline
```

For a shallow clone, fetch exact candidate `86f5be0f495c776e56fb95f589ee507c019ff0cd` before the offline audit. Omit `--offline` to refresh the authority responses and download missing ZIPs. Offline mode validates the retained authority snapshot and bytes, not current GitHub state.

This proves the selected Anthropic repair on two Debug hosts. The full six-profile provider cohort, native C generator hosted gates, full factory, full Pi, default Responses WebSocket behavior, Anthropic query/beta behavior, fresh Linux recapture of original Node fixtures and public activation remain outside this result. No funded provider request was made. The six-profile failure proof (`b43b8cd7`) and two-host negative diagnostics (`f9237bd6`) remain preserved unchanged.
