From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Interaction.Interactive Require Import Types State Local Registry Expand Snapshot Runtime Language.
Import ListNotations.

Definition authored_effect effect := match effect with
 | FillDraft _ _ _ | SendMessage _ _ _ _ | WriteClipboard _ _ _ _ | OpenUrl _ _ _ _ => true
 | _=>false end.
Definition no_authored output := forallb (fun effect=>negb(authored_effect effect)) output.

Theorem feedback_never_issues_effects visible state environment who path ticket ok message :
 (Runtime.step_visible visible (Feedback who path ticket ok message) state environment).(effects) = [].
Proof.
 unfold Runtime.step_visible,Runtime.input_owner.
 destruct(State.find_block who (blocks state)); simpl; [|reflexivity].
 unfold Runtime.reduce; simpl. reflexivity.
Qed.



Theorem storage_feedback_never_issues_effects visible state environment who revision ok message :
 (Runtime.step_visible visible (StorageResult who revision ok message) state environment).(effects) = [].
Proof.
 unfold Runtime.step_visible,Runtime.input_owner.
 destruct(State.find_block who (blocks state)); simpl; [|reflexivity].
 unfold Runtime.reduce; simpl. destruct(N.eqb revision(State.revision b)); reflexivity.
Qed.

Theorem missing_action_owner_ignored visible state environment event_id :
 State.find_block event_id.(event_owner) state.(blocks) = None ->
 Runtime.step_visible visible (ActionClicked event_id) state environment = Decision state [].
Proof. intros missing. unfold Runtime.step_visible,Runtime.input_owner. rewrite missing. reflexivity. Qed.

Theorem hidden_authored_input_ignored visible input b environment :
 Runtime.authored_input input = true -> visible b.(block_owner)=false ->
 Runtime.reduce visible input b environment = (b,[]).
Proof. intros authored hidden. unfold Runtime.reduce. rewrite authored,hidden. reflexivity. Qed.

Theorem settled_feedback_ignored path ticket ok message b expected previous_ok previous_message :
 State.feedback_at path b = Some(FeedbackEntry path (Answered expected previous_ok previous_message)) ->
 Runtime.settle_feedback path ticket ok message b = b.
Proof. intro settled. unfold Runtime.settle_feedback. rewrite settled. reflexivity. Qed.

Theorem matching_feedback_settles_and_preserves_state visible who path ticket occurrence action ok message b environment :
 State.feedback_at path b = Some(FeedbackEntry path (Waiting ticket occurrence action)) ->
 mounted_at path occurrence b.(State.mounts)=true ->
 let next:=fst(Runtime.reduce visible(Feedback who path ticket ok message)b environment)in
 State.feedback_at path next=Some(FeedbackEntry path(Answered ticket ok message)) /\
 (next.(State.locals),next.(State.sources),next.(State.views),next.(State.mounts),next.(State.source),next.(State.syntax),
  next.(State.next_ticket),next.(State.next_occurrence),next.(State.revision),next.(State.restore_state))=
 (b.(State.locals),b.(State.sources),b.(State.views),b.(State.mounts),b.(State.source),b.(State.syntax),
  b.(State.next_ticket),b.(State.next_occurrence),b.(State.revision),b.(State.restore_state)).
Proof.
 intros pending mounted. cbn -[Runtime.settle_feedback State.feedback_at State.set_feedback].
 unfold Runtime.settle_feedback. rewrite pending,N.eqb_refl,mounted. cbn -[State.set_feedback State.feedback_at].
 unfold State.feedback_at,State.set_feedback,State.with_feedbacks.
 destruct b;cbn -[String.eqb];rewrite String.eqb_refl;split;reflexivity.
Qed.

Theorem entry_matching_feedback visible state environment who path ticket occurrence action ok message b :
 State.find_block who state.(blocks)=Some b ->
 State.feedback_at path b=Some(FeedbackEntry path(Waiting ticket occurrence action)) ->
 mounted_at path occurrence b.(State.mounts)=true ->
 exists next,
 Runtime.step_visible visible(Feedback who path ticket ok message)state environment=
   Decision(State(State.replace_block next state.(blocks)))[] /\
 State.feedback_at path next=Some(FeedbackEntry path(Answered ticket ok message)) /\
 (next.(State.locals),next.(State.sources),next.(State.views),next.(State.mounts),next.(State.source),next.(State.syntax),
  next.(State.next_ticket),next.(State.next_occurrence),next.(State.revision),next.(State.restore_state))=
 (b.(State.locals),b.(State.sources),b.(State.views),b.(State.mounts),b.(State.source),b.(State.syntax),
  b.(State.next_ticket),b.(State.next_occurrence),b.(State.revision),b.(State.restore_state)).
Proof.
 intros found pending mounted. exists(Runtime.settle_feedback path ticket ok message b). split.
 - unfold Runtime.step_visible,Runtime.input_owner. rewrite found. reflexivity.
 - exact(matching_feedback_settles_and_preserves_state visible who path ticket occurrence action ok message b environment pending mounted).
Qed.

Theorem wrong_ticket_ignored path ticket ok message b expected occurrence action :
 State.feedback_at path b = Some(FeedbackEntry path (Waiting expected occurrence action)) ->
 N.eqb ticket expected=false -> Runtime.settle_feedback path ticket ok message b=b.
Proof. intros pending different. unfold Runtime.settle_feedback. rewrite pending,different. reflexivity. Qed.

Theorem edited_restore_ignored visible b environment who definition callback_revision payload :
 b.(edited)=true ->
 Runtime.reduce visible (Restore who definition callback_revision payload) b environment=(b,[]).
Proof.
 intro edited. unfold Runtime.reduce,Runtime.authored_input; simpl.
 unfold Snapshot.restore_admitted.
 destruct(restore_state b); try reflexivity.
 rewrite edited. simpl. repeat rewrite andb_false_r. reflexivity.
Qed.

Theorem restore_issues_no_authored_effect b prepared environment definition callback_revision payload :
 no_authored(snd(Snapshot.restore b prepared environment definition callback_revision payload))=true.
Proof.
 unfold Snapshot.restore. destruct(Snapshot.restore_admitted b prepared definition callback_revision); simpl; [|reflexivity].
 destruct payload as[raw|]; simpl;try reflexivity.
 destruct(TextJson.parse_json raw)as[entry|];try reflexivity.
 destruct(Codec.bind(field "payload"entry)(Snapshot.decode _ _))as[admitted|];[destruct admitted as[[restored_locals restored_views] valid]|];reflexivity.
Qed.

Theorem forbidden_external_action_issues_no_effect event_id b environment :
 Expand.external_allowed b (Runtime.prepared b environment) environment=false ->
 match Runtime.clicked event_id b environment with (_,output,_)=>output=[] end.
Proof.
 intro forbidden. unfold Runtime.clicked.
 destruct(Runtime.event_node b environment event_id)as[node|]; [destruct node as[current props binding children|key reason]|];try reflexivity.
 destruct binding as[active|id active|action availability];try reflexivity.
 destruct availability;try reflexivity.
 rewrite forbidden. destruct action as[id value| |text|text|text|url];simpl;try reflexivity.
 destruct(Local.find_local id (locals b));try reflexivity.
 destruct(Local.assign l value);reflexivity.
Qed.

Theorem preview_or_interrupted_actions_issue_no_external_effect event_id b environment :
 b.(block_ending) <> Complete ->
 match Runtime.clicked event_id b environment with (_,output,_)=>output=[] end.
Proof.
 intro incomplete. apply forbidden_external_action_issues_no_effect.
 unfold Expand.external_allowed. destruct(block_ending b);try contradiction;
 simpl;repeat rewrite andb_false_r;reflexivity.
Qed.
