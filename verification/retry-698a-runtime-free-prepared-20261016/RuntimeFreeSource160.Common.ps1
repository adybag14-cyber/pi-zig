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
function Get-S160StartupPolicy {
    @{directories=@('profile','temp','profile\AppData','profile\AppData\Local','profile\AppData\Local\Microsoft','profile\AppData\Local\Microsoft\PowerShell');file='profile\AppData\Local\Microsoft\PowerShell\StartupProfileData-NonInteractive';max_file_bytes=1MB}
}
function Write-S160CreateNewJson([string]$Path,$Value){
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-Json -InputObject $Value -Depth 30))
    $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
}
function New-S160LaunchClaim([string]$Run,[string]$RunId,[string]$CandidateHead,[string]$GrantPath,$Launcher){
    Assert-S160Contained $Run (Join-Path (Get-S160Workspace).evidence 'retry698a-runtime-free-captures')|Out-Null
    if(Test-Path -LiteralPath $Run){throw 'Launcher claim refuses every existing run'}
    # New-Item without Force fails if another claimant wins the directory race.
    New-Item -ItemType Directory -Path $Run -ErrorAction Stop|Out-Null
    $policy=Get-S160StartupPolicy;$path=Join-Path $Run 'launcher-claim.json'
    $claim=[ordered]@{schema=1;scope='Source160LauncherClaim';run_id=$RunId;run=$Run;candidate_head=$CandidateHead;grant_sha256=Get-S160Sha $GrantPath;nonce=[Guid]::NewGuid().ToString('N');launcher_identity=$Launcher;created_utc=[DateTimeOffset]::UtcNow.ToString('o');allowed_startup_directories=$policy.directories;allowed_startup_file=$policy.file;max_startup_file_bytes=$policy.max_file_bytes}
    Write-S160CreateNewJson $path $claim
    @{path=$path;sha256=Get-S160Sha $path;claim=$claim}
}
function Accept-S160LaunchClaim([string]$Run,[string]$RunId,[string]$CandidateHead,[string]$GrantPath,[string]$ClaimPath,[string]$ClaimSha256,$Self){
    Assert-S160Contained $Run (Join-Path (Get-S160Workspace).evidence 'retry698a-runtime-free-captures')|Out-Null
    if($ClaimPath -cne (Join-Path $Run 'launcher-claim.json') -or (Get-S160Sha $ClaimPath) -cne $ClaimSha256){throw 'Exact sealed launcher claim required'}
    $claim=Read-S160Json $ClaimPath;$policy=Get-S160StartupPolicy;$grant=Read-S160Json $GrantPath
    $fields=@('schema','scope','run_id','run','candidate_head','grant_sha256','nonce','launcher_identity','created_utc','allowed_startup_directories','allowed_startup_file','max_startup_file_bytes')
    if(@($claim.PSObject.Properties.Name|Where-Object {$_ -notin $fields}).Count -or $claim.schema -ne 1 -or $claim.scope -cne 'Source160LauncherClaim' -or $claim.run_id -cne $RunId -or $claim.run -cne $Run -or $claim.candidate_head -cne $CandidateHead -or $claim.grant_sha256 -cne (Get-S160Sha $GrantPath) -or $claim.nonce -cnotmatch '^[a-f0-9]{32}$' -or ([DateTimeOffset]$claim.created_utc) -lt ([DateTimeOffset]$grant.issued_utc) -or ([DateTimeOffset]$claim.created_utc) -gt [DateTimeOffset]::UtcNow -or ([DateTimeOffset]$claim.created_utc) -ge ([DateTimeOffset]$grant.expires_utc) -or (@($claim.allowed_startup_directories) -join [char]0) -cne ($policy.directories -join [char]0) -or $claim.allowed_startup_file -cne $policy.file -or $claim.max_startup_file_bytes -ne $policy.max_file_bytes){throw 'Launcher claim identity/policy mismatch'}
    if(!$Self -or ([DateTimeOffset]$Self.created_utc).UtcDateTime -lt ([DateTimeOffset]$claim.created_utc).UtcDateTime.AddMilliseconds(-1) -or [int]$Self.parent_pid -ne [int]$claim.launcher_identity.pid -or !(Test-S160Same $claim.launcher_identity (Get-S160Live ([int]$claim.launcher_identity.pid)))){throw 'Claim launcher is not exact live supervisor parent'}
    $rows=[Collections.Generic.List[object]]::new();$pending=[Collections.Generic.Stack[string]]::new();$pending.Push($Run)
    while($pending.Count){foreach($item in @(Get-ChildItem -LiteralPath $pending.Pop() -Force)){
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Startup claim rejects reparse state'}
        $relative=$item.FullName.Substring($Run.Length+1)
        if($item.PSIsContainer){if($relative -cnotin $policy.directories){throw 'Unapproved existing startup directory'};$pending.Push($item.FullName);$rows.Add(@{relative=$relative;directory=$true})}
        else{
            if($relative -cne 'launcher-claim.json' -and $relative -cne $policy.file){throw 'Existing run file is not exact claimed startup state'}
            if($relative -ceq $policy.file -and $item.Length -gt $policy.max_file_bytes){throw 'Startup profile data exceeds reviewed bound'}
            $rows.Add(@{relative=$relative;directory=$false;bytes=$item.Length;sha256=Get-S160Sha $item.FullName})
        }
    }}
    $accepted=Join-Path $Run 'supervisor-claim-accepted.json'
    # Exclusive creation is the replay fence, including simultaneous invocations.
    Write-S160CreateNewJson $accepted @{run_id=$RunId;candidate_head=$CandidateHead;claim_sha256=$ClaimSha256;claim_nonce=$claim.nonce;grant_sha256=$claim.grant_sha256;supervisor_identity=$Self;launcher_identity=$claim.launcher_identity;startup_state=$rows.ToArray();mutable_owned_profile_data=$policy.file;accepted_utc=[DateTimeOffset]::UtcNow.ToString('o')}
    @{claim_path=$ClaimPath;claim_sha256=$ClaimSha256;acceptance_path=$accepted;acceptance_sha256=Get-S160Sha $accepted}
}
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
    if(!$Row -or !$Row.ProcessId -or $null -eq $Row.ParentProcessId -or !$Row.ExecutablePath -or !$Row.CommandLine -or !$Row.CreationDate){return $null}
    [ordered]@{pid=[int]$Row.ProcessId;parent_pid=[int]$Row.ParentProcessId;executable=[string]$Row.ExecutablePath;command_line=[string]$Row.CommandLine;created_utc=([DateTimeOffset]$Row.CreationDate).UtcDateTime.ToString('o')}
}
function Split-S160WindowsArgv([string]$CommandLine){
    # Pure Windows CRT quote/backslash parsing; no host process or native helper.
    $result=[Collections.Generic.List[string]]::new();$index=0
    while($index -lt $CommandLine.Length){
        while($index -lt $CommandLine.Length -and $CommandLine[$index] -in @([char]32,[char]9)){$index++}
        if($index -ge $CommandLine.Length){break}
        $argument=[Text.StringBuilder]::new();$quoted=$false
        while($index -lt $CommandLine.Length){
            if(!$quoted -and $CommandLine[$index] -in @([char]32,[char]9)){break}
            $slashes=0
            while($index -lt $CommandLine.Length -and $CommandLine[$index] -eq [char]92){$slashes++;$index++}
            if($index -lt $CommandLine.Length -and $CommandLine[$index] -eq [char]34){
                [void]$argument.Append([char]92,[int][Math]::Floor($slashes/2))
                if($slashes%2){[void]$argument.Append([char]34);$index++}elseif($quoted -and $index+1 -lt $CommandLine.Length -and $CommandLine[$index+1] -eq [char]34){[void]$argument.Append([char]34);$index+=2}else{$quoted=!$quoted;$index++}
            }else{
                [void]$argument.Append([char]92,$slashes)
                if($index -ge $CommandLine.Length){break}
                if(!$quoted -and $CommandLine[$index] -in @([char]32,[char]9)){break}
                [void]$argument.Append($CommandLine[$index]);$index++
            }
        }
        if($quoted){throw 'Unclosed Windows command-line quote'}
        $result.Add($argument.ToString())
    }
    $result.ToArray()
}
function Test-S160Argv([string]$CommandLine,[string]$Executable,[string[]]$Arguments){
    $actual=@(Split-S160WindowsArgv $CommandLine);$intended=@($Executable)+@($Arguments)
    ($actual.Count -eq $intended.Count) -and (($actual -join [char]0) -ceq ($intended -join [char]0))
}
function Test-S160Same($Expected,$Row){
    $Row -and $Row.CreationDate -and [int]$Row.ProcessId -eq [int]$Expected.pid -and [int]$Row.ParentProcessId -eq [int]$Expected.parent_pid -and [string]$Row.ExecutablePath -ceq $Expected.executable -and [string]$Row.CommandLine -ceq $Expected.command_line -and [Math]::Abs((([DateTimeOffset]$Row.CreationDate).UtcDateTime-([DateTimeOffset]$Expected.created_utc).UtcDateTime).TotalMilliseconds) -le 1
}
function Add-S160Identity($Context,$Identity){
    if($Identity -and !@($Context.known|Where-Object {$_.pid -eq $Identity.pid -and $_.created_utc -ceq $Identity.created_utc}).Count){
        $Context.known.Add($Identity);Write-S160Json (Join-Path $Context.ledger_root ($Context.label+'-identities.json')) $Context.known.ToArray()
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
                Write-S160Json (Join-Path $Context.ledger_root ($Context.label+'-partial-identities.json')) $Context.partial.ToArray()
            }
            if($identity){Add-S160Identity $Context $identity}
        }
    }
}
function New-S160Context([string]$Run,[string]$Label,[string]$LedgerRoot=$Run){
    @{run=$Run;ledger_root=$LedgerRoot;label=$Label;known=[Collections.Generic.List[object]]::new();partial=[Collections.Generic.List[object]]::new();children=[Collections.Generic.List[object]]::new();git_sequence=0}
}
function Start-S160Process($Context,[string]$Name,[string]$Executable,[string[]]$Arguments,[bool]$AllowTerminalReadOnlyGit=$false){
    Assert-S160Contained $Context.run (Join-Path (Get-S160Workspace).evidence 'retry698a-runtime-free-captures')|Out-Null
    Assert-S160Contained $Context.ledger_root (Join-Path (Get-S160Workspace).evidence 'retry698a-runtime-free-captures')|Out-Null
    $free=(Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 3).FreePhysicalMemory
    Write-S160Json (Join-Path $Context.ledger_root ($Name+'-reservation.json')) @{free_kib=$free;required_free_kib=16MB;source_reserved_kib=2MB;admitted=($free -ge 16MB);observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
    if($free -lt 16MB){throw 'Automatic fresh16GiB child admission denied'}
    $executableSha=Get-S160Sha $Executable
    if($AllowTerminalReadOnlyGit -and $Executable -cne $s160Git){throw 'Terminal-only exception is exclusively pinned read-only Git'}
    $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$Executable;$info.WorkingDirectory=$Context.ledger_root
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $info.Environment.Clear();$safe=Get-S160Environment $Context.run
    foreach($key in $safe.Keys){$info.Environment[$key]=[string]$safe[$key]}
    foreach($argument in $Arguments){$info.ArgumentList.Add($argument)}
    $process=[Diagnostics.Process]::new();$process.StartInfo=$info
    if(!$process.Start()){throw 'Owned process did not start'}
    # Register the actual handle before StartTime/CIM/hash/argv probes or writes.
    $child=@{name=$Name;process=$process;out=$null;err=$null;identity=$null;retained=$null;validation_error=$null;terminal_git_only=$false;started=[DateTimeOffset]::UtcNow;launch_path=(Join-Path $Context.ledger_root ($Name+'-launch.json'))}
    $Context.children.Add($child)
    $partial=[ordered]@{pid=$process.Id;parent_pid=$PID;created_utc=$null;expected_executable=$Executable;executable_sha256=$executableSha;intended_arguments=$Arguments;origin='retained_direct_launch';kill_authority=$false;status='kernel_registered_before_probes'}
    $Context.partial.Add($partial)
    $child.retained=$partial
    try{
        Write-S160Json $child.launch_path @{retained=$partial;identity=$null;status='kernel_registered_before_probes'}
        Write-S160Json (Join-Path $Context.ledger_root ($Context.label+'-partial-identities.json')) $Context.partial.ToArray()
        $partial.created_utc=$process.StartTime.ToUniversalTime().ToString('o')
        Write-S160Json $child.launch_path @{retained=$partial;identity=$null;status='kernel_creation_registered_before_cim'}
        $child.out=$process.StandardOutput.ReadToEndAsync();$child.err=$process.StandardError.ReadToEndAsync()
        for($attempt=0;$attempt -lt 2;$attempt++){
            try{$identity=Convert-S160Identity (Get-S160Live $process.Id)}catch{$identity=$null}
            if($identity){break}
        }
        if(!$identity){
            if($AllowTerminalReadOnlyGit -and $process.HasExited -and $process.ExitCode -eq 0){
                $child.terminal_git_only=$true;$partial.status='read_only_git_kernel_terminal_live_cim_unavailable'
            }else{throw 'Direct launch full CIM identity missing'}
        }else{
            $child.observed_identity=$identity
            if($identity.executable -cne $Executable -or [int]$identity.parent_pid -ne $PID -or [Math]::Abs((([DateTimeOffset]$identity.created_utc).UtcDateTime-([DateTimeOffset]$partial.created_utc).UtcDateTime).TotalMilliseconds) -gt 1 -or !(Test-S160Argv $identity.command_line $Executable $Arguments)){throw 'Direct launch kernel/parent/intended argv identity conflict'}
            $child.identity=$identity;$partial.status='full_parent_argv_kernel_verified'
            Add-S160Identity $Context $identity
        }
    }catch{
        $child.validation_error=$_.Exception.Message;$partial.status='launch_validation_negative'
        # A ledger/probe failure must not leave an undrained child blocked on pipes.
        try{if(!$child.out){$child.out=$process.StandardOutput.ReadToEndAsync()};if(!$child.err){$child.err=$process.StandardError.ReadToEndAsync()}}catch{$child.validation_error+='; pipe setup negative: '+$_.Exception.Message}
        # Reconcile only the registered original handle; the original negative stays.
        try{
            if(!$partial.created_utc){$partial.created_utc=$process.StartTime.ToUniversalTime().ToString('o')}
            $again=Convert-S160Identity (Get-S160Live $process.Id)
            if($again -and $again.executable -ceq $Executable -and [int]$again.parent_pid -eq $PID -and [Math]::Abs((([DateTimeOffset]$again.created_utc).UtcDateTime-([DateTimeOffset]$partial.created_utc).UtcDateTime).TotalMilliseconds) -le 1 -and (Test-S160Argv $again.command_line $Executable $Arguments)){$child.identity=$again;Add-S160Identity $Context $again}
        }catch{$child.validation_error+='; registered handle reconciliation negative: '+$_.Exception.Message}
    }
    # Never throw away a successfully started handle, including ledger I/O errors.
    try{
        Write-S160Json $child.launch_path @{retained=$partial;identity=$child.identity;observed_identity=$child.observed_identity;validation_error=$child.validation_error;status=$partial.status}
        Write-S160Json (Join-Path $Context.ledger_root ($Context.label+'-partial-identities.json')) $Context.partial.ToArray()
    }catch{$child.validation_error+='; launch ledger write failed: '+$_.Exception.Message}
    return $child
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
    $pipes=$false
    try{$pipes=$Child.out -and $Child.err -and $Child.out.Wait(2000) -and $Child.err.Wait(2000)}catch{$Child.validation_error='Bounded pipe completion failed: '+$_.Exception.Message}
    if($pipes){
        [IO.File]::WriteAllText((Join-Path $Context.ledger_root ($Child.name+'.stdout.log')),$Child.out.Result)
        [IO.File]::WriteAllText((Join-Path $Context.ledger_root ($Child.name+'.stderr.log')),$Child.err.Result)
    }
    $terminalGitAbsence=$null
    if($Child.terminal_git_only){
        $terminalGitAbsence=Get-S160Absence @() @($Child.retained)
        if($terminalGitAbsence.present_or_unknown -or (Get-S160Sha $Child.retained.expected_executable) -cne $Child.retained.executable_sha256){$Child.validation_error='Terminal read-only Git independent absence/executable seal failed'}
    }
    $record=@{name=$Child.name;identity=$Child.identity;retained=$Child.retained;validation_error=$Child.validation_error;terminal_kernel_handle=$Child.process.HasExited;exit_code=$Child.process.ExitCode;timed_out=$TimedOut;pipes_settled=[bool]$pipes;terminal_read_only_git_exception=[bool]$Child.terminal_git_only;live_cim_argv_available=[bool]$Child.identity;terminal_git_independent_absence=$terminalGitAbsence;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
    Write-S160Json (Join-Path $Context.ledger_root ($Child.name+'-terminal.json')) $record
    # Keep the retained kernel handle available to the outer negative path until
    # that owner exits. There are only a bounded number of children in this scope.
    if($Child.validation_error -or (!$Child.identity -and !$Child.terminal_git_only) -or !$pipes -or $TimedOut -or $record.exit_code -ne 0){throw ('Owned child negative: '+$Child.name+' '+$Child.validation_error)}
    return $record
}
function Wait-S160Process($Context,$Child,[int]$Seconds){
    $until=$Child.started.AddSeconds($Seconds)
    while(!$Child.process.WaitForExit(500)){
        try{Observe-S160Descendants $Context}catch{$Child.validation_error+='; during-wait identity observation negative: '+$_.Exception.Message}
        if([DateTimeOffset]::UtcNow -ge $until){
            $settleUntil=[DateTimeOffset]::UtcNow.AddSeconds(20)
            foreach($identity in @($Context.known.ToArray()|Sort-Object created_utc -Descending)){
                if([DateTimeOffset]::UtcNow -ge $settleUntil){break}
                if($identity.pid -ne $PID){try{Stop-S160Verified $identity|Out-Null}catch{$Child.validation_error='Verified settlement failed: '+$_.Exception.Message}}
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
        $different=$live -and $live.CreationDate -and $expected.created_utc -and [Math]::Abs((([DateTimeOffset]$live.CreationDate).UtcDateTime-([DateTimeOffset]$expected.created_utc).UtcDateTime).TotalMilliseconds) -gt 1
        @{identity=$expected;original_identity_absent=(!$live -or $different);identity_unknown=[bool]$unknown;identity_conflict=([bool]$live -and !$different -and !$same);pid_reused=[bool]$different}
    })
    $partials=@(foreach($expected in @($Partial)){
        $live=$snapshot|Where-Object ProcessId -eq ([int]$expected.pid)|Select-Object -First 1
        $different=$live -and $expected.created_utc -and $live.CreationDate -and [Math]::Abs((([DateTimeOffset]$live.CreationDate).UtcDateTime-([DateTimeOffset]$expected.created_utc).UtcDateTime).TotalMilliseconds) -gt 1
        @{observation=$expected;original_identity_absent=(!$live -or $different);kill_authority=$false}
    })
    @{rows=$rows;partial_rows=$partials;present_or_unknown=@($rows|Where-Object {!$_.original_identity_absent}).Count+@($partials|Where-Object {!$_.original_identity_absent}).Count;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
}
function Invoke-S160Git([string]$Directory,[string[]]$Arguments,$Context){
    if(!$Context){throw 'Git requires an established retained ownership context'}
    $allowed=($Arguments.Count -eq 2 -and $Arguments[0] -ceq 'rev-parse' -and $Arguments[1] -cin @('HEAD','HEAD^{tree}')) -or ($Arguments.Count -eq 1 -and $Arguments[0] -ceq 'ls-files') -or (($Arguments.Count -eq 2 -or $Arguments.Count -eq 3) -and $Arguments[0] -ceq 'status' -and $Arguments[1] -ceq '--porcelain' -and ($Arguments.Count -eq 2 -or $Arguments[2] -ceq '--untracked-files=no'))
    if(!$allowed){throw 'Only exact whitelisted read-only Git commands may use terminal-only proof'}
    $workspace=Get-S160Workspace
    $allowedDirectories=@([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')),(Join-Path $workspace.upstream 'snapshots/698a2d23-20261016'))
    if([IO.Path]::GetFullPath($Directory) -cnotin $allowedDirectories){throw 'Git may read only the exact assigned candidate or Source698 snapshot'}
    $hooks=Join-Path $Context.run 'disabled-git-hooks'
    Assert-S160Contained $hooks $Context.run|Out-Null
    [void][IO.Directory]::CreateDirectory($hooks)
    if(@(Get-ChildItem -LiteralPath $hooks -Force).Count){throw 'Owned disabled hooks directory must remain empty'}
    $Context.git_sequence++
    $child=Start-S160Process $Context ($Context.label+'-git'+$Context.git_sequence) $s160Git (@('--no-pager','--no-optional-locks','-c','core.fsmonitor=false','-c',('core.hooksPath='+$hooks),'-C',$Directory)+$Arguments) $true
    Wait-S160Process $Context $child 20|Out-Null
    return $child.out.Result.TrimEnd("`r","`n")
}
function Get-S160LaunchUnion([string]$Run){
    $known=[Collections.Generic.List[object]]::new();$partial=[Collections.Generic.List[object]]::new();$paths=[Collections.Generic.List[string]]::new()
    $files=@()
    foreach($root in @($Run,($Run+'.launcher'))){
        Assert-S160Contained $root (Join-Path (Get-S160Workspace).evidence 'retry698a-runtime-free-captures')|Out-Null
        if(Test-Path -LiteralPath $root){$files+=@(Get-ChildItem -LiteralPath $root -File -Filter '*.json')}
    }
    foreach($file in $files){
        if($file.Name -like '*-identities.json' -and $file.Name -notlike '*-partial-identities.json'){foreach($row in @(Read-S160Json $file.FullName)){$known.Add($row)};$paths.Add($file.FullName)}
        elseif($file.Name -like '*-partial-identities.json'){foreach($row in @(Read-S160Json $file.FullName)){$partial.Add($row)};$paths.Add($file.FullName)}
        elseif($file.Name -like '*-launch.json'){
            $record=Read-S160Json $file.FullName
            if($record.identity){$known.Add($record.identity)}
            if($record.retained){$partial.Add($record.retained)}elseif($record.pid){$partial.Add(@{pid=$record.pid;created_utc=$record.retained_created_utc;parent_pid=$record.expected_parent_pid;origin='external_launch_record'})}
            $paths.Add($file.FullName)
        }
        elseif($file.Name -ceq 'source160.json'){$record=Read-S160Json $file.FullName;$partial.Add(@{pid=$record.pid;created_utc=$record.created_utc;origin='original96BE_node_kernel_record';kill_authority=$false});$paths.Add($file.FullName)}
        elseif($file.Name -ceq 'start-fence-ready.json'){
            $record=Read-S160Json $file.FullName;$created=$null;$originalPath=Join-Path $Run 'source160.json'
            if(Test-Path -LiteralPath $originalPath){$original=Read-S160Json $originalPath;if($original.pid -eq $record.pid){$created=$original.created_utc}}
            $partial.Add(@{pid=$record.pid;created_utc=$created;origin='node_ready_pid_linked_to_optional_original96BE_record';kill_authority=$false});$paths.Add($file.FullName)
        }
        elseif($file.Name -like '*-self.json'){$record=Read-S160Json $file.FullName;if($record.identity){$known.Add($record.identity)}elseif($record.pid){$known.Add($record)};$paths.Add($file.FullName)}
    }
    @{known=$known.ToArray();partial=$partial.ToArray();launch_ledger_paths=$paths.ToArray()}
}
