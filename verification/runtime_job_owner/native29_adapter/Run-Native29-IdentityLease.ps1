param(
 [Parameter(Mandatory)][string]$RootGrantPath,
 [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,100}$')][string]$RunId,
 [Parameter(Mandatory)][ValidateSet('BuildQuery','RuntimeOnly')][string]$Mode
)
$ErrorActionPreference='Stop'
$taskContainer='C:\Users\adyba\pi-zig'
$taskRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$taskCompiler=Join-Path $taskContainer 'toolchain/zig-x86_64-windows-0.16.0'
$taskZig=Join-Path $taskCompiler 'zig.exe'
$taskGit='C:\Program Files\Git\cmd\git.exe'
$taskCi=Join-Path $taskContainer 'main/tools/ci/native_qualification_ci.ps1'
$taskProtocol=Join-Path $taskContainer 'main/tools/ci/Invoke-NativeTestProtocol.ps1'
$taskClassifier=Join-Path $PSScriptRoot 'Get-ModelsNativeCandidates.ps1'
$taskNames=Join-Path $PSScriptRoot 'declared-tests.authority.json'
$taskCoreMap=Join-Path $taskRoot 'verification/runtime_job_owner/packet-v15/controller36-source-map.json'
$taskFixtureMap=Join-Path $taskRoot 'verification/runtime_job_owner/packet-v15/fixture45-source-map.json'
$taskFixtureManifest=Join-Path $taskRoot 'verification/runtime_job_owner/controls/source-v14.manifest.json'
$taskCompilerAuthority=Join-Path $taskContainer 'evidence/durable-latest89-full-inspect-53ae-tool-prehash-20261011.json'
$taskDriverHash=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
$taskGrant=Get-Content -LiteralPath $RootGrantPath -Raw|ConvertFrom-Json
function Assert-TaskPhysicalAncestors {param([string]$Path)
 $taskAbsolute=[IO.Path]::GetFullPath($Path)
 $taskProbe=[IO.Path]::GetPathRoot($taskAbsolute)
 foreach($taskPiece in $taskAbsolute.Substring($taskProbe.Length).Split([char]92)){
  if(!$taskPiece){continue};$taskProbe=Join-Path $taskProbe $taskPiece
  try{$taskItem=Get-Item -LiteralPath $taskProbe -Force -ErrorAction Stop}
  catch{if($_.CategoryInfo.Category -eq [System.Management.Automation.ErrorCategory]::ObjectNotFound){break};throw}
  if($taskItem.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Unapproved linked authority/output ancestor'}
  if(!$taskItem.PSIsContainer){throw 'Expected physical directory ancestor'}
 }
}
$taskNow=[DateTimeOffset]::UtcNow
$taskScope=if($Mode -ceq 'BuildQuery'){'ROOT-NATIVE29-BUILD-QUERY-SERIAL'}else{'ROOT-NATIVE29-RUNTIME-SERIAL'}
if($taskGrant.authorized -ne $true -or $taskGrant.scope -cne $taskScope -or $taskGrant.run_id -cne $RunId -or
 $taskGrant.driver_sha256 -cne $taskDriverHash -or $taskGrant.candidate_root -cne $taskRoot -or
 $taskGrant.candidate_head -cnotmatch '^[0-9a-f]{40}$'){throw 'Exact fresh reviewed Root Native29 grant required'}
$taskIssued=[DateTimeOffset]$taskGrant.issued_utc;$taskExpires=[DateTimeOffset]$taskGrant.expires_utc
if($taskIssued -gt $taskNow -or $taskNow -gt $taskExpires -or $taskExpires -le $taskIssued -or
 ($taskExpires-$taskIssued).TotalSeconds -gt 300){throw 'Fresh bounded Root grant required'}
$taskWorktreesPrefix=([IO.Path]::GetFullPath((Join-Path $taskContainer 'worktrees'))).TrimEnd([char]92)+'\'
$taskEvidencePrefix=([IO.Path]::GetFullPath((Join-Path $taskContainer 'evidence'))).TrimEnd([char]92)+'\'
$taskProofRoot=[IO.Path]::GetFullPath([string]$taskGrant.proof_root)
if(!$taskRoot.StartsWith($taskWorktreesPrefix,[StringComparison]::OrdinalIgnoreCase) -or
 !$taskProofRoot.StartsWith($taskEvidencePrefix,[StringComparison]::OrdinalIgnoreCase) -or $taskProofRoot -cne $taskGrant.proof_root){
 throw 'Contained candidate/evidence roots required'
}
Assert-TaskPhysicalAncestors $taskRoot;Assert-TaskPhysicalAncestors $taskProofRoot
if((Get-FileHash -LiteralPath $taskCi).Hash -cne '607BEDBB91FE318D214CD2C3B9C83D80437335C0062C320C0EACB3A745B38285' -or
 (Get-FileHash -LiteralPath $taskProtocol).Hash -cne '39F273D35A5B28E9D60FBE93355828314458A67FB472D60E0A8A6D4DD1FB704D' -or
 (Get-FileHash -LiteralPath $taskClassifier).Hash -cne '3413A2A50B4D4C3BFF8709E4EE08C76BE449AAB1EDCB1E0C5C167DC7A804E301'){
 throw 'Canonical CI607/Protocol39F/classifier bytes differ'
}
. $taskCi
. $taskProtocol
. $taskClassifier
foreach($taskPin in @(@{path=$taskNames;hash=$taskGrant.declared_names_sha256},@{path=$taskCoreMap;hash=$taskGrant.controller36_map_sha256},
 @{path=$taskFixtureMap;hash=$taskGrant.fixture45_map_sha256},@{path=$taskFixtureManifest;hash=$taskGrant.fixture_source_manifest_sha256})){
 if((Get-FileHash -LiteralPath $taskPin.path).Hash -cne $taskPin.hash){throw 'Reviewed adapter source authority differs'}
}
$taskAuthority=Get-Content -LiteralPath $taskNames -Raw|ConvertFrom-Json
$taskRequired=@($taskAuthority.tests)
if($taskAuthority.planned_declarations -ne 29 -or $taskRequired.Count -ne 29 -or
 @($taskRequired|Sort-Object -Unique).Count -ne 29 -or $taskAuthority.actual_metadata_observed -ne $false){
 throw 'Every distinct declared Native29 full-name authority is required'
}
$taskProof=Join-Path $taskProofRoot $RunId
if(Test-Path -LiteralPath $taskProof){throw 'Fresh proof/output paths required; no restart or proof overwrite'}
New-Item -ItemType Directory -Path $taskProof -ErrorAction Stop|Out-Null
Copy-Item -LiteralPath $RootGrantPath -Destination (Join-Path $taskProof 'root-grant.json') -ErrorAction Stop
$taskAdmissionHistory=[Collections.Generic.List[object]]::new()
$taskArtifactPins=$null;$taskBuildMatch=$null;$taskBefore=$null
function Save-TaskJson {param($Value,[string]$Name) ConvertTo-Json -InputObject $Value -Depth 16|Set-Content -LiteralPath (Join-Path $taskProof $Name) -Encoding utf8NoBOM}
function Get-TaskNativeRoots {
 $taskRows=@(Get-CimInstance Win32_Process -OperationTimeoutSec 3 -ErrorAction Stop)
 if(!$taskRows.Count){throw 'Successful nonempty native process census required'}
 $taskBase=@(Get-ModelsNativeCandidates -Rows $taskRows -Container $taskContainer)
 $taskSeen=[Collections.Generic.HashSet[uint32]]::new()
 foreach($taskRow in $taskBase){[void]$taskSeen.Add([uint32]$taskRow.ProcessId);$taskRow}
 # The actor is an exact additional role. Its fresh out/bin path is not a
 # .zig-cache/zig-out path; a live/partial actor row must never disappear from
 # the conservative census just because its basename is not test.exe.
 foreach($taskRow in $taskRows){
  $taskActorNamed=([string]$taskRow.Name) -ieq 'runtime-job-owner-actor.exe'
  $taskActorImage=([string]$taskRow.ExecutablePath).EndsWith('\runtime-job-owner-actor.exe',[StringComparison]::OrdinalIgnoreCase)
  $taskActorCommand=([string]$taskRow.CommandLine) -imatch '\\runtime-job-owner-actor\.exe(?:["\s]|$)'
  if((!$taskActorNamed-and!$taskActorImage-and!$taskActorCommand) -or $taskSeen.Contains([uint32]$taskRow.ProcessId)){continue}
  $taskBirth=$null;if($null -ne $taskRow.CreationDate){try{$taskBirth=([DateTimeOffset]$taskRow.CreationDate).UtcDateTime.ToString('o')}catch{}}
  [pscustomobject]@{ProcessId=$taskRow.ProcessId;ParentProcessId=$taskRow.ParentProcessId;Name=$taskRow.Name;
   ExecutablePath=$taskRow.ExecutablePath;CommandLine=$taskRow.CommandLine;created_utc=$taskBirth;
   incomplete_identity=(!$taskRow.ExecutablePath-or!$taskRow.CommandLine-or!$taskBirth);admission_reasons=@('exact_native29_actor_role')}
 }
}
function Assert-TaskAdmission {
 $taskOs=Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 3 -ErrorAction Stop
 $taskRoots=@(Get-TaskNativeRoots)
 $taskProbe=[ordered]@{free_kib=$taskOs.FreePhysicalMemory;minimum_kib=16777216;native_roots=$taskRoots.Count;
  native_candidates=$taskRoots;utc=[DateTimeOffset]::UtcNow.ToString('o')}
 $taskAdmissionHistory.Add($taskProbe)
 if($null -eq $taskOs.FreePhysicalMemory -or $taskOs.FreePhysicalMemory -lt 16777216 -or $taskRoots.Count){
  throw 'Fresh16GiB/zero-other-native serial admission denied'
 }
 return $taskProbe
}
function Get-TaskSeal {param([string]$Name)
 $taskHead=([string](& $taskGit -c core.fsmonitor=false -c core.hooksPath=NUL -C $taskRoot rev-parse HEAD)).Trim()
 if($LASTEXITCODE -ne 0 -or $taskHead -cne $taskGrant.candidate_head){throw 'Exact candidate head differs'}
 $taskStatus=@(& $taskGit -c core.fsmonitor=false -c core.hooksPath=NUL -C $taskRoot status --porcelain)
 if($LASTEXITCODE -ne 0 -or $taskStatus.Count){throw 'Clean exact candidate required'}
 $taskPaths=@(& $taskGit -c core.fsmonitor=false -c core.hooksPath=NUL -C $taskRoot ls-files)
 if($LASTEXITCODE -ne 0 -or $taskPaths.Count -ne $taskGrant.tracked_source_count){throw 'Full frozen tracked inventory required'}
 $taskCompilerInventory=Get-CiInventory $taskCompiler
 if($taskCompilerInventory.rows.Count -ne 19546 -or
  (Get-FileHash -LiteralPath $taskCompilerAuthority).Hash -cne 'DEE259F171F720AB2C08E8DD473975E22C876417CD62E4F016C71A7C662794EB'){
  throw 'Original full compiler19546 authority required'
 }
 $taskOriginal=Get-Content -LiteralPath $taskCompilerAuthority -Raw|ConvertFrom-Json
 $taskExpectedCompiler=@($taskOriginal.inputs|ForEach-Object{
  if(!$_.path.StartsWith($taskOriginal.root+'\',[StringComparison]::Ordinal)){throw 'Original compiler path escaped root'}
  $_.path.Substring($taskOriginal.root.Length+1).Replace('\','/')+' '+$_.sha256})
 $taskActualCompiler=@($taskCompilerInventory.rows|ForEach-Object{$_.relative.Replace('\','/')+' '+$_.sha256})
 if($taskExpectedCompiler.Count -ne 19546 -or @($taskExpectedCompiler|Sort-Object -Unique).Count -ne 19546 -or
  @($taskActualCompiler|Sort-Object -Unique).Count -ne 19546 -or
  @(Compare-Object $taskExpectedCompiler $taskActualCompiler -CaseSensitive).Count){throw 'Full original compiler path/hash drift'}
 $taskCore=(Get-Content -LiteralPath $taskCoreMap -Raw|ConvertFrom-Json).files
 $taskFixture=(Get-Content -LiteralPath $taskFixtureMap -Raw|ConvertFrom-Json).files
 if($taskCore.Count -ne 36 -or $taskFixture.Count -ne 45){throw 'Current source36/45 required; old35/43 not admitted'}
 foreach($taskRow in $taskFixture){
  $taskFile=Join-Path $taskRoot $taskRow.relative
  if((Get-Item -LiteralPath $taskFile).Length -ne $taskRow.bytes -or (Get-FileHash -LiteralPath $taskFile).Hash -cne $taskRow.sha256){
   throw 'Exact current fixture45 bytes differ'
  }
 }
 $taskControls=@($PSCommandPath,$taskCi,$taskProtocol,$taskClassifier,$taskNames,$taskCoreMap,$taskFixtureMap,$taskFixtureManifest,
  $taskCompilerAuthority,(Join-Path $PSScriptRoot 'README.md'),(Join-Path $PSScriptRoot 'root-grant.template.json'),
  (Join-Path $taskProof 'root-grant.json'),(Join-Path $taskContainer '.pi-zig-workspace.json'),(Join-Path $taskContainer 'path-relocations.json'),
  $taskGit,'C:\Program Files\PowerShell\7\pwsh.exe')
 if($Mode -ceq 'RuntimeOnly'){$taskControls+=@($taskGrant.build_result_path,$taskGrant.build_artifacts_path,$taskGrant.build_metadata_path,$taskGrant.fixture_grant_path)}
 $taskSeal=[ordered]@{candidate_head=$taskHead;source=@(Get-CiRows $taskRoot $taskPaths);compiler=@($taskCompilerInventory.rows);
  controls=@($taskControls|ForEach-Object{@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}});
  source36=@($taskCore);source45=@($taskFixture);driver_sha256=$taskDriverHash;utc=[DateTimeOffset]::UtcNow.ToString('o')}
 Save-TaskJson $taskSeal "$Name.json";return $taskSeal
}
function Assert-TaskSeal {param($Actual,$Expected)
 if($Actual.candidate_head -cne $Expected.candidate_head -or $Actual.driver_sha256 -cne $Expected.driver_sha256){throw 'Head/driver drift'}
 foreach($taskGroup in @('source','compiler','controls')){
  $taskOld=@($Expected[$taskGroup]|ForEach-Object{$(if($taskGroup -ceq 'controls'){$_.path}else{$_.relative})+' '+$_.sha256})
  $taskNew=@($Actual[$taskGroup]|ForEach-Object{$(if($taskGroup -ceq 'controls'){$_.path}else{$_.relative})+' '+$_.sha256})
  if(@(Compare-Object $taskOld $taskNew -CaseSensitive).Count){throw "$taskGroup full inventory/hash drift"}
 }
}
function Assert-TaskNames {param([string[]]$Names)
 if(@($Names|Sort-Object -Unique).Count -ne $Names.Count){throw 'Duplicate actual full test name'}
 $taskMissing=@($taskRequired|Where-Object{$_ -cnotin $Names})
 $taskUnknown=@($Names|Where-Object{$_ -cnotin $taskRequired})
 Save-TaskJson @{actual=$Names;declared=$taskRequired;missing=$taskMissing;unknown=$taskUnknown;filters_used=$false} 'metadata-name-comparison.json'
 if($taskMissing.Count -or $taskUnknown.Count){throw 'Missing declaration or unknown full metadata name; do not filter or infer storage extras'}
}
function Read-TaskMetadata {param([string]$Binary)
 $taskReceipt=Join-Path $taskProof 'metadata'
 $taskOwned=Invoke-CiOwnedProcess $Binary @('--listen=-') $taskRoot $taskReceipt 30 ([byte[]](4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
 $taskBytes=[IO.File]::ReadAllBytes("$taskReceipt.stdout.bin");$taskOffset=0;$taskVersion=$null;$taskActualNames=$null
 while($taskOffset -lt $taskBytes.Length){
  if($taskBytes.Length-$taskOffset -lt 8){throw 'Truncated metadata header'}
  $taskTag=[BitConverter]::ToUInt32($taskBytes,$taskOffset);$taskLength=[BitConverter]::ToUInt32($taskBytes,$taskOffset+4);$taskOffset+=8
  if($taskLength -gt 1MB -or $taskLength -gt $taskBytes.Length-$taskOffset){throw 'Invalid metadata length'}
  if($taskTag -eq 0){
   if($null -ne $taskVersion -or $null -ne $taskActualNames){throw 'Duplicate or late metadata version'}
   $taskVersion=[Text.Encoding]::UTF8.GetString($taskBytes,$taskOffset,$taskLength)
  }elseif($taskTag -eq 3){
   if($taskVersion -cne '0.16.0' -or $null -ne $taskActualNames -or $taskLength -lt 8){throw 'Unexpected metadata array'}
   $taskStrings=[BitConverter]::ToUInt32($taskBytes,$taskOffset);$taskCount=[BitConverter]::ToUInt32($taskBytes,$taskOffset+4)
   # Parse and preserve every actual name before applying any authority. No
   # expected count is manufactured from the29 source declarations.
   if($taskCount -eq 0 -or $taskCount -gt 64 -or $taskLength -ne 8+8*$taskCount+$taskStrings){throw 'Invalid actual metadata shape'}
   $taskStart=$taskOffset+8+8*$taskCount;$taskActualNames=@()
   for($taskIndex=0;$taskIndex -lt $taskCount;$taskIndex++){
    $taskNameOffset=[BitConverter]::ToUInt32($taskBytes,$taskOffset+8+4*$taskIndex)
    $taskPanic=[BitConverter]::ToUInt32($taskBytes,$taskOffset+8+4*$taskCount+4*$taskIndex)
    if($taskPanic -ne 0 -or $taskNameOffset -ge $taskStrings){throw 'Invalid actual panic/name offset'}
    $taskEnd=$taskNameOffset
    while($taskEnd -lt $taskStrings -and $taskBytes[$taskStart+$taskEnd] -ne 0){$taskEnd++}
    if($taskEnd -eq $taskStrings){throw 'Unterminated actual full test name'}
    $taskActualNames+=[Text.Encoding]::UTF8.GetString($taskBytes,$taskStart+$taskNameOffset,$taskEnd-$taskNameOffset)
   }
  }else{throw "Unexpected metadata-only tag $taskTag"}
  $taskOffset+=$taskLength
 }
 if($taskVersion -cne '0.16.0' -or $null -eq $taskActualNames){throw 'Missing metadata/version'}
 $taskMetadata=[ordered]@{binary=$Binary;binary_sha256=$taskOwned.executable_sha256;version=$taskVersion;
  actual_count=$taskActualNames.Count;tests=$taskActualNames;planned_declarations=29;actual_count_known_before_query=$false;
  method='Actual query4/exit0; canonicalCI607; all actual names retained before exact declared-name whitelist; no run_test'}
 Save-TaskJson $taskMetadata 'actual-metadata.json'
 if((Get-Item -LiteralPath "$taskReceipt.stderr.log").Length){throw 'Empty metadata stderr required'}
 Assert-TaskNames $taskActualNames;return $taskMetadata
}
$taskResult=[ordered]@{status='running';mode=$Mode;source_head=$taskGrant.candidate_head;planned_declarations=29;
 actual_metadata_count=$null;compile=$null;metadata=$null;runtime=$null;postseal=$false;artifact_seal=$false;
 native_roots_after=$null;runtime_status='recovery_pending';authority_complete=$false}
$taskOldFixtureGrant=$env:PI_ZIG_FIXTURE_GRANT;$taskOldFixtureSha=$env:PI_ZIG_FIXTURE_GRANT_SHA256
try{
 if((Get-FileHash -LiteralPath $taskZig).Hash -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Pinned Zig0.16 required'}
 Save-TaskJson (Assert-TaskAdmission) 'initial-admission.json';$taskBefore=Get-TaskSeal 'before'
 if($Mode -ceq 'BuildQuery'){
  Save-TaskJson (Assert-TaskAdmission) 'compile-admission.json'
  $taskPrefix=Join-Path $taskProof 'out'
  $taskArgs=@('build','--build-file','verification/runtime_job_owner/controls_build.zig','-Doptimize=Debug','-j1',
   '--prefix',$taskPrefix,'--cache-dir',(Join-Path $taskProof 'cache'),'--global-cache-dir',(Join-Path $taskProof 'global-cache'),'--summary','all')
  $taskResult.compile=Invoke-CiOwnedProcess $taskZig $taskArgs $taskRoot (Join-Path $taskProof 'compile') 1320
  if(@(Get-TaskNativeRoots).Count){throw 'Native root remains after build-only phase'}
  $taskArtifactPins=Get-CiInventory $taskPrefix;Save-TaskJson $taskArtifactPins 'artifacts-before.json'
  $taskExpectedArtifacts=@('bin/runtime-job-owner-actor.exe','bin/runtime-job-owner-actor.pdb','bin/test.exe','bin/test.pdb')
  if(@(Compare-Object $taskExpectedArtifacts @($taskArtifactPins.rows.relative) -CaseSensitive).Count){throw 'Exact new actor/test EXE/PDB roles required'}
  Save-TaskJson (Assert-TaskAdmission) 'metadata-admission.json'
  $taskResult.metadata=Read-TaskMetadata (Join-Path $taskPrefix 'bin/test.exe');$taskResult.actual_metadata_count=$taskResult.metadata.actual_count
  if(@(Get-TaskNativeRoots).Count){throw 'Native root remains after metadata-only phase'}
  Assert-TaskSeal (Get-TaskSeal 'between') $taskBefore
  Assert-CiInventory $taskArtifactPins (Join-Path $taskProof 'artifacts-between.json')
  $taskResult.status='built_metadata_verified_pending_independent_review'
 }else{
  foreach($taskPin in @(@{path=$taskGrant.build_result_path;hash=$taskGrant.build_result_sha256},@{path=$taskGrant.build_artifacts_path;hash=$taskGrant.build_artifacts_sha256},
   @{path=$taskGrant.build_metadata_path;hash=$taskGrant.build_metadata_sha256},@{path=$taskGrant.fixture_grant_path;hash=$taskGrant.fixture_grant_sha256})){
   if(!$taskPin.path.StartsWith((Join-Path $taskContainer 'evidence/'),[StringComparison]::OrdinalIgnoreCase) -or
    (Get-FileHash -LiteralPath $taskPin.path).Hash -cne $taskPin.hash){throw 'Exact Root-reviewed matching build/fixture grant required'}
  }
  $taskBuildMatch=Get-Content -LiteralPath $taskGrant.build_result_path -Raw|ConvertFrom-Json
  $taskArtifactPins=Get-Content -LiteralPath $taskGrant.build_artifacts_path -Raw|ConvertFrom-Json
  $taskMetadata=Get-Content -LiteralPath $taskGrant.build_metadata_path -Raw|ConvertFrom-Json
  if($taskBuildMatch.status -cne 'built_metadata_verified_pending_independent_review' -or $taskBuildMatch.source_head -cne $taskGrant.candidate_head -or
   $taskMetadata.version -cne '0.16.0' -or !$taskBuildMatch.postseal -or !$taskBuildMatch.artifact_seal -or $taskBuildMatch.native_roots_after -ne 0){
   throw 'Accepted matching build/query terminal/fullpost/absence required'
  }
  $taskMatchedMetadata=$taskBuildMatch.metadata
  if($null -eq $taskMatchedMetadata -or $taskBuildMatch.mode -cne 'BuildQuery' -or
   $taskMetadata.binary -cne $taskMatchedMetadata.binary -or $taskMetadata.binary_sha256 -cne $taskMatchedMetadata.binary_sha256 -or
   $taskMetadata.version -cne $taskMatchedMetadata.version -or $taskMetadata.actual_count -ne $taskMatchedMetadata.actual_count -or
   ([string]::Join([char]0,[string[]]$taskMetadata.tests)) -cne ([string]::Join([char]0,[string[]]$taskMatchedMetadata.tests))){
   throw 'Supplied actual metadata is not the exact matched build-result metadata'
  }
  $taskMatchedBinary=[IO.Path]::GetFullPath([string]$taskMatchedMetadata.binary)
  $taskMatchedArtifactRoot=[IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName($taskMatchedBinary))
  if($taskMatchedMetadata.binary -cne $taskMatchedBinary -or
   $taskMatchedBinary -cne (Join-Path $taskMatchedArtifactRoot 'bin/test.exe') -or $taskArtifactPins.root -cne $taskMatchedArtifactRoot){
   throw 'Artifact root is not the one derived from the matched build metadata'
  }
  $taskRuntimeArtifactRoles=@('bin/runtime-job-owner-actor.exe','bin/runtime-job-owner-actor.pdb','bin/test.exe','bin/test.pdb')
  if(@($taskArtifactPins.rows).Count -ne 4 -or
   @(Compare-Object $taskRuntimeArtifactRoles @($taskArtifactPins.rows.relative) -CaseSensitive).Count){
   throw 'Matching runtime requires every exact actor/test EXE/PDB artifact role'
  }
  Assert-TaskNames @($taskMetadata.tests)
  Assert-CiInventory $taskArtifactPins (Join-Path $taskProof 'artifacts-before.json')
  $taskBinary=Join-Path $taskArtifactPins.root 'bin/test.exe';$taskActor=Join-Path $taskArtifactPins.root 'bin/runtime-job-owner-actor.exe'
  if($taskMetadata.binary -cne $taskBinary -or $taskMetadata.binary_sha256 -cne (Get-FileHash -LiteralPath $taskBinary).Hash -or
   $taskMetadata.actual_count -ne @($taskMetadata.tests).Count){throw 'Actual metadata/binary/count match differs'}
  $taskFixtureGrant=Get-Content -LiteralPath $taskGrant.fixture_grant_path -Raw|ConvertFrom-Json
  if($taskFixtureGrant.authorized -ne $true -or $taskFixtureGrant.scope -cne 'runtime_job_owner_native_fixture29' -or
   $taskFixtureGrant.source_commit -cne $taskGrant.candidate_head -or $taskFixtureGrant.tests_executable -cne $taskBinary -or
   $taskFixtureGrant.tests_sha256 -cne (Get-FileHash -LiteralPath $taskBinary).Hash -or $taskFixtureGrant.actor_executable -cne $taskActor -or
   $taskFixtureGrant.actor_sha256 -cne (Get-FileHash -LiteralPath $taskActor).Hash -or $taskFixtureGrant.controls_manifest -cne $taskFixtureManifest){
   throw 'Exact actor/test role/source grant differs'
  }
  $env:PI_ZIG_FIXTURE_GRANT=$taskGrant.fixture_grant_path;$env:PI_ZIG_FIXTURE_GRANT_SHA256=$taskGrant.fixture_grant_sha256
  Save-TaskJson (Assert-TaskAdmission) 'runtime-admission.json'
  $taskResult.actual_metadata_count=$taskMetadata.actual_count
  $taskResult.runtime=Invoke-NativeTestProtocol $taskBinary $taskRoot (Join-Path $taskProof 'runtime') $taskMetadata.actual_count
  if((Get-Item -LiteralPath (Join-Path $taskProof 'runtime.stderr.log')).Length){throw 'Empty runtime stderr required'}
  $taskResult.status='native_controls_passed_pending_independent_review'
 }
}catch{$taskResult.status='failed';$taskResult.error=$_.Exception.Message}
finally{
 $env:PI_ZIG_FIXTURE_GRANT=$taskOldFixtureGrant;$env:PI_ZIG_FIXTURE_GRANT_SHA256=$taskOldFixtureSha
 try{$taskFinal=Get-TaskSeal 'final';if($null -eq $taskBefore){throw 'Before baseline unavailable; final retained only'};Assert-TaskSeal $taskFinal $taskBefore;$taskResult.postseal=$true}
 catch{$taskResult.status='failed_postseal';$taskResult.postseal_error=$_.Exception.Message}
 try{if($null -ne $taskArtifactPins){Assert-CiInventory $taskArtifactPins (Join-Path $taskProof 'artifacts-final.json');$taskResult.artifact_seal=$true}
  elseif(Test-Path -LiteralPath (Join-Path $taskProof 'out')){Save-TaskJson (Get-CiInventory (Join-Path $taskProof 'out')) 'artifacts-negative.json'}}
 catch{$taskResult.status='failed_artifacts';$taskResult.artifact_error=$_.Exception.Message}
 try{$taskRoots=@(Get-TaskNativeRoots);Save-TaskJson $taskRoots 'native-roots-final.json';$taskResult.native_roots_after=$taskRoots.Count;
  if($taskRoots.Count){throw 'Native roots/actors remain'}}catch{$taskResult.status='failed_native_roots';$taskResult.native_roots_error=$_.Exception.Message}
 try{$taskAbsence=@(foreach($taskPhase in @('compile','metadata','runtime')){
  $taskReceipt=Join-Path $taskProof "$taskPhase.json";if(!(Test-Path -LiteralPath $taskReceipt)){continue}
  $taskOwned=Get-Content -LiteralPath $taskReceipt -Raw|ConvertFrom-Json
  $taskLive=@(Get-CimInstance Win32_Process -Filter "ProcessId = $($taskOwned.pid)" -OperationTimeoutSec 3 -ErrorAction Stop)
  @{phase=$taskPhase;pid=$taskOwned.pid;recorded_created_utc=$taskOwned.created_utc;current=$taskLive;absent=($taskLive.Count -eq 0)}
 });Save-TaskJson $taskAbsence 'owner-absence.json';if(@($taskAbsence|Where-Object{!$_.absent}).Count){throw 'Recorded PID present/reused; Root reconciliation required'}}
 catch{$taskResult.status='failed_absence';$taskResult.absence_error=$_.Exception.Message}
 $taskResult.admission_probes=$taskAdmissionHistory.ToArray();$taskResult.completed_utc=[DateTimeOffset]::UtcNow.ToString('o');Save-TaskJson $taskResult 'result.json'
}
$taskResult|ConvertTo-Json -Depth 16
if($taskResult.status -cnotin @('built_metadata_verified_pending_independent_review','native_controls_passed_pending_independent_review')){
 throw 'Native29 phase failed; retain every negative'
}
