From Stdlib Require Import String List Bool NArith.
From Selvedge.Browser.Presentation Require LiveUpdate.
From Selvedge.Browser.Scene Require Surface.
Import ListNotations.
Module S:=Surface.

Theorem retained_live_preview_has_no_action before after view key gesture input :
 LiveUpdate.retains_preview before after=true ->
 S.node_actions (Selvedge.Browser.AuditReading.in_view view before)=[] /\
 S.node_actions (Selvedge.Browser.AuditReading.in_view view after)=[] /\
 S.resolve_node key gesture input (Selvedge.Browser.AuditReading.in_view view before)=None /\
 S.resolve_node key gesture input (Selvedge.Browser.AuditReading.in_view view after)=None.
Proof.
 unfold LiveUpdate.retains_preview. intros Retains.
 apply Bool.andb_true_iff in Retains as [_ Passive].
 destruct before as [first semantic label role meaning children].
 destruct after as [second semantic' label' role' meaning' children'].
 destruct children; [|discriminate]. destruct children';[|discriminate].
 destruct meaning; try discriminate; destruct meaning'; try discriminate;
 cbn [Selvedge.Browser.AuditReading.in_view Selvedge.Browser.AuditReading.scope_meaning S.node_actions
   S.meaning_actions S.resolve_node S.resolve_meaning];
 repeat match goal with |- context [String.eqb ?x ?y] => destruct (String.eqb x y) end;
 destruct gesture; repeat split.
Qed.
