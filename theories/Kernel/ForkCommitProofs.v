From Selvedge.Kernel Require Import TaskChangesProofs.
From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import Domain Codec State Inputs CommandHandlers
 CommandExecution Tasks ForkCommit Delivery Notifications.
From Selvedge.Features Require Import Worktree.
Import ListNotations.
Open Scope string_scope.
Module G := Selvedge.Generated.Commands.

Definition settings_origin (request : G.fork_payload) :=
 match G.fork_settings_origin request with
 | Some source => if String.eqb (proj1_sig source) "environment"
   then Tasks.EnvironmentSettings else Tasks.ParentSettings
 | None => Tasks.ParentSettings
 end.
Definition message_sources (request : G.fork_payload) :=
 match G.fork_messages request with Some values => values | None => [] end.

Lemma the_fork_constructor_emits_no_unbound_effects : forall entry origin owner count messages raw before,
 decision_effects (Tasks.fork_with_caller entry origin owner count messages raw before) = [].
Proof.
 intros; rewrite TaskChangesProofs.fork_with_caller_expression; cbv beta zeta.
 destruct (find_task owner before) as [parent|]; [|reflexivity].
 destruct (_ && _) eqn:Eligible; [|reflexivity].
 destruct (Tasks.resolve_settings _ _ _ _) as [selected|]; [|reflexivity].
 destruct (Tasks.admit_fork_selection _ _ _) as [selection|]; [|reflexivity].
 destruct (match entry with Tasks.ManualFork => false | Tasks.AcceptedNativeFork _ _ =>
   negb (Workspace.may_delegate (Tasks.fork_selected parent before selection) (task_current_settings parent) && Tasks.no_resource_observation raw) end);
 reflexivity.
Qed.

Lemma the_manual_fork_handler_emits_no_unbound_effects : forall request before,
 decision_effects (CommandHandlers.execute (G.Cmd_fork request) None before) = [].
Proof.
 intros request before.
 unfold CommandHandlers.execute, G.dispatch; cbn [CommandHandlers.handlers G.handle_fork].
 unfold CommandExecution.handle_fork.
 destruct (traverse Images.parse_content _) as [messages|]; [|reflexivity].
 apply the_fork_constructor_emits_no_unbound_effects.
Qed.

Lemma the_manual_fork_proposal_emits_no_unbound_effects : forall request before,
 decision_effects (ForkCommit.propose request before) = [].
Proof.
 intros; unfold ForkCommit.propose, Worktree.execution_guard.
 destruct (Worktree.execution_allowed _ _); [apply the_manual_fork_handler_emits_no_unbound_effects|reflexivity].
Qed.

Lemma the_fork_transaction_emits_only_its_durable_continuation : forall request before,
 Forall (fun effect => effect = ContinueScheduling) (decision_effects (ForkCommit.candidate request before)).
Proof.
 intros request before; unfold ForkCommit.candidate.
 remember (ForkCommit.propose request before) as proposed eqn:Proposed.
 assert (Effects : decision_effects proposed = []) by
   (subst proposed; apply the_manual_fork_proposal_emits_no_unbound_effects).
 unfold ForkCommit.admit_workspace.
 destruct (skipn _ _) as [|child rest]; cbn;
 try destruct (_ && _); cbn;
 try destruct (bool_default _ _ _); cbn;
 rewrite ?Effects; repeat constructor.
Qed.

Lemma workspace_admission_keeps_the_constructor_or_the_before_world : forall before proposed,
 decision_world (ForkCommit.admit_workspace before proposed) = decision_world proposed \/
 decision_world (ForkCommit.admit_workspace before proposed) = before.
Proof.
 intros; unfold ForkCommit.admit_workspace.
 destruct (skipn _ _) as [|child rest]; [left; reflexivity|].
 destruct (_ && _); [left|right]; reflexivity.
Qed.

Lemma the_fork_transaction_keeps_the_admitted_world : forall request before,
 decision_world (ForkCommit.candidate request before) =
 decision_world (ForkCommit.admit_workspace before
   (ForkCommit.propose request before)).
Proof. intros; unfold ForkCommit.candidate; destruct (bool_default _ _ _); reflexivity. Qed.

Lemma delivered_fork_effects_are_only_continuations : forall request before,
 let delivered := snd (Delivery.deliver_with_status true (ForkCommit.candidate request before) before) in
 Forall (fun effect => effect = ContinueScheduling) (decision_effects delivered).
Proof.
 intros request before; cbn zeta; unfold Delivery.deliver_with_status.
 destruct (Delivery.fits true (ForkCommit.candidate request before)); cbn [snd];
 [apply the_fork_transaction_emits_only_its_durable_continuation|constructor].
Qed.

Lemma the_actual_manual_fork_handler_interprets_its_message_admission : forall request before,
 CommandHandlers.execute (G.Cmd_fork request) None before =
 match traverse Images.parse_content (message_sources request) with
 | Some messages => Tasks.fork_with_caller Tasks.ManualFork (settings_origin request)
   (G.fork_task_id request) (G.fork_child_count request) messages (G.fork_settings request) before
 | None => reject "invalid_message" "Child messages contain invalid content parts" before end.
Proof. reflexivity. Qed.

Lemma a_manual_fork_uses_the_actual_domain_constructor : forall request messages before,
 traverse Images.parse_content (message_sources request) = Some messages ->
 CommandHandlers.execute (G.Cmd_fork request) None before =
 Tasks.fork_with_caller Tasks.ManualFork (settings_origin request)
   (G.fork_task_id request) (G.fork_child_count request) messages (G.fork_settings request) before.
Proof.
 intros request messages before Parsed.
 rewrite the_actual_manual_fork_handler_interprets_its_message_admission, Parsed; reflexivity.
Qed.

Lemma a_constructed_fork_admits_its_workspace_once : forall request before after reply child rest,
 Worktree.execution_guard (G.fork_task_id request) before = None ->
 CommandHandlers.execute (G.Cmd_fork request) None before = accept reply after [] ->
 skipn (List.length (world_tasks before)) (world_tasks after) = child :: rest ->
 Worktree.workspace_available (settings_workspace (task_current_settings child)) before &&
 Worktree.binding_available (task_current_settings child) after = true ->
 ForkCommit.candidate request before = Decision after (success reply) [ContinueScheduling].
Proof.
 intros request before after reply child rest ParentAvailable Constructed Births Available.
 unfold ForkCommit.candidate, ForkCommit.propose, ForkCommit.admit_workspace.
 rewrite ParentAvailable, Constructed.
 cbn [accept decision_world decision_reply]; rewrite Births, Available; reflexivity.
Qed.

Lemma a_fork_with_an_admitted_output_budget_is_delivered : forall request before candidate,
 ForkCommit.candidate request before = candidate ->
 Delivery.fits true candidate = true ->
 ForkCommit.packet request before =
 (with_sequence (N.succ (world_sequence before)) (decision_world candidate),
  Notifications.envelope true true (Some (UserCommand (G.Cmd_fork request))) before candidate).
Proof.
 intros request before candidate Constructed Fits.
 unfold ForkCommit.packet; rewrite Constructed.
 unfold Delivery.deliver_with_status; rewrite Fits; reflexivity.
Qed.
