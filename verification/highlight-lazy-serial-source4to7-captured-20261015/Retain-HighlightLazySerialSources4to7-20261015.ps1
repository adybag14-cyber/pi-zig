$ErrorActionPreference='Stop'
$taskPrivate='C:/Users/adyba/pi-zig-highlight-lazy-batch8-20261015'
$taskTemplate=Get-Content -LiteralPath (Join-Path $taskPrivate 'src/native_highlight_lazy_batch3_test.zig') -Raw
$taskBuild=Get-Content -LiteralPath (Join-Path $taskPrivate 'build.zig') -Raw
$taskNewBuild=''
foreach($taskSpec in @(@{b=4;c=102;head='aff26143e45fcdc79d10c541a2d209aeab67087f'},@{b=5;c=112;head='303d078ea69482957fff831cbec53709b3cac3b2'},@{b=6;c=102;head='7c1a5116bab00c6e90e11efac9de6159fd80b157'},@{b=7;c=106;head='20bc816810b633a4b3d393aa61ca1c170fada537'})) {
 $taskName="highlight-lazy-batch$($taskSpec.b)-source$($taskSpec.c)-first-20261015"
 $taskOwner=Get-Content -LiteralPath (Join-Path $PSScriptRoot "$taskName.json") -Raw|ConvertFrom-Json
 $taskPost=Get-Content -LiteralPath (Join-Path $PSScriptRoot "$taskName-posthash.json") -Raw|ConvertFrom-Json
 if($taskOwner.status -cne 'passed' -or @($taskPost.manifests|Where-Object drift -ne 0).Count -or $taskPost.control_drift -ne 0 -or $taskPost.source_path_drift -ne 0){throw 'Actual terminal/post0 required'}
 $taskResult=Get-Content -LiteralPath (Join-Path $PSScriptRoot "$taskName-output.json") -Raw|ConvertFrom-Json
 if($taskResult.cases -ne $taskSpec.c -or @($taskResult.rows).Count -ne $taskSpec.c){throw 'Exact genuine captured rows required'}
 $taskProof=Join-Path $taskPrivate "verification/highlight-lazy-batch$($taskSpec.b)-source-captured-20261015"
 New-Item -ItemType Directory -Path $taskProof -ErrorAction Stop|Out-Null
 $taskExpected=Join-Path $taskPrivate "src/extensions/fixtures/sdk-highlight-lazy-batch$($taskSpec.b)-10_7_3.json"
 if(Test-Path -LiteralPath $taskExpected){throw 'Fresh expected target required'}
 Copy-Item -LiteralPath (Join-Path $PSScriptRoot "$taskName-output.json") -Destination $taskExpected
 foreach($taskFile in @("Run-HighlightLazyBatch$($taskSpec.b)Source-20261015.ps1","capture-highlight-lazy-batch$($taskSpec.b)-20261015.mjs","$taskName.json","$taskName-posthash.json","$taskName-controls-before.json","$taskName-admission.json")){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $taskFile) -Destination $taskProof}
 @{candidate_head=$taskSpec.head;source_rows=$taskSpec.c;expected_sha256=(Get-FileHash -LiteralPath $taskExpected).Hash;source_capture='passed';native_compile='unrun';native_runtime='unrun';full_pi=$false;public_activation=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskProof 'qualification.json') -Encoding utf8NoBOM
 $taskDriver=Get-Content -LiteralPath (Join-Path $PSScriptRoot "capture-highlight-lazy-batch$($taskSpec.b)-20261015.mjs") -Raw
 $taskNames=[regex]::Match($taskDriver,'(?m)^const names=(.*?);$').Groups[1].Value.Replace("'",'"')|ConvertFrom-Json
 $taskBaseline=[regex]::Match($taskDriver,'(?m)^const baseline=(.*?);$').Groups[1].Value.Replace("'",'"')|ConvertFrom-Json
 # createEager implements the same first21 actual original baseline factories.
 $taskBaseline=@($taskBaseline|Select-Object -Skip 21)
 $taskNative=$taskTemplate.Replace('batch3',"batch$($taskSpec.b)").Replace('Batch3',"Batch$($taskSpec.b)").Replace('Source102',"Source$($taskSpec.c)").Replace('original102',"original$($taskSpec.c)")
 $taskBaseImports=($taskBaseline|ForEach-Object{'            @import("extensions/native_highlight_grammar_'+$_.Replace('-','_')+'.zig"),'}) -join "`n"
 $taskBaseNames=($taskBaseline|ForEach-Object{'"'+$_+'"'}) -join ', '
 $taskBaseBlock='        inline for (.{'+"`n"+$taskBaseImports+"`n"+'        }, .{ '+$taskBaseNames+' }) |grammar, name| {'
 $taskNative=[regex]::Replace($taskNative,'(?s)        inline for \(.\{.*?\}, .\{.*?\}\) \|grammar, name\| \{',[Text.RegularExpressions.MatchEvaluator]{param($m)$taskBaseBlock})
 $taskFactoryImports=($taskNames|ForEach-Object{'            .{ "'+$_+'", @import("extensions/native_highlight_grammar_'+$_.Replace('-','_')+'.zig") },'}) -join "`n"
 $taskFactoryBlock='        inline for (.{'+"`n"+$taskFactoryImports+"`n"+'        }) |entry|'
 $taskNative=[regex]::Replace($taskNative,'(?s)(?<=const factories = try s.object\(\);\r?\n)        inline for \(.\{.*?\}\) \|entry\|',[Text.RegularExpressions.MatchEvaluator]{param($m)$taskFactoryBlock})
 [IO.File]::WriteAllText((Join-Path $taskPrivate "src/native_highlight_lazy_batch$($taskSpec.b)_test.zig"),$taskNative,[Text.UTF8Encoding]::new($false))
 $taskN="highlight_lazy_batch$($taskSpec.b)_tests"
 $taskNewBuild+='    const '+$taskN+' = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_highlight_lazy_batch'+$taskSpec.b+'_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native actual lazy batch'+$taskSpec.b+' grammar bodies"}, .use_llvm = use_llvm });'+"`n"
 $taskNewBuild+='    linkQuickJs(b, '+$taskN+'.root_module, quickjs, sqlite_lib_dir);'+"`n"
 $taskNewBuild+='    '+$taskN+'.root_module.addImport("catalog_tool", catalog_tool);'+"`n"
 $taskNewBuild+='    b.step("build-native-highlight-lazy-batch'+$taskSpec.b+'", "Compile actual lazy batch'+$taskSpec.b+' against genuine Source'+$taskSpec.c+'").dependOn(&'+$taskN+'.step);'+"`n"
 $taskNewBuild+='    b.step("test-native-highlight-lazy-batch'+$taskSpec.b+'", "Replay genuine Source'+$taskSpec.c+' factory graphs live helpers and scanner observations").dependOn(&b.addRunArtifact('+$taskN+').step);'+"`n"
}
$taskAnchor='    const highlight_lazy_batch2_tests ='
if(!$taskBuild.Contains($taskAnchor)){throw 'Exact build anchor absent'}
$taskBuild=$taskBuild.Replace($taskAnchor,$taskNewBuild+$taskAnchor)
[IO.File]::WriteAllText((Join-Path $taskPrivate 'build.zig'),$taskBuild,[Text.UTF8Encoding]::new($false))
