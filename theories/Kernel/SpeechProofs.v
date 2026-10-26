From Selvedge.Kernel Require Import TaskChangesProofs.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json JsonProofs Utf8.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import Domain Codec State CommandExecution Packet LifecycleProofs.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

(** A final transcript is durable conversation evidence, not a request to
    execute work. Its stable identity belongs to the accepting task.
    This is the domain operation's update; Packet may advance the durable
    sequence in addition to that update. *)
Theorem a_new_transcript_changes_only_the_task_history :
 forall id session item speaker completion text value task,
 find_task id value = Some task ->
 nonempty session = true -> nonempty item = true -> nonempty text = true ->
 Utf8.well_formed text = true ->
 find (fun message => match message with
   | SpeechTranscript owner actual_session actual_item _ _ _ =>
     N.eqb owner id && String.eqb session actual_session && String.eqb item actual_item
   | _ => false end) (task_history task) = None ->
 task_archived task = false ->
 let result := CommandExecution.speech_transcript id session item speaker completion text value in
 decision_world result = put_task id
   (set task_history (fun _ => task_history task ++
     [SpeechTranscript id session item speaker completion text]) task) value /\
 decision_effects result = [].
Proof.
 intros id session item speaker completion text value task Found Session Item Text Unicode Fresh Live.
 unfold CommandExecution.speech_transcript; rewrite Found, Session, Item, Text, Unicode, Fresh.
 unfold task_archived in Live.
 destruct (task_lifecycle task) eqn:Lifecycle; try discriminate;
 split; reflexivity.
Qed.

Theorem a_matching_transcript_receipt_is_not_recorded_twice :
 forall id session item speaker completion text value task,
 find_task id value = Some task ->
 nonempty session = true -> nonempty item = true -> nonempty text = true ->
 Utf8.well_formed text = true ->
 find (fun message => match message with
   | SpeechTranscript owner actual_session actual_item _ _ _ =>
     N.eqb owner id && String.eqb session actual_session && String.eqb item actual_item
   | _ => false end) (task_history task) =
   Some (SpeechTranscript id session item speaker completion text) ->
 let result := CommandExecution.speech_transcript id session item speaker completion text value in
 decision_world result = value /\ decision_effects result = [] /\
 bool_default "replayed" (value_or_null "result" (decision_reply result)) false = true.
Proof.
 intros id session item speaker completion text value task Found Session Item Text Unicode Receipt.
 unfold CommandExecution.speech_transcript; rewrite Found, Session, Item, Text, Unicode, Receipt,
   JsonProofs.equal_is_reflexive.
 repeat split; reflexivity.
Qed.

Theorem transcript_commands_never_request_scheduling : forall payload result,
 Packet.command_schedules (Cmd_record_speech_transcript payload) result = false.
Proof.
 intros payload result; unfold Packet.command_schedules.
 destruct (bool_default "ok" (decision_reply result) false); reflexivity.
Qed.

Theorem a_matching_delegation_receipt_is_not_delivered_twice :
 forall id session identity mode text value task,
 find_task id value = Some task ->
 nonempty session = true -> nonempty identity = true ->
 Tasks.content_nonempty [TextPart text] = true ->
 find (fun message => match message with
   | SpeechDelegation owner actual_session actual_identity _ _ =>
     N.eqb owner id && String.eqb session actual_session && String.eqb identity actual_identity
   | _ => false end) (task_history task) = Some (SpeechDelegation id session identity mode text) ->
 let result := CommandExecution.speech_delegation id session identity mode text value in
 decision_world result = value /\ decision_effects result = [] /\
 bool_default "replayed" (value_or_null "result" (decision_reply result)) false = true.
Proof.
 intros id session identity mode text value task Found Session Identity Text Receipt.
 unfold CommandExecution.speech_delegation; rewrite Found, Session, Identity, Text, Receipt,
   JsonProofs.equal_is_reflexive.
 repeat split; reflexivity.
Qed.

Theorem replayed_delegations_never_request_scheduling : forall payload result,
 bool_default "replayed" (value_or_null "result" (decision_reply result)) false = true ->
 Packet.command_schedules (Cmd_accept_speech_delegation payload) result = false.
Proof.
 intros payload result Replayed; unfold Packet.command_schedules; rewrite Replayed.
 destruct (bool_default "ok" (decision_reply result) false); reflexivity.
Qed.

Theorem a_fresh_voice_delegation_records_ordinary_input_and_its_receipt :
 forall id session identity mode text value task,
 (mode = "send" \/ mode = "steer") ->
 find_task id value = Some task ->
 task_lifecycle task = Running Idle [] -> task_queued task = [] ->
 nonempty session = true -> nonempty identity = true ->
 Tasks.content_nonempty [TextPart text] = true ->
 find (fun message => match message with
   | SpeechDelegation owner actual_session actual_identity _ _ =>
     N.eqb owner id && String.eqb session actual_session && String.eqb identity actual_identity
   | _ => false end) (task_history task) = None ->
 exists updated,
 find_task id (decision_world (CommandExecution.speech_delegation id session identity mode text value)) = Some updated /\
 task_history updated = task_history task ++
   [UserMessage [TextPart text]; SpeechDelegation id session identity mode text] /\
 task_lifecycle updated = Running WantsModel [] /\
 decision_effects (CommandExecution.speech_delegation id session identity mode text value) = [].
Proof.
 intros id session identity mode text value task Mode Found IdleTask NoQueued Session Identity Text Fresh.
 destruct Mode as [Mode|Mode]; subst mode.
 - assert (Delivered : Tasks.send_result id [TextPart text] value =
     CommandResult.Accepted (CommandResult.Change (JObject [("task_id",Numbers.number id)])
       (put_task id (Tasks.receive [TextPart text] task) value) [])).
   { apply CommandResult.a_successful_decision_identifies_its_typed_change with (before:=value).
     change (Tasks.send id [TextPart text] value =
       accept (JObject [("task_id",Numbers.number id)]) (put_task id (Tasks.receive [TextPart text] task) value) []).
     rewrite TaskChangesProofs.send_expression,Found,IdleTask,Text; reflexivity. }
   unfold CommandExecution.speech_delegation; rewrite Found, Session, Identity, Text, Fresh.
   change (String.eqb "send" "steer") with false; cbn [andb]; rewrite Delivered.
   cbn [CommandResult.commit CommandResult.map CommandResult.bind CommandResult.decide CommandResult.resolve
     CommandResult.accept CommandResult.change_world CommandResult.change_value CommandResult.change_effects].
   rewrite (find_put_task id task (Tasks.receive [TextPart text] task) value Found).
   eexists; split; [apply find_put_task with (Tasks.receive [TextPart text] task); apply find_put_task with task; exact Found|].
   unfold Tasks.receive,Tasks.receive_changes; rewrite IdleTask,NoQueued.
   repeat split; try reflexivity.
   change ((task_history task ++ [UserMessage [TextPart text]]) ++
     [SpeechDelegation id session identity "send" text] =
     task_history task ++ [UserMessage [TextPart text]; SpeechDelegation id session identity "send" text]).
   rewrite <- app_assoc; reflexivity.
   destruct task as [contract profile settings lifecycle history queued lineage parent cursor consumed].
   cbn in IdleTask; subst lifecycle; reflexivity.
 - assert (Steered : Tasks.steer_result id [TextPart text] value =
     CommandResult.Accepted (CommandResult.Change (JObject [("task_id",Numbers.number id)])
       (put_task id (with_lifecycle (Running WantsModel [])
         (append_history [UserMessage [TextPart text]] task)) value) [])).
   { apply CommandResult.a_successful_decision_identifies_its_typed_change with (before:=value).
     change (Tasks.steer id [TextPart text] value =
       accept (JObject [("task_id",Numbers.number id)])
         (put_task id (with_lifecycle (Running WantsModel []) (append_history [UserMessage [TextPart text]] task)) value) []).
     rewrite TaskChangesProofs.steer_expression; rewrite Found, IdleTask, Text.
     unfold task_activity, task_operations; rewrite !IdleTask.
     cbn [History.interrupted_phase].
     unfold Tasks.inference_effects, task_activity; rewrite IdleTask.
     destruct task as [contract profile settings lifecycle history queued lineage parent cursor consumed].
     cbn in IdleTask; subst lifecycle; reflexivity. }
   unfold CommandExecution.speech_delegation; rewrite Found, Session, Identity, Text, Fresh.
   rewrite String.eqb_refl, Steered; cbn [andb].
   cbn [CommandResult.commit CommandResult.map CommandResult.bind CommandResult.decide CommandResult.resolve
     CommandResult.accept CommandResult.change_world CommandResult.change_value CommandResult.change_effects].
   rewrite (find_put_task id task
     (with_lifecycle (Running WantsModel []) (append_history [UserMessage [TextPart text]] task)) value Found).
   eexists; split.
   + apply find_put_task with
       (with_lifecycle (Running WantsModel []) (append_history [UserMessage [TextPart text]] task)).
     apply find_put_task with task. exact Found.
   + unfold append_history.
     repeat split; try reflexivity.
     change ((task_history task ++ [UserMessage [TextPart text]]) ++
       [SpeechDelegation id session identity "steer" text] =
       task_history task ++ [UserMessage [TextPart text]; SpeechDelegation id session identity "steer" text]).
     rewrite <- app_assoc; reflexivity.
Qed.
