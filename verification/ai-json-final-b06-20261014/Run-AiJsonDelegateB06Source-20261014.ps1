param([string]$Attempt='first')
$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskName="ai-json-delegate-b06-source6-$Attempt-20261014"
$taskNode='C:/Program Files/nodejs/node.exe'
$taskSource='C:/Users/adyba/pi-upstream-source-b06c1f2-20261014'
$taskRuntime='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
$taskInput=Join-Path $taskEvidence 'ai-json-delegate-b06-caller-20261014.mjs'
$taskDriver=Join-Path $taskEvidence 'ai-json-delegate-b06-source-capture-20261014.mjs'
$taskObserver=Join-Path $taskEvidence 'sdk-source-b06-observe-20261014.mjs'
$taskAudit=Join-Path $taskEvidence 'sdk-source-b06-dependency-contract-audit-20261014.json'
$taskJobOwner=Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'
$taskSpecs=@(
    @{name='source';file='sdk-source-b06-full-manifest-20261014.json';count=1965},
    @{name='dependencies';file='durable-19cb534-reference-20261012-all-built-runtime.json';count=31064},
    @{name='node_tools';file='root-current8a-npm-tools-before.json';count=1774}
)
function Check-Rows($taskRows){
    $taskChanged=[Collections.Generic.List[string]]::new()
    foreach($taskRow in $taskRows){
        if(!(Test-Path -LiteralPath $taskRow.path -PathType Leaf) -or (Get-FileHash -LiteralPath $taskRow.path).Hash -cne $taskRow.sha256){$taskChanged.Add($taskRow.path)}
    }
    return @($taskChanged)
}
$taskFrozen=@()
foreach($taskSpec in $taskSpecs){
    $taskRows=@(Get-Content -LiteralPath (Join-Path $taskEvidence $taskSpec.file) -Raw|ConvertFrom-Json)
    if($taskRows.Count -ne $taskSpec.count){throw "Full manifest inventory mismatch $($taskSpec.name)"}
    $taskChanged=@(Check-Rows $taskRows)
    if($taskChanged.Count){throw "Reference prehash drift $($taskSpec.name): $($taskChanged.Count)"}
    $taskFrozen+=@{name=$taskSpec.name;manifest=$taskSpec.file;rows=$taskRows}
}
if((git -C $taskSource rev-parse HEAD) -cne 'b06c1f2cf1dea6af8748ddeee18c23587d2cb7c6'){throw 'Pinned Source head changed'}
if((Get-FileHash -LiteralPath $taskNode).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Pinned Node changed'}
$taskContract=Get-Content -LiteralPath $taskAudit -Raw|ConvertFrom-Json
if($taskContract.latestHead -cne 'b06c1f2cf1dea6af8748ddeee18c23587d2cb7c6' -or $taskContract.installed_metadata_verified -ne 281 -or $taskContract.platform_optional_absent_records -ne 80 -or $taskContract.historical_missing_records_retained -ne 4){throw 'Dependency contract scope changed'}
$taskAbsent=@($taskContract.pins|Where-Object status -eq 'platform_optional_absent'|ForEach-Object {Join-Path $taskRuntime $_.path})+@($taskContract.mismatches|ForEach-Object {Join-Path $taskRuntime $_.path})
if($taskAbsent.Count -ne 84 -or @($taskAbsent|Where-Object {Test-Path -LiteralPath $_}).Count){throw 'Historical absent dependency state changed'}
$taskExtraPaths=@($taskInput,$taskDriver,$taskObserver,$taskAudit,$taskJobOwner,$PSCommandPath)+@($taskSpecs|ForEach-Object {Join-Path $taskEvidence $_.file})
$taskExtra=@($taskExtraPaths|ForEach-Object {@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskExtra|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-extra-before.json") -Encoding utf8NoBOM
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt 2MB){@{status='admission_denied';free_kib=$taskFree;required_kib=2MB;node_launched=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json");exit 2}
@{status='admitted';free_kib=$taskFree;required_kib=2MB;heap_mb=256;coordinated_with='Root explicitly coordinated AI Source reservation; max two local reservations';observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json")
$taskOutput=Join-Path $taskEvidence "$taskName-output.json"
& $taskJobOwner -Name $taskName -Executable $taskNode -WorkingDirectory $taskSource -Arguments @('--max-old-space-size=256','--conditions=source','--experimental-transform-types','--import',([Uri]$taskObserver).AbsoluteUri,$taskDriver,$taskOutput) -TimeoutSeconds 300 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH='';PI_PACKAGE_DIR='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/packages/coding-agent'}
$taskPost=@()
foreach($taskItem in $taskFrozen){$taskChanged=@(Check-Rows $taskItem.rows);$taskPost+=@{name=$taskItem.name;files=$taskItem.rows.Count;drift=$taskChanged.Count;changed=$taskChanged}}
$taskExtraChanged=@(Check-Rows $taskExtra)
$taskAbsentChanged=@($taskAbsent|Where-Object {Test-Path -LiteralPath $_})
@{manifests=$taskPost;extra_control_drift=$taskExtraChanged;absent_dependency_drift=$taskAbsentChanged;historical_absence_records=$taskAbsent.Count;driver_sha256=(Get-FileHash -LiteralPath $taskDriver).Hash;input_sha256=(Get-FileHash -LiteralPath $taskInput).Hash;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-posthash.json")
if(@($taskPost|Where-Object drift -ne 0).Count -or $taskExtraChanged.Count -or $taskAbsentChanged.Count){throw 'Reference posthash drift'}
$taskOwner=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
if($taskOwner.status -cne 'passed'){throw "Source oracle terminal $($taskOwner.status)"}
$taskResult=Get-Content -LiteralPath $taskOutput -Raw|ConvertFrom-Json
if($taskResult.cases -ne 6 -or @($taskResult.rows).Count -ne 6 -or $taskResult.sourceHead -cne 'b06c1f2cf1dea6af8748ddeee18c23587d2cb7c6' -or $taskResult.actualNode.version -cne 'v24.14.0'){throw 'Original b06 Source6 output missing'}
Write-Output ('ORIGINAL_B06_JSON_ORIGIN_CASES='+$taskResult.rows.Count)
