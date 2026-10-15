param([ValidateSet('build','test')][string]$Phase='build',[string]$Attempt='first',[string]$Step='native-edit-diff-source')
$ErrorActionPreference='Stop'
$taskRoot='C:/Users/adyba/pi-zig-tool-render-20261015'
$taskEvidence='C:/Users/adyba/pi-zig-update-evidence-20261003'
$taskName="tool-render-edit54-debug-$Phase-$Attempt-20261015"
$taskBase=Join-Path $taskEvidence $taskName
$taskOwner=Join-Path $PSScriptRoot 'run-owner.ps1'
function Candidate-Rows {
    @(git -C $taskRoot ls-files --cached --others --exclude-standard | Sort-Object -Unique | ForEach-Object { $taskFile=Join-Path $taskRoot $_; [ordered]@{path=$taskFile;sha256=(Get-FileHash -LiteralPath $taskFile).Hash} })
}
$taskCandidate=Candidate-Rows
$taskCandidatePath="$taskBase-candidate.json"
$taskCandidate|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskCandidatePath -Encoding utf8NoBOM
$taskVendor=@(Get-ChildItem -LiteralPath (Join-Path $taskRoot 'vendor') -File -Recurse -Force|ForEach-Object{[ordered]@{path=$_.FullName;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}})
$taskVendorPath="$taskBase-vendor.json"
$taskVendor|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskVendorPath -Encoding utf8NoBOM
$taskToolsPath=Join-Path $taskEvidence 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json'
$taskTools=@((Get-Content -LiteralPath $taskToolsPath -Raw|ConvertFrom-Json).inputs)
$taskToolRows="$taskBase-tools.json"
$taskTools|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskToolRows -Encoding utf8NoBOM
$taskControls=@($PSCommandPath,$taskOwner,$taskToolsPath)|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}}
$taskControlPath="$taskBase-controls.json"
$taskControls|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskControlPath -Encoding utf8NoBOM
$taskManifestPaths=@((Join-Path $taskEvidence 'sdk-source-b45-full-manifest-20261014.json'),(Join-Path $taskEvidence 'durable-19cb534-reference-20261012-all-built-runtime.json'),(Join-Path $taskEvidence 'root-current8a-npm-tools-before.json'),$taskCandidatePath,$taskVendorPath,$taskToolRows,$taskControlPath)
$taskManifests=@($taskManifestPaths|ForEach-Object{[ordered]@{name=[IO.Path]::GetFileName($_);path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
function Verify-Frozen {
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
$taskExisting=@(Get-CimInstance Win32_Process|Where-Object{$_.ExecutablePath -and ($_.ExecutablePath.EndsWith('\zig.exe') -or $_.ExecutablePath -like 'C:\Users\adyba\pi-zig*\.zig-cache\*\build.exe' -or $_.ExecutablePath -like 'C:\Users\adyba\pi-zig*\.zig-cache\*\test.exe')})
$taskIds=@($taskExisting|ForEach-Object ProcessId)
$taskRoots=@($taskExisting|Where-Object{$_.ParentProcessId -notin $taskIds})
[ordered]@{minimum_free_bytes=16GB;available_bytes=$taskFree;existing_native_roots=$taskRoots.Count;existing_native_processes=@($taskExisting|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine,CreationDate);checked_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath "$taskBase-admission.json" -Encoding utf8NoBOM
if($taskFree -lt 16GB -or $taskRoots.Count -ge 4){throw 'Normal16GiB/max4 native root admission rejected'}
$taskFailure=$null
try{& $taskOwner -Executable 'C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0/zig.exe' -WorkingDirectory $taskRoot -Arguments @('build',"$Phase-$Step",'-Doptimize=Debug','-j1','--test-timeout','120s','--summary','all') -ReceiptBase $taskBase -TimeoutSeconds $(if($Phase -eq 'build'){1320}else{300})}catch{$taskFailure=$_}
$taskAfter=Verify-Frozen
$taskAfter|ConvertTo-Json -Depth 5|Set-Content -LiteralPath "$taskBase-after.json" -Encoding utf8NoBOM
$taskCandidateAfter=Candidate-Rows
if(@(Compare-Object ($taskCandidate|ForEach-Object{"$($_.path):$($_.sha256)"}) ($taskCandidateAfter|ForEach-Object{"$($_.path):$($_.sha256)"})).Count){throw 'Candidate inventory drift'}
if($taskFailure){throw $taskFailure}
Write-Output "NATIVE_EDIT54_$($Phase.ToUpper())_PASSED candidate=$($taskCandidate.Count) vendor=$($taskVendor.Count) toolchain=$($taskTools.Count)"
