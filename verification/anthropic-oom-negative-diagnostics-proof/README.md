# Two-host Anthropic allocation failure diagnostics

[Run 38800086916](https://github.com/adybag14-cyber/pi-zig/actions/runs/38800086916) is terminal **failure** on Windows and Linux Debug at exact head `f9ada04e5e9fca034824a996c5df17cea776b31b`. It changes only the reviewed Anthropic test file against original integrated product base `4b6d46d4226c8f49fec120132847c0904786ebbc`, adding diagnostics and the existing strict complete-range helper. No product implementation, original Source golden, test name or allocation universe was relaxed.

Each profile queries the real compiled artifact's exact three-test array, then executes both complete unpartitioned allocation probes and the imported declaration test. Both profiles execute one pass and two failures. The diagnostic failures remain real failures; no complete-universe pass is claimed.

| Probe | Measured baseline | First failing index | Actual failure |
|---|---:|---:|---|
| Request schemas / transcript images / getter exceptions | 227 | 226 | Success after an induced allocation failure: optional exception diagnostic `gpa.dupe` in `Engine.captureValue` catches the OOM and returns normally |
| Pending callback continuation / terminal output | 161 | 153 | `JavaScriptException` survives classification despite native generation 0 to 1; captured error tag is 0 after host allocation failure in `NativeStream.push` during Anthropic decoder failure publication |

For both probes on both hosts, every index before the first failure has an ordered begin/complete marker. The failing index has a begin and diagnostic but no complete marker. The range-complete marker is absent. The pending boundary explicitly reports `raw=JavaScriptException classified=JavaScriptException before=0 after=1 captured_tag=0 diagnostic=none`.

Measured allocated/freed byte counts are equal at both failing indices on both hosts. Linux records 255,298 request bytes and 221,219 pending bytes; Windows records 221,814 and 187,735. This evidence identifies error propagation defects without reporting a measured byte leak.

`independent-diagnostic-audit.json` retains artifact SHA256s, selected executable hashes, measured indices and outcomes. Both ZIPs are retained alongside the GitHub run/artifact snapshots and an independent online/offline verifier. The audit verifies exact candidate Git bytes for all 6,530 source files, zero pre/post source and 19,546-file compiler inventory drift, owned process identities/exit statuses, raw metadata-only Zig 0.16 tags 0/3 and exact names, and actual failed runtime summaries.

With the diagnostic candidate Git object available in the local repository, repeat the retained-byte audit:

```powershell
python verification/anthropic-oom-negative-diagnostics-proof/audit_diagnostic.py . verification/anthropic-oom-negative-diagnostics-proof --offline
```

If using a shallow clone that lacks the diagnostic object, fetch exact commit `f9ada04e5e9fca034824a996c5df17cea776b31b` before performing the offline audit. Omit `--offline` to refresh GitHub authority responses and download missing ZIPs. Offline mode verifies retained snapshots and bytes, and does not claim a fresh GitHub state check.

The separately reviewed minimal repair consists of original commits `9ae7a3bd24442d896516654d699dd3890c9ca31d`, `8485d3525a3e6859bbffac87b596a4238905f02f` and `d4576c7196962e8d434106d4a139430996dc980e`. Their new isolated qualification candidate is `86f5be0f495c776e56fb95f589ee507c019ff0cd`, [run 38802701752](https://github.com/adybag14-cyber/pi-zig/actions/runs/38802701752). This negative diagnostic proof makes no successful-repair claim.

Full factory, full Pi, complete provider cohort and public activation remain unqualified. The original six-profile failure proof at `b43b8cd70faf0eab10b0fef00e6aeb67c4c483dc` is preserved unchanged.
