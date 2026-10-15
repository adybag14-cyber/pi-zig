param([ValidateSet('Debug','ReleaseSafe')][string]$Mode='Debug',[string]$Attempt='fourth',[int]$Slot=3)
$ErrorActionPreference='Stop'
$ev=$PSScriptRoot
$tree='C:/Users/adyba/pi-zig-native-url-errors-20261015'
$head='1c3d01e42328de7353c5102fd910da41cae336ae'
$name="url-node24-source40-native-$($Mode.ToLowerInvariant())-$Attempt-20261015"
$zig='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0/zig.exe'
$source='C:/Users/adyba/pi-upstream-source-ae7b16d-20261015'
$runtime='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
$helper=Join-Path $tree 'tools/ci/native_qualification_ci.ps1'
$compilerManifest=Join-Path $ev 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json'
$readinessPath=Join-Path $tree 'verification/native-url-constructor-node24-source40-20261015/native-readiness.json'
. $helper
function Rows($paths){@($paths|Sort-Object -Unique|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})}
function Drift($rows){$changed=[Collections.Generic.List[string]]::new();foreach($row in $rows){if(!(Test-Path -LiteralPath $row.path -PathType Leaf)){$changed.Add($row.path);continue};$stream=[IO.File]::OpenRead($row.path);try{$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()};if($hash -cne $row.sha256.ToUpperInvariant()){$changed.Add($row.path)}};@($changed)}
function CandidatePaths{@(git -c gc.auto=0 -c maintenance.auto=false -c pack.threads=2 -C $tree ls-files --cached --others --exclude-standard|ForEach-Object{$path=Join-Path $tree $_;if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw "Candidate input absent: $_"};$path}|Sort-Object -Unique)}
function ScopedPaths([string]$root){@(Get-ChildItem -LiteralPath $root -File -Recurse -Force|ForEach-Object{if($_.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked scoped input refused'};$_.FullName}|Sort-Object -Unique)}
function SourcePaths{@(@(git -c gc.auto=0 -c maintenance.auto=false -c pack.threads=2 -C $source ls-files --cached --others --exclude-standard|ForEach-Object{Join-Path $source $_})+@(Get-ChildItem -LiteralPath (Join-Path $source 'packages/ai/src/providers/data') -File -Force|ForEach-Object FullName)|Sort-Object -Unique)}
function NodePaths{@(@('C:/Program Files/nodejs/node.exe')+@(ScopedPaths 'C:/Program Files/nodejs/node_modules/npm')|ForEach-Object{[IO.Path]::GetFullPath($_)}|Sort-Object -Unique)}
function PauseCheck{if(Test-Path -LiteralPath (Join-Path $ev 'url-native-20261015.pause')){throw 'Scoped URL batch paused; no further phase admitted'}}
function Admit([string]$phase){PauseCheck;$free=[long](Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1024;$roots=@(Get-CimInstance Win32_Process -Filter "Name='zig.exe'"|Where-Object{$_.CommandLine -match '\sbuild\s'}|Select-Object ProcessId,CommandLine);[ordered]@{phase=$phase;root_slot=$Slot;free_bytes=$free;required_bytes=16GB;other_native_roots=$roots;max_roots=4;jobs=1;compile_seconds=1320;runtime_seconds=300;test_seconds=120;new_test_await_ms=10000;settle_seconds=10;candidate=$head;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $ev "$name-$phase-admission.json") -Encoding utf8NoBOM;if($free -lt 16GB -or $roots.Count -ge 4){throw 'Fresh normal16GiB/max4 admission denied'}}
function AbsentOwner($record){$live=Get-CimInstance Win32_Process -Filter "ProcessId = $($record.pid)";if($live -and [Math]::Abs((([DateTimeOffset]$live.CreationDate).UtcDateTime-([DateTimeOffset]$record.created_utc).UtcDateTime).Ticks) -le 10){throw 'Owned process remains present'};return @{pid=$record.pid;created_utc=$record.created_utc;owned_root_absent=$true;pid_reused=[bool]$live}}
if((git -c gc.auto=0 -c maintenance.auto=false -c pack.threads=2 -C $tree rev-parse HEAD) -cne $head -or @(git -c gc.auto=0 -c maintenance.auto=false -c pack.threads=2 -C $tree status --porcelain).Count){throw 'Exact sealed clean URL candidate required'}
if((git -c gc.auto=0 -c maintenance.auto=false -c pack.threads=2 -C $source rev-parse HEAD) -cne 'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d'){throw 'Immutable Source head changed'}
if((Get-FileHash -LiteralPath $zig).Hash -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Pinned Zig changed'}
if((Get-FileHash -LiteralPath (Join-Path $tree 'src/extensions/fixtures/url-errors-node24.json')).Hash -cne '31093DADB66AD33E30C1A5BAAE4329C5B5169341A03642B4319361E9324D5832'){throw 'Original Node40 fixture changed'}
$originalOwner=Get-Content -LiteralPath (Join-Path $ev 'url-constructor-node24-source40-first-20261015.json') -Raw|ConvertFrom-Json
$originalPost=Get-Content -LiteralPath (Join-Path $ev 'url-constructor-node24-source40-first-20261015-posthash.json') -Raw|ConvertFrom-Json
if($originalOwner.status -cne 'passed' -or $originalOwner.exit_code -ne 0 -or @($originalPost.manifests|Where-Object drift -ne 0).Count -or $originalPost.extra_control_drift.Count -or $originalPost.absent_dependency_drift.Count -or $originalPost.control_manifest_drift){throw 'Genuine Node40 terminal/fullpost0 prerequisite missing'}
$originalControls=@(Get-Content -LiteralPath (Join-Path $ev 'url-constructor-node24-source40-first-20261015-extra-before.json') -Raw|ConvertFrom-Json)
if(@(Drift $originalControls).Count){throw 'Original sealed Source40 input/caller/runner controls changed'}
$readiness=Get-Content -LiteralPath $readinessPath -Raw|ConvertFrom-Json
if($readiness.expected_named_tests -ne 17 -or @($readiness.required_names).Count -ne 17){throw 'Exact seventeen named URL regressions required'}
$specs=@(@{name='source';file='sourceae7-full-manifest-20261015.json';count=1968},@{name='dependencies';file='sourceae7-runtime-manifest-20261015.json';count=31064},@{name='node';file='sourceae7-node-tools-before-20261015.json';count=1774},@{name='compiler';file='durable-latest89-full-inspect-53ae-tool-prehash-20261011.json';count=19546})
$frozen=@();foreach($spec in $specs){$data=Get-Content -LiteralPath (Join-Path $ev $spec.file) -Raw|ConvertFrom-Json;$rows=if($spec.name -ceq 'compiler'){@($data.inputs)}else{@($data)};if($rows.Count -ne $spec.count -or @(Drift $rows).Count){throw "Full $($spec.name) prehash/count drift"};$frozen+=@{name=$spec.name;rows=$rows}}
$preparationPath=Join-Path $ev 'sourceae7-preparation-controls-20261015.json'
$preparation=@(Get-Content -LiteralPath $preparationPath -Raw|ConvertFrom-Json)
if((Get-FileHash -LiteralPath $preparationPath).Hash -cne '3C84A2C828A906617A50E5C568BA9DA9CAEC7FD79D202C20CA7D6087DD02637C' -or $preparation.Count -ne 5 -or @(Drift $preparation).Count){throw 'Exact ae7 preparation controls changed'}
$contract=Get-Content -LiteralPath (Join-Path $ev 'sourceae7-dependency-contract-audit-20261015.json') -Raw|ConvertFrom-Json
if($contract.latestHead -cne 'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d' -or $contract.installed_metadata_verified -ne 281 -or $contract.platform_optional_absent_records -ne 80 -or $contract.historical_missing_records_retained -ne 4){throw 'Source dependency contract changed'}
$absencePaths=@($contract.pins|Where-Object status -eq 'platform_optional_absent'|ForEach-Object path)+@($contract.mismatches|ForEach-Object path)
$absent=@($absencePaths|ForEach-Object{@{source=Join-Path $source $_;runtime=Join-Path $runtime $_}})
function PresentAbsent{@($absent|Where-Object{(Test-Path -LiteralPath $_.source) -or (Test-Path -LiteralPath $_.runtime)})}
if($absent.Count -ne 84 -or @(PresentAbsent).Count){throw 'Exact Source/runtime84 historical absences changed'}
$before=Rows (CandidatePaths);$vendor=Rows (ScopedPaths (Join-Path $tree 'vendor'))
$paths=@{source=@(SourcePaths);dependencies=@(ScopedPaths $runtime);compiler=@(ScopedPaths (Split-Path $zig -Parent));node=@(NodePaths);vendor=@(ScopedPaths (Join-Path $tree 'vendor'))}
foreach($key in @('source','compiler','node')){$manifestRows=@(($frozen|Where-Object name -ceq $key).rows);if(@(Compare-Object @($manifestRows.path|ForEach-Object{[IO.Path]::GetFullPath($_)}|Sort-Object -Unique) @($paths[$key]|ForEach-Object{[IO.Path]::GetFullPath($_)}|Sort-Object -Unique)).Count){throw "$key full scoped path inventory mismatch"}}
$controlPaths=@($PSCommandPath,$helper,$readinessPath,$compilerManifest,$preparationPath,(Join-Path $ev 'sourceae7-preparation-readiness-20261015.json'),(Join-Path $ev 'sourceae7-dependency-contract-audit-20261015.json'),(Join-Path $ev 'sourceae7-observe-20261015.mjs'),(Join-Path $ev 'url-errors-node24-capture-20261015.mjs'),(Join-Path $ev 'Run-URLConstructorNode24Source-20261015.ps1'),(Join-Path $ev 'Invoke-OwnedEeSourceJob-20261012.ps1'))+@($specs|ForEach-Object{Join-Path $ev $_.file})+@(Get-ChildItem -LiteralPath $ev -Filter 'url-constructor-node24-source40-first-20261015*' -File|ForEach-Object FullName)
$controlPaths+=@($originalControls.path)
$controls=Rows $controlPaths
foreach($entry in @(@{suffix='candidate-before';rows=$before},@{suffix='vendor-before';rows=$vendor},@{suffix='controls-before';rows=$controls},@{suffix='absences-before';rows=$absent},@{suffix='inventories-before';rows=$paths})){$entry.rows|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $ev "$name-$($entry.suffix).json") -Encoding utf8NoBOM}
foreach($phaseReceipt in @('compile','runtime','metadata-probe')){if(Test-Path -LiteralPath (Join-Path $ev "$name-$phaseReceipt.json")){throw 'Refuse immutable native receipt replay'}}
$compile=$null;$run=$null;$probe=$null;$artifacts=@();$metadata=$null
function Post([string]$phase){$after=Rows (CandidatePaths);$candidateDrift=@(Compare-Object @($before|ForEach-Object{"$($_.path):$($_.sha256)"}) @($after|ForEach-Object{"$($_.path):$($_.sha256)"}));$refs=@(foreach($item in $frozen){@{name=$item.name;count=$item.rows.Count;drift=@(Drift $item.rows)}});$pathAfter=@{source=@(SourcePaths);dependencies=@(ScopedPaths $runtime);compiler=@(ScopedPaths (Split-Path $zig -Parent));node=@(NodePaths);vendor=@(ScopedPaths (Join-Path $tree 'vendor'))};$inventoryDrift=@(foreach($key in @('source','dependencies','compiler','node','vendor')){@{name=$key;before=$paths[$key].Count;after=$pathAfter[$key].Count;drift=@(Compare-Object $paths[$key] $pathAfter[$key])}});$result=[ordered]@{phase=$phase;head=$head;head_after=(git -c gc.auto=0 -c maintenance.auto=false -c pack.threads=2 -C $tree rev-parse HEAD);candidate_before=$before.Count;candidate_after=$after.Count;candidate_drift=$candidateDrift;vendor=$vendor.Count;vendor_drift=@(Drift $vendor);references=$refs;inventories=$inventoryDrift;controls=$controls.Count;control_drift=@(Drift $controls);preparation_drift=@(Drift $preparation);absences84=$absent.Count;absence_drift=@(PresentAbsent);artifacts=$artifacts.Count;artifact_drift=@(Drift $artifacts);compile=if($compile){$compile.status}else{'not_run'};runtime=if($run){$run.status}else{'not_run'};metadata_count=if($metadata){$metadata.count}else{$null};full_pi_qualified=$false;public_activation=$false;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')};$result|ConvertTo-Json -Depth 9|Set-Content -LiteralPath (Join-Path $ev "$name-$phase-posthash.json") -Encoding utf8NoBOM;if($result.head_after -cne $head -or $candidateDrift.Count -or $result.vendor_drift.Count -or $result.control_drift.Count -or $result.preparation_drift.Count -or $result.absence_drift.Count -or $result.artifact_drift.Count -or @($refs|Where-Object{$_.drift.Count}).Count -or @($inventoryDrift|Where-Object{$_.drift.Count}).Count){throw 'Full native freeze posthash/inventory drift'};return $result}
function ReadMetadata([string]$binary){
 $request=[byte[]](4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
 $receipt=Join-Path $ev "$name-metadata-probe"
 $script:probe=Invoke-CiOwnedProcess $binary @('--listen=-') $tree $receipt 30 $request
 $probeAbsent=AbsentOwner $script:probe
 $bytes=[IO.File]::ReadAllBytes("$receipt.stdout.bin");$offset=0;$names=@();$version=$null
 while($offset -lt $bytes.Length){if($offset+8 -gt $bytes.Length){throw 'Truncated metadata header'};$tag=[BitConverter]::ToUInt32($bytes,$offset);$length=[BitConverter]::ToUInt32($bytes,$offset+4);$offset+=8;if($length -gt 1MB -or $offset+$length -gt $bytes.Length){throw 'Metadata bounds mismatch'};if($tag -eq 0){$version=[Text.Encoding]::UTF8.GetString($bytes,$offset,$length)}elseif($tag -eq 3){$strings=[BitConverter]::ToUInt32($bytes,$offset);$count=[BitConverter]::ToUInt32($bytes,$offset+4);if(!$count -or $names.Count -or $length -ne 8+8*$count+$strings){throw 'Exact nonempty metadata array required'};$start=$offset+8+8*$count;for($i=0;$i -lt $count;$i++){$at=[BitConverter]::ToUInt32($bytes,$offset+8+4*$i);$panic=[BitConverter]::ToUInt32($bytes,$offset+8+4*$count+4*$i);if($panic -or $at -ge $strings){throw 'Unexpected panic/offset metadata'};$end=$at;while($end -lt $strings -and $bytes[$start+$end] -ne 0){$end++};if($end -eq $strings){throw 'Unterminated metadata name'};$names+=[Text.Encoding]::UTF8.GetString($bytes,$start+$at,$end-$at)}}else{throw "Unexpected metadata-only tag $tag"};$offset+=$length}
 $named=@($names|Where-Object{$_ -notmatch '\.test_0$'});$unnamed=@($names|Where-Object{$_ -match '\.test_0$'})
 if($names.Count -ne 19 -or $unnamed.Count -ne 2 -or @(Compare-Object @($unnamed|Sort-Object) @('extension_node_url_test.test_0','extensions.native_durable_storage.test_0'|Sort-Object)).Count){throw 'Actual nineteen-entry URL metadata including exact two imported wrappers required'}
 if($version -cne '0.16.0' -or $names.Count -ne @($names|Sort-Object -Unique).Count -or $named.Count -ne 17 -or @(Compare-Object @($named|Sort-Object) @($readiness.required_names|Sort-Object)).Count){throw 'Every exact seventeen named URL test must occur once in actual metadata; only genuine unnamed wrappers may be additional'}
 return [ordered]@{binary=$binary;binary_sha256=$script:probe.executable_sha256;version=$version;tests=$names;count=$names.Count;named_count=$named.Count;unnamed_count=$unnamed.Count;unnamed_tests=$unnamed;probe_absence=$probeAbsent;source40_expected_sha256='31093DADB66AD33E30C1A5BAAE4329C5B5169341A03642B4319361E9324D5832';method='Actual Zig0.16 metadata-only query4 and exit0; no run_test command';candidate=$head}
}
try{
 Admit 'compile'
 $priorArtifacts=@(Get-ChildItem -LiteralPath (Join-Path $tree '.zig-cache') -Recurse -Filter test.exe -File -ErrorAction SilentlyContinue|ForEach-Object FullName)
 try{$compile=Invoke-CiOwnedProcess $zig @('build','build-extension-url',"-Doptimize=$Mode",'-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') $tree (Join-Path $ev "$name-compile") 1320}finally{if(Test-Path -LiteralPath (Join-Path $ev "$name-compile.json")){$compile=Get-Content -LiteralPath (Join-Path $ev "$name-compile.json") -Raw|ConvertFrom-Json};$null=Post 'compile'}
 if(!$compile -or $compile.status -cne 'passed'){throw 'Compile prerequisite failed; runtime refused'}
 $compileAbsent=AbsentOwner $compile
 $newArtifacts=@(Get-ChildItem -LiteralPath (Join-Path $tree '.zig-cache') -Recurse -Filter test.exe -File|Where-Object{$_.FullName -notin $priorArtifacts})
 if($newArtifacts.Count -ne 1){throw "Exactly one fresh compiled URL test artifact required; found $($newArtifacts.Count)"}
 $artifacts=Rows @(Get-ChildItem -LiteralPath $newArtifacts[0].DirectoryName -File|ForEach-Object FullName)
 $artifacts|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $ev "$name-artifacts.json") -Encoding utf8NoBOM
 Admit 'metadata'
 $metadata=ReadMetadata $newArtifacts[0].FullName
 $metadata|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $ev "$name-metadata.json") -Encoding utf8NoBOM
 $null=Post 'metadata'
 Admit 'runtime'
 $run=Invoke-CiOwnedProcess $zig @('build','test-extension-url',"-Doptimize=$Mode",'-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') $tree (Join-Path $ev "$name-runtime") 300
 $runAbsent=AbsentOwner $run
 $runtimeLog=Get-Content -LiteralPath (Join-Path $ev "$name-runtime.stderr.log") -Raw
 $summary=[regex]::Matches($runtimeLog,'(\d+)/(\d+) tests passed')
 if($summary.Count -ne 1 -or [int]$summary[0].Groups[1].Value -ne $metadata.count -or [int]$summary[0].Groups[2].Value -ne $metadata.count){throw 'Runtime must report exactly every compiled metadata test passed'}
}finally{if(Test-Path -LiteralPath (Join-Path $ev "$name-runtime.json")){$run=Get-Content -LiteralPath (Join-Path $ev "$name-runtime.json") -Raw|ConvertFrom-Json};$post=Post 'terminal';$post|ConvertTo-Json -Depth 9}
if(!$compile -or $compile.status -cne 'passed' -or !$run -or $run.status -cne 'passed'){throw 'Native URL pair failed'}
[ordered]@{candidate=$head;mode=$Mode;source_cases=40;named_tests=17;metadata_count=$metadata.count;unnamed_wrappers=$metadata.unnamed_count;compile_absence=$compileAbsent;runtime_absence=$runAbsent;terminal='passed';all_posthash_zero=$true;full_pi_qualified=$false;public_activation=$false}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $ev "$name-validation.json") -Encoding utf8NoBOM
Write-Output 'ACTUAL_NODE40_AND_ALL_NATIVE_URL_REGRESSIONS_FROZEN_PAIR_PASSED'






