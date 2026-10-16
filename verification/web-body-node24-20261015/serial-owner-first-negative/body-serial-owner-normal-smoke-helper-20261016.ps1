$ErrorActionPreference='Stop'
$child=Start-Process -FilePath 'C:\Program Files\PowerShell\7\pwsh.exe' -ArgumentList @('-NoProfile','-Command','Start-Sleep -Seconds 2; Write-Output child-terminal') -WindowStyle Hidden -PassThru
$child.WaitForExit()
Write-Output parent-terminal
