param([string]$PacketRoot=$PSScriptRoot,[string]$ExpectedManifestSha256='')
$ErrorActionPreference='Stop'
$taskRoot=[IO.Path]::GetFullPath($PacketRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
$taskManifestPath=Join-Path $taskRoot 'packet-manifest.json'
$taskManifestHash=(Get-FileHash -LiteralPath $taskManifestPath).Hash
if($ExpectedManifestSha256 -and $taskManifestHash -cne $ExpectedManifestSha256){throw 'Packet manifest hash mismatch'}
$taskManifest=Get-Content -Raw -LiteralPath $taskManifestPath|ConvertFrom-Json
foreach($taskEntry in $taskManifest.entries){
 $taskPath=[IO.Path]::GetFullPath((Join-Path $taskRoot $taskEntry.relative))
 if(!$taskPath.StartsWith($taskRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Packet path escapes root'}
 if(!(Test-Path -LiteralPath $taskPath -PathType Leaf) -or (Get-FileHash -LiteralPath $taskPath).Hash -cne $taskEntry.sha256){throw "Packet payload mismatch $($taskEntry.relative)"}
}
$taskPrefix='oauth-codex-radius-browser-ae7-source7-resumed-second-20261015'
$taskOwner=Get-Content -Raw -LiteralPath (Join-Path $taskRoot "$taskPrefix.json")|ConvertFrom-Json
$taskPost=Get-Content -Raw -LiteralPath (Join-Path $taskRoot "$taskPrefix-posthash.json")|ConvertFrom-Json
$taskSource=Get-Content -Raw -LiteralPath (Join-Path $taskRoot "$taskPrefix-output.json")|ConvertFrom-Json
$taskCleanup=Get-Content -Raw -LiteralPath (Join-Path $taskRoot "$taskPrefix-independent-cleanup.json")|ConvertFrom-Json
if($taskOwner.status -cne 'passed' -or $taskOwner.exit_code -ne 0 -or !$taskOwner.independent_pid_absent -or !$taskOwner.terminal_kernel_handle -or $taskOwner.executable_sha256 -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Original Source terminal identity failed'}
if($taskPost.candidate_files -ne 6602 -or $taskPost.candidate_drift.Count -or $taskPost.candidate_inventory_drift.Count -or $taskPost.extra_control_drift.Count -or $taskPost.absent_dependency_drift.Count -or $taskPost.historical_absence_records -ne 84 -or $taskPost.control_manifest_drift -or $taskPost.candidate_head_drift -or $taskPost.source_head_drift -or !$taskPost.expected_still_absent -or $taskPost.owner_failure){throw 'Original full posthash failed'}
foreach($taskSpec in @(@{name='source';count=1968},@{name='dependencies';count=31064},@{name='node_tools';count=1774})){
 $taskHashes=$taskPost.manifests|Where-Object name -ceq $taskSpec.name
 $taskPaths=$taskPost.path_inventories|Where-Object name -ceq $taskSpec.name
 if($taskHashes.files -ne $taskSpec.count -or $taskHashes.drift -ne 0 -or $taskPaths.count -ne $taskSpec.count -or $taskPaths.drift.Count){throw "Original inventory posthash failed $($taskSpec.name)"}
}
if($taskSource.sourceHead -cne 'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d' -or $taskSource.runtime -cne 'v24.14.0' -or $taskSource.count -ne 7 -or $taskSource.rows.Count -ne 7 -or $taskSource.listeners.Count -ne 7 -or @($taskSource.listeners|Where-Object {$_.pid -ne $taskOwner.pid -or !$_.actualServer}).Count){throw 'Original seven-row Source/listener authority failed'}
if($taskSource.ownedSockets.accepted -ne 2 -or $taskSource.ownedSockets.closed -ne 2 -or $taskSource.ownedSockets.remaining -ne 0 -or !$taskCleanup.sourcePidAbsent -or $taskCleanup.listeningCount -ne 0){throw 'Owned callback cleanup failed'}
if(@($taskSource.rawEvents|Where-Object type -ceq 'auth_url').Count -ne 7 -or $taskSource.rawDiagnostics.Count -ne 3 -or @($taskSource.rawDiagnostics|Where-Object {-not $_.stack}).Count){throw 'Original raw effect/diagnostic inventory failed'}
$taskExpectedPath=Join-Path $taskRoot 'oauth-codex-radius-browser-ae7-source.json'
if((Get-FileHash -LiteralPath $taskExpectedPath).Hash -cne 'B94EFF93E5F1BF05F708C435EDD0A64629E82505411EA958250364531BF20B3F' -or (Get-FileHash -LiteralPath (Join-Path $taskRoot 'source35-preserved-expected.json')).Hash -cne '085F6A4C5CC6AF456BC2FBBEB71365A527EE111CDE4794A837D3541B22E12495'){throw 'Expected fixture bytes changed'}
$taskExpected=Get-Content -Raw -LiteralPath $taskExpectedPath|ConvertFrom-Json
if(($taskExpected|ConvertTo-Json -Depth 100 -Compress) -cne ($taskSource.rows|ConvertTo-Json -Depth 100 -Compress)){throw 'Published expected differs from genuine Source rows'}
@{status='passed';manifest_sha256=$taskManifestHash;payloads=@($taskManifest.entries).Count;source_cases=7;candidate_files=6602;raw_urls=7;raw_error_stacks=3;owned_listeners=7;owned_sockets_remaining=0;native_qualified=$false;full_pi_qualified=$false}|ConvertTo-Json -Depth 6
