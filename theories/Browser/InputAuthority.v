From Stdlib Require Import Bool NArith.
From Selvedge.Browser Require Publication.
From Selvedge.Browser.Session Require Input.

(** Authored controls refer to a physically published source prefix. Ordinary
    application controls only need their synchronously committed DOM. This
    classification applies after resolving a semantic element; parser and IO
    observations retain their own owner, epoch and ticket checks. *)
Definition requires_prefix (input : Input.input) : bool :=
 match input with Input.Interactive _=>true|_=>false end.

Definition admit_generation (generation : N) (input : Input.input) (native prefix : option N) : bool :=
 match (if requires_prefix input then prefix else native) with
 |Some displayed=>N.eqb generation displayed
 |None=>false end.

Definition admit generation input current :=
 admit_generation generation input (Publication.native_displayed_generation current)
  (Publication.displayed_generation current).

Theorem authored_input_requires_its_published_prefix generation input current :
 admit generation (Input.Interactive input) current=Publication.admit generation current.
Proof. reflexivity. Qed.

Theorem native_input_uses_its_dom_receipt generation input current :
 requires_prefix input=false ->
 admit generation input current=Publication.native_admit generation current.
Proof. intro Native. unfold admit,admit_generation,Publication.native_admit. now rewrite Native. Qed.
