From Stdlib Require Import String List NArith.
From Selvedge.Features Require Import Domain TaskGraph.
Import ListNotations.
Scheme All for Forall2.
Module F := Selvedge.Features.Domain.

(** Declaration semantics: an output expression denotes the source text, a
    literal denotes its own text, and concatenation preserves fragment order.
    This relation mentions neither the production expander nor its output. *)
Inductive message_meaning (source : string) : F.graph_message -> string -> Prop :=
| output_meaning : message_meaning source F.GraphOutput source
| literal_meaning : forall text, message_meaning source (F.GraphLiteral text) text
| concat_meaning : forall parts fragments,
    Forall2 (message_meaning source) parts fragments ->
    message_meaning source (F.GraphConcat parts) (String.concat "" fragments).

(** Binding is stated on the declaration's node identities, independently of
    the production resolver. Checked declarations have unique node keys. *)
Inductive node_binding (key:string) (task:N) : list F.resolved_node -> Prop :=
| binding_here : forall rest, node_binding key task (F.ResolvedNode key task::rest)
| binding_later : forall node rest,
    key<>F.node_key node -> node_binding key task rest ->
    node_binding key task (node::rest).

(** Actions are interpreted in declaration order, including repeated targets.
    Missing bindings are omitted; admitted declarations have no such bindings.
    A binding is a fact about node identity, not an assumption that a delivery
    was produced. *)
Inductive action_meaning (nodes : list F.resolved_node) (graph : N)
    (rule : string) (output : string) :
    list F.graph_action -> list TaskGraph.delivery -> Prop :=
| no_actions : action_meaning nodes graph rule output [] []
| missing_target : forall action actions deliveries,
    (forall target, ~node_binding (F.action_target action) target nodes) ->
    action_meaning nodes graph rule output actions deliveries ->
    action_meaning nodes graph rule output (action :: actions) deliveries
| delivered_action : forall action actions target text deliveries,
    node_binding (F.action_target action) target nodes ->
    message_meaning output (F.action_message action) text ->
    action_meaning nodes graph rule output actions deliveries ->
    action_meaning nodes graph rule output (action :: actions)
      (TaskGraph.Delivery graph rule target text :: deliveries).

Inductive rule_meaning (source graph : N) (nodes : list F.resolved_node)
    (rule : F.graph_rule) (output : string) : list TaskGraph.delivery -> Prop :=
| missing_source :
    (forall expected, ~node_binding (F.rule_source rule) expected nodes) ->
    rule_meaning source graph nodes rule output []
| other_source : forall expected,
    node_binding (F.rule_source rule) expected nodes ->
    source <> expected -> rule_meaning source graph nodes rule output []
| matching_source : forall deliveries,
    node_binding (F.rule_source rule) source nodes ->
    action_meaning nodes graph (F.rule_key rule) output
      (F.rule_actions rule) deliveries ->
    rule_meaning source graph nodes rule output deliveries.

(** A positive handoff obligation, independent of dispatch implementation. *)
Definition declared_handoff (source graph : N) (nodes : list F.resolved_node)
    (rule : F.graph_rule) (output : string) (item : TaskGraph.delivery) : Prop :=
  node_binding (F.rule_source rule) source nodes /\
  exists action,
    In action (F.rule_actions rule) /\
    node_binding (F.action_target action) (TaskGraph.delivery_target item) nodes /\
    TaskGraph.delivery_graph item = graph /\
    TaskGraph.delivery_rule item = F.rule_key rule /\
    message_meaning output (F.action_message action) (TaskGraph.delivery_text item).

(** Registry order determines dispatch order; empty slots left by deletion
    contribute no delivery and do not reorder the remaining graphs. *)
Inductive registry_meaning (source : N) (output : string) :
    list (N * option F.task_graph) -> list TaskGraph.delivery -> Prop :=
| no_registered_graphs : registry_meaning source output [] []
| absent_registered_graph : forall graph entries deliveries,
    registry_meaning source output entries deliveries ->
    registry_meaning source output ((graph,None)::entries) deliveries
| present_registered_graph : forall graph value entries fragments deliveries,
    Forall2 (fun rule parts =>
      rule_meaning source graph (F.graph_nodes value) rule output parts)
      (F.graph_rules value) fragments ->
    registry_meaning source output entries deliveries ->
    registry_meaning source output ((graph,Some value)::entries)
      (List.concat fragments ++ deliveries).
