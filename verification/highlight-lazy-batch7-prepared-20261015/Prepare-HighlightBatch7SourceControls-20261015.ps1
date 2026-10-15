$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskPrivate='C:/Users/adyba/pi-zig-highlight-lazy-batch7-20261015'
$taskNames="['plaintext','clojure-repl','vbscript-html','julia-repl','erlang-repl','oxygene','angelscript','vbscript','delphi','mercury','haskell','zephir','matlab','moonscript','processing','haxe','hsp','objectivec','hy','erlang']"
$taskInput=Get-Content -LiteralPath (Join-Path $taskPrivate 'src/extensions/fixtures/sdk-highlight-lazy-batch6-10_7_3.input.txt') -Raw
$taskInput=$taskInput.Replace('batch6','batch7').Replace('Batch6','Batch7').Replace('102','106')
$taskInput=[regex]::Replace($taskInput,'(?m)^const names=.*?;$',('const names='+$taskNames+';'))
$taskSamples=@'
const samples={
 plaintext:['plain <>& "text"\n','function value() { return 42; }\n'],
 'clojure-repl':['user=> (+ 1 2)\n3\n','demo.core=> (println "hello")\nnil\n'],
 'vbscript-html':['<h1><%= title %></h1>\n','<% Dim value\nvalue = 42\nResponse.Write(value) %><p>done</p>\n'],
 'julia-repl':['julia> println("hello")\nhello\n','julia> function square(x)\n       x * x\n       end\nsquare (generic function with 1 method)\n'],
 'erlang-repl':['1> self().\n<0.1.0>\n','2> spawn(fun() -> ok end).\n% TODO: repl\n'],
 oxygene:['namespace Demo;\ninterface\nmethod Main;\nbegin\nend;\n','(* TODO: Pascal *)\nvar value: Integer := 42;\nvar text := \'hello\';\n'],
 angelscript:['void main() { string value = "hello"; }\n','class Item : Base { array<int>@ values; }\n// TODO: script\n'],
 vbscript:['Option Explicit\nDim value\nvalue = MsgBox("hello")\n',"' TODO: VBScript\nIf True Then\n Response.Write \"hello\"\nEnd If\n"],
 delphi:["program Demo;\nbegin\n WriteLn('hello');\nend.\n",'{$IFDEF DEBUG}\n(* TODO: Pascal *)\nprocedure Run(value: Integer);\nbegin\n value := $ff;\nend;\n'],
 mercury:[':- module demo.\n:- interface.\n:- pred main is det.\n','% TODO: logic\nmain :- io.write_string("hello\\n", !IO).\nvalue(X) :- X = 42.\n'],
 haskell:['module Main where\nmain = putStrLn "Hello"\n','{-# LANGUAGE OverloadedStrings #-}\n-- TODO: Haskell\ndata Item = Empty | Value Int deriving Show\nsquare x = x * x\n'],
 zephir:['namespace Demo;\nclass Item { public function value() { return 42; } }\n','/** @param value TODO */\nlet value = "hello";\necho value;\n'],
 matlab:['function y = square(x)\ny = x.^2;\nend\n',"% TODO: matrix\nvalue = [1,2;3,4]';\ndisp(\"hello\");\n"],
 moonscript:['square = (x) -> x * x\nprint square 42\n','-- TODO: MoonScript\nclass Item extends Base\n  value: "hello #{name}"\n'],
 processing:['void setup() { size(640, 480); }\nvoid draw() { ellipse(mouseX, mouseY, 40, 40); }\n','// TODO: drawing\nPVector value = new PVector(1, 2);\nprintln(PI);\n'],
 haxe:['package demo;\nclass Main { static function main() { trace("hello"); } }\n',"@:keep\nclass Item { var value:Int = 42; var text = 'hello ${name}'; }\n"],
 hsp:['#include "hsp3.as"\nmes "hello"\nstop\n','; TODO: HSP\n*loop\nrepeat 3\n mes cnt\nloop\n'],
 objectivec:['@interface Item : NSObject\n@property(nonatomic, copy) NSString *name;\n@end\n','#import <Foundation/Foundation.h>\n@implementation Item\n- (void)run { NSLog(@"hello"); }\n@end\n'],
 hy:['(defn square [x] (* x x))\n(print (square 42))\n','; TODO: Hy\n(setv value {:name "hello" :ready True})\n'],
 erlang:['-module(demo).\n-export([square/1]).\nsquare(X) -> X * X.\n','% TODO: Erlang\nrun() -> receive {message, Value} -> io:format("~p", [Value]) end.\n']
};
'@
$taskInput=[regex]::Replace($taskInput,'(?s)const samples=\{.*?\n\};',[Text.RegularExpressions.MatchEvaluator]{param($m) $taskSamples})
$taskAlias=@'
record('actual batch7 canonical registration and aliases',()=>({registry:highlightCoreAPI.listLanguages(),aliases:[['text','plaintext'],['txt','plaintext'],['asc','angelscript'],['vbs','vbscript'],['pas','delphi'],['moo','mercury'],['hs','haskell'],['zep','zephir'],['moon','moonscript'],['hx','haxe'],['objc','objectivec'],['hylang','hy'],['erl','erlang']].map(([alias,name])=>({alias,name,same:highlightCoreAPI.getLanguage(alias)===highlightCoreAPI.getLanguage(name)}))}));
record('Julia REPL actual contained alias placement',()=>{const g=highlightLazyFactories['julia-repl'](highlightCoreAPI);return{rootAliases:g.aliases,promptAliases:g.contains[0].aliases,registeredAlias:!!highlightCoreAPI.getLanguage('jldoctest')}});
record('Mercury actual live array slice and push calls',()=>{const trace=[],slice=Array.prototype.slice,push=Array.prototype.push;Array.prototype.slice=function(...args){Reflect.apply(push,trace,[['slice',args.length]]);return Reflect.apply(slice,this,args)};Array.prototype.push=function(...args){Reflect.apply(push,trace,[['push',args.length]]);return Reflect.apply(push,this,args)};let grammar;try{grammar=highlightLazyFactories.mercury(highlightCoreAPI)}finally{Array.prototype.slice=slice;Array.prototype.push=push}return{trace,graph:graph(grammar)}});
record('VBScript actual builtin function spread uses live array iterator',()=>{const trace=[],original=Array.prototype[Symbol.iterator];Array.prototype[Symbol.iterator]=function(){trace.push(this.length);return Reflect.apply(original,this,[])};let grammar;try{grammar=highlightLazyFactories.vbscript(highlightCoreAPI)}finally{Array.prototype[Symbol.iterator]=original}return{trace,graph:graph(grammar)}});
record('Erlang actual directive weight arrow metadata and string coercion',()=>{const trace=[],map=Array.prototype.map;let grammar;Array.prototype.map=function(callback,...rest){trace.push({length:this.length,name:callback.name,arity:callback.length,prototype:Object.hasOwn(callback,'prototype')});return Reflect.apply(map,this,[callback,...rest])};try{grammar=highlightLazyFactories.erlang(highlightCoreAPI)}finally{Array.prototype.map=map}return{trace,keywords:grammar.contains[2].keywords}});
'@
$taskInput=[regex]::Replace($taskInput,'(?m)^record\(''actual batch7 canonical registration and aliases''.*$', [Text.RegularExpressions.MatchEvaluator]{param($m) $taskAlias})
$taskTarget=Join-Path $taskPrivate 'src/extensions/fixtures/sdk-highlight-lazy-batch7-10_7_3.input.txt'
if(Test-Path -LiteralPath $taskTarget){throw 'Fresh batch7 fixture required'}
[IO.File]::WriteAllText($taskTarget,$taskInput,[Text.UTF8Encoding]::new($false))
$taskDriver=Get-Content -LiteralPath (Join-Path $taskEvidence 'capture-highlight-lazy-batch6-20261015.mjs') -Raw
$taskPrevious=[regex]::Match($taskDriver,'(?m)^const names=(.*?);$').Groups[1].Value
$taskBaseline=[regex]::Match($taskDriver,'(?m)^const baseline=(.*?);$').Groups[1].Value
$taskDriver=$taskDriver.Replace('batch6','batch7').Replace('Batch6','Batch7').Replace('102','106')
$taskDriver=[regex]::Replace($taskDriver,'(?m)^const baseline=.*?;$',('const baseline='+$taskBaseline.TrimEnd(']')+','+$taskPrevious.TrimStart('[')+';'))
$taskDriver=[regex]::Replace($taskDriver,'(?m)^const names=.*?;$',('const names='+$taskNames+';'))
[IO.File]::WriteAllText((Join-Path $taskEvidence 'capture-highlight-lazy-batch7-20261015.mjs'),$taskDriver,[Text.UTF8Encoding]::new($false))
$taskOwner=(Get-Content -LiteralPath (Join-Path $taskEvidence 'Run-HighlightLazyBatch6Source-20261015.ps1') -Raw).Replace('batch6','batch7').Replace('Batch6','Batch7').Replace('102','106')
[IO.File]::WriteAllText((Join-Path $taskEvidence 'Run-HighlightLazyBatch7Source-20261015.ps1'),$taskOwner,[Text.UTF8Encoding]::new($false))
Write-Output 'PREPARED_GENUINE_BATCH7_SOURCE106_CONTROLS_ONLY'
