# Graph0 C3 focused two-run proof

The original v1 and v2 execution/control files in this packet are byte-exact originals. This packet is prepared for public retention; packaging is not proof of publication. Original manifests and READMEs describe their earlier prepared/unexecuted status and remain unchanged. Actual run receipts plus independent raw audit establish later results.

V1 exact d2ab9d32dacc0ffb448152818921d93ebd0d57c0 FAILED overall. The queued group reported eight genuine metadata entries, ran all eight with zero flags, and exited0 with empty runtime stderr. Binding compilation then failed because JS_IsAsyncFunction returns bool and the control compared it with integer0. Binding metadata/runtime did not execute. Neither the queued subgroup pass nor v1 compilation of the queued target is a full C3 pass.

The sole successor source correction preserves the ordinary-function assertion by replacing JS_IsAsyncFunction(function)==0 with !JS_IsAsyncFunction(function). Production C/H/binding/Engine were unchanged. Only the two explicitly disposable original compiler caches were reused, with fresh v2 output/receipt paths; all33 protected v1 receipt/output members retain original hashes.

V2 exact8a530f772b734d9a4ff3ffe45e940c6ad5185562 PASSED the focused queued and binding groups. Raw metadata contains eight queued entries (seven named controls plus storage test_0) and three binding entries (two named controls plus storage test_0). Raw runtime streams contain all eleven ordered starts/results with zero flags and empty runtime stderr. These are nine named controls plus TWO executions of the imported storage entry. They are not eleven unique named controls.

IMPORTANT SUMMARY LIMITATION: original v2 result.json has actual_metadata_total:null. It is preserved unchanged. The independent audit derives actual total11 from raw metadata8+3 and confirms execution from raw runtime frames. Null is not treated as zero, an unknown result is not treated as passed, and the original summary is not rewritten to make it appear complete.

V2 queued executable SHA2567BEF1492432D0F63ED2A6B3559C0F8D44DD8D62615CC9C4A511B756FA8A0B738; binding executable SHA25633807BF615DD7D5F7301785208D278C2B5D0AE303C674D5014CACF0E7A5A75DA. Exact C3 C/H are DA14DFBB7E73DED032E9FCD742FD2E49FDAF45273F48D24D6089018539601614 and A79E75A40D34C9E7CAFB9AB31359B7EE925FE205636603F2022CF764CFC18346.

Audit checks complete saved source10658/compiler19546 phase/final seals and original compiler authority, owner identity/deadlines/admissions, raw metadata/results, current executable/PDB hashes and phase inventories, all original owner PIDs absent, and original33 protected members unchanged. Historical v1 and v2 observations remain separate; no older pass is reused as a v2 execution. The original actual_metadata_total:null is explicitly disclosed in the audit.

Scope is focused C3 only. C3 is not accepted into Main by this packet; retained150 regression remains required. No full SDK/default/private Graph2/full application/runtime restoration acceptance is established. Raw jobctx lifetime, inherited ignored enqueue/loader fatal/INIT policies remain the prior explicitly disclosed separate boundaries.

Executable/PDB payloads, compiler payloads, and mutable cache contents are EXCLUDED from this ZIP. Those payloads remain local, identified by artifact receipts, and are not durably stored here. This is not a binary/debugger reproduction claim. Exact tested source/control leaves and complete source/compiler inventories are included. No original history/receipt/fixture is rewritten. No build/test/Node/native job or Main edit is performed by this audit/package.

member-manifest.json inventories every payload by length and SHA256. The archive additionally contains this manifest. All members are decompressed and hashed before package-verification.json is issued.
