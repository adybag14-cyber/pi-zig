param([Parameter(Mandatory)][string]$CandidateHead,[string]$Attempt='first')
$ErrorActionPreference='Stop'
$taskPrivate='C:/Users/adyba/pi-zig-native-writable-stream-20261015'
$taskEvidence=Join-Path 'C:/Users/adyba/pi-zig-update-evidence-20261003' "writable-stream-node24-source56-$Attempt-20261015"
$taskName="writable-stream-node24-source56-$Attempt-20261015"
$taskNode='C:/Program Files/nodejs/node.exe'
$taskGit=(Get-Command git.exe -CommandType Application | Select-Object -First 1).Source
$taskInput=Join-Path $taskPrivate 'src/extensions/fixtures/writable-stream-node24.input.txt'
$taskExpected=Join-Path $taskPrivate 'src/extensions/fixtures/writable-stream-node24.json'
$taskDriver=Join-Path $taskPrivate 'tools/capture-writable-stream-node24.mjs'
$taskObserver=Join-Path $PSScriptRoot 'observe-builtin-authority.mjs'
$taskAuthority='C:/Users/adyba/pi-zig-update-evidence-20261003/web-body-node24-source-first-20261015-node-builtin-authorities.json'
$taskToolsManifest='C:/Users/adyba/pi-zig-update-evidence-20261003/root-current8a-npm-tools-before.json'
$taskOwner=Join-Path $PSScriptRoot 'Invoke-OwnedEeSourceJob-20261012.ps1'
function CandidateGit([string[]]$Arguments){& $taskGit -c gc.auto=0 -c maintenance.auto=false -c pack.threads=2 -c pack.windowMemory=64m -C $taskPrivate @Arguments}
function ChangedRows($Rows){$changed=[Collections.Generic.List[string]]::new();foreach($row in $Rows){if(!(Test-Path -LiteralPath $row.path -PathType Leaf) -or (Get-FileHash -LiteralPath $row.path).Hash -ine $row.sha256){$changed.Add($row.path)}};return @($changed)}
function FreezePaths($Paths,[string]$Manifest){$rows=@($Paths|ForEach-Object{@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}});$rows|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $Manifest -Encoding utf8NoBOM;return ,$rows}
if(Test-Path -LiteralPath $taskEvidence){throw 'Fresh Source56 evidence directory required'}
if(Test-Path -LiteralPath $taskExpected){throw 'Expected WritableStream fixture must remain absent'}
if((CandidateGit @('rev-parse','HEAD')) -cne $CandidateHead -or @(CandidateGit @('status','--porcelain')).Count){throw 'Exact published clean WritableStream candidate required'}
if((Get-FileHash -LiteralPath $taskNode).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Pinned Node24.14.0 executable changed'}
if((Get-FileHash -LiteralPath $taskAuthority).Hash -cne '0CD86676BB2A46A4E772D1FD8BB3D00FCA658383BC388846DCC796547DC79263'){throw 'Exact original Node24 builtin bodies changed'}
New-Item -ItemType Directory -Path $taskEvidence|Out-Null
$taskTools=@(Get-Content -LiteralPath $taskToolsManifest -Raw|ConvertFrom-Json)
if($taskTools.Count -ne 1774 -or @(ChangedRows $taskTools).Count){throw 'Strict1774 Node/tool prehash mismatch'}
$taskNamesBefore=@(CandidateGit @('ls-files'))
$taskCandidate=FreezePaths @($taskNamesBefore|ForEach-Object{Join-Path $taskPrivate $_}) (Join-Path $taskEvidence 'whole-candidate-before.json')
$taskControls=FreezePaths @($PSCommandPath,$taskOwner,$taskInput,$taskDriver,$taskObserver,$taskAuthority,$taskToolsManifest,$taskNode,$taskGit,(Join-Path $taskEvidence 'whole-candidate-before.json')) (Join-Path $taskEvidence 'controls-before.json')
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt 2MB){throw 'Normal Source2GiB admission denied'}
@{status='admitted';candidate_head=$CandidateHead;candidate_files=$taskCandidate.Count;node_tool_files=1774;free_kib=$taskFree;required_kib=2MB;heap_mb=256;timeout_seconds=300;cases=56;expected_absent=$true;caller_sha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;owner_sha256=(Get-FileHash -LiteralPath $taskOwner).Hash;input_sha256=(Get-FileHash -LiteralPath $taskInput).Hash;driver_sha256=(Get-FileHash -LiteralPath $taskDriver).Hash;authority_sha256=(Get-FileHash -LiteralPath $taskAuthority).Hash;utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence 'admission.json') -Encoding utf8NoBOM
$taskOutput=Join-Path $taskEvidence "$taskName-output.json"
# The audited owner writes next to its own script. Copy its exact immutable bytes
# into this fresh attempt directory so records cannot collide across attempts.
$taskOwnedCopy=Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'
Copy-Item -LiteralPath $taskOwner -Destination $taskOwnedCopy
$taskOwnerHash=(Get-FileHash -LiteralPath $taskOwnedCopy).Hash
try {
 & $taskOwnedCopy -Name $taskName -Executable $taskNode -WorkingDirectory $taskPrivate -Arguments @('--max-old-space-size=256','--expose-gc','--import',([Uri]$taskObserver).AbsoluteUri,$taskDriver,$taskInput,$taskOutput,$taskAuthority) -TimeoutSeconds 300 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH='';WRITABLE_BUILTIN_OBSERVATION=(Join-Path $taskEvidence 'actual-builtin-authority.json')}
} finally {
 $taskToolsChanged=@(ChangedRows $taskTools)
 $taskCandidateChanged=@(ChangedRows $taskCandidate)
 $taskControlChanged=@(ChangedRows $taskControls)
 $taskNamesChanged=@(Compare-Object $taskNamesBefore @(CandidateGit @('ls-files')))
 $taskHeadChanged=(CandidateGit @('rev-parse','HEAD')) -cne $CandidateHead
 $taskDirty=@(CandidateGit @('status','--porcelain'))
 $taskOwnerChanged=(Get-FileHash -LiteralPath $taskOwnedCopy).Hash -cne $taskOwnerHash
 @{node_tool_files=1774;node_tool_drift=$taskToolsChanged;candidate_files=$taskCandidate.Count;candidate_drift=$taskCandidateChanged;control_drift=$taskControlChanged;candidate_path_drift=$taskNamesChanged;candidate_head_drift=$taskHeadChanged;candidate_dirty=$taskDirty;owner_copy_drift=$taskOwnerChanged;expected_present=(Test-Path -LiteralPath $taskExpected);completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence 'full-posthash.json') -Encoding utf8NoBOM
 if($taskToolsChanged.Count -or $taskCandidateChanged.Count -or $taskControlChanged.Count -or $taskNamesChanged.Count -or $taskHeadChanged -or $taskDirty.Count -or $taskOwnerChanged -or (Test-Path -LiteralPath $taskExpected)){throw 'Source56 full immutable posthash drift'}
}
$taskTerminal=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
if($taskTerminal.status -cne 'passed' -or $taskTerminal.exit_code -ne 0){throw 'Genuine WritableStream Source56 process failed'}
$taskResult=Get-Content -LiteralPath $taskOutput -Raw|ConvertFrom-Json -Depth 1024
if($taskResult.nodeVersion -cne 'v24.14.0' -or $taskResult.cases -ne 56 -or @($taskResult.rows).Count -ne 56 -or @($taskResult.rows|Where-Object unexpected).Count){throw 'Actual Node24 WritableStream Source56 rows incomplete'}
$taskBuiltin=Get-Content -Raw (Join-Path $taskEvidence 'actual-builtin-authority.json')|ConvertFrom-Json
if($taskBuiltin.pid -ne $taskTerminal.pid -or $taskBuiltin.nodeVersion -cne 'v24.14.0' -or $taskBuiltin.keys -ne 369 -or $taskBuiltin.stringBodies -ne 368 -or !$taskBuiltin.configsOwn -or !$taskBuiltin.configsUndefined -or $taskBuiltin.actualBodiesSha256 -cne '0cd86676bb2a46a4e772d1fd8bb3d00fca658383bc388846dcc796547dc79263'){throw 'Actual369 builtin/368body/configsundefined authority missing'}
Copy-Item -LiteralPath $taskOutput -Destination $taskExpected
@{source_cases=56;expected_sha256=(Get-FileHash -LiteralPath $taskExpected).Hash;accepted_after_terminal_and_fullpost0=$true;candidate_head=$CandidateHead;native_compile_run=$false;native_runtime_run=$false;full_pi_qualified=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence 'validation.json') -Encoding utf8NoBOM
Write-Output 'GENUINE_WRITABLE_SOURCE56_TERMINAL_FULLPOST0'
