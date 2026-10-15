$ErrorActionPreference='Stop'
$taskRoot='C:/Users/adyba/pi-zig-ai-compat-b45-20261014'
$taskDestination=Join-Path $taskRoot 'verification/ai-http-wire-b45-20261014'
if(Test-Path -LiteralPath $taskDestination){throw 'Proof destination already exists'}
New-Item -ItemType Directory -Path $taskDestination > $null
$taskPrefixes=@('native-ai-http-compile-debug-first-20261014','native-ai-http-compile-debug-second-20261014','native-ai-http-compile-debug-third-20261014','native-ai-http-runtime-debug-first-20261014','native-ai-http-runtime-debug-second-20261014')
foreach($taskPrefix in $taskPrefixes){Get-ChildItem -LiteralPath $PSScriptRoot -File|Where-Object {$_.Name.StartsWith($taskPrefix,[StringComparison]::Ordinal)}|Copy-Item -Destination $taskDestination}
$taskArtifacts=@('Run-AiHttpCompile-20261014.ps1','Run-AiHttpRuntime-20261014.ps1','Inspect-AiHttpTestInventory-20261014.ps1','native-ai-http-debug-compiled-test-inventory-20261014.json','ai-http-owner-hooks-unqualified-20261014.patch','ai-b45-b06-provider-delta-audit-20261014.md')
foreach($taskArtifact in $taskArtifacts){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $taskArtifact) -Destination $taskDestination}
$taskOldProof=Join-Path $taskRoot 'verification/ai-provider-helpers-b45-20261014'
Get-ChildItem -LiteralPath $taskOldProof -File|Where-Object Name -Like 'ai-openai-completions-b45-http12*'|Copy-Item -Destination $taskDestination
$taskFirst=@(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'native-ai-http-runtime-debug-first-20261014-source-before.json') -Raw|ConvertFrom-Json)
$taskTest=[IO.File]::ReadAllText((Join-Path $taskRoot 'src/native_ai_http_test.zig'))
$taskOriginal=$taskTest.Replace("        // The direct QuickJS C parser requires a NUL byte after buf_len.`n        const expected_z = try gpa.dupeZ(u8, expected);`n        defer gpa.free(expected_z);`n",'').Replace('expected_z.ptr, expected_z.len','expected.ptr, expected.len')
$taskNegative=Join-Path $taskDestination 'negative-wire-caller-before-nul.zig.txt'
[IO.File]::WriteAllText($taskNegative,$taskOriginal,[Text.UTF8Encoding]::new($false))
$taskOriginalHash=($taskFirst|Where-Object path -eq 'src/native_ai_http_test.zig').sha256
if((Get-FileHash -LiteralPath $taskNegative).Hash -cne $taskOriginalHash){throw 'Reconstructed original negative caller does not match frozen first runtime hash'}
$taskCode=@('src/extensions/native_ai_http_worker.zig','src/extensions/native_ai_http.zig','src/extensions/engine.zig','src/extensions/native_stdio_frontend.zig','src/native_ai_http_test.zig','build.zig','src/extensions/fixtures/ai-openai-http-b45.input.json','src/extensions/fixtures/ai-openai-http-b45.json')|ForEach-Object {@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $taskRoot $_)).Hash}}
$taskProof=[ordered]@{
 schema=1;candidate_base='f5e69af0f7e4f70f9ff50862366e14041e2db376';source_head='b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb';genuine_wire_scenarios=12;
 native=@{optimize='Debug';tests=6;authored_tests=5;imported_unnamed_storage_tests=1;strict_inventory='Read-only actual PE TestFn array; six exact names/lengths and executable function pointers';source_files=5330;source_drift=0;tool_files=19546;tool_drift=0;host_allocation_failure_scope='Every host allocation in pre-aborted request preparation; worker does not start';worker_allocator='page_allocator; failure injection over worker allocations is not claimed'};
 ownership=@{workers='Owned input/header/proxy bytes and native Io only; no JS values or provider state';owner='All promise capabilities, iterators, signal reads and provider decisions stay on owner thread';teardown='Cancel every worker before joining any; VM/context/Io retained through all joins; queued responses freed exactly once';limits='64 events/1MiB queue,512KiB frame/errorbody,16 owner requests';wake='Actual Engine pump/drain/await and stdio idle pending predicates'};
 negative=@{compile_first='Zig declaration shadowing; parameter renamed function to callee';runtime_first='5/6 passed; wire replay failed before HTTP because test caller passed non-NUL buffer to direct JS_ParseJSON';runtime_fix='Use gpa.dupeZ as required by existing direct C API; original caller recovered and hash verified against first frozen manifest';original_caller_sha256=$taskOriginalHash};
 code=$taskCode;
 qualification=@{raw_wire='Actual native owned HTTP POST, captured request body/auth placeholder and raw SSE frames from genuine b45 Source12';lifecycle='CR/LF/CRLF/BOM/multiline/events,429 body, native AbortSignal, bounded-queue timeout, cancel/join teardown and host preparation GPA';provider='No native provider request builder, assistant-event decoder, provider error/retry or builtin API qualification';latest_upstream='b06 delta separately source-audited; b45 oracles retain original head; fresh b06 JSON helper observations external, no native claim here'};
 limitations=@('ReleaseSafe has not run','Raw worker API is internal and not a public module alias','OpenAI provider integration remains incomplete','Builtins and latest official generated catalog remain incomplete','Default compat completeSimple for production summaries remains unwired','Whole application parity, public activation, Node bridge removal and release are not qualified');
 recorded_utc=[DateTimeOffset]::UtcNow.ToString('o')
}
$taskProof|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskDestination 'checkpoint-proof.json') -Encoding utf8NoBOM
$taskHashes=@(Get-ChildItem -LiteralPath $taskDestination -File|Sort-Object Name|ForEach-Object {@{path=$_.Name;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash;bytes=$_.Length}})
$taskHashes|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $taskDestination 'artifact-hashes.json') -Encoding utf8NoBOM
@{proof_sha256=(Get-FileHash -LiteralPath (Join-Path $taskDestination 'checkpoint-proof.json')).Hash;artifact_manifest_sha256=(Get-FileHash -LiteralPath (Join-Path $taskDestination 'artifact-hashes.json')).Hash;files=$taskHashes.Count}|ConvertTo-Json
