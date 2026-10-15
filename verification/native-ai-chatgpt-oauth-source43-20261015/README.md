# Genuine ChatGPT OAuth Source43 receipt packet

This packet preserves the successful original capture against immutable Pi Source `ae7b16d43b7c78c5b6fa3213fdd1215bb339729d`. It was retained afterward without rerunning Source or native tests and without changing product files.

- Original Node `v24.14.0` child PID: `69972`; created `2026-10-15T20:13:08.3855957Z`; exited `0` at `2026-10-15T20:13:28.7231912+00:00`.
- Original full posthash completed `2026-10-15T20:13:44.9060512+00:00`: all `1968` Source, `31064` runtime and `1774` Node files had zero drift. All `84` historical absences, extra controls and the caller control manifest were unchanged.
- The capture contains `43` observations and `20` fake fetch requests. No real user authentication, token endpoint request, credential read or browser launch occurred.
- After an existing-listener check and owned bind probe, the Source caller observed six actual `Server` handles on `127.0.0.1:1455`, each owned by child PID `69972`. The caller required all six to close. No unrelated listener was touched.
- The retained output and committed expected fixture are byte-identical: SHA-256 `61B2B03DADA222EF369EF20C901E64BFF7A17C5238E1E434FC7922FDF623DE24`.

Original receipts, stdout/stderr, the module observer log, exact caller/owner/wrapper controls, preparation controls and readiness, dependency audit, input and output are retained as bytes. The four actually observed Source module bodies are in `original-source/`. The three original frozen manifests are in `original-frozen-manifests.zip`; all three ZIP entries were independently rehashed against their frozen originals during retention.

`packet-sha256.json` identifies each retained payload, its byte count, hash and original path. `retention-verification.json` records the retrospective receipt checks. Its retained-file count describes the original receipt payload at verification time, before this README and retention-tool copy were added. The retained wrapper is historical evidence tied to its original absolute paths; copying this packet does not authorize or make a new Source run portable.

This packet qualifies the original Source capture only. Native compilation, native OAuth execution, full Pi qualification and public activation are not asserted by these receipts.
