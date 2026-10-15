#requires -Version 7.0
[CmdletBinding()]
param([string]$PackageDirectory=$PSScriptRoot,[string]$ExtractTo='')
$ErrorActionPreference='Stop'
$candidate='aea5f178efdd3105d903553c8f5ff82bfbb25ea3'
$cHash='47996DFE76080EEA68B13214B3D2EC351B8B0C4BDF759CD06084ABA9920F81EF'
$evidence='C:/Users/adyba/pi-zig-update-evidence-20261003'
$audit="$evidence/highlight15-dispatch-audit-20261015"
$native='C:/Users/adyba/pi-zig-sdk-events-hosted-20261013'
function Require([bool]$condition,[string]$message){if(!$condition){throw $message}}
function Key([string]$path){$path.Replace('\','/').TrimEnd('/').ToUpperInvariant()}
function Digest([byte[]]$bytes){[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))}
$descriptor=Get-Content -LiteralPath (Join-Path $PackageDirectory 'package.json') -Raw|ConvertFrom-Json
Require ($descriptor.candidate -ceq $candidate -and $descriptor.c_sha256 -ceq $cHash) 'Package scope mismatch'
Require ((Get-FileHash -LiteralPath $PSCommandPath).Hash -ceq $descriptor.verifier_sha256) 'Verifier SHA256 mismatch'
Require ($descriptor.archive -cmatch '^[A-Za-z0-9._-]+\.zip$') 'Unsafe archive name'
$archivePath=Join-Path $PackageDirectory $descriptor.archive
Require ((Get-FileHash -LiteralPath $archivePath).Hash -ceq $descriptor.archive_sha256) 'Archive SHA256 mismatch'
$zip=[IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    function ZipBytes([string]$name){
        $entry=$zip.GetEntry($name);Require ($null -ne $entry) "Missing ZIP entry: $name"
        $stream=$entry.Open();$memory=[IO.MemoryStream]::new()
        try{$stream.CopyTo($memory);return ,$memory.ToArray()}finally{$stream.Dispose();$memory.Dispose()}
    }
    $indexBytes=ZipBytes 'index.json'
    Require ((Digest $indexBytes) -ceq $descriptor.index_sha256) 'Index SHA256 mismatch'
    $index=[Text.Encoding]::UTF8.GetString($indexBytes)|ConvertFrom-Json
    Require ($index.candidate -ceq $candidate -and $index.c_sha256 -ceq $cHash) 'Archived scope mismatch'
    $files=@{};$objects=@{};$archiveNames=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($entry in $zip.Entries){Require ($archiveNames.Add($entry.FullName)) 'Duplicate ZIP entry'}
    foreach($file in $index.files){
        $key=Key $file.original_path
        Require (!$files.ContainsKey($key)) "Duplicate original path: $key"
        Require ($file.sha256 -cmatch '^[0-9A-F]{64}$' -and $file.length -ge 0) 'Invalid object identity'
        $files[$key]=$file;$objects[$file.sha256]=$file.length
    }
    Require ($files.Count -eq $descriptor.original_files -and $objects.Count -eq $descriptor.distinct_objects) 'Archive object count mismatch'
    Require ($zip.Entries.Count -eq $objects.Count+1) 'Unindexed ZIP entries'
    # Independently reopen every unique object. Every original path resolves to one
    # of these verified objects, including empty logs and repeated inventories.
    foreach($hash in $objects.Keys){
        $bytes=ZipBytes "objects/$hash.bin"
        Require ($bytes.Length -eq $objects[$hash] -and (Digest $bytes) -ceq $hash) "Corrupt archived object: $hash"
    }
    function Record([string]$path){$key=Key $path;Require ($files.ContainsKey($key)) "Missing original record: $path";return $files[$key]}
    function Bytes([string]$path){$record=Record $path;return ,(ZipBytes "objects/$($record.sha256).bin")}
    function Json([string]$path){[Text.Encoding]::UTF8.GetString((Bytes $path)).TrimStart([char]0xFEFF)|ConvertFrom-Json}
    function Text([string]$path){[Text.Encoding]::UTF8.GetString((Bytes $path))}
    function HashIs([string]$path,[string]$expected){Require ((Record $path).sha256 -ceq $expected.ToUpperInvariant()) "Referenced digest mismatch: $path"}
    $proofPath="$audit/core-gpa-full-aea5-final.validation.json"
    HashIs $proofPath 'F9EB88656DF93E14314EB202113A10E55386EE87E651969F52DDB13026309217'
    $proof=Json $proofPath
    Require ($proof.status -ceq 'qualified' -and $proof.candidate -ceq $candidate -and $proof.c_sha256 -ceq $cHash) 'Final proof identity mismatch'
    Require ($proof.full_GPA_complete -and !$proof.C_VM_exhaustive_malloc_qualified -and !$proof.all191_qualified -and !$proof.public_activation) 'Qualification scope was broadened'
    Require ($proof.baseline -eq 22272 -and $proof.ranges -eq 250 -and $proof.covered_indices -eq 22272) 'Wrong failure universe'
    HashIs "$audit/Validate-NativeHighlightFullGPA-aea5-20261015.ps1" $proof.validator_sha256
    HashIs "$audit/core-gpa-mixed-oom-r4-controls.json" $proof.controls_sha256
    $controls=@(Json "$audit/core-gpa-mixed-oom-r4-controls.json")
    Require ($controls.Count -eq 18) 'Incomplete final controls'
    foreach($control in $controls){HashIs $control.path $control.sha256}
    $canonical="$evidence/native-highlight-core-gpa128-oom-gpa-1-20261015"
    $source=@(Json "$canonical-source-before.json")
    $vendor=@(Json "$canonical-vendor-before.json")
    $original=@(Json "$canonical-original-before.json")
    $compiler=Json "$evidence/durable-latest89-full-inspect-53ae-tool-prehash-20261011.json"
    Require ($source.Count -eq 5523 -and $vendor.Count -eq 1319 -and $original.Count -eq 1965 -and @($compiler.inputs).Count -eq 19546) 'Frozen inventory count mismatch'
    $cRow=@($source|Where-Object {$_.path -ceq 'vendor/quickjs/quickjs.c'})
    Require ($cRow.Count -eq 1 -and $cRow[0].sha256 -ceq $cHash) 'Frozen candidate C mismatch'
    HashIs "$native/vendor/quickjs/quickjs.c" $cHash
    # Source state includes preserved unrelated WIP. These inventories describe
    # the actual tested tree; the code checkpoint remains exact AEA5.
    foreach($fixture in @('sdk-highlight-core-b45.input.txt','sdk-highlight-core-b45.json','sdk-highlight-deep7-b45.input.txt','sdk-highlight-deep7-b45.json','sdk-highlight-legacy32-b45.input.txt','sdk-highlight-legacy32-b45.json')){
        $relative="src/extensions/fixtures/$fixture"
        $row=@($source|Where-Object {$_.path -ceq $relative})
        Require ($row.Count -eq 1) "Missing frozen fixture $fixture"
        HashIs "$native/$relative" $row[0].sha256
    }
    $begins=[int[]]::new(22272);$completes=[int[]]::new(22272);$cursor=0
    $rows=@($proof.range_proofs|Sort-Object -Property @{Expression={[int]$_.start};Ascending=$true})
    Require ($rows.Count -eq 250) 'Range proof count mismatch'
    foreach($row in $rows){
        $parts=[int]$row.parts;$shard=[int]$row.shard;$start=[int]$row.start;$end=[int]$row.end;$width=[int](22272/$parts)
        Require ($parts -in @(128,256) -and $start -eq $cursor -and $start -eq $shard*$width -and $end -eq ($shard+1)*$width -and $row.indices -eq $width) 'Range gap, overlap or arithmetic mismatch'
        $cursor=$end
        $tag=if($parts -eq 256 -and $shard -ge 190 -and $shard -le 252){'-r4'}elseif($parts -eq 256 -and $shard -ge 174 -and $shard -le 189){'-r3'}elseif($parts -eq 256 -and $shard -ge 19 -and $shard -le 173){'-r2'}else{''}
        $base="$evidence/native-highlight-core-gpa$parts-oom$tag-gpa-$shard-20261015"
        HashIs "$base.validation.json" $row.validation_sha256
        HashIs "$base.process.json" $row.process_sha256
        HashIs "$base-posthash.json" $row.posthash_sha256
        HashIs "$base-controls-before.json" $row.controls_sha256
        HashIs "$base.stderr.log" $row.stderr_sha256
        $validation=Json "$base.validation.json";$process=Json "$base.process.json";$post=Json "$base-posthash.json"
        Require ($validation.status -ceq 'qualified_range' -and $validation.candidate -ceq $candidate -and $validation.shard -eq $shard -and $validation.shards -eq $parts -and $validation.start -eq $start -and $validation.end -eq $end -and $validation.total -eq 22272 -and $validation.complete_indices -eq $width) 'Range validation mismatch'
        Require ($process.status -ceq 'passed' -and $process.exit_code -eq 0 -and $process.outer_seconds -eq 300 -and $process.settle_seconds -eq 10 -and $process.argv -contains '-j1' -and $process.argv -contains '120s' -and $process.executable_sha256 -ceq '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864') 'Native terminal, compiler or bounds mismatch'
        foreach($field in @('source_drift','vendor_drift','original_drift','tool_drift','control_drift')){Require ($post.$field -eq 0) "Posthash drift: $field"}
        Require ($post.source -eq 5523 -and $post.vendor -eq 1319 -and $post.original -eq 1965 -and $post.tools -eq 19546 -and $post.controls -eq 4) 'Posthash inventory mismatch'
        foreach($part in @('source-before','vendor-before','original-before')){Require ((Record "$base-$part.json").sha256 -ceq (Record "$canonical-$part.json").sha256) "Cross-range $part mismatch"}
        $snapshot=@(Json "$base-controls-before.json");Require ($snapshot.Count -eq 4) 'Incomplete range controls'
        foreach($control in $snapshot){HashIs $control.path $control.sha256}
        $log=Text "$base.stderr.log"
        Require ($log.Contains('EXHAUSTIVE_ALLOCATION_BASELINE highlight-core-b45 total=22272')) 'Raw baseline absent'
        foreach($event in @('BEGIN','COMPLETE')){
            $matches=[regex]::Matches($log,"EXHAUSTIVE_ALLOCATION_INDEX_$event highlight-core-b45 (\d+)")
            Require ($matches.Count -eq $width) "Wrong raw $event count"
            foreach($match in $matches){$i=[int]$match.Groups[1].Value;Require ($i -ge $start -and $i -lt $end) 'Marker outside actual range';if($event -ceq 'BEGIN'){$begins[$i]++}else{$completes[$i]++}}
        }
    }
    Require ($cursor -eq 22272) 'Range union incomplete'
    for($i=0;$i -lt 22272;$i++){Require ($begins[$i] -eq 1 -and $completes[$i] -eq 1) "Index $i lacks exact-once markers"}
    $functionalPath="$audit/functional-qualified-aea5-20261015.json"
    HashIs $functionalPath 'A6290C3A60FAD028E71318E5049D1E7D92D506342188432A3FFAAE031168FD37'
    $functional=Json $functionalPath
    Require ($functional.candidate -ceq $candidate -and $functional.quickjs_sha256 -ceq $cHash -and $functional.source_authority -ceq 'b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb' -and $functional.source74_exact -and $functional.host_oom_origin_and_guest_lookalike_controls) 'Functional Source identity mismatch'
    foreach($phase in $functional.phases){
        HashIs $phase.process_receipt $phase.process_sha256;HashIs $phase.posthash $phase.posthash_sha256;HashIs $phase.stderr $phase.stderr_sha256
        $process=Json $phase.process_receipt;Require ($phase.status -ceq 'passed' -and $process.status -ceq 'passed' -and $process.exit_code -eq 0) 'Functional terminal failure'
        $post=Json $phase.posthash;foreach($field in @('source_drift','vendor_drift','original_drift','tool_drift','control_drift')){Require ($post.$field -eq 0) 'Functional posthash drift'}
    }
    foreach($fixture in $functional.fixtures){HashIs "$native/$($fixture.path)" $fixture.sha256}
    $scopeLog=Text "$evidence/native-highlight-inline32-b45-debug-scope-trusted-oom-20261015.stderr.log"
    $profileLog=Text "$evidence/native-highlight-inline32-b45-debug-profile-trusted-oom-20261015.stderr.log"
    $legacyLog=Text "$evidence/native-highlight-inline32-b45-debug-legacy32-trusted-oom-20261015.stderr.log"
    Require ($scopeLog.Contains('5/5 tests passed') -and $profileLog.Contains('3/3 tests passed') -and $legacyLog.Contains('5/5 tests passed')) 'Functional raw test count mismatch'
    Require ($profileLog.Contains('HIGHLIGHT_INLINE_PROFILE actual_source_cases=74 eager_factories=21 baseline=22272 allocated_bytes=14630410 freed_bytes=14630410 full_GPA=false')) 'Raw allocation profile mismatch'
    foreach($event in @('BEGIN','COMPLETE')){
        $legacyCounts=[int[]]::new(233)
        $matches=[regex]::Matches($legacyLog,"EXHAUSTIVE_ALLOCATION_INDEX_$event highlight-legacy-function32 (\d+)")
        Require ($matches.Count -eq 233) "Legacy32 raw $event count mismatch"
        foreach($match in $matches){$i=[int]$match.Groups[1].Value;Require ($i -ge 0 -and $i -lt 233) 'Legacy32 marker out of bounds';$legacyCounts[$i]++}
        foreach($count in $legacyCounts){Require ($count -eq 1) 'Legacy32 marker duplicate or gap'}
    }
    $vmMatch=[regex]::Match($legacyLog,'LEGACY_FUNCTION_VM_HEAP_LIMIT_COVERAGE=(\{[^\r\n]+\})')
    Require ($vmMatch.Success) 'Legacy32 raw VM budget data absent'
    $vm=$vmMatch.Groups[1].Value|ConvertFrom-Json
    Require ($vm.completed -eq 514 -and $vm.owner_leaks -eq 0 -and !$vm.exhaustive_C_malloc) 'Legacy32 targeted VM coverage mismatch'
    foreach($capture in @(@('sdk-core74-b45-gc-original-local-20261014',74),@('sdk-deep7-b45-gc-original-local-20261014',7),@('sdk-legacy32-b45-gc-original-local-20261014',32))){
        $first=Json "$evidence/$($capture[0])-first-output.json";$second=Json "$evidence/$($capture[0])-second-output.json"
        foreach($output in @($first,$second)){Require ($output.sourceHead -ceq 'b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb' -and $output.cases -eq $capture[1] -and $output.actualNodeGcExecuted) 'Genuine Source capture mismatch'}
        Require (($first.rows|ConvertTo-Json -Depth 100 -Compress) -ceq ($second.rows|ConvertTo-Json -Depth 100 -Compress)) 'Source double capture rows differ'
        foreach($attempt in @('first','second')){foreach($post in @(Json "$evidence/$($capture[0])-$attempt-after.json")){Require ($post.drift -eq 0) 'Source posthash drift'}}
    }
    $sortNegative=Json "$audit/aggregate-r4-sort-negative-diagnostic.json"
    $oldState=Json "$audit/core-gpa-mixed-oom-r4-batch.state.json"
    Require ($oldState.status -ceq 'failed') 'Old controller negative was relabeled'
    Require ((Text "$audit/mixed-oom-r4-gpa-batch.stderr.log").Contains('Mixed union gap or duplicate coverage')) 'Original sort negative missing'
    $terminal=Json "$audit/full-gpa-terminal-audit.json"
    Require ($terminal.status -ceq 'qualified' -and $terminal.indices -eq 22272 -and $terminal.wrapper_count -eq 63 -and $terminal.wrapper_failures -eq 0 -and $terminal.GPA_driver73020_absent -and $terminal.validator45196_absent) 'Final terminal audit mismatch'
    for($shard=190;$shard -le 252;$shard++){$wrapper=Json "$audit/gpa-mixed-r4-shard-$shard-owner.process.json";Require ($wrapper.status -ceq 'passed' -and $wrapper.exit_code -eq 0) 'Fresh wrapper terminal failure'}
    if($ExtractTo){
        Require (!(Test-Path -LiteralPath $ExtractTo)) 'Extraction destination must be new'
        $destination=[IO.Path]::GetFullPath($ExtractTo)
        foreach($file in $index.files){
            # Drive C and slash-delimited original path are retained beneath a
            # fresh destination; no original absolute path is written.
            $relative=$file.original_path.Replace('\','/').Replace(':','')
            Require ($relative -notmatch '(^/|(^|/)\.\.(/|$))') 'Unsafe recovered path'
            $target=[IO.Path]::GetFullPath((Join-Path $destination $relative))
            Require ($target.StartsWith($destination+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) 'Extraction escaped destination'
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))|Out-Null
            [IO.File]::WriteAllBytes($target,(Bytes $file.original_path))
        }
    }
    [ordered]@{status='qualified_portable_offline';candidate=$candidate;c_sha256=$cHash;archive_sha256=$descriptor.archive_sha256;original_files=$files.Count;distinct_objects=$objects.Count;ranges=250;indices=22272;BEGIN_exactly_once=$true;COMPLETE_exactly_once=$true;source_controls='Deep7/Core74/Legacy32';all_objects_reopened_hashed=$true;C_VM_exhaustive_malloc_qualified=$false;all191_qualified=$false;public_activation=$false}|ConvertTo-Json
}finally{$zip.Dispose()}
