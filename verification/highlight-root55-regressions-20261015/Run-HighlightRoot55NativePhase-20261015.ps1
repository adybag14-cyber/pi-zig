param([Parameter(Mandatory)][ValidateSet('foundation','generator','generator-gpa','json','direct191')][string]$Target,[Parameter(Mandatory)][ValidateSet('compile','runtime')][string]$Phase,[string]$Attempt='first')
$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskTree='C:/Users/adyba/pi-zig-highlight-complete191-root55-20261015'
$taskHead='8685fd09298955e1f2fbae41e7677141b07e7b14'
$taskZig='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0/zig.exe'
$taskHelper=Join-Path $taskTree 'tools/ci/native_qualification_ci.ps1'
. $taskHelper
$taskName="highlight-root55-$Target-$Phase-$Attempt-20261015"
$taskCompileName="highlight-root55-$Target-compile-$Attempt-20261015"
$taskSteps=@{foundation='native-highlight-root55-foundation';generator='native-async-generator';'generator-gpa'='native-async-generator-gpa';json='native-ai-json-parse';direct191='native-highlight-complete191-direct'}
function Check-Rows($Rows){
 $changed=[Collections.Generic.List[string]]::new()
 foreach($row in $Rows){
  if(!(Test-Path -LiteralPath $row.path -PathType Leaf)){$changed.Add($row.path);continue}
  $stream=[IO.File]::OpenRead($row.path)
  try{$actual=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()}
  if($actual -ine $row.sha256){$changed.Add($row.path)}
 }
 return @($changed)
}
function Candidate-Rows {
 @(& git -c gc.auto=0 -c maintenance.auto=false -C $taskTree ls-files --cached --others --exclude-standard|Sort-Object -Unique|ForEach-Object {$path=Join-Path $taskTree $_;@{path=$path;relative=$_;sha256=(Get-FileHash -LiteralPath $path).Hash}})
}
function Scoped-Paths([string]$Root){@(Get-ChildItem -LiteralPath $Root -Recurse -File -Force|ForEach-Object FullName|Sort-Object)}
function Node-Paths {@(@('C:\Program Files\nodejs\node.exe')+@(Scoped-Paths 'C:/Program Files/nodejs/node_modules/npm')|Sort-Object)}
if((& git -C $taskTree rev-parse HEAD) -cne $taskHead -or (& git -C $taskTree status --porcelain)){throw 'Exact clean sealed8685 candidate required'}
if((Get-FileHash -LiteralPath $taskZig).Hash -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Pinned Zig0.16 changed'}
if((Get-FileHash -LiteralPath (Join-Path $taskTree 'vendor/quickjs/quickjs.c')).Hash -cne '8239A6841DE1F59CCC39E61CD912B9F4439F3E2F059104A9802E3D23380231F5' -or (Get-FileHash -LiteralPath (Join-Path $taskTree 'vendor/quickjs/quickjs.h')).Hash -cne 'EC16662550F3F254928AC6B77028518D59371B90CA3EDAD08DBA277A2144E639'){throw 'Approved C/H byte identity changed'}
$taskSpecs=@(
 @{name='source';file='source5ab-full-manifest-20261015.json';count=1967},
 @{name='dependencies';file='durable-19cb534-reference-20261012-all-built-runtime.json';count=31064},
 @{name='node';file='root-current8a-npm-tools-before.json';count=1774},
 @{name='canonical';file='highlight-complete191-canonical195-20261015.json';count=195},
 @{name='compiler';file='durable-latest89-full-inspect-53ae-tool-prehash-20261011.json';count=19546}
)
$taskFrozen=@()
foreach($spec in $taskSpecs){
 $value=Get-Content -Raw (Join-Path $taskEvidence $spec.file)|ConvertFrom-Json
 $rows=if($spec.name -ceq 'compiler'){@($value.inputs)}else{@($value)}
 if($rows.Count -ne $spec.count -or @(Check-Rows $rows).Count){throw "Full $($spec.name) prehash mismatch"}
 $taskFrozen+=@{name=$spec.name;rows=$rows}
}
$taskAbsenceManifest=Join-Path $taskEvidence 'highlight-lazy-batch8-source106-absences84-20261015.json'
$taskAbsent=@(Get-Content -Raw $taskAbsenceManifest|ConvertFrom-Json)
function Present-Absent {@($taskAbsent|Where-Object{(Test-Path -LiteralPath $_.source) -or (Test-Path -LiteralPath $_.runtime)})}
if($taskAbsent.Count -ne 84 -or @(Present-Absent).Count){throw 'Exact84 absence records mismatch'}
$taskSourceRoot='C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015'
$taskRuntimeRoot='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
$taskPathSets=@{source=@(Scoped-Paths $taskSourceRoot);dependencies=@(Scoped-Paths $taskRuntimeRoot);compiler=@(Scoped-Paths (Split-Path $taskZig -Parent));node=@(Node-Paths)}
foreach($key in @('compiler','node')){
 $rows=@(($taskFrozen|Where-Object name -ceq $key).rows)
 if(@(Compare-Object @($rows.path|Sort-Object) $taskPathSets[$key]).Count){throw "$key manifest path inventory mismatch"}
}
$taskBefore=Candidate-Rows
$taskBefore|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-before.json") -Encoding utf8NoBOM
$taskPathSets|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-paths-before.json") -Encoding utf8NoBOM
$taskControls=@($PSCommandPath,$taskHelper,$taskAbsenceManifest,(Join-Path $taskEvidence 'Run-HighlightComplete191Source-20261015.ps1'),(Join-Path $taskEvidence 'Run-HighlightComplete191Series-20261015.ps1'),(Join-Path $taskEvidence 'capture-highlight-complete191-20261015.mjs'),(Join-Path $taskEvidence 'source5ab-observe-20261015.mjs'),(Join-Path $taskEvidence 'highlight-complete191-source-series-terminal-20261015.json'))+@($taskSpecs|ForEach-Object {Join-Path $taskEvidence $_.file})
foreach($mode in @('success','lookup_failure','safe_factory_failure')){
 foreach($suffix in @('output.json','posthash.json','module-observations.json','controls-before.json','json')){
  $file=if($suffix -ceq 'json'){"highlight-complete191-source-$mode-first-20261015.json"}else{"highlight-complete191-source-$mode-first-20261015-$suffix"}
  $taskControls+=Join-Path $taskEvidence $file
 }
 $original=Get-Content -Raw (Join-Path $taskEvidence "highlight-complete191-source-$mode-first-20261015-controls-before.json")|ConvertFrom-Json
 $taskControls+=@($original.path)
}
$taskControls=@($taskControls|Sort-Object -Unique|ForEach-Object {@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskControls|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-controls.json") -Encoding utf8NoBOM
function Post-Check {
 $after=Candidate-Rows
 $candidateDrift=@(Compare-Object @($taskBefore|ForEach-Object {"$($_.relative):$($_.sha256)"}) @($after|ForEach-Object {"$($_.relative):$($_.sha256)"}))
 $manifests=@(foreach($item in $taskFrozen){@{name=$item.name;count=$item.rows.Count;drift=@(Check-Rows $item.rows)}})
 $afterPaths=@{source=@(Scoped-Paths $taskSourceRoot);dependencies=@(Scoped-Paths $taskRuntimeRoot);compiler=@(Scoped-Paths (Split-Path $taskZig -Parent));node=@(Node-Paths)}
 $pathDrift=@(foreach($key in @('source','dependencies','compiler','node')){@{name=$key;count=$afterPaths[$key].Count;drift=@(Compare-Object $taskPathSets[$key] $afterPaths[$key])}})
 $controlDrift=@(Check-Rows $taskControls);$absenceDrift=@(Present-Absent)
 @{head=$taskHead;target=$Target;phase=$Phase;candidate_before=$taskBefore.Count;candidate_after=$after.Count;candidate_drift=$candidateDrift;manifests=$manifests;inventories=$pathDrift;controls=$taskControls.Count;control_drift=$controlDrift;absences=84;absence_drift=$absenceDrift;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 9|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-posthash.json") -Encoding utf8NoBOM
 if($candidateDrift.Count -or @($manifests|Where-Object {$_.drift.Count}).Count -or @($pathDrift|Where-Object {$_.drift.Count}).Count -or $controlDrift.Count -or $absenceDrift.Count){throw 'Frozen native input/post inventory drift'}
}
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
$taskRoots=@(Get-CimInstance Win32_Process -Filter "Name = 'zig.exe'"|Where-Object {$_.CommandLine -match '\sbuild\s'}|Select-Object ProcessId,CommandLine)
@{free_kib=$taskFree;required_kib=16MB;slot=4;max_native_roots=4;roots=$taskRoots;candidate=$taskHead;target=$Target;phase=$Phase;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json") -Encoding utf8NoBOM
if($taskFree -lt 16MB -or $taskRoots.Count -ge 4){throw 'Fresh normal16GiB/max4 admission denied'}
if($Phase -ceq 'runtime'){
 $compile=Get-Content -Raw (Join-Path $taskEvidence "$taskCompileName.json")|ConvertFrom-Json
 $post=Get-Content -Raw (Join-Path $taskEvidence "$taskCompileName-posthash.json")|ConvertFrom-Json
 $artifacts=@(Get-Content -Raw (Join-Path $taskEvidence "$taskCompileName-artifacts.json")|ConvertFrom-Json)
 $metadata=Get-Content -Raw (Join-Path $taskEvidence "$taskCompileName-metadata.json")|ConvertFrom-Json
 if($compile.status -cne 'passed' -or $post.candidate_drift.Count -or @($post.manifests|Where-Object {$_.drift.Count}).Count -or @($post.inventories|Where-Object {$_.drift.Count}).Count -or $post.control_drift.Count -or $post.absence_drift.Count -or @(Check-Rows $artifacts).Count -or !$metadata.tests.Count){throw 'Prior compile/fullpost0/artifact/metadata required'}
 $step="test-$($taskSteps[$Target])";$timeout=300
}else{$step="build-$($taskSteps[$Target])";$timeout=1320}
$taskPriorArtifacts=@(Get-ChildItem -LiteralPath (Join-Path $taskTree '.zig-cache') -Recurse -Filter test.exe -File -ErrorAction SilentlyContinue|ForEach-Object FullName)
try{
 $terminal=Invoke-CiOwnedProcess $taskZig @('build',$step,'-Doptimize=Debug','-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') $taskTree (Join-Path $taskEvidence $taskName) $timeout
 if($Phase -ceq 'compile'){
  $newArtifacts=@(Get-ChildItem -LiteralPath (Join-Path $taskTree '.zig-cache') -Recurse -Filter test.exe -File|Where-Object {$_.FullName -notin $taskPriorArtifacts})
  if($newArtifacts.Count -ne 1){throw "Expected one fresh selected test artifact, found $($newArtifacts.Count)"}
  $binary=$newArtifacts[0].FullName
  $artifacts=@(Get-ChildItem -LiteralPath $newArtifacts[0].DirectoryName -File|ForEach-Object {@{path=$_.FullName;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}})
  $artifacts|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-artifacts.json") -Encoding utf8NoBOM
  $request=[byte[]](4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
  $receipt=Join-Path $taskEvidence "$taskName-metadata-probe"
  $probe=Invoke-CiOwnedProcess $binary @('--listen=-') $taskTree $receipt 30 $request
  $bytes=[IO.File]::ReadAllBytes("$receipt.stdout.bin");$offset=0;$names=@();$version=$null
  while($offset -lt $bytes.Length){
   if($offset+8 -gt $bytes.Length){throw 'Truncated metadata header'}
   $tag=[BitConverter]::ToUInt32($bytes,$offset);$length=[BitConverter]::ToUInt32($bytes,$offset+4);$offset+=8
   if($length -gt 1MB -or $offset+$length -gt $bytes.Length){throw 'Metadata bounds mismatch'}
   if($tag -eq 0){$version=[Text.Encoding]::UTF8.GetString($bytes,$offset,$length)}
   elseif($tag -eq 3){
    $strings=[BitConverter]::ToUInt32($bytes,$offset);$count=[BitConverter]::ToUInt32($bytes,$offset+4)
    if(!$count -or $names.Count -or $length -ne 8+8*$count+$strings){throw 'Nonempty exact metadata array required'}
    $start=$offset+8+8*$count
    for($i=0;$i -lt $count;$i++){
     $at=[BitConverter]::ToUInt32($bytes,$offset+8+4*$i);$panic=[BitConverter]::ToUInt32($bytes,$offset+8+4*$count+4*$i)
     if($panic -or $at -ge $strings){throw 'Unexpected panic/offset metadata'}
     $end=$at;while($end -lt $strings -and $bytes[$start+$end] -ne 0){$end++}
     if($end -eq $strings){throw 'Unterminated metadata name'}
     $names+=[Text.Encoding]::UTF8.GetString($bytes,$start+$at,$end-$at)
    }
   }else{throw "Unexpected metadata-only tag $tag"}
   $offset+=$length
  }
  if($version -cne '0.16.0' -or !$names.Count){throw 'Actual metadata/version absent'}
  if($Target -ceq 'foundation' -and $names.Count -ne 5){throw 'Foundation must select exact five actual tests'}
  if($Target -ceq 'direct191' -and $names.Count -ne 3){throw 'Direct191 must select exact three actual tests'}
  if($Target -ceq 'generator-gpa' -and !@($names|Where-Object {$_ -match 'native async generator host GPA'}).Count){throw 'Mandatory generator GPA test absent'}
  if($Target -ceq 'generator' -and @($names|Where-Object {$_ -match 'native async generator functional'}).Count -lt 8){throw 'Mandatory native C-generator functional tests absent'}
  if($Target -ceq 'json' -and !@($names|Where-Object {$_ -match 'native AI JSON'}).Count){throw 'Mandatory native JSON tests absent'}
  @{binary=$binary;binary_sha256=$probe.executable_sha256;version=$version;tests=$names;count=$names.Count;method='Actual Zig0.16 metadata-only query4 and clean exit0; no run command';candidate=$taskHead;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-metadata.json") -Encoding utf8NoBOM
 }elseif(@(Check-Rows $artifacts).Count){throw 'Compiled matching runtime artifact drift'}
}finally{Post-Check}
Write-Output "NATIVE_ROOT55_PHASE_PASSED target=$Target phase=$Phase head=$taskHead"
