param([Parameter(Mandatory)][string]$RootGrant,[Parameter(Mandatory)][ValidateSet('BuildQuery','RuntimeOnly')][string]$Mode)
$ErrorActionPreference='Stop'
$taskBuildMode=($Mode-ceq'BuildQuery')
$taskContainer=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$taskResolver=Join-Path $taskContainer 'main/tools/workspace/Resolve-PiZigWorkspace.ps1'
function Contained([string]$Path,[string]$Under){
 if(!$Path){throw 'Explicit contained path required'}
 $resolved=[IO.Path]::GetFullPath($Path)
 if(!$resolved.StartsWith([IO.Path]::GetFullPath($Under)+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Path escapes declared contained root'}
 $ancestor=[IO.DirectoryInfo]::new($resolved)
 while($ancestor){if($ancestor.Exists-and($ancestor.Attributes-band[IO.FileAttributes]::ReparsePoint)){throw 'Reparse ancestor rejected'};if($ancestor.FullName-eq$taskContainer){break};$ancestor=$ancestor.Parent}
 if((Test-Path -LiteralPath $resolved)-and((Get-Item -LiteralPath $resolved -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)){throw 'Reparse leaf rejected'}
 return $resolved
}
$taskLiteralEvidence=Join-Path $taskContainer 'evidence'
$RootGrant=Contained $RootGrant $taskLiteralEvidence
if(!(Test-Path -LiteralPath $RootGrant -PathType Leaf)){throw 'Literal contained regular Root grant required'}
$taskGrant=Get-Content -LiteralPath $RootGrant -Raw|ConvertFrom-Json
# Bootstrap from literal contained data, pinning every control used by the
# resolver before invoking it. No grant-supplied script is executed here.
foreach($pin in @(
 @{path=(Contained $PSCommandPath $taskLiteralEvidence);hash=$taskGrant.driver_sha256},
 @{path=(Contained $taskResolver $taskContainer);hash=$taskGrant.workspace_resolver_sha256},
 @{path=(Contained (Join-Path $taskContainer '.pi-zig-workspace.json') $taskContainer);hash=$taskGrant.workspace_layout_sha256},
 @{path=(Contained (Join-Path $taskContainer 'path-relocations.json') $taskContainer);hash=$taskGrant.path_relocations_sha256}
)){if(!$pin.hash-or!(Test-Path -LiteralPath $pin.path -PathType Leaf)-or(Get-FileHash -LiteralPath $pin.path).Hash-cne$pin.hash){throw 'Bootstrap control identity differs before resolver execution'}}
$taskWorkspace=& $taskResolver -StartPath $PSScriptRoot
if($taskWorkspace.Container-cne$taskContainer-or$taskWorkspace.evidence-cne$taskLiteralEvidence-or$taskWorkspace.worktrees-cne(Join-Path $taskContainer 'worktrees')){throw 'Pinned workspace resolver returned unexpected literal container roots'}
$taskRoot=Contained ([string]$taskGrant.candidate_root) $taskContainer
if($taskRoot-cne$taskWorkspace.main-and!$taskRoot.StartsWith($taskWorkspace.worktrees+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Candidate must be Main or a contained assigned worktree'}
$taskProof=Contained ([string]$taskGrant.receipt_directory) $taskWorkspace.evidence
$taskHead=[string]$taskGrant.candidate_head
if($taskHead-cnotmatch'^[0-9a-f]{40}$'){throw 'Root must pin one complete candidate commit'}
if($taskGrant.status-cne'root_reviewed_combined_native_batch_release'-or$taskGrant.mode-cne$Mode-or$taskGrant.candidate_head-cne$taskHead-or!$taskGrant.grant_id-or$taskGrant.runtime_restoration_claim-ne$false-or$taskGrant.execution_authorized-ne$true-or$taskGrant.dedicated_external53_controller-ne$true){throw 'Exact separate-mode combined native Root release required'}
if($taskGrant.qualification_requested-isnot[bool]-or$taskGrant.qualification_requested-ne$true-or$taskGrant.cache_mode-cne'fresh_batch'-or$taskGrant.reuse_unsealed_original_compile_caches-isnot[bool]-or$taskGrant.reuse_unsealed_original_compile_caches-ne$false){throw 'Fresh batch qualification with no previous cache reuse required'}
if($taskGrant.cache_seed_manifest_path-or$taskGrant.cache_seed_manifest_sha256-or@($taskGrant.allow_seed_source_delta_paths).Count){throw 'Batch qualification cannot receive any seed cache'}
if($taskGrant.initial_grant_max_age_seconds-ne300-or$taskGrant.minimum_free_kib-ne16777216-or$taskGrant.compile_outer_seconds-ne1320-or$taskGrant.metadata_outer_seconds-ne30-or$taskGrant.runtime_outer_actual_seconds-ne120-or$taskGrant.owner_settle_seconds-ne10){throw 'Reviewed fresh grant and exact budgets required'}
foreach($field in @('initial_grant_max_age_seconds','minimum_free_kib','compile_outer_seconds','metadata_outer_seconds','runtime_outer_actual_seconds','owner_settle_seconds','outer_controller_seconds')){
 if($taskGrant.$field-isnot[int]-and$taskGrant.$field-isnot[long]-and$taskGrant.$field-isnot[ulong]){throw 'Grant budget fields require actual scalar integers'}
}
if($taskGrant.outer_controller_seconds-ne1800){throw 'Exact external53 controller budget required'}
if($taskGrant.issued_utc-isnot[datetime]-and$taskGrant.issued_utc-isnot[datetimeoffset]-and$taskGrant.issued_utc-isnot[string]){throw 'Explicit actual timestamp required'}
if($taskGrant.issued_utc-is[string]-and[string]::IsNullOrWhiteSpace($taskGrant.issued_utc)){throw 'Explicit actual timestamp required'}
function Assert-InitialGrantFresh {$issued=[DateTimeOffset]$taskGrant.issued_utc;$age=([DateTimeOffset]::UtcNow-$issued).TotalSeconds;if($age-lt0-or$age-gt300){throw 'Initial grant must be within300seconds before first child launch'}}
Assert-InitialGrantFresh
if(Test-Path -LiteralPath $taskProof){throw 'Fresh unique proof/output directory required'}
# A -File process is required before any controller-private environment write.
$taskHostExe='C:\Program Files\PowerShell\7\pwsh.exe'
$taskHost=([Environment]::ProcessPath)
if(!$taskHost-or![StringComparer]::OrdinalIgnoreCase.Equals($taskHost,$taskHostExe)-or(Get-FileHash -LiteralPath $taskHost).Hash-cne'FA2C8BB1E35CDD62AD15CD06A1D8F2C5961E9725A9BFA1E7CFD2C322F49E9619'){throw 'Pinned actual PowerShell controller executable required'}
$taskManagedEntry=Join-Path ([IO.Path]::GetDirectoryName($taskHostExe)) 'pwsh.dll'
if((Get-FileHash -LiteralPath $taskManagedEntry).Hash-cne'A583A3721FEEBC4F9552A02358BC81BBDD41E2E18BB3F424226F2B1E0BF07DEB'){throw 'Pinned managed PowerShell entry differs'}
$taskActualControllerArgs=@([Environment]::GetCommandLineArgs())
$taskExpectedControllerArgs=@($taskManagedEntry,'-NoLogo','-NoProfile','-NonInteractive','-File',$PSCommandPath,'-RootGrant',$RootGrant)
if($PSBoundParameters.ContainsKey('Mode')){$taskExpectedControllerArgs+=@('-Mode',[string]$Mode)}
if($taskActualControllerArgs.Count-ne$taskExpectedControllerArgs.Count){throw 'Exact externally owned -File controller argv required'}
for($taskArgumentIndex=0;$taskArgumentIndex-lt$taskExpectedControllerArgs.Count;$taskArgumentIndex++){if(![StringComparer]::OrdinalIgnoreCase.Equals([string]$taskActualControllerArgs[$taskArgumentIndex],[string]$taskExpectedControllerArgs[$taskArgumentIndex])){throw 'Current PowerShell -File/script/grant argv differs'}}
foreach($taskBoolean in @('execution_authorized','dedicated_external53_controller','runtime_restoration_claim')){if($taskGrant.$taskBoolean-isnot[bool]){throw 'Grant authority flags must be actual JSON booleans'}}
$taskCompiler=[IO.Path]::GetDirectoryName($taskWorkspace.zig);$taskZig=$taskWorkspace.zig
$taskCi=Join-Path $taskWorkspace.main 'tools/ci/native_qualification_ci.ps1'
$taskProtocol=Join-Path $taskWorkspace.main 'tools/ci/Invoke-NativeTestProtocol.ps1'
$taskLayout=Join-Path $taskContainer '.pi-zig-workspace.json'
$taskCompilerManifest=Join-Path $taskWorkspace.evidence 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json'
$taskOuterOwner=Join-Path $taskWorkspace.evidence 'root-crypto58-native-outer-prepared-20261017/outer-owned-process.ps1'
$taskPowerShell='C:\Program Files\PowerShell\7\pwsh.exe'
foreach($pin in @(
 @{path=$taskCi;hash='607BEDBB91FE318D214CD2C3B9C83D80437335C0062C320C0EACB3A745B38285'},@{path=$taskProtocol;hash='39F273D35A5B28E9D60FBE93355828314458A67FB472D60E0A8A6D4DD1FB704D'},
 @{path=$taskZig;hash='086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'},@{path=$taskCompilerManifest;hash='DEE259F171F720AB2C08E8DD473975E22C876417CD62E4F016C71A7C662794EB'},
 @{path=$taskOuterOwner;hash='53E522C8397B5F7EE9AF721D8160B227E97FADA4E1DA36A938656E2403D56B6B'},@{path=$taskPowerShell;hash='FA2C8BB1E35CDD62AD15CD06A1D8F2C5961E9725A9BFA1E7CFD2C322F49E9619'}
)){if((Get-FileHash -LiteralPath $pin.path).Hash-cne$pin.hash){throw 'Pinned native control/tool authority differs'}}
$taskClassifier=Join-Path $PSScriptRoot 'Get-ModelsNativeCandidates.ps1'
if((Get-FileHash -LiteralPath $taskClassifier).Hash-cne'3413A2A50B4D4C3BFF8709E4EE08C76BE449AAB1EDCB1E0C5C167DC7A804E301'){throw 'Reviewed3413 native candidate classifier differs'}
. $taskClassifier
. $taskCi
. $taskProtocol
$taskMatrixPath=Join-Path $PSScriptRoot 'groups.json'
if($taskGrant.group_manifest_sha256-isnot[string]-or$taskGrant.group_manifest_sha256-cnotmatch'^[0-9A-F]{64}$'-or(Get-FileHash -LiteralPath $taskMatrixPath).Hash-cne$taskGrant.group_manifest_sha256){throw 'Root-pinned group manifest required'}
$taskMatrix=Get-Content -LiteralPath $taskMatrixPath -Raw|ConvertFrom-Json

$batchProof=$taskProof
if($taskMatrix.schema-ne1-or$taskGrant.groups-isnot[array]-or$taskGrant.groups.Count-lt1-or$taskGrant.groups.Count-gt64-or@($taskGrant.groups|Select-Object -Unique).Count-ne$taskGrant.groups.Count){throw 'One to64 distinct explicitly ordered groups required'}
$taskSelections=@(foreach($name in $taskGrant.groups){
 if($name-isnot[string]-or$name-cnotmatch'^[a-z0-9-]+$'){throw 'Literal bounded group name required'}
 $found=@($taskMatrix.groups|Where-Object name -CEQ $name)
 if($found.Count-ne1){throw 'Each grant group must select exactly one manifest entry'}
 $selected=$found[0]
 if($selected.target-cnotmatch'^build-native-[a-z0-9-]+$'-or$selected.artifact-cnotmatch'^[a-z0-9-]+$'-or$selected.source_root-cnotmatch'^src/[a-z0-9_]+\.zig$'-or@($selected.required_named).Count-lt1-or@($selected.required_named).Count-gt64-or$selected.runtime_stderr_policy-cne'empty'){throw 'Bounded actual native group and strict stderr policy required'}
 $selected|Add-Member -NotePropertyName names -NotePropertyValue @() -ErrorAction Stop
 $selected
})
$taskFixedMap=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
foreach($selected in $taskSelections){
 foreach($pin in $selected.source_pins){
  if($pin.path-cnotmatch'^src/[A-Za-z0-9_./-]+\.(zig|c|mjs|json)$'-or$pin.path-match'(^|/)\.\.(/|$)'-or$pin.sha256-cnotmatch'^[0-9A-F]{64}$'){throw 'Exact group source pins required'}
  if($taskFixedMap.ContainsKey($pin.path)-and$taskFixedMap[$pin.path]-cne$pin.sha256){throw 'Conflicting shared test source pin'}
  $taskFixedMap[$pin.path]=$pin.sha256
 }
 if(@($selected.source_pins|Where-Object path -CEQ $selected.source_root).Count-ne1){throw 'Each declared source root must be pinned exactly once'}
}
$taskFixed=@(foreach($path in $taskFixedMap.Keys){@{path=$path;sha256=$taskFixedMap[$path]}})
$taskOriginalCompiler=Get-Content -LiteralPath $taskCompilerManifest -Raw|ConvertFrom-Json
$taskMap=Get-Content -LiteralPath $taskWorkspace.path_relocations -Raw|ConvertFrom-Json
$taskMappedCompiler=$null
foreach($mapping in @($taskMap.mappings|Sort-Object {$_.old.Length} -Descending)){$old=[IO.Path]::GetFullPath([string]$mapping.old);$historical=[IO.Path]::GetFullPath([string]$taskOriginalCompiler.root);if($historical-eq$old-or$historical.StartsWith($old+'\',[StringComparison]::OrdinalIgnoreCase)){$taskMappedCompiler=[IO.Path]::GetFullPath([string]$mapping.new+$historical.Substring($old.Length));break}}
if($taskMap.schema-ne1-or$taskMappedCompiler-cne$taskCompiler-or@($taskOriginalCompiler.inputs).Count-ne19546){throw 'Original relocated compiler19546 authority required'}
$taskExpectedCompiler=@(foreach($row in $taskOriginalCompiler.inputs){$relative=[IO.Path]::GetRelativePath([string]$taskOriginalCompiler.root,[string]$row.path).Replace([char]92,[char]47);if([IO.Path]::IsPathRooted($relative)-or$relative-eq'..'-or$relative.StartsWith('../')){throw 'Historical compiler row escapes root'};[ordered]@{relative=$relative;sha256=[string]$row.sha256}})
$taskControlPaths=@($taskHostExe,$taskManagedEntry,$PSCommandPath,$RootGrant,$taskResolver,$taskLayout,$taskWorkspace.path_relocations,$taskCompilerManifest,$taskMatrixPath,$taskClassifier,$taskCi,$taskProtocol,$taskOuterOwner,$taskPowerShell)
function Assert-SelectedNames($Names){
 $names=@($Names)
 if($names.Count-lt1-or$names.Count-gt64-or@($names|Select-Object -Unique).Count-ne$names.Count){throw 'Unique actual metadata names within canonical batch64 required'}
 if($null-ne$selection.historical_order){
  if([string]::Join([char]10,$names)-cne[string]::Join([char]10,@($selection.historical_order))){throw 'Actual retained ordered metadata differs from original authority'}
 }else{
  foreach($name in @($selection.required_named)){if(@($names|Where-Object{$_-ceq$name}).Count-ne1){throw 'Every genuine declared new control must occur exactly once'}}
  foreach($name in $names){if($name-cnotin@($selection.required_named)-and$name-cnotin@($selection.allowed_anonymous)){throw 'Unexpected imported metadata name'}}
 }
}

function Read-ComposedMetadata {
 param([string]$Binary,[string]$Root,[string]$Receipt)
 $request=[byte[]](4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
 $owned=Invoke-CiOwnedProcess $Binary @('--listen=-') $Root $Receipt 30 $request
 $bytes=[IO.File]::ReadAllBytes("$Receipt.stdout.bin");$offset=0;$version=$null;$names=$null
 $utf8=[Text.UTF8Encoding]::new($false,$true)
 while($offset-lt$bytes.Length){
  if($bytes.Length-$offset-lt8){throw 'Truncated actual metadata header'}
  $tag=[BitConverter]::ToUInt32($bytes,$offset);$length=[BitConverter]::ToUInt32($bytes,$offset+4);$offset+=8
  if($length-gt1MB-or$length-gt$bytes.Length-$offset){throw 'Actual metadata length mismatch'}
  if($tag-eq0){if($null-ne$version){throw 'Duplicate protocol version'};$version=$utf8.GetString($bytes,$offset,$length)}
  elseif($tag-eq3){
   if($version-cne'0.16.0'-or$null-ne$names-or$length-lt8){throw 'Version must precede one complete actual metadata array'}
   $strings=[BitConverter]::ToUInt32($bytes,$offset);$count=[BitConverter]::ToUInt32($bytes,$offset+4)
   if($count-lt1-or$count-gt64-or$length-ne8+8*$count+$strings){throw 'Actual metadata count/length outside bounded batch contract'}
   $start=$offset+8+8*$count;$names=@()
   for($index=0;$index-lt$count;$index++){
    $nameOffset=[BitConverter]::ToUInt32($bytes,$offset+8+4*$index);$panic=[BitConverter]::ToUInt32($bytes,$offset+8+4*$count+4*$index)
    if($panic-ne0-or$nameOffset-ge$strings){throw 'Unexpected panic/name offset'}
    $end=$nameOffset;while($end-lt$strings-and$bytes[$start+$end]-ne0){$end++}
    if($end-eq$strings){throw 'Unterminated metadata name'}
    $names+= $utf8.GetString($bytes,$start+$nameOffset,$end-$nameOffset)
   }
  }else{throw 'Unexpected metadata-only tag'}
  $offset+=$length
 }
 if($version-cne'0.16.0'-or$null-eq$names){throw 'Actual complete metadata/version required'}
 Assert-SelectedNames $names
 return [ordered]@{binary=$Binary;binary_sha256=$owned.executable_sha256;version=$version;actual_count=$names.Count;tests=$names;group=$Group;candidate_head=$taskHead;method='Actual query4/exit0 only; no run_test; CI607 owner30';runtime_started=$false}
}

function Save-Json($Value,[string]$Name,[int]$Depth=12){$Value|ConvertTo-Json -Depth $Depth|Set-Content -LiteralPath (Join-Path $taskProof $Name) -Encoding utf8NoBOM}

function Get-TaskProcesses {
 $rows=@(Get-CimInstance Win32_Process -OperationTimeoutSec 5 -ErrorAction Stop)
 if(!$rows.Count){throw 'Complete process census unavailable'}
 return $rows
}

function Select-TaskNative($Rows){@(Get-ModelsNativeCandidates -Rows $Rows -Container $taskContainer)}

function Assert-TaskAdmission([string]$Phase){
 $watch=[Diagnostics.Stopwatch]::StartNew();$probes=[Collections.Generic.List[object]]::new()
 try{do{
  $os=Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 5 -ErrorAction Stop
  if($null-eq$os.FreePhysicalMemory){throw 'Memory census unavailable'}
  $roots=@(Select-TaskNative (Get-TaskProcesses))
  $probe=[ordered]@{phase=$Phase;free_kib=[uint64]$os.FreePhysicalMemory;minimum_kib=16777216;native_roots=$roots.Count;native=@($roots|Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine,CreationDate);elapsed_seconds=$watch.Elapsed.TotalSeconds;utc=[DateTimeOffset]::UtcNow.ToString('o')}
  $probes.Add($probe);$taskAdmissions.Add($probe)
  if($roots.Count){throw 'Other/unknown native roots prevent serial admission'}
  if($watch.Elapsed.TotalSeconds-ge54){throw 'Fresh admission54-second deadline expired before acceptance'}
  if($os.FreePhysicalMemory-ge16777216){Save-Json ([ordered]@{status='admitted';phase=$Phase;probe=$probe;accepted_elapsed_seconds=$watch.Elapsed.TotalSeconds;probes=$probes.ToArray()}) "$Phase-admission.json";return}
  $remaining=54000-$watch.ElapsedMilliseconds
  if($remaining-le0){throw 'Fresh admission deadline expired'}
  Start-Sleep -Milliseconds ([int][Math]::Min(1000,$remaining))
 }while($true)}catch{Save-Json ([ordered]@{status='denied';phase=$Phase;error=[string]$_;elapsed_seconds=$watch.Elapsed.TotalSeconds;probes=$probes.ToArray()}) "$Phase-admission.json";throw}
}

function Get-TaskSeal([string]$Name){
 $seal=[ordered]@{candidate_head=$null;clean=$false;source=@();tree=@();vendor=@();compiler=@();controls=@();errors=@()}
 try{$seal.candidate_head=([string](git --no-optional-locks -C $taskRoot rev-parse HEAD)).Trim();if($LASTEXITCODE-ne0){throw 'git head unavailable'};$seal.clean=@(git --no-optional-locks -C $taskRoot status --porcelain).Count-eq0;if($LASTEXITCODE-ne0){throw 'git clean state unavailable'}}catch{$seal.errors+=,[ordered]@{group='identity';error=[string]$_}}
 foreach($group in @('source','tree','vendor','compiler','controls')){try{
  switch($group){
   source{$paths=@(git --no-optional-locks -C $taskRoot ls-files);if($LASTEXITCODE-ne0){throw 'Tracked inventory unavailable'};$seal.source=@(Get-CiRows $taskRoot $paths)}
   tree{$seal.tree=@((Get-CiInventory $taskRoot tree @('.git','.zig-cache','zig-out')).rows)}
   vendor{$seal.vendor=@((Get-CiInventory (Join-Path $taskRoot 'vendor')).rows)}
   compiler{$seal.compiler=@((Get-CiInventory $taskCompiler).rows)}
   controls{$seal.controls=@(foreach($path in $taskControlPaths){[ordered]@{relative=[IO.Path]::GetFullPath($path);path=[IO.Path]::GetFullPath($path);sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}})}
  }
 }catch{$seal.errors+=,[ordered]@{group=$group;error=[string]$_}}}
 Save-Json $seal "$Name.json" 8
 return $seal
}

function Assert-Rows($Actual,$Expected,[string]$Group){
 $left=@($Actual|ForEach-Object{$_.relative+' '+$_.sha256});$right=@($Expected|ForEach-Object{$_.relative+' '+$_.sha256})
 if(@(Compare-Object $left $right -CaseSensitive).Count){throw "$Group inventory/hash drift"}
}

function Assert-TaskSeal($Actual,$Expected){
 if($Actual.errors.Count-or!$Actual.clean-or$Actual.candidate_head-cne$taskHead){throw 'Complete clean exact-head source seal failed'}
 if($Actual.source.Count-lt1-or$Actual.tree.Count-lt$Actual.source.Count-or$Actual.vendor.Count-lt1){throw 'Complete nonempty source, working tree, and vendor inventories required'}
 if($Actual.compiler.Count-ne19546){throw 'Complete compiler19546 required'}
 Assert-Rows $Actual.compiler $taskExpectedCompiler 'original compiler19546'
 foreach($fixed in $taskFixed){$found=@($Actual.source|Where-Object relative -CEQ $fixed.path);if($found.Count-ne1-or$found[0].sha256-cne$fixed.sha256){throw "Fixed C/H/module/fixture identity differs: $($fixed.path)"}}
 if($null-ne$Expected){foreach($group in @('source','tree','vendor','compiler','controls')){Assert-Rows $Actual[$group] $Expected[$group] $group}}
}

function Get-TaskArtifacts([string]$Name){
 $artifact=[ordered]@{installed=@();cached_executables=@();pe=$null;errors=@()}
 foreach($path in @($taskInstalledBinary,$taskPdb)){try{if(Test-Path -LiteralPath $path -PathType Leaf){$artifact.installed+=,[ordered]@{path=$path;bytes=(Get-Item -LiteralPath $path).Length;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}}}catch{$artifact.errors+=,[string]$_}}
 try{if(Test-Path -LiteralPath $taskCache){$artifact.cached_executables=@(Get-ChildItem -LiteralPath $taskCache -File -Filter test.exe -Recurse|ForEach-Object{[ordered]@{path=$_.FullName;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash;pdb_path=(Join-Path $_.DirectoryName 'test.pdb');pdb_sha256=$(if(Test-Path -LiteralPath (Join-Path $_.DirectoryName 'test.pdb')){(Get-FileHash -LiteralPath (Join-Path $_.DirectoryName 'test.pdb')).Hash}else{$null})}})}}catch{$artifact.errors+=,[string]$_}
 if(Test-Path -LiteralPath $taskInstalledBinary -PathType Leaf){try{
  $bytes=[IO.File]::ReadAllBytes($taskInstalledBinary);if($bytes.Length-lt64){throw 'Truncated PE image'};$offset=[BitConverter]::ToInt32($bytes,0x3c)
  if($offset-lt0-or$offset+112-gt$bytes.Length-or[BitConverter]::ToUInt32($bytes,$offset)-ne0x4550-or[BitConverter]::ToUInt16($bytes,$offset+24)-ne0x20b){throw 'Expected PE32+ executable'}
  $artifact.pe=[ordered]@{reserved_stack_bytes=[BitConverter]::ToUInt64($bytes,$offset+24+72);committed_stack_bytes=[BitConverter]::ToUInt64($bytes,$offset+24+80);Engine_guard_bytes=1048576;guard_authority='Frozen Engine default1MiB; no controller or source stack override';dynamic_stack_measured=$false}
 }catch{$artifact.errors+=,[string]$_}}
 Save-Json $artifact "$Name-artifacts.json"
 return $artifact
}

function Assert-TaskArtifacts($Actual,$Expected){
 if($Actual.errors.Count-or$Actual.installed.Count-ne2-or$null-eq$Actual.pe-or$Actual.pe.reserved_stack_bytes-ne16777216){throw 'Exact executable/PDB and previous16MiB PE reserve required'}
 $exe=@($Actual.installed|Where-Object path -CEQ $taskInstalledBinary)
 if($exe.Count-ne1-or@($Actual.cached_executables|Where-Object sha256 -CEQ $exe[0].sha256).Count-ne1){throw 'Exactly one matching cached/installed executable required'}
 $installedPdb=@($Actual.installed|Where-Object path -CEQ $taskPdb)
 $cachedMatch=@($Actual.cached_executables|Where-Object sha256 -CEQ $exe[0].sha256)
 if($installedPdb.Count-ne1-or$cachedMatch.Count-ne1-or$cachedMatch[0].pdb_sha256-isnot[string]-or$cachedMatch[0].pdb_sha256-cne$installedPdb[0].sha256){throw 'Installed and actual cached PDB byte identity must match'}
 if($null-ne$Expected){foreach($group in @('installed')){if(@(Compare-Object @($Actual.$group|ForEach-Object{$_.path+' '+$_.sha256}) @($Expected.$group|ForEach-Object{$_.path+' '+$_.sha256}) -CaseSensitive).Count){throw 'Compiled artifact changed between phases'}}}
 if($null-ne$Expected){
  $originalExe=@($Expected.installed|Where-Object path -CEQ $taskInstalledBinary)[0]
  $beforeMatch=@($Expected.cached_executables|Where-Object sha256 -CEQ $originalExe.sha256)
  $afterMatch=@($Actual.cached_executables|Where-Object sha256 -CEQ $exe[0].sha256)
  if($beforeMatch.Count-ne1-or$afterMatch.Count-ne1-or$beforeMatch[0].path-cne$afterMatch[0].path){throw 'Exact current matching cached executable identity drift'}
 }
}

# A PID can be reused while children of the older instance remain alive.
# Exclude only a child proved to predate its actual parent instance. Retain
# uncertain/sub-microsecond cases and every possible current descendant.
function Get-AbsenceUtcTicks($Value){
 if($null-eq$Value){throw 'Process creation timestamp missing'}
 if($Value-is[DateTimeOffset]){return $Value.UtcTicks}
 if($Value-is[DateTime]){
  if($Value.Kind-eq[DateTimeKind]::Unspecified){throw 'Process creation timestamp timezone unknown'}
  return $Value.ToUniversalTime().Ticks
 }
 if($Value-isnot[string]-or$Value-cnotmatch '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,7})?(?:Z|[+-]\d\d:\d\d)$'){throw 'Process creation timestamp is not explicit UTC/offset ISO'}
 return ([DateTimeOffset]::Parse($Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None)).UtcTicks
}
function Get-InstanceDescendants($Rows,$Owner){
 $parentBirth=@{};$parentBirth[[int]$Owner.pid]=[long](Get-AbsenceUtcTicks $Owner.created_utc)
 $parents=@([int]$Owner.pid);$descendants=@();$preexisting=@();$seen=@{};$seen[[int]$Owner.pid]=$true
 do{
  $children=@($Rows|Where-Object{$_.ParentProcessId-in$parents-and!$seen.ContainsKey([int]$_.ProcessId)})
  if(!$children.Count){break}
  $next=@()
  foreach($child in $children){
   $seen[[int]$child.ProcessId]=$true
   $born=[long](Get-AbsenceUtcTicks $child.CreationDate)
   $parent=[int]$child.ParentProcessId
   if(!$parentBirth.ContainsKey($parent)){throw 'Original parent creation instance missing'}
   # CIM may expose only microsecond resolution. A strict ten-tick margin
   # prevents rounding a contemporaneous child into an older-instance proof.
   if($born-lt($parentBirth[$parent]-10)){
    $preexisting+=,[ordered]@{reason='Child creation predates this parent instance';parent_pid=$parent;parent_created_utc_ticks=$parentBirth[$parent];child_created_utc_ticks=$born;observed_process=($child|Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine,CreationDate)}
    continue
   }
   $descendants+=@($child|Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine,CreationDate)
   $parentBirth[[int]$child.ProcessId]=$born
   $next+=,[int]$child.ProcessId
  }
  if(!$next.Count){break}
  $parents+=@($next)
 }while($true)
 return [ordered]@{descendants=@($descendants);preexisting_pid_ancestry=@($preexisting)}
}
function Get-PhaseEvidence([string]$Phase){
 $record=[ordered]@{valid=$true;evidence_errors=@();owner=$null;canonical_results=$null;raw_outputs=@();current_owner_pid_present=$null;current_owned_descendants=@();preexisting_pid_ancestry=@();absence_error=$null}
 $ownerPath=Join-Path $taskProof "$Phase.json"
 try{
  if(!(Test-Path -LiteralPath $ownerPath -PathType Leaf)){throw 'Owner receipt missing'}
  $record.owner=Get-Content -LiteralPath $ownerPath -Raw|ConvertFrom-Json
  if($record.owner-isnot[pscustomobject]-or($record.owner.pid-isnot[int]-and$record.owner.pid-isnot[long])-or$record.owner.pid-le0){throw 'Invalid owner receipt/PID'}
 }catch{$record.valid=$false;$record.evidence_errors+=,[ordered]@{part='owner';error=[string]$_};$record.absence_error='Owned identity unavailable or invalid'}
 if($record.owner-and!$record.absence_error){try{$rows=@(Get-TaskProcesses);$record.current_owner_pid_present=@($rows|Where-Object ProcessId -EQ $record.owner.pid).Count;$instances=Get-InstanceDescendants $rows $record.owner;$record.current_owned_descendants=@($instances.descendants);$record.preexisting_pid_ancestry=@($instances.preexisting_pid_ancestry)}catch{$record.valid=$false;$record.absence_error=[string]$_;$record.evidence_errors+=,[ordered]@{part='absence';error=[string]$_}}}
 foreach($path in @((Join-Path $taskProof "$Phase.stdout.bin"),(Join-Path $taskProof "$Phase.stderr.log"))){try{if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw 'Raw owned output missing'};$record.raw_outputs+=,[ordered]@{path=$path;bytes=(Get-Item -LiteralPath $path).Length;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}}catch{$record.valid=$false;$record.evidence_errors+=,[ordered]@{part=$path;error=[string]$_}}}
 $resultsPath=Join-Path $taskProof "$Phase.results.json"
 try{if(Test-Path -LiteralPath $resultsPath){$record.canonical_results=Get-Content -LiteralPath $resultsPath -Raw|ConvertFrom-Json}}catch{$record.valid=$false;$record.evidence_errors+=,[ordered]@{part='canonical_results';error=[string]$_}}
 return $record
}

function Get-OwnerBinding($Evidence,[string]$Step){
 $binding=[ordered]@{status='invalid';errors=@();expected_executable=$null;expected_sha256=$null;expected_deadline=@{compile=1320;metadata=30;runtime=120}[$Step]}
 try{
  if(!$Evidence.valid-or!$Evidence.owner){throw 'Valid original owner evidence required'}
  $owner=$Evidence.owner
  if($Step-eq'compile'){$binding.expected_executable=$taskZig;$binding.expected_sha256='086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864';$expectedArgs=$compileArgs}else{$binding.expected_executable=$taskBinary;$matches=@($taskArtifact.installed|Where-Object path -CEQ $taskInstalledBinary);if($matches.Count-ne1){throw 'Frozen installed executable missing'};$binding.expected_sha256=$matches[0].sha256;$expectedArgs=@('--listen=-')}
  foreach($name in @('exit_code','timeout_seconds','pid','retained_handle')){if($owner.$name-isnot[int]-and$owner.$name-isnot[long]-and$owner.$name-isnot[ulong]){throw 'Owner numeric field invalid'}}
  if($owner.status-cne'passed'-or$owner.exit_code-ne0-or$owner.timeout_seconds-ne$binding.expected_deadline-or$owner.pid-le0-or$owner.retained_handle-le0){throw 'Exact actual terminal0 owner/deadline required on positive and negative protocol paths'}
  if($owner.executable-cne$binding.expected_executable-or$owner.executable_sha256-cne$binding.expected_sha256-or$owner.working_directory-cne$taskRoot){throw 'Owner executable/hash/working-directory binding differs'}
  if([string]::Join("`n",@($owner.arguments))-cne[string]::Join("`n",$expectedArgs)){throw 'Owner launch arguments differ'}
  if(!$owner.live_identity-or$owner.live_identity.executable-cne$owner.executable-or$owner.live_identity.pid-ne$owner.pid-or$owner.live_identity.created_utc-ne$owner.created_utc-or!$owner.live_identity.command_line-or$owner.identity-cne'Retained native Process handle plus fresh executable/UTC start and exact live command line'){throw 'Original retained/live launch identity missing or inconsistent'}
  if(!$owner.created_utc-or!$owner.completed_utc){throw 'Owner launch/terminal timestamps missing'}
  $created=[DateTimeOffset]$owner.created_utc;$completed=[DateTimeOffset]$owner.completed_utc
  if($completed-lt$created){throw 'Owner terminal timestamp precedes launch'}
  if($Step-cne'compile'){
   $stderr=@($Evidence.raw_outputs|Where-Object path -CEQ (Join-Path $taskProof "$Step.stderr.log"))
   if($stderr.Count-ne1-or($stderr[0].bytes-isnot[int]-and$stderr[0].bytes-isnot[long])-or$stderr[0].bytes-lt0){throw 'Actual phase stderr evidence required'}
   if($Step-ceq'metadata'-or$selection.runtime_stderr_policy-ceq'empty'){
    if($stderr[0].bytes-ne0){throw 'Actual metadata/new API or ordinary retained runtime stderr must be empty'}
   }elseif($selection.runtime_stderr_policy-ceq'iterator_callback_observation'){
    # The actual named callback-convention control reports its observed counts.
    # This admits one bounded note only; it never classifies a fatal reason.
    $causal='native_async_iterator_api_test.test.native async iterator API new pending reason cleanup and callback convention control'
    if($Group-cne'new-combined'-or@($selection.names|Where-Object{$_-ceq$causal}).Count-ne1-or$stderr[0].bytes-gt256){throw 'Only the selected bounded iterator observation is permitted'}
    $text=[Text.UTF8Encoding]::new($false,$true).GetString([IO.File]::ReadAllBytes($stderr[0].path))
    $match=[regex]::Match($text,'\Aiterator API native callback convention violation observation: getter=1 method=([01]) owned_result_finalized=(true|false)\n\z')
    if(!$match.Success-or($match.Groups[1].Value-ceq'1'-and$match.Groups[2].Value-cne'true')-or($match.Groups[1].Value-ceq'0'-and$match.Groups[2].Value-cne'false')){throw 'Exact one actual iterator observation line and ownership consistency required'}
   }elseif($selection.runtime_stderr_policy-ceq'retained_generator_gpa_debug'){
    # Original unchanged GPA controls intentionally print caught diagnostics.
    # Canonical flags/assertions remain authority; do not classify OOM by text.
    if($Group-cne'core-generator-gpa'-or$stderr[0].bytes-gt65536){throw 'Only bounded retained generator GPA diagnostics permitted'}
   }elseif($selection.runtime_stderr_policy-ceq'retained_legacy_heap_coverage'){
    if($Group-cne'core-recovery'-or$stderr[0].bytes-gt4096){throw 'Only bounded legacy coverage report permitted'}
    $text=[IO.File]::ReadAllText($stderr[0].path).Trim()
    $prefix='LEGACY_FUNCTION_VM_HEAP_LIMIT_COVERAGE='
    if(!$text.StartsWith($prefix,[StringComparison]::Ordinal)){throw 'Actual retained legacy coverage schema required'}
    $coverage=$text.Substring($prefix.Length)|ConvertFrom-Json
    foreach($field in @('programs','minimum_budget','maximum_budget','step','completed','owner_leaks')){
     if($coverage.$field-isnot[int]-and$coverage.$field-isnot[long]){throw 'Actual scalar legacy coverage field required'}
    }
    if($coverage.programs-ne2-or$coverage.minimum_budget-ne0-or$coverage.maximum_budget-ne8192-or$coverage.step-ne32-or$coverage.completed-ne514-or$coverage.owner_leaks-ne0-or$coverage.exhaustive_C_malloc-isnot[bool]-or$coverage.exhaustive_C_malloc-ne$false-or$coverage.trusted_OOM_classification-isnot[bool]-or$coverage.trusted_OOM_classification-ne$false){throw 'Preserved explicit legacy coverage limitations required'}
    foreach($counts in @($coverage.failures,$coverage.successes)){
     if($counts-isnot[array]-or$counts.Count-ne2){throw 'Actual legacy per-program counts required'}
     foreach($number in $counts){if(($number-isnot[int]-and$number-isnot[long])-or$number-lt0-or$number-gt257){throw 'Bounded actual legacy program count required'}}
    }
    for($index=0;$index-lt2;$index++){if($coverage.failures[$index]+$coverage.successes[$index]-ne257){throw 'Complete actual legacy budget sweep required'}}
   }else{throw 'Unknown sealed runtime stderr policy'}
  }
  if($Step-eq'runtime'){
   $summary=$Evidence.canonical_results
   if($summary-isnot[pscustomobject]-or$summary.binary-isnot[string]-or$summary.binary_sha256-isnot[string]-or$summary.binary-cne$taskBinary-or$summary.binary_sha256-cne$binding.expected_sha256){throw 'Actual canonical runtime executable binding differs'}
   foreach($name in @('expected','started','completed','failed_or_skipped_or_logged_or_leaked')){if(($summary.$name-isnot[int]-and$summary.$name-isnot[long])-or$summary.$name-lt0){throw 'Actual canonical runtime scalar count invalid'}}
   if($summary.version-cne'0.16.0'-or$summary.expected-ne$selection.names.Count-or$summary.started-gt$summary.expected-or$summary.completed-gt$summary.started-or$summary.results-isnot[array]-or$summary.results.Count-ne$summary.completed){throw 'Actual canonical runtime count/version/array inconsistent'}
   $index=0;$failed=0
   foreach($result in $summary.results){if($result-isnot[pscustomobject]-or($result.index-isnot[int]-and$result.index-isnot[long])-or$result.index-ne$index-or($result.flags-isnot[int]-and$result.flags-isnot[long]-and$result.flags-isnot[ulong])-or$result.flags-lt0-or$result.passed-isnot[bool]-or$result.passed-ne($result.flags-eq0)){throw 'Actual canonical runtime result schema/index/flag inconsistent'};if($result.flags-ne0){$failed++};$index++}
   if($failed-ne$summary.failed_or_skipped_or_logged_or_leaked){throw 'Actual canonical runtime failure count inconsistent'}
   $expectedStatus=if($summary.started-eq$summary.expected-and$summary.completed-eq$summary.expected-and$failed-eq0){'passed'}else{'failed'}
   if($summary.status-isnot[string]-or$summary.status-cne$expectedStatus){throw 'Actual canonical runtime terminal status inconsistent'}
  }
  $binding.status='passed'
 }catch{$binding.errors+=,[string]$_}
 return $binding
}

function Observe-RuntimeFrames([string]$Phase) {
 $path=Join-Path $taskProof "$Phase.stdout.bin";$observation=[ordered]@{scope='Raw complete protocol frames including partial failure evidence; never acceptance authority';frames=@();parse_error=$null;trailing_bytes=0}
 if(Test-Path -LiteralPath $path){try{$bytes=[IO.File]::ReadAllBytes($path);$offset=0;while($offset-lt$bytes.Length){if($bytes.Length-$offset-lt8){$observation.trailing_bytes=$bytes.Length-$offset;break};$tag=[BitConverter]::ToUInt32($bytes,$offset);$length=[BitConverter]::ToUInt32($bytes,$offset+4);$offset+=8;if($length-gt1MB-or$length-gt$bytes.Length-$offset){$observation.trailing_bytes=$bytes.Length-$offset;throw 'Incomplete/invalid raw frame body'};$frame=[ordered]@{tag=$tag;length=$length};if($tag-eq0){$frame.version=[Text.Encoding]::UTF8.GetString($bytes,$offset,$length)};if($tag-eq4-and$length-eq12){$frame.index=[BitConverter]::ToUInt32($bytes,$offset);$frame.flags=[BitConverter]::ToUInt64($bytes,$offset+4)};$observation.frames+=,$frame;$offset+=$length}}catch{$observation.parse_error=[string]$_}}
 Save-Json $observation "$Phase-raw-frame-observation.json"
}

function Get-ObserverEnvironment {$value=[Environment]::GetEnvironmentVariable('PI_TYPEBOX_STACK_OBSERVER_FILE',[EnvironmentVariableTarget]::Process);return [ordered]@{present=($null-ne$value);value=$value}}

function Restore-ObserverEnvironment($Snapshot){[Environment]::SetEnvironmentVariable('PI_TYPEBOX_STACK_OBSERVER_FILE',$(if($Snapshot.present){[string]$Snapshot.value}else{[NullString]::Value}),[EnvironmentVariableTarget]::Process);$actual=Get-ObserverEnvironment;if($actual.present-ne$Snapshot.present-or($actual.present-and$actual.value-cne$Snapshot.value)){throw 'Exact observer environment restoration failed'}}

$taskCache=$null;$taskGlobalCache=$null;$taskBuildResult=$null;$taskBuildSourceSeal=$null;$taskAcceptance=$null;$taskBuildProof=$null
foreach($selected in $taskSelections){foreach($pin in @($selected.external_pins)){
 $path=Contained ([string]$pin.path) $taskContainer
 if(!$path.StartsWith((Join-Path $taskContainer 'upstream')+'\',[StringComparison]::OrdinalIgnoreCase)-or$pin.sha256-cnotmatch'^[0-9A-F]{64}$'-or(Get-FileHash -LiteralPath $path).Hash-cne$pin.sha256){throw 'Exact contained external reference input required'}
 $taskControlPaths+=@($path)
}}
if($taskBuildMode){
 $taskCache=Contained ([string]$taskGrant.cache_directory) $taskWorkspace.evidence
 $taskGlobalCache=Contained ([string]$taskGrant.global_cache_directory) $taskWorkspace.evidence
 if($taskCache-cne(Join-Path $batchProof 'cache')-or$taskGlobalCache-cne(Join-Path $batchProof 'global-cache')-or(Test-Path -LiteralPath $taskCache)-or(Test-Path -LiteralPath $taskGlobalCache)){throw 'One initially absent private cache pair required for fresh batch'}
}else{
 $taskBuildResultPath=Contained ([string]$taskGrant.build_result_path) $taskWorkspace.evidence
 $taskBuildSealPath=Contained ([string]$taskGrant.build_source_seal_path) $taskWorkspace.evidence
 $taskAcceptancePath=Contained ([string]$taskGrant.metadata_acceptance_path) $taskWorkspace.evidence
 foreach($pin in @(@{path=$taskBuildResultPath;hash=$taskGrant.build_result_sha256},@{path=$taskBuildSealPath;hash=$taskGrant.build_source_seal_sha256},@{path=$taskAcceptancePath;hash=$taskGrant.metadata_acceptance_sha256})){
  if($pin.hash-isnot[string]-or$pin.hash-cnotmatch'^[0-9A-F]{64}$'-or(Get-FileHash -LiteralPath $pin.path).Hash-cne$pin.hash){throw 'Exact closed whole-batch BuildQuery, final source seal and independent acceptance pins required'}
 }
 $taskBuildProof=Split-Path -Parent $taskBuildResultPath
 if($taskBuildResultPath-cne(Join-Path $taskBuildProof 'result.json')-or$taskBuildSealPath-cne(Join-Path $taskBuildProof 'final.json')){throw 'Exact whole-batch evidence paths required'}
 $taskBuildResult=Get-Content -LiteralPath $taskBuildResultPath -Raw|ConvertFrom-Json
 $taskBuildSourceSeal=Get-Content -LiteralPath $taskBuildSealPath -Raw|ConvertFrom-Json
 $taskAcceptance=Get-Content -LiteralPath $taskAcceptancePath -Raw|ConvertFrom-Json
 if($taskBuildResult.status-cne'passed_build_query_batch'-or$taskBuildResult.mode-cne'BuildQuery'-or$taskBuildResult.candidate_head-cne$taskHead-or$taskBuildResult.driver_sha256-cne$taskGrant.driver_sha256-or$taskBuildResult.group_manifest_sha256-cne$taskGrant.group_manifest_sha256-or$taskBuildResult.cache_mode-cne'fresh_batch'-or@($taskBuildResult.errors).Count-or@($taskBuildResult.absence.native_roots).Count){throw 'Successful same-controller exact-head complete fresh BuildQuery batch required'}
 foreach($flag in @('postseal','controller_environment_restored','fresh_cache_reproduction','qualification_requested','all_groups_closed')){if($taskBuildResult.$flag-isnot[bool]-or$taskBuildResult.$flag-ne$true){throw 'Incomplete whole-batch closure Boolean'}}
 foreach($flag in @('runtime_requested','product_qualified','cache_seeded')){if($taskBuildResult.$flag-isnot[bool]-or$taskBuildResult.$flag-ne$false){throw 'Runtime rejects diagnostic, seeded or product qualification claims'}}
 if($taskAcceptance.accepted-isnot[bool]-or$taskAcceptance.accepted-ne$true-or$taskAcceptance.status-cne'independently_accepted_combined_native_batch_metadata'-or$taskAcceptance.candidate_head-cne$taskHead-or$taskAcceptance.driver_sha256-cne$taskGrant.driver_sha256-or$taskAcceptance.group_manifest_sha256-cne$taskGrant.group_manifest_sha256-or!$taskAcceptance.reviewer-or!$taskAcceptance.reviewed_utc-or$taskAcceptance.build_result_sha256-cne$taskGrant.build_result_sha256-or$taskAcceptance.build_source_seal_sha256-cne$taskGrant.build_source_seal_sha256){throw 'Actual independent complete batch acceptance required'}
 if($taskAcceptance.runtime_started-isnot[bool]-or$taskAcceptance.runtime_started-ne$false-or$taskAcceptance.groups-isnot[array]-or$taskBuildResult.groups-isnot[array]-or[string]::Join([char]10,@($taskAcceptance.groups.group))-cne[string]::Join([char]10,@($taskGrant.groups))-or[string]::Join([char]10,@($taskBuildResult.groups.group))-cne[string]::Join([char]10,@($taskGrant.groups))){throw 'Exact complete independently accepted ordered batch group list required'}
 if($taskBuildSourceSeal.clean-isnot[bool]-or$taskBuildSourceSeal.clean-ne$true-or$taskBuildSourceSeal.candidate_head-cne$taskHead-or@($taskBuildSourceSeal.errors).Count){throw 'Complete original source/compiler seal required'}
 $taskCache=Contained ([string]$taskBuildResult.cache_directory) $taskWorkspace.evidence
 $taskGlobalCache=Contained ([string]$taskBuildResult.global_cache_directory) $taskWorkspace.evidence
 if($taskCache-cne(Join-Path $taskBuildProof 'cache')-or$taskGlobalCache-cne(Join-Path $taskBuildProof 'global-cache')-or$taskGrant.cache_directory-cne$taskCache-or$taskGrant.global_cache_directory-cne$taskGlobalCache){throw 'Runtime binds the same fresh batch cache role'}
 $taskControlPaths+=@($taskBuildResultPath,$taskBuildSealPath,$taskAcceptancePath)
 foreach($selected in $taskSelections){
  $group=$selected.name;$accepted=@($taskAcceptance.groups|Where-Object group -CEQ $group)[0]
  $part=@($taskBuildResult.groups|Where-Object group -CEQ $group)[0]
  if($part.status-cne'passed_build_query'-or$part.postseal-ne$true-or@($part.errors).Count-or$part.runtime_requested-ne$false-or$part.actual_runtime_owner_started-ne$false-or[string]::Join([char]10,@($part.attempted_phases))-cne'compile'+[char]10+'metadata'-or[string]::Join([char]10,@($part.owned_started_phases))-cne'compile'+[char]10+'metadata'){throw 'Each original group must close exact compile and metadata phases'}
  foreach($phase in @('compile','metadata')){
   $step=$part.phases.$phase
   if(!$step-or$step.failure-or$step.original_execution_failure-or$step.owner_binding.status-cne'passed'-or$step.evidence.valid-ne$true){throw 'Original group owner phase closure missing'}
   foreach($flag in @('evidence_valid','owner_bound','source_sealed','artifacts_bound','absence_closed')){if($step.postchecks.$flag-isnot[bool]-or$step.postchecks.$flag-ne$true){throw 'Original group complete postchecks required'}}
  }
  $groupProof=Contained (Join-Path $taskBuildProof ('groups/'+$group)) $taskBuildProof
  foreach($role in @(@{name='build-artifacts.json';hash=$accepted.build_artifacts_sha256},@{name='selected-tests.json';hash=$accepted.build_metadata_sha256})){
   $path=Join-Path $groupProof $role.name
   if($role.hash-isnot[string]-or$role.hash-cnotmatch'^[0-9A-F]{64}$'-or(Get-FileHash -LiteralPath $path).Hash-cne$role.hash){throw 'Independent per-group evidence pin changed'}
   $taskControlPaths+=@($path)
  }
 }
}
[void][IO.Directory]::CreateDirectory($batchProof)
$taskAdmissions=[Collections.Generic.List[object]]::new()
$taskInitialAdmitted=$false

$taskEnvironmentOriginal=Get-ObserverEnvironment
$batchResult=[ordered]@{schema=1;status='running';mode=$Mode;candidate_head=$taskHead;driver_sha256=$taskGrant.driver_sha256;group_manifest_sha256=$taskGrant.group_manifest_sha256;qualification_requested=$true;cache_mode='fresh_batch';cache_seeded=$false;fresh_cache_reproduction=$taskBuildMode;runtime_requested=(!$taskBuildMode);product_qualified=$false;scope='One frozen source head; one initially fresh private cache pair shared serially; distinct installed prefixes and actual metadata per group; complete whole-batch source/compiler/control bookend seals';source_seal_scope='whole_batch';groups=@();postseal=$false;all_groups_closed=$false;controller_environment_restored=$false;errors=@();absence=$null;cache_directory=$taskCache;global_cache_directory=$taskGlobalCache;initial_cache_absence=($taskBuildMode-and!(Test-Path -LiteralPath $taskCache)-and!(Test-Path -LiteralPath $taskGlobalCache))}
$taskBefore=$null;$taskBaselineAccepted=$false;$taskResult=$null
try{
 Restore-ObserverEnvironment ([ordered]@{present=$false;value=$null})
 $engine=Get-Content -LiteralPath (Join-Path $taskRoot 'src/extensions/engine.zig') -Raw
 if($engine-notmatch'stack_limit:\s*usize\s*=\s*1024\s*\*\s*1024'){throw 'Unchanged1MiB Engine guard required'}
 foreach($selected in $taskSelections){if((Get-Content -LiteralPath (Join-Path $taskRoot $selected.source_root) -Raw)-match'\.stack_limit\s*='){throw 'No control may override the default Engine guard'}}
 $taskBefore=Get-TaskSeal 'before';Assert-TaskSeal $taskBefore $null;$taskBaselineAccepted=$true
 if(!$taskBuildMode){foreach($sealGroup in @('source','tree','vendor','compiler')){Assert-Rows $taskBefore[$sealGroup] $taskBuildSourceSeal.($sealGroup) $sealGroup}}
 foreach($selected in $taskSelections){
  $selection=$selected;$Group=[string]$selection.name
  $taskProof=Contained (Join-Path $batchProof ('groups/'+$Group)) $batchProof
  if(Test-Path -LiteralPath $taskProof){throw 'Each group receipt directory must initially be absent'}
  [void][IO.Directory]::CreateDirectory($taskProof)
  $taskPrefix=if($taskBuildMode){Join-Path $taskProof 'installed'}else{Join-Path $taskBuildProof ('groups/'+$Group+'/installed')}
  $taskInstalledBinary=Join-Path $taskPrefix ('bin/'+$selection.artifact+'.exe');$taskPdb=Join-Path $taskPrefix 'bin/test.pdb';$taskBinary=$null
  $taskArtifact=$null
  if($taskBuildMode){if(Test-Path -LiteralPath $taskPrefix){throw 'Group installed prefix must be absent'}}
  else{
   $buildGroup=Join-Path $taskBuildProof ('groups/'+$Group)
   $taskArtifact=Get-Content -LiteralPath (Join-Path $buildGroup 'build-artifacts.json') -Raw|ConvertFrom-Json
   $metadata=Get-Content -LiteralPath (Join-Path $buildGroup 'selected-tests.json') -Raw|ConvertFrom-Json
   $accepted=@($taskAcceptance.groups|Where-Object group -CEQ $Group)[0]
   Assert-SelectedNames @($metadata.tests)
   $selection.names=@($metadata.tests)
   Assert-TaskArtifacts (Get-TaskArtifacts 'runtime-prerequisite') $taskArtifact
   $installed=@($taskArtifact.installed|Where-Object path -CEQ $taskInstalledBinary)[0]
   $pdb=@($taskArtifact.installed|Where-Object path -CEQ $taskPdb)[0]
   $cached=@($taskArtifact.cached_executables|Where-Object sha256 -CEQ $installed.sha256)[0]
   $taskBinary=Contained ([string]$cached.path) $taskCache
   $cachedPdb=Contained ([string]$cached.pdb_path) $taskCache
   if([IO.Path]::GetFileName($taskBinary)-cne'test.exe'-or$cachedPdb-cne(Join-Path (Split-Path -Parent $taskBinary) 'test.pdb')){throw 'Actual canonical cached test.exe/test.pdb required'}
   if($metadata.binary-cne$taskBinary-or$metadata.binary_sha256-cne$installed.sha256-or$metadata.candidate_head-cne$taskHead-or$metadata.group-cne$Group-or$metadata.version-cne'0.16.0'-or$metadata.runtime_started-isnot[bool]-or$metadata.runtime_started-ne$false-or$metadata.tests-isnot[array]-or($metadata.actual_count-isnot[int]-and$metadata.actual_count-isnot[long])-or$metadata.actual_count-ne$selection.names.Count){throw 'Actual complete metadata schema and artifact role differ'}
   if($accepted.cached_executable_path-cne$taskBinary-or$accepted.executable_sha256-cne$installed.sha256-or$accepted.pdb_sha256-cne$pdb.sha256-or$accepted.tests-isnot[array]-or($accepted.actual_count-isnot[int]-and$accepted.actual_count-isnot[long])-or$accepted.actual_count-ne$selection.names.Count-or[string]::Join([char]10,@($accepted.tests))-cne[string]::Join([char]10,$selection.names)){throw 'Independent complete ordered metadata and artifact acceptance differ'}
  }
  $taskResult=[ordered]@{group=$Group;status='running';mode=$Mode;candidate_head=$taskHead;receipt_directory=$taskProof;output_prefix=$taskPrefix;installed_executable=$taskInstalledBinary;installed_pdb=$taskPdb;cached_executable=$taskBinary;phases=[ordered]@{};postseal=$false;source_seal_scope='whole_batch';errors=@();runtime_requested=(!$taskBuildMode);runtime_owner_launch_attempted=$false;actual_runtime_owner_started=$false;native_selected_tests_started=$null;attempted_phases=@();owned_started_phases=@()}
  $batchResult.groups+=,$taskResult
  $taskStartedPhases=[Collections.Generic.List[string]]::new();$taskAttemptedPhases=[Collections.Generic.List[string]]::new()
  $compileArgs=@('build',$selection.target,'-Doptimize=Debug','-Duse-llvm=true','-Ddiagnostic-tests=false','-j1','--test-timeout','120s','--prefix',$taskPrefix,'--cache-dir',$taskCache,'--global-cache-dir',$taskGlobalCache,'--summary','all')
  $steps=if($taskBuildMode){@('compile','metadata')}else{@('runtime')}
  Save-Json ([ordered]@{mode=$Mode;group=$Group;compile=$compileArgs;metadata=@('--listen=-');runtime=@('--listen=-');expected_names=$selection.names;expected_count=$(if($taskBuildMode){$null}else{$selection.names.Count});named_controls=@($selection.required_named).Count;source_seal_scope='whole_batch';cache_authority='One initially fresh private cache pair; serial exact-head group compilation; no seed lineage';compile_seconds=1320;metadata_seconds=30;runtime_whole_group_seconds=120;pipe_settle_seconds=10;installed_executable=$taskInstalledBinary;installed_pdb=$taskPdb}) 'commands.json'
  try{
 foreach($step in $steps){
  $phase=$step;$taskAttemptedPhases.Add($phase)
  if($step-ne'compile'){Assert-TaskArtifacts (Get-TaskArtifacts "$phase-before") $taskArtifact}
  Assert-TaskAdmission $phase
  if(!$taskInitialAdmitted){Assert-InitialGrantFresh;$taskInitialAdmitted=$true}
  $phaseFailure=$null
  try{
   switch($step){
    compile{[void](Invoke-CiOwnedProcess $taskZig $compileArgs $taskRoot (Join-Path $taskProof $phase) 1320)}
    metadata{$metadata=Read-ComposedMetadata $taskBinary $taskRoot (Join-Path $taskProof $phase);$selection.names=@($metadata.tests);Save-Json $metadata 'selected-tests.json'}
    runtime{$taskResult.runtime_owner_launch_attempted=$true;$taskResult.actual_runtime_owner_started=$null;[void](Invoke-NativeTestProtocol -Binary $taskBinary -Root $taskRoot -Receipt (Join-Path $taskProof $phase) -ExpectedCount $selection.names.Count)}
   }
  }catch{$phaseFailure=[string]$_}finally{
   $originalExecutionFailure=$phaseFailure
   $post=[ordered]@{evidence_valid=$false;owner_bound=$false;source_sealed=$false;artifacts_bound=$false;absence_closed=$false;errors=@()}
   try{$evidence=Get-PhaseEvidence $phase}catch{$evidence=[ordered]@{valid=$false;evidence_errors=@([string]$_);owner=$null;canonical_results=$null;raw_outputs=@();current_owner_pid_present=$null;current_owned_descendants=@();absence_error='Evidence read failed; identity unknown'}}
   if($step-ceq'runtime'-and$evidence.canonical_results){$taskResult.native_selected_tests_started=$evidence.canonical_results.started;$taskResult.runtime_count_observation=[ordered]@{expected=$evidence.canonical_results.expected;started=$evidence.canonical_results.started;completed=$evidence.canonical_results.completed;failed_or_skipped_or_logged_or_leaked=$evidence.canonical_results.failed_or_skipped_or_logged_or_leaked;status=$evidence.canonical_results.status;acceptance_authority='Validated canonical result and all original owner/postseal gates remain required'}}
    $owner=$evidence.owner
   $startValid=($owner-and$owner.pid-gt0-and$owner.retained_handle-gt0-and$owner.created_utc-and$owner.live_identity-and$owner.live_identity.pid-eq$owner.pid-and$owner.live_identity.created_utc-eq$owner.created_utc-and$owner.live_identity.executable-ceq$owner.executable-and$owner.live_identity.command_line-and$owner.working_directory-ceq$taskRoot)
   if($startValid){foreach($field in @('pid','retained_handle')){if($owner.$field-isnot[int]-and$owner.$field-isnot[long]-and$owner.$field-isnot[ulong]){$startValid=$false}};if($owner.identity-cne'Retained native Process handle plus fresh executable/UTC start and exact live command line'){$startValid=$false}}
   if($startValid){$expectedStartExe=if($step-ceq'compile'){$taskZig}else{$taskBinary};$expectedStartHash=if($step-ceq'compile'){'086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'}else{if($taskArtifact){@($taskArtifact.installed|Where-Object path -CEQ $taskInstalledBinary)[0].sha256}else{$null}};$expectedStartArgs=if($step-ceq'compile'){$compileArgs}else{@('--listen=-')};$startValid=($owner.executable-ceq$expectedStartExe-and$owner.executable_sha256-ceq$expectedStartHash-and[string]::Join("`n",@($owner.arguments))-ceq[string]::Join("`n",$expectedStartArgs))}
   if($startValid){$taskStartedPhases.Add($phase);if($step-ceq'runtime'){$taskResult.actual_runtime_owner_started=$true}}
   $post.evidence_valid=($evidence.valid-eq$true)
   $taskResult.phases[$phase]=[ordered]@{failure=$phaseFailure;original_execution_failure=$originalExecutionFailure;evidence=$evidence;owner_binding=$null;postchecks=$post}
   try{$binding=Get-OwnerBinding $evidence $step;$taskResult.phases[$phase].owner_binding=$binding;if($binding.status-cne'passed'){throw ('Actual terminal owner binding failed: '+($binding.errors-join '; '))};$post.owner_bound=$true;if($step-ceq'runtime'){$taskResult.native_selected_tests_started=$evidence.canonical_results.started}}catch{$post.errors+=,[string]$_;$taskResult.errors+=,[string]$_;if(!$phaseFailure){$phaseFailure=[string]$_}}
   $post.source_seal_scope='Whole batch before/final; no group is admissible until the final complete seal closes'
   try{$artifacts=Get-TaskArtifacts "$phase-after";if($step-ceq'compile'){if(!$phaseFailure){Assert-TaskArtifacts $artifacts $null;$taskArtifact=$artifacts;$installedExe=@($artifacts.installed|Where-Object path -CEQ $taskInstalledBinary)[0];$taskBinary=@($artifacts.cached_executables|Where-Object sha256 -CEQ $installedExe.sha256)[0].path;$taskResult.cached_executable=$taskBinary;$post.artifacts_bound=$true}}else{Assert-TaskArtifacts $artifacts $taskArtifact;$post.artifacts_bound=$true}}catch{$post.errors+=,[string]$_;$taskResult.errors+=,[string]$_;if(!$phaseFailure){$phaseFailure=[string]$_}}
   try{$roots=@(Select-TaskNative (Get-TaskProcesses));$closed=($evidence.valid-eq$true-and$roots.Count-eq0-and!$evidence.absence_error-and$evidence.owner-and$evidence.current_owner_pid_present-eq0-and$evidence.current_owned_descendants.Count-eq0);Save-Json ([ordered]@{phase=$phase;status=$(if($closed){'closed'}else{'failed_or_unknown'});evidence=$evidence;global_native=@($roots|Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine,CreationDate)}) "$phase-absence.json";if(!$closed){throw 'Owned/global native absence failed or unknown'};$post.absence_closed=$true}catch{$post.errors+=,[string]$_;$taskResult.errors+=,[string]$_;if(!$phaseFailure){$phaseFailure=[string]$_}}
   if($step-ceq'runtime'){try{Observe-RuntimeFrames $phase}catch{$post.errors+=,[string]$_;$taskResult.errors+=,[string]$_;if(!$phaseFailure){$phaseFailure=[string]$_}}}
   $taskResult.phases[$phase].failure=$phaseFailure
  }
  if($phaseFailure){throw $phaseFailure}
 }
   if($taskBuildMode){Save-Json $taskArtifact 'build-artifacts.json'}
   else{
    $summary=$taskResult.phases.runtime.evidence.canonical_results
    if(!$summary-or$summary.status-cne'passed'-or$summary.started-ne$selection.names.Count-or$summary.completed-ne$selection.names.Count-or$summary.failed_or_skipped_or_logged_or_leaked-ne0){throw 'All independently accepted actual indices must have flags zero'}
   }
   $taskResult.status='awaiting_batch_closure'
  }catch{$taskResult.status='failed';$taskResult.errors+=,[string]$_;throw}finally{
   $taskResult.attempted_phases=$taskAttemptedPhases.ToArray();$taskResult.owned_started_phases=$taskStartedPhases.ToArray()
   Save-Json $taskResult 'result-provisional.json' 22
  }
  Write-Output ('Group '+$Group+' completed actual '+$Mode+' phases; awaiting whole-batch closure')
 }
 $batchResult.status='awaiting_final_seals'
}catch{
 $batchResult.status='failed';$batchResult.errors+=,[string]$_
}finally{
 $taskProof=$batchProof
 try{Restore-ObserverEnvironment $taskEnvironmentOriginal;$batchResult.controller_environment_restored=$true}catch{$batchResult.status='failed_environment_restore';$batchResult.errors+=,[string]$_}
 try{
  $final=Get-TaskSeal 'final'
  if(!$taskBefore-or!$taskBaselineAccepted){throw 'No accepted baseline; final observation retained'}
  Assert-TaskSeal $final $taskBefore
  $batchResult.postseal=$true
  foreach($part in $batchResult.groups){
   $part.postseal=$true
   foreach($phase in $part.phases.Keys){$part.phases[$phase].postchecks.source_sealed=$true}
  }
 }catch{$batchResult.status='failed_postseal';$batchResult.errors+=,[string]$_}
 try{
  $rows=@(Get-TaskProcesses);$roots=@(Select-TaskNative $rows)
  $owners=@(foreach($part in $batchResult.groups){
   $taskProof=$part.receipt_directory
   foreach($phase in $part.owned_started_phases){[ordered]@{group=$part.group;phase=$phase;evidence=(Get-PhaseEvidence $phase)}}
  })
  $batchResult.absence=[ordered]@{native_roots=@($roots|Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine,CreationDate);owners=$owners}
  if($roots.Count-or@($owners|Where-Object{$_.evidence.valid-ne$true-or!$_.evidence.owner-or$_.evidence.absence_error-or$_.evidence.current_owner_pid_present-or$_.evidence.current_owned_descendants.Count}).Count){throw 'Final actual owned/global native absence failed or unknown'}
 }catch{$batchResult.status='failed_absence';$batchResult.errors+=,[string]$_}
 foreach($part in $batchResult.groups){
  try{
   $taskProof=$part.receipt_directory;$selection=@($taskSelections|Where-Object name -CEQ $part.group)[0]
   $taskPrefix=$part.output_prefix;$taskInstalledBinary=$part.installed_executable;$taskPdb=$part.installed_pdb
   $artifactPath=if($taskBuildMode){Join-Path $taskProof 'build-artifacts.json'}else{Join-Path $taskBuildProof ('groups/'+$part.group+'/build-artifacts.json')}
   if(Test-Path -LiteralPath $artifactPath){$expectedArtifact=Get-Content -LiteralPath $artifactPath -Raw|ConvertFrom-Json;Assert-TaskArtifacts (Get-TaskArtifacts 'final') $expectedArtifact}
   elseif($part.status-ceq'awaiting_batch_closure'){throw 'A completed group must retain its original actual artifact receipt'}
  }catch{$batchResult.status='failed_final_artifact';$batchResult.errors+=,[string]$_;$part.errors+=,[string]$_}
 }
 $taskProof=$batchProof
 if($batchResult.status-ceq'awaiting_final_seals'-and$batchResult.postseal-and$batchResult.controller_environment_restored-and$batchResult.errors.Count-eq0-and$batchResult.groups.Count-eq$taskSelections.Count-and@($batchResult.groups|Where-Object{$_.status-cne'awaiting_batch_closure'}).Count-eq0){
  $batchResult.all_groups_closed=$true
  $batchResult.status=if($taskBuildMode){'passed_build_query_batch'}else{'passed_selected_native_batch'}
  foreach($part in $batchResult.groups){$part.status=if($taskBuildMode){'passed_build_query'}else{'passed_selected_native_controls'}}
 }
 foreach($part in $batchResult.groups){
  if($part.status-ceq'awaiting_batch_closure'){$part.status='partial_batch_not_admissible'}
  $taskProof=$part.receipt_directory;Save-Json $part 'result.json' 22
 }
 $taskProof=$batchProof
 $batchResult.admission_probes=$taskAdmissions.ToArray();$batchResult.completed_utc=[DateTimeOffset]::UtcNow.ToString('o')
 Save-Json $batchResult 'result.json' 24
}
$batchResult|ConvertTo-Json -Depth 24
if($batchResult.status-cnotin@('passed_build_query_batch','passed_selected_native_batch')){throw 'Native batch terminal negative; no group may enter runtime from this partial batch'}
