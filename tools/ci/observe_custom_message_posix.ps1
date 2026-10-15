param([string]$SourceDir,[string]$Receipt='verification/native-sdk-custom-message-posix-reference')
. "$PSScriptRoot/native_qualification_ci.ps1"
. "$PSScriptRoot/custom_reference_inventory.ps1"
if(!$IsLinux){throw 'Custom-message reference owner is scoped to genuine Linux'}
$taskRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'));$taskSource=[IO.Path]::GetFullPath($SourceDir)
$taskReceipt=Join-Path $taskRoot $Receipt;New-Item -ItemType Directory -Path $taskReceipt -Force > $null
$taskHead='5ab7fe74c400097b386662205cd93900695b8a71'
if((git -C $taskSource rev-parse HEAD).Trim() -cne $taskHead){throw 'Exact latest5ab Source head mismatch'}
$taskTracked=@(git -C $taskSource ls-files);if($LASTEXITCODE -ne 0 -or $taskTracked.Count -ne 1924){throw 'Latest5ab tracked inventory changed'}
$taskHistorical=@(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'custom-message-reference/source5ab-full-manifest.json') -Raw|ConvertFrom-Json)
if($taskHistorical.Count -ne 1967){throw 'Complete original latest5ab Source inventory must contain1967 files'}
$taskExpected=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
foreach($taskRow in $taskHistorical){if(!$taskRow.relative -or $taskExpected.ContainsKey($taskRow.relative) -or $taskRow.sha256 -cnotmatch '^[0-9A-F]{64}$'){throw 'Duplicate/malformed complete original Source path/hash'};$taskExpected.Add($taskRow.relative,$taskRow.sha256)}
$taskTrackedRows=Get-CiRows $taskSource $taskTracked
foreach($taskRow in $taskTrackedRows){if(!$taskExpected.ContainsKey($taskRow.relative) -or $taskExpected[$taskRow.relative] -cne $taskRow.sha256){throw 'Official latest tracked Source hash mismatch'}}
$taskGenerated=@($taskExpected.Keys|Where-Object {$_ -cnotin $taskTracked})
if($taskGenerated.Count -ne 43 -or @($taskGenerated|Where-Object {!$_.StartsWith('packages/ai/src/providers/data/',[StringComparison]::Ordinal)}).Count){throw 'Exactly43 frozen typed provider-data fixture files required'}
$taskProviderZip=[IO.Compression.ZipFile]::OpenRead((Join-Path $PSScriptRoot 'custom-message-reference/frozen-provider-data.zip'))
try {
 if($taskProviderZip.Entries.Count -ne 43){throw 'Frozen provider data archive count mismatch'}
 $taskSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
 foreach($taskEntry in $taskProviderZip.Entries){
  if($taskEntry.FullName -cnotin $taskGenerated -or !$taskSeen.Add($taskEntry.FullName)){throw 'Unexpected or duplicate frozen provider data path'}
  $taskDestination=[IO.Path]::GetFullPath((Join-Path $taskSource $taskEntry.FullName))
  if(!$taskDestination.StartsWith($taskSource+[IO.Path]::DirectorySeparatorChar,[StringComparison]::Ordinal) -or (Test-Path -LiteralPath $taskDestination)){throw 'Frozen provider data destination escapes or already exists'}
  New-Item -ItemType Directory -Path (Split-Path -Parent $taskDestination) -Force > $null
  [IO.Compression.ZipFileExtensions]::ExtractToFile($taskEntry,$taskDestination,$false)
 }
}finally{$taskProviderZip.Dispose()}
$taskSourceRows=Get-CiRows $taskSource @($taskExpected.Keys|Sort-Object -CaseSensitive)
foreach($taskRow in $taskSourceRows){if($taskExpected[$taskRow.relative] -cne $taskRow.sha256){throw 'Complete1967 original Source file hash mismatch'}}
$taskTemp=Join-Path $env:RUNNER_TEMP ('custom-message-reference-'+[Guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $taskTemp > $null
$taskVersion='v24.14.0';$taskArch=$env:RUNNER_ARCH.ToLowerInvariant()
if($taskArch -notin @('x64','arm64')){throw 'Unsupported official Linux Node architecture'}
$taskPinnedArchive=@{x64='41CD79BB7877C81605A9E68EC4C91547774F46A40C67A17E34D7179EF11729DF';arm64='E7ADFCA03D9173276114A6F2219DF1A7D25E1BFD6BBD771D3F839118A2053094'}[$taskArch]
$taskArchiveName="node-$taskVersion-linux-$taskArch.tar.xz";$taskArchive=Join-Path $taskTemp $taskArchiveName;$taskSums=Join-Path $taskTemp 'node-SHASUMS256.txt'
Invoke-WebRequest "https://nodejs.org/dist/$taskVersion/SHASUMS256.txt" -OutFile $taskSums -TimeoutSec 120
$taskPublished=@(Get-Content -LiteralPath $taskSums|Where-Object {$_ -match ('^[0-9a-f]{64}\s+'+[regex]::Escape($taskArchiveName)+'$')})
if($taskPublished.Count -ne 1 -or $taskPublished[0].Substring(0,64).ToUpperInvariant() -cne $taskPinnedArchive){throw 'Official Node checksum differs from immutable hardpin'}
Invoke-WebRequest "https://nodejs.org/dist/$taskVersion/$taskArchiveName" -OutFile $taskArchive -TimeoutSec 120
if((Get-FileHash -LiteralPath $taskArchive).Hash -cne $taskPinnedArchive){throw 'Official Linux Node archive digest mismatch'}
$taskNodePrefix="node-$taskVersion-linux-$taskArch/";$taskEntries=@(& tar -tJf $taskArchive)
if($LASTEXITCODE -ne 0 -or @($taskEntries|Where-Object {!$_.StartsWith($taskNodePrefix,[StringComparison]::Ordinal) -or $_.Split('/') -contains '..'}).Count){throw 'Official Node archive containment mismatch'}
& tar -xJf $taskArchive -C $taskTemp
if($LASTEXITCODE -ne 0){throw 'Official Node extraction failed'}
$taskNodeRoot=Join-Path $taskTemp $taskNodePrefix.TrimEnd('/');$taskNode=Join-Path $taskNodeRoot 'bin/node'
$taskNodeInventory=Get-CiInventory $taskNodeRoot
$taskContract=Join-Path $PSScriptRoot 'custom-message-reference/official-workspace-contract.json'
$taskContractData=Get-Content -LiteralPath $taskContract -Raw|ConvertFrom-Json
if($taskContractData.source_head -cne $taskHead -or $taskContractData.workspaces.Count -ne 16 -or (Get-FileHash -LiteralPath (Join-Path $taskSource 'package-lock.json')).Hash -cne $taskContractData.lock_sha256){throw 'Exact latest5ab dependency/workspace lock contract mismatch'}
$taskNpmCli=Join-Path $taskNodeRoot 'lib/node_modules/npm/bin/npm-cli.js'
$taskInstall=Invoke-CiOwnedProcess $taskNode @('--max-old-space-size=512',$taskNpmCli,'ci','--ignore-scripts','--no-audit','--no-fund','--update-notifier=false','--cache',(Join-Path $taskTemp 'npm-cache')) $taskSource (Join-Path $taskReceipt 'install-exact-locked-dependencies') 300
foreach($taskRow in $taskSourceRows){if((Get-FileHash -LiteralPath $taskRow.path).Hash -cne $taskRow.sha256){throw 'Dependency installation changed original Source file'}}
$taskReferenceInventory=Get-CustomReferenceInventory $taskSource
$taskCandidate=Get-CiInventory $taskRoot 'tree' @('.git','.zig-cache','zig-out',[IO.Path]::GetRelativePath($taskRoot,$taskReceipt).Replace('\','/'),[IO.Path]::GetRelativePath($taskRoot,$taskSource).Replace('\','/'))
$taskModuleManifest=Join-Path $taskTemp 'frozen-modules.json'
@(@($taskReferenceInventory.rows|Where-Object kind -CEQ 'file')+@($taskCandidate.rows))|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $taskModuleManifest -Encoding utf8NoBOM
$taskTempInventory=Get-CiInventory $taskTemp 'tree' @('npm-cache')
@{source_head=$taskHead;original_source_rows=$taskSourceRows;full_source_dependencies_and_links=$taskReferenceInventory;candidate_controls=$taskCandidate;official_node_tools=$taskNodeInventory;temporary_controls=$taskTempInventory;dependency_install=$taskInstall;generated_catalog_scope='Exact frozen typed fixture metadata; latest catalog remains unqualified'}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $taskReceipt 'inputs.json') -Encoding utf8NoBOM
$taskDriver=Join-Path $PSScriptRoot 'custom-message-reference/capture-custom-message.mjs';$taskObserver=Join-Path $PSScriptRoot 'custom-message-reference/observe-latest-source.mjs'
$taskInput=Join-Path $taskRoot 'src/extensions/fixtures/sdk-custom-message-5ab.input.txt';$taskGolden=Join-Path $taskRoot 'src/extensions/fixtures/sdk-custom-message-5ab.json'
$taskCaptures=@()
try {
 foreach($taskCapture in 1..2){
  $taskOutput=Join-Path $taskReceipt "original-$taskCapture.json";$taskClosure=Join-Path $taskReceipt "closure-$taskCapture.json"
  $taskOwner=Invoke-CiOwnedProcess $taskNode @('--max-old-space-size=256','--conditions=source','--experimental-transform-types','--import',([Uri]$taskObserver).AbsoluteUri,$taskDriver,$taskSource,$taskModuleManifest,$taskContract,$taskClosure,$taskInput,$taskGolden,$taskOutput) $taskSource (Join-Path $taskReceipt "owner-$taskCapture") 300
  $taskObserved=Get-Content -LiteralPath $taskOutput -Raw|ConvertFrom-Json;$taskLoaded=Get-Content -LiteralPath $taskClosure -Raw|ConvertFrom-Json
  if(!$taskObserved.matchedOriginal -or $taskObserved.cases -ne 40 -or $taskObserved.actualNode.pid -ne $taskOwner.pid -or $taskObserved.actualNode.executable -cne $taskNode -or $taskLoaded.node.pid -ne $taskOwner.pid -or $taskLoaded.exit_code -ne 0 -or !$taskLoaded.unchanged_default_loader -or $taskLoaded.post_drift.Count){throw 'Actual latest Linux Source40 identity/closure mismatch'}
  $taskSessionPath=Join-Path $taskSource 'packages/coding-agent/src/core/agent-session.ts'
  if(@($taskLoaded.records|Where-Object {$_.path -ceq $taskSessionPath -and $_.kind -ceq 'unchanged-default-module'}).Count -ne 1){throw 'Actual latest AgentSession module missing from unchanged loader closure'}
  if((Get-FileHash -LiteralPath "$taskOutput.rows.bin").Hash.ToLowerInvariant() -cne $taskObserved.rawSha256){throw 'Actual Source40 raw capture hash mismatch'}
  $taskCaptures+=@{owner=$taskOwner;raw_sha256=$taskObserved.rawSha256;output=$taskOutput;closure=$taskClosure}
 }
 if([Convert]::ToBase64String([IO.File]::ReadAllBytes($taskCaptures[0].output+'.rows.bin')) -cne [Convert]::ToBase64String([IO.File]::ReadAllBytes($taskCaptures[1].output+'.rows.bin')) -or ($taskCaptures[0].owner.pid -eq $taskCaptures[1].owner.pid -and $taskCaptures[0].owner.created_utc -ceq $taskCaptures[1].owner.created_utc)){throw 'Double fresh Source40 raw observations differ or process identity reused'}
}finally{
 Assert-CustomReferenceInventory $taskReferenceInventory (Join-Path $taskReceipt 'reference-posthash.json')
 Assert-CiInventory $taskCandidate (Join-Path $taskReceipt 'candidate-posthash.json')
 Assert-CiInventory $taskNodeInventory (Join-Path $taskReceipt 'node-tools-posthash.json')
 Assert-CiInventory $taskTempInventory (Join-Path $taskReceipt 'temporary-controls-posthash.json')
}
@{status='passed';source_head=$taskHead;source_files=1967;tracked_source_files=1924;frozen_typed_catalog_files=43;fresh_reference_processes=2;source_cases=40;raw_double_capture_equal=$true;both_equal_original_windows40=$true;node_version='v24.14.0';official_node_archive_sha256=$taskPinnedArchive;node_executable_sha256=(Get-FileHash -LiteralPath $taskNode).Hash;full_reference_entries=$taskReferenceInventory.rows.Count;full_factory_qualified=$false;latest_catalog_qualified=$false;full_pi_qualified=$false;public_activation=$false;captures=$taskCaptures;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskReceipt 'result.json') -Encoding utf8NoBOM
