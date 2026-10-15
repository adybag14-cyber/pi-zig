function Freeze-OneShotReferences {
 $taskReferenceSpecs=@(
  @{name='source5ab';file='source5ab-full-manifest-20261015.json';count=1967},
  @{name='dependencies';file='durable-19cb534-reference-20261012-all-built-runtime.json';count=31064},
  @{name='node_tools';file='root-current8a-npm-tools-before.json';count=1774}
 )
 $taskReferenceSets=@()
 foreach($taskReferenceSpec in $taskReferenceSpecs){
  $taskReferenceRows=@(Get-Content -LiteralPath (Join-Path $taskEvidence $taskReferenceSpec.file) -Raw|ConvertFrom-Json)
  if($taskReferenceRows.Count -ne $taskReferenceSpec.count){throw "Reference inventory mismatch $($taskReferenceSpec.name)"}
  if(@(Tool-Drift $taskReferenceRows).Count){throw "Reference prehash drift $($taskReferenceSpec.name)"}
  $taskReferenceSets+=@{name=$taskReferenceSpec.name;manifest=$taskReferenceSpec.file;rows=$taskReferenceRows}
 }
 $taskReferenceHead=git -C 'C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015' rev-parse HEAD
 if($taskReferenceHead -cne '5ab7fe74c400097b386662205cd93900695b8a71'){throw 'Original5ab head drift'}
 if((Get-FileHash -LiteralPath 'C:/Program Files/nodejs/node.exe').Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Actual original Node executable drift'}
 $taskReferenceAudit=Get-Content -LiteralPath (Join-Path $taskEvidence 'source5ab-dependency-contract-audit-20261015.json') -Raw|ConvertFrom-Json
 if($taskReferenceAudit.latestHead -cne $taskReferenceHead -or $taskReferenceAudit.installed_metadata_verified -ne 281 -or $taskReferenceAudit.platform_optional_absent_records -ne 80 -or $taskReferenceAudit.historical_missing_records_retained -ne 4){throw 'Dependency contract scope drift'}
 $taskReferenceRuntime='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
 $taskReferenceAbsent=@($taskReferenceAudit.pins|Where-Object status -eq 'platform_optional_absent'|ForEach-Object {Join-Path $taskReferenceRuntime $_.path})+@($taskReferenceAudit.mismatches|ForEach-Object {Join-Path $taskReferenceRuntime $_.path})
 if($taskReferenceAbsent.Count -ne 84 -or @($taskReferenceAbsent|Where-Object {Test-Path -LiteralPath $_}).Count){throw 'Reference absence prehash drift'}
 return @{sets=$taskReferenceSets;absent=$taskReferenceAbsent;head=$taskReferenceHead}
}
function Check-OneShotReferences($taskReferenceFreeze){
 $taskReferencePost=@()
 foreach($taskReferenceSet in $taskReferenceFreeze.sets){
  $taskReferenceChanged=@(Tool-Drift $taskReferenceSet.rows)
  $taskReferencePost+=@{name=$taskReferenceSet.name;files=$taskReferenceSet.rows.Count;drift=$taskReferenceChanged.Count;changed=$taskReferenceChanged}
 }
 $taskReferenceAbsentChanged=@($taskReferenceFreeze.absent|Where-Object {Test-Path -LiteralPath $_})
 $taskReferenceHeadAfter=git -C 'C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015' rev-parse HEAD
 return @{manifests=$taskReferencePost;absent_records=$taskReferenceFreeze.absent.Count;absent_drift=$taskReferenceAbsentChanged;head=$taskReferenceFreeze.head;head_after=$taskReferenceHeadAfter;head_drift=$taskReferenceFreeze.head -cne $taskReferenceHeadAfter;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
}
