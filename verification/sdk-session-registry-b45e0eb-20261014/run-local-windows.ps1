$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskPrivate='C:/Users/adyba/pi-zig-sdk-events-hosted-20261013'
$taskSource='C:/Users/adyba/pi-upstream-source-b45e0eb-20261014'
$taskInput=Join-Path $taskPrivate 'verification/sdk-session-registry-1692bba-20261014/input64.txt'
$taskScript=Join-Path $taskEvidence 'sdk-registry64-b45-source-capture-20261014.mjs'
$taskObserver=Join-Path $taskEvidence 'sdk-source-b45-observe-20261014.mjs'
$taskOwner=Join-Path $taskPrivate 'verification/sdk-session-loadout-e6220e1-20261013/run-native-owner.ps1'
$taskPrefix='sdk-registry64-b45-original-local-20261014'
$taskExpectedHead='033377502f9459101911e10c204ea17d3ff822dd'
if((git -C $taskPrivate rev-parse HEAD).Trim() -cne $taskExpectedHead){throw 'Candidate head mismatch'}
if((git -C $taskSource rev-parse HEAD).Trim() -cne 'b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb'){throw 'Original Source head mismatch'}
$taskCandidate=@(git -C $taskPrivate ls-files --cached --others --exclude-standard|Sort-Object -Unique|ForEach-Object{$taskPath=Join-Path $taskPrivate $_;[ordered]@{path=$taskPath;sha256=(Get-FileHash -LiteralPath $taskPath).Hash}})
$taskCandidateManifest=Join-Path $taskEvidence "$taskPrefix-candidate.json"
$taskCandidate|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskCandidateManifest -Encoding utf8NoBOM
$taskControls=@($taskInput,$taskScript,$taskObserver,$taskOwner,$PSCommandPath)|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}}
$taskControlManifest=Join-Path $taskEvidence "$taskPrefix-controls.json"
$taskControls|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskControlManifest -Encoding utf8NoBOM
$taskManifestNames=@('sdk-source-b45-full-manifest-20261014.json','durable-19cb534-reference-20261012-all-built-runtime.json','root-current8a-npm-tools-before.json',"$taskPrefix-candidate.json","$taskPrefix-controls.json")
$taskManifests=@($taskManifestNames|ForEach-Object{$taskPath=Join-Path $taskEvidence $_;[ordered]@{name=$_;path=$taskPath;sha256=(Get-FileHash -LiteralPath $taskPath).Hash}})
$taskFrozen=Join-Path $taskEvidence "$taskPrefix-frozen.json"
$taskManifests|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskFrozen -Encoding utf8NoBOM
$taskFrozenHash=(Get-FileHash -LiteralPath $taskFrozen).Hash
function Verify-Original {
    if((Get-FileHash -LiteralPath $taskFrozen).Hash -cne $taskFrozenHash){throw 'Frozen manifest list drift'}
    $taskChecks=@()
    foreach($taskManifest in $taskManifests){
        if((Get-FileHash -LiteralPath $taskManifest.path).Hash -cne $taskManifest.sha256){throw 'Manifest identity drift'}
        $taskRows=@(Get-Content -LiteralPath $taskManifest.path -Raw|ConvertFrom-Json)
        $taskDrift=@($taskRows|Where-Object{!(Test-Path -LiteralPath $_.path -PathType Leaf) -or (Get-FileHash -LiteralPath $_.path).Hash -ine $_.sha256}|ForEach-Object path)
        if($taskDrift.Count){throw "Frozen $($taskManifest.name) drift $($taskDrift[0])"}
        $taskChecks+=[ordered]@{manifest=$taskManifest.name;manifest_sha256=$taskManifest.sha256;count=$taskRows.Count;drift=0}
    }
    if($taskChecks[0].count -ne 1965 -or $taskChecks[1].count -ne 31064 -or $taskChecks[2].count -ne 1774){throw 'Original complete inventory mismatch'}
    return $taskChecks
}
foreach($taskAttempt in @('first','second')){
    $taskBase=Join-Path $taskEvidence "$taskPrefix-$taskAttempt"
    $taskBefore=Verify-Original
    $taskBefore|ConvertTo-Json -Depth 5|Set-Content -LiteralPath "$taskBase-before.json" -Encoding utf8NoBOM
    [GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect()
    $taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
    [ordered]@{minimum_free_bytes=2GB;available_bytes=$taskFree*1024;checked_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath "$taskBase-admission.json" -Encoding utf8NoBOM
    if($taskFree -lt 2MB){throw 'Original Source2GiB admission rejected'}
    $taskFailure=$null
    try{& $taskOwner -Executable 'C:/Program Files/nodejs/node.exe' -WorkingDirectory $taskSource -Arguments @('--max-old-space-size=256','--conditions=source','--experimental-transform-types','--import',([uri]$taskObserver).AbsoluteUri,$taskScript,"$taskBase-output.json",$taskInput,$taskFrozen) -ReceiptBase $taskBase -TimeoutSeconds 300}catch{$taskFailure=$_}
    $taskAfter=Verify-Original
    $taskAfter|ConvertTo-Json -Depth 5|Set-Content -LiteralPath "$taskBase-after.json" -Encoding utf8NoBOM
    if($taskFailure){throw $taskFailure}
    $taskRaw=Get-Content -LiteralPath "$taskBase-output.json" -Raw|ConvertFrom-Json
    if($taskRaw.source -cne 'b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb' -or $taskRaw.factories -ne 64 -or $taskRaw.raw.rows.Count -ne 64){throw 'Original actual Registry64 inventory mismatch'}
    $taskReceipt=Get-Content -LiteralPath "$taskBase.process.json" -Raw|ConvertFrom-Json
    if(Get-CimInstance Win32_Process -Filter "ProcessId = $($taskReceipt.pid)"){throw 'Owned Node process remains'}
}
$taskFirst=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskPrefix-first-output.json") -Raw|ConvertFrom-Json
$taskSecond=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskPrefix-second-output.json") -Raw|ConvertFrom-Json
if(($taskFirst.raw.rows|ConvertTo-Json -Depth 100 -Compress) -cne ($taskSecond.raw.rows|ConvertTo-Json -Depth 100 -Compress)){throw 'Original Registry64 double capture drift'}
Write-Output "ORIGINAL_REGISTRY64_B45_DOUBLE_CAPTURE_PASSED candidate=$($taskCandidate.Count)"
