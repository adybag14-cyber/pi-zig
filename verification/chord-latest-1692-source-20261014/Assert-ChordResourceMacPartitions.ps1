function Assert-ChordResourceMacPartitions {
 param([Parameter(Mandatory)][string]$Log)
 $partitionMarkers=[regex]::Matches($Log,'CHORD_RESOURCE_MAC_GPA_PARTITION=(\{[^\r\n]*\})')
 if($partitionMarkers.Count -ne 2){throw 'Complete Resource MacDebug GPA requires exactly two partition receipts'}
 $partitionRows=@($partitionMarkers|ForEach-Object{$_.Groups[1].Value|ConvertFrom-Json}|Sort-Object partition)
 foreach($partitionRow in $partitionRows){
  foreach($partitionField in @('partition','start','end','baseline','completed','leaks','unexpected_errors')){
   $partitionValue=$partitionRow.$partitionField
   if($null -eq $partitionValue -or $partitionValue -isnot [ValueType] -or $partitionValue -is [bool] -or [decimal]$partitionValue -ne [math]::Truncate([decimal]$partitionValue) -or $partitionValue -lt 0){throw 'Invalid Resource MacDebug GPA partition field'}
  }
 }
 $partitionTotal=$partitionRows[0].baseline
 $partitionMiddle=[long][math]::Ceiling($partitionTotal/2.0)
 if($partitionTotal -ne 858 -or $partitionRows[1].baseline -ne $partitionTotal){throw 'Resource MacDebug GPA baseline disagreement'}
 if($partitionRows[0].partition -ne 0 -or $partitionRows[1].partition -ne 1 -or $partitionRows[0].start -ne 0 -or $partitionRows[0].end -ne $partitionMiddle -or $partitionRows[1].start -ne $partitionMiddle -or $partitionRows[1].end -ne $partitionTotal){throw 'Resource MacDebug GPA ranges contain gaps duplicates or changed boundaries'}
 foreach($partitionRow in $partitionRows){
  if($partitionRow.completed -ne ($partitionRow.end-$partitionRow.start) -or $partitionRow.leaks -ne 0 -or $partitionRow.unexpected_errors -ne 0){throw 'Incomplete or failed Resource MacDebug GPA partition'}
 }
 $partitionBaselines=[regex]::Matches($Log,'CHORD_RESOURCE_MAC_GPA_BASELINE_ALLOCATIONS=(\d+)')
 if($partitionBaselines.Count -ne 2 -or @($partitionBaselines|Where-Object{[long]$_.Groups[1].Value -ne $partitionTotal}).Count){throw 'Composed probe allocation baselines do not match completed partitions'}
 $indices=[regex]::Matches($Log,'CHORD_RESOURCE_MAC_GPA_INDEX=(\{[^\r\n]*\})')
 if($indices.Count -ne 858){throw 'Resource MacDebug attempted index inventory incomplete'}
 $indexRows=@($indices|ForEach-Object{$_.Groups[1].Value|ConvertFrom-Json}|Sort-Object index)
 for($index=0;$index -lt 858;$index++){
  $row=$indexRows[$index]
  foreach($field in @('partition','index','baseline')){if($null -eq $row.$field -or $row.$field -isnot [ValueType] -or $row.$field -is [bool] -or [decimal]$row.$field -ne [math]::Truncate([decimal]$row.$field)){throw 'Malformed Resource MacDebug attempted index'}}
  if($row.index -ne $index -or $row.baseline -ne 858 -or $row.partition -ne $(if($index -lt 429){0}else{1})){throw 'Resource MacDebug attempted indices contain gap duplicate or wrong partition'}
 }
 return [ordered]@{baseline=$partitionTotal;partitions=$partitionRows;start=0;end=$partitionTotal;completed=$partitionTotal;gaps=0;duplicates=0;leaks=0;unexpected_errors=0;whole_probe_each_index=$true}
}
