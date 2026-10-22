From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain State Tasks LifecycleProofs.
From Selvedge.Features Require Import Domain State TaskGraph TaskGraphSemantics.
Import ListNotations.
Module F:=Selvedge.Features.Domain.
Module K:=Selvedge.Kernel.State.
Lemma failed_birth_is_terminal : forall nodes owner caller failure,
 fold_left (fun progress node=>TaskGraph.birth owner caller node progress) nodes (TaskGraph.BirthFailed failure) = TaskGraph.BirthFailed failure.
Proof. induction nodes;intros; simpl;auto. Qed.
(** A missing existing node after any declaration prefix cannot leave births
    or effects from that rejected installation behind. *)
Theorem missing_first_node_is_atomic : forall id owner name key target rest rules caller value
 (admitted:TaskGraph.admissible (TaskGraph.Declaration name (F.ExistingNode key target::rest) rules)),
 K.find_task target value = None ->
 decision_world (TaskGraph.install id owner (exist _ _ admitted) caller value) = value /\
 decision_effects (TaskGraph.install id owner (exist _ _ admitted) caller value) = [].
Proof.
 intros.
 assert (first : TaskGraph.birth owner caller (F.ExistingNode key target) (TaskGraph.Born value [] []) =
 TaskGraph.BirthFailed (K.failure "task_not_found"%string "A referenced graph task does not exist"%string)).
 { unfold TaskGraph.birth. rewrite H. reflexivity. }
 unfold TaskGraph.install. destruct (TaskGraph.work_valid owner value); [|split;reflexivity].
 cbn -[TaskGraph.birth]. rewrite first.
 rewrite failed_birth_is_terminal. split;reflexivity.
Qed.

Lemma registry_lookup_at_appended_index : forall (A : Type) (entries : list A) value,
 registry_at (N.of_nat (List.length entries)) (entries ++ [value]) = Some value.
Proof.
 intros A entries; induction entries as [|head rest IH]; intro value; [reflexivity|].
 change ((if N.eqb (N.of_nat (S (List.length rest))) 0 then Some head
   else registry_at (N.pred (N.of_nat (S (List.length rest)))) (rest ++ [value])) = Some value).
 assert (Positive : N.eqb (N.of_nat (S (List.length rest))) 0 = false)
   by (apply N.eqb_neq; lia).
 rewrite Positive.
 replace (N.pred (N.of_nat (S (List.length rest)))) with (N.of_nat (List.length rest)) by lia.
 apply IH.
Qed.

Lemma registry_append_preserves_other_lookup : forall (A : Type) (entries : list A) index value,
 index <> N.of_nat (List.length entries) ->
 registry_at index (entries ++ [value]) = registry_at index entries.
Proof.
 intros A entries; induction entries as [|head rest IH]; intros index value Different.
 - cbn. destruct (N.eqb index 0) eqn:Selected; [|reflexivity].
   apply N.eqb_eq in Selected. exfalso; apply Different; exact Selected.
 - cbn [List.app registry_at]. destruct (N.eqb index 0) eqn:Selected; [reflexivity|].
   apply IH. apply N.eqb_neq in Selected. intro Equal. apply Different.
   cbn [List.length]. rewrite Nat2N.inj_succ, <- Equal.
   symmetry; now apply N.succ_pred.
Qed.

Lemma registry_replacement_preserves_other_lookup : forall (A : Type) (entries : list A)
 updated observed replacement,
 updated <> observed ->
 registry_at observed (replace updated replacement entries) = registry_at observed entries.
Proof.
 intros A entries; induction entries as [|head rest IH]; intros updated observed replacement Different;
   [reflexivity|].
 cbn [replace registry_at].
 destruct (N.eqb updated 0) eqn:Write; destruct (N.eqb observed 0) eqn:Read;
   cbn [registry_at]; rewrite ?Read.
 - apply N.eqb_eq in Write, Read. exfalso; apply Different; congruence.
 - reflexivity.
 - reflexivity.
 - apply IH. apply N.eqb_neq in Write, Read. intro Equal. apply Different.
   now apply N.pred_inj.
Qed.

Lemma graph_lookup_has_registry_entry : forall id value graph,
 TaskGraph.lookup id value = Some graph ->
 registry_at id (TaskGraph.registry value) = Some (Some graph).
Proof.
 intros id value graph Found. unfold TaskGraph.lookup in Found.
 destruct (registry_at id (TaskGraph.registry value)) as [[present|]|] eqn:Entry;
   try discriminate. inversion Found; reflexivity.
Qed.

Theorem replacing_a_graph_preserves_its_identity : forall id value previous graph,
 TaskGraph.lookup id value = Some previous ->
 TaskGraph.lookup id (TaskGraph.store id graph value) = Some graph.
Proof.
 intros id value previous graph Found.
 apply graph_lookup_has_registry_entry in Found.
 unfold TaskGraph.lookup.
 change (match registry_at id
   (if N.eqb id (N.of_nat (List.length (TaskGraph.registry value)))
    then TaskGraph.registry value ++ [Some graph]
    else replace id (Some graph) (TaskGraph.registry value)) with
   | Some graph => graph | None => None end = Some graph).
 destruct (N.eqb id (N.of_nat (List.length (TaskGraph.registry value)))) eqn:Append.
 - apply N.eqb_eq in Append. rewrite Append, registry_lookup_at_appended_index. reflexivity.
 - rewrite (registry_replace_selected _ _ _ _ _ Found). reflexivity.
Qed.

Theorem appending_a_graph_establishes_its_identity : forall value graph,
 let id := N.of_nat (List.length (TaskGraph.registry value)) in
 TaskGraph.lookup id (TaskGraph.store id graph value) = Some graph.
Proof.
 intros value graph; cbv zeta. unfold TaskGraph.lookup.
 change (match registry_at (N.of_nat (List.length (TaskGraph.registry value)))
   (if N.eqb (N.of_nat (List.length (TaskGraph.registry value)))
       (N.of_nat (List.length (TaskGraph.registry value)))
    then TaskGraph.registry value ++ [Some graph]
    else replace (N.of_nat (List.length (TaskGraph.registry value))) (Some graph)
      (TaskGraph.registry value)) with
   | Some graph => graph | None => None end = Some graph).
 rewrite N.eqb_refl, registry_lookup_at_appended_index. reflexivity.
Qed.

Theorem graph_installation_preserves_other_identities : forall id other value graph,
 id <> other ->
 TaskGraph.lookup other (TaskGraph.store id graph value) = TaskGraph.lookup other value.
Proof.
 intros id other value graph Different. unfold TaskGraph.lookup.
 change (match registry_at other
   (if N.eqb id (N.of_nat (List.length (TaskGraph.registry value)))
    then TaskGraph.registry value ++ [Some graph]
    else replace id (Some graph) (TaskGraph.registry value)) with
   | Some graph => graph | None => None end =
   match registry_at other (TaskGraph.registry value) with
   | Some graph => graph | None => None end).
 destruct (N.eqb id (N.of_nat (List.length (TaskGraph.registry value)))) eqn:Append.
 - apply N.eqb_eq in Append. rewrite registry_append_preserves_other_lookup; [reflexivity|lia].
 - rewrite registry_replacement_preserves_other_lookup; [reflexivity|exact Different].
Qed.
(** Installing a graph never dispatches the pre-existing history again. *)
Theorem unchanged_history_has_no_new_outputs : forall value id task,
 K.find_task id value = Some task -> TaskGraph.new_outputs value id task = [].
Proof.
 intros value id task found. unfold TaskGraph.new_outputs. rewrite found.
 rewrite skipn_all. reflexivity.
Qed.

(** A rule only reacts to the Task identified by its declared source. *)
Theorem different_source_never_dispatches : forall source graph nodes rule output expected,
 TaskGraph.resolve (F.rule_source rule) nodes=Some expected -> source<>expected ->
 TaskGraph.pending_rule source graph nodes rule output=[].
Proof.
 intros source graph nodes rule output expected resolved other.
 unfold TaskGraph.pending_rule. rewrite resolved.
 apply N.eqb_neq in other. now rewrite other.
Qed.

Theorem failed_installation_is_atomic : forall id owner checked caller original failure,
 fold_left (fun progress node=>TaskGraph.birth owner caller node progress)
   (TaskGraph.declaration_nodes (proj1_sig checked))
   (TaskGraph.Born original [] [])=TaskGraph.BirthFailed failure ->
 decision_world (TaskGraph.install id owner checked caller original)=original /\
 decision_effects (TaskGraph.install id owner checked caller original)=[].
Proof.
 intros. unfold TaskGraph.install. destruct (TaskGraph.work_valid owner original);
 [rewrite H|]; split;reflexivity.
Qed.

(** Structural admission cannot establish world-dependent ownership. Every
    installation path rejects a Work that is absent from the current world. *)
Theorem missing_work_rejects_installation : forall id owner checked caller original,
 Selvedge.Features.Work.lookup owner original=None ->
 TaskGraph.install id (Some owner) checked caller original=
   TaskGraph.invalid_declaration original.
Proof.
 intros id owner checked caller original missing.
 unfold TaskGraph.install,TaskGraph.work_valid. now rewrite missing.
Qed.

Lemma concat_fragments : forall fragments,
 String.concat "" fragments = fold_right String.append "" fragments.
Proof.
 induction fragments as [|head tail IH]; [reflexivity|].
 destruct tail; cbn in *; [induction head; cbn; congruence|now rewrite IH].
Qed.

Theorem expansion_has_declared_meaning : forall message output,
 message_meaning output message (TaskGraph.expand message output).
Proof.
 fix IH 1. intros [|text|parts] output; try constructor.
 cbn. replace (fold_right (fun part rest=>String.append (TaskGraph.expand part output) rest) "" parts)
   with (String.concat "" (map (fun part=>TaskGraph.expand part output) parts)).
 2: { rewrite concat_fragments. induction parts; cbn; congruence. }
 apply concat_meaning.
 induction parts as [|part parts rest]; constructor; auto.
Qed.

Theorem declared_meaning_is_the_expansion : forall output message text,
 message_meaning output message text -> TaskGraph.expand message output = text.
Proof.
 fix IH 4. intros output message text meaning.
 destruct meaning as [|text|parts fragments related]; [reflexivity|reflexivity|].
 cbn. rewrite concat_fragments.
 induction related as [|part text parts texts head tail rest]; cbn; [reflexivity|].
 rewrite (IH output part text head), rest. reflexivity.
Qed.

Lemma declared_binding_is_resolved : forall key target nodes,
 node_binding key target nodes -> TaskGraph.resolve key nodes=Some target.
Proof.
 intros key target nodes binding. induction binding as [rest|node rest different bound IH].
 - unfold TaskGraph.resolve. cbn. now rewrite String.eqb_refl.
 - unfold TaskGraph.resolve in *. cbn. apply String.eqb_neq in different.
   now rewrite different.
Qed.

Lemma resolved_node_has_declared_binding : forall key target nodes,
 TaskGraph.resolve key nodes=Some target -> node_binding key target nodes.
Proof.
 intros key target nodes. induction nodes as [|[name task] nodes IH]; cbn; [discriminate|].
 unfold TaskGraph.resolve in *. cbn.
 destruct (String.eqb key name) eqn:matches; cbn.
 - intros same. inversion same; subst. apply String.eqb_eq in matches. subst. constructor.
 - intros bound. apply binding_later; [now apply String.eqb_neq|now apply IH].
Qed.

Lemma unresolved_node_has_no_declared_binding : forall key nodes,
 TaskGraph.resolve key nodes=None -> forall target, ~node_binding key target nodes.
Proof.
 intros key nodes missing target binding.
 apply declared_binding_is_resolved in binding. congruence.
Qed.

(** Both positive delivery and order are required. A dispatcher that always
    returns [] fails this theorem for a matching bound action. *)
Theorem pending_rule_obeys_declaration : forall source graph nodes rule output,
 rule_meaning source graph nodes rule output
   (TaskGraph.pending_rule source graph nodes rule output).
Proof.
 intros source graph nodes rule output. unfold TaskGraph.pending_rule.
 destruct (TaskGraph.resolve (F.rule_source rule) nodes) as [expected|] eqn:resolved.
 - destruct (N.eqb source expected) eqn:selected.
   + apply N.eqb_eq in selected. subst expected. apply matching_source;
     [now apply resolved_node_has_declared_binding|].
     induction (F.rule_actions rule) as [|action actions rest]; cbn; [constructor|].
     destruct (TaskGraph.resolve (F.action_target action) nodes) as [target|] eqn:bound.
     * econstructor; [now apply resolved_node_has_declared_binding|apply expansion_has_declared_meaning|exact rest].
     * econstructor; [now apply unresolved_node_has_no_declared_binding|exact rest].
   + eapply other_source with (expected:=expected);
     [now apply resolved_node_has_declared_binding|now apply N.eqb_neq].
 - apply missing_source. now apply unresolved_node_has_no_declared_binding.
Qed.

Theorem every_declared_handoff_is_delivered : forall source graph nodes rule output item,
 declared_handoff source graph nodes rule output item ->
 In item (TaskGraph.pending_rule source graph nodes rule output).
Proof.
 intros source graph nodes rule output [actual_graph actual_rule target text]
   [source_bound [action [member [target_bound [graph_same [rule_same meaning]]]]]].
 cbn in *. subst actual_graph actual_rule.
 apply declared_binding_is_resolved in source_bound.
 apply declared_binding_is_resolved in target_bound.
 unfold TaskGraph.pending_rule. rewrite source_bound, N.eqb_refl.
 induction (F.rule_actions rule) as [|head tail IH]; cbn in *; [contradiction|].
 destruct member as [<-|member].
 - rewrite target_bound. left. f_equal. now apply declared_meaning_is_the_expansion.
 - destruct (TaskGraph.resolve (F.action_target head) nodes); cbn; auto.
Qed.

Theorem registered_handoff_is_pending : forall source graph value declaration rule output item,
 In (graph,Some declaration)
   (indexed (fun id entry=>(id,entry)) 0 (TaskGraph.registry value)) ->
 In rule (F.graph_rules declaration) ->
 declared_handoff source graph (F.graph_nodes declaration) rule output item ->
 In item (TaskGraph.pending_deliveries source output value).
Proof.
 intros source graph value declaration rule output item registered member handoff.
 unfold TaskGraph.pending_deliveries. apply in_flat_map.
 exists (graph,Some declaration). split; [exact registered|]. cbn.
 apply in_flat_map. exists rule. split; [exact member|].
 now apply every_declared_handoff_is_delivered.
Qed.

(** A newly accepted plain assistant reply is observable by the real reaction
    hook. The freshness premise is about the stored origin identity; graph
    installation and repeated transition hooks cannot replay old history. *)
Theorem fresh_plain_reply_is_observed : forall before source task origin text,
 K.find_task source before=Some task ->
 origin_producer origin=source -> origin_mode origin=PlainOutput ->
 text<>""%string -> TaskGraph.seen_origin origin task=false ->
 TaskGraph.new_outputs before source (append_history [AssistantMessage origin text] task)=[text].
Proof.
 intros before source task origin text found producer plain nonempty unseen.
 unfold TaskGraph.new_outputs. rewrite found.
 assert (history : task_history (append_history [AssistantMessage origin text] task)=
   task_history task++[AssistantMessage origin text]) by (destruct task; reflexivity).
 rewrite history.
 rewrite skipn_app,skipn_all,Nat.sub_diag. cbn.
 rewrite producer,plain,unseen,N.eqb_refl.
 apply String.eqb_neq in nonempty. now rewrite nonempty.
Qed.

Lemma recording_receipt_preserves_tasks : forall graph receipt value,
 world_tasks (TaskGraph.record_receipt graph receipt value)=world_tasks value.
Proof.
 intros. unfold TaskGraph.record_receipt. destruct (TaskGraph.lookup graph value); [|reflexivity].
 unfold TaskGraph.store. reflexivity.
Qed.

(** The actual dispatcher writes the delivered text through the ordinary Task
    input operation. This is a state-update guarantee; it makes no assumption
    about an external model eventually producing a reply. *)
Theorem actual_delivery_reaches_idle_task : forall source item result task,
 K.find_task (TaskGraph.delivery_target item) (decision_world result)=Some task ->
 task_lifecycle task=Running Idle [] ->
 content_nonempty [TextPart (TaskGraph.delivery_text item)]=true ->
 exists received,
 K.find_task (TaskGraph.delivery_target item)
   (decision_world (TaskGraph.send_delivery source item result))=Some received /\
 task_history received=task_history task ++
   map UserMessage (task_queued task ++ [[TextPart (TaskGraph.delivery_text item)]]) /\
 task_lifecycle received=Running WantsModel [].
Proof.
 intros source item result task found idle nonempty.
 unfold TaskGraph.send_delivery, Tasks.send. rewrite found, idle, nonempty.
 cbn [decision_world].
 assert (tasks_same : forall id graph receipt value,
   K.find_task id (TaskGraph.record_receipt graph receipt value)=K.find_task id value).
 { intros. unfold K.find_task. now rewrite recording_receipt_preserves_tasks. }
 rewrite tasks_same.
 exists (Tasks.receive [TextPart (TaskGraph.delivery_text item)] task).
 split; [now apply find_put_task with task|].
 unfold Tasks.receive. rewrite idle. split; reflexivity.
Qed.

Lemma removed_graph_owner_is_absent : forall id bindings,
 F.association id (filter (fun entry => negb (N.eqb id (fst entry))) bindings) = None.
Proof.
 intros id bindings; unfold F.association.
 destruct (find (fun entry => N.eqb id (fst entry))
   (filter (fun entry => negb (N.eqb id (fst entry))) bindings))
   as [[key owner]|] eqn:Found; [|reflexivity].
 apply find_some in Found as [Member Selected].
 apply filter_In in Member as [_ Kept].
 change (N.eqb id key = true) in Selected.
 change (negb (N.eqb id key) = true) in Kept.
 rewrite Selected in Kept; discriminate.
Qed.

Theorem resolved_installation_associates_its_work : forall id owner checked caller original prepared nodes effects,
 TaskGraph.work_valid (Some owner) original = true ->
 fold_left (fun progress node => TaskGraph.birth (Some owner) caller node progress)
   (TaskGraph.declaration_nodes (proj1_sig checked)) (TaskGraph.Born original [] []) =
   TaskGraph.Born prepared nodes effects ->
 F.association id (F.feature_graph_owners (world_features
   (decision_world (TaskGraph.install id (Some owner) checked caller original)))) = Some owner.
Proof.
 intros id owner checked caller original prepared nodes effects Owned Prepared.
 unfold TaskGraph.install. rewrite Owned, Prepared.
 unfold F.association, K.with_features, Selvedge.Features.State.with_graph_owners.
 (* RecordUpdate setters reduce when their input records are constructors. *)
 destruct (TaskGraph.store id
   (F.TaskGraph (TaskGraph.declaration_name (proj1_sig checked)) nodes
     (TaskGraph.declaration_rules (proj1_sig checked)) []) prepared)
   as [sequence tasks ticket environment projects features].
 destruct features. cbn -[N.eqb]; now rewrite N.eqb_refl.
Qed.

Theorem graph_removal_preserves_other_identities : forall request caller value previous,
 TaskGraph.lookup (Selvedge.Generated.Commands.delete_task_graph_graph_id request) value = Some previous ->
 exists result,
 TaskGraph.command (Selvedge.Generated.Commands.Cmd_delete_task_graph request) caller value = Some result /\
 TaskGraph.lookup (Selvedge.Generated.Commands.delete_task_graph_graph_id request)
   (decision_world result) = None /\
 F.association (Selvedge.Generated.Commands.delete_task_graph_graph_id request)
   (F.feature_graph_owners (world_features (decision_world result))) = None /\
 forall other, Selvedge.Generated.Commands.delete_task_graph_graph_id request <> other ->
 TaskGraph.lookup other (decision_world result) = TaskGraph.lookup other value.
Proof.
 intros request caller value previous Found.
 unfold TaskGraph.command. rewrite Found.
 eexists; split; [reflexivity|].
 pose proof (graph_lookup_has_registry_entry _ _ _ Found) as Entry.
 split.
 - change (match registry_at (Selvedge.Generated.Commands.delete_task_graph_graph_id request)
     (replace (Selvedge.Generated.Commands.delete_task_graph_graph_id request) None
       (TaskGraph.registry value)) with Some graph => graph | None => None end = None).
   rewrite (registry_replace_selected _ _ _ _ _ Entry). reflexivity.
 - split.
   + apply removed_graph_owner_is_absent.
   + intros other Different. unfold TaskGraph.lookup.
   change (match registry_at other
     (replace (Selvedge.Generated.Commands.delete_task_graph_graph_id request) None
       (TaskGraph.registry value)) with Some graph => graph | None => None end =
     match registry_at other (TaskGraph.registry value) with Some graph => graph | None => None end).
     rewrite registry_replacement_preserves_other_lookup; [reflexivity|exact Different].
Qed.

Theorem recording_a_receipt_retains_the_latest_history : forall id receipt value previous,
 TaskGraph.lookup id value = Some previous ->
 TaskGraph.lookup id (TaskGraph.record_receipt id receipt value) =
 Some (F.TaskGraph (F.graph_name previous) (F.graph_nodes previous) (F.graph_rules previous)
   (skipn (List.length (F.graph_receipts previous ++ [receipt]) - 256)
     (F.graph_receipts previous ++ [receipt]))).
Proof.
 intros id receipt value previous Found. unfold TaskGraph.record_receipt. rewrite Found.
 now apply replacing_a_graph_preserves_its_identity with previous.
Qed.

Theorem recording_a_receipt_preserves_other_graphs : forall id other receipt value,
 id <> other ->
 TaskGraph.lookup other (TaskGraph.record_receipt id receipt value) = TaskGraph.lookup other value.
Proof.
 intros id other receipt value Different. unfold TaskGraph.record_receipt.
 destruct (TaskGraph.lookup id value); [|reflexivity].
 now apply graph_installation_preserves_other_identities.
Qed.

Theorem recording_a_receipt_bounds_the_retained_history : forall id receipt value previous current,
 TaskGraph.lookup id value = Some previous ->
 TaskGraph.lookup id (TaskGraph.record_receipt id receipt value) = Some current ->
 (List.length (F.graph_receipts current) <= 256)%nat.
Proof.
 intros id receipt value previous current Found Recorded.
 rewrite (recording_a_receipt_retains_the_latest_history _ _ _ _ Found) in Recorded.
 inversion Recorded; subst current. cbn [F.graph_receipts]. rewrite length_skipn.
 assert (Bound : forall total limit : nat, (total - (total - limit) <= limit)%nat)
   by (intros; lia).
 apply Bound.
Qed.

Theorem pending_deliveries_obey_registry_order : forall source output value,
 registry_meaning source output
   (indexed (fun id entry => (id,entry)) 0 (TaskGraph.registry value))
   (TaskGraph.pending_deliveries source output value).
Proof.
 intros source output value. unfold TaskGraph.pending_deliveries.
 generalize (indexed (fun id entry => (id,entry)) 0 (TaskGraph.registry value)).
 intro entries; induction entries as [|[id [graph|]] entries IH]; cbn.
 - constructor.
 - assert (Rules : exists fragments,
     Forall2 (fun rule parts => rule_meaning source id (F.graph_nodes graph) rule output parts)
       (F.graph_rules graph) fragments /\
     flat_map (fun rule => TaskGraph.pending_rule source id (F.graph_nodes graph) rule output)
       (F.graph_rules graph) = List.concat fragments).
   { induction (F.graph_rules graph) as [|rule rules [fragments [Meanings Expanded]]].
     - exists []; split; [constructor|reflexivity].
     - exists (TaskGraph.pending_rule source id (F.graph_nodes graph) rule output :: fragments).
       split; [constructor; [apply pending_rule_obeys_declaration|exact Meanings]|].
       cbn. now rewrite Expanded. }
   destruct Rules as [fragments [Meanings Expanded]]. rewrite Expanded.
   econstructor; eauto.
 - now constructor.
Qed.
