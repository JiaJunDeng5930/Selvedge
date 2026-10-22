From Stdlib Require Import Arith.
From Selvedge.Browser Require Import ControlContent Layout.

Theorem full_supporting_uses_available_room available full compact :
  full <= available ->
  choose_supporting available full compact = SupportingLayout FullSupporting Horizontal.
Proof.
  intros Fits. unfold choose_supporting.
  rewrite (proj2 (Nat.leb_le full available) Fits). reflexivity.
Qed.

Theorem compact_supporting_preserves_row_when_it_fits available full compact :
  available < full -> compact <= available ->
  choose_supporting available full compact = SupportingLayout CompactSupporting Horizontal.
Proof.
  intros Small Fits. unfold choose_supporting, row_flow.
  rewrite (proj2 (Nat.leb_gt full available) Small).
  rewrite (proj2 (Nat.leb_le compact available) Fits). reflexivity.
Qed.

Theorem undersized_supporting_changes_the_whole_row available full compact :
  available < full -> available < compact ->
  choose_supporting available full compact = SupportingLayout CompactSupporting Vertical.
Proof.
  intros Full Compact. unfold choose_supporting, row_flow.
  rewrite (proj2 (Nat.leb_gt full available) Full).
  rewrite (proj2 (Nat.leb_gt compact available) Compact). reflexivity.
Qed.
