$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Assert-ChordComposedPartitions.ps1')
function Partition-Log([long]$Total) {
 $middle=[long][math]::Ceiling($Total/2.0)
 $first=@{partition=0;start=0;end=$middle;baseline=$Total;completed=$middle;leaks=0;unexpected_errors=0}|ConvertTo-Json -Compress
 $second=@{partition=1;start=$middle;end=$Total;baseline=$Total;completed=($Total-$middle);leaks=0;unexpected_errors=0}|ConvertTo-Json -Compress
 @("CHORD_COMPOSED_GPA_BASELINE_ALLOCATIONS=$Total",("CHORD_COMPOSED_GPA_PARTITION=$first"),"CHORD_COMPOSED_GPA_BASELINE_ALLOCATIONS=$Total",("CHORD_COMPOSED_GPA_PARTITION=$second")) -join "`n"
}
$positiveCount=0
foreach($total in @(3856,3843)){
 $proof=Assert-ChordComposedPartitions -Log (Partition-Log $total)
 if($proof.completed -ne $total -or $proof.gaps -or $proof.duplicates){throw 'Valid exact coverage was rejected'}
 $positiveCount++
}
$valid=Partition-Log 3856
$negativeLogs=@(
 ($valid -replace '"partition":1','"partition":0'),
 ($valid -replace '"baseline":3856','"baseline":3855'),
 ($valid -replace '"start":1928','"start":1929'),
 ($valid -replace '"start":1928','"start":1927'),
 ($valid -replace '"completed":1928','"completed":1927'),
 ($valid -replace '"leaks":0','"leaks":1'),
 ($valid -replace '"unexpected_errors":0','"unexpected_errors":1'),
 ($valid+"`n"+$valid),
 ($valid -replace 'CHORD_COMPOSED_GPA_BASELINE_ALLOCATIONS=3856','CHORD_COMPOSED_GPA_BASELINE_ALLOCATIONS=3855')
)
$negativeCount=0
foreach($negative in $negativeLogs){
 $rejected=$false
 try{$null=Assert-ChordComposedPartitions -Log $negative}catch{$rejected=$true}
 if(!$rejected){throw 'Invalid composed GPA coverage was accepted'}
 $negativeCount++
}
[ordered]@{positive=$positiveCount;negative=$negativeCount;status='passed';native_runtime_executed=$false}|ConvertTo-Json -Compress
