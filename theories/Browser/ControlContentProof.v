From Stdlib Require Import Arith String List.
From Selvedge.Browser Require Import ControlContent Layout DOM ControlPurpose Appearance.
From Selvedge.Features Require BoardFilter Domain.
From Selvedge.Interaction Require Input ControlPurpose.
From Selvedge.Programming.Presentation Require Surface Model.
From Selvedge.Interaction.Presentation Require Roles.
Import ListNotations.

Module AppPurpose := Selvedge.Interaction.ControlPurpose.
Module S := Selvedge.Programming.Presentation.Surface.
Module PM := Selvedge.Programming.Presentation.Model.
Module R := Selvedge.Interaction.Presentation.Roles.
Module CC := Selvedge.Browser.ControlContent.
Module P := Selvedge.Browser.ControlPurpose.
Module NativeAppearance := Selvedge.Browser.Appearance.
Module BF := Selvedge.Features.BoardFilter.
Module BoardDomain := Selvedge.Features.Domain.
Module I := Selvedge.Interaction.Input.

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

Theorem board_filter_toggle_keeps_its_domain_category snapshot state category value :
  AppPurpose.describe snapshot state (I.BoardToggle (BF.category_name category) value) =
    P.BoardFilterChoice category value.
Proof. destruct category; reflexivity. Qed.

Theorem board_filter_choice_content_shows_its_category_glyph
    artwork label category value symbol :
  CC.board_filter_glyph category value = Some symbol ->
  CC.board_filter_choice_content artwork label category value [] =
    Some (List.app (artwork symbol) [DOM.Text label]).
Proof. unfold CC.board_filter_choice_content; intros Glyph; rewrite Glyph; reflexivity. Qed.

Theorem board_filter_choice_container_shows_its_category_glyph
    snapshot state artwork env key label category value symbol :
  CC.board_filter_glyph category value = Some symbol ->
  CC.container_content (AppPurpose.describe snapshot state) artwork env key label
    R.Button
    (S.Choice S.MultipleChoice false ""
      (PM.Control "board-filter-choice" label PM.Secondary
        (I.BoardToggle (BF.category_name category) value) PM.Available))
    [] [] = Some (List.app (artwork symbol) [DOM.Text label]).
Proof.
  intros Glyph.
  cbn [CC.container_content PM.control_input].
  rewrite board_filter_toggle_keeps_its_domain_category.
  unfold CC.board_filter_choice_content.
  rewrite Glyph.
  reflexivity.
Qed.

Theorem board_filter_glyph_is_registered category value symbol :
  CC.board_filter_glyph category value = Some symbol ->
  NativeAppearance.find_symbol symbol <> None.
Proof.
  destruct category; cbn [CC.board_filter_glyph].
  - destruct (find (fun stage => String.eqb value (BoardDomain.stage_name stage)) BoardDomain.stages)
      as [stage|] eqn:Stage; [|discriminate].
    intros Glyph. inversion Glyph; subst symbol. destruct stage; vm_compute; discriminate.
  - destruct (find (fun priority => String.eqb value (BoardDomain.priority_name priority)) BoardDomain.priorities)
      as [priority|] eqn:Priority; [|discriminate].
    intros Glyph. inversion Glyph; subst symbol. destruct priority; vm_compute; discriminate.
  - intros Glyph. inversion Glyph; subst symbol. vm_compute; discriminate.
  - destruct (String.prefix "agent/" value); intros Glyph;
      inversion Glyph; subst symbol; vm_compute; discriminate.
  - intros Glyph. inversion Glyph; subst symbol. vm_compute; discriminate.
  - intros Glyph. inversion Glyph; subst symbol. vm_compute; discriminate.
  - intros Glyph. inversion Glyph; subst symbol. vm_compute; discriminate.
Qed.
