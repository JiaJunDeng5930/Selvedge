From Stdlib Require Import String Bool Ascii.
From Selvedge.Foundation Require Import Json.

Definition markdown_info_padding (character : ascii) : bool :=
 Ascii.eqb character " "%char || Ascii.eqb character (ascii_of_nat 9).

Fixpoint trim_markdown_info_start (info : string) : string :=
 match info with
 | EmptyString => EmptyString
 | String character rest =>
   if markdown_info_padding character then trim_markdown_info_start rest else info
 end.

Fixpoint trim_markdown_info_end (info : string) : string :=
 match info with
 | EmptyString => EmptyString
 | String character rest =>
   let trimmed := trim_markdown_info_end rest in
   match trimmed with
   | EmptyString => if markdown_info_padding character then EmptyString else String character trimmed
   | _ => String character trimmed
   end
 end.

Definition trim_markdown_info_padding (info : string) : string :=
 trim_markdown_info_start (trim_markdown_info_end info).

Definition interactive_markdown_fence_observation (observation : json) :=
 match string_field "raw_info" observation,
       string_field "fence_kind" observation,
       bool_field "info_complete" observation with
 | Some info, Some "fenced", Some true =>
   String.eqb (trim_markdown_info_padding info) "selvedge-ui"
 | _,_,_ => false
 end.
