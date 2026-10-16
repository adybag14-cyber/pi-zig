param([Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$CandidateHead,[Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9-]{1,70}$')][string]$RunId,[Parameter(Mandatory)][string]$RootGrant,[Parameter(Mandatory)][string]$LaunchClaim,[Parameter(Mandatory)][ValidatePattern('^[A-F0-9]{64}$')][string]$LaunchClaimSha256)
. ($PSScriptRoot+'\RuntimeFreeSource160.Common.ps1')
Initialize-S160OwnedChild $PSCommandPath
$workspace=Get-S160Workspace
$candidate=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
Assert-S160Contained $candidate $workspace.worktrees|Out-Null
Assert-S160Contained $RootGrant $workspace.evidence|Out-Null
$toolNames=@('Start-RuntimeFreeSource160.ps1','Run-RuntimeFreeSource160.ps1','Invoke-RuntimeFreeSource160Controller.ps1','Invoke-RuntimeFreeSource160Seal.ps1','Invoke-RuntimeFreeSource160OriginalOwner.ps1','RuntimeFreeSource160.Common.ps1','Confirm-RuntimeFreeSource160Absent.ps1','Resolve-RuntimeFreeSource160Controls.ps1','guarded-start-fence.mjs','ordered-source160-case-ids.json')
$tools=[ordered]@{}
foreach($name in $toolNames){$tools[$name]=Get-S160Sha (Join-Path $PSScriptRoot $name)}
$grant=Read-S160Json $RootGrant
$grantFields=@('schema','authorized','manual_fresh_16gib','scope','run_id','candidate_head','issued_utc','expires_utc','grant_id','tool_sha256','source_head','node_sha256','owner_sha256')
if(@($grant.PSObject.Properties.Name|Where-Object {$_ -notin $grantFields}).Count){throw 'Unknown Root exception-grant field'}
$now=[DateTimeOffset]::UtcNow
if($grant.schema -ne 1 -or $grant.authorized -isnot [bool] -or !$grant.authorized -or $grant.manual_fresh_16gib -isnot [bool] -or !$grant.manual_fresh_16gib -or $grant.scope -cne 'runtime-free-source160-only' -or $grant.run_id -cne $RunId -or $grant.candidate_head -cne $CandidateHead -or $grant.source_head -cne '698a2d23b86a5045dd54554354a5e0cb7e466795' -or $grant.node_sha256 -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088' -or $grant.owner_sha256 -cne $s160OwnerSha -or ([DateTimeOffset]$grant.issued_utc) -gt $now -or ($now-([DateTimeOffset]$grant.issued_utc)).TotalSeconds -gt 300 -or ([DateTimeOffset]$grant.expires_utc) -le $now -or (([DateTimeOffset]$grant.expires_utc)-([DateTimeOffset]$grant.issued_utc)).TotalSeconds -gt 300){throw 'Fresh exact Root runtime-free exception grant required; no child started'}
if(@($grant.tool_sha256.PSObject.Properties).Count -ne $toolNames.Count){throw 'All exact tooling hashes must be granted'}
foreach($name in $toolNames){if($grant.tool_sha256.$name -cne $tools[$name]){throw 'Granted tooling hash mismatch'}}
$resolved=& (Join-Path $PSScriptRoot 'Resolve-RuntimeFreeSource160Controls.ps1') -RunId $RunId
if((Get-S160Sha $resolved.owner) -cne $s160OwnerSha -or (Get-S160Sha $s160Node) -cne $resolved.node_sha256){throw 'Owner/Node authority changed'}
$run=Assert-S160Contained $resolved.config_template.run (Join-Path $workspace.evidence 'retry698a-runtime-free-captures')
$startupSelf=Convert-S160Identity (Get-S160Live $PID)
$acceptedClaim=Accept-S160LaunchClaim $run $RunId $CandidateHead $RootGrant $LaunchClaim $LaunchClaimSha256 $startupSelf
$free=(Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 3).FreePhysicalMemory
if($free -lt 16MB){throw 'Initial automatic fresh16GiB admission denied'}
foreach($directory in @($run,(Join-Path $run 'profile'),(Join-Path $run 'profile/agent'),(Join-Path $run 'temp'),(Join-Path $run 'admission'))){[void][IO.Directory]::CreateDirectory($directory)}
Assert-S160Environment $run|Out-Null
Copy-Item -LiteralPath $RootGrant -Destination (Join-Path $run 'initial-root-grant.json')
Copy-Item -LiteralPath $resolved.owner -Destination (Join-Path $run 'Invoke-OwnedModelsClassSource-20261016.ps1')
Write-S160Json (Join-Path $run 'initial-admission.json') @{free_kib=$free;required_free_kib=16MB;source_reserved_kib=2MB;admitted=$true;grant_sha256=Get-S160Sha $RootGrant;observed_utc=$now.ToString('o')}
$configPath=Join-Path $run 'capture-config.json'
$pins=@(
    @{path=(Join-Path $candidate 'src/extensions/fixtures/sdk-summary-latest4dd.expected.json');sha256='820AD75D3D804E3EABBC9E78D2268DC09C92F485AFCDCC4BB55A26EDA656582B'},
    @{path=(Join-Path $candidate 'src/extensions/fixtures/sdk-summary-original45-latest4dd.expected.json');sha256='AED51DB78585E898D9CFBDACD27CFE75B09852D4DA27430CE8C559CEDE30DF8C'},
    @{path=(Join-Path $candidate 'src/extensions/fixtures/ai-openai-tool-output4dd.expected.json');sha256='B9FA83B3666297E6653163B489B82FE1EF1D7FA5B2E1B3B5423C690E90BCD674'},
    @{path=(Join-Path $candidate 'src/extensions/fixtures/ai-google-tool-output4dd.expected.json');sha256='3F00C88144C6430E6B6B2A162CA005BDF021A679EA727191D9EC09112D573725'}
)
$config=[ordered]@{
    schema=1;run=$run;run_id=$RunId;container=$workspace.Container;candidate=$candidate;candidate_head=$CandidateHead;source=$resolved.source;
    source_head=$resolved.config_template.source_head;source_tree=$resolved.config_template.source_tree;classifier=$resolved.config_template.classifier;forbidden_runtime=$workspace.runtime;
    module_files=$resolved.config_template.module_files;fence_nonce=[Guid]::NewGuid().ToString('N');nonce=$null;
    node=$s160Node;node_sha256=$resolved.node_sha256;source_manifest=$resolved.source_manifest;node_manifest=$resolved.node_manifest;output=$resolved.output;
    node_full_authority=$resolved.node_full_authority;node_full_authority_sha256=$resolved.node_full_authority_sha256;node_full_authority_group=$resolved.node_full_authority_group;node_full_files=1838;
    own_console_host_path='C:\Windows\system32\conhost.exe';own_console_host_sha256=(Get-S160Sha 'C:\Windows\system32\conhost.exe');own_console_host_command_line='\??\C:\Windows\system32\conhost.exe 0x4';
    classifier_sha256='D7ACFF8DC7F0EEE04ECB116A79FBB8331337D9F091A0CEEE775D623D7478D448';caller_sha256='84C373D351B8D348EE03A922663DC6C74BC2E5479C29BEB760E4B2AD91248392';
    guard=(Join-Path $PSScriptRoot 'guarded-start-fence.mjs');guard_url=(Convert-S160FileUrl (Join-Path $PSScriptRoot 'guarded-start-fence.mjs'));driver=$resolved.driver;capture_control_root=$PSScriptRoot;capture_caller_root=(Split-Path -Parent $resolved.driver);case_ids=(Join-Path $PSScriptRoot 'ordered-source160-case-ids.json');
    owner_copy=(Join-Path $run 'Invoke-OwnedModelsClassSource-20261016.ps1');owner_invocation=(Join-Path $PSScriptRoot 'Invoke-RuntimeFreeSource160OriginalOwner.ps1');seal_script=(Join-Path $PSScriptRoot 'Invoke-RuntimeFreeSource160Seal.ps1');
    workspace_metadata=(Join-Path $workspace.Container '.pi-zig-workspace.json');relocation_map=$workspace.path_relocations;workspace_resolver=(Join-Path $workspace.main 'tools/workspace/Resolve-PiZigWorkspace.ps1');initial_grant=(Join-Path $run 'initial-root-grant.json');
    launcher_claim=$acceptedClaim.claim_path;launcher_claim_sha256=$acceptedClaim.claim_sha256;launcher_claim_acceptance=$acceptedClaim.acceptance_path;launcher_claim_acceptance_sha256=$acceptedClaim.acceptance_sha256;
    old273_pins=$pins;expected160_absences=@((Join-Path $candidate 'src/extensions/fixtures/ai-retry698-classifier.expected.json'),(Join-Path $PSScriptRoot 'source160.expected.json'));
    tool_sha256=$tools;controller_seconds=960;supervisor_seconds=1260;hash_phase_seconds=180;artifact_seconds=60;node_seconds=300;settle_seconds=10;original_owner_hard_seconds=330;admission_seconds=120;heap_mb=256
}
$config.nonce=$config.fence_nonce
Write-S160Json $configPath $config
$configSha=Get-S160Sha $configPath
$context=New-S160Context $run 'supervisor'
$self=Convert-S160Identity (Get-S160Live $PID)
if(!$self){throw 'External supervisor live identity required before child'}
Write-S160Json (Join-Path $run 'supervisor-self.json') @{identity=$self;tool_sha256=$tools;hard_seconds=1260;started_utc=[DateTimeOffset]::UtcNow.ToString('o')}
$start=[DateTimeOffset]::UtcNow;$hard=$start.AddSeconds(1260);$failures=[Collections.Generic.List[string]]::new();$controller=$null;$recoveryNeeded=$false
try{
    if((Invoke-S160Git $candidate @('rev-parse','HEAD') $context) -cne $CandidateHead -or (Invoke-S160Git $candidate @('status','--porcelain') $context)){throw 'Exact clean assigned candidate required'}
    $controller=Start-S160Process $context 'controller' $s160Pwsh @('-NoLogo','-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot 'Invoke-RuntimeFreeSource160Controller.ps1'),'-Config',$configPath,'-ConfigSha256',$configSha)
    # Controller960s leaves300s to settle/final-seal/artifact on a negative.
    Wait-S160Process $context $controller 960|Out-Null
}catch{$failures.Add($_.Exception.Message);$recoveryNeeded=$true}finally{
    # Preserve the entire observed tree before considering narrowly verified stops.
    try{Observe-S160Descendants $context}catch{$failures.Add($_.Exception.Message)}
    if($controller -and !$controller.process.HasExited){
        foreach($identity in @($context.known.ToArray()|Sort-Object created_utc -Descending)){
            if([DateTimeOffset]::UtcNow -ge $hard.AddSeconds(-240)){break}
            try{Stop-S160Verified $identity|Out-Null}catch{$failures.Add($_.Exception.Message)}
        }
    }
    $postPath=Join-Path $run 'post-full-seal.json'
    if(!(Test-Path -LiteralPath $postPath)){$recoveryNeeded=$true}
    if($recoveryNeeded){
        try{
            if([DateTimeOffset]::UtcNow.AddSeconds(240) -ge $hard){throw 'Recovery final-seal reserve exhausted'}
            $child=Start-S160Process $context 'recovery-post' $s160Pwsh @('-NoLogo','-NoProfile','-NonInteractive','-File',$config.seal_script,'-Config',$configPath,'-ConfigSha256',$configSha,'-Phase','recovery-post')
            Wait-S160Process $context $child 180|Out-Null
        }catch{$failures.Add($_.Exception.Message)}
    }
    try{
        # Merge controller records: its fast descendants may have exited between our samples.
        foreach($path in @((Join-Path $run 'controller-identities.json'))){if(Test-Path -LiteralPath $path){foreach($identity in @(Read-S160Json $path)){Add-S160Identity $context $identity}}}
        if(Test-Path -LiteralPath (Join-Path $run 'controller-partial-identities.json')){foreach($row in @(Read-S160Json (Join-Path $run 'controller-partial-identities.json'))){$context.partial.Add($row)}}
        $union=Get-S160LaunchUnion $run
        $exclude=@($PID,[int]$self.parent_pid)
        $absence=Get-S160Absence @($union.known|Where-Object {$_.pid -notin $exclude}) @($union.partial|Where-Object {$_.pid -notin $exclude})
        Set-S160DeferredSupervisorConsole $absence $self $config
        Write-S160Json (Join-Path $run 'supervisor-descendants-absence.json') $absence
        if($absence.unresolved_present_or_unknown){$failures.Add('Supervisor owned/observed descendants still present or unknown')}
    }catch{$failures.Add($_.Exception.Message)}
    $terminal=if(Test-Path -LiteralPath (Join-Path $run 'controller-outcome.json')){Read-S160Json (Join-Path $run 'controller-outcome.json')}else{$null}
    if(!$terminal -or $terminal.status -cne 'captured_pending_root_review'){$failures.Add('Controller capture is not terminal positive')}
    Write-S160Json (Join-Path $run 'supervisor-terminal.json') @{status=if(!$failures.Count){'captured_pending_external_absence_and_root_review'}else{'negative'};failures=$failures.ToArray();candidate_head=$CandidateHead;source_head=$config.source_head;known_owned_identities=$context.known.ToArray();partial_observations=$context.partial.ToArray();all_launch_ledger_paths=@($union.launch_ledger_paths);config_sha256=$configSha;expected_created=$false;global_hold_lifted=$false;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
    # No unbounded GetResult call exists in this supervisor. Its own pipes are guarded2s.
}
if($failures.Count){exit 1}
