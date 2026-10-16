$ErrorActionPreference='Stop'
$taskContainer='C:\Users\adyba\pi-zig'
$taskManifest=Join-Path $taskContainer 'evidence\typebox-heap-scope-args-static-second49d-20261016-frozen.json'
$taskAuthorityHash='35F1F2B0F12BF79C06B47AE2BA8C485EF10A7714BE3F129772E3BA1BBB97B927'
$taskDestination=Join-Path $taskContainer 'upstream\package-sources\typebox-static-authoring-20261016'
if(Test-Path -LiteralPath $taskDestination){throw 'Refuse source copy overwrite'}
if((Get-FileHash -LiteralPath $taskManifest).Hash -cne $taskAuthorityHash){throw 'Original authority differs'}
$taskOriginal=Get-Content -LiteralPath $taskManifest -Raw|ConvertFrom-Json
$taskClock=[Diagnostics.Stopwatch]::StartNew()
function Assert-TaskDeadline {if($taskClock.Elapsed.TotalSeconds -gt 120){throw 'Source-only copy deadline expired'}}
function Assert-TaskPhysical([string]$Path){
 $taskCursor=Get-Item -LiteralPath $Path -Force
 while($null -ne $taskCursor){
  if($taskCursor.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked copy path refused'}
  $taskCursor=if($taskCursor.PSIsContainer){$taskCursor.Parent}else{$taskCursor.Directory}
 }
}
$taskGroups=@(
 @{name='typebox';old_root='C:\Users\adyba\pi-upstream-runtime-19cb534-20261012\node_modules\typebox';source=Join-Path $taskContainer 'upstream\runtime\19cb534-recovery-staging-20261016-174542-398b434f\node_modules\typebox';rows=@($taskOriginal.original_package);count=1385},
 @{name='acorn';old_root='C:\Users\adyba\AppData\Roaming\npm\node_modules\wrangler\node_modules\acorn';source='C:\Users\adyba\AppData\Roaming\npm\node_modules\wrangler\node_modules\acorn';rows=@($taskOriginal.acorn_complete);count=10}
)
$taskRecords=[Collections.Generic.List[object]]::new()
foreach($taskGroup in $taskGroups){
 Assert-TaskDeadline
 Assert-TaskPhysical $taskGroup.source
 if($taskGroup.rows.Count -ne $taskGroup.count){throw 'Original package count differs'}
 $taskExpected=@($taskGroup.rows|ForEach-Object{[IO.Path]::GetRelativePath($taskGroup.old_root,$_.path)})
 if(@($taskExpected|Where-Object{[IO.Path]::IsPathRooted($_) -or $_ -eq '..' -or $_.StartsWith('..\',[StringComparison]::Ordinal)}).Count){throw 'Original path escapes root'}
 $taskItems=@(Get-ChildItem -LiteralPath $taskGroup.source -Force -Recurse)
 if(@($taskItems|Where-Object{$_.Attributes -band [IO.FileAttributes]::ReparsePoint}).Count){throw 'Linked package inventory refused'}
 $taskFiles=@($taskItems|Where-Object{!$_.PSIsContainer})
 $taskActual=@($taskFiles|ForEach-Object{[IO.Path]::GetRelativePath($taskGroup.source,$_.FullName)})
 if(@(Compare-Object $taskExpected $taskActual -CaseSensitive).Count){throw 'Source package inventory differs'}
 foreach($taskRow in $taskGroup.rows){
  Assert-TaskDeadline
  $taskRelative=[IO.Path]::GetRelativePath($taskGroup.old_root,$taskRow.path)
  $taskSource=Join-Path $taskGroup.source $taskRelative
  if((Get-FileHash -LiteralPath $taskSource).Hash -cne $taskRow.sha256){throw 'Source package hash differs'}
  $taskRecords.Add([ordered]@{package=$taskGroup.name;relative=$taskRelative;original_path=$taskRow.path;source=$taskSource;destination=Join-Path (Join-Path $taskDestination $taskGroup.name) $taskRelative;sha256=$taskRow.sha256})
 }
}
Assert-TaskPhysical (Split-Path -Parent (Split-Path -Parent $taskDestination))
[void][IO.Directory]::CreateDirectory($taskDestination)
foreach($taskRecord in $taskRecords){
 Assert-TaskDeadline
 [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($taskRecord.destination))
 [IO.File]::Copy($taskRecord.source,$taskRecord.destination,$false)
 if((Get-FileHash -LiteralPath $taskRecord.destination).Hash -cne $taskRecord.sha256){throw 'Destination package hash differs'}
}
foreach($taskGroup in $taskGroups){
 $taskCopiedRoot=Join-Path $taskDestination $taskGroup.name
 $taskItems=@(Get-ChildItem -LiteralPath $taskCopiedRoot -Force -Recurse)
 if(@($taskItems|Where-Object{$_.Attributes -band [IO.FileAttributes]::ReparsePoint}).Count){throw 'Linked copied inventory refused'}
 $taskActual=@($taskItems|Where-Object{!$_.PSIsContainer}|ForEach-Object{[IO.Path]::GetRelativePath($taskCopiedRoot,$_.FullName)})
 $taskExpected=@($taskRecords|Where-Object{$_.package -ceq $taskGroup.name}|ForEach-Object relative)
 if(@(Compare-Object $taskExpected $taskActual -CaseSensitive).Count){throw 'Copied inventory differs'}
 foreach($taskRecord in @($taskRecords|Where-Object{$_.package -ceq $taskGroup.name})){
  Assert-TaskDeadline
  if((Get-FileHash -LiteralPath $taskRecord.source).Hash -cne $taskRecord.sha256 -or (Get-FileHash -LiteralPath $taskRecord.destination).Hash -cne $taskRecord.sha256){throw 'Final source/destination drift'}
 }
}
$taskReceipt=[ordered]@{schema=1;status='verified_source_only_packages';scope='Exact TypeBox1385 and Acorn10 bytes only; no runtime restoration, reference capture or generation';original_manifest=$taskManifest;original_manifest_sha256=$taskAuthorityHash;destination=$taskDestination;copied_files=$taskRecords.Count;rows=$taskRecords.ToArray();elapsed_seconds=$taskClock.Elapsed.TotalSeconds;source_modified=$false;runtime_status_changed=$false;utc=[DateTimeOffset]::UtcNow.ToString('o')}
$taskReceipt|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'receipt.json') -Encoding utf8NoBOM
[pscustomobject]@{status=$taskReceipt.status;files=$taskRecords.Count;destination=$taskDestination;elapsed_seconds=$taskReceipt.elapsed_seconds}
