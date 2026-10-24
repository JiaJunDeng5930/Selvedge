From Stdlib Require Import Arith Lia.
From Selvedge.Browser Require Import Typography.

(** Each information level is visibly larger than the preceding level at every root size. *)
Theorem body_larger_than_support root : support_size root < body_size root.
Proof. unfold body_size. pose proof (Nat.le_max_l (S (support_size root)) (scaled root 13)). lia. Qed.
Theorem section_larger_than_body root : body_size root < section_size root.
Proof. unfold section_size. pose proof (Nat.le_max_l (S (body_size root)) (scaled root 14)). lia. Qed.
Theorem title_larger_than_section root : section_size root < title_size root.
Proof. unfold title_size. pose proof (Nat.le_max_l (S (section_size root)) (scaled root 20)). lia. Qed.
Theorem introduction_larger_than_title root : title_size root < display_size root.
Proof. unfold display_size. pose proof (Nat.le_max_l (S (title_size root)) (scaled root 28)). lia. Qed.
Theorem line_box_exceeds_font_size root tier : size root tier < line_height root tier.
Proof. unfold line_height. pose proof (Nat.le_max_l (S (size root tier)) (scaled root (nominal_leading tier))). lia. Qed.
