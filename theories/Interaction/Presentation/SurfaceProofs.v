From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Interaction.Presentation Require Import Model Surface Gesture.
From Selvedge.Interaction.Experience Require Model.
Open Scope string_scope.

Theorem unavailable_control_cannot_press {A} (value:control A) reason :
 control_availability value=Unavailable reason -> press_control value=None.
Proof. intros Disabled. unfold press_control. rewrite Disabled. reflexivity. Qed.

Theorem display_only_field_cannot_assign {A} (value:edit_control A) input :
 editing_entry value=Selvedge.Interaction.Submission.Fields.DisplayOnly -> edit_value value input=None.
Proof. intros DisplayOnly. unfold edit_value. destruct(available(editing_availability value));[rewrite DisplayOnly|];reflexivity. Qed.

Theorem unavailable_commit_cannot_dispatch {A e} assessment (value:control A) reason input :
 control_availability value=Unavailable reason ->
 resolve_meaning(ActionCommit e assessment value)Press input=None.
Proof. apply unavailable_control_cannot_press. Qed.
