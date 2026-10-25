From Stdlib Require Import String Ascii List Bool NArith.
From Selvedge.Foundation Require Import Utf8.
Open Scope string_scope.

(** Failure text is an external observation. Each receiver chooses its own
    durable byte bound and whether an explanation must contain nonblank text. *)
Record contract := Contract { byte_budget : nat; require_nonblank : bool }.
Definition fallback := "External execution failed".
Definition accepts (receiver : contract) (text : string) :=
  Utf8.well_formed text && Utf8.no_nul text &&
  Nat.leb (String.length text) receiver.(byte_budget) &&
  (if receiver.(require_nonblank) then Utf8.nonblank text else true).

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

(** The smart constructor checks the receiver's actual text contract. Blank
    observations (including a prefix consisting only of whitespace) need the
    fixed explanation for receivers requiring a reason. *)
Definition make (receiver : contract) (source : string) : string :=
  let candidate := prefix (String.length source) receiver.(byte_budget) source in
  (* DEFENSE: External diagnostics can be blank or malformed; the durable
     receiver requires an admitted explanation even when execution failed. *)
  if accepts receiver candidate then candidate else fallback.
