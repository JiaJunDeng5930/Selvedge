From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common Observation Audio.
Import ListNotations.
Open Scope string_scope.

Theorem transcript_events_cannot_delegate_work : forall source delegation,
  str source "type" = "turn.done" ->
  event source <> inr (DelegationEvent delegation).
Proof.
  intros source delegation kind H.
  unfold event in H. rewrite kind in H. cbn in H.
  unfold transcript,control_event in H.
  destruct (existsb (String.eqb (str (get source "turn") "role")) ["user";"assistant"] &&
    is_text (get (get source "turn") "transcript")); discriminate.
Qed.

Theorem audio_capability_matches_account_authority : forall transport assistant content source result,
  Audio.call transport assistant content "audio.capability" source = success result <->
  boolean_field source "authorized" = true /\ str source "source" = "chatgpt_audio" /\
  nonempty_text (get source "id") = true /\ result = get source "id".
Proof.
  intros transport assistant content source result.
  split.
  - intros accepted.
    change (admit (eligible source) (get source "id") "ChatGPT audio sign-in is required" = success result) in accepted.
    unfold admit in accepted. destruct (eligible source) eqn:eligible; [|discriminate].
    inversion accepted; subst result.
    unfold Audio.eligible, authorized in eligible.
    apply andb_true_iff in eligible as [authority identity].
    apply andb_true_iff in authority as [authority_flag source_kind].
    apply String.eqb_eq in source_kind. auto.
  - intros [authority_flag [source_kind [identity ->]]].
    change (admit (eligible source) (get source "id") "ChatGPT audio sign-in is required" = success (get source "id")).
    unfold admit, eligible, authorized.
    rewrite authority_flag, source_kind, identity. reflexivity.
Qed.

Definition initial_item (item : json) :=
  String.eqb (str item "type") "message" && existsb (String.eqb (str item "role")) ["user";"assistant"] &&
  is_array (get item "content") && forallb (fun content =>
    existsb (String.eqb (str content "type")) ["input_text";"output_text"] && nonempty_text (get content "text")) (items (get item "content")).

Local Lemma initial_message_is_valid : forall role content,
  existsb (String.eqb role) ["user";"assistant"] = true ->
  nonempty_text content = true -> initial_item (initial_message role content) = true.
Proof.
  intros role content role_valid content_valid.
  apply existsb_exists in role_valid. destruct role_valid as [selected [member same]].
  cbn in member. destruct member as [<-|[<-|[]]];
    apply String.eqb_eq in same; subst role;
    change (nonempty_text content && true = true); now rewrite content_valid.
Qed.

Local Lemma initial_history_items_are_valid : forall assistant content message,
  forallb initial_item (initial_history_item assistant content message) = true.
Proof.
  intros assistant content message. unfold initial_history_item.
  set (role := if assistant message then JString "assistant"
    else if String.eqb (str message "role") "speech_transcript" then get message "speaker" else get message "role").
  destruct (existsb (String.eqb (text role)) ["user";"assistant"] && nonempty_text (content message)) eqn:accepted;
    [|reflexivity].
  apply andb_true_iff in accepted as [role_valid content_valid].
  cbn [forallb]. rewrite (initial_message_is_valid _ _ role_valid content_valid). reflexivity.
Qed.

Theorem initial_context_constructs_protocol_messages : forall transport assistant content source result,
  Audio.call transport assistant content "audio.initial_context" source = success result ->
  is_array result = true /\ forallb initial_item (items result) = true.
Proof.
  intros transport assistant content source result accepted.
  change (initial_context assistant content source = success result) in accepted.
  unfold initial_context in accepted.
  inversion accepted; subst result; clear accepted. split; [reflexivity|].
  change (forallb initial_item (flat_map (initial_history_item assistant content) (items (get source "messages"))) = true).
  induction (items (get source "messages")) as [|message rest remaining]; [reflexivity|].
  cbn [flat_map]. rewrite forallb_app, initial_history_items_are_valid, remaining. reflexivity.
Qed.

Theorem transcript_tail_preserves_unrelated_utterance : forall pending completed,
  starts pending completed = false -> starts completed pending = false ->
  transcript_tail pending completed = pending.
Proof.
  intros pending completed H1 H2.
  unfold transcript_tail. now rewrite H1,H2.
Qed.
