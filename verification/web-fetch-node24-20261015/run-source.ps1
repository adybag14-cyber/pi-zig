param([string]$Attempt='first')
$ErrorActionPreference='Stop'
$taskRoot='C:/Users/adyba/pi-zig-web-body-integration-20261015'
$taskEvidence='C:/Users/adyba/pi-zig-update-evidence-20261003'
$taskName="web-fetch-node24-source-$Attempt-20261015"
$taskBase=Join-Path $taskEvidence $taskName
$taskNode='C:/Program Files/nodejs/node.exe'
$taskSource='C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015'
$taskRuntime='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
$taskInput=Join-Path $taskRoot 'verification/web-fetch-node24-20261015/input.mjs'
$taskExpected=Join-Path $taskRoot 'src/extensions/fixtures/web-fetch-node24.json'
if(Test-Path -LiteralPath $taskExpected){throw 'Actual fetch expected must remain absent until successful capture and full posthash'}
if(@(Get-ChildItem -LiteralPath $taskEvidence -Filter "$taskName*" -File).Count){throw 'Refuse capture owner/receipt overwrite'}
$taskDriver=Join-Path $PSScriptRoot 'source-capture.mjs'
$taskOwner=Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'
$taskAudit=Join-Path $taskEvidence 'source5ab-dependency-contract-audit-20261015.json'
if((git -C $taskSource rev-parse HEAD).Trim() -cne '5ab7fe74c400097b386662205cd93900695b8a71'){throw 'Pinned Source context head drift'}
if((Get-FileHash -LiteralPath $taskNode).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Pinned Node executable drift'}
$taskContract=Get-Content -LiteralPath $taskAudit -Raw|ConvertFrom-Json
$taskAbsent=@($taskContract.pins|Where-Object status -eq 'platform_optional_absent'|ForEach-Object{Join-Path $taskRuntime $_.path})+@($taskContract.mismatches|ForEach-Object{Join-Path $taskRuntime $_.path})
if($taskAbsent.Count-ne84-or@($taskAbsent|Where-Object{Test-Path -LiteralPath $_}).Count){throw 'Original absent dependency inventory drift'}
$taskCandidate=@(git -C $taskRoot ls-files --cached --others --exclude-standard|Sort-Object -Unique|ForEach-Object{$taskFile=Join-Path $taskRoot $_;[ordered]@{path=$taskFile;sha256=(Get-FileHash -LiteralPath $taskFile).Hash}})
$taskCandidatePath="$taskBase-candidate.json"
$taskCandidate|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskCandidatePath -Encoding utf8NoBOM
$taskControls=@($PSCommandPath,$taskInput,$taskDriver,$taskOwner,$taskAudit)|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}}
$taskControlPath="$taskBase-controls.json"
$taskControls|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskControlPath -Encoding utf8NoBOM
$taskManifestPaths=@((Join-Path $taskEvidence 'source5ab-full-manifest-20261015.json'),(Join-Path $taskEvidence 'durable-19cb534-reference-20261012-all-built-runtime.json'),(Join-Path $taskEvidence 'root-current8a-npm-tools-before.json'),$taskCandidatePath,$taskControlPath)
$taskManifests=@($taskManifestPaths|ForEach-Object{[ordered]@{name=[IO.Path]::GetFileName($_);path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskFrozen="$taskBase-frozen.json"
$taskManifests|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskFrozen -Encoding utf8NoBOM
$taskFrozenHash=(Get-FileHash -LiteralPath $taskFrozen).Hash
function Verify-Frozen {
 if((Get-FileHash -LiteralPath $taskFrozen).Hash-cne$taskFrozenHash){throw 'Frozen registry drift'}
 $taskChecks=@()
 foreach($taskManifest in $taskManifests){
  if((Get-FileHash -LiteralPath $taskManifest.path).Hash-cne$taskManifest.sha256){throw 'Manifest identity drift'}
  $taskRows=@(Get-Content -LiteralPath $taskManifest.path -Raw|ConvertFrom-Json)
  foreach($taskRow in $taskRows){if(!(Test-Path -LiteralPath $taskRow.path -PathType Leaf)-or(Get-FileHash -LiteralPath $taskRow.path).Hash-ine$taskRow.sha256){throw "Frozen input drift $($taskRow.path)"}}
  $taskChecks+=[ordered]@{manifest=$taskManifest.name;count=$taskRows.Count;drift=0}
 }
 if($taskChecks[0].count-ne1967-or$taskChecks[1].count-ne31064-or$taskChecks[2].count-ne1774){throw 'Original full inventory mismatch'}
 if(@($taskAbsent|Where-Object{Test-Path -LiteralPath $_}).Count){throw 'Absent dependency state drift'}
 return $taskChecks
}
$taskBefore=Verify-Frozen
$taskBefore|ConvertTo-Json -Depth 5|Set-Content -LiteralPath "$taskBase-before.json" -Encoding utf8NoBOM
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1024
[ordered]@{minimum_free_bytes=2GB;available_bytes=$taskFree;heap_mb=256;outer_seconds=300;light_lane=6;root_grant='PENDING actual fetch Source39 LIGHT grant';checked_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath "$taskBase-admission.json" -Encoding utf8NoBOM
if($taskFree-lt2GB){throw 'Source2GiB admission rejected'}
$taskFailure=$null
try{& $taskOwner -Name $taskName -Executable $taskNode -WorkingDirectory $taskRoot -Arguments @('--expose-gc','--max-old-space-size=256',$taskDriver,"$taskBase-output.json",$taskInput,"$taskBase-bundled-undici.js.txt",$taskFrozen) -TimeoutSeconds 300 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH='';NODE_USE_ENV_PROXY='';HTTP_PROXY='';HTTPS_PROXY='';ALL_PROXY='';NO_PROXY='127.0.0.1,localhost'}}catch{$taskFailure=$_}
$taskAfter=Verify-Frozen
$taskAfter|ConvertTo-Json -Depth 5|Set-Content -LiteralPath "$taskBase-after.json" -Encoding utf8NoBOM
if($taskFailure){throw $taskFailure}
$taskResult=Get-Content -LiteralPath "$taskBase-output.json" -Raw|ConvertFrom-Json
if($taskResult.actualNode.version-cne'v24.14.0'-or$taskResult.cases-ne39){throw 'Actual Node fetch capture inventory mismatch'}
Write-Output "ACTUAL_NODE24_FETCH_CAPTURE_PASSED cases=$($taskResult.cases) bundled_undici=$($taskResult.actualNode.undici) candidate=$($taskCandidate.Count)"
