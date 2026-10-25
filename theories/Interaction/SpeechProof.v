From Stdlib Require Import String List Bool NArith.
From Selvedge.Interaction Require Speech.

Theorem cancelling_speech_releases_the_owned_operation state:
 Speech.speech_effects(Speech.speech_step Speech.Cancel state)=Speech.release state /\
 Speech.current(Speech.speech_state(Speech.speech_step Speech.Cancel state))=Speech.Idle.
Proof. split;reflexivity. Qed.
Theorem late_transcript_cannot_replace_the_active_recording connections selected next current ticket target text notice live:
 N.eqb ticket current=false ->
 Speech.speech_step(Speech.Transcribed ticket text)
  (Speech.Speech connections selected next(Speech.Transcribing current target)notice live)=
 Speech.keep(Speech.Speech connections selected next(Speech.Transcribing current target)notice live).
Proof. intro Different. cbn[Speech.speech_step Speech.current]. rewrite Different. reflexivity. Qed.
Theorem busy_speech_cannot_authorize state:
 Speech.free state=false -> Speech.speech_step Speech.Authorize state=Speech.keep state.
Proof. intro Busy. cbn[Speech.speech_step]. rewrite Busy. reflexivity. Qed.
Theorem unavailable_voice_cannot_take_the_microphone state task:
 Speech.free state=false \/ Speech.eligible true state=None ->
 Speech.speech_step(Speech.BeginVoice task)state=Speech.keep state.
Proof.
 intros [Busy|Unavailable];cbn[Speech.speech_step];unfold Speech.begin_voice.
 - rewrite Busy. reflexivity.
 - rewrite Unavailable. destruct(Speech.free state);reflexivity.
Qed.
