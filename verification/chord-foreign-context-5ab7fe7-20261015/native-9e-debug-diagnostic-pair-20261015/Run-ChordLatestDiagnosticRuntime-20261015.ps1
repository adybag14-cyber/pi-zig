param([Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9-]+$')][string]$Attempt,[Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$RootGrant,[Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9-]+$')][string]$CompileAttempt,[string]$PausePath='C:/Users/adyba/pi-zig-update-evidence-20261003/chord-latest-native-pause-20261015.flag')
$ErrorActionPreference='Stop'
$chordRoot='C:/Users/adyba/pi-zig-chord-foreign-context-5ab7fe7-20261015'
$chordSourceRoot='C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015'
$chordExpectedHead='9e6825df2787df4f44dbe4ba7913c66d4e6afed5'
$chordExpectedSource='5ab7fe74c400097b386662205cd93900695b8a71'
$chordEvidence=$PSScriptRoot
$chordName="chord-latest-diagnostic-debug-runtime-$Attempt-20261015"
$chordZig='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0/zig.exe'
function Assert-NotPaused {if(Test-Path -LiteralPath $PausePath){throw 'Scoped Chord native pause requested; no launch or validation'}}
function Rows($data){if($data -is [array]){@($data)}elseif($data.inputs){@($data.inputs)}elseif($data.files -is [array]){@($data.files)}else{@($data)}}
function Check-Rows($rows,[string]$root){
 $drift=[Collections.Generic.List[string]]::new();$index=0
 foreach($row in $rows){if(($index++ % 128) -eq 0){Assert-NotPaused};$path=if([IO.Path]::IsPathRooted($row.path)){$row.path}else{Join-Path $root $row.path};if(!(Test-Path -LiteralPath $path -PathType Leaf)){$drift.Add($path);continue};$stream=[IO.File]::OpenRead($path);try{$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()};if($hash -cne $row.sha256){$drift.Add($path)}}
 @($drift)
}
function Physical-Names([string]$root,[bool]$includeNodeModules){
 $files=[Collections.Generic.List[string]]::new();$directories=[Collections.Generic.Stack[string]]::new();$directories.Push($root)
 while($directories.Count){Assert-NotPaused;foreach($item in Get-ChildItem -LiteralPath $directories.Pop() -Force){if($item.Name -eq '.git' -or (!$includeNodeModules -and $item.Name -eq 'node_modules')){continue};if($item.PSIsContainer){if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0){$directories.Push($item.FullName)}}else{$files.Add([IO.Path]::GetFullPath($item.FullName))}}}
 @($files|Sort-Object -Unique)
}
Assert-NotPaused
if((git -C $chordRoot rev-parse HEAD).Trim() -cne $chordExpectedHead -or (git -C $chordSourceRoot rev-parse HEAD).Trim() -cne $chordExpectedSource){throw 'Reviewed native/Source heads changed'}
if(Test-Path -LiteralPath (Join-Path $chordEvidence "$chordName-candidate-before.json")){throw 'Refuse native compile attempt replay'}
$chordGoldenPaths=@((Join-Path $chordRoot 'src/extensions/fixtures/chord-output-original-5ab7fe7.json'),(Join-Path $chordRoot 'src/extensions/fixtures/chord-foreign-context-original-5ab7fe7.json'))
$chordGoldenHashes=@('EE67E4E925EE0784D863A3BC10D668C88EC5D229E4F34C3810CB0CF8340BF1BC','6967BB3C8A7497D2BD63B2CE922BC22272C26D792E8FFC58C530C8E5E787E419')
for($index=0;$index -lt 2;$index++){if((Get-FileHash -LiteralPath $chordGoldenPaths[$index]).Hash -cne $chordGoldenHashes[$index]){throw 'Actual double-captured Source golden intake changed'}}
$chordSourcePairPath=Join-Path $chordEvidence 'chord-latest-foreign-source-root-light3-first-20261015-pair-result.json'
$chordSourcePair=Get-Content -LiteralPath $chordSourcePairPath -Raw|ConvertFrom-Json
if($chordSourcePair.status -cne 'passed' -or $chordSourcePair.source_head -cne $chordExpectedSource -or !$chordSourcePair.output_caller_and_wrapper_unchanged -or @($chordSourcePair.double_captures|Where-Object{$_.status -cne 'passed' -or $_.cases -ne 5}).Count -or @($chordSourcePair.retained_unchanged_output_double_captures|Where-Object{$_.status -cne 'passed' -or $_.cases -ne 14}).Count){throw 'Genuine Source Output14/Foreign5 prerequisite rejected'}
$chordSets=@(
 @{name='source';manifest=(Join-Path $chordEvidence 'source5ab-full-manifest-20261015.json');count=1967;root=$chordSourceRoot},
 @{name='dependencies';manifest=(Join-Path $chordEvidence 'durable-19cb534-reference-20261012-all-built-runtime.json');count=31064;root='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'},
 @{name='node';manifest=(Join-Path $chordEvidence 'root-current8a-npm-tools-before.json');count=1774;root='C:/Program Files/nodejs'},
 @{name='compiler';manifest=(Join-Path $chordEvidence 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json');count=19546;root=(Split-Path -Parent $chordZig)}
)
foreach($set in $chordSets){$set.rows=@(Rows (Get-Content -LiteralPath $set.manifest -Raw|ConvertFrom-Json));if($set.rows.Count -ne $set.count){throw 'Full compile authority count changed'}}
$chordCurrent=@(git -C $chordRoot ls-files --cached --others --exclude-standard|Sort-Object -Unique|Where-Object{Test-Path -LiteralPath (Join-Path $chordRoot $_) -PathType Leaf}|ForEach-Object{Assert-NotPaused;[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $chordRoot $_)).Hash}})
$chordCompileName="chord-latest-diagnostic-debug-compile-$CompileAttempt-20261015"
$chordCompileResultPath=Join-Path $chordEvidence "$chordCompileName-result.json"
$chordCompileResult=Get-Content -LiteralPath $chordCompileResultPath -Raw|ConvertFrom-Json
$chordCompilePostPath=Join-Path $chordEvidence "$chordCompileName-after-freeze.json"
$chordCompilePost=Get-Content -LiteralPath $chordCompilePostPath -Raw|ConvertFrom-Json
if($chordCompileResult.status -cne 'passed' -or !$chordCompileResult.root_pid_absent -or $chordCompileResult.head -cne $chordExpectedHead -or $chordCompilePost.candidate_drift -or $chordCompilePost.candidate_inventory_drift -or $chordCompilePost.control_drift -or @($chordCompilePost.sets|Where-Object{$_.drift -or $_.inventory_drift}).Count){throw 'Native runtime requires exact compile PASS and full zero-drift post'}
$chordFrozen=@(Get-Content -LiteralPath (Join-Path $chordEvidence "$chordCompileName-candidate-before.json") -Raw|ConvertFrom-Json)
if(@(Compare-Object @($chordFrozen|ForEach-Object{$_.path+' '+$_.sha256}) @($chordCurrent|ForEach-Object{$_.path+' '+$_.sha256})).Count){throw 'Native compile frozen candidate does not match runtime admission'}
$chordFrozen|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $chordEvidence "$chordName-candidate-before.json") -Encoding utf8NoBOM
$chordControlPaths=@($PSCommandPath,$chordCompileResultPath,$chordCompilePostPath,(Join-Path $chordEvidence "$chordCompileName-controls.json"),(Join-Path $chordEvidence "$chordCompileName-candidate-before.json"),(Join-Path $chordEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'),$chordSourcePairPath,(Join-Path $chordEvidence 'chord-latest-foreign-source-root-light3-first-20261015-final-freeze.json'),(Join-Path $chordEvidence 'source5ab-dependency-contract-audit-20261015.json'))+@($chordSets.manifest)+@($chordGoldenPaths)+(Join-Path $chordEvidence "$chordName-candidate-before.json")
$chordControls=@($chordControlPaths|Sort-Object -Unique|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$chordCompileControls=@(Get-Content -LiteralPath (Join-Path $chordEvidence "$chordCompileName-controls.json") -Raw|ConvertFrom-Json)
if(@(Check-Rows $chordCompileControls '').Count){throw 'Compile controls drift before native runtime'}
$chordControls=@($chordControls)+@($chordCompileControls)
$chordControlsPath=Join-Path $chordEvidence "$chordName-controls.json"
$chordControls|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $chordControlsPath -Encoding utf8NoBOM
$chordControlsHash=(Get-FileHash -LiteralPath $chordControlsPath).Hash
function Assert-Frozen([string]$Phase){
 Assert-NotPaused
 $changed=@(Check-Rows $chordFrozen $chordRoot)
 $names=@(git -C $chordRoot ls-files --cached --others --exclude-standard|Sort-Object -Unique|Where-Object{Test-Path -LiteralPath (Join-Path $chordRoot $_) -PathType Leaf})
 $inventory=@(Compare-Object @($chordFrozen.path|Sort-Object) $names)
 $sets=@(foreach($set in $chordSets){$drift=@(Check-Rows $set.rows $set.root);$expected=@($set.rows|ForEach-Object{[IO.Path]::GetFullPath($(if([IO.Path]::IsPathRooted($_.path)){$_.path}else{Join-Path $set.root $_.path}))}|Sort-Object -Unique);$actual=if($set.name -ceq 'node'){@([IO.Path]::GetFullPath((Join-Path $set.root 'node.exe')))+@(Physical-Names (Join-Path $set.root 'node_modules/npm') $true)}else{@(Physical-Names $set.root ($set.name -cne 'source'))};$difference=@(Compare-Object $expected @($actual|Sort-Object -Unique));[ordered]@{name=$set.name;count=$set.rows.Count;drift=$drift.Count;inventory_drift=$difference.Count}})
 $controls=@(Check-Rows $chordControls '')
 $head=(git -C $chordRoot rev-parse HEAD).Trim();$sourceHead=(git -C $chordSourceRoot rev-parse HEAD).Trim()
 $proof=[ordered]@{completed_utc=[DateTimeOffset]::UtcNow.ToString('o');phase=$Phase;head=$head;source_head=$sourceHead;candidate=$chordFrozen.Count;candidate_drift=$changed.Count;candidate_inventory_drift=$inventory.Count;sets=$sets;controls=$chordControls.Count;control_drift=$controls.Count;control_manifest_sha256=(Get-FileHash -LiteralPath $chordControlsPath).Hash;runtime_executed=[bool]($Phase -match 'after|final' -or ($chordResults -and $chordResults.Count));public_activation=$false}
 $proof|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $chordEvidence "$chordName-$Phase-freeze.json") -Encoding utf8NoBOM
 if($head -cne $chordExpectedHead -or $sourceHead -cne $chordExpectedSource -or $changed.Count -or $inventory.Count -or @($sets|Where-Object{$_.drift -or $_.inventory_drift}).Count -or $controls.Count -or $proof.control_manifest_sha256 -cne $chordControlsHash){throw 'Whole native compile frozen authority drift'}
 [pscustomobject]@{phase=$Phase;freeze='passed';candidate=$chordFrozen.Count;source=1967;dependencies=31064;node=1774;compiler=19546}|ConvertTo-Json -Compress
}
Assert-Frozen 'before'
$chordAdmission=[ordered]@{observed_utc=[DateTimeOffset]::UtcNow.ToString('o');root_authority=$RootGrant;runtime_seconds=300;test_seconds=120;host_await_ms=10000;jobs=1;serial=$true;compile_result=$chordCompileResultPath;complete_host_failure_coverage=$false;full_chord_qualified=$false;full_pi_qualified=$false;public_activation=$false}
$chordAdmission|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $chordEvidence "$chordName-admission.json") -Encoding utf8NoBOM
$chordTargets=@(
 @{name='output';target='test-native-chord-output-source';inventory='CHORD_OUTPUT_COMPILED_INVENTORY';observed='CHORD_OUTPUT_OBSERVED_CASES';baseline='CHORD_OUTPUT_HOST_BASELINE_ALLOCATIONS';golden=$chordGoldenPaths[0];cases=14},
 @{name='foreign';target='test-native-chord-foreign-context-review';inventory='CHORD_FOREIGN_CONTEXT_REVIEW_COMPILED_INVENTORY';observed='CHORD_FOREIGN_CONTEXT_OBSERVED_CASES';baseline='CHORD_FOREIGN_CONTEXT_REVIEW_HOST_BASELINE_ALLOCATIONS';golden=$chordGoldenPaths[1];cases=5}
)
$chordResults=[Collections.Generic.List[object]]::new()
foreach($target in $chordTargets){
 Assert-Frozen ($target.name+'-before')
 [GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect()
 $free=[long](Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1024
 $other=@(Get-CimInstance Win32_Process -Filter "Name = 'zig.exe'"|Where-Object{$_.CommandLine -match 'zig(?:\.exe)?"?\s+build\s'})
 if($free -lt 16GB -or $other.Count -ge 4){throw 'Fresh runtime normal16GiB/max4 admission rejected'}
 Assert-NotPaused
 $ownerName=$chordName+'-'+$target.name
 & (Join-Path $chordEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1') -Name $ownerName -Executable $chordZig -WorkingDirectory $chordRoot -Arguments @('build',$target.target,'-Doptimize=Debug','-j1','--test-timeout','120s','--summary','all') -TimeoutSeconds 300
 Assert-Frozen ($target.name+'-after')
 $owner=Get-Content -LiteralPath (Join-Path $chordEvidence "$ownerName.json") -Raw|ConvertFrom-Json
 $absent=!(Get-CimInstance Win32_Process -Filter "ProcessId = $($owner.pid)")
 $logs=(Get-Content -LiteralPath (Join-Path $chordEvidence "$ownerName.stdout.log") -Raw)+(Get-Content -LiteralPath (Join-Path $chordEvidence "$ownerName.stderr.log") -Raw)
 $inventoryMatches=[regex]::Matches($logs,[regex]::Escape($target.inventory)+'=(\[[^\r\n]*\])')
 $caseMatches=[regex]::Matches($logs,[regex]::Escape($target.observed)+'=(\[[^\r\n]*\])')
 $baselineMatches=[regex]::Matches($logs,[regex]::Escape($target.baseline)+'=(\d+)')
 $inventory=@();$observed=@();$baseline=$null;$match=$false
 if($inventoryMatches.Count -eq 1){$inventory=@($inventoryMatches[0].Groups[1].Value|ConvertFrom-Json)}
 if($caseMatches.Count -eq 1){$observed=@($caseMatches[0].Groups[1].Value|ConvertFrom-Json);$golden=Get-Content -LiteralPath $target.golden -Raw|ConvertFrom-Json;$match=($observed|ConvertTo-Json -Depth 100 -Compress) -ceq ($golden.cases|ConvertTo-Json -Depth 100 -Compress)}
 if($baselineMatches.Count -eq 1){$baseline=[long]$baselineMatches[0].Groups[1].Value}
 $passed=$owner.status -ceq 'passed' -and $owner.exit_code -eq 0 -and $absent -and $inventory.Count -eq 4 -and @($inventory|Sort-Object -Unique).Count -eq 4 -and $observed.Count -eq $target.cases -and $match -and $baseline -gt 0 -and $logs -match '(?:All 4 tests passed|4/4 tests passed)'
 $entry=[ordered]@{name=$target.name;target=$target.target;status=if($passed){'passed'}else{'failed'};owner=$owner;root_pid_absent=$absent;compiled_inventory=$inventory;cases=$observed.Count;actual_source_match=$match;host_baseline_allocations=$baseline;complete_host_failure_coverage=$false}
 $chordResults.Add($entry)
 $entry|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $chordEvidence "$ownerName-result.json") -Encoding utf8NoBOM
 if(!$passed){throw 'Native diagnostic runtime negative retained; no remaining target launch'}
}
Assert-Frozen 'final'
$chordResult=[ordered]@{completed_utc=[DateTimeOffset]::UtcNow.ToString('o');head=$chordExpectedHead;source_head=$chordExpectedSource;status='passed';targets=$chordResults;compiled_test_executions=8;unique_compiled_test_names=@($chordResults.compiled_inventory|ForEach-Object{$_}|Sort-Object -Unique).Count;source_output_cases=14;source_foreign_cases=5;complete_host_failure_coverage=$false;fork_guest_compiled=$false;full_chord_qualified=$false;full_pi_qualified=$false;public_activation=$false}
$chordResult|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $chordEvidence "$chordName-result.json") -Encoding utf8NoBOM
$chordResult|ConvertTo-Json -Depth 12