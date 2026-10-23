From Stdlib Require Import String List NArith.
From Selvedge.Interaction Require Import Identity.
From Selvedge.Interaction.Experience Require Model.
From Selvedge.Interaction.Presentation Require Import Surface Construction.
From Selvedge.Interaction.Presentation Require Import Model.
From Selvedge.Interaction.Presentation Require Roles Information.
Import ListNotations.
Open Scope string_scope.
Module Experience := Selvedge.Interaction.Experience.Model.
Definition commit_role {e}(unit:Experience.action_unit e)(feedback:option string) :=
 if Experience.action_pending unit then Roles.PrimaryButton else
 match feedback with Some _=>Roles.DestructiveButton|None=>Roles.PrimaryButton end.

Definition property_information {A e} parent (property : Experience.property e) : list (node A) :=
  let principal := information parent "value" Information.FieldValue (Experience.principal_information property) in
  let caption := information parent "label" Information.FieldLabel (Experience.property_label property) in
  caption :: principal :: match Experience.secondary_information property with
  | Some explanation => [information parent "description" Information.Description explanation]
  | None => [] end.

Definition property_control {A e} parent (property : Experience.property e) (action : control A) :=
  let identity := part parent (control_identity action) in
  Node identity (control_identity action) (Experience.property_label property) Roles.Button
    (SettingEntry e property action) (property_information identity property).

Definition supporting_control {A e} parent (support:Experience.support e)
    (property:Experience.property e) (action:control A) :=
 let identity:=part parent(control_identity action)in
 Node identity(control_identity action)(Experience.property_label property)Roles.Button
  (SupportingControl e support property action)(property_information identity property).

Definition action_feedback {A e} parent (unit:Experience.action_unit e)
    (feedback:option string):list(node A):=match feedback with
|Some message=>[Node(part parent "feedback")"submission-feedback" "Submission failed" Roles.Alert
  (ActionFeedback e(Experience.action_identity_of unit)message)[]]
|None=>[]end.

(** The supporting tools and canonical commit remain distinct children.  The
    owner index ties the field, action and assessment to the same editor. *)
Definition composer {A e} parent (unit : Experience.action_unit e)
    (subject : Experience.subject e) (editing : edit_control A)
    (body_controls tools : list (node A)) (assessment : Experience.assessment e)
    (submit : control A) (feedback : option string) : node A :=
  Node parent "composer" "Message" Roles.Composer (ActionUnit e unit)
    ([Node (part parent "message") "message" (match e with NewTask _ => "Task" | _ => "Message" end) Roles.Field (Edit e subject editing) []] ++ body_controls ++
     [Node (part parent "actions") "composer/actions" "Actions" Roles.ComposerActions Region
        [Node (part parent "tools") "composer/tools" "Supporting controls" Roles.Toolbar Region tools;
         Node (part parent "submit") "composer/submit" (control_label submit) (commit_role unit feedback)
           (ActionCommit e assessment submit) []]] ++
     action_feedback parent unit feedback)%list.
