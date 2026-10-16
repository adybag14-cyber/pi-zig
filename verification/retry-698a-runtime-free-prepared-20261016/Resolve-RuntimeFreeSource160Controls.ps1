param([string]$RunId='ROOT-REVIEW-REQUIRED')
$ErrorActionPreference='Stop'
if($RunId -cnotmatch '^[A-Za-z0-9-]{1,70}$'){throw 'Contained run ID required'}
$taskDirectory=[IO.DirectoryInfo]::new([IO.Path]::GetFullPath($PSScriptRoot))
while($taskDirectory -and !(Test-Path -LiteralPath (Join-Path $taskDirectory.FullName '.pi-zig-workspace.json'))){$taskDirectory=$taskDirectory.Parent}
if(!$taskDirectory){throw 'Contained workspace required'}
$taskResolver=Join-Path $taskDirectory.FullName 'main/tools/workspace/Resolve-PiZigWorkspace.ps1'
$taskWorkspace=& $taskResolver -StartPath $PSScriptRoot
$taskSource=Join-Path $taskWorkspace.upstream 'snapshots/698a2d23-20261016'
$taskCandidate=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$taskCallerRoot=Join-Path $taskCandidate 'verification/retry-698a-successor-prepared-20261016'
$taskSourceFile=Join-Path $taskSource 'packages/ai/src/utils/retry.ts'
$taskText=Get-Content -LiteralPath $taskSourceFile -Raw
$taskImports=@([regex]::Matches($taskText,'(?m)^import[^\r\n]+')|ForEach-Object{$_.Value})
if($taskImports.Count -ne 1 -or $taskImports[0] -cne 'import type { AssistantMessage } from "../types.ts";' -or [regex]::IsMatch($taskText,'\b(?:require\s*\(|import\s*\()')){throw 'Runtime-free static Source closure changed'}
if((Get-FileHash -LiteralPath $taskSourceFile).Hash -cne 'D7ACFF8DC7F0EEE04ECB116A79FBB8331337D9F091A0CEEE775D623D7478D448'){throw 'Exact Source698 classifier bytes required'}
if(Test-Path -LiteralPath (Join-Path $taskSource 'node_modules')){throw 'No snapshot node_modules link permitted for this exception'}
$taskModuleFiles=@(
    (Join-Path $PSScriptRoot 'guarded-start-fence.mjs'),
    (Join-Path $taskCallerRoot 'capture-retry-698a.mjs'),
    (Join-Path $taskCallerRoot 'retry-698a-classifier.input.mjs'),
    $taskSourceFile
)|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}}
$taskSourceManifest=Join-Path $PSScriptRoot 'source698-full1970-manifest.json'
$taskNodeManifest=Join-Path $PSScriptRoot 'node1774-original-manifest.json'
$taskSourceRows=@(Get-Content -LiteralPath $taskSourceManifest -Raw|ConvertFrom-Json)
$taskNodeRows=@(Get-Content -LiteralPath $taskNodeManifest -Raw|ConvertFrom-Json)
if($taskSourceRows.Count -ne 1970 -or $taskNodeRows.Count -ne 1774){throw 'Complete Source1970/Node1774 reference manifests required'}
$taskNodeFullAuthority=Join-Path $taskWorkspace.evidence 'typebox-heap-scope-args-static-second49d-20261016-frozen.json'
$taskNodeFullAuthoritySha='35F1F2B0F12BF79C06B47AE2BA8C485EF10A7714BE3F129772E3BA1BBB97B927'
if((Get-FileHash -LiteralPath $taskNodeFullAuthority).Hash -cne $taskNodeFullAuthoritySha){throw 'Original complete Node authority changed'}
$taskNodeFullRows=@((Get-Content -LiteralPath $taskNodeFullAuthority -Raw|ConvertFrom-Json -Depth 80).node_complete)
if($taskNodeFullRows.Count -ne 1838){throw 'Complete original Node1838 authority required'}
$taskNodeFullMap=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($taskRow in $taskNodeFullRows){$taskNodeFullMap.Add([string]$taskRow.path,[string]$taskRow.sha256)}
foreach($taskRow in $taskNodeRows){if(!$taskNodeFullMap.ContainsKey([string]$taskRow.path) -or $taskNodeFullMap[[string]$taskRow.path] -cne [string]$taskRow.sha256){throw 'Original Node1774 must be exact subset of original Node1838'}}
$taskRun=Join-Path $taskWorkspace.evidence ('retry698a-runtime-free-captures/'+$RunId)
$taskConfig=[ordered]@{container=$taskWorkspace.Container;run=$taskRun;source_head='698a2d23b86a5045dd54554354a5e0cb7e466795';source_tree='495eca20433379a8cdd995e53c31278d72886c2b';classifier=$taskSourceFile;forbidden_runtime=$taskWorkspace.runtime;module_files=@($taskModuleFiles);nonce='ROOT-OWNED-FRESH-NONCE-REQUIRED'}
[pscustomobject][ordered]@{
    mode='SOURCE_ONLY_RUNTIME_FREE_EXCEPTION_PREPARATION';execution_authorized=$false;exception_granted=$false;global_runtime_status=$taskWorkspace.Layout.runtime_status;global_jobs_held=$taskWorkspace.Layout.all_agent_jobs_held_for_revalidation;
    workspace_resolver=$taskResolver;container=$taskWorkspace.Container;candidate=$taskCandidate;source=$taskSource;source_manifest=$taskSourceManifest;source_manifest_sha256=(Get-FileHash -LiteralPath $taskSourceManifest).Hash;source_files=1970;
    node='C:\Program Files\nodejs\node.exe';node_sha256='63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088';node_manifest=$taskNodeManifest;node_manifest_sha256=(Get-FileHash -LiteralPath $taskNodeManifest).Hash;node_files=1774;
    node_full_authority=$taskNodeFullAuthority;node_full_authority_sha256=$taskNodeFullAuthoritySha;node_full_authority_group='node_complete';node_full_files=1838;
    owner=(Join-Path $PSScriptRoot 'Invoke-OwnedModelsClassSource-20261016.ps1');owner_sha256='96BEA0CF8E17535C322EE4F36C0115387386F16988BC2B98465BD070A504F5E5';config_template=$taskConfig;
    driver=(Join-Path $taskCallerRoot 'capture-retry-698a.mjs');source_argument=$taskSource;output=(Join-Path $taskRun 'source160-raw.json');cases=160;runtime_dependencies=0;third_party_loader=$false;node_started=$false
}
