param([Parameter(Mandatory)][ValidateSet('foundation','async26','generator','generator-gpa','json','source51','operators','engine','recovery','direct191','host445')][string]$Target,[Parameter(Mandatory)][ValidateSet('compile','runtime')][string]$Phase,[string]$Attempt='first',[Parameter(Mandatory)][string]$CandidateHead,[Parameter(Mandatory)][ValidateRange(1,4)][int]$Slot,[Parameter(Mandatory)][string]$RootExecutionGrant)
$ErrorActionPreference='Stop'
$PSNativeCommandUseErrorActionPreference=$true
if($RootExecutionGrant.Trim().Length -lt 8){throw 'Explicit Root C9h execution grant required; source-only preparation is not a grant'}
$taskEvidence='C:/Users/adyba/pi-zig-update-evidence-20261003'
$taskTree=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$taskOwner='C:/Users/adyba/pi-zig-web-body-full-source-20261016/verification/web-body-node24-20261015/run-owner.ps1'
if((Get-FileHash -LiteralPath $taskOwner).Hash -cne 'B91945EF77F91388BB8792959AB29C3A49505B5381BA0994723AC0FC6E0502AB'){throw 'Original proven owner changed'}
$taskHead=$CandidateHead
$taskZig='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0/zig.exe'
$taskHelper=Join-Path $taskTree 'tools/ci/native_qualification_ci.ps1'
. $taskHelper
$taskName="highlight-root10db-$Target-$Phase-$Attempt-20261016"
$taskCompileName="highlight-root10db-$Target-compile-$Attempt-20261016"
$taskSteps=@{foundation='native-highlight-root55-foundation';async26='native-async-function-qualification';generator='native-async-generator';'generator-gpa'='native-async-generator-gpa';json='native-ai-json-parse';source51='native-ai-ae7-json-transform';engine='extension-engine';recovery='native-highlight-root463-engine-recovery';host445='native-highlight-complete191-host';operators='native-binary-operators';direct191='native-highlight-complete191-direct'}
$taskPlan=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'gate-plan.json') -Raw|ConvertFrom-Json
foreach($required in @($taskPlan.gates|Where-Object name -ceq $Target).prerequisites){
 $prior=Join-Path $taskEvidence "highlight-root10db-$required-runtime-$Attempt-20261016"
 $owner=Get-Content -LiteralPath "$prior.process.json" -Raw|ConvertFrom-Json
 $post=Get-Content -LiteralPath "$prior-posthash.json" -Raw|ConvertFrom-Json
 if($owner.status -cne 'passed' -or $owner.exit_code -ne 0 -or $post.head -cne $taskHead -or $post.candidate_drift.Count -or @($post.manifests|Where-Object {$_.drift.Count}).Count -or @($post.inventories|Where-Object {$_.drift.Count}).Count -or $post.control_drift.Count -or $post.absence_drift.Count){throw 'Matching complete predecessor runtime/fullpost required before this gate'}
}
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
function Authority-Paths([string]$Root){@(Scoped-Paths $Root|Where-Object {[IO.Path]::GetRelativePath($Root,$_) -notmatch '(^|[\\/])\.git([\\/]|$)'})}
function Assert-PassedTerminal($Record,[string]$Label){
 if($null -eq $Record -or $Record.status -cne 'passed' -or $null -eq $Record.exit_code -or $Record.exit_code -ne 0){throw "$Label requires terminal passed with explicit exit_code0"}
}
function Node-Paths {@(@('C:\Program Files\nodejs\node.exe')+@(Scoped-Paths 'C:/Program Files/nodejs/node_modules/npm')|Sort-Object)}
if((& git -C $taskTree rev-parse HEAD) -cne $taskHead -or (& git -C $taskTree status --porcelain)){throw 'Exact clean sealed current-Root C9h candidate required'}
if((Get-FileHash -LiteralPath $taskZig).Hash -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Pinned Zig0.16 changed'}
if((Get-FileHash -LiteralPath (Join-Path $taskTree 'vendor/quickjs/quickjs.c')).Hash -cne 'E2F988956B452EBACDDC1B24AB45E5F70F7AFB4777F7452EDF1457649B2D1D3B' -or (Get-FileHash -LiteralPath (Join-Path $taskTree 'vendor/quickjs/quickjs.h')).Hash -cne '341CF06F8041B8311D49767026C85C7B859BCFEE3088380F3FFE6D77527052AB'){throw 'Approved C33+9h composition changed'}
$taskExpected26=Join-Path $taskTree 'verification/native-async-function-20261016/expected-tests26.json'
if(!(Test-Path -LiteralPath $taskExpected26 -PathType Leaf)){throw 'Original qualified AF26 metadata authority missing before native work'}
if((Get-FileHash -LiteralPath $taskExpected26).Hash -cne '983E620F3D63ED657102F7C5ECC3A35B584572465BC727931EC5FFC123D0781A'){throw 'Original qualified AF26 metadata authority changed before native work'}
foreach($item in @(
 @{mode='success';hash='D6D410D29A79FCCC24D2C4690F40D66A34A879E6C3B662C102B4B9B7F9AD17F6'},
 @{mode='lookup_failure';hash='5AF3FF3C8BA5433DC6D5945B84A99D08F7AACD2F5FF93A4BF972E58C88AF1BEA'},
 @{mode='safe_factory_failure';hash='C5D2A7A27D1711885B76D74A1CBFFB926B0DA3FEEA65543B354B854350FBAB92'}
)){if((Get-FileHash -LiteralPath (Join-Path $taskTree "src/extensions/fixtures/sdk-highlight-complete191-10_7_3.$($item.mode).json")).Hash -cne $item.hash){throw 'Original genuine Source445 changed'}}
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
$taskPathSets=@{source=@(Authority-Paths $taskSourceRoot);dependencies=@(Authority-Paths $taskRuntimeRoot);compiler=@(Scoped-Paths (Split-Path $taskZig -Parent));node=@(Node-Paths)}
foreach($key in @('source','dependencies','compiler','node')){
 $rows=@(($taskFrozen|Where-Object name -ceq $key).rows)
 if(@(Compare-Object @($rows.path|Sort-Object) $taskPathSets[$key]).Count){throw "$key manifest path inventory mismatch"}
}
$taskBefore=Candidate-Rows
$taskBefore|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-before.json") -Encoding utf8NoBOM
$taskPathSets|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-paths-before.json") -Encoding utf8NoBOM
$taskControls=@($PSCommandPath,$taskHelper,$taskOwner,(Join-Path $PSScriptRoot 'gate-plan.json'),$taskAbsenceManifest,(Join-Path $taskEvidence 'Run-HighlightComplete191Source-20261015.ps1'),(Join-Path $taskEvidence 'Run-HighlightComplete191Series-20261015.ps1'),(Join-Path $taskEvidence 'capture-highlight-complete191-20261015.mjs'),(Join-Path $taskEvidence 'source5ab-observe-20261015.mjs'),(Join-Path $taskEvidence 'highlight-complete191-source-series-terminal-20261015.json'))+@($taskSpecs|ForEach-Object {Join-Path $taskEvidence $_.file})
$taskControls+=$taskExpected26
foreach($mode in @('success','lookup_failure','safe_factory_failure')){
 foreach($suffix in @('output.json','posthash.json','module-observations.json','controls-before.json','json')){
  $file=if($suffix -ceq 'json'){"highlight-complete191-source-$mode-first-20261015.json"}else{"highlight-complete191-source-$mode-first-20261015-$suffix"}
  $taskControls+=Join-Path $taskEvidence $file
 }
 $original=Get-Content -Raw (Join-Path $taskEvidence "highlight-complete191-source-$mode-first-20261015-controls-before.json")|ConvertFrom-Json
 $taskControls+=@($original.path)
}
if($Phase -ceq 'runtime'){
 foreach($suffix in @('.process.json','-posthash.json','-artifacts.json','-metadata.json','-metadata-probe.json','-metadata-probe.stdout.bin')){$taskControls+=Join-Path $taskEvidence "$taskCompileName$suffix"}
 $taskControls+=Join-Path $taskEvidence 'Run-HighlightRoot55NativePhase-20261015.ps1'
 if($Target -ceq 'foundation'){$taskControls+=Join-Path $taskEvidence 'Validate-HighlightFoundationMetadata6-20261015.ps1'}
}
$taskControls=@($taskControls|Sort-Object -Unique|ForEach-Object {@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskControls|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-controls.json") -Encoding utf8NoBOM
function Post-Check {
 $after=Candidate-Rows
 $candidateDrift=@(Compare-Object @($taskBefore|ForEach-Object {"$($_.relative):$($_.sha256)"}) @($after|ForEach-Object {"$($_.relative):$($_.sha256)"}))
 $manifests=@(foreach($item in $taskFrozen){@{name=$item.name;count=$item.rows.Count;drift=@(Check-Rows $item.rows)}})
 $afterPaths=@{source=@(Authority-Paths $taskSourceRoot);dependencies=@(Authority-Paths $taskRuntimeRoot);compiler=@(Scoped-Paths (Split-Path $taskZig -Parent));node=@(Node-Paths)}
 $pathDrift=@(foreach($key in @('source','dependencies','compiler','node')){@{name=$key;count=$afterPaths[$key].Count;drift=@(Compare-Object $taskPathSets[$key] $afterPaths[$key])}})
 $controlDrift=@(Check-Rows $taskControls);$absenceDrift=@(Present-Absent)
 @{head=$taskHead;target=$Target;phase=$Phase;candidate_before=$taskBefore.Count;candidate_after=$after.Count;candidate_drift=$candidateDrift;manifests=$manifests;inventories=$pathDrift;controls=$taskControls.Count;control_drift=$controlDrift;absences=84;absence_drift=$absenceDrift;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 9|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-posthash.json") -Encoding utf8NoBOM
 if($candidateDrift.Count -or @($manifests|Where-Object {$_.drift.Count}).Count -or @($pathDrift|Where-Object {$_.drift.Count}).Count -or $controlDrift.Count -or $absenceDrift.Count){throw 'Frozen native input/post inventory drift'}
}
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
$taskRoots=@(Get-CimInstance Win32_Process -Filter "Name='zig.exe' OR Name='build.exe' OR Name='test.exe'"|Where-Object {$_.Name -ceq 'zig.exe' -or $_.ExecutablePath -like 'C:\Users\adyba\pi-zig*\*'}|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine,CreationDate)
@{free_kib=$taskFree;required_kib=16MB;slot=$Slot;max_native_roots=1;zero_other_native_required=$true;roots=$taskRoots;candidate=$taskHead;target=$Target;phase=$Phase;root_execution_grant=$RootExecutionGrant;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json") -Encoding utf8NoBOM
if($taskFree -lt 16MB -or $taskRoots.Count -ne 0){throw 'Fresh16GiB/zero-other-native serial admission denied'}
if($Phase -ceq 'runtime'){
 $compile=Get-Content -Raw (Join-Path $taskEvidence "$taskCompileName.process.json")|ConvertFrom-Json
 $post=Get-Content -Raw (Join-Path $taskEvidence "$taskCompileName-posthash.json")|ConvertFrom-Json
 $artifacts=@(Get-Content -Raw (Join-Path $taskEvidence "$taskCompileName-artifacts.json")|ConvertFrom-Json)
 $metadata=Get-Content -Raw (Join-Path $taskEvidence "$taskCompileName-metadata.json")|ConvertFrom-Json
 Assert-PassedTerminal $compile 'Prior compile'
 $metadataProbe=Get-Content -Raw (Join-Path $taskEvidence "$taskCompileName-metadata-probe.json")|ConvertFrom-Json
 Assert-PassedTerminal $metadataProbe 'Prior metadata probe'
 if($post.head -cne $taskHead -or $metadata.candidate -cne $taskHead -or $post.candidate_drift.Count -or @($post.manifests|Where-Object {$_.drift.Count}).Count -or @($post.inventories|Where-Object {$_.drift.Count}).Count -or $post.control_drift.Count -or $post.absence_drift.Count -or @(Check-Rows $artifacts).Count -or !$metadata.tests.Count){throw 'Prior matching-head compile/fullpost0/artifact/metadata required'}
 $step="test-$($taskSteps[$Target])";$timeout=300
}else{$step="build-highlight-root10db-$Target";$timeout=1320}
$taskPriorArtifacts=@(Get-ChildItem -LiteralPath (Join-Path $taskTree '.zig-cache') -Recurse -Filter test.exe -File -ErrorAction SilentlyContinue|ForEach-Object FullName)
try{
 & $taskOwner -Executable $taskZig -WorkingDirectory $taskTree -Arguments @('build',$step,'-Doptimize=Debug','-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') -ReceiptBase (Join-Path $taskEvidence $taskName) -TimeoutSeconds $timeout | Out-Null
 $terminal=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.process.json") -Raw|ConvertFrom-Json
 Assert-PassedTerminal $terminal 'Owned native phase'
 if($Phase -ceq 'compile'){
  $installed=Join-Path $taskTree "zig-out/bin/highlight-root10db-$Target.exe"
  $installedHash=(Get-FileHash -LiteralPath $installed).Hash
  $matching=@(Get-ChildItem -LiteralPath (Join-Path $taskTree '.zig-cache/o') -Recurse -Filter test.exe -File|Where-Object {(Get-FileHash -LiteralPath $_.FullName).Hash -ceq $installedHash})
  if($matching.Count -ne 1){throw 'Exactly one hash-matching selected cached artifact required'}
  $binary=$matching[0].FullName
  $artifacts=@(@($matching[0].Directory.GetFiles()|ForEach-Object {@{path=$_.FullName;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}})+@(@{path=$installed;sha256=$installedHash}))
  $artifacts|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-artifacts.json") -Encoding utf8NoBOM
  $request=[byte[]](4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
  $receipt=Join-Path $taskEvidence "$taskName-metadata-probe"
  $probe=Invoke-CiOwnedProcess $binary @('--listen=-') $taskTree $receipt 30 $request
  Assert-PassedTerminal $probe 'Metadata probe'
  if(@(Check-Rows $artifacts).Count -or $probe.executable_sha256 -cne $installedHash){throw 'Compile/metadata artifact identity drift'}
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
  if($Target -ceq 'async26'){
   $required=@(Get-Content -LiteralPath $taskExpected26 -Raw|ConvertFrom-Json)
   if($names.Count -ne 26 -or @(Compare-Object ($required|Sort-Object -CaseSensitive) ($names|Sort-Object -CaseSensitive) -CaseSensitive).Count){throw 'All26 qualified AsyncFunction/AG/JSON/span metadata required on C33+9h'}
  }
  if($Target -ceq 'foundation' -and ($names.Count -ne 6 -or $names[-1] -cne 'extensions.native_durable_storage.test_0')){throw 'Foundation requires five selected tests plus actual imported storage test_0'}
  if($Target -ceq 'direct191' -and @($names|Where-Object {$_ -match 'native actual complete191'}).Count -ne 3){throw 'Direct191 must include exact three named actual tests'}
  if($Target -ceq 'generator-gpa' -and !@($names|Where-Object {$_ -match 'native async generator host GPA'}).Count){throw 'Mandatory generator GPA test absent'}
  if($Target -ceq 'generator' -and @($names|Where-Object {$_ -match 'native async generator functional'}).Count -lt 8){throw 'Mandatory native C-generator functional tests absent'}
  if($Target -ceq 'json' -and !@($names|Where-Object {$_ -match 'native AI JSON'}).Count){throw 'Mandatory native JSON tests absent'}
  if($Target -in @('engine','recovery')){
   $required=@(Select-String -LiteralPath (Join-Path $taskTree 'src/extensions/engine.zig') -Pattern '^test "([^"]+)"'|ForEach-Object {'extensions.engine.test.'+$_.Matches[0].Groups[1].Value})
   if(!$required.Count -or @($required|Where-Object {$_ -cnotin $names}).Count){throw 'Every actual ordinary-engine test must be selected'}
  }
  if($Target -ceq 'recovery'){
   foreach($pattern in @('restores inactive frames after actual native enumeration cancellation','targeted C VM heap budgets','native Root463 dispatch ordinary constructors','native Root463 dispatch ordinary VM stack overflow')){if(@($names|Where-Object {$_.Contains($pattern)}).Count -ne 1){throw "Mandatory recovery metadata absent: $pattern"}}
  }
  if($Target -ceq 'host445' -and @($names|Where-Object {$_ -match 'native actual complete191 host unchanged'}).Count -ne 3){throw 'All three unchanged Source445 host tests required'}
  if($Target -ceq 'operators' -and @($names|Where-Object {$_ -match 'native binary operators preserve guest coercion BigInt exception and borrowed identity'}).Count -ne 1){throw 'Actual14-operator regression absent'}
  if($Target -ceq 'source51' -and @($names|Where-Object {$_ -match 'native ae7 JSON39 and thinking DROP12 match fresh genuine Source51 complete records'}).Count -ne 1){throw 'Genuine current Source51 regression absent'}
  @{binary=$binary;binary_sha256=$probe.executable_sha256;version=$version;tests=$names;count=$names.Count;method='Actual Zig0.16 metadata-only query4 and clean exit0; no run command';candidate=$taskHead;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-metadata.json") -Encoding utf8NoBOM
 }else{
  if(@(Check-Rows $artifacts).Count){throw 'Compiled matching runtime artifact drift'}
  $runtimeText=[IO.File]::ReadAllText((Join-Path $taskEvidence "$taskName.stderr.log"))
  $summary=[regex]::Matches($runtimeText,'Build Summary:[^\r\n]*; (\d+)/(\d+) tests passed')
  if(!$summary.Count -or [int]$summary[-1].Groups[1].Value -ne $metadata.tests.Count -or [int]$summary[-1].Groups[2].Value -ne $metadata.tests.Count){throw 'Actual runtime test totals must match compiled nonempty metadata'}
 }
}finally{Post-Check}
Write-Output "NATIVE_ROOT10DB_C9H_PHASE_PASSED target=$Target phase=$Phase head=$taskHead"
