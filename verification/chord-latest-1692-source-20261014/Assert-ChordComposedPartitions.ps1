function Assert-ChordComposedPartitions {
 param([Parameter(Mandatory)][string]$Log)
 $partitionMarkers=[regex]::Matches($Log,'CHORD_COMPOSED_GPA_PARTITION=(\{[^\r\n]*\})')
 if($partitionMarkers.Count -ne 2){throw 'Complete composed GPA requires exactly two partition receipts'}
 $partitionRows=@($partitionMarkers|ForEach-Object{$_.Groups[1].Value|ConvertFrom-Json}|Sort-Object partition)
 foreach($partitionRow in $partitionRows){
  foreach($partitionField in @('partition','start','end','baseline','completed','leaks','unexpected_errors')){
   $partitionValue=$partitionRow.$partitionField
   if($null -eq $partitionValue -or $partitionValue -isnot [ValueType] -or $partitionValue -is [bool] -or [decimal]$partitionValue -ne [math]::Truncate([decimal]$partitionValue) -or $partitionValue -lt 0){throw 'Invalid composed GPA partition field'}
  }
 }
 $partitionTotal=$partitionRows[0].baseline
 $partitionMiddle=[long][math]::Ceiling($partitionTotal/2.0)
 if($partitionTotal -le 1 -or $partitionRows[1].baseline -ne $partitionTotal){throw 'Composed GPA baseline disagreement'}
 if($partitionRows[0].partition -ne 0 -or $partitionRows[1].partition -ne 1 -or $partitionRows[0].start -ne 0 -or $partitionRows[0].end -ne $partitionMiddle -or $partitionRows[1].start -ne $partitionMiddle -or $partitionRows[1].end -ne $partitionTotal){throw 'Composed GPA ranges contain gaps duplicates or changed boundaries'}
 foreach($partitionRow in $partitionRows){
  if($partitionRow.completed -ne ($partitionRow.end-$partitionRow.start) -or $partitionRow.leaks -ne 0 -or $partitionRow.unexpected_errors -ne 0){throw 'Incomplete or failed composed GPA partition'}
 }
 $partitionBaselines=[regex]::Matches($Log,'CHORD_COMPOSED_GPA_BASELINE_ALLOCATIONS=(\d+)')
 if($partitionBaselines.Count -ne 2 -or @($partitionBaselines|Where-Object{[long]$_.Groups[1].Value -ne $partitionTotal}).Count){throw 'Composed probe allocation baselines do not match completed partitions'}
 return [ordered]@{baseline=$partitionTotal;partitions=$partitionRows;start=0;end=$partitionTotal;completed=$partitionTotal;gaps=0;duplicates=0;leaks=0;unexpected_errors=0;whole_probe_each_index=$true}
}
