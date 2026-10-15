param([Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9-]+$')][string]$Attempt,[Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$RootGrant)
$ErrorActionPreference='Stop'
$chordRoot='C:/Users/adyba/pi-zig-chord-foreign-context-5ab7fe7-20261015'
$chordSourceRoot='C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015'
$chordExpectedHead='e66b0b3f90f4a4a8f6c997f1924a3e3c332963e1'
$chordExpectedSource='5ab7fe74c400097b386662205cd93900695b8a71'
$chordEvidence=$PSScriptRoot
$chordPrefix="chord-latest-output-foreign-source-$Attempt-20261015"
$chordNode='C:/Program Files/nodejs/node.exe'
$chordZig='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0/zig.exe'
$chordObserver=Join-Path $chordEvidence 'source5ab-observe-20261015.mjs'
$chordObserverUri=([Uri]([IO.Path]::GetFullPath($chordObserver))).AbsoluteUri
$chordVerification=Join-Path $chordRoot 'verification/chord-foreign-context-5ab7fe7-20261015'
$chordTargets=@(
 @{name='output';driver=(Join-Path $chordVerification 'Capture-ChordOutput5ab7fe7.mjs');fixture=(Join-Path $chordRoot 'src/extensions/fixtures/chord-output-5ab7fe7.input.txt');cases=14;required_source='packages/chord/src/output.ts'},
 @{name='foreign';driver=(Join-Path $chordVerification 'Capture-ChordForeignContext5ab7fe7.mjs');fixture=(Join-Path $chordRoot 'src/extensions/fixtures/chord-foreign-context-review-5ab7fe7.input.txt');cases=5;required_source='packages/chord/src/remote.ts'}
)
if((git -C $chordRoot rev-parse HEAD).Trim() -cne $chordExpectedHead -or (git -C $chordSourceRoot rev-parse HEAD).Trim() -cne $chordExpectedSource){throw 'Reviewed latest Source/candidate heads changed'}
if(Test-Path -LiteralPath (Join-Path $chordEvidence "$chordPrefix-candidate-before.json")){throw 'Refuse Source pair attempt replay'}
function Rows($data){if($data -is [array]){@($data)}elseif($data.inputs){@($data.inputs)}elseif($data.files -is [array]){@($data.files)}else{@($data)}}
function Check-Rows($rows,[string]$root){
 $drift=[Collections.Generic.List[string]]::new()
 foreach($row in $rows){
  $path=if([IO.Path]::IsPathRooted($row.path)){$row.path}else{Join-Path $root $row.path}
  if(!(Test-Path -LiteralPath $path -PathType Leaf)){$drift.Add($path);continue}
  $stream=[IO.File]::OpenRead($path)
  try{$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()}
  if($hash -cne $row.sha256){$drift.Add($path)}
 }
 @($drift)
}
function Physical-Names([string]$root,[bool]$includeNodeModules){
 $files=[Collections.Generic.List[string]]::new();$directories=[Collections.Generic.Stack[string]]::new();$directories.Push($root)
 while($directories.Count){foreach($item in Get-ChildItem -LiteralPath $directories.Pop() -Force){if($item.Name -eq '.git' -or (!$includeNodeModules -and $item.Name -eq 'node_modules')){continue};if($item.PSIsContainer){if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0){$directories.Push($item.FullName)}}else{$files.Add([IO.Path]::GetFullPath($item.FullName))}}}
 @($files|Sort-Object -Unique)
}
$chordFrozen=@(git -C $chordRoot ls-files --cached --others --exclude-standard|Sort-Object -Unique|Where-Object{Test-Path -LiteralPath (Join-Path $chordRoot $_) -PathType Leaf}|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $chordRoot $_)).Hash}})
$chordFrozen|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $chordEvidence "$chordPrefix-candidate-before.json") -Encoding utf8NoBOM
$chordSets=@(
 @{name='source';manifest=(Join-Path $chordEvidence 'source5ab-full-manifest-20261015.json');count=1967;root=$chordSourceRoot},
 @{name='dependencies';manifest=(Join-Path $chordEvidence 'durable-19cb534-reference-20261012-all-built-runtime.json');count=31064;root='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'},
 @{name='node';manifest=(Join-Path $chordEvidence 'root-current8a-npm-tools-before.json');count=1774;root='C:/Program Files/nodejs'},
 @{name='compiler';manifest=(Join-Path $chordEvidence 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json');count=19546;root=(Split-Path -Parent $chordZig)}
)
foreach($set in $chordSets){$set.rows=@(Rows (Get-Content -LiteralPath $set.manifest -Raw|ConvertFrom-Json));if($set.rows.Count -ne $set.count){throw 'Full closure authority count changed'}}
$chordControlPaths=@($PSCommandPath,(Join-Path $chordEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'),$chordObserver,(Join-Path $chordEvidence 'source5ab-dependency-contract-audit-20261015.json'),(Join-Path $chordEvidence 'Run-ChordLatestOutputForeignSourcePair-20261015.ps1'),(Join-Path $chordEvidence 'chord-latest-output-foreign-source-root-slot3-first-20261015-prelaunch-negative.json'),(Join-Path $chordEvidence 'chord-latest-output-foreign-source-root-slot3-first-20261015-output-first-before-freeze.json'))+@($chordSets.manifest)+@($chordTargets.driver)+@($chordTargets.fixture)+(Join-Path $chordEvidence "$chordPrefix-candidate-before.json")
$chordControls=@($chordControlPaths|Sort-Object -Unique|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$chordControlsPath=Join-Path $chordEvidence "$chordPrefix-controls.json"
$chordControls|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $chordControlsPath -Encoding utf8NoBOM
$chordControlsHash=(Get-FileHash -LiteralPath $chordControlsPath).Hash
function Assert-Frozen([string]$Name){
 $candidateDrift=@(Check-Rows $chordFrozen $chordRoot)
 $candidateNames=@(git -C $chordRoot ls-files --cached --others --exclude-standard|Sort-Object -Unique|Where-Object{Test-Path -LiteralPath (Join-Path $chordRoot $_) -PathType Leaf})
 $candidateInventory=@(Compare-Object @($chordFrozen.path|Sort-Object) $candidateNames)
 $sets=@(foreach($set in $chordSets){
  $changed=@(Check-Rows $set.rows $set.root)
  $expectedNames=@($set.rows|ForEach-Object{[IO.Path]::GetFullPath($(if([IO.Path]::IsPathRooted($_.path)){$_.path}else{Join-Path $set.root $_.path}))}|Sort-Object -Unique)
  # The supplied1774 authority is node.exe plus the entire npm subtree. The
  # installation's unrelated Corepack/root launchers were never in that scope.
  $actualNames=if($set.name -ceq 'node'){@([IO.Path]::GetFullPath($chordNode))+@(Physical-Names (Join-Path $set.root 'node_modules/npm') $true)}else{@(Physical-Names $set.root ($set.name -cne 'source'))}
  $inventory=@(Compare-Object $expectedNames @($actualNames|Sort-Object -Unique))
  [ordered]@{name=$set.name;count=$set.rows.Count;drift=$changed.Count;inventory_drift=$inventory.Count;inventory_scope=if($set.name -ceq 'node'){'exact original node.exe plus complete npm subtree'}else{$set.root}}
 })
 $controls=@(Check-Rows $chordControls '')
 $head=(git -C $chordRoot rev-parse HEAD).Trim();$sourceHead=(git -C $chordSourceRoot rev-parse HEAD).Trim()
 $proof=[ordered]@{completed_utc=[DateTimeOffset]::UtcNow.ToString('o');head=$head;source_head=$sourceHead;candidate=$chordFrozen.Count;candidate_drift=$candidateDrift.Count;candidate_inventory_drift=$candidateInventory.Count;sets=$sets;controls=$chordControls.Count;control_drift=$controls.Count;control_manifest_sha256=(Get-FileHash -LiteralPath $chordControlsPath).Hash;public_activation=$false}
 $proof|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $chordEvidence "$Name-freeze.json") -Encoding utf8NoBOM
 if($head -cne $chordExpectedHead -or $sourceHead -cne $chordExpectedSource -or $candidateDrift.Count -or $candidateInventory.Count -or @($sets|Where-Object{$_.drift -or $_.inventory_drift}).Count -or $controls.Count -or $proof.control_manifest_sha256 -cne $chordControlsHash){throw 'Whole frozen Source/candidate/dependencies/Node/compiler/control authority drift'}
 [pscustomobject]@{phase=$Name;freeze='passed';candidate=$chordFrozen.Count;source=1967;dependencies=31064;node=1774;compiler=19546}|ConvertTo-Json -Compress
}
$chordResults=@()
foreach($target in $chordTargets){
 $targetResults=@()
 foreach($iteration in @('first','second')){
  $name="$chordPrefix-$($target.name)-$iteration"
  if(Test-Path -LiteralPath (Join-Path $chordEvidence "$name.json")){throw 'Refuse unique Source owner receipt replay'}
  Assert-Frozen "$name-before"
  $free=[long](Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1024
  [ordered]@{observed_utc=[DateTimeOffset]::UtcNow.ToString('o');root_authority=$RootGrant;free_bytes=$free;required_bytes=2GB;heap_mib=256;timeout_seconds=120;max_total_local_jobs=4;candidate=$chordFrozen.Count;source=1967;dependencies=31064;node=1774;compiler=19546;native_runtime_authorized=$false;public_activation=$false}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $chordEvidence "$name-admission.json") -Encoding utf8NoBOM
  if($free -lt 2GB){throw 'Fresh Source normal2GiB admission rejected; no Source launch'}
  & (Join-Path $chordEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1') -Name $name -Executable $chordNode -WorkingDirectory $chordSourceRoot -Arguments @('--max-old-space-size=256','--conditions=source','--experimental-transform-types','--import',$chordObserverUri,$target.driver,$chordSourceRoot,$target.fixture) -EnvironmentOverrides @{PI_SOURCE_ORACLE_CONTROL_MANIFEST=$chordControlsPath} -TimeoutSeconds 120
  Assert-Frozen "$name-after"
  $owner=Get-Content -LiteralPath (Join-Path $chordEvidence "$name.json") -Raw|ConvertFrom-Json
  $stdout=[IO.File]::ReadAllText((Join-Path $chordEvidence "$name.stdout.log"))
  $failures=[Collections.Generic.List[string]]::new()
  $data=$null
  try{$data=$stdout|ConvertFrom-Json}catch{$failures.Add('Source stdout is not one genuine JSON observation')}
  if($owner.status -cne 'passed' -or $owner.exit_code -ne 0){$failures.Add('Owned Source invocation failed')}
  if($null -eq $data -or @($data.cases).Count -ne $target.cases){$failures.Add('Actual Source caller case inventory changed')}
  $observed=@(Get-ChildItem -LiteralPath $chordEvidence -File -Filter "source5ab-modules-$($owner.pid)-*-20261015.jsonl")
  $modules=@(foreach($file in $observed){Get-Content -LiteralPath $file.FullName|Where-Object{$_}|ForEach-Object{$_|ConvertFrom-Json}})
  $required=[IO.Path]::GetFullPath((Join-Path $chordSourceRoot $target.required_source))
  if(@($modules|Where-Object{$_.kind -ceq 'observed-module' -and $_.path -eq $required}).Count -ne 1){$failures.Add('Required genuine Source implementation was not observed exactly once')}
  $absent=!(Get-CimInstance Win32_Process -Filter "ProcessId = $($owner.pid)")
  if(!$absent){$failures.Add('Owned Source PID remains present')}
  $output=Join-Path $chordEvidence "$name-output.json"
  [IO.File]::WriteAllText($output,$stdout,[Text.UTF8Encoding]::new($false))
  $result=[ordered]@{head=$chordExpectedHead;source_head=$chordExpectedSource;target=$target.name;iteration=$iteration;status=if($failures.Count){'failed'}else{'passed'};cases=if($data){@($data.cases).Count}else{0};owner=$owner;root_pid_absent=$absent;observed_module_files=@($observed.FullName);observed_module_records=$modules.Count;output=$output;output_sha256=(Get-FileHash -LiteralPath $output).Hash;failures=@($failures);native_compiled=$false;native_runtime_executed=$false;public_activation=$false;full_chord_qualified=$false;full_pi_qualified=$false}
  $result|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $chordEvidence "$name-result.json") -Encoding utf8NoBOM
  $targetResults+=@($result);$chordResults+=@($result)
  if($failures.Count){throw 'Actual latest Source capture failed; retained negative, no qualification'}
 }
 if($targetResults.Count -ne 2 -or $targetResults[0].output_sha256 -cne $targetResults[1].output_sha256){throw 'Genuine latest Source double capture differs'}
}
Assert-Frozen "$chordPrefix-final"
[ordered]@{completed_utc=[DateTimeOffset]::UtcNow.ToString('o');head=$chordExpectedHead;source_head=$chordExpectedSource;status='passed';double_captures=$chordResults;candidate=$chordFrozen.Count;source=1967;dependencies=31064;node=1774;compiler=19546;control_manifest_sha256=$chordControlsHash;native_compiled=$false;native_runtime_executed=$false;complete_host_failure_coverage=$false;full_chord_qualified=$false;full_pi_qualified=$false;public_activation=$false}|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $chordEvidence "$chordPrefix-pair-result.json") -Encoding utf8NoBOM
[pscustomobject]@{head=$chordExpectedHead;status='passed';output_cases=14;foreign_cases=5;source_invocations=4;native_runtime_executed=$false;public_activation=$false}|ConvertTo-Json
