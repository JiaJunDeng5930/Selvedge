From Stdlib Require Import String List Bool.
From Selvedge.Adapters Require Import Common.
From Selvedge.Host Require Import AudioState AudioSession.
Import ListNotations.
Open Scope string_scope.

Theorem stop_closes_stream : forall state message,
  AudioState.phase (fst (AudioState.stop state message)) = AudioState.Closed.
Proof.
  intros [identity generation phase sequence user assistant turns pending] message.
  destruct phase; unfold AudioState.stop; cbn [AudioState.phase AudioState.user_tail AudioState.assistant_tail AudioState.completed];
    destruct (String.eqb user ""); destruct (String.eqb assistant ""); reflexivity.
Qed.

Theorem closing_stream_flushes_at_most_once : forall state message,
  snd (AudioState.stop (fst (AudioState.stop state message)) message) = [].
Proof.
  intros state message. unfold AudioState.stop at 1.
  rewrite stop_closes_stream. reflexivity.
Qed.

Theorem final_transcript_requires_journal : forall state event,
  str event "type" = "transcript" -> boolean_field event "final" = true ->
  exists next token command,
    AudioSession.observe_event state event = (next,[AudioSession.CommitSpeech token command]).
Proof.
  intros state event Htype Hfinal. unfold AudioSession.observe_event.
  rewrite Htype, Hfinal. simpl. unfold AudioSession.commit.
  repeat eexists.
Qed.
