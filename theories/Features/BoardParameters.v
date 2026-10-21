From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Utf8 Schema.
From Selvedge.Kernel Require Import Numbers Codec.
From Selvedge.Features Require Domain.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Definition limited (text:string) (maximum:N) := Utf8.well_formed text && Utf8.no_nul text && N.leb (N.of_nat (String.length text)) maximum.
Definition text_id (text:string) := match natural (JNumber text) with Some id=>if String.eqb text (Selvedge.Features.Domain.decimal_text id) then Some id else None | None=>None end.
Definition stage (name:string) := find (fun stage=>String.eqb name (Selvedge.Features.Domain.stage_name stage)) Selvedge.Features.Domain.stages.
Definition priority (name:string) := find (fun priority=>String.eqb name (Selvedge.Features.Domain.priority_name priority)) Selvedge.Features.Domain.priorities.
Definition owner (name:string) :option Selvedge.Features.Domain.owner :=
 if String.eqb name "none" then Some Selvedge.Features.Domain.Unassigned else if String.eqb name "self" then Some Selvedge.Features.Domain.Self else
 if String.prefix "profile/" name then let key:=String.substring 8 (String.length name) name in
 if nonempty key && limited name 1024 then Some (Selvedge.Features.Domain.ProfileOwner key) else None
 else if String.prefix "agent/" name then option_map Selvedge.Features.Domain.AgentOwner (text_id (String.substring 6 (String.length name) name)) else None.
Definition optional_project (text:string) :option (option N) := if String.eqb text "" then Some None else option_map (@Some N) (text_id text).
Definition attachment (source:json) :option Selvedge.Features.Domain.attachment :=
 match Schema.decode [Field "id" KText;Field "name" KText;Field "mime" KText;Field "path" KText;Field "bytes" KText] source,
 string_field "id" source,string_field "name" source,string_field "mime" source,string_field "path" source,string_field "bytes" source with
 | Some _,Some id,Some name,Some mime,Some path,Some bytes=>match text_id bytes with
 | Some count=>if Nat.eqb (String.length id) 64 && nonempty name && limited name 256 && limited mime 128 && String.prefix "/" path && limited path 4096 && N.leb count 10485760 then Some (Selvedge.Features.Domain.Attachment id name mime path count) else None
 | None=>None end | _,_,_,_,_,_=>None end.
