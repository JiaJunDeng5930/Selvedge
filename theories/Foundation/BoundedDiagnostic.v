From Stdlib Require Import String Ascii List Bool NArith.
From Selvedge.Foundation Require Import Utf8.
From Selvedge.Foundation Require ArgumentDeclaration.
Open Scope string_scope.

Definition fallback := "External execution failed".

(** Consume complete scalars after escaping. Invalid UTF-8 bytes are replaced
    individually, as these bytes cannot denote a scalar in the observation. *)
Fixpoint prefix_acc (fuel budget : nat) (source accepted : string) : string :=
  match fuel, source with
  | S fuel, String _ rest =>
      let '(piece, remaining) := match Utf8.decode_one source with
      | Some value =>
          (if N.eqb value.(Utf8.scalar) 0%N then "\u0000" else value.(Utf8.encoded),
           value.(Utf8.remaining))
      | None => (String (ascii_of_nat 239) (String (ascii_of_nat 191)
                    (String (ascii_of_nat 189) "")), rest)
      end in
      let bytes := String.length piece in
      if Nat.leb bytes budget then prefix_acc fuel (budget - bytes) remaining (accepted ++ piece) else accepted
  | _, _ => accepted
  end.
Definition prefix fuel budget source := prefix_acc fuel budget source "".

(** The constructor returns the declared text value. A caller supplies a
    fixed admitted explanation for external blank or malformed diagnostics. *)
Definition make (constraints : ArgumentDeclaration.text_constraints)
 (fallback : ArgumentDeclaration.text_value (ArgumentDeclaration.ConstrainedText constraints))
 (source : string) : ArgumentDeclaration.text_value (ArgumentDeclaration.ConstrainedText constraints) :=
 let candidate := prefix (String.length source) (N.to_nat (ArgumentDeclaration.maximum_bytes constraints)) source in
 (* DEFENSE: External diagnostics can be blank or malformed; normalize these
    observations before constructing the durable callback. *)
 match ArgumentDeclaration.decode_text (ArgumentDeclaration.ConstrainedText constraints) candidate with
 | Some value => value | None => fallback end.
