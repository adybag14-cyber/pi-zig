param([ValidateSet('renderers','statistics')][string]$Task='renderers')
$ErrorActionPreference='Stop'
$taskCandidate=(Get-Location).Path
$taskSource=Join-Path $taskCandidate '.reference-source'
$taskBundle=Join-Path $taskCandidate 'verification/sdk-renderers-posix-original-1692bba-20261014'
$taskReceipts=Join-Path $taskCandidate $(if($Task -eq 'statistics'){'verification/sdk-statistics-original-result'}else{'verification/sdk-renderers-posix-original-result'})
[void](New-Item -ItemType Directory -Path $taskReceipts -Force)
$taskNode=(Get-Command node).Source
if((& $taskNode --version).Trim() -cne 'v24.14.0'){throw 'Original Node pin mismatch'}
if((git -C $taskSource rev-parse HEAD).Trim() -cne '1692bba6347a287ab0f3cb554a4430fafffc474b'){throw 'Original Source head mismatch'}
if((git rev-parse HEAD).Trim() -cne $env:GITHUB_SHA){throw 'Capture candidate head mismatch'}
function Available-SourceBytes {
    if($IsWindows){return [long](Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1024}
    if($IsLinux){$taskText=Get-Content -LiteralPath '/proc/meminfo' -Raw;$taskMatch=[regex]::Match($taskText,'(?m)^MemAvailable:\s+(\d+) kB$');if(!$taskMatch.Success){throw 'Linux Source RAM observation absent'};return [long]$taskMatch.Groups[1].Value*1024}
    if($IsMacOS){$taskText=(& /usr/bin/vm_stat)-join [Environment]::NewLine;$taskPage=[regex]::Match($taskText,'page size of (\d+) bytes');if(!$taskPage.Success){throw 'macOS page size absent'};$taskPages=0L;foreach($taskName in @('Pages free','Pages inactive','Pages speculative')){$taskMatch=[regex]::Match($taskText,[regex]::Escape($taskName)+':\s+(\d+)\.');if(!$taskMatch.Success){throw 'macOS Source RAM observation absent'};$taskPages += [long]$taskMatch.Groups[1].Value};return $taskPages*[long]$taskPage.Groups[1].Value}
    throw 'Unsupported Source oracle platform'
}
if((Available-SourceBytes) -lt 2GB){throw 'Original hydration2GiB admission rejected'}
$taskCatalog=Join-Path $taskBundle 'models-all-pinned-439c5347.json'
if((Get-FileHash -LiteralPath $taskCatalog).Hash -cne '439C53478C84ED27A58F8B54E1C3BD45810E5A969515B4E3666A3898D51EE22F'){throw 'Official metadata pin drift'}
$taskInitial=@(Get-Content -LiteralPath (Join-Path $taskReceipts 'tracked-initial.json') -Raw|ConvertFrom-Json)
foreach($taskRow in $taskInitial){if((Get-FileHash -LiteralPath $taskRow.path).Hash -cne $taskRow.sha256){throw 'Tracked Source changed during npm ci'}}
$env:NODE_OPTIONS='';$env:NODE_PATH=''
& (Join-Path $taskCandidate 'verification/sdk-session-loadout-e6220e1-20261013/run-native-owner.ps1') -Executable $taskNode -WorkingDirectory $taskSource -Arguments @('--max-old-space-size=128',(Join-Path $taskSource 'packages/ai/scripts/hydrate-model-catalog.ts'),$taskCatalog) -ReceiptBase (Join-Path $taskReceipts 'official-hydration') -TimeoutSeconds 300
foreach($taskRow in $taskInitial){if((Get-FileHash -LiteralPath $taskRow.path).Hash -cne $taskRow.sha256){throw 'Original hydration changed tracked Source'}}
$taskHydrated=@(Get-ChildItem -LiteralPath (Join-Path $taskSource 'packages/ai/src/providers/data') -File -Force|ForEach-Object{[ordered]@{path=$_.FullName;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}})
if($taskInitial.Count -ne 1912 -or $taskHydrated.Count -ne 43){throw 'Complete original Source inventory changed'}
$taskSourceRows=@($taskInitial+$taskHydrated)
$taskWorkspaces=@(Get-Content -LiteralPath (Join-Path $taskBundle 'workspaces.json') -Raw|ConvertFrom-Json)
$taskModuleRoots=@((Join-Path $taskSource 'node_modules');$taskWorkspaces|ForEach-Object{Join-Path $taskSource "$($_.path)/node_modules"})|Where-Object{Test-Path -LiteralPath $_ -PathType Container}
$taskDependencyPaths=@($taskModuleRoots|ForEach-Object{Get-ChildItem -LiteralPath $_ -File -Recurse -Force|Where-Object{!$_.LinkType}|ForEach-Object FullName})|Sort-Object -Unique
$taskDependencies=@($taskDependencyPaths|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
if($taskDependencies.Count -lt 1000){throw 'Complete dependency inventory absent'}
$taskNodeRoot=Split-Path -Parent (Split-Path -Parent $taskNode)
$taskNodePaths=@($taskNode;Get-ChildItem -LiteralPath $taskNodeRoot -File -Recurse -Force|Where-Object{!$_.LinkType}|ForEach-Object FullName)|Sort-Object -Unique
$taskNodeTools=@($taskNodePaths|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskCandidateRows=@(git ls-files|Sort-Object|ForEach-Object{$taskPath=Join-Path $taskCandidate $_;[ordered]@{path=$taskPath;sha256=(Get-FileHash -LiteralPath $taskPath).Hash}})
$taskInventories=[ordered]@{source=$taskSourceRows;dependencies=$taskDependencies;'node-tools'=$taskNodeTools;candidate=$taskCandidateRows}
foreach($taskKind in $taskInventories.Keys){@($taskInventories[$taskKind])|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $taskReceipts "$taskKind-before.json") -Encoding utf8NoBOM}
function Verify-Original {
    $taskChecks=@()
    foreach($taskKind in $taskInventories.Keys){
        $taskRows=@($taskInventories[$taskKind]);$taskDrift=@($taskRows|Where-Object{!(Test-Path -LiteralPath $_.path -PathType Leaf) -or (Get-FileHash -LiteralPath $_.path).Hash -cne $_.sha256}|ForEach-Object path)
        $taskChecks += [ordered]@{kind=$taskKind;count=$taskRows.Count;drift=$taskDrift}
        if($taskDrift.Count){throw "Frozen Original $taskKind drift $($taskDrift[0])"}
    }
    return $taskChecks
}
$taskObserverUri=[UriBuilder]::new();$taskObserverUri.Scheme='file';$taskObserverUri.Host='';$taskObserverUri.Port=-1;$taskObserverUri.Path=Join-Path $taskBundle 'observe-original.mjs'
$env:PI_RENDERER_SOURCE_ROOT=$taskSource;$env:PI_RENDERER_CANDIDATE_ROOT=$taskCandidate;$env:PI_RENDERER_RECEIPTS=$taskReceipts
$taskResults=@()
$taskFamilies=if($Task -eq 'statistics'){@('statistics')}else{@('listing','shell')}
foreach($taskFamily in $taskFamilies){
    $taskInput=if($Task -eq 'statistics'){Join-Path $taskCandidate 'verification/sdk-statistics-original-1692bba-20261014/sdk-session-statistics-1692.input.txt'}else{Join-Path $taskCandidate "src/extensions/fixtures/sdk-tool-$taskFamily-renderers-e622.input.txt"}
    $taskCaptureScript=if($Task -eq 'statistics'){Join-Path $taskCandidate 'verification/sdk-statistics-original-1692bba-20261014/capture-statistics.mjs'}else{Join-Path $taskBundle 'capture-original.mjs'}
    $taskCaptures=@()
    foreach($taskAttempt in @('first','second')){
        $taskBase=Join-Path $taskReceipts "$taskFamily-$taskAttempt"
        $taskBefore=Verify-Original
        [GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect()
        $taskFree=Available-SourceBytes
        [ordered]@{minimum_free_bytes=2GB;available_bytes=$taskFree;checked_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath "$taskBase-admission.json" -Encoding utf8NoBOM
        if($taskFree -lt 2GB){throw 'Original Source2GiB admission rejected'}
        $taskFailure=$null
        $taskCaptureTail=if($Task -eq 'statistics'){@($taskCaptureScript,"$taskBase-output.json",$taskInput)}else{@($taskCaptureScript,$taskFamily,"$taskBase-output.json",$taskInput)}
        $taskCaptureArgs=@('--max-old-space-size=256','--conditions=source','--experimental-transform-types','--import',($taskObserverUri.Uri.AbsoluteUri))+$taskCaptureTail
        try{& (Join-Path $taskCandidate 'verification/sdk-session-loadout-e6220e1-20261013/run-native-owner.ps1') -Executable $taskNode -WorkingDirectory $taskSource -Arguments $taskCaptureArgs -ReceiptBase $taskBase -TimeoutSeconds 300}catch{$taskFailure=$_}
        $taskAfter=Verify-Original
        [ordered]@{before=$taskBefore;after=$taskAfter;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath "$taskBase-posthash.json" -Encoding utf8NoBOM
        if($taskFailure){throw $taskFailure}
        $taskCaptures += Get-Content -LiteralPath "$taskBase-output.json" -Raw|ConvertFrom-Json
    }
    $taskFirst=$(if($Task -eq 'statistics'){$taskCaptures[0].rows}else{$taskCaptures[0].raw})|ConvertTo-Json -Depth 100 -Compress
    $taskSecond=$(if($Task -eq 'statistics'){$taskCaptures[1].rows}else{$taskCaptures[1].raw})|ConvertTo-Json -Depth 100 -Compress
    if($taskFirst -cne $taskSecond){throw "Original $taskFamily raw double capture drift"}
    $taskMatchesWindows=$null
    if($Task -ne 'statistics'){$taskWindows=Get-Content -LiteralPath (Join-Path $taskCandidate "src/extensions/fixtures/sdk-tool-$taskFamily-renderers-e622.json") -Raw|ConvertFrom-Json;$taskMatchesWindows=$taskFirst -ceq ($taskWindows|ConvertTo-Json -Depth 100 -Compress)}
    $taskResults += [ordered]@{family=$taskFamily;platform=$taskCaptures[0].platform;arch=$taskCaptures[0].arch;cases=$taskCaptures[0].cases;double_capture_identical=$true;windows_raw_equivalent=$taskMatchesWindows;first_sha256=(Get-FileHash -LiteralPath (Join-Path $taskReceipts "$taskFamily-first-output.json")).Hash;second_sha256=(Get-FileHash -LiteralPath (Join-Path $taskReceipts "$taskFamily-second-output.json")).Hash}
}
$taskPost=Verify-Original
[ordered]@{status=$(if($Task -eq 'statistics'){'genuine_original_statistics36_double_captures_completed'}else{'genuine_original_renderer_double_captures_completed'});head=$env:GITHUB_SHA;source='1692bba6347a287ab0f3cb554a4430fafffc474b';source_files=$taskSourceRows.Count;dependency_files=$taskDependencies.Count;node_tool_files=$taskNodeTools.Count;candidate_files=$taskCandidateRows.Count;catalog_scope='Pinned official439c5347 typed metadata; latest generated model catalog gate remains separate';families=$taskResults;posthash=$taskPost;public_activation=$false;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskReceipts 'result.json') -Encoding utf8NoBOM
