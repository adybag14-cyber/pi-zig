param([string]$CandidateRoot=(Join-Path $PSScriptRoot '../..'),[string]$MappedReferenceOutput)
$ErrorActionPreference='Stop'
# Bootstrap only locates the central resolver. All project paths come from it.
$taskDirectory=[IO.DirectoryInfo]::new([IO.Path]::GetFullPath($PSScriptRoot))
while($taskDirectory -and !(Test-Path -LiteralPath (Join-Path $taskDirectory.FullName '.pi-zig-workspace.json'))){$taskDirectory=$taskDirectory.Parent}
if(!$taskDirectory){throw 'Contained pi-zig workspace required'}
$taskCentral=Join-Path $taskDirectory.FullName 'main/tools/workspace'
$taskWorkspaceResolver=Join-Path $taskCentral 'Resolve-PiZigWorkspace.ps1'
$taskHistoricalResolver=Join-Path $taskCentral 'Resolve-PiZigHistoricalPath.ps1'
$taskWorkspace=& $taskWorkspaceResolver -StartPath $PSScriptRoot
$taskCandidate=[IO.Path]::GetFullPath($CandidateRoot)
if(!$taskCandidate.StartsWith($taskWorkspace.worktrees+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'An assigned contained candidate is required; Root main is not an agent target'}
$taskPlan=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'native-replay-plan.json') -Raw|ConvertFrom-Json
if($taskPlan.source_head -cne $taskWorkspace.Layout.integration_upstream_commit){throw 'Reviewed Source authority mismatch'}
$taskRoots=@(
    @{kind='source';old='C:\Users\adyba\pi-upstream-source-4dd2b149-20261016';required=$taskWorkspace.upstream_repository},
    @{kind='runtime';old='C:\Users\adyba\pi-upstream-runtime-19cb534-20261012';required=$taskWorkspace.runtime},
    @{kind='compiler';old='C:\Users\adyba\pi-zig-toolchain-20261003';required=$taskWorkspace.toolchain}
)
foreach($taskRoot in $taskRoots){
    $taskRoot.current=& $taskHistoricalResolver -HistoricalPath $taskRoot.old -Container $taskWorkspace.Container
    if($taskRoot.current -ine $taskRoot.required){throw 'Historical explicit root mapping differs from central workspace layout'}
}
function Resolve-OriginalRow($Row,[string]$Kind){
    if(!$Row -or !$Row.path -or [string]$Row.sha256 -cnotmatch '^[A-Fa-f0-9]{64}$'){throw 'Original reference row shape missing'}
    $taskOriginal=[IO.Path]::GetFullPath([string]$Row.path)
    if($Kind -eq 'node'){
        if(!$taskOriginal.StartsWith('C:\Program Files\nodejs\',[StringComparison]::OrdinalIgnoreCase)){throw 'Unrelocated Node system authority outside explicit allowed distribution'}
        return [ordered]@{historical_path=$taskOriginal;resolved_path=$taskOriginal;sha256=$Row.sha256;location='unchanged_system_node_distribution'}
    }
    $taskMapping=$taskRoots|Where-Object kind -ceq $Kind|Select-Object -First 1
    if(!$taskMapping -or !$taskOriginal.StartsWith($taskMapping.old+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Reference path has no explicit expected historical root mapping'}
    $taskMapped=[IO.Path]::GetFullPath((Join-Path $taskMapping.current $taskOriginal.Substring($taskMapping.old.Length).TrimStart('\')))
    if(!$taskMapped.StartsWith($taskWorkspace.Container+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Resolved project reference escaped container'}
    return [ordered]@{historical_path=$taskOriginal;resolved_path=$taskMapped;sha256=$Row.sha256;location='explicit_historical_relocation';mapping_old_root=$taskMapping.old;mapping_new_root=$taskMapping.current}
}
$taskAcceptedBefore=Join-Path $taskCandidate 'verification/latest-upstream-4dd2-20261016/google146-qualified-source-proof/root-accb-google146-20261016/full-before.json'
$taskOriginal=Get-Content -LiteralPath $taskAcceptedBefore -Raw|ConvertFrom-Json
$taskMappedGroups=[Collections.Generic.List[object]]::new()
foreach($taskKind in @('source','runtime','node','compiler')){
    $taskGroup=$taskOriginal.groups|Where-Object name -ceq $taskKind|Select-Object -First 1
    if(!$taskGroup -or @($taskGroup.rows).Count -ne $taskPlan.reference_inventories.$taskKind){throw 'Complete accepted original reference census mismatch'}
    $taskRows=@(foreach($taskRow in $taskGroup.rows){Resolve-OriginalRow $taskRow $taskKind})
    $taskMappedGroups.Add([ordered]@{name=$taskKind;count=$taskRows.Count;rows=$taskRows})
}
$taskAbsences=@(foreach($taskAbsent in $taskOriginal.absences){
    $taskRuntime=Resolve-OriginalRow @{path=$taskAbsent.runtime;sha256=('0'*64)} 'runtime'
    $taskSource=Resolve-OriginalRow @{path=$taskAbsent.source;sha256=('0'*64)} 'source'
    [ordered]@{relative=$taskAbsent.relative;historical_runtime=$taskAbsent.runtime;historical_source=$taskAbsent.source;runtime=$taskRuntime.resolved_path;source=$taskSource.resolved_path}
})
if($taskAbsences.Count -ne 84){throw 'All84 explicit original absences required'}
$taskGates=@(foreach($taskGate in $taskPlan.gates){
    $taskCaller=Join-Path $taskCandidate $taskGate.caller;$taskExpected=Join-Path $taskCandidate $taskGate.expected
    if((Get-FileHash -LiteralPath $taskCaller).Hash -cne $taskGate.caller_sha256 -or (Get-FileHash -LiteralPath $taskExpected).Hash -cne $taskGate.expected_sha256){throw 'Accepted caller/expected bytes changed'}
    [ordered]@{id=$taskGate.id;observations=$taskGate.observations;compile_target=$taskGate.compile_target;replay_target=$taskGate.replay_target;caller=$taskCaller;expected=$taskExpected;caller_sha256=$taskGate.caller_sha256;expected_sha256=$taskGate.expected_sha256;required_named_tests=$taskGate.required_named_tests;compiled_metadata_discovered=$false;compile_arguments=@('build',$taskGate.compile_target,'-Doptimize=Debug','-j1','--test-timeout','120s','--summary','all')}
})
$taskRuntimeHeld=([string]$taskWorkspace.Layout.runtime_status -ceq 'recovery_pending')
$taskHeld=($taskWorkspace.Layout.all_agent_jobs_held_for_revalidation -eq $true)
$taskResult=[ordered]@{
    mode='SOURCE_ONLY_CONTROL_PREPARATION_NOT_EXECUTION';container=$taskWorkspace.Container;candidate=$taskCandidate;root_main=$taskWorkspace.main;root_base=$taskPlan.root_base;upstream=$taskWorkspace.upstream_repository;source_head=$taskPlan.source_head;
    zig=$taskWorkspace.zig;zig_sha256=$taskPlan.zig_sha256;runtime=$taskWorkspace.runtime;runtime_status=$taskWorkspace.Layout.runtime_status;runtime_authority_usable=$false;jobs_held=$taskHeld;
    workspace_resolver=$taskWorkspaceResolver;historical_resolver=$taskHistoricalResolver;relocation_map=$taskWorkspace.path_relocations;relocation_map_sha256=(Get-FileHash -LiteralPath $taskWorkspace.path_relocations).Hash;
    original_reference_manifest=$taskAcceptedBefore;original_reference_manifest_sha256=(Get-FileHash -LiteralPath $taskAcceptedBefore).Hash;
    groups=$taskMappedGroups.ToArray();absences=$taskAbsences;gates=$taskGates;owner=(Join-Path $PSScriptRoot $taskPlan.owner_file);owner_sha256=$taskPlan.owner_sha256;
    execution_authorized=$false;qualification_transferred=$false;runtime_recovery_blocker=$taskRuntimeHeld;historical_reference_bytes_modified=$false
}
if($MappedReferenceOutput){
    $taskOutput=[IO.Path]::GetFullPath($MappedReferenceOutput)
    if(!$taskOutput.StartsWith($taskWorkspace.evidence+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Derived control output must stay in contained evidence'}
    if(Test-Path -LiteralPath $taskOutput){throw 'Refuse derived control overwrite'}
    ConvertTo-Json -InputObject $taskResult -Depth 18|Set-Content -LiteralPath $taskOutput -Encoding utf8NoBOM
}
[pscustomobject]$taskResult
