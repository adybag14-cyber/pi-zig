$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskRuntime='C:\Users\adyba\pi-upstream-runtime-19cb534-20261012'
$taskName='mcp-19cb534-original-first-20261012'
function Verify([string]$Name) {
 $taskRows=@(Get-Content -LiteralPath (Join-Path $taskEvidence $Name) -Raw|ConvertFrom-Json)
 $taskDrift=@($taskRows|Where-Object{!(Test-Path -LiteralPath $_.path) -or (Get-FileHash -LiteralPath $_.path).Hash -cne $_.sha256})
 [ordered]@{manifest=$Name;count=$taskRows.Count;mismatches=$taskDrift.Count;paths=@($taskDrift|ForEach-Object path)}
}
$taskPre=@(Verify 'durable-19cb534-reference-20261012-all-built-runtime.json';Verify 'root-current8a-npm-tools-before.json')
$taskPre|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-prehash.json") -Encoding utf8NoBOM
if(@($taskPre|Where-Object mismatches -ne 0).Count){throw 'Genuine journal capture prehash mismatch'}
if((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory -lt 2MB){throw 'Source journal oracle needs fresh2GiB RAM'}
& (Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1') -Name $taskName -Executable 'C:\Program Files\nodejs\node.exe' -WorkingDirectory $taskRuntime -Arguments @('--max-old-space-size=64','--import','file:///C:/Users/adyba/pi-zig-update-evidence-20261003/mcp-19cb534-observe-modules-20261012.mjs',(Join-Path $taskEvidence 'mcp-19cb534-original-source-20261012.mjs'),(Join-Path $taskEvidence "$taskName-output.json"),(Join-Path $taskEvidence 'durable-19cb534-reference-20261012-junctions-before-build.json')) -TimeoutSeconds 30 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH=''}
$taskPost=@(Verify 'durable-19cb534-reference-20261012-all-built-runtime.json';Verify 'root-current8a-npm-tools-before.json')
$taskPost|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-posthash.json") -Encoding utf8NoBOM
if(@($taskPost|Where-Object mismatches -ne 0).Count){throw 'Genuine journal capture posthash mismatch'}
$taskResult=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
if($taskResult.status -cne 'passed'){throw 'Genuine journal capture failed; original outputs retained'}

