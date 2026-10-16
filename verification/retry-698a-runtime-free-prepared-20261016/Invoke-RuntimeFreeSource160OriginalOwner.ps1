param([Parameter(Mandatory)][string]$Config,[Parameter(Mandatory)][string]$ConfigSha256)
. ($PSScriptRoot+'\RuntimeFreeSource160.Common.ps1')
Initialize-S160OwnedChild $PSCommandPath
if((Get-S160Sha $Config) -cne $ConfigSha256){throw 'Exact original-owner invocation config required'}
$task=Read-S160Json $Config
Assert-S160Environment $task.run|Out-Null
if((Get-S160Sha $task.owner_copy) -cne $s160OwnerSha){throw 'Untouched96BE owner bytes required'}
$command=Read-S160Json (Join-Path $task.run 'node-command.json')
if($command.TimeoutSeconds -ne 300 -or $command.SettleSeconds -ne 10 -or $command.Executable -cne $task.node -or $command.WorkingDirectory -cne $task.run -or $command.Name -cne 'source160'){throw 'Exact Source160 owner command required'}
& $task.owner_copy -Name 'source160' -Executable $task.node -WorkingDirectory $task.run -Arguments ([string[]]$command.Arguments) -TimeoutSeconds 300 -SettleSeconds 10
