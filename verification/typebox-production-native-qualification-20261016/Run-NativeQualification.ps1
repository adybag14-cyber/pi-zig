param(
 [Parameter(Mandatory)][ValidateSet('build','metadata','test')][string]$Phase,
 [Parameter(Mandatory)][string]$Attempt,
 [Parameter(Mandatory)][string]$ExpectedHead,
 [Parameter(Mandatory)][string]$RootGrant,
 [string]$BuildAttempt,
 [string]$MetadataAttempt
)
$ErrorActionPreference='Stop'
$taskRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$taskEvidence='C:/Users/adyba/pi-zig-update-evidence-20261003'
$taskSource='C:/Users/adyba/pi-upstream-source-4954d76-20261015'
$taskRuntime='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
$taskCompiler='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0'
$taskNodeRoot='C:/Program Files/nodejs'
$taskOwner=Join-Path $PSScriptRoot 'Invoke-ReviewedSerialOwner.ps1'
$taskContractPath=Join-Path $PSScriptRoot 'qualification-contract.json'
$taskContract=Get-Content -LiteralPath $taskContractPath -Raw|ConvertFrom-Json
$taskGrant=Get-Content -LiteralPath $RootGrant -Raw|ConvertFrom-Json
# A retained Body owner negative is not an execution grant. A reviewed successor
# and an explicit exact-head Root lane release must be supplied before hashing.
if($taskGrant.status -cne 'root_reviewed_typebox_native_release' -or $taskGrant.candidate_head -cne $ExpectedHead -or $taskGrant.phase -cne $Phase -or !$taskGrant.grant_id -or $taskGrant.owner_sha256 -cne (Get-FileHash -LiteralPath $taskOwner).Hash -or $taskGrant.owner_sha256 -ceq $taskContract.historicalOwnerSha256){throw 'Explicit Root release and reviewed owner successor required; historical9B5 owner remains held'}
if((git -C $taskRoot rev-parse HEAD) -cne $ExpectedHead -or @(git -C $taskRoot status --porcelain).Count){throw 'Exact clean sealed qualification candidate required'}
$taskName="typebox-production-$Phase-$Attempt-20261016"
$taskBase=Join-Path $taskEvidence $taskName
if(@(Get-ChildItem -LiteralPath $taskEvidence -Filter "$taskName*" -File).Count){throw 'Fresh unique native qualification attempt required'}
function Hash-Paths($paths){@($paths|Sort-Object -Unique|ForEach-Object{[ordered]@{path=[IO.Path]::GetFullPath($_);sha256=(Get-FileHash -LiteralPath $_).Hash}})}
function Check-Rows($rows){@($rows|Where-Object{!(Test-Path -LiteralPath $_.path -PathType Leaf)-or(Get-FileHash -LiteralPath $_.path).Hash -ine $_.sha256}|ForEach-Object path)}
$taskAuditPath=Join-Path $taskEvidence 'source4954-dependency-contract-audit-20261015.json'
$taskAudit=Get-Content -LiteralPath $taskAuditPath -Raw|ConvertFrom-Json
$taskLinks=@($taskAudit.workspaces|ForEach-Object{[ordered]@{path=[IO.Path]::GetFullPath((Join-Path (Join-Path $taskRuntime 'node_modules') $_.specifier));target=[IO.Path]::GetFullPath((Join-Path $taskRuntime $_.path));type='Junction'}})
$taskAbsences=@($taskAudit.pins|Where-Object status -eq 'platform_optional_absent'|ForEach-Object path)+@($taskAudit.mismatches|ForEach-Object path)
if($taskLinks.Count -ne 16 -or $taskAbsences.Count -ne 84){throw 'Original16 links/84 explicit absences required'}
function Inventory($directory,[string[]]$excluded=@()){
 foreach($entry in Get-ChildItem -LiteralPath $directory -Force){if($entry.Name -in $excluded){continue};if($entry.PSIsContainer){if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){$link=$taskLinks|Where-Object path -eq $entry.FullName;if(!$link -or $entry.LinkType -cne $link.type -or $entry.Target -cne $link.target){throw "Frozen junction inventory drift $($entry.FullName)"};continue};Inventory $entry.FullName $excluded}else{$entry.FullName}}
}
function Compare-Paths($rows,$actual){@(Compare-Object @($rows.path|Sort-Object) @($actual|Sort-Object)).Count}
function Candidate-Paths(){@(Inventory $taskRoot @('.git','.zig-cache','zig-out'))}
$taskSpecs=@(
 @{name='reference';path=(Join-Path $taskEvidence 'source4954-full-manifest-20261015.json');count=1970;root=$taskSource;excluded=@('.git','node_modules')},
 @{name='runtime';path=(Join-Path $taskEvidence 'source4954-runtime-manifest-20261015.json');count=31064;root=$taskRuntime;excluded=@('.git')},
 @{name='node';path=(Join-Path $taskEvidence 'source4954-node-tools-before-20261015.json');count=1774;root=$taskNodeRoot;excluded=@()},
 @{name='compiler';path=(Join-Path $taskEvidence 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json');count=19546;root=$taskCompiler;excluded=@()}
)
$taskFrozen=[ordered]@{}
foreach($spec in $taskSpecs){$parsed=Get-Content -LiteralPath $spec.path -Raw|ConvertFrom-Json;$rows=if($spec.name -eq 'compiler'){@($parsed.inputs)}else{@($parsed)};if($rows.Count -ne $spec.count){throw 'Original full reference/tool inventory count mismatch'};$taskFrozen[$spec.name]=$rows}
$taskFrozen.candidate=Hash-Paths (Candidate-Paths)
$taskFrozen.vendor=Hash-Paths @(Inventory (Join-Path $taskRoot 'vendor'))
$taskFrozen.controls=Hash-Paths (@($PSCommandPath,$taskOwner,$taskContractPath,$RootGrant,$taskAuditPath,(Join-Path $taskRoot 'tools/ci/native_qualification_ci.ps1'))+@($taskSpecs.path))
$taskFrozen.fixtures=@($taskContract.fixtures|ForEach-Object{[ordered]@{path=(Join-Path $taskRoot $_.path);sha256=$_.sha256}})
function Verify-Frozen {
 $checks=@()
 foreach($pair in $taskFrozen.GetEnumerator()){$drift=@(Check-Rows $pair.Value);$checks+=@{name=$pair.Key;files=@($pair.Value).Count;drift=$drift.Count;changed=$drift}}
 foreach($spec in $taskSpecs){$paths=if($spec.name -eq 'node'){@((Join-Path $taskNodeRoot 'node.exe'))+@(Inventory (Join-Path $taskNodeRoot 'node_modules/npm'))}else{@(Inventory $spec.root $spec.excluded)};$checks+=@{name=$spec.name+'_inventory';drift=(Compare-Paths $taskFrozen[$spec.name] $paths)}}
 $checks+=@{name='candidate_inventory';drift=(Compare-Paths $taskFrozen.candidate (Candidate-Paths))}
 $checks+=@{name='vendor_inventory';drift=(Compare-Paths $taskFrozen.vendor @(Inventory (Join-Path $taskRoot 'vendor')))}
 $checks+=@{name='explicit84_absences';drift=@($taskAbsences|Where-Object{(Test-Path -LiteralPath (Join-Path $taskRuntime $_))-or(Test-Path -LiteralPath (Join-Path $taskSource $_))}).Count}
 $taskLinkDrift=@(foreach($link in $taskLinks){$entry=Get-Item -LiteralPath $link.path -Force -ErrorAction SilentlyContinue;if(!$entry-or$entry.LinkType -cne $link.type-or$entry.Target -cne $link.target){$link.path}})
 $checks+=@{name='explicit16_workspace_junctions';drift=$taskLinkDrift.Count;changed=$taskLinkDrift}
 $checks+=@{name='candidate_head';drift=[int]((git -C $taskRoot rev-parse HEAD) -cne $ExpectedHead)}
 $checks+=@{name='reference_head';drift=[int]((git -C $taskSource rev-parse HEAD) -cne $taskContract.sourceHead)}
 $checks
}
$taskFrozen|ConvertTo-Json -Depth 7|Set-Content -LiteralPath "$taskBase-frozen.json" -Encoding utf8NoBOM
$taskBefore=@(Verify-Frozen)
$taskBefore|ConvertTo-Json -Depth 6|Set-Content -LiteralPath "$taskBase-before.json" -Encoding utf8NoBOM
if(@($taskBefore|Where-Object drift -ne 0).Count){throw 'Full strict TypeBox prehash/inventory failed'}
$taskFrozenHash=(Get-FileHash -LiteralPath "$taskBase-frozen.json").Hash
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1024
$taskOther=@(Get-CimInstance Win32_Process|Where-Object{$_.ExecutablePath-and($_.ExecutablePath.EndsWith('\zig.exe')-or$_.ExecutablePath-like'C:\Users\adyba\pi-zig*\.zig-cache\*\build.exe'-or$_.ExecutablePath-like'C:\Users\adyba\pi-zig*\.zig-cache\*\test.exe')})
@{minimum_free_bytes=12GB;pressure_stop_bytes=4GB;free_bytes=$taskFree;other_native=@($taskOther|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine,CreationDate);root_grant=$taskGrant;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath "$taskBase-admission.json" -Encoding utf8NoBOM
if($taskFree -lt 12GB -or $taskOther.Count){throw 'Fresh12GiB/zero-other-native admission rejected; no launch'}
$taskBinary=$null
if($Phase -ne 'build'){
 if(!$BuildAttempt){throw 'Matching sealed compile attempt required'}
 $taskBuildBase=Join-Path $taskEvidence "typebox-production-build-$BuildAttempt-20261016"
 $build=Get-Content -LiteralPath "$taskBuildBase-validation.json" -Raw|ConvertFrom-Json
 if($build.status -cne 'passed' -or $build.candidate_head -cne $ExpectedHead){throw 'Matching terminal0 full-post0 compile required'}
 $prior=Get-Content -LiteralPath "$taskBuildBase-frozen.json" -Raw|ConvertFrom-Json
 foreach($name in @('candidate','vendor','reference','runtime','node','compiler','fixtures')){if(@(Compare-Object @($prior.$name|ForEach-Object{"$($_.path):$($_.sha256)"}) @($taskFrozen[$name]|ForEach-Object{"$($_.path):$($_.sha256)"})).Count){throw "Between compile/runtime frozen drift $name"}}
 $taskBinary=$build.binary
 if(!(Test-Path -LiteralPath $taskBinary.path)-or(Get-FileHash -LiteralPath $taskBinary.path).Hash -cne $taskBinary.sha256){throw 'Exact compiled test executable required'}
 if($Phase -eq 'test'){$meta=Get-Content -LiteralPath (Join-Path $taskEvidence "typebox-production-metadata-$MetadataAttempt-20261016-validation.json") -Raw|ConvertFrom-Json;if(!$MetadataAttempt-or$meta.status -cne 'passed'-or$meta.candidate_head -cne $ExpectedHead-or$meta.binary.sha256 -cne $taskBinary.sha256){throw 'Exact original test metadata must pass before runtime'}}
}
$taskBeforeBinaries=@(Get-ChildItem -LiteralPath (Join-Path $taskRoot '.zig-cache/o') -Filter test.exe -Recurse -File -ErrorAction SilentlyContinue|ForEach-Object FullName)
$taskBeforeBinaries|ConvertTo-Json -AsArray|Set-Content -LiteralPath "$taskBase-before-binaries.json" -Encoding utf8NoBOM
$taskFailure=$null;$taskMetadata=$null
try{
 if($Phase -eq 'metadata'){
  $taskQueryFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1024
  $taskQueryOther=@(Get-CimInstance Win32_Process|Where-Object{$_.ExecutablePath-and($_.ExecutablePath.EndsWith('\zig.exe')-or$_.ExecutablePath-like'C:\Users\adyba\pi-zig*\.zig-cache\*\build.exe'-or$_.ExecutablePath-like'C:\Users\adyba\pi-zig*\.zig-cache\*\test.exe')})
  if($taskQueryFree -lt 12GB-or$taskQueryOther.Count){throw 'Fresh metadata launch12GiB/zero-other-native admission failed'}
  . (Join-Path $taskRoot 'tools/ci/native_qualification_ci.ps1')
  $taskMetadata=Read-CiTestMetadata $taskBinary.path $taskRoot "$taskBase-query" $taskContract.expectedTests.Count
  if(@(Compare-Object @($taskMetadata.tests|Sort-Object -CaseSensitive) @($taskContract.expectedTests|Sort-Object -CaseSensitive) -CaseSensitive).Count){throw 'Exact actual Zig test metadata names mismatch'}
 }else{
  & $taskOwner -Executable (Join-Path $taskCompiler 'zig.exe') -WorkingDirectory $taskRoot -Arguments @('build',"$Phase-native-typebox-production-source",'-Doptimize=Debug','-j1','--test-timeout','120s','--summary','all') -ReceiptBase $taskBase -TimeoutSeconds $(if($Phase -eq 'build'){1320}else{300})
 }
}catch{$taskFailure=[string]$_}finally{
 $taskAfter=@(Verify-Frozen)
 if((Get-FileHash -LiteralPath "$taskBase-frozen.json").Hash -cne $taskFrozenHash){$taskAfter+=@{name='frozen_registry';drift=1}}
 if($taskBinary-and(Get-FileHash -LiteralPath $taskBinary.path).Hash -cne $taskBinary.sha256){$taskAfter+=@{name='compiled_binary';drift=1}}
 $taskAfter|ConvertTo-Json -Depth 6|Set-Content -LiteralPath "$taskBase-after.json" -Encoding utf8NoBOM
}
if(@($taskAfter|Where-Object drift -ne 0).Count){throw 'Full strict TypeBox posthash/inventory failed'}
if($taskFailure){throw $taskFailure}
if($Phase -eq 'build'){$new=@(Get-ChildItem -LiteralPath (Join-Path $taskRoot '.zig-cache/o') -Filter test.exe -Recurse -File|Where-Object FullName -NotIn $taskBeforeBinaries);if($new.Count -ne 1){throw 'Exactly one newly compiled shared graph executable required'};$taskBinary=@{path=$new[0].FullName;sha256=(Get-FileHash -LiteralPath $new[0].FullName).Hash}}
if($Phase -eq 'test'){$log=[IO.File]::ReadAllText("$taskBase.stderr.log");foreach($marker in @('TYPEBOX_COMPILE_SOURCE_PARITY cases=80','TYPEBOX_PROVIDER_SCHEMA_SOURCE_PARITY cases=52','TYPEBOX_OPERATOR_SOURCE_PARITY cases=396')){if(!$log.Contains($marker)){throw 'Missing original shared graph replay marker'}};if($log -notmatch '4/4 tests passed' -or $log -match '\bskip(?:ped)?\b'){throw 'Exactly all metadata-selected4 native tests must execute and pass without skips'}}
@{status='passed';phase=$Phase;candidate_head=$ExpectedHead;binary=$taskBinary;metadata=$taskMetadata;source_replays=@(80,52,396);full_posthash_drift=0;full_pi_qualified=$false;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath "$taskBase-validation.json" -Encoding utf8NoBOM
Write-Output "TYPEBOX_NATIVE_$($Phase.ToUpper())_PASSED_FULL_POSTHASH0"
