From Stdlib Require Import String List Bool.
Import ListNotations.
Open Scope string_scope.
Inductive builtin:=Length|Count|Minimum|Maximum|Absolute|Round|Clamp|Sum|Filter|Sort|Take|Text|Format|Working|AwaitingHuman.
Definition name value:=match value with
 |Length=>"len"|Count=>"count"|Minimum=>"min"|Maximum=>"max"|Absolute=>"abs"|Round=>"round"|Clamp=>"clamp"
 |Sum=>"sum"|Filter=>"filter"|Sort=>"sort"|Take=>"take"|Text=>"text"|Format=>"format"|Working=>"working"|AwaitingHuman=>"awaitingHuman"end.
Definition arguments value:=match value with
 |Length=>["string-or-list"]|Count=>["list"]|Minimum|Maximum=>["number";"number"]|Absolute=>["number"]
 |Round=>["number";"precision"]|Clamp=>["number";"lower";"upper"]|Sum=>["records";"field-path"]
 |Filter=>["records";"field-path";"scalar"]|Sort=>["records";"field-path";"asc-or-desc"]
 |Take=>["list";"count"]|Text=>["value"]|Format=>["number";"style"]|Working|AwaitingHuman=>["task"]end.
Definition all:=[Length;Count;Minimum;Maximum;Absolute;Round;Clamp;Sum;Filter;Sort;Take;Text;Format;Working;AwaitingHuman].
Definition decode text:=find(fun value=>String.eqb text(name value))all.
Definition text:=String.concat "; "(map(fun value=>name value++"("++String.concat ","(arguments value)++")")all).
