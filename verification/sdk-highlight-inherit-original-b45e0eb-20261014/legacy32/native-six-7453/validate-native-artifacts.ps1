$taskEvidence='C:/Users/adyba/pi-zig-update-evidence-20261003'
$ErrorActionPreference='Stop'
$taskPrivate='C:/Users/adyba/pi-zig-sdk-events-hosted-20261013'
$taskRoot='C:/Users/adyba/pi-zig-update-evidence-20261003/sdk-legacy32-native-six-7453-20261014'
$taskBundle=Join-Path $taskEvidence 'sdk-legacy32-native-six-7453-20261014/audited-proof'
[void](New-Item -ItemType Directory -Path $taskBundle -Force)
$taskProfiles=@();$taskSourceIdentity=$null
foreach($taskDirectory in (Get-ChildItem -LiteralPath $taskRoot -Directory|Where-Object Name -ne 'audited-proof')){
    $taskResult=Get-Content -LiteralPath (Join-Path $taskDirectory.FullName 'result.json') -Raw|ConvertFrom-Json -DateKind String
    $taskSource=Get-Content -LiteralPath (Join-Path $taskDirectory.FullName 'source.json') -Raw|ConvertFrom-Json -DateKind String
    if($taskResult.head -cne '7453d4d616fa5ac7a91831d7e2db32f00851675d' -or $taskResult.status -cne 'passed' -or $taskResult.source_cases -ne 32 -or $taskResult.tests_each -ne 5 -or $taskResult.shards -ne 8 -or $taskResult.missing -ne 0 -or $taskResult.duplicates -ne 0 -or $taskResult.full_highlight_grammar_engine_qualified){throw 'Legacy32 profile/result identity mismatch'}
    $taskInputs=@(Get-Content -LiteralPath (Join-Path $taskDirectory.FullName 'inputs.json') -Raw|ConvertFrom-Json)
    $taskTools=@(Get-Content -LiteralPath (Join-Path $taskDirectory.FullName 'tools.json') -Raw|ConvertFrom-Json)
    $taskInputMap=@{};$taskToolMap=@{}
    foreach($taskInput in $taskInputs){$taskInputMap[$taskInput.path]=$taskInput.sha256}
    foreach($taskTool in $taskTools){$taskToolMap[$taskTool.path]=$taskTool.sha256}
    $taskIdentity=($taskInputs|Sort-Object path|ForEach-Object{"$($_.path):$($_.sha256)"}) -join "`n"
    if($null -eq $taskSourceIdentity){$taskSourceIdentity=$taskIdentity}elseif($taskSourceIdentity -cne $taskIdentity){throw 'Legacy32 all six complete Source inventories differ'}
    foreach($taskPath in @('vendor/quickjs/quickjs.c','vendor/quickjs/quickjs.h','src/extensions/native_legacy_function.zig','src/extensions/native_source_for_in.zig','src/extensions/native_highlight_inherit.zig','src/native_highlight_legacy32_function_test.zig','src/extensions/fixtures/sdk-highlight-legacy32-b45.input.txt','src/extensions/fixtures/sdk-highlight-legacy32-b45.json')){
        if($taskInputMap[$taskPath] -ine (Get-FileHash -LiteralPath (Join-Path $taskPrivate $taskPath)).Hash){throw 'Legacy32 qualified native body/Source input/raw expected drift'}
    }
    foreach($taskKind in @('inputs','tools')){
        $taskPost=Get-Content -LiteralPath (Join-Path $taskDirectory.FullName "$taskKind-posthash.json") -Raw|ConvertFrom-Json
        $taskCount=if($taskKind -eq 'inputs'){$taskInputs.Count}else{$taskTools.Count}
        if($taskPost.count -ne $taskCount -or $taskPost.drift.Count){throw 'Legacy32 full frozen Source/compiler posthash drift'}
    }
    $taskOwners=@();$taskPrevious=0;$taskIndices=[Collections.Generic.List[int]]::new()
    foreach($taskPhase in @('compile')+@(0..7|ForEach-Object{"shard-$_"})){
        $taskOwnerPath=Join-Path $taskDirectory.FullName "$taskPhase.process.json"
        $taskOwner=Get-Content -LiteralPath $taskOwnerPath -Raw|ConvertFrom-Json -DateKind String
        if($taskOwner.status -cne 'passed' -or $taskOwner.exit_code -ne 0 -or $taskOwner.settle_seconds -ne 10 -or $taskToolMap[$taskOwner.executable] -ine $taskOwner.executable_sha256){throw 'Legacy32 exact executable/terminal owner mismatch'}
        $taskCompile=$taskPhase -eq 'compile'
        if($taskOwner.outer_seconds -ne $(if($taskCompile){1320}else{300}) -or ($taskOwner.argv -join ' ') -cne "build $(if($taskCompile){'build'}else{'test'})-native-highlight-legacy-function32 -Doptimize=$($taskResult.mode) -j1 --test-timeout 120s --summary all"){throw 'Legacy32 exact owner argv/deadline mismatch'}
        $taskSeconds=([DateTimeOffset]::Parse($taskOwner.completed_utc).UtcDateTime-[DateTimeOffset]::Parse($taskOwner.created_utc).UtcDateTime).TotalSeconds
        $taskOwners += [ordered]@{phase=$taskPhase;pid=$taskOwner.pid;status=$taskOwner.status;outer_seconds=$taskOwner.outer_seconds;seconds=$taskSeconds;sha256=(Get-FileHash -LiteralPath $taskOwnerPath).Hash;artifact_file="$taskPhase.process.json"}
        if($taskCompile){continue}
        $taskShard=[int]$taskPhase.Substring(6)
        $taskLog=Get-Content -LiteralPath (Join-Path $taskDirectory.FullName "$taskPhase.stderr.log") -Raw
        if($taskLog -notmatch '(?m)Build Summary:.*\b5/5 tests passed'){throw 'Legacy32 original complete named/transitive inventory did not pass'}
        $taskHeapMarkers=@([regex]::Matches($taskLog,'(?m)^LEGACY_FUNCTION_VM_HEAP_LIMIT_COVERAGE=(\{[^\r\n]+\})$'))
        if($taskHeapMarkers.Count -ne 1){throw 'Legacy32 targeted VM pressure marker absent/repeated'}
        $taskHeap=$taskHeapMarkers[0].Groups[1].Value|ConvertFrom-Json
        if($taskHeap.programs -ne 2 -or $taskHeap.minimum_budget -ne 0 -or $taskHeap.maximum_budget -ne 8192 -or $taskHeap.step -ne 32 -or $taskHeap.completed -ne 514 -or $taskHeap.owner_leaks -ne 0 -or $taskHeap.exhaustive_C_malloc -or $taskHeap.trusted_OOM_classification -or $taskHeap.failures.Count -ne 2 -or $taskHeap.successes.Count -ne 2 -or @($taskHeap.failures|Where-Object{$_ -le 0}).Count -or @($taskHeap.successes|Where-Object{$_ -le 0}).Count){throw 'Legacy32 targeted VM scope/cleanup/outcomes mismatch'}
        $taskRange=@([regex]::Matches($taskLog,'(?m)^EXHAUSTIVE_ALLOCATION_RANGE highlight-legacy-function32 (\d+)/(\d+) range=\[(\d+),(\d+)\) total=(\d+)$'))
        $taskBaseline=@([regex]::Matches($taskLog,'(?m)^EXHAUSTIVE_ALLOCATION_BASELINE highlight-legacy-function32 total=(\d+)$'))
        if($taskRange.Count -ne 1 -or $taskBaseline.Count -ne 1){throw 'Legacy32 range/baseline absent or repeated'}
        $taskValues=@($taskRange[0].Groups|Select-Object -Skip 1|ForEach-Object{[int]$_.Value})
        $taskStart=$taskValues[2];$taskEnd=$taskValues[3];$taskTotal=$taskValues[4]
        if($taskValues[0] -ne $taskShard -or $taskValues[1] -ne 8 -or $taskTotal -ne $taskResult.baseline -or [int]$taskBaseline[0].Groups[1].Value -ne $taskTotal -or $taskStart -ne $taskPrevious -or $taskStart -ne [math]::Floor($taskTotal*$taskShard/8) -or $taskEnd -ne [math]::Floor($taskTotal*($taskShard+1)/8)){throw 'Legacy32 current universe baseline/range gap/overlap/change'}
        $taskBegin=@([regex]::Matches($taskLog,'(?m)^EXHAUSTIVE_ALLOCATION_INDEX_BEGIN highlight-legacy-function32 (\d+)$')|ForEach-Object{[int]$_.Groups[1].Value})
        $taskDone=@([regex]::Matches($taskLog,'(?m)^EXHAUSTIVE_ALLOCATION_INDEX_COMPLETE highlight-legacy-function32 (\d+)$')|ForEach-Object{[int]$_.Groups[1].Value})
        if($taskBegin.Count -ne ($taskEnd-$taskStart) -or $taskDone.Count -ne $taskBegin.Count){throw 'Legacy32 original allocation indices missing'}
        for($taskIndex=0;$taskIndex -lt $taskDone.Count;$taskIndex++){if($taskBegin[$taskIndex] -ne ($taskStart+$taskIndex) -or $taskDone[$taskIndex] -ne ($taskStart+$taskIndex)){throw 'Legacy32 index gap/duplicate'};$taskIndices.Add($taskDone[$taskIndex])}
        if([regex]::Matches($taskLog,[regex]::Escape("EXHAUSTIVE_ALLOCATION_COMPLETE highlight-legacy-function32 $taskShard/8 range=[$taskStart,$taskEnd) total=$taskTotal")).Count -ne 1){throw 'Legacy32 terminal exact partition marker absent'}
        $taskPrevious=$taskEnd
    }
    if($taskPrevious -ne $taskResult.baseline -or $taskIndices.Count -ne $taskResult.baseline -or @($taskIndices|Sort-Object -Unique).Count -ne $taskResult.baseline){throw 'Legacy32 complete current allocation universe did not pass'}
    $taskPrefix="$($taskResult.os)-$($taskResult.mode)"
    foreach($taskFile in @('result.json','source.json','inputs-posthash.json','tools-posthash.json')){Copy-Item -LiteralPath (Join-Path $taskDirectory.FullName $taskFile) -Destination (Join-Path $taskBundle "$taskPrefix-$taskFile")}
    $taskProfiles += [ordered]@{os=$taskResult.os;mode=$taskResult.mode;baseline=$taskResult.baseline;completed_indices=$taskIndices.Count;missing=0;duplicates=0;cases=32;tests_each=5;partitions=8;source_files=$taskInputs.Count;compiler_files=$taskTools.Count;source_post_drift=0;compiler_post_drift=0;source_manifest_sha256=(Get-FileHash -LiteralPath (Join-Path $taskDirectory.FullName 'inputs.json')).Hash;compiler_manifest_sha256=(Get-FileHash -LiteralPath (Join-Path $taskDirectory.FullName 'tools.json')).Hash;artifact=$taskDirectory.Name;owners=$taskOwners}
}
if($taskProfiles.Count -ne 6 -or @($taskProfiles|ForEach-Object{"$($_.os)/$($_.mode)"}|Sort-Object -Unique).Count -ne 6){throw 'Legacy32 complete six profiles absent'}
$taskProof=[ordered]@{status='actual_Source_Legacy32_helpers_all_six_profiles_and_complete_current_allocation_universes_qualified';run_id=38645227942;url='https://github.com/adybag14-cyber/pi-zig/actions/runs/38645227942';head='7453d4d616fa5ac7a91831d7e2db32f00851675d';source='b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb';original_source_run='ActualWindows32 explicitGC doublecapture_dee03 plus genuineLinux/macOS32 doublecaptures_run38645228006 independentlyaudited_b1e8c3e0';cases=32;native_methods=@('Isolated legacy CJS inherit Original32 contract only; ordinary strict function/VM unchanged');profiles=$taskProfiles;all_six_full_source_inventories_identical=$true;source_body_rewrites=0;original_expected_row_edits=0;compile_outer_seconds=1320;runtime_outer_seconds=300;test_seconds=120;host_await_ms=10000;public_class_metadata_qualified=$false;full_highlight_grammar_engine_qualified=$false;read_write_edit_renderers_qualified=$false;full_factory_qualified=$false;public_activation=$false;artifacts=$taskRoot;verified_utc=[DateTimeOffset]::UtcNow.ToString('o')}
$taskProof|ConvertTo-Json -Depth 15|Set-Content -LiteralPath (Join-Path $taskBundle 'qualification.json') -Encoding utf8NoBOM
$taskProfiles|ForEach-Object{"$($_.os)/$($_.mode) original32 tests5 partitions8 baseline$($_.baseline) allindices$($_.completed_indices) Source$($_.source_files)/compiler$($_.compiler_files) post0"}
