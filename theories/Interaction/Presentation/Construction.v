From Stdlib Require Import String List NArith.
From Selvedge.Interaction.Presentation Require Import Surface Model.
From Selvedge.Interaction.Presentation Require Roles Information Composition.
Import ListNotations.
Open Scope string_scope.

Definition part := Selvedge.Interaction.Identity.key_part.
Definition information {A} parent name role label : node A :=
  Node (part parent name) name label Roles.Content (InformationText role) [].
Definition region {A} parent name label role (content : list (node A)) :=
  Node (part parent name) name label role Region content.
Definition dialog_header {A} parent (content : list (node A)) :=
  region parent "header" "" Roles.DialogHeader content.
Definition dialog_body {A} parent (content : list (node A)) :=
  region parent "body" "" Roles.DialogBody content.
Definition dialog_actions {A} parent (content : list (node A)) :=
  region parent "actions" "Actions" Roles.DialogActions content.
Definition page_region {A} parent region position (children : list (node A)) :=
  let name:=Composition.region_name region in
  Node (part parent (part "region" name)) name "" Roles.Section (PageRegion region position) children.
Definition declared {A} parent role (action : control A) :=
  Node (part parent (control_identity action)) (control_identity action)
    (control_label action) role (Activate action) [].
Definition secondary {A} identity label (action : A) := Control identity label Secondary action Available.
Definition primary {A} identity label (action : A) := Control identity label Primary action Available.
Definition destructive {A} identity label (action : A) := Control identity label Destructive action Available.
Definition read_only {A} parent name label value : node A :=
  let key := part parent name in
  Node key name label Roles.Content Region
    ((if String.eqb label "" then [] else [information key "label" Information.FieldLabel label]) ++
     [Node (part key "value") "value" "" Roles.Content (Fact value) []])%list.
Definition title {A} parent label := information (A:=A) parent "heading" Information.SurfaceTitle label.
Definition group_title {A} parent label := information (A:=A) parent "heading" Information.GroupTitle label.
Definition availability_reason (value : availability) := match value with
| Unavailable reason | Busy reason => Some reason | _ => None end.
