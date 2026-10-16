param([Parameter(Mandatory)][string]$Config,[Parameter(Mandatory)][string]$ConfigSha256)
$ErrorActionPreference='Stop'
if((Get-FileHash -LiteralPath $Config).Hash -cne $ConfigSha256){throw 'Phase config changed'}
$taskConfig=Get-Content -LiteralPath $Config -Raw|ConvertFrom-Json
if($taskConfig.mode -eq 'artifacts'){
    $taskDrift=@(Get-Content -LiteralPath $taskConfig.captured -Raw|ConvertFrom-Json|Where-Object {!(Test-Path -LiteralPath $_.path -PathType Leaf) -or (Get-FileHash -LiteralPath $_.path).Hash -cne $_.sha256})
    $taskRows=@(Get-ChildItem -LiteralPath $taskConfig.run -File -Recurse|Where-Object {$_.Name -notin @('artifact-manifest.json','terminal.json')}|ForEach-Object {@{path=$_.FullName;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash;bytes=$_.Length}})
    @{rows=$taskRows;captured_drift=$taskDrift;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $taskConfig.run 'artifact-manifest.json') -Encoding utf8NoBOM
    if($taskDrift.Count){throw 'Raw captured output/module/closure artifacts changed'}
    exit 0
}
if($taskConfig.mode -eq 'hash'){
    & $taskConfig.freeze -CandidateHead $taskConfig.candidate_head -OutputManifest $taskConfig.manifest -Receipt $taskConfig.receipt -Phase $taskConfig.phase -AdditionalControls $taskConfig.additional_controls
    exit 0
}
if($taskConfig.mode -cne 'node'){throw 'Unknown owned phase'}
if((Get-FileHash -LiteralPath $taskConfig.owner).Hash -cne '96BEA0CF8E17535C322EE4F36C0115387386F16988BC2B98465BD070A504F5E5'){throw 'Retained Source owner changed'}
$taskEnvironment=@{}
foreach($taskProperty in $taskConfig.environment.PSObject.Properties){$taskEnvironment[$taskProperty.Name]=[string]$taskProperty.Value}
$taskFree=(Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 3).FreePhysicalMemory
@{free_kib=$taskFree;required_free_kib=16MB;source_reserved_kib=2MB;heap_mb=256;node_started=$false;admitted=($taskFree -ge 16MB);observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path (Split-Path -Parent $taskConfig.owner) ($taskConfig.name+'-node-admission.json')) -Encoding utf8NoBOM
if($taskFree -lt 16MB){throw 'Immediate pre-Node fresh16GiB admission denied'}
& $taskConfig.owner -Name $taskConfig.name -Executable $taskConfig.node -WorkingDirectory $taskConfig.working_directory -Arguments @($taskConfig.arguments) -TimeoutSeconds 300 -SettleSeconds 10 -EnvironmentOverrides $taskEnvironment
$taskRecord=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $taskConfig.owner) ($taskConfig.name+'.json')) -Raw|ConvertFrom-Json
if($taskRecord.status -cne 'passed' -or $taskRecord.exit_code -ne 0 -or !$taskRecord.independent_pid_absent -or !$taskRecord.terminal_kernel_handle){throw 'Retained Node owner terminal negative'}
