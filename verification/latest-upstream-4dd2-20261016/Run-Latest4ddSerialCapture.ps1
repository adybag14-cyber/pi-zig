param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$CandidateHead,
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9-]{1,60}$')][string]$RunId,
    [Parameter(Mandatory)][string]$RootGrant
)
$ErrorActionPreference='Stop'
$taskCandidate=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$taskEvidence='C:\Users\adyba\pi-zig-update-evidence-20261003'
$taskRuns=Join-Path $taskEvidence 'latest4dd-source-captures'
$taskRun=Join-Path $taskRuns $RunId
$taskSource='C:\Users\adyba\pi-upstream-source-4dd2b149-20261016'
$taskRuntime='C:\Users\adyba\pi-upstream-runtime-19cb534-20261012'
$taskNode='C:\Program Files\nodejs\node.exe'
$taskPwsh='C:\Program Files\PowerShell\7\pwsh.exe'
$taskGit='C:\Program Files\Git\cmd\git.exe'
$taskGitActual='C:\Program Files\Git\mingw64\bin\git.exe'
$taskOwnerOriginal=Join-Path $taskEvidence 'Invoke-OwnedModelsClassSource-20261016.ps1'
$taskOwnerHash='96BEA0CF8E17535C322EE4F36C0115387386F16988BC2B98465BD070A504F5E5'
$taskLauncherHash=(Get-FileHash -LiteralPath $PSCommandPath).Hash
$taskGrant=Get-Content -LiteralPath $RootGrant -Raw|ConvertFrom-Json
if(@($taskGrant.PSObject.Properties.Name|Where-Object {$_ -notin @('authorized','manual_fresh_16gib','run_id','candidate_head','launcher_sha256','issued_utc','expires_utc','grant_id')}).Count){throw 'Root grant must contain only the documented metadata fields'}
$taskNow=[DateTimeOffset]::UtcNow
if($taskGrant.authorized -isnot [bool] -or $taskGrant.authorized -ne $true -or $taskGrant.manual_fresh_16gib -isnot [bool] -or $taskGrant.manual_fresh_16gib -ne $true -or $taskGrant.run_id -cne $RunId -or $taskGrant.candidate_head -cne $CandidateHead -or $taskGrant.launcher_sha256 -cne $taskLauncherHash -or ([DateTimeOffset]$taskGrant.expires_utc) -le $taskNow -or ([DateTimeOffset]$taskGrant.issued_utc) -gt $taskNow -or ($taskNow-([DateTimeOffset]$taskGrant.issued_utc)).TotalSeconds -gt 300){throw 'Exact fresh manual Root grant required; no owner/child started'}
if((Get-FileHash -LiteralPath $taskOwnerOriginal).Hash -cne $taskOwnerHash){throw 'Retained owner authority changed'}
if((Get-FileHash -LiteralPath $taskNode).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Pinned Node changed'}
if((& $taskGit -C $taskCandidate rev-parse HEAD).Trim() -cne $CandidateHead -or (& $taskGit -C $taskCandidate status --porcelain).Count){throw 'Exact clean candidate required'}
if(Test-Path -LiteralPath $taskRun){throw 'Refuse run-directory replay'}
foreach($taskPath in @($taskEvidence,$taskRuns)){if((Test-Path -LiteralPath $taskPath) -and ((Get-Item -LiteralPath $taskPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Owned evidence parent must not be a reparse point'}}
$taskInitialFree=(Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 3).FreePhysicalMemory
if($taskInitialFree -lt 16MB){throw 'Fresh initial16GiB admission denied'}
[void][IO.Directory]::CreateDirectory($taskRun)
foreach($taskDirectory in @('profile','profile/agent','temp','records','configs','admission')){[void][IO.Directory]::CreateDirectory((Join-Path $taskRun $taskDirectory))}
$taskOwner=Join-Path $taskRun 'Invoke-OwnedModelsClassSource-20261016.ps1'
Copy-Item -LiteralPath $taskOwnerOriginal -Destination $taskOwner
Copy-Item -LiteralPath $RootGrant -Destination (Join-Path $taskRun 'initial-root-grant.json')
@{free_kib=$taskInitialFree;required_free_kib=16MB;admitted=$true;manual_root_grant_sha256=(Get-FileHash -LiteralPath $RootGrant).Hash;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskRun 'initial-admission.json') -Encoding utf8NoBOM
$taskStart=[DateTimeOffset]::UtcNow
# 4*(300+10) +6*600 full hash +5*120 admission +120 artifact
# seal +140 controller/settlement overhead =5700s hard outer budget.
$taskDeadline=$taskStart.AddSeconds(5700)
$taskKnown=[Collections.Generic.List[object]]::new()
$taskCaseRecords=[Collections.Generic.List[object]]::new()
$taskFailures=[Collections.Generic.List[string]]::new()
$taskPhaseRecords=[Collections.Generic.List[object]]::new()
$taskCapturedArtifacts=[Collections.Generic.List[object]]::new()
$taskAccepted=$false
$taskFreeze=Join-Path $PSScriptRoot 'Freeze-Latest4ddSource.ps1'
$taskWorker=Join-Path $PSScriptRoot 'Invoke-Latest4ddPhase.ps1'
$taskManifest=Join-Path $taskRun 'full-before.json'
$taskExtra=Join-Path $taskRun 'run-controls.json'
$taskCasesPath=Join-Path $PSScriptRoot 'ordered-case-ids.json'
function Write-Json([string]$Path,$Value){ConvertTo-Json -InputObject $Value -Depth 60|Set-Content -LiteralPath $Path -Encoding utf8NoBOM}
function Budget([int]$Reserve=0){if(([DateTimeOffset]::UtcNow).AddSeconds($Reserve) -ge $taskDeadline){throw 'Outer bounded capture deadline exhausted'}}
function Identity($Row){return [ordered]@{pid=[int]$Row.ProcessId;parent_pid=[int]$Row.ParentProcessId;executable=[string]$Row.ExecutablePath;created_utc=([DateTimeOffset]$Row.CreationDate).ToUniversalTime().ToString('o');command_line=[string]$Row.CommandLine}}
function Same-Process($Expected,$Actual){
    return $Actual -and [int]$Actual.ProcessId -eq $Expected.pid -and [string]$Actual.ExecutablePath -ceq $Expected.executable -and [string]$Actual.CommandLine -ceq $Expected.command_line -and [Math]::Abs((([DateTimeOffset]$Actual.CreationDate)-([DateTimeOffset]$Expected.created_utc)).TotalMilliseconds) -le 1
}
function Remember($Identity){if(!@($taskKnown|Where-Object {$_.pid -eq $Identity.pid -and $_.created_utc -ceq $Identity.created_utc}).Count){$taskKnown.Add($Identity)}}
function Observe-Descendants([int]$RootPid){
    $taskAll=@(Get-CimInstance Win32_Process -OperationTimeoutSec 3)
    $taskParents=[Collections.Generic.HashSet[int]]::new()
    foreach($taskKnownRow in $taskKnown){$taskLive=@($taskAll|Where-Object ProcessId -eq $taskKnownRow.pid);if($taskLive.Count -eq 1 -and (Same-Process $taskKnownRow $taskLive[0])){[void]$taskParents.Add($taskKnownRow.pid)}}
    for($taskDepth=0;$taskDepth -lt 8;$taskDepth++){
        $taskAdded=$false
        foreach($taskRow in $taskAll){
            if($taskParents.Contains([int]$taskRow.ParentProcessId) -and !$taskParents.Contains([int]$taskRow.ProcessId) -and ([DateTimeOffset]$taskRow.CreationDate) -ge $taskStart){
                $taskIdentity=Identity $taskRow
                if(!$taskIdentity.executable -or !$taskIdentity.command_line){throw 'Owned descendant identity incomplete'}
                Remember $taskIdentity;[void]$taskParents.Add($taskIdentity.pid);$taskAdded=$true
            }
        }
        if(!$taskAdded){break}
    }
}
function Stop-Verified($Expected){
    $taskLive=Get-CimInstance Win32_Process -Filter "ProcessId=$($Expected.pid)" -OperationTimeoutSec 3 -ErrorAction SilentlyContinue
    if(!($taskLive)){return}
    if(!(Same-Process $Expected $taskLive)){return} # Original identity absent; preserve reused PID.
    if($Expected.executable -cnotin @($taskPwsh,$taskNode,$taskGit,$taskGitActual) -or $Expected.executable -match 'codex'){throw 'Unapproved descendant executable preserved'}
    $taskHandle=[Diagnostics.Process]::GetProcessById($Expected.pid)
    try{$taskHandle.Kill($false);if(!$taskHandle.WaitForExit(10000)){throw 'Verified owned root failed10s settlement'}}finally{$taskHandle.Dispose()}
}
function Absence([string]$Label){
    $taskAll=@(Get-CimInstance Win32_Process -OperationTimeoutSec 3)
    $taskRows=@(foreach($taskExpected in $taskKnown){
        $taskLive=$taskAll|Where-Object ProcessId -eq $taskExpected.pid|Select-Object -First 1
        $taskPresent=Same-Process $taskExpected $taskLive
        @{identity=$taskExpected;original_identity_absent=!$taskPresent;pid_reused=($taskLive -and !$taskPresent)}
    })
    Write-Json (Join-Path $taskRun ($Label+'-independent-absence.json')) @{rows=$taskRows;present=@($taskRows|Where-Object {!$_.original_identity_absent}).Count;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
    if(@($taskRows|Where-Object {!$_.original_identity_absent}).Count){throw 'Owned process/observed descendant still present; no handoff'}
}
function Child-Environment {
    # No caller environment is inherited by phase workers or Node. These are
    # the complete allowlist; no actual credential values are read or logged.
    return @{
        SystemRoot='C:\Windows';WINDIR='C:\Windows';ComSpec='C:\Windows\System32\cmd.exe';
        PATH='C:\Windows\System32;C:\Windows;C:\Program Files\PowerShell\7;C:\Program Files\Git\cmd;C:\Program Files\nodejs';
        PATHEXT='.EXE';
        TEMP=(Join-Path $taskRun 'temp');TMP=(Join-Path $taskRun 'temp');
        HOME=(Join-Path $taskRun 'profile');USERPROFILE=(Join-Path $taskRun 'profile');
        HOMEDRIVE='C:';HOMEPATH=((Join-Path $taskRun 'profile').Substring(2));
        APPDATA=(Join-Path $taskRun 'profile');LOCALAPPDATA=(Join-Path $taskRun 'profile');
        PI_CODING_AGENT_DIR=(Join-Path $taskRun 'profile/agent');
        NO_COLOR='1';POWERSHELL_TELEMETRY_OPTOUT='1';POWERSHELL_UPDATECHECK='Off'
    }
}
function Phase([string]$Label,[string]$Config,[int]$Seconds){
    Budget ($Seconds+$(if($Label -in @('final','artifact-seal')){15}else{800}))
    $taskInfo=[Diagnostics.ProcessStartInfo]::new()
    $taskInfo.FileName=$taskPwsh;$taskInfo.WorkingDirectory=$taskRun
    $taskInfo.UseShellExecute=$false;$taskInfo.CreateNoWindow=$true
    $taskInfo.RedirectStandardOutput=$true;$taskInfo.RedirectStandardError=$true
    $taskInfo.Environment.Clear()
    $taskSafe=Child-Environment
    foreach($taskName in $taskSafe.Keys){$taskInfo.Environment[$taskName]=[string]$taskSafe[$taskName]}
    foreach($taskArgument in @('-NoLogo','-NoProfile','-NonInteractive','-File',$taskWorker,'-Config',$Config,'-ConfigSha256',(Get-FileHash -LiteralPath $Config).Hash)){$taskInfo.ArgumentList.Add($taskArgument)}
    $taskProcess=[Diagnostics.Process]::new();$taskProcess.StartInfo=$taskInfo
    if(!$taskProcess.Start()){throw 'Owned phase worker did not start'}
    $taskOut=$taskProcess.StandardOutput.ReadToEndAsync();$taskErr=$taskProcess.StandardError.ReadToEndAsync()
    $taskCreated=$taskProcess.StartTime.ToUniversalTime()
    $taskLive=Get-CimInstance Win32_Process -Filter "ProcessId=$($taskProcess.Id)" -OperationTimeoutSec 3 -ErrorAction SilentlyContinue
    $taskExpected=if($taskLive){Identity $taskLive}else{@{pid=$taskProcess.Id;parent_pid=$PID;executable=$taskPwsh;created_utc=$taskCreated.ToString('o');command_line=$taskPwsh+' '+($taskInfo.ArgumentList -join ' ')}}
    Remember $taskExpected
    $taskPhaseDeadline=[DateTimeOffset]::UtcNow.AddSeconds($Seconds)
    $taskTimedOut=$false
    try{
        while(!$taskProcess.WaitForExit(200)){
            Observe-Descendants $taskProcess.Id
            if([DateTimeOffset]::UtcNow -ge $taskPhaseDeadline -or [DateTimeOffset]::UtcNow -ge $taskDeadline){$taskTimedOut=$true;break}
        }
        if($taskTimedOut){
            # Descendants are stopped individually only after exact ownership
            # revalidation, with no tree/name kill or C9 process authority.
            foreach($taskOwned in @($taskKnown|Sort-Object created_utc -Descending)){if($taskOwned.pid -ne $taskExpected.pid){Stop-Verified $taskOwned}}
            Stop-Verified $taskExpected
        }
        if(!$taskProcess.HasExited){throw 'Phase worker terminal state unavailable'}
        if(!$taskOut.Wait(5000) -or !$taskErr.Wait(5000)){throw 'Owned pipes did not settle within5s'}
        [IO.File]::WriteAllText((Join-Path $taskRun ($Label+'.stdout.log')),$taskOut.Result)
        [IO.File]::WriteAllText((Join-Path $taskRun ($Label+'.stderr.log')),$taskErr.Result)
        $taskRecord=@{label=$Label;identity=$taskExpected;exit_code=$taskProcess.ExitCode;timed_out=$taskTimedOut;budget_seconds=$Seconds;terminal=$taskProcess.HasExited;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
        $taskPhaseRecords.Add($taskRecord);Write-Json (Join-Path $taskRun ($Label+'-phase.json')) $taskRecord
        if($taskTimedOut -or $taskProcess.ExitCode -ne 0){throw "Owned phase negative: $Label"}
    }finally{$taskProcess.Dispose()}
}
function Hash-Phase([string]$Label,[string]$Config){Phase $Label $Config 600}
function Admission([string]$Kind){
    Budget 920
    $taskNonce=[Guid]::NewGuid().ToString('N')
    $taskRequest=Join-Path $taskRun ('admission/'+$Kind+'.request.json')
    $taskApproval=Join-Path $taskRun ('admission/'+$Kind+'.approval.json')
    if(Test-Path -LiteralPath $taskApproval){throw 'Approval must follow this fresh request'}
    Write-Json $taskRequest @{status='paused_pending_root';kind=$Kind;nonce=$taskNonce;run_id=$RunId;candidate_head=$CandidateHead;launcher_sha256=$taskLauncherHash;required_free_kib=16MB;expires_utc=[DateTimeOffset]::UtcNow.AddSeconds(120).ToString('o')}
    Write-Output "PAUSED_ROOT_ADMISSION $taskApproval NONCE=$taskNonce"
    $taskUntil=[DateTimeOffset]::UtcNow.AddSeconds(120)
    while(!(Test-Path -LiteralPath $taskApproval)){if([DateTimeOffset]::UtcNow -ge $taskUntil){throw "No Root admission for $Kind"};Start-Sleep -Milliseconds 250}
    $taskPermit=Get-Content -LiteralPath $taskApproval -Raw|ConvertFrom-Json
    if($taskPermit.approved -isnot [bool] -or $taskPermit.approved -ne $true -or $taskPermit.nonce -cne $taskNonce -or $taskPermit.kind -cne $Kind -or $taskPermit.run_id -cne $RunId -or $taskPermit.candidate_head -cne $CandidateHead){throw 'Root admission identity mismatch'}
    $taskFree=(Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 3).FreePhysicalMemory
    Write-Json (Join-Path $taskRun ('admission/'+$Kind+'.reservation.json')) @{kind=$Kind;nonce=$taskNonce;free_kib=$taskFree;required_free_kib=16MB;source_reserved_kib=2MB;heap_mb=256;approved_sha256=(Get-FileHash -LiteralPath $taskApproval).Hash;observed_utc=[DateTimeOffset]::UtcNow.ToString('o');admitted=($taskFree -ge 16MB)}
    if($taskFree -lt 16MB){throw 'Automatic fresh16GiB admission denied'}
    foreach($taskPath in @($taskRequest,$taskApproval,(Join-Path $taskRun ('admission/'+$Kind+'.reservation.json')))){$taskCapturedArtifacts.Add(@{path=$taskPath;sha256=(Get-FileHash -LiteralPath $taskPath).Hash})}
}
try{
$taskCaseIds=@((Get-Content -LiteralPath $taskCasesPath -Raw|ConvertFrom-Json).cases)
if($taskCaseIds.Count -ne 273 -or @($taskCaseIds.caseId|Select-Object -Unique).Count -ne 273){throw 'Exact ordered273 caller IDs required'}
$taskSpecs=@(
    @{kind='summary30';count=30;driver='verification/latest-upstream-4dd2-20261016/summary-source-capture.mjs';input='src/extensions/fixtures/sdk-summary-latest4dd.input.txt'},
    @{kind='summary45';count=45;driver='verification/latest-upstream-4dd2-20261016/summary-original45-source-capture.mjs';input='src/extensions/fixtures/sdk-summary-generation-b45.input.txt'},
    @{kind='openai52';count=52;driver='verification/openai-tool-output4dd-prepared-20261016/capture-primary-tool-output.mjs';input='verification/openai-tool-output4dd-prepared-20261016/primary-tool-callers.mjs'},
    @{kind='google';count=146;driver='verification/google-tool-output4dd-prepared-20261016/capture-primary-tool-output.mjs';input='verification/google-tool-output4dd-prepared-20261016/primary-tool-callers.mjs'}
)
$taskAdditional=[Collections.Generic.List[object]]::new()
foreach($taskPath in @($taskOwner,(Join-Path $taskRun 'initial-root-grant.json'),(Join-Path $taskRun 'initial-admission.json'),$taskPwsh,$taskGit,$taskGitActual,$taskCasesPath)){$taskAdditional.Add(@{path=$taskPath;sha256=(Get-FileHash -LiteralPath $taskPath).Hash})}
$taskSafe=Child-Environment
Write-Json (Join-Path $taskRun 'environment-policy.json') @{inheritance='ProcessStartInfo.Environment.Clear';allowed_names=@($taskSafe.Keys|Sort-Object);runtime_generated_allowed_names=@('PSModulePath');credential_values_read=$false;all_other_names_absent=$true;profile=(Join-Path $taskRun 'profile');temp=(Join-Path $taskRun 'temp');agent=(Join-Path $taskRun 'profile/agent');network_policy='deny capture network entrypoints; Node native permission model disallows child/worker/addon and fs writes outside owned run'}
$taskAdditional.Add(@{path=(Join-Path $taskRun 'environment-policy.json');sha256=(Get-FileHash -LiteralPath (Join-Path $taskRun 'environment-policy.json')).Hash})
$taskHashConfigs=@{}
foreach($taskLabel in @('before','after-summary30','after-summary45','after-openai52','after-google','final')){
    $taskPath=Join-Path $taskRun ('configs/'+$taskLabel+'.json')
    Write-Json $taskPath @{mode='hash';candidate_head=$CandidateHead;freeze=$taskFreeze;manifest=$taskManifest;receipt=(Join-Path $taskRun ($taskLabel+'-fullhash.json'));phase=if($taskLabel -eq 'before'){'before'}else{'post'};additional_controls=$taskExtra}
    $taskHashConfigs[$taskLabel]=$taskPath;$taskAdditional.Add(@{path=$taskPath;sha256=(Get-FileHash -LiteralPath $taskPath).Hash})
}
foreach($taskSpec in $taskSpecs){
    $taskSpec.output=Join-Path $taskRun ($taskSpec.kind+'-raw-source.json')
    $taskSpec.config=Join-Path $taskRun ('configs/'+$taskSpec.kind+'.json')
    $taskSpec.name='latest4dd-'+$RunId+'-'+$taskSpec.kind
    if(Test-Path -LiteralPath $taskSpec.output){throw 'Raw capture output must be absent'}
    $taskEnv=@{};foreach($taskKey in $taskSafe.Keys){$taskEnv[$taskKey]=$taskSafe[$taskKey]}
    $taskEnv.PI_SOURCE_ORACLE_CONTROL_MANIFEST=$taskManifest+'.controls.json';$taskEnv.PI_LATEST_CAPTURE_KIND=$taskSpec.kind;$taskEnv.PI_LATEST_CAPTURE_RECORD_DIR=Join-Path $taskRun 'records'
    $taskArguments=@('--max-old-space-size=256','--permission',('--allow-fs-read='+$taskCandidate),('--allow-fs-read='+$taskSource),('--allow-fs-read='+$taskRuntime),('--allow-fs-read='+$taskRun),('--allow-fs-write='+$taskRun),'--conditions=source','--experimental-transform-types','--import',([Uri](Join-Path $PSScriptRoot 'source-network-guard.mjs')).AbsoluteUri,'--import',([Uri](Join-Path $PSScriptRoot 'source-observe.mjs')).AbsoluteUri,(Join-Path $taskCandidate $taskSpec.driver),$taskSpec.output)
    if($taskSpec.kind -in @('summary30','summary45')){$taskArguments+=Join-Path $taskCandidate $taskSpec.input}
    Write-Json $taskSpec.config @{mode='node';candidate_head=$CandidateHead;owner=$taskOwner;name=$taskSpec.name;node=$taskNode;working_directory=(Join-Path $taskRun 'profile');arguments=$taskArguments;environment=$taskEnv}
    $taskAdditional.Add(@{path=$taskSpec.config;sha256=(Get-FileHash -LiteralPath $taskSpec.config).Hash})
}
Write-Json $taskExtra $taskAdditional.ToArray()
$taskOuterLive=Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -OperationTimeoutSec 3
if(!$taskOuterLive.ExecutablePath -or !$taskOuterLive.CommandLine){throw 'Outer identity unavailable'}
Write-Json (Join-Path $taskRun 'outer-owner.json') @{identity=(Identity $taskOuterLive);run_id=$RunId;candidate_head=$CandidateHead;launcher_sha256=$taskLauncherHash;start_utc=$taskStart.ToString('o');deadline_utc=$taskDeadline.ToString('o');maximum_seconds=5700;status='running';expected_files_created=$false}
$taskExpectedPaths=@('sdk-summary-latest4dd.expected.json','sdk-summary-original45-latest4dd.expected.json','ai-openai-tool-output4dd.expected.json','ai-google-tool-output4dd.expected.json')|ForEach-Object {Join-Path $taskCandidate ('src/extensions/fixtures/'+$_)}
Write-Json (Join-Path $taskRun 'expected-absence-before.json') @{paths=@($taskExpectedPaths);present=@($taskExpectedPaths|Where-Object {Test-Path -LiteralPath $_});observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
if(@($taskExpectedPaths|Where-Object {Test-Path -LiteralPath $_}).Count){throw 'New expected Source destinations must be absent'}
    Hash-Phase 'before' $taskHashConfigs.before
    foreach($taskSpec in $taskSpecs){
        Admission $taskSpec.kind
        $taskNodeFailure=$null
        try{Phase $taskSpec.kind $taskSpec.config 320}catch{$taskNodeFailure=$_.Exception.Message;$taskFailures.Add('Node first negative: '+$taskNodeFailure)}finally{
            $taskOwnerRecord=Join-Path $taskRun ($taskSpec.name+'.json')
            if(Test-Path -LiteralPath $taskOwnerRecord){$taskNodeRecord=Get-Content -LiteralPath $taskOwnerRecord -Raw|ConvertFrom-Json;Remember @{pid=[int]$taskNodeRecord.pid;parent_pid=0;executable=$taskNodeRecord.executable;created_utc=$taskNodeRecord.created_utc;command_line=$taskNodeRecord.command_line}}
            try{Hash-Phase ('after-'+$taskSpec.kind) $taskHashConfigs[('after-'+$taskSpec.kind)]}catch{$taskFailures.Add('Between full hash negative: '+$_.Exception.Message);if(!$taskNodeFailure){throw}}
        }
        if($taskNodeFailure){throw $taskNodeFailure}
        Absence $taskSpec.kind
        $taskResult=Get-Content -LiteralPath $taskSpec.output -Raw|ConvertFrom-Json
        if($taskResult.sourceHead -cne '4dd2b149d155d7369de16ea4dc77c84e9f5ffb24' -or $taskResult.actualNode.version -cne 'v24.14.0' -or [int]$taskResult.actualNode.pid -ne [int]$taskNodeRecord.pid -or $taskResult.actualNode.execPath -ine $taskNode){throw 'Actual Source/Node result identity mismatch'}
        $taskRows=if($taskSpec.kind -in @('summary30','summary45')){@($taskResult.rows)}else{@($taskResult.observations)}
        $taskExpected=@($taskCaseIds|Where-Object kind -eq $taskSpec.kind)
        if($taskRows.Count -ne $taskSpec.count -or $taskExpected.Count -ne $taskSpec.count){throw 'Original record count mismatch'}
        $taskScriptHash=(Get-FileHash -LiteralPath (Join-Path $taskCandidate $taskSpec.driver)).Hash
        $taskInputHash=(Get-FileHash -LiteralPath (Join-Path $taskCandidate $taskSpec.input)).Hash
        if($taskResult.inputSha256 -and ([string]$taskResult.inputSha256).ToUpperInvariant() -cne $taskInputHash){throw 'Actual input SHA mismatch'}
        if($taskResult.callerSha256 -and ([string]$taskResult.callerSha256).ToUpperInvariant() -cne $taskInputHash){throw 'Actual caller SHA mismatch'}
        for($taskIndex=0;$taskIndex -lt $taskRows.Count;$taskIndex++){
            foreach($taskSelector in $taskExpected[$taskIndex].selector.PSObject.Properties){if((ConvertTo-Json -InputObject $taskRows[$taskIndex].($taskSelector.Name) -Compress) -cne (ConvertTo-Json -InputObject $taskSelector.Value -Compress)){throw 'Ordered caller ID/selector mismatch'}}
            $taskCaseRecords.Add(@{caseId=$taskExpected[$taskIndex].caseId;kind=$taskSpec.kind;index=$taskIndex;script_sha256=$taskScriptHash;input_sha256=$taskInputHash;observation=$taskRows[$taskIndex]})
        }
        $taskNodePid=[int]$taskNodeRecord.pid
        $taskClosure=Get-Content -LiteralPath (Join-Path $taskRun ('records/source4dd2-closure-'+$taskNodePid+'-0-20261016.json')) -Raw|ConvertFrom-Json
        $taskNetwork=Get-Content -LiteralPath (Join-Path $taskRun ('records/network-'+$taskNodePid+'.json')) -Raw|ConvertFrom-Json
        $taskEnvironmentReceipt=Get-Content -LiteralPath (Join-Path $taskRun ('records/environment-'+$taskNodePid+'.json')) -Raw|ConvertFrom-Json
        if($taskClosure.captureKind -cne $taskSpec.kind -or [int]$taskClosure.pid -ne $taskNodePid -or !$taskClosure.allObservedFilesFrozen -or $taskClosure.oldRuntimeSourceFallback -or @($taskNetwork.attempts).Count -ne 0 -or $taskNetwork.networkRequests -ne 0 -or !$taskEnvironmentReceipt.allowlistMatched -or !$taskEnvironmentReceipt.ownedProfileTempAgent -or $taskEnvironmentReceipt.credentialValuesRecorded){throw 'Closure, environment or no-network receipt mismatch'}
        foreach($taskPath in @($taskSpec.output,$taskOwnerRecord)+@(Get-ChildItem -LiteralPath (Join-Path $taskRun 'records') -File|Where-Object {$_.Name -match ('(^source4dd2-(modules|closure)-'+$taskNodePid+'-)|(^(network|environment)-'+$taskNodePid+'\.json$)')}|ForEach-Object{$_.FullName})){$taskCapturedArtifacts.Add(@{path=$taskPath;sha256=(Get-FileHash -LiteralPath $taskPath).Hash})}
        Write-Json (Join-Path $taskRun ($taskSpec.kind+'-probe-complete.json')) @{kind=$taskSpec.kind;count=$taskRows.Count;source_output_sha256=(Get-FileHash -LiteralPath $taskSpec.output).Hash;script_sha256=(Get-FileHash -LiteralPath (Join-Path $taskCandidate $taskSpec.driver)).Hash;input_sha256=(Get-FileHash -LiteralPath (Join-Path $taskCandidate $taskSpec.input)).Hash;node_pid=$taskNodePid;status='terminal0_fullpost0_pending_final_review'}
    }
    if($taskCaseRecords.Count -ne 273){throw 'All273 original ordered records required'}
    Write-Json (Join-Path $taskRun 'all273-original-observations.json') @{cases=$taskCaseRecords.ToArray();count=273;purpose='Raw genuine Source capture artifact; not an accepted expected fixture'}
    $taskCapturedArtifacts.Add(@{path=(Join-Path $taskRun 'all273-original-observations.json');sha256=(Get-FileHash -LiteralPath (Join-Path $taskRun 'all273-original-observations.json')).Hash})
    Admission 'acceptance'
    $taskAccepted=$true
}catch{$taskFailures.Add($_.Exception.Message)}finally{
    try{
        if(!$taskHashConfigs -or !$taskHashConfigs.final -or !(Test-Path -LiteralPath $taskManifest)){
            $taskFallback=Join-Path $taskRun 'configs/final-fallback.json'
            Write-Json $taskFallback @{mode='hash';candidate_head=$CandidateHead;freeze=$taskFreeze;manifest=if(Test-Path -LiteralPath $taskManifest){$taskManifest}else{Join-Path $taskRun 'final-unmatched.json'};receipt=(Join-Path $taskRun 'final-fullhash.json');phase=if(Test-Path -LiteralPath $taskManifest){'post'}else{'before'};additional_controls=$null}
            Hash-Phase 'final' $taskFallback
            $taskFailures.Add('Initial full freeze unavailable; final fallback is not a matching qualification')
        }else{Hash-Phase 'final' $taskHashConfigs.final}
    }catch{$taskFailures.Add('Final full hash negative: '+$_.Exception.Message)}
    $taskExpectedPresent=@($taskExpectedPaths|Where-Object {Test-Path -LiteralPath $_})
    Write-Json (Join-Path $taskRun 'expected-absence-final.json') @{paths=@($taskExpectedPaths);present=$taskExpectedPresent;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
    if($taskExpectedPresent.Count){$taskFailures.Add('Expected Source files appeared during capture')}
    try{Absence 'final'}catch{$taskFailures.Add('Final independent absence negative: '+$_.Exception.Message)}
    try{
        $taskCapturedPath=Join-Path $taskRun 'captured-artifact-freeze.json';Write-Json $taskCapturedPath $taskCapturedArtifacts.ToArray()
        $taskSealConfig=Join-Path $taskRun 'configs/artifact-seal.json'
        Write-Json $taskSealConfig @{mode='artifacts';run=$taskRun;captured=$taskCapturedPath}
        Phase 'artifact-seal' $taskSealConfig 120
        Absence 'artifact-seal'
    }catch{$taskFailures.Add('Artifact seal/absence negative: '+$_.Exception.Message)}
    Write-Json (Join-Path $taskRun 'terminal.json') @{status=if($taskAccepted -and !$taskFailures.Count){'captured_pending_root_expected_review'}else{'negative'};failures=$taskFailures.ToArray();records=$taskCaseRecords.Count;candidate_head=$CandidateHead;launcher_sha256=$taskLauncherHash;known_owned_identities=$taskKnown.ToArray();phases=$taskPhaseRecords.ToArray();expected_files_created=$false;handoff='requires external supervisor confirmation of outer identity absence';deadline_utc=$taskDeadline.ToString('o');completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
}
if($taskFailures.Count -or !$taskAccepted){throw 'Latest Source serial capture negative; retained full packet; no acceptance/handoff'}
Write-Output 'LATEST4DD_RAW273_CAPTURED_PENDING_ROOT_EXPECTED_REVIEW'
