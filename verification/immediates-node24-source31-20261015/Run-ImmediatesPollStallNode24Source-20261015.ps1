param([string]$Attempt='first')
$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskName="immediates-poll-stall-node24-source-$Attempt-20261015"
$taskTree='C:/Users/adyba/pi-zig-native-immediates-20261015'
$taskNode='C:/Program Files/nodejs/node.exe'
$taskDriver=Join-Path $taskTree 'tools/capture-immediate-poll-stall-node24.mjs'
$taskInput=Join-Path $taskTree 'src/extensions/fixtures/immediates-poll-stall-node24.input.txt'
$taskExpected=Join-Path $taskTree 'src/extensions/fixtures/immediates-poll-stall-node24.json'
$taskBuiltin=Join-Path $taskEvidence 'web-body-node24-source-first-20261015-node-builtin-authorities.json'
$taskNodeManifest=Join-Path $taskEvidence 'sourceae7-node-tools-before-20261015.json'
$taskOwner=Join-Path $taskEvidence 'Invoke-WebCryptoOwnedSource-20261015.ps1'
if(Test-Path -LiteralPath $taskExpected){throw 'Expected must remain absent before genuine Source terminal/posthash'}
if((Get-FileHash -LiteralPath $taskNode).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Actual Node24 executable changed'}
if((Get-FileHash -LiteralPath $taskBuiltin).Hash -cne '0CD86676BB2A46A4E772D1FD8BB3D00FCA658383BC388846DCC796547DC79263'){throw 'Full368 builtin authority packet changed'}
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt 2MB){throw 'Fresh2GiB admission required before Source syntax/controls'}
& $taskOwner -Name "$taskName-syntax" -Executable $taskNode -WorkingDirectory $taskTree -Arguments @('--max-old-space-size=256','--check',$taskDriver) -TimeoutSeconds 30 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH=''}
if((Get-Content -Raw (Join-Path $taskEvidence "$taskName-syntax.json")|ConvertFrom-Json).status -cne 'passed'){throw 'Driver syntax failed'}
function Check-Rows($taskRows){
 $taskChanged=[Collections.Generic.List[string]]::new()
 foreach($taskRow in $taskRows){if(!(Test-Path -LiteralPath $taskRow.path -PathType Leaf) -or (Get-FileHash -LiteralPath $taskRow.path).Hash -cne $taskRow.sha256){$taskChanged.Add($taskRow.path)}}
 return @($taskChanged)
}
function Candidate-Paths {
 @(& git -c gc.auto=0 -c maintenance.auto=false -C $taskTree ls-files --cached --others --exclude-standard | Where-Object {$_ -ne 'src/extensions/fixtures/immediates-poll-stall-node24.json'} | ForEach-Object {Join-Path $taskTree $_})
}
function Node-Paths {@(@('C:\Program Files\nodejs\node.exe')+@(Get-ChildItem -LiteralPath 'C:/Program Files/nodejs/node_modules/npm' -Recurse -File -Force|ForEach-Object FullName)|Sort-Object)}
$taskNodeRows=@(Get-Content -Raw $taskNodeManifest|ConvertFrom-Json)
if($taskNodeRows.Count -ne 1774 -or @(Check-Rows $taskNodeRows).Count){throw 'Full1774 Node inventory prehash drift'}
$taskNodePaths=Node-Paths
if(@(Compare-Object @($taskNodeRows.path|Sort-Object) $taskNodePaths).Count){throw 'Full scoped Node1774 path inventory drift'}
$taskCandidatePaths=@(Candidate-Paths)
$taskCandidate=@($taskCandidatePaths|ForEach-Object {@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskControls=@($taskOwner,$PSCommandPath,$taskBuiltin,$taskNodeManifest,$taskDriver,$taskInput)|Select-Object -Unique|ForEach-Object {@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}}
@{candidate_head=(& git -c gc.auto=0 -c maintenance.auto=false -C $taskTree rev-parse HEAD);node=$taskNodeRows;candidate=$taskCandidate;controls=$taskControls;builtin_count=368;oracle_scope='Node builtin Immediate only; imports node:fs,node:vm,node:net,node:crypto. One real127.0.0.1 TCP data callback held8ms on actualclock. No PiSDK/external dependencies used.'}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-before.json") -Encoding utf8NoBOM
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt 2MB){throw 'Fresh2GiB Source admission denied'}
@{status='admitted';free_kib=$taskFree;required_kib=2MB;heap_mb=256;coordinated_with='Root explicit Immediates Source grant';observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json") -Encoding utf8NoBOM
$taskOutput=Join-Path $taskEvidence "$taskName-output.json"
& $taskOwner -Name $taskName -Executable $taskNode -WorkingDirectory $taskTree -Arguments @('--max-old-space-size=256','--expose-gc',$taskDriver,$taskInput,$taskOutput,$taskBuiltin) -TimeoutSeconds 300 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH='';NODE_USE_ENV_PROXY='';HTTP_PROXY='';HTTPS_PROXY='';ALL_PROXY=''}
$taskNodeChanged=@(Check-Rows $taskNodeRows)
$taskCandidateChanged=@(Check-Rows $taskCandidate)
$taskControlChanged=@(Check-Rows $taskControls)
$taskInventoryChanged=@(Compare-Object $taskCandidatePaths @(Candidate-Paths))
$taskNodeInventoryChanged=@(Compare-Object $taskNodePaths @(Node-Paths))
$taskPost=@{node_files=$taskNodeRows.Count;node_drift=$taskNodeChanged;node_inventory_drift=$taskNodeInventoryChanged;candidate_files=$taskCandidate.Count;candidate_drift=$taskCandidateChanged;control_files=@($taskControls).Count;control_drift=$taskControlChanged;candidate_inventory_drift=$taskInventoryChanged;expected_still_absent=!(Test-Path -LiteralPath $taskExpected);completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
$taskPost|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-posthash.json") -Encoding utf8NoBOM
if($taskNodeChanged.Count -or $taskNodeInventoryChanged.Count -or $taskCandidateChanged.Count -or $taskControlChanged.Count -or $taskInventoryChanged.Count -or !$taskPost.expected_still_absent){throw 'Full posthash drift'}
$taskTerminal=Get-Content -Raw (Join-Path $taskEvidence "$taskName.json")|ConvertFrom-Json
if($taskTerminal.status -cne 'passed'){throw "Actual Source terminal $($taskTerminal.status)"}
$taskResult=Get-Content -Raw $taskOutput|ConvertFrom-Json
if($taskResult.realLoopbackPolls -ne 1){throw 'Actual loopback poll controls missing'}
if($taskResult.nodeVersion -cne 'v24.14.0' -or $taskResult.builtinSourceCount -ne 368 -or $taskResult.builtinAuthoritySha256 -cne '0CD86676BB2A46A4E772D1FD8BB3D00FCA658383BC388846DCC796547DC79263' -or $taskResult.count -ne @($taskResult.rows).Count -or $taskResult.count -ne 1){throw 'Genuine Source controls output malformed'}
Copy-Item -LiteralPath $taskOutput -Destination $taskExpected
@{source_cases=$taskResult.count;pid=$taskTerminal.pid;expected_sha256=(Get-FileHash -LiteralPath $taskExpected).Hash;owner_sha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;expected_published_after_terminal_and_posthash=$true;native_qualified=$false;full_pi_qualified=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-validation.json") -Encoding utf8NoBOM
Write-Output ('NODE24_IMMEDIATE_POLL_STALL_SOURCE_CASES='+$taskResult.count)
