param([string]$Container)
$ErrorActionPreference='Stop'
# Prospective metadata only. This script contains no process-launch, Node,
# compiler, source-generator, cleanup or historical-receipt rewrite operation.
if(!$Container){
    $taskDirectory=[IO.DirectoryInfo]::new($PSScriptRoot)
    while($taskDirectory -and !(Test-Path -LiteralPath (Join-Path $taskDirectory.FullName '.pi-zig-workspace.json'))){$taskDirectory=$taskDirectory.Parent}
    if(!$taskDirectory){throw 'Contained Pi-zig workspace is required'}
    $Container=$taskDirectory.FullName
}
$taskResolver=Join-Path $Container 'main/tools/workspace/Resolve-PiZigWorkspace.ps1'
$taskWorkspace=& $taskResolver -StartPath $PSScriptRoot
$taskHistoricalResolver=Join-Path $taskWorkspace.main 'tools/workspace/Resolve-PiZigHistoricalPath.ps1'
$taskCandidate=Join-Path $taskWorkspace.worktrees 'streams'
if(![IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).Equals([IO.Path]::GetFullPath($taskCandidate),[StringComparison]::OrdinalIgnoreCase)){throw 'Use only the assigned contained stream worktree'}
$taskHistorical=@(
    'C:/Users/adyba/pi-zig-update-evidence-20261003/Invoke-Env15-OwnedJob-Slot2-20261015.ps1',
    'C:/Users/adyba/pi-zig-update-evidence-20261003/Invoke-Env15-OwnedJob-Slot5-20261016.ps1',
    'C:/Users/adyba/pi-zig-update-evidence-20261003/web-body-node24-source-first-20261015-node-builtin-authorities.json'
)
$taskReferences=@(foreach($taskOld in $taskHistorical){
    $taskResolved=& $taskHistoricalResolver -HistoricalPath $taskOld -Container $taskWorkspace.Container
    if(!(Test-Path -LiteralPath $taskResolved -PathType Leaf)){throw "Resolved immutable reference is absent: $taskOld"}
    [ordered]@{historical_path=$taskOld;resolved_path=$taskResolved;sha256=(Get-FileHash -LiteralPath $taskResolved).Hash;historical_bytes_rewritten=$false}
})
[pscustomobject][ordered]@{
    schema='pi-zig-contained-stream-prospective-controls-v1'
    container=$taskWorkspace.Container
    candidate=$taskCandidate
    main=$taskWorkspace.main
    source=$taskWorkspace.upstream_repository
    integration_source_head=$taskWorkspace.Layout.integration_upstream_commit
    evidence=$taskWorkspace.evidence
    runtime=$taskWorkspace.runtime
    runtime_status=$taskWorkspace.Layout.runtime_status
    compiler=$taskWorkspace.zig
    compiler_version_required='0.16.0'
    compiler_sha256_required=$taskWorkspace.Layout.zig_sha256
    workspace_resolver=$taskResolver
    historical_path_resolver=$taskHistoricalResolver
    source20_runner=(Join-Path $taskCandidate 'tools/capture_node_stream_classic_source20.mjs')
    source14_runner=(Join-Path $taskCandidate 'tools/capture_node_stream_classic_iterator_source14.mjs')
    writer_source8_runner=(Join-Path $taskCandidate 'tools/capture_node_fs_write_stream_source8.mjs')
    writer_windows_crt_selected=$false
    child_windows_output_scheduler_selected=$false
    immutable_references=$taskReferences
    root_grant=$false
    source_grant=$false
    canonical_checks_released=$false
    native_minimum_available_gib=16
    source_minimum_available_gib=2
    source_node_version_required='v24.14.0'
    source_node_heap_mib=256
    compiler_jobs=1
    compile_outer_seconds=1320
    runtime_outer_seconds=300
    test_seconds=120
    host_await_seconds=10
    settle_seconds=10
    maximum_coordinated_roots=4
    expected_packets_manufactured=$false
    historical_receipts_rewritten=$false
    relocation_is_execution=$false
    launch_allowed=$false
    reason='Prospective paths resolved from contained workspace. Runtime recovery, complete original inventories, explicit absences, Root resource ownership and fresh full pre/post seals must be accepted before any future execution.'
}
