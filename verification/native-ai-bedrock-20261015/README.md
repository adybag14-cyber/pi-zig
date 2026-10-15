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
runtime validation are pending Root's heavy-job reservation.

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
