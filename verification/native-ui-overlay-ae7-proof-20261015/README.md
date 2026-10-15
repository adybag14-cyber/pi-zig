# Native ae7 custom overlay proof checkpoint

This bundle preserves the captured evidence for the saved-overlay-handle close contract in upstream `ae7b16d43b7c78c5b6fa3213fdd1215bb339729d`. It contains original receipt, log, manifest, caller, control and primary Source bytes. The packaging commit adds proof files only; its parent source candidate is `039f31088beaa1f42252bcd6f1df1ac67c5a53f8`.

Run the portable audit from this directory with PowerShell 7 or newer:

```powershell
pwsh -NoProfile -File ./Verify-Proof.ps1
```

The audit reads only this bundle. It requires no original Windows directories, network, Node, Zig, live process, compiler cache or installed test executable. It verifies exact payload hashes, original Source output and method identities, frozen inventory counts, terminal owner identities, captured posthash results, resource admission, retained failures, controls and worker/ConPTY artifact identities. It does not rerun Source or native tests, and does not establish qualification for later product changes.

| Qualified evidence | Source identity | Result |
|---|---|---|
| Genuine `InteractiveMode.prototype.showExtensionCustom` caller capture | Upstream ae7 | 12 scenarios, Node 24.14.0, full Source 1,968 / dependencies 31,064 / Node tools 1,774 posthash drift zero |
| Actual Manager → Controller → Frontend → Application regression | `d04dbecd983c26d277215b7089a969867c49f9c1` | 31/31 tests, compile and runtime passed, all full posthashes zero |
| Actual native worker and ConPTY regression | `039f31088beaa1f42252bcd6f1df1ac67c5a53f8` | 1/1 aggregate test covering regular and fullscreen modes, compile and runtime passed, all full posthashes and three artifact identities unchanged |

The unit candidate and final process candidate differ only in `src/fullscreen_frontend_process_test.zig`. The later fixture gives repeated command invocations unique terminal markers. Production code and the unit fixture are identical across those candidates. `payloads/unit-to-final-paths.txt` preserves that local Git comparison, and `payloads/qualified-code.patch` preserves the complete source delta from base `56d51c4f84867941e2966df98d11ac3af6795394` to the final qualified candidate.

The Source caller retrieves the actual method from its imported prototype. It supplies controlled TUI, editor, factory and handle collaborators; it does not rewrite the Source method body. The original JSON was preserved before creating the expected fixture. The original output SHA256 is `CBC8607F5645ABB7B277F99C9D5A03C0AF46721700576213728CEDA280BDEF50` and the observed method SHA256 is `e47f572a19acf40c8df3c6efaea9bc37ef09514dcfa430a1eba1dd9d399c874d`.

The original scenarios cover three close orders, asynchronous factory readiness, synchronous and asynchronous early completion, factory rejection and throw, disposal failure, raw saved-handle hide failure, normal editor restoration and normal factory rejection. Native comparisons retain Source stack, result-state and disposer-order observations. The terminal regression adds simultaneous middle/lower/top closure, unique repeated-invocation results, and usable editor input after closure, with no Node on the fixture PATH.

All native runs used pinned Zig 0.16.0 SHA256 `086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864`, LLVM, one build job, the normal 16 GiB fresh memory floor, compile timeout 1,320 seconds, runtime owner timeout 300 seconds, per-test timeout 120 seconds and host-await timeout 10 seconds. Frozen manifests cover candidate source 6,323 files, compiler 19,546 files, Source 1,968 files, dependency runtime 31,064 files, Node tools 1,774 files and nine controls for each native pair. The final process artifact record binds `pi.exe` (also the internal native worker), `pi-conpty-launcher.exe` and `pi-terminal-probe.exe`.

The bundle also preserves the superseded unit pass and every failed runtime pair and denied admission from this task:

- The first unit fixture omitted the reserved frontend-owner admission. Its runtime failed at `nativeUi.setEditorText`; the fixture was corrected through the existing public owner API.
- The first actual process test exposed the production Controller singleton: only the lower overlay appeared. The Controller now retains all admitted fences and closes the matching owner.
- The next process test exposed a reused terminal wait marker that could match an earlier transcript notice. Each invocation now has unique readiness and close-result markers.
- A later attempt was denied before native launch when fresh free memory was below the unchanged normal 16 GiB floor. The final passing attempt ran after capacity recovered.

Original payload paths and SHA256 values are listed in `payload-origins.json`. Historical control variants are stored by captured SHA256; missing current variants were recovered byte-for-byte from the local Git object history. Empty stdout files, raw ANSI diagnostics, line endings and EOF boundaries are retained. Original absolute paths inside receipts are historical identity fields and are not required by the offline audit.

This checkpoint qualifies the bounded UI contract above. Full Pi, the full factory path and public activation remain unqualified. NATIVE4 was released after the terminal pass and zero-drift final posthash. No new Source or native job was run while packaging this bundle.
