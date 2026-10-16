param()
$ErrorActionPreference='Stop'
$taskDirectory=[IO.DirectoryInfo]::new([IO.Path]::GetFullPath($PSScriptRoot))
while($taskDirectory -and !(Test-Path -LiteralPath (Join-Path $taskDirectory.FullName '.pi-zig-workspace.json'))){$taskDirectory=$taskDirectory.Parent}
if(!$taskDirectory){throw 'Contained Pi-zig workspace was not found'}
$taskContainer=$taskDirectory.FullName
$taskResolver=Join-Path $taskContainer 'main/tools/workspace/Resolve-PiZigWorkspace.ps1'
$taskHistorical=Join-Path $taskContainer 'main/tools/workspace/Resolve-PiZigHistoricalPath.ps1'
$taskWorkspace=& $taskResolver -StartPath $PSScriptRoot
function Resolve-Historical([string]$Path){& $taskHistorical -HistoricalPath $Path -Container $taskContainer}
$taskGraph=Resolve-Historical 'C:\Users\adyba\pi-zig-private-module-graph-phase1-20261016'
$taskAdapter=Resolve-Historical 'C:\Users\adyba\pi-zig-engine-extension-import-adapter-20261016'
$taskSdk=Resolve-Historical 'C:\Users\adyba\pi-zig-sdk-default-real-assembly-20261016'
$taskSource4954=Resolve-Historical 'C:\Users\adyba\pi-upstream-source-4954d76-20261015'
$taskSource0fb=Resolve-Historical 'C:\Users\adyba\pi-upstream-source-0fbdbd3-20261016'
foreach($taskResolved in @($taskGraph,$taskAdapter,$taskSdk,$taskSource4954,$taskSource0fb)){
    if(!([IO.Path]::GetFullPath($taskResolved)).StartsWith($taskContainer+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Relocated project input escapes container'}
}
$taskExpected=@(
    @{root=$taskGraph;path='vendor/quickjs/quickjs.c';sha='15CB5267575DA7A6EB6DB7A952E81D9C21777C0D0DE5DECAA666C51612F52A50'},
    @{root=$taskGraph;path='vendor/quickjs/quickjs.h';sha='9E734ED5B17A977128888A8BF3192D9987FCCB897829560E9812F8DB04800784'},
    @{root=$taskGraph;path='src/native_private_module_graph_test.zig';sha='12B113FC8E8F64753F6EE340551B1539B7E75293B2A34D1C4FCE4BF6535BFC2D'},
    @{root=$taskAdapter;path='src/extensions/native_extension_import_adapter.zig';sha='AEA85D372A462FDB8A7934AE2A133CEFA24339733ED77224F5B3A9B0B08BF6B9'},
    @{root=$taskAdapter;path='src/native_engine_extension_import_adapter_controls.zig';sha='410941D251E88F38E6C9D619FF6EA9C00134B6153C18062263BD8D3B8918390E'},
    @{root=$taskSdk;path='src/extensions/native_sdk_package_transport.zig';sha='0D0F0FFD6C44842E065E4D1CC3FEE708C15C2F7D62EFAB24544F6B7DA90E15EE'},
    @{root=$taskSdk;path='src/extensions/fixtures/sdk-model-dependencies-4954.expected.json';sha='2809D24B7150E1F14CCA82F1522AD1906943DF2A5202C49572FBC20167BC3E8C'},
    @{root=$taskSdk;path='src/extensions/fixtures/sdk-runtime-helpers-4954.expected.json';sha='94AEC310834B683D9F70D2F50498C84CFFF03D4EB9E8C5EC18674DC0569663C3'},
    @{root=$taskSdk;path='src/extensions/fixtures/sdk-async-brand-4954.expected.json';sha='D0B06269EC1B29C9C8A679DB3E73305820FB0BD0667C9B288C0961EB4D80D2E5'},
    @{root=$taskSdk;path='src/extensions/fixtures/sdk-loader-inputs-4954.expected.json';sha='14EEBD914A04DCBCBCEF24CD8D4509CB22A61FC2C18FB305B81ADE0E25C5DA00'},
    @{root=$taskSdk;path='src/extensions/fixtures/sdk-module-policy-4954.expected.json';sha='0DDCAB7DC649CBA5AC7147C722CE0AB98C9465E9B74290F57CD92C1A1FE89F27'}
)
$taskRecords=foreach($taskItem in $taskExpected){
    $taskPath=[IO.Path]::GetFullPath((Join-Path $taskItem.root $taskItem.path))
    if(!$taskPath.StartsWith($taskContainer+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Prospective input escapes container'}
    $taskHash=(Get-FileHash -LiteralPath $taskPath -Algorithm SHA256).Hash
    if(!$taskHash.Equals($taskItem.sha,[StringComparison]::OrdinalIgnoreCase)){throw ('Prospective input changed: '+$taskPath)}
    [ordered]@{path=$taskPath;sha256=$taskHash;bytes=(Get-Item -LiteralPath $taskPath).Length}
}
[pscustomobject][ordered]@{
    status='prospective_relocated_inputs_only_not_an_execution_seal'
    container=$taskContainer
    workspace_metadata_sha256=(Get-FileHash -LiteralPath (Join-Path $taskContainer '.pi-zig-workspace.json') -Algorithm SHA256).Hash
    relocation_map_sha256=(Get-FileHash -LiteralPath $taskWorkspace.path_relocations -Algorithm SHA256).Hash
    workspace_resolver_sha256=(Get-FileHash -LiteralPath $taskResolver -Algorithm SHA256).Hash
    historical_resolver_sha256=(Get-FileHash -LiteralPath $taskHistorical -Algorithm SHA256).Hash
    graph2=$taskGraph
    adapter=$taskAdapter
    sdk_assembly=$taskSdk
    source4954=$taskSource4954
    source0fb=$taskSource0fb
    integration_source=$taskWorkspace.upstream_repository
    runtime=$taskWorkspace.runtime
    runtime_status=$taskWorkspace.Layout.runtime_status
    runtime_usable_authority=$false
    runtime_required_original_files=31064
    runtime_workspace_links_and_absences_required=$true
    zig=$taskWorkspace.zig
    zig_required_sha256=$taskWorkspace.Layout.zig_sha256
    evidence=$taskWorkspace.evidence
    proposed_physical_directory=(Join-Path $taskWorkspace.evidence 'extension-import-relocated-native-prospective-20261016/physical')
    historical_proofs_rewritten=$false
    full_candidate_manifests_sealed=$false
    independent_ownership_grant=$false
    native_or_node_launch_available=$false
    inputs=@($taskRecords)
}
