From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common Observation Audio.
Import ListNotations.
Open Scope string_scope.

Theorem transcript_events_cannot_delegate_work : forall source result,
  str (get source "value") "type" = "turn.done" ->
  event source = success result ->
  get result "type" <> JString "delegation".
Proof.
  intros source result kind H.
  unfold event in H. rewrite kind in H. cbn in H.
  unfold transcript,admit in H.
  destruct (existsb (String.eqb (str (get (get source "value") "turn") "role")) ["user";"assistant"] &&
    is_text (get (get (get source "value") "turn") "transcript")); [|discriminate].
  destruct (String.eqb (str (get (get source "value") "turn") "transcript") "");
    inversion H; subst; discriminate.
Qed.

Theorem accepted_voice_session_requires_audio_authority : forall source result,
  session_request source = success result ->
  boolean_field source "authorized" = true /\ str source "source" = "chatgpt_audio".
Proof.
  intros source result H.
  assert (A : request_connection source = true).
  { destruct (request_connection source) eqn:E; [reflexivity|].
    unfold session_request in H. rewrite E in H. cbn [admit] in H. discriminate. }
  unfold request_connection,authorized in A.
  repeat rewrite andb_true_iff in A.
  destruct A as [_ [authority identity]].
  apply String.eqb_eq in identity. auto.
Qed.

Theorem transcript_tail_preserves_unrelated_utterance : forall source,
  is_text (get source "pending") = true -> is_text (get source "completed") = true ->
  starts (str source "pending") (str source "completed") = false ->
  starts (str source "completed") (str source "pending") = false ->
  transcript_tail source = success (JString (str source "pending")).
Proof.
  intros source pending completed H1 H2.
  unfold transcript_tail,admit. rewrite pending,completed,H1,H2. reflexivity.
Qed.
