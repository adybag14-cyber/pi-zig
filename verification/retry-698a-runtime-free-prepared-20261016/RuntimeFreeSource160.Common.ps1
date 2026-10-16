# Capture tooling only. Dot-source from the separately granted bounded owners.
$ErrorActionPreference='Stop'
$s160Pwsh='C:\Program Files\PowerShell\7\pwsh.exe'
$s160Git='C:\Program Files\Git\cmd\git.exe'
$s160Node='C:\Program Files\nodejs\node.exe'
$s160OwnerSha='96BEA0CF8E17535C322EE4F36C0115387386F16988BC2B98465BD070A504F5E5'
function Write-S160Json([string]$Path,$Value){
    $temporary=$Path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
    [IO.File]::WriteAllText($temporary,(ConvertTo-Json -InputObject $Value -Depth 70),[Text.UTF8Encoding]::new($false))
    [IO.File]::Move($temporary,$Path,$true)
}
function Read-S160Json([string]$Path){Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json}
function Read-S160SettledJson([string]$Path,[DateTimeOffset]$Until){
    $limit=[DateTimeOffset]::UtcNow.AddMilliseconds(500)
    if($Until -lt $limit){$limit=$Until}
    do{
        try{return Read-S160Json $Path}catch{if([DateTimeOffset]::UtcNow -ge $limit){throw};Start-Sleep -Milliseconds 25}
    }while($true)
}
function Get-S160Sha([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
function Assert-S160Contained([string]$Path,[string]$Root){
    $full=[IO.Path]::GetFullPath($Path);$base=[IO.Path]::GetFullPath($Root).TrimEnd('\')
    if($full -ine $base -and !$full.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Path escaped exact owned root'}
    $part=$full
    while($part -and $part.Length -ge $base.Length){
        if((Test-Path -LiteralPath $part) -and ((Get-Item -LiteralPath $part -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Reparse escape denied'}
        if($part -ieq $base){break};$part=[IO.Path]::GetDirectoryName($part)
    }
    return $full
}
function Get-S160Workspace {
    $directory=[IO.DirectoryInfo]::new($PSScriptRoot)
    while($directory -and !(Test-Path -LiteralPath (Join-Path $directory.FullName '.pi-zig-workspace.json'))){$directory=$directory.Parent}
    if(!$directory){throw 'Contained workspace metadata required'}
    & (Join-Path $directory.FullName 'main/tools/workspace/Resolve-PiZigWorkspace.ps1') -StartPath $PSScriptRoot
}
function Get-S160Environment([string]$Run){
    @{
        SystemRoot='C:\Windows';WINDIR='C:\Windows';ComSpec='C:\Windows\System32\cmd.exe';PATHEXT='.EXE';
        PATH='C:\Windows\System32;C:\Windows;C:\Program Files\PowerShell\7;C:\Program Files\Git\cmd;C:\Program Files\nodejs';
        TEMP=(Join-Path $Run 'temp');TMP=(Join-Path $Run 'temp');HOME=(Join-Path $Run 'profile');USERPROFILE=(Join-Path $Run 'profile');
        HOMEDRIVE='C:';HOMEPATH=((Join-Path $Run 'profile').Substring(2));APPDATA=(Join-Path $Run 'profile');LOCALAPPDATA=(Join-Path $Run 'profile');
        PI_CODING_AGENT_DIR=(Join-Path $Run 'profile/agent');NO_COLOR='1';POWERSHELL_TELEMETRY_OPTOUT='1';POWERSHELL_UPDATECHECK='Off';
        PSModulePath='C:\Program Files\PowerShell\7\Modules;C:\Windows\System32\WindowsPowerShell\v1.0\Modules';
        PI_RETRY698_CAPTURE_CONFIG=(Join-Path $Run 'capture-config.json')
    }
}
function Assert-S160Environment([string]$Run){
    $safe=Get-S160Environment $Run
    $actual=@([Environment]::GetEnvironmentVariables().Keys|ForEach-Object{[string]$_})
    if(@($actual|Where-Object {$_ -notin @($safe.Keys)}).Count){throw 'Unexpected inherited outer/worker environment name'}
    foreach($name in $safe.Keys){if([Environment]::GetEnvironmentVariable($name) -cne [string]$safe[$name]){throw 'Owned environment mismatch'}}
    return @($actual|Sort-Object)
}
function Get-S160Live([int]$ProcessId){
    Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -OperationTimeoutSec 3 -ErrorAction Stop
}
function Convert-S160Identity($Row){
    if(!$Row -or !$Row.ExecutablePath -or !$Row.CommandLine -or !$Row.CreationDate){return $null}
    [ordered]@{pid=[int]$Row.ProcessId;parent_pid=[int]$Row.ParentProcessId;executable=[string]$Row.ExecutablePath;command_line=[string]$Row.CommandLine;created_utc=([DateTimeOffset]$Row.CreationDate).UtcDateTime.ToString('o')}
}
function Test-S160Same($Expected,$Row){
    $Row -and $Row.CreationDate -and [int]$Row.ProcessId -eq [int]$Expected.pid -and [string]$Row.ExecutablePath -ceq $Expected.executable -and [string]$Row.CommandLine -ceq $Expected.command_line -and [Math]::Abs((([DateTimeOffset]$Row.CreationDate).UtcDateTime-([DateTimeOffset]$Expected.created_utc).UtcDateTime).TotalMilliseconds) -le 1
}
function Add-S160Identity($Context,$Identity){
    if($Identity -and !@($Context.known|Where-Object {$_.pid -eq $Identity.pid -and $_.created_utc -ceq $Identity.created_utc}).Count){
        $Context.known.Add($Identity);Write-S160Json (Join-Path $Context.run ($Context.label+'-identities.json')) $Context.known.ToArray()
    }
}
function Observe-S160Descendants($Context){
    # Only exact known parents are queried. Missing CIM fields never authorize a kill.
    $observeUntil=[DateTimeOffset]::UtcNow.AddSeconds(12)
    foreach($expected in @($Context.known.ToArray())){
        if([DateTimeOffset]::UtcNow -ge $observeUntil){break}
        $parent=Get-S160Live $expected.pid
        if(!(Test-S160Same $expected $parent)){continue}
        foreach($row in @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($expected.pid)" -OperationTimeoutSec 3)){
            if($row.CreationDate -and ([DateTimeOffset]$row.CreationDate).UtcDateTime -lt ([DateTimeOffset]$expected.created_utc).UtcDateTime){continue}
            $identity=Convert-S160Identity $row
            if(!$identity){
                $partial=[ordered]@{pid=[int]$row.ProcessId;parent_pid=[int]$row.ParentProcessId;created_utc=if($row.CreationDate){([DateTimeOffset]$row.CreationDate).UtcDateTime.ToString('o')}else{$null};missing_executable=!$row.ExecutablePath;missing_command_line=!$row.CommandLine;missing_creation=!$row.CreationDate;kill_authority=$false;status='incomplete';observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
                $Context.partial.Add($partial)
                for($attempt=0;$attempt -lt 2;$attempt++){
                    $again=Get-S160Live ([int]$row.ProcessId)
                    if(!$again){$partial.status='absent_on_requery';break}
                    if($partial.created_utc -and $again.CreationDate -and [Math]::Abs((([DateTimeOffset]$again.CreationDate).UtcDateTime-([DateTimeOffset]$partial.created_utc).UtcDateTime).TotalMilliseconds) -gt 1){$partial.status='original_pid_reused';break}
                    $identity=Convert-S160Identity $again
                    if($identity -and $partial.created_utc -and [int]$identity.parent_pid -eq [int]$partial.parent_pid){$partial.status='full_identity_recovered';break}
                    $identity=$null
                }
                Write-S160Json (Join-Path $Context.run ($Context.label+'-partial-identities.json')) $Context.partial.ToArray()
            }
            if($identity){Add-S160Identity $Context $identity}
        }
    }
}
function New-S160Context([string]$Run,[string]$Label){
    @{run=$Run;label=$Label;known=[Collections.Generic.List[object]]::new();partial=[Collections.Generic.List[object]]::new()}
}
function Start-S160Process($Context,[string]$Name,[string]$Executable,[string[]]$Arguments){
    Assert-S160Contained $Context.run (Join-Path (Get-S160Workspace).evidence 'retry698a-runtime-free-captures')|Out-Null
    $free=(Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 3).FreePhysicalMemory
    Write-S160Json (Join-Path $Context.run ($Name+'-reservation.json')) @{free_kib=$free;required_free_kib=16MB;source_reserved_kib=2MB;admitted=($free -ge 16MB);observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
    if($free -lt 16MB){throw 'Automatic fresh16GiB child admission denied'}
    $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$Executable;$info.WorkingDirectory=$Context.run
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $info.Environment.Clear();$safe=Get-S160Environment $Context.run
    foreach($key in $safe.Keys){$info.Environment[$key]=[string]$safe[$key]}
    foreach($argument in $Arguments){$info.ArgumentList.Add($argument)}
    $process=[Diagnostics.Process]::new();$process.StartInfo=$info
    if(!$process.Start()){throw 'Owned process did not start'}
    $created=$process.StartTime.ToUniversalTime();$out=$process.StandardOutput.ReadToEndAsync();$err=$process.StandardError.ReadToEndAsync()
    $identity=$null
    for($attempt=0;$attempt -lt 2;$attempt++){
        try{$live=Get-S160Live $process.Id;$identity=Convert-S160Identity $live}catch{$identity=$null}
        if($identity){break}
    }
    $retained=[ordered]@{pid=$process.Id;executable=$Executable;created_utc=$created.ToString('o');arguments=$Arguments;full_live_identity=$identity;retained_kernel_handle=$true;stdout_pipe_bounded_by_parent=$true}
    Write-S160Json (Join-Path $Context.run ($Name+'-launch.json')) $retained
    if($identity){
        if($identity.executable -cne $Executable -or [Math]::Abs((([DateTimeOffset]$identity.created_utc).UtcDateTime-$created).TotalMilliseconds) -gt 1){throw 'Retained kernel/live identity disagreement'}
        Add-S160Identity $Context $identity
    }else{
        $Context.partial.Add(@{pid=$process.Id;parent_pid=$PID;created_utc=$created.ToString('o');kill_authority=$false;status='launched_full_cim_identity_missing'})
        Write-S160Json (Join-Path $Context.run ($Context.label+'-partial-identities.json')) $Context.partial.ToArray()
    }
    @{name=$Name;process=$process;out=$out;err=$err;identity=$identity;retained=$retained;started=[DateTimeOffset]::UtcNow}
}
function Stop-S160Verified($Identity){
    if(!$Identity){return $false}
    $live=Get-S160Live $Identity.pid
    if(!$live){return $true}
    if(!(Test-S160Same $Identity $live)){return $false}
    if($Identity.executable -cnotin @($s160Pwsh,$s160Node,'C:\Program Files\Git\cmd\git.exe','C:\Program Files\Git\mingw64\bin\git.exe') -or $Identity.executable -match '(?i)codex'){throw 'Unapproved executable has no termination authority'}
    $handle=[Diagnostics.Process]::GetProcessById([int]$Identity.pid)
    try{
        if([Math]::Abs(($handle.StartTime.ToUniversalTime()-([DateTimeOffset]$Identity.created_utc).UtcDateTime).TotalMilliseconds) -gt 1){return $false}
        # Recheck immediately before using the retained handle; no process-tree kill.
        if(!(Test-S160Same $Identity (Get-S160Live $Identity.pid))){return $false}
        $handle.Kill($false);return $handle.WaitForExit(10000)
    }finally{$handle.Dispose()}
}
function Finish-S160Process($Context,$Child,[bool]$TimedOut){
    if(!$Child.process.HasExited){throw 'Owned child has no terminal kernel state'}
    $pipes=$Child.out.Wait(2000) -and $Child.err.Wait(2000)
    if($pipes){
        [IO.File]::WriteAllText((Join-Path $Context.run ($Child.name+'.stdout.log')),$Child.out.Result)
        [IO.File]::WriteAllText((Join-Path $Context.run ($Child.name+'.stderr.log')),$Child.err.Result)
    }
    $record=@{name=$Child.name;identity=$Child.identity;retained=$Child.retained;terminal_kernel_handle=$Child.process.HasExited;exit_code=$Child.process.ExitCode;timed_out=$TimedOut;pipes_settled=$pipes;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
    Write-S160Json (Join-Path $Context.run ($Child.name+'-terminal.json')) $record
    # Keep the retained kernel handle available to the outer negative path until
    # that owner exits. There are only a bounded number of children in this scope.
    if(!$Child.identity -or !$pipes -or $TimedOut -or $record.exit_code -ne 0){throw ('Owned child negative: '+$Child.name)}
    return $record
}
function Wait-S160Process($Context,$Child,[int]$Seconds){
    $until=$Child.started.AddSeconds($Seconds)
    while(!$Child.process.WaitForExit(500)){
        Observe-S160Descendants $Context
        if([DateTimeOffset]::UtcNow -ge $until){
            $settleUntil=[DateTimeOffset]::UtcNow.AddSeconds(20)
            foreach($identity in @($Context.known.ToArray()|Sort-Object created_utc -Descending)){
                if([DateTimeOffset]::UtcNow -ge $settleUntil){break}
                if($identity.pid -ne $PID){Stop-S160Verified $identity|Out-Null}
            }
            if(!$Child.process.WaitForExit(1000)){throw 'Owned child timeout could not be reconciled; preserve/no handoff'}
            return Finish-S160Process $Context $Child $true
        }
    }
    Finish-S160Process $Context $Child $false
}
function Get-S160Absence($Identities,$Partial){
    # One bounded snapshot; never print or retain unrelated rows.
    $snapshot=@(Get-CimInstance Win32_Process -OperationTimeoutSec 3 -ErrorAction Stop)
    $rows=@(foreach($expected in @($Identities)){
        $live=$snapshot|Where-Object ProcessId -eq ([int]$expected.pid)|Select-Object -First 1
        # An incomplete live CIM row is unknown, never absence or kill authority.
        $unknown=$live -and !(Convert-S160Identity $live)
        $same=Test-S160Same $expected $live
        @{identity=$expected;original_identity_absent=(!$same -and !$unknown);identity_unknown=[bool]$unknown;pid_reused=([bool]$live -and !$same -and !$unknown)}
    })
    $partials=@(foreach($expected in @($Partial)){
        $live=$snapshot|Where-Object ProcessId -eq ([int]$expected.pid)|Select-Object -First 1
        $different=$live -and $expected.created_utc -and $live.CreationDate -and [Math]::Abs((([DateTimeOffset]$live.CreationDate).UtcDateTime-([DateTimeOffset]$expected.created_utc).UtcDateTime).TotalMilliseconds) -gt 1
        @{observation=$expected;original_identity_absent=(!$live -or $different);kill_authority=$false}
    })
    @{rows=$rows;partial_rows=$partials;present_or_unknown=@($rows|Where-Object {!$_.original_identity_absent}).Count+@($partials|Where-Object {!$_.original_identity_absent}).Count;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
}
function Invoke-S160Git([string]$Directory,[string[]]$Arguments){
    $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$s160Git;$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    foreach($arg in @('-C',$Directory)+$Arguments){$info.ArgumentList.Add($arg)}
    # The bounded phase already has an explicitly cleared environment.
    $process=[Diagnostics.Process]::new();$process.StartInfo=$info
    if(!$process.Start()){throw 'Pinned Git failed to start'}
    try{
        $out=$process.StandardOutput.ReadToEndAsync();$err=$process.StandardError.ReadToEndAsync()
        if(!$process.WaitForExit(20000) -or !$out.Wait(1000) -or !$err.Wait(1000)){throw 'Git20s bound failed; enclosing phase retains descendant ownership'}
        if($process.ExitCode -ne 0){throw 'Pinned Git identity/inventory check failed'}
        return $out.Result.TrimEnd("`r","`n")
    }finally{$process.Dispose()}
}
