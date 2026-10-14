$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Assert-ChordResourceMacPartitions.ps1')
$lines=[Collections.Generic.List[string]]::new()
foreach($partition in 0..1){
 $start=$partition*429;$end=$start+429
 $lines.Add('CHORD_RESOURCE_MAC_GPA_BASELINE_ALLOCATIONS=858')
 foreach($index in $start..($end-1)){$lines.Add('CHORD_RESOURCE_MAC_GPA_INDEX='+(@{partition=$partition;index=$index;baseline=858}|ConvertTo-Json -Compress))}
 $lines.Add('CHORD_RESOURCE_MAC_GPA_PARTITION='+(@{partition=$partition;start=$start;end=$end;baseline=858;completed=429;leaks=0;unexpected_errors=0}|ConvertTo-Json -Compress))
}
$valid=$lines -join "`n"
$proof=Assert-ChordResourceMacPartitions $valid
if($proof.completed -ne 858 -or $proof.gaps -or $proof.duplicates){throw 'Complete Resource partition collector positive failed'}
$negatives=@(
 ($valid -replace '"partition":1','"partition":0'),
 ($valid -replace '"baseline":858','"baseline":857'),
 ($valid -replace '"start":429','"start":430'),
 ($valid -replace '"start":429','"start":428'),
 ($valid -replace '"completed":429','"completed":428'),
 ($valid -replace '"leaks":0','"leaks":1'),
 ($valid -replace '"unexpected_errors":0','"unexpected_errors":1'),
 ($valid+"`n"+$valid),
 ($valid -replace 'CHORD_RESOURCE_MAC_GPA_BASELINE_ALLOCATIONS=858','CHORD_RESOURCE_MAC_GPA_BASELINE_ALLOCATIONS=857'),
 ($valid -replace '"index":857','"index":856'),
 ($valid -replace 'CHORD_RESOURCE_MAC_GPA_INDEX=','REMOVED_INDEX=')
)
$count=0
foreach($log in $negatives){$rejected=$false;try{Assert-ChordResourceMacPartitions $log|Out-Null}catch{$rejected=$true};if(!$rejected){throw 'Incomplete Resource partition accepted'};$count++}
[ordered]@{positive=1;negative=$count;native_runtime_executed=$false;status='passed'}|ConvertTo-Json