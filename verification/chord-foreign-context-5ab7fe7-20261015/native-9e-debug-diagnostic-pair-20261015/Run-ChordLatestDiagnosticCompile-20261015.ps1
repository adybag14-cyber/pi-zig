param([Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9-]+$')][string]$Attempt,[Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$RootGrant,[string]$PausePath='C:/Users/adyba/pi-zig-update-evidence-20261003/chord-latest-native-pause-20261015.flag')
$ErrorActionPreference='Stop'
$chordRoot='C:/Users/adyba/pi-zig-chord-foreign-context-5ab7fe7-20261015'
$chordSourceRoot='C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015'
$chordExpectedHead='9e6825df2787df4f44dbe4ba7913c66d4e6afed5'
$chordExpectedSource='5ab7fe74c400097b386662205cd93900695b8a71'
$chordEvidence=$PSScriptRoot
$chordName="chord-latest-diagnostic-debug-compile-$Attempt-20261015"
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
$chordFrozen=@(git -C $chordRoot ls-files --cached --others --exclude-standard|Sort-Object -Unique|Where-Object{Test-Path -LiteralPath (Join-Path $chordRoot $_) -PathType Leaf}|ForEach-Object{Assert-NotPaused;[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $chordRoot $_)).Hash}})
$chordFrozen|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $chordEvidence "$chordName-candidate-before.json") -Encoding utf8NoBOM
$chordControlPaths=@($PSCommandPath,(Join-Path $chordEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'),$chordSourcePairPath,(Join-Path $chordEvidence 'chord-latest-foreign-source-root-light3-first-20261015-final-freeze.json'),(Join-Path $chordEvidence 'source5ab-dependency-contract-audit-20261015.json'))+@($chordSets.manifest)+@($chordGoldenPaths)+(Join-Path $chordEvidence "$chordName-candidate-before.json")
$chordControls=@($chordControlPaths|Sort-Object -Unique|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
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
 $proof=[ordered]@{completed_utc=[DateTimeOffset]::UtcNow.ToString('o');phase=$Phase;head=$head;source_head=$sourceHead;candidate=$chordFrozen.Count;candidate_drift=$changed.Count;candidate_inventory_drift=$inventory.Count;sets=$sets;controls=$chordControls.Count;control_drift=$controls.Count;control_manifest_sha256=(Get-FileHash -LiteralPath $chordControlsPath).Hash;runtime_executed=$false;public_activation=$false}
 $proof|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $chordEvidence "$chordName-$Phase-freeze.json") -Encoding utf8NoBOM
 if($head -cne $chordExpectedHead -or $sourceHead -cne $chordExpectedSource -or $changed.Count -or $inventory.Count -or @($sets|Where-Object{$_.drift -or $_.inventory_drift}).Count -or $controls.Count -or $proof.control_manifest_sha256 -cne $chordControlsHash){throw 'Whole native compile frozen authority drift'}
 [pscustomobject]@{phase=$Phase;freeze='passed';candidate=$chordFrozen.Count;source=1967;dependencies=31064;node=1774;compiler=19546}|ConvertTo-Json -Compress
}
Assert-Frozen 'before'
[GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect()
$chordOther=@(Get-CimInstance Win32_Process -Filter "Name = 'zig.exe'"|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine,@{n='created_utc';e={([DateTimeOffset]$_.CreationDate).UtcDateTime.ToString('o')}})
$chordRoots=@($chordOther|Where-Object{$_.CommandLine -match 'zig(?:\.exe)?"?\s+build\s'})
$chordFree=[long](Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1024
[ordered]@{observed_utc=[DateTimeOffset]::UtcNow.ToString('o');root_authority=$RootGrant;free_bytes=$chordFree;required_bytes=16GB;other_native=$chordOther;max_total_local_jobs=4;compile_seconds=1320;jobs=1;llvm='default';compiler_peak_calibrated=$false;runtime_authorized=$false;source_output_cases=14;source_foreign_cases=5;public_activation=$false}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $chordEvidence "$chordName-admission.json") -Encoding utf8NoBOM
if($chordFree -lt 16GB -or $chordRoots.Count -ge 4){throw 'Fresh normal16GiB/max4 native admission rejected; no compiler launch'}
Assert-NotPaused
& (Join-Path $chordEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1') -Name $chordName -Executable $chordZig -WorkingDirectory $chordRoot -Arguments @('build','build-native-chord-output-source','build-native-chord-foreign-context-review','-Doptimize=Debug','-j1','--summary','all') -TimeoutSeconds 1320
Assert-Frozen 'after'
$chordOwner=Get-Content -LiteralPath (Join-Path $chordEvidence "$chordName.json") -Raw|ConvertFrom-Json
$chordAbsent=!(Get-CimInstance Win32_Process -Filter "ProcessId = $($chordOwner.pid)")
$chordResult=[ordered]@{completed_utc=[DateTimeOffset]::UtcNow.ToString('o');head=$chordExpectedHead;source_head=$chordExpectedSource;status=if($chordOwner.status -ceq 'passed' -and $chordOwner.exit_code -eq 0 -and $chordAbsent){'passed'}else{'failed'};targets=@('build-native-chord-output-source','build-native-chord-foreign-context-review');owner=$chordOwner;root_pid_absent=$chordAbsent;source_output_cases=14;source_foreign_cases=5;runtime_executed=$false;fresh_host_baselines=$null;complete_host_failure_coverage=$false;fork_guest_compiled=$false;full_chord_qualified=$false;full_pi_qualified=$false;public_activation=$false}
$chordResult|ConvertTo-Json -Depth 9|Set-Content -LiteralPath (Join-Path $chordEvidence "$chordName-result.json") -Encoding utf8NoBOM
if($chordResult.status -cne 'passed'){throw 'Reviewed native diagnostic compile failed; negative retained, no runtime'}
[pscustomobject]@{head=$chordExpectedHead;status='passed';compiled_targets=2;runtime_executed=$false;public_activation=$false}|ConvertTo-Json
