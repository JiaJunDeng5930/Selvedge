From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Utf8 Schema.
From Selvedge.Foundation Require ArgumentDeclaration FiniteChoice.
From Selvedge.Kernel Require Import Numbers Codec.
From Selvedge.Features Require Domain BoardClock.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Definition limited (text:string) (maximum:N) := Utf8.well_formed text && Utf8.no_nul text && N.leb (N.of_nat (String.length text)) maximum.
Module D := ArgumentDeclaration.
Module F := Selvedge.Features.Domain.
Definition stage_declaration := FiniteChoice.declaration F.stage_choices.
Definition priority_declaration := FiniteChoice.declaration F.priority_choices.
Definition stage_of_values := FiniteChoice.value F.stage_choices.
Definition priority_of_values := FiniteChoice.value F.priority_choices.
Definition local_owners := FiniteChoice.declare F.owner_name F.Unassigned [F.Self].
Definition owner_declaration := D.Union [FiniteChoice.declaration local_owners;
 D.PrefixedText "profile/" (D.bounded_format 1016);
 D.PrefixedText "agent/" (D.NaturalSpelling 0 (Some D.maximum_natural))].
Definition owner_of_values (value : D.denote owner_declaration) : F.owner := match value with
 | inl value => FiniteChoice.value local_owners value
 | inr (inl value) => F.ProfileOwner (proj1_sig value)
 | inr (inr (inl value)) => F.AgentOwner (proj1_sig value)
 | inr (inr (inr impossible)) => match impossible with end end.
Definition project_declaration := D.Union [D.Const (JString "");D.NaturalText 0 (Some D.maximum_natural)].
Definition project_of_values (value : D.denote project_declaration) : option N := match value with
 | inl _ => None | inr (inl value) => Some (proj1_sig value)
 | inr (inr impossible) => match impossible with end end.
Definition clock_declaration := BoardClock.declaration.
Definition clock := BoardClock.t.
Definition clock_value := BoardClock.value.
Definition zero_clock := BoardClock.zero.
Definition observed_clock := BoardClock.observed.

(** Raw views are admitted once at snapshot and form boundaries. Command
    handlers consume the values above without parsing their string projection. *)
Definition stage name := option_map stage_of_values (D.decode stage_declaration (JString name)).
Definition priority name := option_map priority_of_values (D.decode priority_declaration (JString name)).
Definition owner name := option_map owner_of_values (D.decode owner_declaration (JString name)).
Definition optional_project name := option_map project_of_values (D.decode project_declaration (JString name)).
Definition text_within maximum := D.Text (D.TextConstraints 0 D.maximum_natural maximum true false false None).
Definition agent_name_declaration := D.bounded_text 160.
Definition agent_profile_declaration := D.bounded_text 1024.
Definition agent_reasoning_declaration := D.bounded_text 64.
Definition agent_instructions_declaration := text_within 100000.
Definition agent_capacity_declaration := D.Natural 1 64.
Definition attachment_fields (observed : bool) := [
 ("id",true,ContentDeclarations.identifier_declaration);
 ("name",observed,D.bounded_text 256);
 ("mime",false,text_within 128);
 ("path",observed,D.PrefixedText "/" (D.ConstrainedText (D.TextConstraints 0 D.maximum_natural 4095 true false false None)));
 ("bytes",false,D.NaturalText 0 (Some ContentDeclarations.image_byte_limit))].
Definition attachment_declaration observed := D.Object (attachment_fields observed).
Definition attachments_declaration observed := D.BoundedArray 0 4 (attachment_declaration observed).
Definition attachment_of_values (value : D.denote (attachment_declaration true)) :=
 let '(id,(name,(mime,(path,(bytes,_))))) := proj1_sig value in
 F.Attachment (proj1_sig id) (proj1_sig name)
   (match mime with Some value => proj1_sig value | None => "" end)
   (String.append "/" (proj1_sig path))
   (match bytes with Some value => proj1_sig value | None => 0%N end).
Definition attachments_of_values (values : D.denote (attachments_declaration true)) :=
 map attachment_of_values (proj1_sig values).
