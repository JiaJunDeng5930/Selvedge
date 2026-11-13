From Stdlib Require Import String List Bool NArith.
From Stdlib Require FSets.FMapFacts Structures.OrderedTypeEx.
From Selvedge.Browser.Presentation Require LiveUpdate.
From Selvedge.Browser.Scene Require Surface.
Import ListNotations.
Module S:=Surface.
Module Bindings := FMapFacts.WFacts_fun OrderedTypeEx.String_as_OT S.BindingMap.

Local Definition bound_input {A} (node : S.node A) key gesture value :=
 match S.BindingMap.find key (S.bind_node (fun receive => receive) node
   (S.BindingMap.empty _)) with
 |Some receive=>receive gesture value
 |None=>None end.

Theorem retained_live_preview_has_no_action before after view key gesture input :
 LiveUpdate.retains_preview before after=true ->
 S.node_actions (Selvedge.Browser.AuditReading.in_view view before)=[] /\
 S.node_actions (Selvedge.Browser.AuditReading.in_view view after)=[] /\
 bound_input (Selvedge.Browser.AuditReading.in_view view before) key gesture input=None /\
 bound_input (Selvedge.Browser.AuditReading.in_view view after) key gesture input=None.
Proof.
 unfold LiveUpdate.retains_preview. intros Retains.
 apply Bool.andb_true_iff in Retains as [_ Passive].
 destruct before as [first semantic label role meaning children].
 destruct after as [second semantic' label' role' meaning' children'].
 destruct children; [|discriminate]. destruct children';[|discriminate].
 destruct meaning; try discriminate; destruct meaning'; try discriminate;
 unfold bound_input;
 cbn [Selvedge.Browser.AuditReading.in_view Selvedge.Browser.AuditReading.scope_meaning
   S.node_actions S.meaning_actions List.map S.bind_node S.node_key S.node_meaning
   S.node_children List.fold_right S.bind_meaning];
 repeat rewrite Bindings.add_o; repeat rewrite Bindings.empty_o;
 repeat match goal with |- context [OrderedTypeEx.String_as_OT.eq_dec ?x ?y] =>
   destruct (OrderedTypeEx.String_as_OT.eq_dec x y) end;
 destruct gesture; repeat split.
Qed.
