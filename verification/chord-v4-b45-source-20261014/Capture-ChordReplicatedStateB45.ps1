param([Parameter(Mandatory)][string]$Attempt,[Parameter(Mandatory)][string]$Fixture,[Parameter(Mandatory)][string]$GlobalName,[Parameter(Mandatory)][string]$RootGrant)
$ErrorActionPreference='Stop'
$captureEvidence='C:/Users/adyba/pi-zig-update-evidence-20261003'
$captureRows=@(@{name='sdk-source-b45-full-manifest-20261014.json';root='C:/Users/adyba/pi-upstream-source-b45e0eb-20261014'},@{name='durable-19cb534-reference-20261012-all-built-runtime.json';root='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'},@{name='root-current8a-npm-tools-before.json';root='C:/Program Files/nodejs'})
$captureDriver=Join-Path $captureEvidence 'Capture-ChordReplicatedStateB45.mjs'
$captureResolver=Join-Path $captureEvidence 'sdk-source-b45-observe-20261014.mjs'
$captureFixture=Join-Path 'C:/Users/adyba/pi-zig-chord-v4-state-b45-20261014/src/extensions/fixtures' $Fixture
$captureOutput=Join-Path $captureEvidence "$Attempt-output.json"
$captureInputs=@($PSCommandPath,(Join-Path $captureEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'),$captureDriver,$captureResolver,$captureFixture,(Join-Path $captureEvidence 'sdk-source-b45-dependency-contract-audit-20261014.json')) | ForEach-Object { [ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash} }
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
$captureRoot='C:/Users/adyba/pi-zig-chord-v4-state-b45-20261014'
if(Test-Path -LiteralPath (Join-Path $captureEvidence "$Attempt.json")){throw 'Refuse Source capture replay'}
function Candidate-Rows {
 @(git -C $captureRoot ls-files --cached --others --exclude-standard|Sort-Object -Unique|Where-Object{Test-Path -LiteralPath (Join-Path $captureRoot $_) -PathType Leaf}|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $captureRoot $_)).Hash}})
}
$captureCandidateBefore=Candidate-Rows
$captureCandidateBefore|ConvertTo-Json -Depth 4|Set-Content (Join-Path $captureEvidence "$Attempt-candidate-before.json") -Encoding utf8NoBOM
$captureInputs+=@($captureRows|ForEach-Object{[ordered]@{path=(Join-Path $captureEvidence $_.name);sha256=(Get-FileHash -LiteralPath (Join-Path $captureEvidence $_.name)).Hash}})
$captureBefore=@(Get-CaptureHashes)
if(($captureBefore.files -join ',') -cne '1965,31064,1774'){throw 'Exact latest closure inventory changed'}
$captureBefore|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $captureEvidence "$Attempt-before.json") -Encoding utf8NoBOM
$captureMemory=Get-CimInstance Win32_OperatingSystem
if([long]$captureMemory.FreePhysicalMemory*1024 -lt 2GB){throw 'Source capture requires fresh 2 GiB free physical RAM'}
if((Get-FileHash -LiteralPath 'C:/Program Files/nodejs/node.exe').Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Pinned Node identity mismatch'}
[ordered]@{observed_utc=[DateTimeOffset]::UtcNow.ToString('o');free_bytes=[long]$captureMemory.FreePhysicalMemory*1024;max_old_space_mib=256;source='b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb';drivers=@($captureInputs)}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $captureEvidence "$Attempt-admission.json") -Encoding utf8NoBOM
$captureFree=[long](Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1024
$captureNative=@(Get-CimInstance Win32_Process -Filter "Name = 'zig.exe'"|Where-Object{$_.CommandLine -match 'zig(?:\.exe)?"?\s+build\s'}|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine)
[ordered]@{free_bytes=$captureFree;required_bytes=2GB;native_roots=$captureNative;max_roots=2;heap_mb=256;source_node_reservation=$true;root_authority=$RootGrant;utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $captureEvidence "$Attempt-admission.json") -Encoding utf8NoBOM
if($captureFree -lt 2GB -or $captureNative.Count -gt 1){throw 'Source oracle admission rejected; no Node launched'}
if((Get-FileHash -LiteralPath 'C:/Program Files/nodejs/node.exe').Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Pinned Node distribution changed'}
& (Join-Path $captureEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1') -Name $Attempt -Executable 'C:/Program Files/nodejs/node.exe' -WorkingDirectory $captureEvidence -Arguments @('--max-old-space-size=256','--conditions=source','--experimental-transform-types','--import','file:///C:/Users/adyba/pi-zig-update-evidence-20261003/sdk-source-b45-observe-20261014.mjs',$captureDriver,$captureFixture,$captureOutput,$GlobalName) -TimeoutSeconds 30
$captureAfter=@(Get-CaptureHashes)
$captureAfter|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $captureEvidence "$Attempt-after.json") -Encoding utf8NoBOM
$captureDriverDrift=@($captureInputs|Where-Object{(Get-FileHash -LiteralPath $_.path).Hash -ine $_.sha256})
$captureJob=Get-Content -LiteralPath (Join-Path $captureEvidence "$Attempt.json") -Raw|ConvertFrom-Json
$captureCandidateAfter=Candidate-Rows
$captureCandidateDrift=@(Compare-Object @($captureCandidateBefore|ForEach-Object{"$($_.path):$($_.sha256)"}) @($captureCandidateAfter|ForEach-Object{"$($_.path):$($_.sha256)"}))
$captureAbsent=!(Get-CimInstance Win32_Process -Filter "ProcessId = $($captureJob.pid)")
[ordered]@{candidate_before=$captureCandidateBefore.Count;candidate_after=$captureCandidateAfter.Count;candidate_drift=$captureCandidateDrift.Count;root_pid_absent=$captureAbsent;source_inputs=1965;dependency_inputs=31064;node_inputs=1774;control_drift=$captureDriverDrift.Count;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $captureEvidence "$Attempt-candidate-post.json") -Encoding utf8NoBOM
if($captureCandidateDrift.Count -or !$captureAbsent){throw 'Complete candidate freeze or exact Source PID absence failed'}
$capturePacket=[ordered]@{source='b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb';fixture=$captureFixture;source_body_replaced=$false;actual_factory_calls=$true;pre=@($captureBefore);post=@($captureAfter);driver_drift=$captureDriverDrift.Count;job=$captureJob;output=$captureOutput;output_sha256=if(Test-Path -LiteralPath $captureOutput){(Get-FileHash -LiteralPath $captureOutput).Hash}else{$null}}
$capturePacket|ConvertTo-Json -Depth 9|Set-Content -LiteralPath (Join-Path $captureEvidence "$Attempt-qualified.json") -Encoding utf8NoBOM
if($captureDriverDrift.Count -or $captureJob.status -cne 'passed'){throw 'Original Source capture not qualified'}
[pscustomobject]$capturePacket|Select-Object source,driver_drift,output,output_sha256|ConvertTo-Json
