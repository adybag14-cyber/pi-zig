param([Parameter(Mandatory)][string]$Binary,[Parameter(Mandatory)][string]$Pdb,[Parameter(Mandatory)][string]$ReceiptBase)
$ErrorActionPreference='Stop'
$taskTool='C:/Program Files/LLVM/bin/llvm-pdbutil.exe'
$taskExpectedTool='EBEFFD8BC9B9098C14FD087FD4CE7671E755B7570A5326AA625B8F9C01907A04'
if((Get-FileHash -LiteralPath $taskTool).Hash -cne $taskExpectedTool){throw 'Pinned PDB measurement tool drift'}
if(@(Get-ChildItem -LiteralPath ([IO.Path]::GetDirectoryName($ReceiptBase)) -Filter "$([IO.Path]::GetFileName($ReceiptBase))*" -File).Count){throw 'Refuse stack measurement overwrite'}
$taskBinaryHash=(Get-FileHash -LiteralPath $Binary).Hash
$taskPdbHash=(Get-FileHash -LiteralPath $Pdb).Hash
$taskRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $taskRoot 'tools/ci/native_qualification_ci.ps1')
$taskOwned=Invoke-CiOwnedProcess $taskTool @('dump','-symbols',$Pdb) $taskRoot "$ReceiptBase-pdb-owner" 60
$taskOwnerRecord=@($taskOwned|Where-Object {$null-ne$_.pid})
if($taskOwnerRecord.Count-ne1-or$taskOwnerRecord[0].status-cne'passed'-or$taskOwnerRecord[0].exit_code-ne0-or$taskOwnerRecord[0].executable_sha256-cne$taskExpectedTool-or$taskOwnerRecord[0].timeout_seconds-ne60){throw 'Terminal matching bounded PDB measurement owner required'}
$taskRemaining=@(Get-CimInstance Win32_Process -Filter "ProcessId = $($taskOwnerRecord[0].pid)")
[ordered]@{pid=$taskOwnerRecord[0].pid;executable=$taskOwnerRecord[0].executable;created_utc=$taskOwnerRecord[0].created_utc;pid_present=$taskRemaining.Count;observed_utc=[DateTimeOffset]::UtcNow.ToString('o');remaining=@($taskRemaining|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine,CreationDate)}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath "$ReceiptBase-pdb-owner-absence.json" -Encoding utf8NoBOM
if($taskRemaining.Count){throw 'PDB measurement owner PID remains present'}
$taskSymbolsPath="$ReceiptBase-pdb-owner.stdout.bin"
$taskSymbols=[IO.File]::ReadAllText($taskSymbolsPath)
$taskPattern='S_[LG]PROC32[^\r\n]*?`(?<name>[^`]+)`[\s\S]{0,500}?S_FRAMEPROC[^\r\n]*[\r\n]+\s*size = (?<size>\d+)'
$taskFrames=@(foreach($entry in [regex]::Matches($taskSymbols,$taskPattern)){[ordered]@{name=$entry.Groups['name'].Value;frame_bytes=[int]$entry.Groups['size'].Value}})
$taskRequested=@('f_0','f_1','f_9','f_625','f_628','f_637','f_638','f_642','f_660','f_661','f_662','f_663','f_664','f_675','try_block_0','runBranch','JS_CallInternal','JS_CallInternalBody','js_call_c_function','JS_Call','js_array_reduce')
$taskSelected=@(foreach($name in $taskRequested){$found=@($taskFrames|Where-Object name -ceq $name);[ordered]@{name=$name;matches=$found.Count;frames=$found}})
$taskBytes=[IO.File]::ReadAllBytes($Binary)
$taskPe=[BitConverter]::ToInt32($taskBytes,0x3c)
if([BitConverter]::ToUInt32($taskBytes,$taskPe)-ne0x4550-or[BitConverter]::ToUInt16($taskBytes,$taskPe+24)-ne0x20b){throw 'Expected PE32+ native artifact'}
$taskStackReserve=[BitConverter]::ToUInt64($taskBytes,$taskPe+24+72)
$taskStackCommit=[BitConverter]::ToUInt64($taskBytes,$taskPe+24+80)
if((Get-FileHash -LiteralPath $Binary).Hash -cne $taskBinaryHash-or(Get-FileHash -LiteralPath $Pdb).Hash -cne $taskPdbHash){throw 'Artifact changed during stack measurement'}
[ordered]@{scope='Fixed PDB frame sizes for this compiled artifact; no dynamic stack or parity claim';binary=[IO.Path]::GetFullPath($Binary);binary_sha256=$taskBinaryHash;pdb=[IO.Path]::GetFullPath($Pdb);pdb_sha256=$taskPdbHash;tool=$taskTool;tool_sha256=$taskExpectedTool;owner=$taskOwnerRecord[0];owner_deadline_seconds=60;owner_settle_seconds=10;symbols_path=$taskSymbolsPath;symbols_sha256=(Get-FileHash -LiteralPath $taskSymbolsPath).Hash;pe_reserved_stack_bytes=$taskStackReserve;pe_committed_stack_bytes=$taskStackCommit;requested=$taskSelected;largest_fixed_frames=@($taskFrames|Sort-Object frame_bytes -Descending|Select-Object -First 25);original_negative='b97 Source396 row391: native RangeError at assign14/create102 versus genuine source policy Error at assign129/create792; retained original packet unchanged'}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath "$ReceiptBase.frames.json" -Encoding utf8NoBOM
