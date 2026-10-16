$ErrorActionPreference='Stop'
$taskP=$PSScriptRoot
$taskName='typebox-compile-source80-first-3b7a6480-20261016'
$taskPacket=Get-Content -LiteralPath (Join-Path $taskP 'source-packet-sha256.json') -Raw|ConvertFrom-Json
foreach($row in $taskPacket){$taskPath=Join-Path $taskP $row.path;if(!(Test-Path -LiteralPath $taskPath -PathType Leaf)-or(Get-FileHash -LiteralPath $taskPath).Hash -ine $row.sha256){throw "Retained Source80 packet drift $($row.path)"}}
$taskOwner=Get-Content -LiteralPath (Join-Path $taskP "$taskName.json") -Raw|ConvertFrom-Json
$taskPost=Get-Content -LiteralPath (Join-Path $taskP "$taskName-posthash.json") -Raw|ConvertFrom-Json
$taskOutput=Get-Content -LiteralPath (Join-Path $taskP "$taskName-output.json") -Raw|ConvertFrom-Json
$taskAbsent=Get-Content -LiteralPath (Join-Path $taskP 'source-process-absence.json') -Raw|ConvertFrom-Json
if($taskOwner.status -cne 'passed'-or $taskOwner.exit_code -ne 0-or !$taskAbsent.absent-or $taskAbsent.pid -ne $taskOwner.pid){throw 'Original terminal0/absence evidence missing'}
foreach($property in $taskPost.psobject.Properties){if($property.Name -like '*_drift'-and $property.Value){throw "Original complete posthash drift $($property.Name)"}}
if($taskPost.source_files -ne 1970-or $taskPost.runtime_files -ne 31064-or $taskPost.node_files -ne 1774-or $taskPost.candidate_files -ne 7984-or $taskPost.controls_files -ne 9){throw 'Original full frozen scope mismatch'}
if($taskOutput.count -ne 80-or @($taskOutput.rows).Count -ne 80-or $taskOutput.version -cne '1.3.27'-or $taskOutput.runtime -cne 'v24.14.0'){throw 'Original actual Source80 scope mismatch'}
$taskGolden=Join-Path $taskP '../../src/extensions/fixtures/typebox-compile-production.json'
if((Get-FileHash -LiteralPath $taskGolden).Hash -cne '54303EE9477C4632F408963887DD58E5103775D1C8B75B37DF8F27A020984DE2'){throw 'Accepted genuine expected drift'}
$taskZip=[IO.Compression.ZipFile]::OpenRead((Join-Path $taskP 'source-full-prehash.zip'))
try{$taskEntry=$taskZip.GetEntry("$taskName-prehash.json");if(!$taskEntry){throw 'Original full prehash missing'};$taskReader=[IO.StreamReader]::new($taskEntry.Open());try{$taskPre=$taskReader.ReadToEnd()|ConvertFrom-Json}finally{$taskReader.Dispose()};foreach($pair in @(@{name='source';count=1970},@{name='runtime';count=31064},@{name='node';count=1774},@{name='candidate';count=7984},@{name='controls';count=9})){if(@($taskPre.($pair.name)).Count -ne $pair.count){throw 'Archived full inventory mismatch'}}}finally{$taskZip.Dispose()}
Write-Output 'SOURCE80_PACKET_VERIFIED reference_only native_unrun full_pi_unqualified'
