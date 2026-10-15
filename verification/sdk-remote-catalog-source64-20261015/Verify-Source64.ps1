$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$taskZipPath=Join-Path $PSScriptRoot 'source64-proof.zip'
$taskManifestPath=Join-Path $PSScriptRoot 'payload-manifest.json'
if((Get-FileHash -LiteralPath $taskZipPath).Hash -cne 'F7505071D520F4F8189FE625BF00753F9D0633351785593B2606562409F483E5'){throw 'Archive hash mismatch'}
if((Get-FileHash -LiteralPath $taskManifestPath).Hash -cne '662D46631B1BF4C88DB5789E583183D7D678DAA9798ABD68C5CCC17AA1EF2638'){throw 'Payload manifest mismatch'}
$taskRows=@(Get-Content -LiteralPath $taskManifestPath -Raw|ConvertFrom-Json)
$taskZip=[IO.Compression.ZipFile]::OpenRead($taskZipPath)
function Read-Entry([string]$taskName){$taskStream=$taskZip.GetEntry($taskName).Open();$taskReader=[IO.StreamReader]::new($taskStream);try{return $taskReader.ReadToEnd()}finally{$taskReader.Dispose()}}
try {
    if($taskZip.Entries.Count -ne 25 -or $taskRows.Count -ne 25){throw 'Exact25 payloads required'}
    foreach($taskRow in $taskRows){
        $taskEntry=$taskZip.GetEntry($taskRow.name)
        if(!$taskEntry -or $taskEntry.Length -ne $taskRow.bytes){throw 'Payload inventory mismatch'}
        $taskStream=$taskEntry.Open()
        try{$taskSHA=[Security.Cryptography.SHA256]::Create();try{$taskHash=[Convert]::ToHexString($taskSHA.ComputeHash($taskStream));if($taskHash -cne $taskRow.sha256){throw "Payload hash mismatch: $($taskRow.name)"}}finally{$taskSHA.Dispose()}}finally{$taskStream.Dispose()}
    }
    $taskStem='catalog-wrappers-4954-source64-first-20261015'
    $taskTerminal=(Read-Entry "$taskStem.json")|ConvertFrom-Json
    $taskPost=(Read-Entry "$taskStem-posthash.json")|ConvertFrom-Json
    $taskResult=(Read-Entry "$taskStem-output.json")|ConvertFrom-Json
    $taskValidation=(Read-Entry "$taskStem-validation.json")|ConvertFrom-Json
    if($taskTerminal.pid -ne 78440 -or $taskTerminal.status -cne 'passed' -or $taskTerminal.exit_code -ne 0){throw 'Terminal source failure'}
    if([DateTimeOffset]$taskPost.completed_utc -le [DateTimeOffset]$taskTerminal.completed_utc){throw 'Posthash must follow terminal'}
    if(@($taskPost.manifests|Where-Object drift -ne 0).Count -or $taskPost.control_manifest_drift -or !$taskPost.expected_still_absent){throw 'Frozen manifest check failed'}
    foreach($taskKey in @('extra_control_drift','absent_dependency_drift','compiler_drift','candidate_drift','compiler_inventory_drift','candidate_inventory_drift','reference_inventory_drift','node_inventory_drift')){if(@($taskPost.$taskKey).Count){throw "Frozen inventory changed: $taskKey"}}
    if($taskResult.count -ne 64 -or @($taskResult.rows).Count -ne 64 -or $taskResult.version -cne '1.1.0' -or $taskResult.sourceRuntimeUserAgent -cne 'pi/1.1.0 (win32; node/v24.14.0; x64)'){throw 'Actual explicit metadata capture required'}
    if($taskValidation.expected_sha256 -cne '7423CCD26F148A654A2C88BDBDAD38A40C1EBBD1B15E3D740E6DEFA169A7BBF5' -or !$taskValidation.expected_published_after_terminal_and_full_posthash -or $taskValidation.native_qualified){throw 'Source-only qualification mismatch'}
    $taskDependencies=@((Read-Entry 'source4954-runtime-manifest-20261015.json')|ConvertFrom-Json)
    $taskPackage=@($taskDependencies|Where-Object path -eq 'C:\Users\adyba\pi-upstream-runtime-19cb534-20261012\packages\coding-agent\package.json')
    if($taskDependencies.Count -ne 31064 -or $taskPackage.Count -ne 1 -or $taskPackage[0].sha256 -cne 'B74D12F072FB468B99D3C05106AEE87F80ABCBD5437BB778DFC2B0A370465499'){throw 'Ordinary package metadata must be frozen'}
    Write-Output 'PASS: 25 immutable payloads, actual64 functional source observations, explicit1.1 metadata frozen, full terminal posthash zero; native/latest-default unqualified'
} finally {$taskZip.Dispose()}
