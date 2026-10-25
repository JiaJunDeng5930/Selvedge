From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Numbers.
From Selvedge.Interaction.Interactive Require Import Bounds.
Import ListNotations.
Open Scope string_scope.
Inductive builtin:=Length|Count|Minimum|Maximum|Absolute|Round|Clamp|Sum|Filter|Sort|Take|Text|Format|Working|AwaitingHuman.
Inductive number_format:=DecimalFormat|PercentFormat|UsdFormat|CnyFormat.
Definition format_name value:=match value with
 |DecimalFormat=>"number"|PercentFormat=>"percent"|UsdFormat=>"currency:USD"|CnyFormat=>"currency:CNY"end.
Definition formats:=[DecimalFormat;PercentFormat;UsdFormat;CnyFormat].
Definition decode_format text:=find(fun value=>String.eqb text(format_name value))formats.
Inductive sort_order:=Ascending|Descending.
Definition sort_name value:=match value with Ascending=>"asc"|Descending=>"desc"end.
Definition sort_orders:=[Ascending;Descending].
Definition decode_sort text:=find(fun value=>String.eqb text(sort_name value))sort_orders.
Definition name value:=match value with
 |Length=>"len"|Count=>"count"|Minimum=>"min"|Maximum=>"max"|Absolute=>"abs"|Round=>"round"|Clamp=>"clamp"
 |Sum=>"sum"|Filter=>"filter"|Sort=>"sort"|Take=>"take"|Text=>"text"|Format=>"format"|Working=>"working"|AwaitingHuman=>"awaitingHuman"end.
Definition arguments value:=match value with
 |Length=>["string-or-list"]|Count=>["list"]|Minimum|Maximum=>["number";"number"]|Absolute=>["number"]
 |Round=>["number";"integer precision 0.."++Numbers.show_nat Bounds.fraction_digits]
 |Clamp=>["number";"number lower";"number upper >= lower"]|Sum=>["records";"field-path"]
 |Filter=>["records";"field-path";"scalar"]
 |Sort=>["records";"field-path";"direction "++String.concat "|"(map sort_name sort_orders)]
 |Take=>["list";"integer count 0.."++Numbers.show_nat Bounds.collection_items]
 |Text=>["scalar (null becomes empty text)"]
 |Format=>["number";"style "++String.concat "|"(map format_name formats)]
 |Working|AwaitingHuman=>["task record with working/awaitingHuman Boolean facts, or null"]end.
Definition all:=[Length;Count;Minimum;Maximum;Absolute;Round;Clamp;Sum;Filter;Sort;Take;Text;Format;Working;AwaitingHuman].
Definition decode text:=find(fun value=>String.eqb text(name value))all.
Definition text:=String.concat "; "(map(fun value=>name value++"("++String.concat ","(arguments value)++")")all).
