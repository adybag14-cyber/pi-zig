param(
 [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$CandidateHead,
 [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9-]{1,60}$')][string]$RunId,
 [Parameter(Mandatory)][string]$RootGrant
)
# Thin Root pure9 successor: one direct Node process, unchanged CI607 owner.
$ErrorActionPreference='Stop'
$taskRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$taskDirectory=[IO.DirectoryInfo]::new($taskRoot)
while($taskDirectory -and !(Test-Path -LiteralPath (Join-Path $taskDirectory.FullName '.pi-zig-workspace.json'))){$taskDirectory=$taskDirectory.Parent}
if(!$taskDirectory){throw 'Pi-zig container metadata missing'}
$taskResolver=Join-Path $taskDirectory.FullName 'main/tools/workspace/Resolve-PiZigWorkspace.ps1'
$taskWorkspace=& $taskResolver -StartPath $taskRoot
$taskOwner=Join-Path $taskWorkspace.main 'tools/ci/native_qualification_ci.ps1'
$taskAuthority=Join-Path $taskWorkspace.evidence 'typebox-heap-scope-args-static-second49d-20261016-frozen.json'
$taskSubsetAuthority=Join-Path $taskWorkspace.evidence 'source4954-node-tools-before-20261015.json'
$taskProof=Join-Path $taskWorkspace.evidence ('crypto-sha256-original58/'+$RunId)
$taskNodeRoot='C:\Program Files\nodejs'
$taskNode=Join-Path $taskNodeRoot 'node.exe'
$taskGit='C:\Program Files\Git\cmd\git.exe'
$taskPwsh='C:\Program Files\PowerShell\7\pwsh.exe'
$taskDriver=Join-Path $PSScriptRoot 'capture-original.mjs'
$taskInput=Join-Path $taskRoot 'src/extensions/fixtures/node-crypto-sha256-package.input.txt'
$taskModule=Join-Path $taskRoot 'src/extensions/native_node_crypto_hash.zig'
$taskExpected=Join-Path $taskRoot 'src/extensions/fixtures/node-crypto-sha256-package.json'
$taskControls=Join-Path $PSScriptRoot 'source-only-controls.json'
$taskParser=Join-Path $PSScriptRoot 'Read-Original58Capture.ps1'
$taskClassifier=Join-Path $PSScriptRoot 'Get-ModelsNativeCandidates.ps1'
$taskLauncherSha=(Get-FileHash -LiteralPath $PSCommandPath).Hash
# Environment reset is permitted only in a dedicated pwsh -File invocation of
# this exact runner. Dot-sourcing/interactive/-Command/Codex hosts are rejected.
$taskArgv=[Environment]::GetCommandLineArgs()
$taskFileSlots=@(for($taskIndex=0;$taskIndex -lt $taskArgv.Length;$taskIndex++){if($taskArgv[$taskIndex] -ieq '-File'){$taskIndex}})
if($taskFileSlots.Count -ne 1 -or $taskFileSlots[0]+1 -ge $taskArgv.Length -or [IO.Path]::GetFullPath($taskArgv[$taskFileSlots[0]+1]) -ine [IO.Path]::GetFullPath($PSCommandPath) -or @($taskArgv|Where-Object {$_ -iin @('-Command','-CommandWithArgs','-EncodedCommand')}).Count){throw 'Dedicated exact pwsh -File intent required before environment reset'}
$taskSelf=Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -OperationTimeoutSec 3
if(!$taskSelf -or $taskSelf.ExecutablePath -ine $taskPwsh -or !$taskSelf.CommandLine -or !$taskSelf.CreationDate -or $taskSelf.ExecutablePath -match 'codex'){throw 'Dedicated runner live identity unavailable'}
$taskRunnerIdentity=@{pid=$PID;executable=$taskSelf.ExecutablePath;created_utc=([DateTimeOffset]$taskSelf.CreationDate).ToUniversalTime().ToString('o');command_line=$taskSelf.CommandLine}
$taskGrantPath=[IO.Path]::GetFullPath($RootGrant)
if(!$taskGrantPath.StartsWith($taskWorkspace.evidence+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Root metadata grant must be inside evidence'}
$taskGrant=Get-Content -LiteralPath $taskGrantPath -Raw|ConvertFrom-Json
if(@($taskGrant.PSObject.Properties.Name|Where-Object {$_ -cnotin @('authorized','builtin_only_no_deleted_runtime','manual_fresh_16gib','candidate_head','run_id','launcher_sha256','issued_utc','expires_utc','grant_id')}).Count){throw 'Root grant may contain metadata fields only'}
$taskNow=[DateTimeOffset]::UtcNow
if($taskGrant.authorized -isnot [bool] -or !$taskGrant.authorized -or $taskGrant.builtin_only_no_deleted_runtime -isnot [bool] -or !$taskGrant.builtin_only_no_deleted_runtime -or $taskGrant.manual_fresh_16gib -isnot [bool] -or !$taskGrant.manual_fresh_16gib -or $taskGrant.candidate_head -cne $CandidateHead -or $taskGrant.run_id -cne $RunId -or $taskGrant.launcher_sha256 -cne $taskLauncherSha -or ([DateTimeOffset]$taskGrant.issued_utc) -gt $taskNow -or ($taskNow-([DateTimeOffset]$taskGrant.issued_utc)).TotalSeconds -gt 300 -or ([DateTimeOffset]$taskGrant.expires_utc) -le $taskNow){throw 'Exact fresh standalone original58 Root grant required'}
if(Test-Path -LiteralPath $taskProof){throw 'Refuse owned capture replay'}
foreach($taskParent in @($taskWorkspace.evidence,(Split-Path -Parent $taskProof))){if((Test-Path -LiteralPath $taskParent) -and ((Get-Item -LiteralPath $taskParent -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Owned evidence parent may not be linked'}}
if((Get-FileHash -LiteralPath $taskOwner).Hash -cne '607BEDBB91FE318D214CD2C3B9C83D80437335C0062C320C0EACB3A745B38285'){throw 'Canonical CI607 owner changed'}
. $taskOwner
. $taskParser
if((Get-FileHash -LiteralPath $taskClassifier).Hash -cne '3413A2A50B4D4C3BFF8709E4EE08C76BE449AAB1EDCB1E0C5C167DC7A804E301'){throw 'Reviewed native census classifier changed'}
. $taskClassifier
function Get-CryptoNativeCensus {
 $taskRows=@(Get-CimInstance Win32_Process -OperationTimeoutSec 3 -ErrorAction Stop)
 if(!$taskRows.Count){throw 'Nonempty successful native admission census required'}
 $taskCandidates=@(Get-ModelsNativeCandidates -Rows $taskRows -Container $taskWorkspace.Container)
 return @{census_count=$taskRows.Count;candidates=$taskCandidates;candidate_count=$taskCandidates.Count;utc=[DateTimeOffset]::UtcNow.ToString('o')}
}
function Assert-CryptoAdmission {
 $taskOs=Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 3 -ErrorAction Stop
 $taskCensus=Get-CryptoNativeCensus
 if($taskCensus.candidate_count -or !$taskOs -or $taskOs.FreePhysicalMemory -lt 16777216){throw 'Fresh16GiB and native-zero from nonempty classified census required; preserve unrelated jobs'}
 return @{free_kib=$taskOs.FreePhysicalMemory;native_roots=0;native_census=$taskCensus;light_reserved_kib=2097152;heap_mb=256;utc=[DateTimeOffset]::UtcNow.ToString('o')}
}
function Node-Row($Row){
 $taskRelative=[IO.Path]::GetRelativePath($taskNodeRoot,[IO.Path]::GetFullPath($Row.path)).Replace([char]92,[char]47)
 if($taskRelative -eq '..' -or $taskRelative.StartsWith('../',[StringComparison]::Ordinal)){throw 'Node authority path escapes original install'}
 return $taskRelative+' '+([string]$Row.sha256).ToUpperInvariant()
}
function Get-CryptoSeal([string]$Label){
 $taskHead=([string](& $taskGit -C $taskRoot rev-parse HEAD)).Trim()
 if($LASTEXITCODE -ne 0 -or $taskHead -cne $CandidateHead){throw 'Exact candidate head required'}
 if(@(& $taskGit -C $taskRoot status --porcelain).Count -or $LASTEXITCODE -ne 0){throw 'Clean candidate required'}
 if((Get-FileHash -LiteralPath $taskAuthority).Hash -cne '35F1F2B0F12BF79C06B47AE2BA8C485EF10A7714BE3F129772E3BA1BBB97B927' -or (Get-FileHash -LiteralPath $taskSubsetAuthority).Hash -cne 'F834312AAC6AC8D79EF4B49CCB806096D80E92FCA403CC650A05E901D4C280DD'){throw 'Original Node1838/1774 authority changed'}
 $taskOriginal=@((Get-Content -LiteralPath $taskAuthority -Raw|ConvertFrom-Json).node_complete)
 $taskSubset=@(Get-Content -LiteralPath $taskSubsetAuthority -Raw|ConvertFrom-Json)
 if($taskOriginal.Count -ne 1838 -or $taskSubset.Count -ne 1774){throw 'Exact original authority inventories required'}
 $taskInventory=Get-CiInventory $taskNodeRoot
 $taskActual=@($taskInventory.rows|ForEach-Object {Node-Row $_}|Sort-Object -CaseSensitive)
 $taskOriginalRows=@($taskOriginal|ForEach-Object {Node-Row $_}|Sort-Object -CaseSensitive)
 $taskActualSubset=@($taskInventory.rows|Where-Object {$taskName=$_.relative.Replace([char]92,[char]47);$taskName -ceq 'node.exe' -or $taskName.StartsWith('node_modules/npm/',[StringComparison]::Ordinal)}|ForEach-Object {Node-Row $_}|Sort-Object -CaseSensitive)
 $taskSubsetRows=@($taskSubset|ForEach-Object {Node-Row $_}|Sort-Object -CaseSensitive)
 if($taskActual.Count -ne 1838 -or $taskActualSubset.Count -ne 1774 -or @(Compare-Object $taskOriginalRows $taskActual -CaseSensitive).Count -or @(Compare-Object $taskSubsetRows $taskActualSubset -CaseSensitive).Count){throw 'Complete original Node1838 or retained1774 subset hash/inventory drift'}
 if((Get-FileHash -LiteralPath $taskModule).Hash -cne '91FBAD6661EE2345F64E5F3166A27C6C0870278DEA5072E2DA79CF70F34C7487' -or (Get-FileHash -LiteralPath $taskInput).Hash -cne 'A9722654D1FCF6B3F00638B59F9D4EAA829549CC996EE7BE36808E24D7E2DA26'){throw 'Immutable crypto module/original58 input changed'}
 $taskPaths=@($taskDriver,$taskInput,$taskModule,$taskControls,$taskParser,$taskClassifier,(Join-Path $PSScriptRoot 'Test-ModelsNativeAdmission.ps1'),$PSCommandPath,$taskOwner,$taskAuthority,$taskSubsetAuthority,$taskGrantPath,$taskResolver,(Join-Path $taskWorkspace.Container '.pi-zig-workspace.json'),$taskWorkspace.path_relocations,$taskGit,$taskPwsh,(Join-Path $PSScriptRoot 'STANDALONE-CAPTURE.md'),(Join-Path $PSScriptRoot 'parser-duplicate-property.negative.txt'),(Join-Path $PSScriptRoot 'parser-trailing-object.negative.txt'))
 $taskSeal=[ordered]@{candidate_head=$taskHead;scope='Standalone actual node:crypto builtin only; complete original Node1838 and unchanged1774 subset; no deleted runtime or Source package dependency';files=@($taskPaths|ForEach-Object {@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}});node1838=$taskActual;node1774=$taskActualSubset;expected_absent=!(Test-Path -LiteralPath $taskExpected)}
 $taskSeal|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskProof ($Label+'.json')) -Encoding utf8NoBOM
 if(!$taskSeal.expected_absent){throw 'Expected must remain absent until independent capture acceptance'}
 return $taskSeal
}
$taskInitialAdmission=Assert-CryptoAdmission
[void][IO.Directory]::CreateDirectory($taskProof)
foreach($taskName in @('profile','temp')){[void][IO.Directory]::CreateDirectory((Join-Path $taskProof $taskName))}
$taskSafe=@{SystemRoot='C:\Windows';WINDIR='C:\Windows';ComSpec='C:\Windows\System32\cmd.exe';PATH='C:\Windows\System32;C:\Windows;C:\Program Files\Git\cmd';PATHEXT='.EXE';PSModulePath='C:\Program Files\PowerShell\7\Modules;C:\Windows\System32\WindowsPowerShell\v1.0\Modules';TEMP=(Join-Path $taskProof 'temp');TMP=(Join-Path $taskProof 'temp');HOME=(Join-Path $taskProof 'profile');USERPROFILE=(Join-Path $taskProof 'profile');HOMEDRIVE='C:';HOMEPATH=((Join-Path $taskProof 'profile').Substring(2));APPDATA=(Join-Path $taskProof 'profile');LOCALAPPDATA=(Join-Path $taskProof 'profile');NO_COLOR='1';POWERSHELL_TELEMETRY_OPTOUT='1';POWERSHELL_UPDATECHECK='Off'}
# Only names are enumerated. No inherited credential values are read or logged.
foreach($taskName in @([Environment]::GetEnvironmentVariables('Process').Keys)){[Environment]::SetEnvironmentVariable($taskName,[NullString]::Value,'Process')}
foreach($taskName in $taskSafe.Keys){[Environment]::SetEnvironmentVariable($taskName,[string]$taskSafe[$taskName],'Process')}
$taskRecords=[ordered]@{status='running';candidate_head=$CandidateHead;launcher_sha256=$taskLauncherSha;runner_identity=$taskRunnerIdentity;initial_admission=$taskInitialAdmission;node_launch_requested=$false;postseal=$false;owned_absent=$false;expected_created=$false;deleted_runtime_used=$false;independent_capture_acceptance=$false;failures=@()}
$taskBefore=$null
try{
 # The first work after rebuilding the dedicated runner environment is a
 # names-only exact-set check. Typed null above removes each inherited entry.
 $taskRecords.post_reset_environment_names=@([Environment]::GetEnvironmentVariables('Process').Keys|ForEach-Object {[string]$_}|Sort-Object -CaseSensitive)
 ConvertTo-Json -InputObject $taskRecords.post_reset_environment_names|Set-Content -LiteralPath (Join-Path $taskProof 'post-reset-environment-names.json') -Encoding utf8NoBOM
 $taskSafeEnvironmentNames=@($taskSafe.Keys|ForEach-Object {([string]$_).ToUpperInvariant()}|Sort-Object -CaseSensitive)
 if(@(Compare-Object $taskSafeEnvironmentNames @($taskRecords.post_reset_environment_names|ForEach-Object {$_.ToUpperInvariant()}|Sort-Object -CaseSensitive) -CaseSensitive).Count){throw 'Exact sanitized runner environment names differ immediately after reset'}
 $taskBefore=Get-CryptoSeal 'before'
 $taskPolicy=Get-Content -LiteralPath $taskControls -Raw|ConvertFrom-Json
 if($taskPolicy.count -ne 58 -or @($taskPolicy.case_ids).Count -ne 58 -or @($taskPolicy.case_ids|Select-Object -Unique).Count -ne 58){throw 'Immutable original58 ordered IDs required'}
 $taskRecords.pre_node_admission=Assert-CryptoAdmission
 $taskArguments=@('--max-old-space-size=256','--permission',('--allow-fs-read='+$taskNodeRoot),('--allow-fs-read='+$taskDriver),('--allow-fs-read='+$taskInput),('--allow-fs-read='+$taskControls),$taskDriver,'--owned-original58')
 if([DateTimeOffset]::UtcNow -ge ([DateTimeOffset]$taskGrant.expires_utc) -or ([DateTimeOffset]::UtcNow-([DateTimeOffset]$taskGrant.issued_utc)).TotalSeconds -gt 300){throw 'Root grant expired before actual Node launch'}
 $taskRecords.node_launch_requested=$true
 # Diagnostic names only, after admission and grant checks, before CI607 adds
 # its three empty Node control variables. Never serialize environment values.
 $taskRecords.pre_node_environment_names=@([Environment]::GetEnvironmentVariables('Process').Keys|ForEach-Object {[string]$_}|Sort-Object -CaseSensitive)
 ConvertTo-Json -InputObject $taskRecords.pre_node_environment_names|Set-Content -LiteralPath (Join-Path $taskProof 'pre-node-environment-names.json') -Encoding utf8NoBOM
 if(@(Compare-Object $taskSafeEnvironmentNames @($taskRecords.pre_node_environment_names|ForEach-Object {$_.ToUpperInvariant()}|Sort-Object -CaseSensitive) -CaseSensitive).Count){throw 'Exact sanitized runner environment names differ before Node launch'}
 $null=Invoke-CiOwnedProcess $taskNode $taskArguments $taskProof (Join-Path $taskProof 'owner') 300 ([Text.Encoding]::UTF8.GetBytes("CRYPTO_SHA256_ORIGINAL58_OWNED_START`n"))
 $taskOwned=Get-Content -LiteralPath (Join-Path $taskProof 'owner.json') -Raw|ConvertFrom-Json
 if($taskOwned.status -cne 'passed' -or $taskOwned.exit_code -ne 0 -or $taskOwned.executable_sha256 -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Actual original Node terminal0 required'}
 if((Get-Item -LiteralPath (Join-Path $taskProof 'owner.stderr.log')).Length -ne 0){throw 'Empty original Node stderr required'}
 $taskBytes=[IO.File]::ReadAllBytes((Join-Path $taskProof 'owner.stdout.bin'))
 $taskCapture=Read-CryptoOriginal58 $taskBytes $taskOwned @($taskPolicy.case_ids) $taskPolicy.input_sha256
 $taskExpectedNames=@($taskSafe.Keys)+@('NODE_OPTIONS','NODE_PATH','NODE_COMPILE_CACHE')|ForEach-Object {([string]$_).ToUpperInvariant()}|Sort-Object
 $taskActualNames=@($taskCapture.capture.environmentNames|ForEach-Object {([string]$_).ToUpperInvariant()}|Sort-Object)
 if(@(Compare-Object $taskExpectedNames $taskActualNames -CaseSensitive).Count){throw 'Exact sanitized child environment names differ'}
 $taskRecords.cases=58;$taskRecords.raw_sha256=(Get-FileHash -LiteralPath (Join-Path $taskProof 'owner.stdout.bin')).Hash
 $taskRecords.status='captured_pending_independent_audit'
}catch{$taskRecords.status='negative';$taskRecords.failures+=@($_.Exception.Message)}
finally{
 try{
  $taskAfter=Get-CryptoSeal 'final'
  if(!$taskBefore -or ($taskBefore|ConvertTo-Json -Depth 6 -Compress) -cne ($taskAfter|ConvertTo-Json -Depth 6 -Compress)){throw 'Complete pre/post input seal differs'}
  $taskRecords.postseal=$true
 }catch{$taskRecords.status='negative';$taskRecords.failures+=@('Final seal: '+$_.Exception.Message);@{complete=$false;error=$_.Exception.Message}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskProof 'final-seal-negative.json') -Encoding utf8NoBOM}
 try{
  if(Test-Path -LiteralPath (Join-Path $taskProof 'owner.json')){
   $taskOwned=Get-Content -LiteralPath (Join-Path $taskProof 'owner.json') -Raw|ConvertFrom-Json
   $taskLive=@(Get-CimInstance Win32_Process -Filter "ProcessId=$($taskOwned.pid)" -OperationTimeoutSec 3)
   $taskRecords.owned_absent=($taskLive.Count -eq 0)
   $taskRecords.node_identity=$taskOwned
  }
  $taskFinalCensus=Get-CryptoNativeCensus
  $taskRecords.final_native_census=$taskFinalCensus
  $taskRecords.native_roots_after=$taskFinalCensus.candidate_count
  if(!$taskRecords.owned_absent -or $taskRecords.native_roots_after){throw 'Independent owned PID absence/native-zero failed'}
 }catch{$taskRecords.status='negative';$taskRecords.failures+=@('Owned absence: '+$_.Exception.Message)}
 $taskRecords.expected_created=Test-Path -LiteralPath $taskExpected
 if($taskRecords.expected_created){$taskRecords.status='negative';$taskRecords.failures+=@('Expected appeared before independent audit')}
 $taskRecords.outer_handoff='Independent supervisor must confirm this runner identity absent after process exit'
 $taskRecords.completed_utc=[DateTimeOffset]::UtcNow.ToString('o')
 $taskRecords|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskProof 'result.json') -Encoding utf8NoBOM
}
$taskRecords|ConvertTo-Json -Depth 8
if($taskRecords.status -cne 'captured_pending_independent_audit'){throw 'Standalone original58 capture negative; preserve complete evidence'}
