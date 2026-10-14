param([string]$Attempt='first')
$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskName="sdk-session-manual-compaction-b45-source32-$Attempt-20261014"
$taskNode='C:\Program Files\nodejs\node.exe'
$taskInput='C:\Users\adyba\pi-zig-update-evidence-20261003\sdk-session-manual-compaction-b45.input.txt'
$taskDriver=Join-Path $taskEvidence 'sdk-session-manual-compaction-b45-source-capture-20261014.mjs'
$taskObserver=Join-Path $taskEvidence 'sdk-source-b45-observe-20261014.mjs'
$taskSpecs=@(
    @{name='source';file='sdk-source-b45-full-manifest-20261014.json';count=1965},
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
if((Get-FileHash -LiteralPath $taskNode).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Pinned Node changed'}
$taskExtra=@($taskInput,$taskDriver,$taskObserver)|ForEach-Object{@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}}
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt 2MB){@{status='admission_denied';free_kib=$taskFree;required_kib=2MB;node_launched=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json");exit 2}
@{status='admitted';free_kib=$taskFree;required_kib=2MB;heap_mb=256;coordinated_with='Root Source20 transcript context oracle reservation; at most one other coordinated native reservation';observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json")
$taskOutput=Join-Path $taskEvidence "$taskName-output.json"
& (Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1') -Name $taskName -Executable $taskNode -WorkingDirectory 'C:\Users\adyba\pi-upstream-source-b45e0eb-20261014' -Arguments @('--max-old-space-size=256','--conditions=source','--experimental-transform-types','--import',([Uri]$taskObserver).AbsoluteUri,$taskDriver,$taskOutput,$taskInput) -TimeoutSeconds 300 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH='';PI_PACKAGE_DIR='C:\Users\adyba\pi-upstream-runtime-19cb534-20261012\packages\coding-agent'}
$taskPost=@()
foreach($taskItem in $taskFrozen){$taskChanged=@(Check-Rows $taskItem.rows);$taskPost+=@{name=$taskItem.name;files=$taskItem.rows.Count;drift=$taskChanged.Count;changed=$taskChanged}}
$taskExtraChanged=@(Check-Rows $taskExtra)
@{manifests=$taskPost;caller_input_drift=$taskExtraChanged;driver_sha256=$taskExtra[1].sha256;input_sha256=$taskExtra[0].sha256;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-posthash.json")
if(@($taskPost|Where-Object drift -ne 0).Count -or $taskExtraChanged.Count){throw 'Reference posthash drift'}
$taskOwner=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
if($taskOwner.status -cne 'passed'){throw "Source oracle terminal $($taskOwner.status)"}
$taskResult=Get-Content -LiteralPath $taskOutput -Raw|ConvertFrom-Json
if( $taskResult.cases -ne 32 -or @($taskResult.rows).Count -ne 32){throw 'Original32 output missing'}
Write-Output ('ORIGINAL_MANUAL_COMPACTION_CASES='+$taskResult.rows.Count)
