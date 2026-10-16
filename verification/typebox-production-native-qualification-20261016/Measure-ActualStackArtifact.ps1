param([Parameter(Mandatory)][string]$Binary,[Parameter(Mandatory)][string]$Pdb,[Parameter(Mandatory)][string]$ReceiptBase)
$ErrorActionPreference='Stop'
$taskTool='C:/Program Files/LLVM/bin/llvm-pdbutil.exe'
$taskExpectedTool='EBEFFD8BC9B9098C14FD087FD4CE7671E755B7570A5326AA625B8F9C01907A04'
if((Get-FileHash -LiteralPath $taskTool).Hash -cne $taskExpectedTool){throw 'Pinned PDB measurement tool drift'}
if(Test-Path -LiteralPath "$ReceiptBase.frames.json"){throw 'Refuse stack measurement overwrite'}
$taskBinaryHash=(Get-FileHash -LiteralPath $Binary).Hash
$taskPdbHash=(Get-FileHash -LiteralPath $Pdb).Hash
& $taskTool dump -symbols $Pdb > "$ReceiptBase.symbols.txt"
if($LASTEXITCODE){throw 'Actual artifact PDB symbol dump failed'}
$taskSymbols=[IO.File]::ReadAllText("$ReceiptBase.symbols.txt")
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
[ordered]@{scope='Fixed PDB frame sizes for this compiled artifact; no dynamic stack or parity claim';binary=[IO.Path]::GetFullPath($Binary);binary_sha256=$taskBinaryHash;pdb=[IO.Path]::GetFullPath($Pdb);pdb_sha256=$taskPdbHash;tool=$taskTool;tool_sha256=$taskExpectedTool;symbols_sha256=(Get-FileHash -LiteralPath "$ReceiptBase.symbols.txt").Hash;pe_reserved_stack_bytes=$taskStackReserve;pe_committed_stack_bytes=$taskStackCommit;requested=$taskSelected;largest_fixed_frames=@($taskFrames|Sort-Object frame_bytes -Descending|Select-Object -First 25);original_negative='b97 Source396 row391: native RangeError at assign14/create102 versus genuine source policy Error at assign129/create792; retained original packet unchanged'}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath "$ReceiptBase.frames.json" -Encoding utf8NoBOM
