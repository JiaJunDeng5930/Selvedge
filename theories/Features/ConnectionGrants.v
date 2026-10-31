From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Schema.
From Selvedge.Programming Require ArgumentDeclaration.
From Selvedge.Foundation Require KeyedCollection OptionList.
From Selvedge.Kernel Require Import Numbers Domain Codec ChatgptArguments.
Import ListNotations.
Open Scope string_scope.
Module D := ArgumentDeclaration.

Definition identity_declaration := ChatgptArguments.identity_declaration.
Definition maximum_connections : N := 32.
Definition maximum_projects : N := 32.
Definition project_ids_declaration := D.BoundedArray 0 maximum_projects identity_declaration.
Definition grant_declaration := D.Object [
 ("connection_id",true,identity_declaration);
 ("project_ids",true,project_ids_declaration);
 ("sandbox",true,Codec.sandbox_declaration)].
Definition declaration := D.BoundedArray 0 maximum_connections grant_declaration.

Module ProjectEntries.
 Definition t := D.denote identity_declaration.
 Definition key := N.
 Definition key_of (value : t) := proj1_sig value.
 Definition key_eq_dec := N.eq_dec.
End ProjectEntries.
Module Projects := KeyedCollection.Make ProjectEntries.
Definition projects_of_values (values : D.denote project_ids_declaration) :=
 Projects.admit (proj1_sig values).
Definition project_ids (values : Projects.t) := map ProjectEntries.key_of (Projects.values values).
Definition projects_json values := JArray (map number (project_ids values)).

(** The same grant model serves local configuration and the command boundary.
    A project identity and a connection identity each name one retained entry. *)
Record grant := Grant {
 grant_identity : D.denote identity_declaration;
 grant_projects : Projects.t;
 grant_sandbox : sandbox
}.
Definition identity value := proj1_sig (grant_identity value).
Definition projects value := project_ids (grant_projects value).
Definition admits_project id value := existsb (N.eqb id) (projects value).
Module GrantEntries.
 Definition t := grant.
 Definition key := N.
 Definition key_of := identity.
 Definition key_eq_dec := N.eq_dec.
End GrantEntries.
Module Grants := KeyedCollection.Make GrantEntries.
Definition admit_grant (values : D.denote grant_declaration) : option grant :=
 let '(id,(projects,(sandbox,_))) := proj1_sig values in
 option_map (fun projects => Grant id projects (Codec.sandbox_of_values sandbox))
   (projects_of_values projects).
Definition admit_grants (values : D.denote declaration) : option Grants.t :=
 match OptionList.traverse admit_grant (proj1_sig values) with
 | Some entries => Grants.admit entries | None => None end.
