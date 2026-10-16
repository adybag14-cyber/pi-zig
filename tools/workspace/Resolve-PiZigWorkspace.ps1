param([string]$StartPath=$PSScriptRoot)
$ErrorActionPreference='Stop'
$taskDirectory=[IO.DirectoryInfo]::new([IO.Path]::GetFullPath($StartPath))
while($taskDirectory -and !(Test-Path -LiteralPath (Join-Path $taskDirectory.FullName '.pi-zig-workspace.json'))){$taskDirectory=$taskDirectory.Parent}
if(!$taskDirectory){throw 'Pi-zig project container metadata was not found'}
$taskContainer=$taskDirectory.FullName
$taskLayout=Get-Content -LiteralPath (Join-Path $taskContainer '.pi-zig-workspace.json') -Raw|ConvertFrom-Json
if($taskLayout.schema -ne 1){throw 'Unsupported Pi-zig workspace schema'}
$taskResult=[ordered]@{Container=$taskContainer;Layout=$taskLayout}
foreach($taskName in @('main','worktrees','upstream','upstream_repository','runtime','evidence','toolchain','zig','path_relocations')){
    $taskRelative=[string]$taskLayout.$taskName
    if(!$taskRelative -or [IO.Path]::IsPathRooted($taskRelative)){throw 'Workspace paths must be explicit relative locations'}
    $taskResolved=[IO.Path]::GetFullPath((Join-Path $taskContainer $taskRelative))
    if(!$taskResolved.StartsWith($taskContainer+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Workspace path escapes its container'}
    $taskResult[$taskName]=$taskResolved
}
[pscustomobject]$taskResult
