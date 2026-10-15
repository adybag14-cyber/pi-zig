param([Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$CandidateHead,[ValidatePattern('^[a-zA-Z0-9_-]+$')][string]$Attempt='first',[string]$Evidence='C:/Users/adyba/pi-zig-update-evidence-20261003')
$ErrorActionPreference='Stop'
$taskTree='C:/Users/adyba/pi-zig-native-transform-compression-20261015'
$taskName="transform-compression-node24-source-$Attempt-20261015"
$taskNode='C:/Program Files/nodejs/node.exe'
$taskOriginalDriver=Join-Path $taskTree 'tools/capture-web-transform-compression-node24.mjs'
$taskPreparedOwner='C:/Users/adyba/pi-zig-native-transform-compression-20261015/verification/transform-compression-node24-prepared-20261015/Run-TransformCompressionSource-20261015.ps1'
$taskDriver=Join-Path $Evidence 'capture-transform-compression-configs-companion-20261015.mjs'
$taskInput=Join-Path $taskTree 'src/extensions/fixtures/web-transform-compression-node24.input.txt'
$taskExpected=Join-Path $taskTree 'src/extensions/fixtures/web-transform-compression-node24.json'
$taskAuthority=Join-Path $Evidence 'web-body-node24-source-first-20261015-node-builtin-authorities.json'
$taskNodeManifest=Join-Path $Evidence 'root-current8a-npm-tools-before.json'
$taskOwner=Join-Path $Evidence 'Invoke-OwnedEeSourceJob-20261012.ps1'
$taskOutput=Join-Path $Evidence "$taskName-output.json"
$taskClock=[Diagnostics.Stopwatch]::StartNew()
function Deadline {if($taskClock.Elapsed.TotalSeconds -gt 600){throw 'Transform/compression Source ten-minute operation deadline'}}
function Check-Rows($rows){@($rows|Where-Object{Deadline;!(Test-Path -LiteralPath $_.path -PathType Leaf) -or (Get-FileHash -LiteralPath $_.path).Hash -ine $_.sha256})}
function Candidate-Paths {@(git -c gc.auto=0 -c maintenance.auto=false -c pack.threads=2 -c pack.windowMemory=64m -C $taskTree ls-files --cached --others --exclude-standard|Sort-Object -Unique|ForEach-Object{Join-Path $taskTree $_})}
if((git -c gc.auto=0 -c maintenance.auto=false -c pack.threads=2 -c pack.windowMemory=64m -C $taskTree rev-parse HEAD) -cne $CandidateHead){throw 'Exact sealed native candidate required'}
if(@(git -c gc.auto=0 -c maintenance.auto=false -c pack.threads=2 -c pack.windowMemory=64m -C $taskTree status --porcelain).Count){throw 'Clean native candidate required'}
if(Test-Path -LiteralPath $taskExpected){throw 'Expected must remain absent until genuine Source terminal/fullpost0'}
if((Test-Path -LiteralPath $taskOutput) -or (Test-Path -LiteralPath (Join-Path $Evidence "$taskName.json"))){throw 'Fresh Source attempt required; prior negatives retained'}
if((Get-FileHash -LiteralPath $taskNode).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Actual Node24 executable pin changed'}
if((Get-FileHash -LiteralPath $taskAuthority).Hash -cne '0CD86676BB2A46A4E772D1FD8BB3D00FCA658383BC388846DCC796547DC79263'){throw 'Actual368 builtin source authority packet changed'}
$taskNodes=@(Get-Content -LiteralPath $taskNodeManifest -Raw|ConvertFrom-Json)
if($taskNodes.Count -ne 1774 -or @(Check-Rows $taskNodes).Count){throw 'Full1774 actual Node files prehash mismatch'}
$taskPaths=@(Candidate-Paths)
$taskCandidate=@($taskPaths|ForEach-Object{Deadline;@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskControls=@($PSCommandPath,$taskPreparedOwner,$taskOwner,$taskAuthority,$taskNodeManifest,$taskDriver,$taskOriginalDriver,$taskInput)|ForEach-Object{@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}}
@{scope='Node builtins only; actual368 bodies compared byte-for-byte in child; no Pi or external npm module execution';candidate_head=$CandidateHead;node=$taskNodes;candidate=$taskCandidate;controls=$taskControls;builtin_count=368}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $Evidence "$taskName-before.json") -Encoding utf8NoBOM
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt 2MB){throw 'Fresh2GiB admission denied; no Node child launched'}
Deadline
@{status='admitted';coordinated_with='Explicit Root Source LIGHT slot grant required before invocation';free_kib=$taskFree;required_kib=2MB;heap_mb=256;timeout_seconds=300;operation_deadline_seconds=600;candidate_head=$CandidateHead;cases=66;node_files=1774;candidate_files=$taskCandidate.Count;control_files=@($taskControls).Count;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $Evidence "$taskName-admission.json") -Encoding utf8NoBOM
$taskFailure=$null
try {
 & $taskOwner -Name $taskName -Executable $taskNode -WorkingDirectory $taskTree -Arguments @('--max-old-space-size=256','--expose-gc',$taskDriver,$taskOutput,$taskInput,$taskAuthority) -TimeoutSeconds 300 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH='';NODE_USE_ENV_PROXY='';HTTP_PROXY='';HTTPS_PROXY='';ALL_PROXY=''}
} catch {$taskFailure=$_}
finally {
 Start-Sleep -Seconds 10
 $taskNodeDrift=@(Check-Rows $taskNodes)
 $taskCandidateDrift=@(Check-Rows $taskCandidate)
 $taskControlDrift=@(Check-Rows $taskControls)
 $taskInventoryDrift=@(Compare-Object $taskPaths @(Candidate-Paths))
 $taskHeadAfter=git -c gc.auto=0 -c maintenance.auto=false -c pack.threads=2 -c pack.windowMemory=64m -C $taskTree rev-parse HEAD
 $taskPost=@{node_files=$taskNodes.Count;node_drift=$taskNodeDrift;candidate_files=$taskCandidate.Count;candidate_drift=$taskCandidateDrift;control_files=@($taskControls).Count;control_drift=$taskControlDrift;candidate_inventory_drift=$taskInventoryDrift;candidate_head_before=$CandidateHead;candidate_head_after=$taskHeadAfter;expected_still_absent=!(Test-Path -LiteralPath $taskExpected);elapsed_seconds=$taskClock.Elapsed.TotalSeconds;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
 $taskPost|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $Evidence "$taskName-posthash.json") -Encoding utf8NoBOM
}
if($taskNodeDrift.Count -or $taskCandidateDrift.Count -or $taskControlDrift.Count -or $taskInventoryDrift.Count -or $taskHeadAfter -cne $CandidateHead -or !$taskPost.expected_still_absent){throw 'Full Source66 posthash/input inventory drift'}
if($taskFailure){throw $taskFailure}
$taskTerminal=Get-Content -LiteralPath (Join-Path $Evidence "$taskName.json") -Raw|ConvertFrom-Json
if($taskTerminal.status -cne 'passed' -or $taskTerminal.exit_code -ne 0 -or !$taskTerminal.identity_captured -or $taskTerminal.executable_sha256 -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Actual Node24 Source terminal/identity failure'}
$taskConfigs=Get-Content -LiteralPath ($taskOutput+'.configs.json') -Raw|ConvertFrom-Json
if($taskConfigs.pid -ne $taskTerminal.pid -or $taskConfigs.totalEntries -ne 369 -or $taskConfigs.sourceBodies -ne 368 -or !$taskConfigs.configs.own -or !$taskConfigs.configs.undefined -or $taskConfigs.configs.type -cne 'undefined'){throw 'Separate same-child configs inventory malformed'}
$taskResult=Get-Content -LiteralPath $taskOutput -Raw|ConvertFrom-Json
if($taskResult.actualNode.version -cne 'v24.14.0' -or $taskResult.builtinCount -ne 368 -or $taskResult.builtinAuthoritySha256 -cne '0CD86676BB2A46A4E772D1FD8BB3D00FCA658383BC388846DCC796547DC79263' -or $taskResult.cases -ne 66 -or @($taskResult.rows).Count -ne 66){throw 'Genuine Source66 inventory malformed'}
@{status='genuine_source66_captured';configs=$taskConfigs;owner_sha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;prepared_owner_sha256=(Get-FileHash -LiteralPath $taskPreparedOwner).Hash;companion_caller_sha256=(Get-FileHash -LiteralPath $taskDriver).Hash;original_caller_sha256=(Get-FileHash -LiteralPath $taskOriginalDriver).Hash;candidate_head=$CandidateHead;source_cases=66;actual_node=$taskTerminal;output_path=$taskOutput;output_sha256=(Get-FileHash -LiteralPath $taskOutput).Hash;expected_still_absent=$true;native_qualified=$false;full_pi_qualified=$false}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $Evidence "$taskName-qualified.json") -Encoding utf8NoBOM
Write-Output "GENUINE_TRANSFORM_COMPRESSION_SOURCE66_CAPTURED=$taskOutput"
