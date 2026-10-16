param([string]$Attempt='review1')
$ErrorActionPreference='Stop'
$taskCandidate=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskEvidence='C:\Users\adyba\pi-zig-update-evidence-20261003'
$taskName="async-function-body-node24-source42-$Attempt-20261016"
$taskNode='C:\Program Files\nodejs\node.exe'
$taskNodeManifest=Join-Path $taskEvidence 'source4954-node-tools-before-20261015.json'
$taskCompilerManifest=Join-Path $taskEvidence 'auth-storage-production-4954-source47-first-20261015-compiler-before.json'
$taskDriver=Join-Path $PSScriptRoot 'capture-native-async-function-node24.mjs'
$taskObserver=Join-Path $PSScriptRoot 'observe-native-async-function-node24.mjs'
$taskInput=Join-Path $taskCandidate 'src\extensions\fixtures\async-function-body-node24.input.txt'
$taskExpected=Join-Path $taskCandidate 'src\extensions\fixtures\async-function-body-node24.json'
$taskOutput=Join-Path $taskEvidence "$taskName-output.json"
$taskModules=Join-Path $taskEvidence "$taskName-modules.jsonl"
if($Attempt -notmatch '^[a-zA-Z0-9_-]+$'){throw 'Invalid attempt identifier'}
foreach($taskPath in @($taskOutput,$taskModules,$taskExpected,(Join-Path $taskEvidence "$taskName-before.json"))){if(Test-Path -LiteralPath $taskPath){throw "Refuse capture replay $taskPath"}}
function Write-Json($path,$value){$value|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $path -Encoding utf8NoBOM}
function File-Rows($paths){@($paths|ForEach-Object {@{path=[IO.Path]::GetFullPath($_);sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash}})}
function Drift($rows){@($rows|Where-Object {!(Test-Path -LiteralPath $_.path -PathType Leaf) -or (Get-FileHash -LiteralPath $_.path -Algorithm SHA256).Hash -cne $_.sha256}|ForEach-Object path)}
function Admit($phase){
 $taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
 Write-Json (Join-Path $taskEvidence "$taskName-$phase-admission.json") @{free_kib=$taskFree;required_kib=2MB;heap_mb=256;granted_lane='LIGHT6';phase=$phase;admitted=($taskFree -ge 2MB);utc=[DateTimeOffset]::UtcNow.ToString('o')}
 if($taskFree -lt 2MB){throw 'Source42 admission denied: less than 2 GiB available'}
}
function Run-Node($phase,$arguments){
 $taskState=Join-Path $taskEvidence "$taskName-$phase.json"
 if(Test-Path -LiteralPath $taskState){throw 'Refuse owner record replay'}
 Admit $phase
 $taskStart=[Diagnostics.ProcessStartInfo]::new()
 $taskStart.FileName=$taskNode;$taskStart.WorkingDirectory=$taskCandidate
 $taskStart.UseShellExecute=$false;$taskStart.CreateNoWindow=$true
 $taskStart.RedirectStandardOutput=$true;$taskStart.RedirectStandardError=$true
 foreach($taskArg in @('--max-old-space-size=256')+$arguments){$taskStart.ArgumentList.Add($taskArg)}
 foreach($taskKey in @('NODE_OPTIONS','NODE_PATH','NODE_USE_ENV_PROXY','HTTP_PROXY','HTTPS_PROXY','ALL_PROXY')){$taskStart.Environment[$taskKey]=''}
 $taskStart.Environment['PI_ASYNC_SOURCE_CONTROLS']=Join-Path $taskEvidence "$taskName-controls-before.json"
 $taskStart.Environment['PI_ASYNC_SOURCE_MODULE_LOG']=$taskModules
 $taskProcess=[Diagnostics.Process]::new();$taskProcess.StartInfo=$taskStart
 if(!$taskProcess.Start()){throw 'Node Source42 failed to start'}
 $taskCreated=$taskProcess.StartTime.ToUniversalTime()
 $taskLiveAtLaunch=Get-CimInstance Win32_Process -Filter "ProcessId = $($taskProcess.Id)"
 $taskRecord=[ordered]@{phase=$phase;pid=$taskProcess.Id;executable=$taskNode;executable_sha256=(Get-FileHash -LiteralPath $taskNode).Hash;created_utc=$taskCreated.ToString('o');argv=@($taskStart.ArgumentList);command_line=if($taskLiveAtLaunch){$taskLiveAtLaunch.CommandLine}else{$null};identity_source='retained kernel process handle PID/starttime and exact native argv; live CIM when available';status='running';timeout_seconds=300}
 Write-Json $taskState $taskRecord
 $taskOut=$taskProcess.StandardOutput.ReadToEndAsync();$taskErr=$taskProcess.StandardError.ReadToEndAsync()
 $taskFinished=$taskProcess.WaitForExit(300000)
 if(!$taskFinished){
  $taskLive=Get-CimInstance Win32_Process -Filter "ProcessId = $($taskProcess.Id)"
  if(!$taskLive -or $taskLive.ExecutablePath -cne $taskNode -or ([DateTimeOffset]$taskLive.CreationDate).UtcDateTime -ne $taskCreated -or $taskLive.ExecutablePath -match 'codex'){throw 'Source timeout process identity mismatch'}
  if($taskLiveAtLaunch -and $taskLive.CommandLine -cne $taskLiveAtLaunch.CommandLine){throw 'Source timeout command line identity mismatch'}
  $taskProcess.Kill();if(!$taskProcess.WaitForExit(10000)){throw 'Owned Node did not terminate'}
 }
 [IO.File]::WriteAllText((Join-Path $taskEvidence "$taskName-$phase.stdout.log"),$taskOut.GetAwaiter().GetResult())
 [IO.File]::WriteAllText((Join-Path $taskEvidence "$taskName-$phase.stderr.log"),$taskErr.GetAwaiter().GetResult())
 $taskRecord.exit_code=$taskProcess.ExitCode;$taskRecord.status=if(!$taskFinished){'timed_out'}elseif($taskProcess.ExitCode -eq 0){'passed'}else{'failed'}
 $taskRecord.completed_utc=[DateTimeOffset]::UtcNow.ToString('o');$taskRecord.handle_has_exited=$taskProcess.HasExited
 $taskAfter=Get-CimInstance Win32_Process -Filter "ProcessId = $($taskProcess.Id)"
 $taskRecord.original_identity_absent=(!$taskAfter -or ([DateTimeOffset]$taskAfter.CreationDate).UtcDateTime -ne $taskCreated)
 Write-Json $taskState $taskRecord
 $taskProcess.Dispose()
 if($taskRecord.status -cne 'passed' -or !$taskRecord.original_identity_absent){throw "Source42 $phase terminal $($taskRecord.status)"}
}
$taskNodeRows=@(Get-Content -LiteralPath $taskNodeManifest -Raw|ConvertFrom-Json)
$taskCompilerRows=@(Get-Content -LiteralPath $taskCompilerManifest -Raw|ConvertFrom-Json)
if($taskNodeRows.Count -ne 1774 -or $taskCompilerRows.Count -ne 19546){throw 'Full pinned tool inventory count changed'}
if(@(Drift $taskNodeRows).Count -or @(Drift $taskCompilerRows).Count){throw 'Pinned Node/compiler prehash drift'}
if((Get-FileHash -LiteralPath $taskNode).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Pinned Node executable changed'}
$taskHead=(git -C $taskCandidate rev-parse HEAD)
$taskNames=@(git -C $taskCandidate ls-files -c -o --exclude-standard)
if($LASTEXITCODE -ne 0){throw 'Candidate inventory failed'}
$taskCandidateRows=File-Rows @($taskNames|ForEach-Object {Join-Path $taskCandidate $_})
$taskControls=File-Rows @($taskDriver,$taskObserver,$taskInput,$PSCommandPath,$taskNodeManifest,$taskCompilerManifest)
Write-Json (Join-Path $taskEvidence "$taskName-candidate-before.json") $taskCandidateRows
Write-Json (Join-Path $taskEvidence "$taskName-controls-before.json") $taskControls
$taskManifestPath=Join-Path $taskEvidence "$taskName-controls-before.json"
$taskManifestHash=(Get-FileHash -LiteralPath $taskManifestPath).Hash
Write-Json (Join-Path $taskEvidence "$taskName-before.json") @{candidate_head=$taskHead;candidate_files=$taskCandidateRows.Count;node_files=$taskNodeRows.Count;compiler_files=$taskCompilerRows.Count;compiler_executed=$false;source_dependencies='Node builtins only; no upstream source or external package substitution';controls=$taskControls;native_executed=$false;utc=[DateTimeOffset]::UtcNow.ToString('o')}
$taskRunFailure=$null
try{
 Run-Node 'driver-syntax' @('--check',$taskDriver)
 Run-Node 'observer-syntax' @('--check',$taskObserver)
 Run-Node 'capture' @('--expose-gc','--import',([Uri]$taskObserver).AbsoluteUri,$taskDriver,$taskOutput,$taskInput)
}catch{$taskRunFailure=$_.Exception.Message}
$taskCandidateDrift=@(Drift $taskCandidateRows)
$taskNodeDrift=@(Drift $taskNodeRows);$taskCompilerDrift=@(Drift $taskCompilerRows);$taskControlDrift=@(Drift $taskControls)
$taskAfterNames=@(git -C $taskCandidate ls-files -c -o --exclude-standard)
$taskInventoryDrift=@(Compare-Object $taskNames $taskAfterNames)
$taskManifestDrift=(Get-FileHash -LiteralPath $taskManifestPath).Hash -cne $taskManifestHash
$taskHeadDrift=(git -C $taskCandidate rev-parse HEAD) -cne $taskHead
Write-Json (Join-Path $taskEvidence "$taskName-posthash.json") @{candidate_files=$taskCandidateRows.Count;node_files=$taskNodeRows.Count;compiler_files=$taskCompilerRows.Count;candidate_drift=$taskCandidateDrift;candidate_inventory_drift=$taskInventoryDrift;node_drift=$taskNodeDrift;compiler_drift=$taskCompilerDrift;control_drift=$taskControlDrift;control_manifest_drift=$taskManifestDrift;head_drift=$taskHeadDrift;run_failure=$taskRunFailure;native_executed=$false;utc=[DateTimeOffset]::UtcNow.ToString('o')}
if($taskRunFailure){throw $taskRunFailure}
if($taskCandidateDrift.Count -or $taskInventoryDrift.Count -or $taskNodeDrift.Count -or $taskCompilerDrift.Count -or $taskControlDrift.Count -or $taskManifestDrift -or $taskHeadDrift){throw 'Source42 posthash drift'}
$taskResult=Get-Content -LiteralPath $taskOutput -Raw|ConvertFrom-Json
if($taskResult.runtime -cne 'v24.14.0' -or $taskResult.count -ne 42 -or @($taskResult.rows).Count -ne 42 -or @($taskResult.rows.name|Sort-Object -Unique).Count -ne 42){throw 'Genuine Source42 result incomplete'}
$taskObserved=@(Get-Content -LiteralPath $taskModules|ForEach-Object {$_|ConvertFrom-Json})
if($taskObserved.Count -ne 2){throw 'Expected exactly driver and observer file modules; all dependencies builtin'}
Copy-Item -LiteralPath $taskOutput -Destination $taskExpected
Write-Json (Join-Path $taskEvidence "$taskName-validation.json") @{source_cases=42;runtime=$taskResult.runtime;expected_sha256=(Get-FileHash -LiteralPath $taskExpected).Hash;expected_published_after_terminal_and_full_posthash=$true;actual_observed_file_modules=$taskObserved;native_executed=$false;native_qualified=$false;full_pi_qualified=$false}
Write-Output 'GENUINE_NODE24_ASYNC_FUNCTION_SOURCE42_CAPTURED_POSTHASH_ZERO_DRIFT'
