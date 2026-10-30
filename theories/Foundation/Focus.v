From Stdlib Require Import List.

(** A focus exposes the part an update may change and retains the rest.  Product
    decomposition makes the frame law independent of the operations built with
    the focus; adding an operation does not add another preservation case. *)
Record t (whole part : Type) := Focus {
 remainder : Type;
 split : whole -> part * remainder;
 join : part * remainder -> whole;
 join_split : forall value, join (split value) = value;
 split_join : forall parts, split (join parts) = parts
}.
Arguments remainder {whole part}.
Arguments split {whole part}.
Arguments join {whole part}.
Arguments join_split {whole part}.
Arguments split_join {whole part}.

Definition read {whole part} (focus : t whole part) (value : whole) :=
 fst (split focus value).
Definition frame {whole part} (focus : t whole part) (value : whole) :=
 snd (split focus value).
Definition modify {whole part} (focus : t whole part) (change : part -> part) (value : whole) :=
 join focus (change (read focus value), frame focus value).

Theorem modification_keeps_the_frame : forall whole part (focus : t whole part) change value,
 frame focus (modify focus change value) = frame focus value.
Proof.
 intros; unfold frame, modify, read; rewrite split_join; reflexivity.
Qed.
Theorem modification_has_its_selected_value : forall whole part (focus : t whole part) change value,
 read focus (modify focus change value) = change (read focus value).
Proof.
 intros; unfold frame, modify, read; rewrite split_join; reflexivity.
Qed.
Theorem unchanged_focus_keeps_the_value : forall whole part (focus : t whole part) value,
 modify focus (fun value => value) value = value.
Proof.
 intros; unfold modify, read, frame; rewrite <- surjective_pairing; apply join_split.
Qed.
Theorem modifications_compose : forall whole part (focus : t whole part) first second value,
 modify focus second (modify focus first value) =
 modify focus (fun selected => second (first selected)) value.
Proof.
 intros; unfold modify, read, frame; rewrite split_join; reflexivity.
Qed.
Theorem modifications_keep_the_frame : forall whole part change (focus : t whole part)
 (interpret : change -> part -> part) changes value,
 frame focus (fold_left (fun value change => modify focus (interpret change) value) changes value) =
 frame focus value.
Proof.
 intros whole part change focus interpret changes; induction changes as [|first rest IH]; intro value.
 - reflexivity.
 - cbn; rewrite IH; apply modification_keeps_the_frame.
Qed.
