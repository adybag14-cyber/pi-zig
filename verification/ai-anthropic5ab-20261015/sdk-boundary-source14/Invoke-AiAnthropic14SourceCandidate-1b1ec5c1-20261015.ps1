$ErrorActionPreference='Stop'
$taskTree='C:/Users/adyba/pi-zig-ai-anthropic-bedrock-20261015'
$taskHead='1b1ec5c1'
$taskEvidence=$PSScriptRoot
$taskName='ai-anthropic14-sdk-boundaries-5ab-source14-first-20261015'
$taskWrapper=Join-Path $taskEvidence 'Run-AiAnthropic14SdkBoundariesSource-20261015.ps1'
if((git -C $taskTree rev-parse --short=8 HEAD) -cne $taskHead -or @(git -C $taskTree status --porcelain).Count){throw 'Source14 candidate must be clean exact head'}
if((Get-FileHash -LiteralPath $taskWrapper).Hash -cne 'F05171ED98464568DBC432EF6FA0A1AEB0899148D306F4299743334AA153F8E0'){throw 'Granted Source14 wrapper changed'}
$taskFiles=@(git -C $taskTree ls-files)
$taskRows=@($taskFiles|ForEach-Object{$taskPath=Join-Path $taskTree $_;@{path=$taskPath;sha256=(Get-FileHash -LiteralPath $taskPath).Hash}})
$taskRows+=@{path=$PSCommandPath;sha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash}
$taskManifest=Join-Path $taskEvidence "$taskName-candidate-caller-before.json"
$taskRows|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskManifest -Encoding utf8NoBOM
$taskManifestHash=(Get-FileHash -LiteralPath $taskManifest).Hash
$taskFailed=$null
try{& $taskWrapper -Attempt first;if($LASTEXITCODE -and $LASTEXITCODE -ne 0){throw "Source14 inner exit $LASTEXITCODE"}}catch{$taskFailed=$_}
finally{
 $taskChanged=@($taskRows|Where-Object{!(Test-Path -LiteralPath $_.path -PathType Leaf) -or (Get-FileHash -LiteralPath $_.path).Hash -cne $_.sha256}|ForEach-Object path)
 $taskCurrent=@(git -C $taskTree ls-files)
 $taskInventoryChanged=@(Compare-Object $taskFiles $taskCurrent)
 $taskHeadChanged=(git -C $taskTree rev-parse --short=8 HEAD) -cne $taskHead
 $taskDirty=@(git -C $taskTree status --porcelain)
 @{candidate=$taskHead;files=$taskFiles.Count;candidate_and_caller_records=$taskRows.Count;changed=$taskChanged;inventory_changed=$taskInventoryChanged;head_changed=$taskHeadChanged;dirty=$taskDirty;manifest_changed=(Get-FileHash -LiteralPath $taskManifest).Hash -cne $taskManifestHash;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-candidate-caller-posthash.json") -Encoding utf8NoBOM
 if($taskChanged.Count -or $taskInventoryChanged.Count -or $taskHeadChanged -or $taskDirty.Count -or (Get-FileHash -LiteralPath $taskManifest).Hash -cne $taskManifestHash){throw 'Source14 candidate/caller full posthash drift'}
}
if($taskFailed){throw $taskFailed}
