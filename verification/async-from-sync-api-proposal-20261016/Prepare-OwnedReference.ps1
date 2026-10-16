param()
$ErrorActionPreference='Stop'
$taskDirectory=[IO.DirectoryInfo]::new($PSScriptRoot)
while($taskDirectory -and !(Test-Path -LiteralPath (Join-Path $taskDirectory.FullName '.pi-zig-workspace.json'))){$taskDirectory=$taskDirectory.Parent}
if(!$taskDirectory){throw 'Contained workspace metadata missing'}
$taskLayout=Get-Content -LiteralPath (Join-Path $taskDirectory.FullName '.pi-zig-workspace.json') -Raw|ConvertFrom-Json
$taskWorkspace=& (Join-Path (Join-Path $taskDirectory.FullName $taskLayout.main) 'tools/workspace/Resolve-PiZigWorkspace.ps1') -StartPath $PSScriptRoot
# Read-only preparation. No reference/native process is launched here.
[pscustomobject]@{
    Status='proposal_only_no_launch_no_composition'
    Container=$taskWorkspace.Container
    Evidence=$taskWorkspace.evidence
    PinnedZig=$taskWorkspace.zig
    Driver=Join-Path $PSScriptRoot 'capture-language-reference.mjs'
    DriverArguments=@('<owned-output-path-under-evidence>')
    NodeVersion='v24.14.0'
    SDKRuntimeDependency=$false
    RequiresSpecificRootResourceGrant=$true
    RequiresFullOwnerSealsAndAbsences=$true
    TlaPeerReviewAndCompositionPending=$true
}
