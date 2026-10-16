# Prepared executable outer launcher — unexecuted

`Run-Latest4ddSerialCapture.ps1` is the executable outer controller for the canonical273-record plan. Run it only as a separate owned, hidden, noninteractive PowerShell process after explicit Root review and admission. Calling it in a persistent interactive shell prevents the subsequent external outer-absence check from succeeding. The source dependency junction must already exist with the exact frozen target; the launcher does not edit Source, runtime, candidate or parent environment.

The mandatory arguments are an exact clean `CandidateHead`, a fresh alphanumeric/hyphen `RunId`, and a Root-created metadata-only JSON `RootGrant`. No default grant exists. The initial grant schema is:

```json
{
  "authorized": true,
  "manual_fresh_16gib": true,
  "run_id": "ROOT-SELECTED-FRESH-ID",
  "candidate_head": "EXACT-SEALED-40-HEX-HEAD",
  "launcher_sha256": "EXACT-SEALED-LAUNCHER-SHA256",
  "issued_utc": "ROOT-CURRENT-UTC",
  "expires_utc": "ROOT-NEAR-FUTURE-UTC",
  "grant_id": "ROOT-EXPLICIT-REVIEW-GRANT"
}
```

The two authorization fields must be JSON booleans, not truthy strings. The grant must match this exact run/head/launcher, have been issued within300s, and remain unexpired when the launcher starts. Unknown grant fields are rejected. The launcher records the initial automatic fresh16GiB admission and refuses an existing run directory. It copies the retained96BE owner byte-for-byte into its new owned run directory, keeping its normal stdout/stderr/identity records there.

Before each of the four Source probes and before acceptance, the outer owner writes `admission/<kind>.request.json` with a fresh nonce, reports the exact response path, and pauses for at most120s. Root must create the matching `<kind>.approval.json` **after** this request, with `approved: true`, and matching `nonce`, `kind`, `run_id` and `candidate_head`. Preexisting, missing or mismatched approval is a negative. Immediately after approval the controller automatically queries fresh free RAM; less than16GiB denies the Node child and preserves the reservation record. Each child reserves2GiB with256MiB heap. These are SourceLite reservations; overlap with C9 still requires the explicit Root grant and does not change any native memory gate.

The outer hard budget is5700s:

| Slot | Maximum |
| --- | ---: |
| Four retained Node owners | 4 ×(300s execution +10s settlement) =1240s |
| Full before, four full between and full final checks | 6 ×600s =3600s |
| Four probe admissions plus acceptance | 5 ×120s =600s |
| Artifact sealing worker | 120s |
| Bounded process setup, monitoring, pipes and settlement overhead | 140s |

Each Node phase worker allows320s around the unchanged300s+10s retained Node owner; the additional10s per worker is charged to controller overhead, not a relaxed Node execution deadline. Normal phase admission reserves800s for the final full check, artifact sealing and cleanup, so exhaustion fails before starting another probe. Hashing runs in individually bounded PowerShell workers. After the first negative, no further Source probe starts; the controller still attempts the matching full final check, independent descendant absence and artifact retention. The full before manifest is emitted before drift acceptance so a negative before check can still have a matching final check. If no initial manifest could be produced, a final fresh census is explicitly marked unmatched and cannot qualify.

Every phase worker starts with `ProcessStartInfo.Environment.Clear()`. The complete explicit allowlist is Windows `SystemRoot/WINDIR/ComSpec/PATH`; owned `TEMP/TMP/HOME/USERPROFILE/HOMEDRIVE/HOMEPATH/APPDATA/LOCALAPPDATA/PI_CODING_AGENT_DIR`; and the color/PowerShell startup controls. Node adds only the exact control manifest, capture kind and owned record-directory variables. PowerShell's generated `PSModulePath` is permitted by the Node environment assertion. No credential environment value is read, copied or logged. All `OPENAI_`, `AZURE_OPENAI_`, other provider credentials, proxy variables, `NODE_OPTIONS`, `NODE_PATH`, `NODE_COMPILE_CACHE` and `PI_PACKAGE_DIR` are absent because the inherited environment is discarded. Environment proof records names and assertions only. Profile, temp and agent directories are private to this new run.

Node uses its native v24.14 permission model: reads cover the frozen candidate, Source, immutable runtime root and owned run (the runtime-root read grants realpath metadata; the loader still rejects every old Source file outside node_modules); fs writes cover the owned run only. Child processes, worker threads, addons, WASI and inspector are not granted. The capture control preload denies unexpected HTTP/HTTPS/net/TLS/datagram/DNS/fetch/WebSocket activity and records API names without arguments or URLs. Any attempted network call makes terminal status negative even if Source catches the throw. It supplies no fake response and does not replace a selected Source converter/summary function. The permission model is a guard for this trusted frozen corpus, not a claim to sandbox malicious code. Its exact resource scope and limitations were checked against [the official Node v24.14 permission documentation](https://github.com/nodejs/node/blob/v24.14.0/doc/api/permissions.md).

The outer owner tracks exact phase roots and observed descendants by PID, executable, creation time and command line. Reused PIDs are preserved. Timeout cleanup revalidates each individual owned identity and permits only the frozen PowerShell/Node/Git executables; there is no process-name/tree kill or authority over C9/Codex. Unexpected survivors produce a cleanup negative. The final retained packet includes raw outputs, all273 ordered caller IDs and observations, actual script/input SHA256, module logs, closure/network/environment receipts, original negatives, full hash records, reservation/approval files and artifact hashes. Root request/approval/reservation files and completed raw captures are frozen and rechecked during final artifact sealing.

The outer process cannot prove its own absence while alive. Its terminal record therefore requires the external supervisor to execute `Confirm-Latest4ddOuterAbsent.ps1 -RunDirectory <exact-owned-run>` after outer termination. That helper independently checks the exact outer identity and all observed descendant identities, preserves PID reuse, and emits a distinct handoff receipt. Source expected files remain absent. Even a positive raw273 terminal remains **pending Root expected review**; no launcher code creates or publishes an expected fixture.

Preparation validation is PowerShell parser-only and Git whitespace checks. No launcher, phase worker, Node, Source capture, Zig or native process has been executed for this packet.
