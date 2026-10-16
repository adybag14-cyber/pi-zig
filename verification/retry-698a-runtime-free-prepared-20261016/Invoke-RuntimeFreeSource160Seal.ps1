param([Parameter(Mandatory)][string]$Config,[Parameter(Mandatory)][string]$ConfigSha256,[Parameter(Mandatory)][ValidateSet('before','post','recovery-post','artifact')][string]$Phase)
. (Join-Path $PSScriptRoot 'RuntimeFreeSource160.Common.ps1')
if((Get-S160Sha $Config) -cne $ConfigSha256){throw 'Immutable run config changed'}
$task=Read-S160Json $Config
Assert-S160Environment $task.run|Out-Null
Assert-S160Contained $task.run (Join-Path (Get-S160Workspace).evidence 'retry698a-runtime-free-captures')|Out-Null
$receipt=Join-Path $task.run ($Phase+'-full-seal.json')
if(Test-Path -LiteralPath $receipt){throw 'Refuse seal replay'}
$failures=[Collections.Generic.List[string]]::new()
$groups=@();$sourceDifference=@();$nodeDifference=@()
$baselinePath=Join-Path $task.run 'full-before-manifest.json'
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
            if(!(Test-Path -LiteralPath $row.path -PathType Leaf) -or (Get-S160Sha $row.path) -cne ([string]$row.sha256).ToUpperInvariant()){$changed.Add([string]$row.path)}
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
    $rows=@(Get-ChildItem -LiteralPath $task.run -File -Recurse|Where-Object {$_.Name -notlike '*.tmp' -and $_.Name -notin @('supervisor-identities.json','supervisor-partial-identities.json','controller-identities.json','controller-partial-identities.json')}|ForEach-Object{@{path=$_.FullName;sha256=Get-S160Sha $_.FullName;bytes=$_.Length}})
    Write-S160Json (Join-Path $task.run 'capture-artifact-manifest.json') @{rows=$rows;files=$rows.Count;excludes_only_live_owner_ledgers=$true;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
    exit 0
}
try{
    foreach($root in @($task.source,$task.candidate,$task.run)){Assert-S160Contained $root $task.container|Out-Null}
    if(Test-Path -LiteralPath (Join-Path $task.source 'node_modules')){$failures.Add('Source node_modules unexpectedly present')}
    try{
        if((Invoke-S160Git $task.source @('rev-parse','HEAD')) -cne $task.source_head -or (Invoke-S160Git $task.source @('rev-parse','HEAD^{tree}')) -cne $task.source_tree){$failures.Add('Source698 HEAD/tree changed')}
        if(Invoke-S160Git $task.source @('status','--porcelain','--untracked-files=no')){$failures.Add('Official tracked Source dirty')}
        if((Invoke-S160Git $task.candidate @('rev-parse','HEAD')) -cne $task.candidate_head -or (Invoke-S160Git $task.candidate @('status','--porcelain'))){$failures.Add('Exact clean candidate changed')}
    }catch{$failures.Add('Git metadata negative: '+$_.Exception.Message)}
    try{$candidateRelative=@((Invoke-S160Git $task.candidate @('ls-files')).Split("`n")|ForEach-Object{$_.TrimEnd("`r")})}catch{
        $failures.Add('Git candidate inventory negative: '+$_.Exception.Message)
        $candidateRelative=if(Test-Path -LiteralPath $baselinePath){@((Read-S160Json $baselinePath).candidate_relative)}else{@()}
    }
    $sourceRows=@(Read-S160Json $task.source_manifest);$nodeRows=@(Read-S160Json $task.node_manifest)
    if($sourceRows.Count -ne 1970 -or $nodeRows.Count -ne 1774){throw 'Complete original inventories required'}
    foreach($row in $sourceRows){Assert-S160Contained $row.path $task.source|Out-Null}
    foreach($row in $nodeRows){Assert-S160Contained $row.path 'C:\Program Files\nodejs'|Out-Null}
    $sourceInventory=@(Inventory $task.source $true);$nodeInventory=@(Inventory 'C:\Program Files\nodejs' $false)
    $sourceDifference=Compare-Inventory @($sourceRows.path) $sourceInventory 'Source1970'
    $nodeDifference=Compare-Inventory @($nodeRows.path) $nodeInventory 'Node1774'
    if($Phase -eq 'before' -or !(Test-Path -LiteralPath $baselinePath)){
        if($Phase -ne 'before'){$failures.Add('Original before baseline absent; current full inventory retained without before-proof claim')}
        if(Test-Path -LiteralPath $baselinePath){throw 'Refuse original full freeze overwrite'}
        $candidateRows=@(foreach($relative in $candidateRelative){$path=Join-Path $task.candidate $relative;Assert-S160Contained $path $task.candidate|Out-Null;@{path=$path;sha256=Get-S160Sha $path}})
        $controlRows=@(foreach($path in @($Config,$task.source_manifest,$task.node_manifest,$task.owner_copy,$task.initial_grant,$task.workspace_metadata,$task.relocation_map,$task.workspace_resolver)) {@{path=$path;sha256=Get-S160Sha $path}})
        $baseline=@{candidate_head=$task.candidate_head;source_head=$task.source_head;source_tree=$task.source_tree;candidate_relative=$candidateRelative;groups=@(@{name='source1970';rows=$sourceRows},@{name='node1774';rows=$nodeRows},@{name='candidate';rows=$candidateRows},@{name='controls';rows=$controlRows},@{name='accepted273';rows=@($task.old273_pins)});runtime_manifest_required=$false;runtime_read_permitted=$false}
        Write-S160Json $(if($Phase -eq 'before'){$baselinePath}else{Join-Path $task.run 'recovery-current-manifest.json'}) $baseline
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
Write-S160Json $receipt @{phase=$Phase;source_head=$task.source_head;source_tree=$task.source_tree;candidate_head=$task.candidate_head;baseline_sha256=if(Test-Path -LiteralPath $baselinePath){Get-S160Sha $baselinePath}else{$null};groups=@($groups);source_inventory_difference=@($sourceDifference);node_inventory_difference=@($nodeDifference);failures=$failures.ToArray();failure_count=$failures.Count;runtime_dependencies=0;runtime_seal_claimed=$false;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
if($failures.Count){throw ('Source160 '+$Phase+' full seal negative')}
