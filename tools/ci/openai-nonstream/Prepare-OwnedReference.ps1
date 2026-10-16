param()
$ErrorActionPreference='Stop'
$taskDirectory=[IO.DirectoryInfo]::new($PSScriptRoot)
while($taskDirectory -and !(Test-Path -LiteralPath (Join-Path $taskDirectory.FullName '.pi-zig-workspace.json'))){$taskDirectory=$taskDirectory.Parent}
if(!$taskDirectory){throw 'Pi-zig container metadata not found'}
$taskLayout=Get-Content -LiteralPath (Join-Path $taskDirectory.FullName '.pi-zig-workspace.json') -Raw|ConvertFrom-Json
$taskResolver=Join-Path (Join-Path $taskDirectory.FullName $taskLayout.main) 'tools/workspace/Resolve-PiZigWorkspace.ps1'
$taskWorkspace=& $taskResolver -StartPath $PSScriptRoot
$taskDriver=Join-Path $PSScriptRoot 'capture-primary-nonstream.mjs'
# This returns prospective paths only. It launches no Node/native process and
# supplies neither an admission grant nor a runtime-recovery qualification.
[pscustomobject]@{
    Status='prepared_only_no_launch'
    Container=$taskWorkspace.Container
    Runtime=$taskWorkspace.runtime
    RuntimeStatus=$taskWorkspace.Layout.runtime_status
    Evidence=$taskWorkspace.evidence
    Driver=$taskDriver
    SharedCallers=Join-Path $PSScriptRoot 'primary-nonstream-callers.mjs'
    DriverArguments=@($taskWorkspace.runtime,'<owned-output-path-under-evidence>')
    RequiresRootGrant=$true
    RequiresOriginalRuntimeManifest31064=$true
    RequiresFullPrePostControlsAndAbsences=$true
}
