$ErrorActionPreference='Stop'
$taskContainer='C:\Users\adyba\pi-zig'
$taskTree=Join-Path $taskContainer 'worktrees/semver'
$taskRun='root-crypto58-fixed-20261016-235900'
$taskInner=Join-Path $taskContainer ('evidence/crypto-sha256-original58/'+$taskRun)
$taskOuter=Join-Path $PSScriptRoot $taskRun
$taskOutput=Join-Path $taskOuter 'independent-acceptance.json'
if(Test-Path -LiteralPath $taskOutput){throw 'Refuse acceptance overwrite'}
$taskChecks=[ordered]@{}
function Assert-Audit([string]$Name,[bool]$Pass){$taskChecks[$Name]=$Pass;if(!$Pass){throw ('Independent audit failed: '+$Name)}}
function Read-Audit([string]$Path){Get-Content -Raw -LiteralPath $Path|ConvertFrom-Json}
function Hash-Audit([string]$Path){(Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash}
$taskControlPath=Join-Path $taskTree 'verification/node-crypto-sha256-package-sourceonly-20261016'
$taskParser=Join-Path $taskControlPath 'Read-Original58Capture.ps1'
Assert-Audit 'strict_parser_identity' ((Hash-Audit $taskParser) -ceq 'DA1C59A9088EFF7CD919F211FB3AFC28579E863A7FFEF5B37A47FA70F9D38E38')
. $taskParser
$taskOwner=Read-Audit (Join-Path $taskInner 'owner.json')
$taskResult=Read-Audit (Join-Path $taskInner 'result.json')
$taskOuterResult=Read-Audit (Join-Path $taskOuter 'outer.json')
$taskControls=Read-Audit (Join-Path $taskControlPath 'source-only-controls.json')
$taskRawPath=Join-Path $taskInner 'owner.stdout.bin'
$taskRaw=Read-CryptoOriginal58 ([IO.File]::ReadAllBytes($taskRawPath)) $taskOwner ([string[]]$taskControls.case_ids) 'A9722654D1FCF6B3F00638B59F9D4EAA829549CC996EE7BE36808E24D7E2DA26'
Assert-Audit 'raw_identity' ((Hash-Audit $taskRawPath) -ceq '5062712D48821C749D5D9E416A9DC1CB6A7F15748AB5F64F9D2DC17AB3481074')
Assert-Audit 'strict_schema_framing_58_ordered_unique_ids' (@($taskRaw.rows).Count -eq 58 -and @($taskControls.case_ids|Select-Object -Unique).Count -eq 58)
Assert-Audit 'builtin_fenced_no_network_module_attempts' ($taskRaw.capture.stdinFence -and $taskRaw.capture.builtinOnly -and !$taskRaw.capture.deletedRuntimeUsed -and @($taskRaw.capture.networkAttempts).Count -eq 0 -and @($taskRaw.capture.moduleAttempts).Count -eq 0)
Assert-Audit 'node_terminal0_empty_stderr' ($taskOwner.pid -eq 2612 -and $taskOwner.status -ceq 'passed' -and $taskOwner.exit_code -eq 0 -and (Get-Item -LiteralPath (Join-Path $taskInner 'owner.stderr.log')).Length -eq 0)
Assert-Audit 'inner_terminal_fullpost_nativezero' ($taskResult.status -ceq 'captured_pending_independent_audit' -and $taskResult.postseal -and $taskResult.owned_absent -and !$taskResult.expected_created -and @($taskResult.failures).Count -eq 0 -and $taskResult.final_native_census.census_count -gt 0 -and $taskResult.native_roots_after -eq 0)
Assert-Audit 'outer_terminal0_originals_descendants_absent' ($taskOuterResult.pid -eq 81980 -and $taskOuterResult.runner_exit_code -eq 0 -and $taskOuterResult.status -ceq 'runner_terminal0_pending_audit' -and $taskOuterResult.absence_state -ceq 'verified_originals_absent' -and $taskOuterResult.runner_absent -and $taskOuterResult.node_absent -and $taskOuterResult.descendants_absent -and @($taskOuterResult.rejections).Count -eq 0)
Assert-Audit 'kernel_cim_agreement' (@($taskOuterResult.identity_captures).Count -eq 1 -and $taskOuterResult.identity_captures[0].status -ceq 'agreed' -and $taskOuterResult.identity_captures[0].kernel_microsecond_ticks -eq $taskOuterResult.identity_captures[0].cim_microsecond_ticks -and $taskOuterResult.identity_captures[0].retained_handle -eq $taskOuterResult.retained_handle)
Assert-Audit 'independent_kernel_cim_absence_receipts' (@($taskOuterResult.absence_captures).Count -eq 2 -and @($taskOuterResult.absence_captures|Where-Object{!$_.absent -or !$_.kernel_absent -or !$_.cim_absent -or @($_.cim_rows).Count}).Count -eq 0)
Assert-Audit 'nonempty_complete_descendant_censuses' (@($taskOuterResult.child_snapshots).Count -eq 2 -and @($taskOuterResult.child_snapshots|Where-Object{$_.status -cne 'captured' -or $_.census_count -le 0 -or @($_.descendants).Count -or @($_.direct_children).Count -or @($_.node_hints).Count -or @($_.incomplete_ancestry_rows).Count}).Count -eq 0)
Assert-Audit '300_inner_900_outer_bounds' ($taskOwner.timeout_seconds -eq 300 -and (([DateTimeOffset]$taskOwner.completed_utc)-([DateTimeOffset]$taskOwner.created_utc)).TotalSeconds -lt 300 -and $taskOuterResult.total_monotonic_seconds -eq 900 -and $taskOuterResult.execution_wait_seconds -eq 810 -and $taskOuterResult.shared_cleanup_reserve_seconds -eq 90 -and $taskOuterResult.settlement_seconds_per_stage_cap -eq 10 -and $taskOuterResult.monotonic_elapsed_ms -lt 900000)
$taskSafe=@('SystemRoot','WINDIR','ComSpec','PATH','PATHEXT','PSModulePath','TEMP','TMP','HOME','USERPROFILE','HOMEDRIVE','HOMEPATH','APPDATA','LOCALAPPDATA','NO_COLOR','POWERSHELL_TELEMETRY_OPTOUT','POWERSHELL_UPDATECHECK')
$taskSafeUpper=@($taskSafe|ForEach-Object{$_.ToUpperInvariant()}|Sort-Object -CaseSensitive)
foreach($taskName in @('post-reset','pre-node')){
 $taskNames=@(Read-Audit (Join-Path $taskInner ($taskName+'-environment-names.json')))
 Assert-Audit ($taskName+'_exact_17_names') ($taskNames.Count -eq 17 -and @(Compare-Object $taskSafeUpper @($taskNames|ForEach-Object{$_.ToUpperInvariant()}|Sort-Object -CaseSensitive) -CaseSensitive).Count -eq 0)
}
Assert-Audit 'node_exact_20_names' (@($taskRaw.capture.environmentNames).Count -eq 20 -and @(Compare-Object @($taskSafeUpper+@('NODE_OPTIONS','NODE_PATH','NODE_COMPILE_CACHE')|Sort-Object -CaseSensitive) @($taskRaw.capture.environmentNames|ForEach-Object{$_.ToUpperInvariant()}|Sort-Object -CaseSensitive) -CaseSensitive).Count -eq 0)
$taskBefore=Read-Audit (Join-Path $taskInner 'before.json')
$taskFinal=Read-Audit (Join-Path $taskInner 'final.json')
Assert-Audit 'before_final_bytes_identical' ((Hash-Audit (Join-Path $taskInner 'before.json')) -ceq (Hash-Audit (Join-Path $taskInner 'final.json')))
Assert-Audit 'sealed_exact_source_controls' ($taskBefore.candidate_head -ceq 'c64aa31cb8726b9da66afea2c76aed34f626a402' -and $taskBefore.expected_absent -and $taskBefore.files.Count -eq 20 -and @($taskBefore.files|Where-Object{(Hash-Audit $_.path) -cne $_.sha256}).Count -eq 0)
$taskNodeRoot='C:\Program Files\nodejs'
$taskCurrentNode=@(Get-ChildItem -LiteralPath $taskNodeRoot -File -Recurse -Force|ForEach-Object{[IO.Path]::GetRelativePath($taskNodeRoot,$_.FullName).Replace([char]92,[char]47)+' '+(Hash-Audit $_.FullName)}|Sort-Object -CaseSensitive)
$taskOriginalNode=@((Read-Audit (Join-Path $taskContainer 'evidence/typebox-heap-scope-args-static-second49d-20261016-frozen.json')).node_complete|ForEach-Object{[IO.Path]::GetRelativePath($taskNodeRoot,$_.path).Replace([char]92,[char]47)+' '+$_.sha256.ToUpperInvariant()}|Sort-Object -CaseSensitive)
$taskOriginalSubset=@(Read-Audit (Join-Path $taskContainer 'evidence/source4954-node-tools-before-20261015.json')|ForEach-Object{[IO.Path]::GetRelativePath($taskNodeRoot,$_.path).Replace([char]92,[char]47)+' '+$_.sha256.ToUpperInvariant()}|Sort-Object -CaseSensitive)
Assert-Audit 'complete_original_node1838_inventory_hashes' ($taskCurrentNode.Count -eq 1838 -and $taskBefore.node1838.Count -eq 1838 -and @(Compare-Object $taskOriginalNode $taskBefore.node1838 -CaseSensitive).Count -eq 0 -and @(Compare-Object $taskCurrentNode $taskBefore.node1838 -CaseSensitive).Count -eq 0)
Assert-Audit 'original_node1774_subset_inventory_hashes' ($taskBefore.node1774.Count -eq 1774 -and @(Compare-Object $taskOriginalSubset $taskBefore.node1774 -CaseSensitive).Count -eq 0)
Assert-Audit 'source_outer_pins_exact' ($taskResult.launcher_sha256 -ceq 'D29070CD3D8C0D3723FDC231732DBADC49590FF289DF1059AC7D8FBB3073F8E1' -and (Hash-Audit (Join-Path $PSScriptRoot 'Invoke-Crypto58Outer-EnvironmentRemoval.ps1')) -ceq '0607F7148B52DFEFB74A79A9FEB9FF9426E11B9E9DCF11F4DB3D90DB30343F4F' -and $taskOuterResult.helper_sha256 -ceq '0607F7148B52DFEFB74A79A9FEB9FF9426E11B9E9DCF11F4DB3D90DB30343F4F')
Assert-Audit 'fresh_admission16gib_nativezero' ($taskResult.initial_admission.free_kib -ge 16777216 -and $taskResult.pre_node_admission.free_kib -ge 16777216 -and $taskResult.initial_admission.native_census.census_count -gt 0 -and $taskResult.pre_node_admission.native_census.census_count -gt 0 -and $taskResult.initial_admission.native_census.candidate_count -eq 0 -and $taskResult.pre_node_admission.native_census.candidate_count -eq 0)
$taskGrantPath=Join-Path $PSScriptRoot ($taskRun+'-grant.json')
$taskGrant=Read-Audit $taskGrantPath
Assert-Audit 'exact_grant_fresh_at_launch' ($taskGrant.authorized -and $taskGrant.builtin_only_no_deleted_runtime -and $taskGrant.manual_fresh_16gib -and $taskGrant.candidate_head -ceq $taskResult.candidate_head -and $taskGrant.run_id -ceq $taskRun -and $taskGrant.launcher_sha256 -ceq $taskResult.launcher_sha256 -and (Hash-Audit $taskGrantPath) -ceq $taskOuterResult.root_grant_sha256 -and ([DateTimeOffset]$taskGrant.issued_utc) -lt ([DateTimeOffset]$taskOwner.created_utc) -and ([DateTimeOffset]$taskGrant.expires_utc) -gt ([DateTimeOffset]$taskOwner.created_utc) -and (([DateTimeOffset]$taskOwner.created_utc)-([DateTimeOffset]$taskGrant.issued_utc)).TotalSeconds -lt 300)
$taskNegativeManifest=Read-Audit (Join-Path $taskControlPath 'environment-removal-sourceonly.json')
Assert-Audit 'both_historical_negatives_preserved_15_hashes' ($taskNegativeManifest.negative_raw_files.Count -eq 15 -and @($taskNegativeManifest.negative_raw_files|Where-Object{(Hash-Audit $_.path) -cne $_.sha256}).Count -eq 0)
Assert-Audit 'expected_still_absent' (!(Test-Path -LiteralPath (Join-Path $taskTree 'src/extensions/fixtures/node-crypto-sha256-package.json')))
$taskArtifacts=@(Get-ChildItem -LiteralPath $taskInner -File)+@(Get-Item -LiteralPath (Join-Path $taskOuter 'outer.json'))
$taskReceipt=[ordered]@{status='accepted_original_builtin_crypto58_capture';reviewer='/root/body_validation_resume';run_id=$taskRun;audited_utc=[DateTimeOffset]::UtcNow.ToString('o');source_head=$taskResult.candidate_head;raw_sha256=(Hash-Audit $taskRawPath);input_sha256=$taskRaw.inputSha256;rows=58;node_pid=2612;runner_pid=81980;checks=$taskChecks;artifacts=@($taskArtifacts|ForEach-Object{@{path=$_.FullName;sha256=(Hash-Audit $_.FullName)}});scope='Actual original Windows Node24.14 builtin crypto observations only; no restored runtime, native implementation parity, full node:crypto or whole Pi qualification';new_node_zig_native_jobs_started=$false;expected_created=$false;historical_negatives_modified=$false}
$taskReceipt|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $taskOutput -Encoding utf8NoBOM
@{receipt=$taskOutput;sha256=(Hash-Audit $taskOutput);checks=$taskChecks.Count;status=$taskReceipt.status}|ConvertTo-Json
