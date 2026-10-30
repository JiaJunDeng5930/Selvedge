From Stdlib Require Import String List Bool.
From Selvedge.Host Require Import Process ProcessProofs.
From Selvedge.Adapters Require Import Common HostProcess.
Import ListNotations.
Open Scope string_scope.

Theorem process_state_roundtrip current : state_of (state_json current) = current.
Proof.
  destruct current as [phase input busy drained reason].
  destruct phase, reason as [[code message]|]; reflexivity.
Qed.

Theorem public_reserved_write_is_exclusive current next :
  reserve_write current = inr next ->
  HostProcess.call "control.process.reserve_write"
    (JObject [("state",state_json next)]) =
  Json.failure "process_input_busy" "Another input write is still pending for this process".
Proof.
  intros H.
  change (match reserve_write (state_of (state_json next)) with
    | inl reason => fail reason | inr after => success (state_json after) end =
    Json.failure "process_input_busy" "Another input write is still pending for this process").
  rewrite process_state_roundtrip, (reserved_write_is_exclusive current next H).
  reflexivity.
Qed.

Theorem public_exit_rejects_write current terminal eof resize :
  process_phase current = Running ->
  admit_write (state_of (state_json (observe current ShellExited))) terminal eof resize =
    Some (Failure "process_stdin_closed" "The process input is closed").
Proof. rewrite process_state_roundtrip; apply exit_rejects_write. Qed.
