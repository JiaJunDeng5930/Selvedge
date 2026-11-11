From Stdlib Require Import String List Bool NArith.
From Selvedge.Browser.Session Require Speech.

Theorem cancelling_speech_releases_the_owned_operation state:
 Speech.speech_effects(Speech.speech_step Speech.Cancel state)=Speech.release state /\
 Speech.current(Speech.speech_state(Speech.speech_step Speech.Cancel state))=Speech.Idle.
Proof. split;reflexivity. Qed.
Theorem late_transcript_cannot_replace_the_active_recording connections selected next current ticket target text notice live login:
 N.eqb ticket current=false ->
 Speech.speech_step(Speech.Transcribed ticket text)
  (Speech.Speech connections selected next(Speech.Transcribing current target)notice live login)=
 Speech.keep(Speech.Speech connections selected next(Speech.Transcribing current target)notice live login).
Proof. intro Different. cbn[Speech.speech_step Speech.current]. rewrite Different. reflexivity. Qed.
Theorem busy_speech_cannot_authorize state trigger:
 Speech.free state=false -> Speech.speech_step(Speech.Authorize trigger)state=Speech.keep state.
Proof. intro Busy. cbn[Speech.speech_step]. unfold Speech.can_authorize. rewrite Busy. reflexivity. Qed.
Theorem closing_sign_in_releases_the_active_attempt state dialog ticket method:
 Speech.sign_in state=Some dialog ->
 Speech.login_attempt(Speech.login_stage dialog)=Some(ticket,method) ->
 let decision:=Speech.speech_step Speech.CloseLogin state in
 Speech.sign_in(Speech.speech_state decision)=None /\
 Speech.speech_effects decision=(Speech.ReleaseLogin ticket::nil)%list.
Proof.
 intros Open Active. cbn[Speech.speech_step]. unfold Speech.close_login. rewrite Open.
 unfold Speech.release_login. rewrite Active. split;reflexivity.
Qed.
Theorem closed_sign_in_ignores_late_completion state ticket outcome:
 Speech.sign_in state=None ->
 Speech.speech_step(Speech.LoginFinished ticket outcome)state=Speech.keep state.
Proof. intro Closed. cbn[Speech.speech_step]. unfold Speech.observe_login. rewrite Closed. reflexivity. Qed.
Theorem unavailable_voice_cannot_take_the_microphone state task:
 Speech.free state=false \/ Speech.eligible true state=None ->
 Speech.speech_step(Speech.BeginVoice task)state=Speech.keep state.
Proof.
 intros [Busy|Unavailable];cbn[Speech.speech_step];unfold Speech.begin_voice.
 - rewrite Busy. reflexivity.
 - rewrite Unavailable. destruct(Speech.free state);reflexivity.
Qed.
