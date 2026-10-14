param([Parameter(Mandatory)][string]$Attempt,[Parameter(Mandatory)][string]$RootGrant)
$ErrorActionPreference='Stop'
$chordRoot='C:/Users/adyba/pi-zig-chord-v4-websocket-b45-20261014'
$chordEvidence=$PSScriptRoot
. (Join-Path $chordRoot 'verification/chord-latest-1692-source-20261014/Assert-ChordComposedPartitions.ps1')
$chordPrefix="chord-websockets-gpa-debug-runtime-$Attempt-20261014"
$chordZig='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0/zig.exe'
$chordCompile='chord-websockets-gpa-debug-compile-first-20261014'
$chordCompilePost=Get-Content -LiteralPath (Join-Path $chordEvidence "$chordCompile-posthash.json") -Raw|ConvertFrom-Json
if($chordCompilePost.status -cne 'passed' -or $chordCompilePost.source_drift -or $chordCompilePost.compiler_drift -or $chordCompilePost.original_source_drift -or !$chordCompilePost.root_pid_absent -or $chordCompilePost.runtime_executed){throw 'Reviewed exact compile prerequisite changed'}
$chordFrozen=Get-Content -LiteralPath (Join-Path $chordEvidence "$chordCompile-source-before.json") -Raw|ConvertFrom-Json
$chordTools=(Get-Content -LiteralPath (Join-Path $chordEvidence 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json') -Raw|ConvertFrom-Json).inputs
$chordOriginalData=Get-Content -LiteralPath (Join-Path $chordEvidence 'sdk-source-b45-full-manifest-20261014.json') -Raw|ConvertFrom-Json
$chordOriginal=if($chordOriginalData -is [array]){@($chordOriginalData)}elseif($chordOriginalData.inputs){@($chordOriginalData.inputs)}elseif($chordOriginalData.files -is [array]){@($chordOriginalData.files)}else{@($chordOriginalData)}
$chordControls=@(@($PSCommandPath,(Join-Path $chordEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'),(Join-Path $chordEvidence 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json'),(Join-Path $chordEvidence 'sdk-source-b45-full-manifest-20261014.json'))|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
function Check-Rows($rows,[string]$root){
 $changed=[Collections.Generic.List[string]]::new()
 foreach($row in $rows){$path=if([IO.Path]::IsPathRooted($row.path)){$row.path}else{Join-Path $root $row.path};if(!(Test-Path -LiteralPath $path -PathType Leaf)){$changed.Add($path);continue};$stream=[IO.File]::OpenRead($path);try{$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()};if($hash -cne $row.sha256){$changed.Add($path)}}
 @($changed)
}
function Freeze-Proof([string]$Name){
 $controls=@(Check-Rows $chordControls '');$working=@(Check-Rows $chordFrozen $chordRoot);$compiler=@(Check-Rows $chordTools '');$original=@(Check-Rows $chordOriginal 'C:/Users/adyba/pi-upstream-source-b45e0eb-20261014')
 $names=@(git -C $chordRoot ls-files --cached --others --exclude-standard|Sort-Object -Unique|Where-Object{Test-Path -LiteralPath (Join-Path $chordRoot $_) -PathType Leaf})
 $workingNames=@(Compare-Object @($chordFrozen.path|Sort-Object) $names)
 $compilerNames=@(Compare-Object @($chordTools.path|Sort-Object) @(Get-ChildItem -LiteralPath (Split-Path -Parent $chordZig) -File -Recurse|ForEach-Object FullName|Sort-Object))
 $proof=[ordered]@{head=(git -C $chordRoot rev-parse HEAD).Trim();source=$chordFrozen.Count;source_drift=$working.Count;source_inventory_drift=$workingNames.Count;compiler=$chordTools.Count;compiler_drift=$compiler.Count;compiler_inventory_drift=$compilerNames.Count;original_source=$chordOriginal.Count;original_source_drift=$original.Count;control_inputs=$chordControls.Count;control_drift=$controls.Count;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
 $proof|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $chordEvidence "$Name-freeze.json") -Encoding utf8NoBOM
 if($proof.head -cne $chordCompilePost.head -or $working.Count -or $compiler.Count -or $original.Count -or $controls.Count -or $workingNames.Count -or $compilerNames.Count){throw 'Frozen compile/runtime input identity changed'}
}
$chordTargets=@(
 @{name='state';target='test-native-chord-websockets-source';marker='CHORD_WEBSOCKETS_COMPILED_INVENTORY';tests=5;cases=13;gpa=$true;names=@('native Chordb45 accept WebSockets diagnostic compiled inventory','native Chordb45 accept WebSockets actual Source13 authentication immediate wrapping live getters frames packing and close with GC','native Chordb45 accept WebSockets measured complete Source13 host allocation baseline diagnostic only','native Chordb45 accept WebSockets complete Source13 GC and teardown every host allocation failure')}
)
$chordResults=@()
foreach($chordTarget in $chordTargets){
 $chordName="$chordPrefix-$($chordTarget.name)"
 if(Test-Path -LiteralPath (Join-Path $chordEvidence "$chordName.json")){throw 'Refuse owned runtime receipt replay'}
 Freeze-Proof "$chordName-before"
 [GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect()
 $chordOther=@(Get-CimInstance Win32_Process -Filter "Name = 'zig.exe'"|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine,@{n='created_utc';e={([DateTimeOffset]$_.CreationDate).UtcDateTime.ToString('o')}})
 $chordOtherRoots=@($chordOther|Where-Object{$_.CommandLine -match 'zig(?:\.exe)?"?\s+build\s'})
 $chordFree=[long](Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1024
 [ordered]@{observed_utc=[DateTimeOffset]::UtcNow.ToString('o');free_bytes=$chordFree;required_bytes=16GB;other_native=$chordOther;other_native_roots=$chordOtherRoots.Count;root_authority=$RootGrant;outer_seconds=300;test_seconds=120;host_seconds=10;jobs=1;llvm='default';sole8_exception_used=$false;public_activation=$false}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $chordEvidence "$chordName-admission.json") -Encoding utf8NoBOM
 if($chordFree -lt 16GB -or $chordOtherRoots.Count -gt 1){throw 'Fresh normal16 or max2 native roots rejected; no runtime launched'}
 & (Join-Path $chordEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1') -Name $chordName -Executable $chordZig -WorkingDirectory $chordRoot -Arguments @('build',$chordTarget.target,'-Doptimize=Debug','-j1','--test-timeout','120s','--summary','all') -TimeoutSeconds 300
 Freeze-Proof "$chordName-after"
 $chordOwner=Get-Content -LiteralPath (Join-Path $chordEvidence "$chordName.json") -Raw|ConvertFrom-Json
 $chordLog=[IO.File]::ReadAllText((Join-Path $chordEvidence "$chordName.stdout.log"))+[Environment]::NewLine+[IO.File]::ReadAllText((Join-Path $chordEvidence "$chordName.stderr.log"))
 $chordMarkers=[regex]::Matches($chordLog,$chordTarget.marker+'=(\[[^\r\n]*\])')
 $chordNames=if($chordMarkers.Count -eq 1){@($chordMarkers[0].Groups[1].Value|ConvertFrom-Json)}else{@()}
 $chordFailures=[Collections.Generic.List[string]]::new()
 if($chordOwner.status -cne 'passed' -or $chordOwner.exit_code -ne 0){$chordFailures.Add('Owned target did not pass')}
 if($chordNames.Count -ne $chordTarget.tests -or @($chordNames|Sort-Object -Unique).Count -ne $chordTarget.tests){$chordFailures.Add('Compiled inventory count changed')}
 foreach($wanted in $chordTarget.names){if(@($chordNames|Where-Object{$_.EndsWith('.test.'+$wanted,[StringComparison]::Ordinal)}).Count -ne 1){$chordFailures.Add("Missing exact selected gate $wanted")}}
 if(@($chordNames|Where-Object{$_ -ceq 'extensions.native_durable_storage.test_0'}).Count -ne 1){$chordFailures.Add('Missing transitive storage gate')}
 if($chordLog.IndexOf(('run test '+$chordTarget.tests+' pass ('+$chordTarget.tests+' total)'),[StringComparison]::Ordinal) -lt 0){$chordFailures.Add('Not every selected test passed')}
 foreach($baselineMarker in $(if($chordTarget.name -ceq 'contracts'){@('CHORD_V4_CONTRACTS_GPA_BASELINE_ALLOCATIONS','CHORD_V4_OBSERVABLE_GPA_BASELINE_ALLOCATIONS')}elseif($chordTarget.name -ceq 'cells'){@('CHORD_V4_CELLS_GPA_BASELINE_ALLOCATIONS')}else{@('CHORD_WEBSOCKETS_HOST_BASELINE_ALLOCATIONS')})){
  $baselineMatches=[regex]::Matches($chordLog,$baselineMarker+'=(\d+)')
  if($baselineMatches.Count -ne 1 -or [long]$baselineMatches[0].Groups[1].Value -le 0){$chordFailures.Add('Missing actual complete host allocator baseline '+$baselineMarker)}
 }
 $chordCoverage=$null
 if($chordTarget.name -ceq 'core'){
  try{$chordCoverage=Assert-ChordComposedPartitions -Log $chordLog}catch{$chordFailures.Add($_.Exception.Message)}
 }
 if($chordTarget.name -ceq 'state'){
  $gpaBaseline=[regex]::Matches($chordLog,'CHORD_WEBSOCKETS_GPA_BASELINE_ALLOCATIONS=(\d+)')
  $gpaComplete=[regex]::Matches($chordLog,'CHORD_WEBSOCKETS_GPA_COMPLETE=(\{[^\r\n]*\})')
  if($gpaBaseline.Count -ne 1 -or $gpaBaseline[0].Groups[1].Value -cne '1585'){$chordFailures.Add('Actual complete sweep baseline differs from measured Windows1585')}
  if($gpaComplete.Count -ne 1){$chordFailures.Add('Missing exact complete WebSocket host allocation coverage receipt')}else{
   try{
    $coverage=$gpaComplete[0].Groups[1].Value|ConvertFrom-Json
    if($coverage.start -ne 0 -or $coverage.end -ne 1585 -or $coverage.baseline -ne 1585 -or $coverage.completed -ne 1585 -or $coverage.leaks -ne 0 -or $coverage.unexpected_errors -ne 0){throw 'Incomplete or mismatched actual WebSocket host allocation universe'}
    $chordCoverage=$coverage
   }catch{$chordFailures.Add($_.Exception.Message)}
  }
 }
 $absent=!(Get-CimInstance Win32_Process -Filter "ProcessId = $($chordOwner.pid)")
 if(!$absent){$chordFailures.Add('Owned target PID still present')}
 $result=[ordered]@{head=$chordCompilePost.head;target=$chordTarget.target;status=if($chordFailures.Count){'failed'}else{'passed'};source_cases=$chordTarget.cases;compiled_expected=$chordTarget.tests;compiled_observed=$chordNames.Count;compiled_names=$chordNames;composed_gpa_coverage=$chordCoverage;failures=@($chordFailures);native_gc=if($chordFailures.Count){'unqualified'}else{'passed'};c_malloc_exhaustive=$false;allocation_scope='host allocator';all_gpa_failures=if(!$chordTarget.gpa){'not_yet_qualified'}elseif($chordFailures.Count){'unqualified'}else{'passed'};owner=$chordOwner;root_pid_absent=$absent;outer_seconds=300;test_seconds=120;host_seconds=10;public_activation=$false;fork_driver_implemented=$false;full_pi_qualified=$false}
 $result|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $chordEvidence "$chordName-result.json") -Encoding utf8NoBOM
 $chordResults+=@($result)
}
$chordResults|ConvertTo-Json -Depth 9|Set-Content -LiteralPath (Join-Path $chordEvidence "$chordPrefix-summary.json") -Encoding utf8NoBOM
$chordResults|ForEach-Object{[pscustomobject]$_|Select-Object target,status,source_cases,compiled_expected,compiled_observed,root_pid_absent,all_gpa_failures}|ConvertTo-Json
if(@($chordResults|Where-Object{$_.status -cne 'passed'}).Count){throw 'Actual WebSocket13 complete host allocation gate failed; no full qualification'}
