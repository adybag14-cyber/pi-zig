$taskEvidence='C:/Users/adyba/pi-zig-update-evidence-20261003'
$ErrorActionPreference='Stop'
$taskPrivate='C:/Users/adyba/pi-zig-sdk-events-hosted-20261013'
$taskBundle=Join-Path $taskEvidence 'sdk-legacy32-original-7453-20261014/audited-proof'
$taskRoot='C:/Users/adyba/pi-zig-update-evidence-20261003/sdk-legacy32-original-7453-20261014'
$taskLocalSource='C:/Users/adyba/pi-upstream-source-b45e0eb-20261014'
$taskRows=@();$taskPayload=$null
[void](New-Item -ItemType Directory -Path $taskBundle -Force)
Copy-Item -LiteralPath (Join-Path $taskPrivate 'verification/sdk-highlight-inherit-original-b45e0eb-20261014/legacy32/original-win32-32.json') -Destination (Join-Path $taskBundle 'original-win32-32.json')
foreach($taskDirectory in (Get-ChildItem -LiteralPath $taskRoot -Directory|Where-Object Name -ne 'audited-proof')){
    $taskResult=Get-Content -LiteralPath (Join-Path $taskDirectory.FullName 'result.json') -Raw|ConvertFrom-Json
    if($taskResult.head -cne '7453d4d616fa5ac7a91831d7e2db32f00851675d' -or $taskResult.source -cne 'b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb' -or $taskResult.source_files -ne 1965 -or @($taskResult.posthash|Where-Object{$_.drift.Count}).Count){throw 'Retry result identity/posthash mismatch'}
    $taskManifest=@{};$taskSourceDrift=@();$taskManifestProof=@()
    foreach($taskKind in @('source','dependencies','node-tools','candidate')){
        $taskManifestPath=Join-Path $taskDirectory.FullName "$taskKind-before.json"
        $taskItems=@(Get-Content -LiteralPath $taskManifestPath -Raw|ConvertFrom-Json)
        $taskManifestProof += [ordered]@{kind=$taskKind;count=$taskItems.Count;artifact_file="$taskKind-before.json";sha256=(Get-FileHash -LiteralPath $taskManifestPath).Hash}
        foreach($taskItem in $taskItems){
            $taskManifest[$taskItem.path]=$taskItem.sha256
            if($taskKind -eq 'source'){
                $taskIndex=$taskItem.path.IndexOf('/.reference-source/')
                if($taskIndex -lt 0){throw 'Original Source root mapping absent'}
                $taskRelative=$taskItem.path.Substring($taskIndex+'/.reference-source/'.Length)
                $taskCurrent=Join-Path $taskLocalSource $taskRelative
                if(!(Test-Path -LiteralPath $taskCurrent -PathType Leaf) -or (Get-FileHash -LiteralPath $taskCurrent).Hash -cne $taskItem.sha256){$taskSourceDrift+=$taskRelative}
            }
        }
    }
    if($taskSourceDrift.Count){throw "Original full Source mismatch $($taskSourceDrift[0])"}
    $taskCaptures=@();$taskOwners=@()
    foreach($taskAttempt in @('first','second')){
        $taskOutputPath=Join-Path $taskDirectory.FullName "legacy32-$taskAttempt-output.json"
        $taskCapture=Get-Content -LiteralPath $taskOutputPath -Raw|ConvertFrom-Json
        if($taskCapture.sourceHead -cne 'b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb' -or $taskCapture.inputSha256 -cne 'cc9ac874e371ab2e28952fd9a4de75f5fc9b9bee4a8276f9a7c748903f639769' -or $taskCapture.rows.Count -ne 32 -or $taskCapture.cases -ne 32){throw 'Retry original complete case/factory/input mismatch'}
        foreach($taskObserved in @($taskCapture.observedModules|Where-Object{$_.kind -eq 'observed-module'})){if(!$taskManifest.ContainsKey($taskObserved.path) -or $taskManifest[$taskObserved.path] -ine $taskObserved.sha256){throw 'Observed module not frozen/hash mismatch'}}
        if($taskManifest[$taskCapture.node.path] -ine $taskCapture.node.sha256 -or $taskCapture.node.version -cne 'v24.14.0'){throw 'Actual Node identity mismatch'}
        $taskOwnerPath=Join-Path $taskDirectory.FullName "legacy32-$taskAttempt.process.json"
        $taskOwner=Get-Content -LiteralPath $taskOwnerPath -Raw|ConvertFrom-Json
        if($taskOwner.status -cne 'passed' -or $taskOwner.exit_code -ne 0 -or $taskOwner.outer_seconds -ne 300 -or $taskOwner.settle_seconds -ne 10 -or $taskOwner.executable_sha256 -ine $taskCapture.node.sha256){throw 'Retry capture owner mismatch'}
        $taskRepoOwner="original-$($taskCapture.platform)-$taskAttempt.process.json"
        Copy-Item -LiteralPath $taskOwnerPath -Destination (Join-Path $taskBundle $taskRepoOwner)
        Copy-Item -LiteralPath (Join-Path $taskDirectory.FullName "legacy32-$taskAttempt-posthash.json") -Destination (Join-Path $taskBundle "original-$($taskCapture.platform)-$taskAttempt-posthash.json")
        $taskOwners += [ordered]@{path=$taskRepoOwner;sha256=(Get-FileHash -LiteralPath $taskOwnerPath).Hash;pid=$taskOwner.pid;status=$taskOwner.status;outer_seconds=$taskOwner.outer_seconds;created_utc=$taskOwner.created_utc;completed_utc=$taskOwner.completed_utc}
        $taskPost=Get-Content -LiteralPath (Join-Path $taskDirectory.FullName "legacy32-$taskAttempt-posthash.json") -Raw|ConvertFrom-Json
        if(@($taskPost.before|Where-Object{$_.drift.Count}).Count -or @($taskPost.after|Where-Object{$_.drift.Count}).Count -or $taskPost.before.Count -ne 4 -or $taskPost.after.Count -ne 4){throw 'Complete capture before/after manifest drift'}
        if(!$taskCapture.actualNodeGcExecuted -or '--expose-gc' -notin $taskCapture.node.execArgv){throw 'Actual GC execution or explicit Node GC switch absent'}
        $taskCore=@($taskCapture.observedModules|Where-Object{$_.kind -eq 'observed-module' -and $_.path.EndsWith('/node_modules/highlight.js/lib/core.js')})
        if($taskCore.Count -ne 1){throw 'Actual original highlight core module absent'}
        $taskCaptures+=$taskCapture
    }
    $taskFirst=$taskCaptures[0].rows|ConvertTo-Json -Depth 100 -Compress
    $taskWindows=Get-Content -LiteralPath (Join-Path $taskBundle 'original-win32-32.json') -Raw|ConvertFrom-Json
    if($taskFirst -cne ($taskWindows.rows|ConvertTo-Json -Depth 100 -Compress)){throw 'Actual Linux/macOS/Windows raw rows differ'}
    if($taskFirst -cne ($taskCaptures[1].rows|ConvertTo-Json -Depth 100 -Compress)){throw 'Original retry double capture mismatch'}
    if($null -eq $taskPayload){$taskPayload=$taskFirst}elseif($taskPayload -cne $taskFirst){throw 'Original retry Linux/macOS rows mismatch'}
    Copy-Item -LiteralPath (Join-Path $taskDirectory.FullName 'legacy32-first-output.json') -Destination (Join-Path $taskBundle "original-$($taskCaptures[0].platform)-legacy3232.json")
    $taskRows += [ordered]@{artifact=$taskDirectory.Name;platform=$taskCaptures[0].platform;arch=$taskCaptures[0].arch;cases=32;source_files=1965;source_matches_local_authority=1965;dependency_files=$taskResult.dependency_files;node_tool_files=$taskResult.node_tool_files;candidate_files=$taskResult.candidate_files;source_drift=0;post_drift=0;observed_modules_first=@($taskCaptures[0].observedModules|Where-Object{$_.kind -eq 'observed-module'}).Count;observed_modules_second=@($taskCaptures[1].observedModules|Where-Object{$_.kind -eq 'observed-module'}).Count;double_capture_identical=$true;node_sha256=$taskCaptures[0].node.sha256;first_capture_sha256=(Get-FileHash -LiteralPath (Join-Path $taskDirectory.FullName 'legacy32-first-output.json')).Hash;second_capture_sha256=(Get-FileHash -LiteralPath (Join-Path $taskDirectory.FullName 'legacy32-second-output.json')).Hash;owner_receipts=$taskOwners;full_manifest_hashes=$taskManifestProof}
}
if($taskRows.Count -ne 2){throw 'Complete Original Linux/macOS pair absent'}
$taskProof=[ordered]@{windows_linux_macos_raw_rows_identical=$true;status='genuine_b45_original_Legacy32_actual_Linux_macOS_double_captures_qualified';run_id=38645228006;url='https://github.com/adybag14-cyber/pi-zig/actions/runs/38645228006';head='7453d4d616fa5ac7a91831d7e2db32f00851675d';source='b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb';input_sha256='cc9ac874e371ab2e28952fd9a4de75f5fc9b9bee4a8276f9a7c748903f639769';cases=32;linux_macos_raw_rows_identical=$true;source_body_rewrites=0;raw_normalizations=0;catalog_scope='Pinned official439c5347 typed metadata; latest generated model catalog gate remains separate';captures=$taskRows;native_qualification='Native32 six-profile run38645227942 still pending; no full native qualification from this reference proof';root_worktree_edits=0;public_activation=$false;verified_utc=[DateTimeOffset]::UtcNow.ToString('o')}
$taskProof|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $taskBundle 'source-qualification.json') -Encoding utf8NoBOM
$taskRows|ForEach-Object{"$($_.platform) cases32 source1965 deps=$($_.dependency_files) Node=$($_.node_tool_files) candidate=$($_.candidate_files) modules=$($_.observed_modules_first)/$($_.observed_modules_second) drift0"}
