param([string]$Attempt='first')
$ErrorActionPreference='Stop'
$taskEvidence='C:/Users/adyba/pi-zig-update-evidence-20261003'
$taskRoot='C:/Users/adyba/pi-zig-web-headers-20261015'
$taskName="web-body-node-builtin-inventory-$Attempt-20261015"
$taskBase=Join-Path $taskEvidence $taskName
$taskNode='C:/Program Files/nodejs/node.exe'
$taskOwner=Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'
$taskDriver=Join-Path $PSScriptRoot 'builtin-inventory.mjs'
$taskOriginal=Join-Path $taskEvidence 'web-body-node24-source-first-20261015-node-builtin-authorities.json'
if((Get-FileHash -LiteralPath $taskNode).Hash-cne'63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Pinned Node executable drift'}
$taskControls=@($PSCommandPath,$taskDriver,$taskOwner,$taskNode,$taskOriginal,(Join-Path $taskRoot 'src/extensions/fixtures/web-body-node24.json'),(Join-Path $taskRoot 'src/extensions/fixtures/web-body-node24.input.txt'))|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}}
$taskControlsPath="$taskBase-controls.json"
$taskControls|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskControlsPath -Encoding utf8NoBOM
$taskManifests=@([ordered]@{name='immutable-probe-controls-and-Source176';path=$taskControlsPath;sha256=(Get-FileHash -LiteralPath $taskControlsPath).Hash})
$taskFrozen="$taskBase-frozen.json"
$taskManifests|ConvertTo-Json -AsArray -Depth 4|Set-Content -LiteralPath $taskFrozen -Encoding utf8NoBOM
$taskFrozenHash=(Get-FileHash -LiteralPath $taskFrozen).Hash
function Verify-Frozen {if((Get-FileHash -LiteralPath $taskFrozen).Hash-cne$taskFrozenHash){throw 'Supplement frozen registry drift'};foreach($taskControl in $taskControls){if((Get-FileHash -LiteralPath $taskControl.path).Hash-cne$taskControl.sha256){throw "Supplement control drift $($taskControl.path)"}};return [ordered]@{controls=$taskControls.Count;drift=0}}
$taskBefore=Verify-Frozen
$taskBefore|ConvertTo-Json|Set-Content -LiteralPath "$taskBase-before.json" -Encoding utf8NoBOM
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1024
[ordered]@{minimum_free_bytes=2GB;available_bytes=$taskFree;heap_mb=256;outer_seconds=30;grant='Root NATIVE1 read-only builtin inventory plumbing';checked_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath "$taskBase-admission.json" -Encoding utf8NoBOM
if($taskFree-lt2GB){throw '2GiB supplement admission rejected'}
$taskFailure=$null
try{& $taskOwner -Name $taskName -Executable $taskNode -WorkingDirectory $taskRoot -Arguments @('--max-old-space-size=256',$taskDriver,"$taskBase-output.json",$taskOriginal,$taskFrozen) -TimeoutSeconds 30 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH='';NODE_USE_ENV_PROXY='';HTTP_PROXY='';HTTPS_PROXY='';ALL_PROXY='';NO_PROXY='127.0.0.1,localhost'}}catch{$taskFailure=$_}
$taskAfter=Verify-Frozen
$taskAfter|ConvertTo-Json|Set-Content -LiteralPath "$taskBase-after.json" -Encoding utf8NoBOM
if($taskFailure){throw $taskFailure}
$taskResult=Get-Content -LiteralPath "$taskBase-output.json" -Raw|ConvertFrom-Json
if($taskResult.string_bodies-ne368-or$taskResult.enumerated_entries-ne369-or$taskResult.undefined_keys.Count-ne1-or$taskResult.undefined_keys[0]-cne'configs'){throw 'Actual supplement contract mismatch'}
Write-Output 'ACTUAL_NODE_BUILTIN_INVENTORY_PASSED368_SOURCE_BODIES_PLUS_UNDEFINED_CONFIGS'
