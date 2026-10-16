param([Parameter(Mandatory)][string]$HistoricalPath,[string]$Container)
$ErrorActionPreference='Stop'
if(!$Container){$taskWorkspace=& (Join-Path $PSScriptRoot 'Resolve-PiZigWorkspace.ps1');$Container=$taskWorkspace.Container}
$Container=[IO.Path]::GetFullPath($Container).TrimEnd([IO.Path]::DirectorySeparatorChar)
$taskMap=Get-Content -LiteralPath (Join-Path $Container 'path-relocations.json') -Raw|ConvertFrom-Json
if($taskMap.schema -ne 1){throw 'Unsupported path-relocation schema'}
$taskOriginal=[IO.Path]::GetFullPath($HistoricalPath)
foreach($taskMapping in @($taskMap.mappings|Sort-Object {$_.old.Length} -Descending)){
    $taskOld=[IO.Path]::GetFullPath([string]$taskMapping.old)
    if($taskOriginal.Equals($taskOld,[StringComparison]::OrdinalIgnoreCase) -or $taskOriginal.StartsWith($taskOld+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
        $taskSuffix=$taskOriginal.Substring($taskOld.Length).TrimStart([IO.Path]::DirectorySeparatorChar)
        $taskNew=[IO.Path]::GetFullPath([string]$taskMapping.new)
        if(!$taskNew.StartsWith($Container+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Relocation target escapes its container'}
        $taskResolved=[IO.Path]::GetFullPath($(if($taskSuffix){Join-Path $taskNew $taskSuffix}else{$taskNew}))
        if(!$taskResolved.StartsWith($Container+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Resolved historical path escapes its container'}
        return $taskResolved
    }
}
# System executables and unrelated user inputs were not relocated.
$taskOriginal
