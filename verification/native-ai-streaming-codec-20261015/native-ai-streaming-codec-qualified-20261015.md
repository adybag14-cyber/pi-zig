# Native AI streaming JSON and OpenAI decoder qualification

Qualified exact candidate: `6cb61bcb6a83b1845a3a7bd6ca5b748c4a26fde9`, private `C:/Users/adyba/pi-zig-ai-compat-b45-20261014`, clean after terminal posthash. Source candidate commit `dc800208548621b766b7e93f36701aa80cc34cff` plus narrow Zig declaration-shadow/span fixes `3817633ba27d8281221ffd00e1d394ca4feb8a90` and qualified head above.

Root granted native slot 1. The strict owned wrapper admitted normal 16GiB, max four coordinated native roots, Debug LLVM, -j1, 1320-second compile, 300-second runtime outer, 120-second test and 10-second host await. It froze all 5449 candidate paths (including vendor/fixtures), all 19546 pinned compiler manifest inputs, and three control files across the serial compile/runtime pair. Every terminal drift count was zero. Wrapper SHA256 `A3CE13F84CCCFF30CCA56AA948058DEE47440597BBB92B2FBBE5F870EE877AEA`. Pinned compiler SHA256 `086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864`.

Compile: `build-native-ai-json-parse -Doptimize=Debug -Duse-llvm=true -j1 --test-timeout 120s --summary all`. Owned Zig PID 45340, created UTC `2026-10-15T16:23:50.8550005Z`, exit 0, terminal UTC `2026-10-15T16:24:05.1501413+00:00`.

Matching runtime: `test-native-ai-json-parse` with identical controls. Owned Zig PID 10088, created UTC `2026-10-15T16:24:18.9793266Z`, exit 0, terminal UTC `2026-10-15T16:24:26.9913402+00:00`. Build summary: 156/156 steps succeeded, 7/7 tests passed. The actual seven-test binary passed native partial streaming fallback against all original 28 JSON inputs, all genuine b06 HTTP20 chunk sequences' decoder terminal results/event fields, and retained final/delegate/scoped-hook/allocation coverage. The generated catalog is not part of this claim.

Terminal posthash SHA256 `A0B2DE01C171E83412C1BB9BEE57EDF6DA54B369DF81F6A176AC771808EB8736`. Machine records and logs use prefix `native-ai-streaming-codec-6cb61bcb-debug-repaired-20261015`.

Preserved negative: exact dc800208 compiler owner PID45656 exited1 for a local declaration shadow. Its candidate/compiler/controls posthash showed zero drift; runtime was not run. The two narrow repairs preceded a fresh freeze and matching successful pair. Records use prefix `native-ai-streaming-codec-dc800208-debug-first-20261015`.

Scope limitations: synchronous decoder validation excludes mutable partial/message/error snapshots from event comparison, while terminal results are exact after assistant clock normalization. This does not qualify full intermediate snapshots, live HTTP decode timing, request construction, payload/response/provider callbacks, transport-error normalization/retries, Kimi native factory composition, other provider codecs, public activation, whole factory/Pi parity, bridge removal or release. The partial parser's native recursion limit is 256. No C changes, paid endpoints, credentials or main-tree edits occurred. Slot 1 was released after terminal success and zero-drift proof.
