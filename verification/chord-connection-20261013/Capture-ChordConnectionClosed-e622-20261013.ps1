$ErrorActionPreference='Stop'
$taskAttempt='first'
$taskEvidence=$PSScriptRoot
$taskManifestNames=@('sdk-loadout-e622-full-source-runtime-manifest-20261013.json','durable-19cb534-reference-20261012-all-built-runtime.json','root-current8a-npm-tools-before.json')
$taskInputs=@(foreach($taskManifestName in $taskManifestNames){Get-Content -LiteralPath (Join-Path $taskEvidence $taskManifestName) -Raw|ConvertFrom-Json})
$taskFiles=@('Capture-ChordConnectionClosed-e622-20261013.mjs','sdk-loadout-e622-source-observe-20261013.mjs')
$taskDriverInputs=@(foreach($taskFile in $taskFiles){$taskPath=Join-Path $taskEvidence $taskFile;[ordered]@{path=$taskPath;sha256=(Get-FileHash -LiteralPath $taskPath).Hash}}; $taskPath='C:\Users\adyba\pi-zig-update-evidence-20261003\chord-connection-closed-original-e622.input.txt';[ordered]@{path=$taskPath;sha256=(Get-FileHash -LiteralPath $taskPath).Hash})
function Drift($rows){@($rows|Where-Object{!(Test-Path -LiteralPath $_.path) -or (Get-FileHash -LiteralPath $_.path).Hash -ine $_.sha256})}
$taskBefore=Drift $taskInputs
if($taskBefore.Count){throw "Source capture prehash drift $($taskBefore.Count)"}
& (Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1') -Name "chord-connection-closed-original-e622-capture-$taskAttempt-20261013" -Executable 'C:\Program Files\nodejs\node.exe' -WorkingDirectory $taskEvidence -Arguments @('--import','file:///C:/Users/adyba/pi-zig-update-evidence-20261003/sdk-loadout-e622-source-observe-20261013.mjs',(Join-Path $taskEvidence 'Capture-ChordConnectionClosed-e622-20261013.mjs')) -TimeoutSeconds 30
$taskAfter=Drift $taskInputs
$taskDriverAfter=Drift $taskDriverInputs
$taskResult=Get-Content -LiteralPath (Join-Path $taskEvidence "chord-connection-closed-original-e622-capture-$taskAttempt-20261013.json") -Raw|ConvertFrom-Json
$taskPacket=[ordered]@{source='e6220e1316f86af818a0ccbfe1c09d7e918b41cf';manifest_files=$taskManifestNames;inputs=$taskInputs.Count;prehash_drift=$taskBefore.Count;posthash_drift=$taskAfter.Count;driver_inputs=$taskDriverInputs;driver_posthash_drift=$taskDriverAfter.Count;job=$taskResult;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
$taskPacket|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskEvidence 'chord-connection-closed-original-e622-capture-qualified-20261013.json') -Encoding utf8NoBOM
if($taskAfter.Count -or $taskDriverAfter.Count -or $taskResult.status -cne 'passed'){throw 'Source capture not qualified'}
$taskPacket|Select-Object source,inputs,prehash_drift,posthash_drift,driver_posthash_drift,completed_utc|ConvertTo-Json


