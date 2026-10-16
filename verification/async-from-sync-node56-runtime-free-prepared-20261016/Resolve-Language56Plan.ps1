param([string]$RunId='ROOT-REVIEW-REQUIRED')
$ErrorActionPreference='Stop'
if($RunId -cnotmatch '^[A-Za-z0-9-]{1,70}$'){throw 'Contained fresh run ID required'}
$taskDirectory=[IO.DirectoryInfo]::new($PSScriptRoot)
while($taskDirectory -and !(Test-Path -LiteralPath (Join-Path $taskDirectory.FullName '.pi-zig-workspace.json'))){$taskDirectory=$taskDirectory.Parent}
if(!$taskDirectory){throw 'Contained workspace metadata missing'}
$taskResolver=Join-Path $taskDirectory.FullName 'main/tools/workspace/Resolve-PiZigWorkspace.ps1'
$taskWorkspace=& $taskResolver -StartPath $PSScriptRoot
$taskIds=@(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'ordered-source56-case-ids.json') -Raw|ConvertFrom-Json)
$taskNodeManifest=Join-Path $PSScriptRoot 'node1774-original-manifest.json'
if($taskIds.Count -ne 56 -or @($taskIds|Select-Object -Unique).Count -ne 56 -or @(Get-Content -LiteralPath $taskNodeManifest -Raw|ConvertFrom-Json).Count -ne 1774){throw 'Exact56 IDs and complete originalNode1774 manifest required'}
$taskRun=Join-Path $taskWorkspace.evidence ('async-from-sync-language56-captures/'+$RunId)
$taskSnapshot=Join-Path $taskRun 'snapshot'
$taskModules=@(foreach($taskName in @('guarded-language56-start-fence.mjs','capture-language56.mjs','language-consumer.mjs','for-await-callers.mjs')){
    $taskPath=Join-Path $PSScriptRoot $taskName
    [ordered]@{name=$taskName;source_path=$taskPath;path=(Join-Path $taskSnapshot $taskName);sha256=(Get-FileHash -LiteralPath $taskPath).Hash}
})
# Prospective paths/data only: no directory creation, admission or process launch.
[pscustomobject][ordered]@{
    status='SOURCE_ONLY_PLAN_NOT_EXECUTABLE_ADMISSION';execution_authorized=$false;controller_specialization_reviewed=$false
    workspace_resolver=$taskResolver;container=$taskWorkspace.Container;candidate=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    global_jobs_held=$taskWorkspace.Layout.all_agent_jobs_held_for_revalidation;global_runtime_status=$taskWorkspace.Layout.runtime_status
    node='C:\Program Files\nodejs\node.exe';node_sha256='63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088';node_version='v24.14.0'
    node_manifest=$taskNodeManifest;node_manifest_sha256=(Get-FileHash -LiteralPath $taskNodeManifest).Hash;node_files=1774
    run=$taskRun;snapshot=$taskSnapshot;modules=$taskModules;cases=56;source_packet='6c7781c2c05d5dcfc80cd36fd9b70a5aa5312fb3'
    source160_design='7b2762dd16aa92ac4fcc6ea29c321fc8bdfdd5d9';owner_sha256='96BEA0CF8E17535C322EE4F36C0115387386F16988BC2B98465BD070A504F5E5'
    config_template=[ordered]@{scope='runtime-free-language56-only';container=$taskWorkspace.Container;run=$taskRun;snapshot=$taskSnapshot;source_head='6c7781c2c05d5dcfc80cd36fd9b70a5aa5312fb3';subject=(Join-Path $taskSnapshot 'language-consumer.mjs');forbidden_runtime=$taskWorkspace.runtime;expected_cases=56;expected_case_ids=$taskIds;node_sha256='63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088';module_files=$taskModules;nonce='ROOT-FRESH-OWNED-NONCE-REQUIRED'}
    runtime_manifest_required=$false;runtime_absences_claimed=$false;npm_dependency_imports=0;source160_grant_reused=$false
}
