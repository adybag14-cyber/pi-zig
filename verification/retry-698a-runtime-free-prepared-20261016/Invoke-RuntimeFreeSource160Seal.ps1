param([Parameter(Mandatory)][string]$Config,[Parameter(Mandatory)][string]$ConfigSha256,[Parameter(Mandatory)][ValidateSet('before','post','recovery-post','artifact')][string]$Phase)
. ($PSScriptRoot+'\RuntimeFreeSource160.Common.ps1')
Initialize-S160OwnedChild $PSCommandPath
if((Get-S160Sha $Config) -cne $ConfigSha256){throw 'Immutable run config changed'}
$task=Read-S160Json $Config
$context=New-S160Context $task.run ('seal-'+$Phase)
$self=Convert-S160Identity (Get-S160Live $PID)
if(!$self){throw 'Seal worker self identity required; direct launch remains registered by parent'}
Write-S160Json (Join-Path $task.run ('seal-'+$Phase+'-self.json')) $self
Assert-S160Environment $task.run|Out-Null
Assert-S160Contained $task.run (Join-Path (Get-S160Workspace).evidence 'retry698a-runtime-free-captures')|Out-Null
$receipt=Join-Path $task.run ($Phase+'-full-seal.json')
if(Test-Path -LiteralPath $receipt){throw 'Refuse seal replay'}
$failures=[Collections.Generic.List[string]]::new()
$groups=@();$sourceDifference=@();$nodeDifference=@()
$markerAbsence=@();$fallbackPath=$null
$baselinePath=Join-Path $task.run 'full-before-manifest.json'
$checkedDirectories=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$pathChecks=@{lexical=0;leaf=0;directory=0;cache_hits=0;end_revalidated=0}
function Assert-SealAncestors([string]$Path,[string]$Root){
    $full=[IO.Path]::GetFullPath($Path);$base=[IO.Path]::GetFullPath($Root).TrimEnd('\');$pathChecks.lexical++
    if(!$full.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Sealed file escaped its exact scope'}
    $part=[IO.Path]::GetDirectoryName($full)
    while($part.Length -ge $base.Length){
        if($checkedDirectories.Contains($part)){$pathChecks.cache_hits++}else{
            $attributes=[IO.File]::GetAttributes($part);$pathChecks.directory++
            if(!($attributes -band [IO.FileAttributes]::Directory) -or ($attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Sealed ancestor is not a physical directory'}
            [void]$checkedDirectories.Add($part)
        }
        if($part -ieq $base){break};$part=[IO.Path]::GetDirectoryName($part)
    }
    return $full
}
function Assert-SealFile([string]$Path,[string]$Root){
    $full=Assert-SealAncestors $Path $Root
    $attributes=[IO.File]::GetAttributes($full);$pathChecks.leaf++
    if(($attributes -band [IO.FileAttributes]::Directory) -or ($attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Sealed file must be a physical leaf'}
    return $full
}
function Revalidate-SealDirectories {
    foreach($directory in $checkedDirectories){
        $attributes=[IO.File]::GetAttributes($directory);$pathChecks.end_revalidated++
        if(!($attributes -band [IO.FileAttributes]::Directory) -or ($attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Sealed ancestor changed during phase'}
    }
}
function Check-CallerMarkerAbsence {
    $policy=Get-S160CallerMarkerPolicy $task.driver $task.container
    @(foreach($path in $policy.expected_absent){
        Assert-SealAncestors $path $task.container|Out-Null
        $present=$true
        try{[void][IO.File]::GetAttributes($path)}catch [IO.FileNotFoundException]{$present=$false}catch [IO.DirectoryNotFoundException]{$present=$false}
        if($present){$failures.Add('Unexpected intermediate caller workspace marker')}
        @{path=$path;expected_absent=$true;present=$present}
    })
}
function Inventory([string]$Root,[bool]$ExcludeGit){
    $files=[Collections.Generic.List[string]]::new();$pending=[Collections.Generic.Stack[string]]::new();$pending.Push($Root)
    while($pending.Count){
        foreach($item in @(Get-ChildItem -LiteralPath $pending.Pop() -Force)){
            if($ExcludeGit -and $item.Name -ceq '.git'){continue}
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Unsealed reparse path in reference inventory'}
            if($item.PSIsContainer){$pending.Push($item.FullName)}else{$files.Add($item.FullName)}
        }
    }
    @($files.ToArray()|Sort-Object)
}
function Check-Rows($Rows){
    $changed=[Collections.Generic.List[string]]::new()
    foreach($row in @($Rows)){
        if(!$row.path -or [string]$row.sha256 -cnotmatch '^[A-Fa-f0-9]{64}$'){throw 'Malformed original manifest row'}
        try{
            $scope=if(([string]$row.path).StartsWith('C:\Program Files\nodejs\',[StringComparison]::OrdinalIgnoreCase)){'C:\Program Files\nodejs'}elseif(([string]$row.path).StartsWith($task.container+'\',[StringComparison]::OrdinalIgnoreCase)){$task.container}elseif([string]$row.path -ieq $task.own_console_host_path){'C:\Windows\system32'}else{throw 'Manifest file has no reviewed physical scope'}
            Assert-SealFile $row.path $scope|Out-Null
            if((Get-S160Sha $row.path) -cne ([string]$row.sha256).ToUpperInvariant()){$changed.Add([string]$row.path)}
        }catch{$changed.Add([string]$row.path)}
    }
    @($changed.ToArray())
}
function Compare-Inventory($Expected,$Actual,[string]$Name){
    $difference=@(Compare-Object -ReferenceObject @($Expected|Sort-Object) -DifferenceObject @($Actual|Sort-Object))
    if($difference.Count){$failures.Add($Name+' exact path inventory changed')}
    return $difference
}
if($Phase -eq 'artifact'){
    # Do not hash this worker's still-being-enriched launch record. The parent
    # closes that immutable record before this artifact snapshot is permitted.
    $launchPath=Join-Path $task.run 'artifact-launch.json';$until=[DateTimeOffset]::UtcNow.AddSeconds(10)
    $closed=$false
    do{
        if(Test-Path -LiteralPath $launchPath){
            $launch=Read-S160Json $launchPath
            if($launch.validation_error){throw 'Artifact launch ownership negative'}
            if($launch.status -ceq 'full_parent_argv_kernel_verified' -and [int]$launch.identity.pid -eq $PID -and [int]$launch.identity.parent_pid -eq [int]$self.parent_pid -and $launch.identity.command_line -ceq $self.command_line -and [Math]::Abs((([DateTimeOffset]$launch.identity.created_utc).UtcDateTime-([DateTimeOffset]$self.created_utc).UtcDateTime).TotalMilliseconds) -le 1){$closed=$true;break}
        }
        if([DateTimeOffset]::UtcNow -ge $until){throw 'Artifact launch-record closure deadline10s'}
        Start-Sleep -Milliseconds 25
    }while(!$closed)
    $mutableProfile=Join-Path $task.run 'profile/AppData/Local/Microsoft/PowerShell/StartupProfileData-NonInteractive'
    $rows=@(Get-ChildItem -LiteralPath $task.run -File -Recurse|Where-Object {$_.Name -notlike '*.tmp' -and $_.FullName -ine $mutableProfile -and $_.Name -notin @('supervisor-identities.json','supervisor-partial-identities.json','controller-identities.json','controller-partial-identities.json')}|ForEach-Object{@{path=$_.FullName;sha256=Get-S160Sha $_.FullName;bytes=$_.Length}})
    Write-S160Json (Join-Path $task.run 'capture-artifact-manifest.json') @{rows=$rows;files=$rows.Count;mutable_owned_profile_file_excluded=$mutableProfile;live_owner_ledgers_excluded=@('supervisor-identities.json','supervisor-partial-identities.json','controller-identities.json','controller-partial-identities.json');final_external_manifest_after_all_absence_required=$true;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
    exit 0
}
try{
    foreach($root in @($task.source,$task.candidate,$task.run)){Assert-S160Contained $root $task.container|Out-Null}
    if((Get-S160Sha $task.launcher_claim) -cne $task.launcher_claim_sha256 -or (Get-S160Sha $task.launcher_claim_acceptance) -cne $task.launcher_claim_acceptance_sha256){$failures.Add('Sealed launcher claim/acceptance changed')}
    if((Get-S160Sha $task.node_full_authority) -cne $task.node_full_authority_sha256 -or $task.node_full_authority_sha256 -cne '35F1F2B0F12BF79C06B47AE2BA8C485EF10A7714BE3F129772E3BA1BBB97B927'){$failures.Add('Original complete Node1838 authority changed')}
    if((Get-S160Sha $task.own_console_host_path) -cne $task.own_console_host_sha256){$failures.Add('Prospective supervisor console-host binary seal changed')}
    $markerPolicy=Get-S160CallerMarkerPolicy $task.driver $task.container
    if((@($task.caller_marker_probes) -join [char]0) -cne ($markerPolicy.probe_paths -join [char]0) -or (@($task.caller_marker_absences) -join [char]0) -cne ($markerPolicy.expected_absent -join [char]0) -or $markerPolicy.actual_marker -cne $task.workspace_metadata){throw 'Caller marker absence/permission policy changed'}
    if(Test-Path -LiteralPath (Join-Path $task.source 'node_modules')){$failures.Add('Source node_modules unexpectedly present')}
    try{
        if((Invoke-S160Git $task.source @('rev-parse','HEAD') $context) -cne $task.source_head -or (Invoke-S160Git $task.source @('rev-parse','HEAD^{tree}') $context) -cne $task.source_tree){$failures.Add('Source698 HEAD/tree changed')}
        if(Invoke-S160Git $task.source @('status','--porcelain','--untracked-files=no') $context){$failures.Add('Official tracked Source dirty')}
        if((Invoke-S160Git $task.candidate @('rev-parse','HEAD') $context) -cne $task.candidate_head -or (Invoke-S160Git $task.candidate @('status','--porcelain') $context)){$failures.Add('Exact clean candidate changed')}
    }catch{$failures.Add('Git metadata negative: '+$_.Exception.Message)}
    try{$candidateRelative=@((Invoke-S160Git $task.candidate @('ls-files') $context).Split("`n")|ForEach-Object{$_.TrimEnd("`r")})}catch{
        $failures.Add('Git candidate inventory negative: '+$_.Exception.Message)
        $candidateRelative=if(Test-Path -LiteralPath $baselinePath){@((Read-S160Json $baselinePath).candidate_relative)}else{@()}
    }
    $sourceRows=@(Read-S160Json $task.source_manifest);$nodeRows=@(Read-S160Json $task.node_manifest);$nodeFullRows=@((Read-S160Json $task.node_full_authority).node_complete)
    if($sourceRows.Count -ne 1970 -or $nodeRows.Count -ne 1774 -or $nodeFullRows.Count -ne 1838 -or $task.node_full_authority_group -cne 'node_complete'){throw 'Complete original inventories required'}
    foreach($row in $sourceRows){Assert-SealFile $row.path $task.source|Out-Null}
    $nodeFullMap=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($row in $nodeFullRows){Assert-SealFile $row.path 'C:\Program Files\nodejs'|Out-Null;$nodeFullMap.Add([string]$row.path,[string]$row.sha256)}
    foreach($row in $nodeRows){if(!$nodeFullMap.ContainsKey([string]$row.path) -or $nodeFullMap[[string]$row.path] -cne [string]$row.sha256){throw 'Original1774 is not exact subset of original1838'}}
    $sourceInventory=@(Inventory $task.source $true);$nodeInventory=@(Inventory 'C:\Program Files\nodejs' $false)
    $sourceDifference=Compare-Inventory @($sourceRows.path) $sourceInventory 'Source1970'
    $nodeDifference=Compare-Inventory @($nodeFullRows.path) $nodeInventory 'Node1838 original complete authority'
    if($Phase -eq 'before' -or !(Test-Path -LiteralPath $baselinePath)){
        if($Phase -ne 'before'){$failures.Add('Original before baseline absent; current full inventory retained without before-proof claim')}
        if(Test-Path -LiteralPath $baselinePath){throw 'Refuse original full freeze overwrite'}
        $candidateRows=@(foreach($relative in $candidateRelative){$path=Join-Path $task.candidate $relative;Assert-SealFile $path $task.candidate|Out-Null;@{path=$path;sha256=Get-S160Sha $path}})
        $controlRows=@(foreach($path in @($Config,$task.source_manifest,$task.node_manifest,$task.node_full_authority,$task.owner_copy,$task.initial_grant,$task.workspace_metadata,$task.relocation_map,$task.workspace_resolver,$task.launcher_claim,$task.launcher_claim_acceptance,$task.own_console_host_path)) {@{path=$path;sha256=Get-S160Sha $path}})
        $baseline=@{candidate_head=$task.candidate_head;source_head=$task.source_head;source_tree=$task.source_tree;candidate_relative=$candidateRelative;node_full_authority_sha256=$task.node_full_authority_sha256;original1774_exact_subset=$true;groups=@(@{name='source1970';rows=$sourceRows},@{name='node1774';rows=$nodeRows},@{name='node_complete1838';rows=$nodeFullRows},@{name='candidate';rows=$candidateRows},@{name='controls';rows=$controlRows},@{name='accepted273';rows=@($task.old273_pins)});runtime_manifest_required=$false;runtime_read_permitted=$false}
        if($Phase -eq 'before'){Write-S160Json $baselinePath $baseline}else{
            $fallbackPath=Join-Path $task.run ($Phase+'-current-manifest.json')
            Write-S160CreateNewJson $fallbackPath $baseline
        }
        if(Test-Path -LiteralPath $task.output){$failures.Add('Source160 output was already present before launch')}
        foreach($path in @($task.expected160_absences)){if(Test-Path -LiteralPath $path){$failures.Add('Source160 expected must remain absent')}}
    }else{
        $baseline=Read-S160Json $baselinePath
        $beforeReceipt=Read-S160Json (Join-Path $task.run 'before-full-seal.json')
        if((Get-S160Sha $baselinePath) -cne $beforeReceipt.baseline_sha256){$failures.Add('Original full before manifest hash changed')}
        if($baseline.candidate_head -cne $task.candidate_head){$failures.Add('Original baseline identity changed')}
        Compare-Inventory @($baseline.candidate_relative) $candidateRelative 'candidate'|Out-Null
    }
    $groups=@(foreach($group in $baseline.groups){$changed=@(Check-Rows $group.rows);if($changed.Count){$failures.Add($group.name+' file drift')};@{name=$group.name;files=@($group.rows).Count;drift=$changed.Count;changed=$changed}})
    foreach($path in @($task.expected160_absences)){if(Test-Path -LiteralPath $path){$failures.Add('Source160 expected absence changed')}}
    if((Get-S160Sha $task.owner_copy) -cne $s160OwnerSha){$failures.Add('Original96BE owner changed')}
    if((Get-S160Sha $task.node) -cne $task.node_sha256){$failures.Add('Pinned Node changed')}
}catch{$failures.Add($_.Exception.Message)}
try{$markerAbsence=Check-CallerMarkerAbsence}catch{$failures.Add($_.Exception.Message)}
try{Revalidate-SealDirectories}catch{$failures.Add($_.Exception.Message)}
Write-S160Json $receipt @{phase=$Phase;source_head=$task.source_head;source_tree=$task.source_tree;candidate_head=$task.candidate_head;node_full_authority_sha256=$task.node_full_authority_sha256;node_full_files=1838;original_node1774_retained=$true;caller_marker_absence=$markerAbsence;physical_path_checks=$pathChecks;baseline_sha256=if(Test-Path -LiteralPath $baselinePath){Get-S160Sha $baselinePath}else{$null};fallback_current_manifest=$fallbackPath;fallback_current_manifest_sha256=if($fallbackPath -and (Test-Path -LiteralPath $fallbackPath)){Get-S160Sha $fallbackPath}else{$null};groups=@($groups);source_inventory_difference=@($sourceDifference);node_inventory_difference=@($nodeDifference);failures=$failures.ToArray();failure_count=$failures.Count;runtime_dependencies=0;runtime_seal_claimed=$false;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
if($failures.Count){throw ('Source160 '+$Phase+' full seal negative')}
