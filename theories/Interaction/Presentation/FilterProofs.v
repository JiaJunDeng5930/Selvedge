From Stdlib Require Import String List.
From Selvedge.Features Require BoardFilter.
Module BF := Selvedge.Features.BoardFilter.

(** A facet edit must leave every other selection intact.  The statement targets
    the same public toggle operation used by native board-filter input. *)
Theorem toggling_facet_preserves_other_facets
    (name entry:string)(before:BF.filter)(selected other:BF.category):
 BF.parse_category name=Some selected -> selected<>other ->
 BF.filter_values(BF.toggle name entry before)other=BF.filter_values before other.
Proof.
 intros Selected Distinct. unfold BF.toggle. rewrite Selected.
 unfold BF.set_values. simpl. destruct selected,other;simpl in *;congruence.
Qed.

Theorem toggling_facet_preserves_search_and_view name entry before:
 (BF.filter_query(BF.toggle name entry before),BF.filter_tab(BF.toggle name entry before))=
 (BF.filter_query before,BF.filter_tab before).
Proof. unfold BF.toggle. destruct(BF.parse_category name);reflexivity. Qed.

Theorem changing_query_preserves_selection query before:
 BF.filter_values(BF.set_query query before)=BF.filter_values before /\
 BF.filter_tab(BF.set_query query before)=BF.filter_tab before.
Proof. split;reflexivity. Qed.
