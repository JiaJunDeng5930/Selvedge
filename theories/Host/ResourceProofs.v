From Stdlib Require Import String List.
From Selvedge.Adapters Require Import Common.
From Selvedge.Host Require Import Resources.
Import ListNotations.
Open Scope string_scope.
Theorem recovery_never_allocates : forall receipt,
  get (Resources.recover receipt) "effects" = JArray [JString "finish"] \/
  get (Resources.recover receipt) "effects" = JArray [JString "credentials"].
Proof.
  intros receipt. unfold Resources.recover.
  destruct (String.eqb (str receipt "status") "destroyed"); [left | right]; reflexivity.
Qed.

Theorem new_allocation_requires_persistence : forall receipt,
  get (Resources.start receipt) "effects" = JArray [JString "persist"].
Proof. reflexivity. Qed.

Theorem failed_initial_persistence_emits_no_allocation : forall receipt,
  get (Resources.step (get (Resources.start receipt) "state")
    (JObject [("kind",JString "persistence_failed")])) "effects" = JArray [JString "finish"].
Proof. reflexivity. Qed.
