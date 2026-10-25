From Stdlib Require Import String Bool.
From Selvedge.Foundation Require Import BoundedDiagnostic.

Theorem constructed_diagnostic_is_admitted receiver source :
  accepts receiver fallback = true -> accepts receiver (make receiver source) = true.
Proof.
  intro fixed. unfold make.
  destruct (accepts receiver (prefix (String.length source) (byte_budget receiver) source)) eqn:valid;
    assumption.
Qed.

Theorem constructed_diagnostic_obeys_receiver receiver source :
  accepts receiver fallback = true ->
  Utf8.well_formed (make receiver source) = true /\
  Utf8.no_nul (make receiver source) = true /\
  Nat.leb (String.length (make receiver source)) (byte_budget receiver) = true /\
  (require_nonblank receiver = true -> Utf8.nonblank (make receiver source) = true).
Proof.
  intro fixed. pose proof (constructed_diagnostic_is_admitted receiver source fixed) as valid.
  unfold accepts in valid. repeat rewrite Bool.andb_true_iff in valid.
  destruct valid as [[[unicode nul] bytes] blank]. repeat split; try assumption.
  intro required. now rewrite required in blank.
Qed.
