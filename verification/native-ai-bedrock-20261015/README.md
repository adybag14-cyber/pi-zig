# Private native Bedrock facade candidate

`native_ai_bedrock_factory.create(engine)` constructs actual native JS functions
`stream(model, TranscriptContext, options)` and `streamSimple(...)`, each arity 3.
The implementation retains its model, context, options, output, decoder buffers,
callbacks and promise continuations in GC-visible JS owner graphs. The HTTP
worker receives copied bytes and performs optional native credential/signature
preparation; it never receives a guest callback or JS value.

The request builder comes from the separately owned native Bedrock codec work.
The facade does not alias Anthropic or OpenAI provider execution. Binary AWS
EventStream framing, CRC validation, SDK event ordering, redacted blob decoding,
awaited provider hooks, output blocks, metadata and failure diagnostics have their
own native implementations. The signature adapter signs the finalized payload
and eligible custom headers with AWS path escaping and signed-header ordering.

## Genuine Source evidence

The retained Source is immutable
`5ab7fe74c400097b386662205cd93900695b8a71`. The driver imports its actual
`packages/ai/src/api/bedrock-converse-stream.ts` and installed actual AWS SDK;
there is no provider-source replacement or SDK mock. Each of 14 cases sends a
request to a separate owned `127.0.0.1` HTTP server, authenticated with the literal
fake bearer token `fixture-placeholder-bearer`. The server supplies real binary
EventStream frames or a real HTTP error body. Child-only environment overrides
clear ambient AWS credentials/profile/token/file/container/web-identity inputs
and proxies, and disable IMDS. No real credential or paid endpoint is used.

The fourth capture was already started before Root directed that a verifier-only
audit would suffice for the third capture. It completed normally and is the
retained fixture. Node PID 36552, native Node 24.14.0, exited 0; its identity is in
the owned job receipt. The strict wrapper completed 14 observations and 14 HTTP
requests. Full posthash drift is zero for all 1,967 Source files, 31,064 dependency
files, 1,774 Node/tool files, extra controls/control manifest and 84 historical
absence records. The copied output fixture SHA256 is
`C53E30358BA4414FF692EE45557EC2DDCCC546AC92B66A4244BAD62E76566545`.

The earlier external evidence receipts remain intact. The first failed a Windows
ESM import URL before provider execution; the second was an actual negative SDK
token-selection observation with no HTTP request; the third produced genuine
Source observations with terminal Node success and posthash zero but had a final
wrapper verifier typo. These states are distinct from the accepted fourth run.

The 14 observations cover text/usage, signed thinking, encrypted reasoning bytes,
tool deltas and invalid final arguments, finalization of an unstopped block,
missing/unknown stop reasons, SDK stream exceptions, awaited payload replacement,
response callback rejection, provider callback mutation/rejection and a malformed
HTTP 403 body. The native comparison normalizes only clocks/durations and the
binary blob representation already normalized by the Source capture; expected
assistant outputs and callbacks come from the genuine capture.

## Gates and current limits

Native build/run targets: `build-native-ai-bedrock` and `test-native-ai-bedrock`.
The suite compares all 14 genuine request bodies, callback traces, event traces
and terminal results through the actual facade and owned native loopback server.
It also includes an independent cancellation check for a private credential
subprocess. Zig 0.16 formatting and AST checks have run; native compilation and
runtime were run on frozen cc3858c7: compile passed, runtime failed two of four
tests, and terminal posthash drift was zero. The source-only repair fork requires
a fresh native gate; the protocol timing negative awaits reviewed C-generator
integration as detailed below.

The credential chain currently includes static credentials, selected shared
profiles, credential processes, STS role chaining, web identity, ECS/EKS and IMDS.
Every credential result owns its bytes; expiration is checked on fresh request
resolution. HTTP credential requests share cooperative cancellation and request
deadline. Credential subprocess cancellation uses `std.Io.Select` and the exact
owned `std.process.Child` cleanup, and drains and clears racing process outputs.
SSO/token-provider refresh parity is not implemented or qualified. Default SDK
auth-scheme selection and broader SDK serialization behavior remain outside the
14-case evidence. There is no claim of full AWS SDK equivalence.

`native_bedrock_facade_qualified=false`, `full_pi_factory_qualified=false`,
`public_activation=false`. This candidate has not been activated or published.

## First native pair: retained negative

The frozen `cc3858c7042e87373b6f2be1eac6ae3547100470` pair compiled successfully
under owned Zig PID 65908 and then failed runtime under PID 46836: two of four
tests passed. Terminal posthash drift was zero across candidate 6,115, vendor
1,316, compiler 19,546 and five controls. Exact receipts, logs, prehash inventories,
wrapper and artifact digests are in `negative-cc3858c7/`. The original source
branch and genuine Source14 snapshots remain unchanged.

The first trace mismatch is case 6 (`missing-stop-error`): the native immediate
EOF continuation finalizes a queued text delta's shared partial before the guest
consumer snapshots it. Source still exposes the pending/index scratch state at
that point. Root directed that this timing negative await reviewed C-generator
integration. No expected snapshot or timing assertion has been weakened.

The cancellation test returned the expected abort error but took longer than its
unchanged three-second bound. On Windows, the redirected-pipe read inside
`std.process.run` could remain blocked after task cancellation, delaying its hidden
Child cleanup until the sleeping process exited. The source-only repair fork
owns hProcess directly, terminates only that open spawned handle before joining
readers, and retains all process/pipe handles until their borrowers finish. This
repair has formatting/AST checks only and requires a fresh native gate.

The Source14 wire comparison uses the actual captured path (including any query)
and request body. Captured content-type and custom fixture headers are now also
asserted in the repair fork. Source14 did not capture method/full URL and replaced
the auth value with a presence marker; the native literal fake bearer assertion
is independent evidence. No method/full-header equivalence is claimed for
Source14. The subsequent Source18 capture below closes those observation gaps
and adds four streamSimple stimuli.

## Source18 capture and next native owner

Root granted LIGHT3 for Source18. The actual pinned Source5ab provider and actual
AWS SDK completed all 18 cases under owned Node PID 52568, exit 0. Each case
recorded exactly one actual POST in `requests[]`, its full loopback URL, matching
path/query, JSON body and verbatim fake bearer authorization. Four added cases
exercise streamSimple defaults, adaptive Claude block binding, Claude budget
clamping and non-Claude GPT effort. Output fixture SHA256:
`8BD6BD72C082D1CC13939EA65EFC02CE7F7265D213A94BFB1F857B744413D69A`.
Source1967/dependencies31064/Node1774, eleven extra controls, the control manifest
and 84 absence records all had terminal posthash drift zero. LIGHT3 was released.
The driver, owned receipts, module observation log and control hashes are retained
in `source18/`; the old Source14 and native negative remain unchanged.

The new `build-native-ai-bedrock18` / `test-native-ai-bedrock18` target retains
the existing Source14, fragmentation/CRC and cancellation gates and adds the
Source18 comparison. It binds to the actual captured request target and checks
captured method, full URL after rebinding only its origin, unchanged path/query,
body, and every captured functional header including the fake auth value.
Response diagnostic headers remain explicit in the real guest callbacks. Native
Source18 compilation/runtime have not run and need Root's native reservation;
the reviewed C-generator/item-iterator integration remains necessary for the
retained protocol timing negative. No expected Source observation is synthesized
or rewritten to accommodate that negative.
