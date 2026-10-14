function Assert-ChordExpandedStatePartitions {
 param([Parameter(Mandatory)][string]$Log,[long]$ExpectedBaseline=2061)
 $markers=[regex]::Matches($Log,'CHORD_EXPANDED_STATE_GPA_PARTITION=(\{[^\r\n]*\})')
 if($markers.Count -ne 4){throw 'Complete expanded State28 GPA requires exactly four partition receipts'}
 $rows=@($markers|ForEach-Object {$_.Groups[1].Value|ConvertFrom-Json}|Sort-Object partition)
 foreach($row in $rows){
  foreach($field in @('partition','start','end','baseline','completed','leaks','unexpected_errors')){
   $value=$row.$field
   if($null -eq $value -or $value -isnot [ValueType] -or $value -is [bool] -or [decimal]$value -ne [math]::Truncate([decimal]$value) -or $value -lt 0){throw 'Invalid expanded State28 partition field'}
  }
 }
 $total=$rows[0].baseline
 if($total -le 3 -or $total -ne $ExpectedBaseline){throw 'Actual measured expanded State28 baseline changed'}
 for($index=0;$index -lt 4;$index++){
  $row=$rows[$index]
  $start=[long][math]::Floor($total*$index/4.0)
  $end=[long][math]::Floor($total*($index+1)/4.0)
  if($row.partition -ne $index -or $row.baseline -ne $total -or $row.start -ne $start -or $row.end -ne $end){throw 'Expanded State28 partition ranges contain gaps duplicates or baseline disagreement'}
  if($row.completed -ne $end-$start -or $row.leaks -ne 0 -or $row.unexpected_errors -ne 0){throw 'Incomplete or failed expanded State28 allocation partition'}
 }
 $baselines=[regex]::Matches($Log,'CHORD_EXPANDED_STATE_GPA_BASELINE_ALLOCATIONS=(\d+)')
 if($baselines.Count -ne 4 -or @($baselines|Where-Object {[long]$_.Groups[1].Value -ne $total}).Count){throw 'Missing or conflicting expanded State28 baseline measurements'}
 return [ordered]@{baseline=$total;partitions=$rows;start=0;end=$total;completed=$total;gaps=0;duplicates=0;leaks=0;unexpected_errors=0;whole_original_probe_and_gc_each_index=$true;c_malloc_exhaustive=$false}
}
