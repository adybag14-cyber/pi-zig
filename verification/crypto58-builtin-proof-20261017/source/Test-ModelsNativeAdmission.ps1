# Pure in-memory regression candidate; no CIM query, process start or kill.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Get-ModelsNativeCandidates.ps1')
$taskContainer='C:\Users\adyba\pi-zig'
$taskCreation=[DateTimeOffset]'2026-10-16T00:00:00Z'
$taskCases=@(
 @{name='uppercase zig with missing executable';row=@{ProcessId=1;Name='ZIG.EXE';ExecutablePath=$null;CommandLine=$null;CreationDate=$taskCreation};count=1;incomplete=$true},
 @{name='missing build executable';row=@{ProcessId=2;Name='build.exe';ExecutablePath=$null;CommandLine=$null;CreationDate=$taskCreation};count=1;incomplete=$true},
 @{name='missing test executable';row=@{ProcessId=3;Name='test.exe';ExecutablePath=$null;CommandLine=$null;CreationDate=$taskCreation};count=1;incomplete=$true},
 @{name='mixed-case zig suffix';row=@{ProcessId=4;Name='other';ExecutablePath='C:\tools\ZiG.ExE';CommandLine='owned';CreationDate=$taskCreation};count=1;incomplete=$false},
 @{name='custom cache command only';row=@{ProcessId=5;Name='custom.exe';ExecutablePath=$null;CommandLine='"C:/Users/adyba/pi-zig/worktrees/a/.zig-cache/o/hash/custom.exe"';CreationDate=$taskCreation};count=1;incomplete=$true},
 @{name='contained output executable';row=@{ProcessId=6;Name='custom.exe';ExecutablePath='C:\USERS\ADYBA\PI-ZIG\main\ZIG-OUT\bin\custom.exe';CommandLine='owned';CreationDate=$taskCreation};count=1;incomplete=$false},
 @{name='unclassified incomplete row';row=@{ProcessId=7;Name=$null;ExecutablePath=$null;CommandLine=$null;CreationDate=$taskCreation};count=1;incomplete=$true},
 @{name='ordinary protected system process';row=@{ProcessId=8;Name='System';ExecutablePath=$null;CommandLine=$null;CreationDate=$taskCreation};count=0;incomplete=$null},
 @{name='top-level contained cache command only';row=@{ProcessId=9;Name='custom.exe';ExecutablePath=$null;CommandLine='"C:\Users\adyba\pi-zig\.zig-cache\o\hash\custom.exe"';CreationDate=$taskCreation};count=1;incomplete=$true}
)
foreach($taskCase in $taskCases){
 $taskActual=@(Get-ModelsNativeCandidates -Rows @([pscustomobject]$taskCase.row) -Container $taskContainer)
 if($taskActual.Count -ne $taskCase.count-or($taskCase.count-and$taskActual[0].incomplete_identity -ne $taskCase.incomplete)){throw "Native admission classification mismatch: $($taskCase.name)"}
}
