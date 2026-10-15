$ErrorActionPreference='Stop'
$taskRoot='C:/Users/adyba/pi-zig-tool-render-20261015'
$taskEvidence='C:/Users/adyba/pi-zig-update-evidence-20261003'
$taskSource='C:/Users/adyba/pi-upstream-source-b45e0eb-20261014'
$taskPrefix='tool-file-renderers28-source-20261015-second'
$taskBase=Join-Path $taskEvidence $taskPrefix
$taskOwner='C:/Users/adyba/pi-zig-tool-render-20261015/verification/tool-render-edit54-20261015/run-owner.ps1'
$taskFixture=Join-Path $taskEvidence 'tool-file-renderers28-real-fs-20261015'
New-Item -ItemType Directory -Path $taskFixture -Force|Out-Null
[IO.File]::WriteAllText((Join-Path $taskFixture 'one.txt'),"old`nkeep`n")
[IO.File]::WriteAllText((Join-Path $taskFixture 'bom.txt'),[string][char]0xfeff+"old`r`nkeep`r`n")
[IO.File]::WriteAllText((Join-Path $taskFixture 'duplicate.txt'),"repeat repeat`n")
$taskInput=Join-Path $taskEvidence 'tool-file-renderers28.input.txt'
$taskCapture=Join-Path $taskEvidence 'tool-file-renderers28-source-capture-20261015.mjs'
$taskObserver=Join-Path $taskEvidence 'sdk-source-b45-observe-20261014.mjs'
if((git -C $taskSource rev-parse HEAD).Trim() -cne 'b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb'){throw 'Original Source head mismatch'}
$taskCandidate=@(git -C $taskRoot ls-files --cached --others --exclude-standard | Sort-Object -Unique | ForEach-Object { $taskFile=Join-Path $taskRoot $_; [ordered]@{path=$taskFile;sha256=(Get-FileHash -LiteralPath $taskFile).Hash} })
$taskCandidatePath="$taskBase-candidate.json"
$taskCandidate|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskCandidatePath -Encoding utf8NoBOM
$taskControls=@($PSCommandPath,$taskOwner,$taskInput,$taskCapture,$taskObserver,(Join-Path $taskFixture 'one.txt'),(Join-Path $taskFixture 'bom.txt'),(Join-Path $taskFixture 'duplicate.txt'))|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}}
$taskControlPath="$taskBase-controls.json"
$taskControls|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskControlPath -Encoding utf8NoBOM
$taskManifestPaths=@((Join-Path $taskEvidence 'sdk-source-b45-full-manifest-20261014.json'),(Join-Path $taskEvidence 'durable-19cb534-reference-20261012-all-built-runtime.json'),(Join-Path $taskEvidence 'root-current8a-npm-tools-before.json'),$taskCandidatePath,$taskControlPath)
$taskManifests=@($taskManifestPaths|ForEach-Object{[ordered]@{name=[IO.Path]::GetFileName($_);path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskFrozen="$taskBase-frozen.json"
$taskManifests|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskFrozen -Encoding utf8NoBOM
$taskFrozenHash=(Get-FileHash -LiteralPath $taskFrozen).Hash
function Verify-Frozen {
    if((Get-FileHash -LiteralPath $taskFrozen).Hash -cne $taskFrozenHash){throw 'Frozen manifest drift'}
    $taskChecks=@()
    foreach($taskManifest in $taskManifests){
        if((Get-FileHash -LiteralPath $taskManifest.path).Hash -cne $taskManifest.sha256){throw 'Manifest identity drift'}
        $taskRows=@(Get-Content -LiteralPath $taskManifest.path -Raw|ConvertFrom-Json)
        foreach($taskRow in $taskRows){if(!(Test-Path -LiteralPath $taskRow.path -PathType Leaf) -or (Get-FileHash -LiteralPath $taskRow.path).Hash -ine $taskRow.sha256){throw "Frozen file drift $($taskRow.path)"}}
        $taskChecks+=[ordered]@{manifest=$taskManifest.name;count=$taskRows.Count;drift=0}
    }
    if($taskChecks[0].count -ne 1965 -or $taskChecks[1].count -ne 31064 -or $taskChecks[2].count -ne 1774){throw 'Original complete inventory mismatch'}
    return $taskChecks
}
$taskBefore=Verify-Frozen
$taskBefore|ConvertTo-Json -Depth 5|Set-Content -LiteralPath "$taskBase-before.json" -Encoding utf8NoBOM
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1024
[ordered]@{minimum_free_bytes=2GB;available_bytes=$taskFree;checked_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath "$taskBase-admission.json" -Encoding utf8NoBOM
if($taskFree -lt 2GB){throw 'Source2GiB admission rejected'}
$taskFailure=$null
try{& $taskOwner -Executable 'C:/Program Files/nodejs/node.exe' -WorkingDirectory $taskSource -Arguments @('--expose-gc','--max-old-space-size=256','--conditions=source','--experimental-transform-types','--import',([uri]$taskObserver).AbsoluteUri,$taskCapture,"$taskBase-output.json",$taskInput,$taskFrozen,$taskFixture) -ReceiptBase $taskBase -TimeoutSeconds 300}catch{$taskFailure=$_}
$taskAfter=Verify-Frozen
$taskAfter|ConvertTo-Json -Depth 5|Set-Content -LiteralPath "$taskBase-after.json" -Encoding utf8NoBOM
if($taskFailure){throw $taskFailure}
$taskOutput=Get-Content -LiteralPath "$taskBase-output.json" -Raw|ConvertFrom-Json
if($taskOutput.cases -ne 28 -or $taskOutput.rows.Count -ne 28){throw 'Original28 inventory mismatch'}
Write-Output "ACTUAL_EDIT_DIFF28_SOURCE_PASSED candidate=$($taskCandidate.Count)"
