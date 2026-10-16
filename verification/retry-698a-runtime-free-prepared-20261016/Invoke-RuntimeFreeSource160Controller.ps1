param([Parameter(Mandatory)][string]$Config,[Parameter(Mandatory)][string]$ConfigSha256)
. ($PSScriptRoot+'\RuntimeFreeSource160.Common.ps1')
Initialize-S160OwnedChild $PSCommandPath
if((Get-S160Sha $Config) -cne $ConfigSha256){throw 'Exact controller config required'}
$task=Read-S160Json $Config
$context=New-S160Context $task.run 'controller'
$self=Convert-S160Identity (Get-S160Live $PID)
if(!$self){throw 'Live controller identity required'}
Write-S160Json (Join-Path $task.run 'controller-self.json') $self
Assert-S160Environment $task.run|Out-Null
$failures=[Collections.Generic.List[string]]::new();$started=[DateTimeOffset]::UtcNow;$deadline=$started.AddSeconds(960)
$nodeChild=$null;$rawValidated=$false;$postPassed=$false
function Check-Budget([int]$Reserve){if([DateTimeOffset]::UtcNow.AddSeconds($Reserve) -ge $deadline){throw 'Controller960s budget exhausted'}}
function Check-Pause {if(Test-Path -LiteralPath (Join-Path $task.run 'PAUSE')){throw 'Owned capture paused before next phase'}}
function Seal([string]$Phase){
    if($Phase -eq 'before'){Check-Pause;Check-Budget 780}
    $child=Start-S160Process $context $Phase $s160Pwsh @('-NoLogo','-NoProfile','-NonInteractive','-File',$task.seal_script,'-Config',$Config,'-ConfigSha256',$ConfigSha256,'-Phase',$Phase)
    Wait-S160Process $context $child $(if($Phase -eq 'artifact'){60}else{180})|Out-Null
}
function Admission {
    Check-Pause;Check-Budget 630
    $nonce=[Guid]::NewGuid().ToString('N');$request=Join-Path $task.run 'admission/source160.request.json';$approval=Join-Path $task.run 'admission/source160.approval.json'
    if(Test-Path -LiteralPath $approval){throw 'Admission approval preceded fresh request'}
    $issued=[DateTimeOffset]::UtcNow;$expires=$issued.AddSeconds(120)
    Write-S160Json $request @{kind='source160';run_id=$task.run_id;candidate_head=$task.candidate_head;nonce=$nonce;issued_utc=$issued.ToString('o');expires_utc=$expires.ToString('o');required_free_kib=16MB}
    while(!(Test-Path -LiteralPath $approval)){Check-Pause;if([DateTimeOffset]::UtcNow -ge $expires){throw 'Fresh Root source160 admission120s expired'};Start-Sleep -Milliseconds 200}
    $permit=Read-S160SettledJson $approval $expires
    if($permit.approved -isnot [bool] -or !$permit.approved -or $permit.manual_fresh_16gib -isnot [bool] -or !$permit.manual_fresh_16gib -or $permit.kind -cne 'source160' -or $permit.run_id -cne $task.run_id -or $permit.candidate_head -cne $task.candidate_head -or $permit.nonce -cne $nonce -or ([DateTimeOffset]$permit.issued_utc) -lt $issued -or ([DateTimeOffset]$permit.issued_utc) -gt [DateTimeOffset]::UtcNow -or ([DateTimeOffset]$permit.expires_utc) -gt $expires -or ([DateTimeOffset]$permit.expires_utc) -le [DateTimeOffset]::UtcNow){throw 'Fresh exact manual Root source160 approval required'}
    $free=(Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 3).FreePhysicalMemory
    Write-S160Json (Join-Path $task.run 'admission/source160.reservation.json') @{nonce=$nonce;free_kib=$free;required_free_kib=16MB;source_reserved_kib=2MB;heap_mb=256;admitted=($free -ge 16MB);approval_sha256=Get-S160Sha $approval;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
    if($free -lt 16MB){throw 'Automatic fresh16GiB source160 admission denied'}
}
try{
    Seal 'before';Admission;Check-Pause;Check-Budget 510
    # The untouched96BE owner inherits only this cleared allowlisted environment.
    $nodeArguments=@('--max-old-space-size=256','--permission')
    foreach($path in @($task.source,$task.capture_control_root,$task.capture_caller_root,$task.workspace_metadata,$task.run)){$nodeArguments+=('--allow-fs-read='+$path)}
    $nodeArguments+=@(('--allow-fs-write='+$task.run),'--import',$task.guard,$task.driver,$task.source,$task.output)
    $nodeCommand=@{Name='source160';Executable=$task.node;WorkingDirectory=$task.run;Arguments=$nodeArguments;TimeoutSeconds=300;SettleSeconds=10}
    Write-S160Json (Join-Path $task.run 'node-command.json') $nodeCommand
    # A tiny owned invocation script avoids shell quoting and preserves string[] argv.
    $nodeChild=Start-S160Process $context 'original96BE-owner' $s160Pwsh @('-NoLogo','-NoProfile','-NonInteractive','-File',$task.owner_invocation,'-Config',$Config,'-ConfigSha256',$ConfigSha256)
    if($nodeChild.validation_error -or !$nodeChild.identity){throw 'Original96BE invocation parent/intended argv not verified; fence remains closed'}
    $readyPath=Join-Path $task.run 'start-fence-ready.json';$ownerPath=Join-Path $task.run 'source160.json'
    $fenceDeadline=[DateTimeOffset]::UtcNow.AddSeconds(10)
    while(!(Test-Path -LiteralPath $readyPath) -or !(Test-Path -LiteralPath $ownerPath)){
        if($nodeChild.process.HasExited -or [DateTimeOffset]::UtcNow -ge $fenceDeadline){throw 'Owned Node ready/original96BE record missing before10s fence'}
        Start-Sleep -Milliseconds 25
    }
    $ready=Read-S160SettledJson $readyPath $fenceDeadline;$retained=Read-S160SettledJson $ownerPath $fenceDeadline
    $intendedReadyArgv=@($task.node,$task.driver,$task.source,$task.output)
    $intendedExecArgv=@($nodeArguments[0..($nodeArguments.Count-4)])
    if((@($ready.argv) -join [char]0) -cne ($intendedReadyArgv -join [char]0) -or (@($ready.execArgv) -join [char]0) -cne ($intendedExecArgv -join [char]0)){throw 'Ready argv/execArgv differs from intended Node PSI arguments; fence remains closed'}
    $live=Get-S160Live ([int]$ready.pid);$identity=Convert-S160Identity $live
    if(!$identity -or $retained.command_line_source -cne 'live Win32_Process' -or [int]$ready.pid -ne [int]$retained.pid -or $ready.execPath -cne $task.node -or $ready.version -cne 'v24.14.0' -or $ready.sourceImported -ne $false -or $ready.nonce -cne $task.fence_nonce -or $identity.executable -cne $task.node -or $identity.command_line -cne $retained.command_line -or !(Test-S160Argv $identity.command_line $task.node ([string[]]$nodeArguments)) -or [Math]::Abs((([DateTimeOffset]$identity.created_utc).UtcDateTime-([DateTimeOffset]$retained.created_utc).UtcDateTime).TotalMilliseconds) -gt 1 -or $retained.executable_sha256 -cne $task.node_sha256 -or (Get-S160Sha $task.node) -cne $task.node_sha256 -or [int]$identity.parent_pid -ne [int]$nodeChild.process.Id){throw 'Node start-fence live/kernel/executable/parent/intended argv reconciliation failed'}
    Add-S160Identity $context $identity
    $free=(Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 3).FreePhysicalMemory
    Write-S160Json (Join-Path $task.run 'start-fence-identity.json') @{ready=$ready;retained=$retained;live=$identity;exe_sha256=Get-S160Sha $task.node;free_kib=$free;required_free_kib=16MB;admitted=($free -ge 16MB);observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
    if($free -lt 16MB -or [DateTimeOffset]::UtcNow -ge $fenceDeadline){throw 'Fresh16GiB/10s fence admission failed'}
    Write-S160Json (Join-Path $task.run 'start-fence-release.json') @{nonce=$task.fence_nonce;node_pid=[int]$ready.pid;live_identity_verified=$true}
    Wait-S160Process $context $nodeChild 330|Out-Null;$nodeChild=$null
    $original=Read-S160Json $ownerPath;$closure=Read-S160Json (Join-Path $task.run 'runtime-free-closure.json');$raw=Read-S160Json $task.output
    $ids=Read-S160Json $task.case_ids
    if($original.status -cne 'passed' -or $original.exit_code -ne 0 -or !$original.terminal_kernel_handle -or !$original.independent_pid_absent -or $raw.cases -ne 160 -or @($raw.rows).Count -ne 160 -or (@($raw.rows.id) -join "`n") -cne (@($ids.ids) -join "`n") -or $raw.sourceHead -cne $task.source_head -or $raw.sourceTree -cne $task.source_tree -or $raw.actualNode.pid -ne $ready.pid -or $raw.actualNode.version -cne 'v24.14.0' -or $raw.actualNode.execPath -cne $task.node -or $raw.moduleSha256 -cne $task.classifier_sha256 -or $raw.callerSha256 -cne $task.caller_sha256){throw 'Actual Source160 original owner/ordered IDs/provenance negative'}
    $observed=@($closure.observed|Sort-Object);$required=@($task.module_files.path|Sort-Object)
    if($closure.pid -ne $ready.pid -or $closure.sourceHead -cne $task.source_head -or $closure.startFenceNonce -cne $task.fence_nonce -or !$closure.allRequiredModulesObserved -or !$closure.environmentAllowlistMatched -or $closure.credentialValuesRecorded -ne $false -or @($closure.attempts).Count -ne 0 -or $closure.runtimeDependenciesLoaded -ne 0 -or $closure.npmImports -ne 0 -or $closure.networkRequests -ne 0 -or (@($observed) -join "`n") -cne (@($required) -join "`n")){throw 'Required runtime-free resolver/network/env transcript negative'}
    $rawValidated=$true
    Write-S160Json (Join-Path $task.run 'source160-validation.json') @{cases=160;ordered_ids_exact=$true;original_owner_terminal_zero=$true;raw_sha256=Get-S160Sha $task.output;closure_sha256=Get-S160Sha (Join-Path $task.run 'runtime-free-closure.json');expected_created=$false;root_acceptance_pending=$true}
}catch{$failures.Add($_.Exception.Message)}finally{
    # Always settle verified children and preserve final seals, including negatives.
    if($nodeChild -and !$nodeChild.process.HasExited){
        try{Wait-S160Process $context $nodeChild 330|Out-Null}catch{$failures.Add($_.Exception.Message)}
    }
    try{Seal 'post';$postPassed=$true}catch{$failures.Add($_.Exception.Message)}
    try{
        $absence=Get-S160Absence $context.known.ToArray() $context.partial.ToArray()
        Write-S160Json (Join-Path $task.run 'controller-descendants-absence.json') $absence
        if($absence.present_or_unknown){$failures.Add('Controller descendants not independently absent')}
    }catch{$failures.Add($_.Exception.Message)}
    Write-S160Json (Join-Path $task.run 'controller-outcome.json') @{status=if(!$failures.Count -and $rawValidated -and $postPassed){'captured_pending_root_review'}else{'negative'};failures=$failures.ToArray();candidate_head=$task.candidate_head;source_head=$task.source_head;raw160_validated=$rawValidated;full_post_passed=$postPassed;known_owned_identities=$context.known.ToArray();partial_observations=$context.partial.ToArray();expected_created=$false;global_hold_lifted=$false;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
    try{Seal 'artifact'}catch{$failures.Add($_.Exception.Message);Write-S160Json (Join-Path $task.run 'artifact-negative.json') @{failure=$_.Exception.Message}}
}
if($failures.Count){exit 1}
