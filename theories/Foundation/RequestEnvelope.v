From Stdlib Require Import NArith.

(** A pending receiver and its external request share this value.  The
    correlation identity and frozen input cannot be selected independently
    when the receiver is installed and the request is emitted. *)
Record t (payload : Type) := Envelope {
 identity : N;
 input : payload
}.
Arguments Envelope {payload} _ _.
Arguments identity {payload} _.
Arguments input {payload} _.
