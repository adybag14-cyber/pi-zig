param([Parameter(Mandatory)][string]$Attempt,[Parameter(Mandatory)][string]$Fixture,[Parameter(Mandatory)][string]$GlobalName)
$ErrorActionPreference='Stop'
$captureEvidence='C:/Users/adyba/pi-zig-update-evidence-20261003'
$captureRows=@(@{name='sdk-source-1692-full-manifest-20261014.json';root='C:/Users/adyba/pi-upstream-source-1692bba-20261014'},@{name='durable-19cb534-reference-20261012-all-built-runtime.json';root='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'},@{name='root-current8a-npm-tools-before.json';root='C:/Program Files/nodejs'})
$captureDriver=Join-Path $captureEvidence 'Capture-ChordLatest1692.mjs'
$captureResolver=Join-Path $captureEvidence 'sdk-source-1692-observe-20261014.mjs'
$captureFixture=Join-Path 'C:/Users/adyba/pi-zig-chord-full-composition-e6220e1-20261013/src/extensions/fixtures' $Fixture
$captureOutput=Join-Path $captureEvidence "$Attempt-output.json"
$captureInputs=@($captureDriver,$captureResolver,$captureFixture,(Join-Path $captureEvidence 'sdk-source-1692-dependency-contract-audit-20261014.json')) | ForEach-Object { [ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash} }
if($GlobalName -ceq 'chordNodeLoaderCases'){
 $captureGuestManifest=Join-Path $captureEvidence 'chord-node-loader-1692-guests-manifest.json'
 $captureGuests=@(Get-Content -LiteralPath $captureGuestManifest -Raw|ConvertFrom-Json)
 foreach($captureGuest in $captureGuests){if((Get-FileHash -LiteralPath $captureGuest.path).Hash -cne $captureGuest.sha256){throw 'Pinned guest fixture drift'}}
 $captureInputs+=@([ordered]@{path=$captureGuestManifest;sha256=(Get-FileHash -LiteralPath $captureGuestManifest).Hash})
 $captureInputs+=@($captureGuests)
}
function Get-CaptureHashes {
 foreach($captureManifest in $captureRows){
  $captureManifestPath=Join-Path $captureEvidence $captureManifest.name
  $captureData=Get-Content -LiteralPath $captureManifestPath -Raw|ConvertFrom-Json
  $captureFiles=if($captureData -is [array]){@($captureData)}elseif($captureData.inputs){@($captureData.inputs)}elseif($captureData.files -is [array]){@($captureData.files)}else{@($captureData)}
  $captureDrift=[Collections.Generic.List[string]]::new()
  foreach($captureFile in $captureFiles){
   $capturePath=if([IO.Path]::IsPathRooted($captureFile.path)){$captureFile.path}else{Join-Path $captureManifest.root $captureFile.path}
   $captureStream=[IO.File]::OpenRead($capturePath)
   try{$captureHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($captureStream))}finally{$captureStream.Dispose()}
   if($captureHash -ine $captureFile.sha256){$captureDrift.Add($capturePath)}
  }
  [ordered]@{manifest=$captureManifest.name;manifest_sha256=(Get-FileHash -LiteralPath $captureManifestPath).Hash;files=$captureFiles.Count;drift=$captureDrift.Count;changed=@($captureDrift)}
  if($captureDrift.Count){throw "Pinned capture input drift $($captureManifest.name)"}
 }
}
$captureBefore=@(Get-CaptureHashes)
$captureBefore|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $captureEvidence "$Attempt-before.json") -Encoding utf8NoBOM
$captureMemory=Get-CimInstance Win32_OperatingSystem
if([long]$captureMemory.FreePhysicalMemory*1024 -lt 2GB){throw 'Source capture requires fresh 2 GiB free physical RAM'}
if((Get-FileHash -LiteralPath 'C:/Program Files/nodejs/node.exe').Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Pinned Node identity mismatch'}
[ordered]@{observed_utc=[DateTimeOffset]::UtcNow.ToString('o');free_bytes=[long]$captureMemory.FreePhysicalMemory*1024;max_old_space_mib=256;source='1692bba6347a287ab0f3cb554a4430fafffc474b';drivers=@($captureInputs)}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $captureEvidence "$Attempt-admission.json") -Encoding utf8NoBOM
& (Join-Path $captureEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1') -Name $Attempt -Executable 'C:/Program Files/nodejs/node.exe' -WorkingDirectory $captureEvidence -Arguments @('--max-old-space-size=256','--conditions=source','--experimental-transform-types','--import','file:///C:/Users/adyba/pi-zig-update-evidence-20261003/sdk-source-1692-observe-20261014.mjs',$captureDriver,$captureFixture,$captureOutput,$GlobalName) -TimeoutSeconds 30
$captureAfter=@(Get-CaptureHashes)
$captureAfter|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $captureEvidence "$Attempt-after.json") -Encoding utf8NoBOM
$captureDriverDrift=@($captureInputs|Where-Object{(Get-FileHash -LiteralPath $_.path).Hash -ine $_.sha256})
$captureJob=Get-Content -LiteralPath (Join-Path $captureEvidence "$Attempt.json") -Raw|ConvertFrom-Json
$capturePacket=[ordered]@{source='1692bba6347a287ab0f3cb554a4430fafffc474b';fixture=$captureFixture;source_body_replaced=$false;actual_factory_calls=$true;pre=@($captureBefore);post=@($captureAfter);driver_drift=$captureDriverDrift.Count;job=$captureJob;output=$captureOutput;output_sha256=if(Test-Path -LiteralPath $captureOutput){(Get-FileHash -LiteralPath $captureOutput).Hash}else{$null}}
$capturePacket|ConvertTo-Json -Depth 9|Set-Content -LiteralPath (Join-Path $captureEvidence "$Attempt-qualified.json") -Encoding utf8NoBOM
if($captureDriverDrift.Count -or $captureJob.status -cne 'passed'){throw 'Original Source capture not qualified'}
[pscustomobject]$capturePacket|Select-Object source,driver_drift,output,output_sha256|ConvertTo-Json
