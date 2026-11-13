From Stdlib Require Import List Bool.
From Selvedge.Browser.Presentation Require Import Composition.
Import ListNotations.

Theorem conversation_keeps_chronological_reading composer approvals :
  body_regions (page_structure (Conversation composer approvals)) = [TimelineContent] /\
  heading_regions (page_structure (Conversation composer approvals)) =
    [ConversationHeader].
Proof. split; reflexivity. Qed.

Theorem conversation_places_decisions_before_bottom_input :
  dock_regions (page_structure (Conversation true true)) =
    [ApprovalDecisions; ComposerInput].
Proof. reflexivity. Qed.

Theorem creation_keeps_context_with_its_input :
  body_regions (page_structure (Creation true)) = [CreationIntroduction; ComposerInput] /\
  dock_regions (page_structure (Creation true)) = [].
Proof. split; reflexivity. Qed.

Theorem project_preserves_workspace_guidance_and_tasks :
  body_regions (page_structure ProjectOverview) =
    [DefaultWorkspace; ProjectGuidance; ProjectTasks].
Proof. reflexivity. Qed.

Theorem page_regions_are_unique page : NoDup (ordered_regions page).
Proof.
  destruct page; try destruct composer; try destruct approvals; simpl;
    repeat constructor; simpl; intuition discriminate.
Qed.
