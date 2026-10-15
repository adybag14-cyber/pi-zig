#requires -Version 7.0
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$node='C:/Program Files/nodejs/node.exe'
$zig='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0/zig.exe'
function Run([string]$exe,[string[]]$arguments){& $exe @arguments;if($LASTEXITCODE -ne 0){throw "Static check failed: $exe $arguments exit=$LASTEXITCODE"}}
if((Get-FileHash -LiteralPath $zig).Hash -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Pinned Zig drift'}
if((Get-FileHash -LiteralPath $node).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Authoring Node drift'}
$parser='C:/Users/adyba/AppData/Roaming/npm/node_modules/wrangler/node_modules/acorn/dist/acorn.mjs'
if((Get-FileHash -LiteralPath $parser).Hash -cne '402F6759C744EA2CA501C1DC4DED8B1C54C9066CC7A741837057DCB68BC64C93'){throw 'Authoring parser drift'}
Run $node @('--check',(Join-Path $PSScriptRoot 'capture-genuine-source.mjs'))
Run $node @((Join-Path $PSScriptRoot 'lower-authority.mjs'))
$files=@('src/extensions/native_typebox_operators_production.zig','src/extensions/native_typebox_operators_runtime.zig','src/native_typebox_operators_production_test.zig')
foreach($file in $files){Run $zig @('fmt',(Join-Path $root $file));Run $zig @('ast-check',(Join-Path $root $file))}
$hashes=@(foreach($file in $files){[ordered]@{path=$file;sha256=(Get-FileHash -LiteralPath (Join-Path $root $file)).Hash}})
$closure=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'reachable-closure.json') -Raw|ConvertFrom-Json
[ordered]@{status='source_only_static_passed';base='3b479da0a86a20c5fd1baf15969777733ded95c9';typebox_version='1.3.27';package_sha256=$closure.packageSha256;modules=$closure.modules.Count;declarations=$closure.declarations;exports=$closure.publicRoots.Count;generated_native_functions=(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'lowering-map.json') -Raw|ConvertFrom-Json).functions.Count;native_files=$hashes;source_executed=$false;native_compiled=$false;native_executed=$false;full_HOST_GPA=$false;C_malloc_exhaustive=$false;production_qualified=$false;authoring='static AST to direct Zig callbacks; no runtime AST/Source evaluator'}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'static-validation.json') -Encoding utf8NoBOM
Get-Content -LiteralPath (Join-Path $PSScriptRoot 'static-validation.json') -Raw
