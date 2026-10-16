param([Parameter(Mandatory)][string]$ReceiptBase,[Parameter(Mandatory)][string]$OutputDirectory,[Parameter(Mandatory)][string]$RootGrant)
$ErrorActionPreference='Stop'
$taskRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$taskHead=(git -C $taskRoot rev-parse HEAD).Trim()
$taskDirectory=[IO.DirectoryInfo]::new($taskRoot)
while($taskDirectory-and!(Test-Path -LiteralPath (Join-Path $taskDirectory.FullName '.pi-zig-workspace.json'))){$taskDirectory=$taskDirectory.Parent}
if(!$taskDirectory){throw 'Contained workspace metadata not found'}
$taskResolver=Join-Path $taskDirectory.FullName 'main/tools/workspace/Resolve-PiZigWorkspace.ps1'
$taskWorkspace=& $taskResolver -StartPath $PSScriptRoot
function ContainedPath([string]$Path,[string]$Under){
 if(!$Path){throw 'Explicit contained path required'}
 $resolved=[IO.Path]::GetFullPath($Path)
 if(!$resolved.StartsWith([IO.Path]::GetFullPath($Under)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Source/staging path escapes its declared container'}
 $ancestor=[IO.DirectoryInfo]::new($resolved)
 while($ancestor){if($ancestor.Exists-and($ancestor.Attributes-band[IO.FileAttributes]::ReparsePoint)){throw 'Source/staging ancestor is a reparse point'};if($ancestor.FullName-eq$taskWorkspace.Container){break};$ancestor=$ancestor.Parent}
 return $resolved
}
$RootGrant=ContainedPath $RootGrant $taskWorkspace.evidence
if(!(Test-Path -LiteralPath $RootGrant -PathType Leaf)-or((Get-Item -LiteralPath $RootGrant).Attributes-band[IO.FileAttributes]::ReparsePoint)){throw 'Contained regular Root grant file required'}
$taskGrant=Get-Content -LiteralPath $RootGrant -Raw|ConvertFrom-Json
if($taskGrant.status-cne'root_reviewed_typebox_static_package_authoring_release'-or$taskGrant.candidate_head-cne$taskHead-or$taskGrant.input_authority-cne'source_package_only'-or$taskGrant.runtime_restoration_claim-ne$false-or@(git -C $taskRoot status --porcelain).Count){throw 'Explicit exact clean-head source-only package grant required'}
$taskLayout=Join-Path $taskWorkspace.Container '.pi-zig-workspace.json'
$taskOwner=Join-Path $taskWorkspace.main 'tools/ci/native_qualification_ci.ps1'
$taskGenerator=Join-Path $taskRoot 'verification/typebox-operators-production-20261016/lower-authority.mjs'
$taskInput=Join-Path $taskRoot 'src/extensions/fixtures/typebox-operators-production.input.txt'
$taskAuthority=Join-Path $taskWorkspace.evidence 'typebox-heap-scope-args-static-second49d-20261016-frozen.json'
$taskCopyReceipt=Join-Path $taskWorkspace.evidence 'typebox-package-source-copy-20261016/receipt.json'
$taskNodeRoot='C:\Program Files\nodejs'
foreach($seal in @(
 @{path=$taskResolver;hash=$taskGrant.workspace_resolver_sha256},@{path=$taskLayout;hash=$taskGrant.workspace_layout_sha256},@{path=$taskWorkspace.path_relocations;hash=$taskGrant.path_relocations_sha256},
 @{path=$PSCommandPath;hash=$taskGrant.caller_sha256},@{path=$taskGenerator;hash=$taskGrant.driver_sha256},
 @{path=$taskOwner;hash='607BEDBB91FE318D214CD2C3B9C83D80437335C0062C320C0EACB3A745B38285'},
 @{path=$taskAuthority;hash='35F1F2B0F12BF79C06B47AE2BA8C485EF10A7714BE3F129772E3BA1BBB97B927'},
 @{path=$taskCopyReceipt;hash='C25DAC45CA507D50EA03CA20C051423B6F1F07D6D72720688090A3B2ECC96869'},
 @{path=$taskInput;hash='37CEEAC103C70BF1C587F03CAA11C5EE4EC0A6AE414222D8653116E94DB5C9AA'}
)){if(!$seal.hash-or(Get-FileHash -LiteralPath $seal.path -Algorithm SHA256).Hash-cne$seal.hash){throw "Sealed package-authoring control drift: $($seal.path)"}}
$taskPackage=ContainedPath ([string]$taskGrant.source_package_root) $taskWorkspace.Container
$taskAcorn=ContainedPath ([string]$taskGrant.acorn_root) $taskWorkspace.Container
if($taskPackage-cne(Join-Path $taskWorkspace.Container 'upstream/package-sources/typebox-static-authoring-20261016/typebox')-or$taskAcorn-cne(Join-Path $taskWorkspace.Container 'upstream/package-sources/typebox-static-authoring-20261016/acorn')){throw 'Only Root-released immutable source-only package copies are admitted'}
$taskStage=ContainedPath $OutputDirectory $taskWorkspace.evidence
$taskReceipt=ContainedPath $ReceiptBase $taskWorkspace.evidence
if($taskGrant.output_directory-cne$taskStage-or$taskGrant.receipt_base-cne$taskReceipt-or(Test-Path -LiteralPath $taskStage)-or@(Get-ChildItem -LiteralPath ([IO.Path]::GetDirectoryName($taskReceipt)) -Filter ([IO.Path]::GetFileName($taskReceipt)+'*')).Count){throw 'Fresh exact granted stage/receipt paths required'}
if(!(Test-Path -LiteralPath $taskPackage -PathType Container)-or!(Test-Path -LiteralPath $taskAcorn -PathType Container)){throw 'Root must release stable contained source package/Acorn copies first'}
. $taskOwner
$taskOriginal=Get-Content -LiteralPath $taskAuthority -Raw|ConvertFrom-Json
function SourceInventory($Rows,[string]$OldRoot,[string]$CurrentRoot,[int]$Count){
 if(@($Rows).Count-ne$Count){throw 'Complete original source inventory count required'}
 $prefix=[IO.Path]::GetFullPath($OldRoot)+[IO.Path]::DirectorySeparatorChar
 $mapped=@(foreach($row in $Rows){
  $historical=[IO.Path]::GetFullPath([string]$row.path)
  if(!$historical.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Original source row is outside its authority prefix'}
  $relative=$historical.Substring($prefix.Length).Replace('\','/')
  [ordered]@{relative=$relative;path=(Join-Path $CurrentRoot $relative);sha256=([string]$row.sha256).ToUpperInvariant();historical_path=[string]$row.path}
 })
 return @{root=$CurrentRoot;kind='tree';excluded=@();rows=$mapped}
}
$taskInventories=[ordered]@{
 candidate=(Get-CiInventory $taskRoot tree @('.git','.zig-cache','zig-out'))
 source_package=(SourceInventory $taskOriginal.original_package 'C:\Users\adyba\pi-upstream-runtime-19cb534-20261012\node_modules\typebox' $taskPackage 1385)
 acorn=(SourceInventory $taskOriginal.acorn_complete 'C:\Users\adyba\AppData\Roaming\npm\node_modules\wrangler\node_modules\acorn' $taskAcorn 10)
 node=(SourceInventory $taskOriginal.node_complete $taskNodeRoot $taskNodeRoot 1838)
}
$taskDescriptor="$taskReceipt-workspace.json"
[ordered]@{schema=1;mode='static_package_authoring';input_authority='source_package_only';runtime_restoration_claim=$false;container=$taskWorkspace.Container;candidate_root=$taskRoot;source_package_root=$taskPackage;output_directory=$taskStage;input_path=$taskInput;input_sha256='37CEEAC103C70BF1C587F03CAA11C5EE4EC0A6AE414222D8653116E94DB5C9AA';acorn_entry=(Join-Path $taskAcorn 'dist/acorn.mjs');acorn_entry_sha256='402F6759C744EA2CA501C1DC4DED8B1C54C9066CC7A741837057DCB68BC64C93'}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $taskDescriptor -Encoding utf8NoBOM
$taskControls=@(foreach($controlPath in @($RootGrant,$taskDescriptor,$taskAuthority,$taskCopyReceipt,$taskResolver,$taskLayout,$taskWorkspace.path_relocations,$taskOwner)){[ordered]@{path=[IO.Path]::GetFullPath($controlPath);sha256=(Get-FileHash -LiteralPath $controlPath -Algorithm SHA256).Hash}})
[ordered]@{input_authority='source_package_only';runtime_restoration_claim=$false;inventories=$taskInventories;controls=$taskControls}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath "$taskReceipt-frozen.json" -Encoding utf8NoBOM
$taskFrozenHash=(Get-FileHash -LiteralPath "$taskReceipt-frozen.json" -Algorithm SHA256).Hash
function VerifyPackageInputs([string]$Phase){
 $failures=@(
  foreach($name in $taskInventories.Keys){try{Assert-CiInventory $taskInventories[$name] "$taskReceipt-$Phase-$name.json"}catch{[ordered]@{name=$name;error=[string]$_}}}
  foreach($control in $taskControls){try{if((Get-FileHash -LiteralPath $control.path -Algorithm SHA256).Hash-cne$control.sha256){throw 'Control hash drift'}}catch{[ordered]@{name=$control.path;error=[string]$_}}}
  if((git -C $taskRoot rev-parse HEAD).Trim()-cne$taskHead-or@(git -C $taskRoot status --porcelain).Count){[ordered]@{name='candidate_identity';error='Head/clean-state drift'}}
  if((Get-FileHash -LiteralPath "$taskReceipt-frozen.json" -Algorithm SHA256).Hash-cne$taskFrozenHash){[ordered]@{name='frozen_registry';error='Registry hash drift'}}
 )
 [ordered]@{phase=$Phase;errors=$failures;runtime_restoration_claim=$false;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath "$taskReceipt-$Phase-summary.json" -Encoding utf8NoBOM
 if($failures.Count){throw "Package-authoring complete $Phase seal failed"}
}
function NativeProcesses {
 @(Get-CimInstance Win32_Process|Where-Object{
  $_.Name-in@('zig','zig.exe','build','build.exe','test','test.exe')-or($_.ExecutablePath-and([IO.Path]::GetFileName($_.ExecutablePath)-in@('zig','zig.exe','build','build.exe','test','test.exe')-or$_.ExecutablePath-match'[\\/](?:\.zig-cache|zig-out)[\\/]'))
 })
}
VerifyPackageInputs 'before'
$taskFree=[uint64](Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1KB
$taskNative=@(NativeProcesses)
$taskOutputs=@('reachable-closure.json','lowering-map.json','initialization-order.json','native_typebox_operators_production.zig')
[ordered]@{scope='static_package_authoring';candidate_head=$taskHead;root_grant=$taskGrant;runtime_restoration_claim=$false;free_bytes=$taskFree;minimum_free_bytes=16GB;other_native=@($taskNative|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine,CreationDate);deadline_seconds=60;heap_mib=256;settle_seconds=10;outputs=$taskOutputs}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath "$taskReceipt-admission.json" -Encoding utf8NoBOM
if($taskFree-lt16GB-or$taskNative.Count){throw 'Fresh16GiB/zero-native source-authoring admission rejected'}
[void](New-Item -ItemType Directory -Path $taskStage)
@($taskOutputs|ForEach-Object{[ordered]@{path=(Join-Path $taskStage $_);exists=$false}})|ConvertTo-Json -Depth 4|Set-Content -LiteralPath "$taskReceipt-output-before.json" -Encoding utf8NoBOM
$taskFailure=$null;$taskPostFailure=$null;$taskOwnedRecord=$null;$taskRemaining=@();$taskNativeAfter=@()
try{
 [void](Invoke-CiOwnedProcess (Join-Path $taskNodeRoot 'node.exe') @('--max-old-space-size=256',$taskGenerator,$taskStage,'--owned-start',$taskDescriptor) $taskRoot "$taskReceipt-owner" 60 ([Text.Encoding]::UTF8.GetBytes("TYPEBOX_STATIC_AUTHORING_OWNED_START`n")))
}catch{$taskFailure=[string]$_}finally{
 try{VerifyPackageInputs 'after'}catch{$taskPostFailure=[string]$_}
 if(Test-Path -LiteralPath "$taskReceipt-owner.json"){$taskOwnedRecord=Get-Content -LiteralPath "$taskReceipt-owner.json" -Raw|ConvertFrom-Json;$taskRemaining=@(Get-CimInstance Win32_Process -Filter "ProcessId = $($taskOwnedRecord.pid)")}
 $taskNativeAfter=@(NativeProcesses)
 [ordered]@{owner=$taskOwnedRecord;owner_pid_present=$taskRemaining.Count;remaining=@($taskRemaining|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine,CreationDate);global_native=@($taskNativeAfter|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine,CreationDate);observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath "$taskReceipt-absence.json" -Encoding utf8NoBOM
 $taskActualOutputs=Get-CiInventory $taskStage tree
 $taskActualOutputs|ConvertTo-Json -Depth 7|Set-Content -LiteralPath "$taskReceipt-output-after.json" -Encoding utf8NoBOM
 [ordered]@{process_failure=$taskFailure;postseal_failure=$taskPostFailure}|ConvertTo-Json|Set-Content -LiteralPath "$taskReceipt-errors.json" -Encoding utf8NoBOM
}
if($taskPostFailure){throw $taskPostFailure};if($taskRemaining.Count-or$taskNativeAfter.Count){throw 'Owned/global native absence required'};if($taskFailure){throw $taskFailure}
if(!$taskOwnedRecord-or$taskOwnedRecord.status-cne'passed'-or$taskOwnedRecord.exit_code-ne0){throw 'Actual owned terminal0 required'}
if(@(Compare-Object @($taskOutputs|Sort-Object) @($taskActualOutputs.rows.relative|Sort-Object) -CaseSensitive).Count){throw 'Exactly four fresh staged files required'}
$taskMap=Get-Content -LiteralPath (Join-Path $taskStage 'lowering-map.json') -Raw|ConvertFrom-Json
if(@($taskMap.functions).Count-ne1669-or@($taskMap.branches).Count-ne585-or$taskMap.tryHelpers-ne1-or$taskMap.callSetup.selectedCallbacks-ne24-or$taskMap.callSetup.identityFrozen-ne$true){throw 'Original callback/branch/try/scoped metadata drift'}
[ordered]@{status='static_package_authoring_terminal0_fullpost0';candidate_head=$taskHead;input_authority='source_package_only';runtime_restoration_claim=$false;owner=$taskOwnedRecord;outputs=$taskActualOutputs.rows;metadata=@{callbacks=1669;branches=585;tries=1;scoped_callbacks=24};product_intaken=$false;native_compiled=$false;native_executed=$false;source_observer_executed=$false;goldens_generated=$false}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath "$taskReceipt-validation.json" -Encoding utf8NoBOM
