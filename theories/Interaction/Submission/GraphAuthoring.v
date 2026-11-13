From Stdlib Require Import List String Bool NArith.
From Selvedge.Foundation Require Import Json TextJson.
From Selvedge.Features Require Domain Observation.
From Selvedge.Interaction Require Import Codec.
Import ListNotations.
Open Scope string_scope.

Record handoff := Handoff {
  handoff_name : string;
  handoff_source : option N;
  handoff_target : option N
}.

Definition source_endpoint_label := "来源对话".
Definition target_endpoint_label := "接收对话".
Definition handoff_name_label := "转发名称".
Definition empty_handoff := Handoff "对话转发" None None.

Fixpoint render_declaration_at (indent : string) (value : json) : string :=
 let line := TextJson.byte 10 in
 let inner := indent ++ "  " in
 let enclosure open close rows :=
   open ++ line ++ inner ++ String.concat ("," ++ line ++ inner) rows ++ line ++ indent ++ close in
 match value with
 | JArray [] => "[]"
 | JArray values =>
   enclosure "[" "]" (map (render_declaration_at inner) values)
 | JObject [] => "{}"
 | JObject fields =>
   enclosure "{" "}" (map (fun '(key, value) =>
     TextJson.quote key ++ ": " ++ render_declaration_at inner value) fields)
 | _ => TextJson.render_json value
 end.

Definition render_declaration := render_declaration_at "".

Definition handoff_node key task :=
 JObject [("key", JString key); ("task_id", match task with Some id => number id | None => JNull end)].

(** An unselected endpoint is part of the draft. The graph declaration parser
    rejects it until it has a task identifier. *)
Definition handoff_declaration (draft : handoff) :=
 JObject [("name", JString (handoff_name draft));
   ("nodes", JArray [handoff_node "source" (handoff_source draft);
                    handoff_node "target" (handoff_target draft)]);
   ("rules", JArray [Observation.graph_rule_json
     (Domain.GraphRule "handoff" "source" [Domain.GraphAction "target" Domain.GraphOutput])])].

Definition endpoint node : option (option N) :=
 value <- field "task_id" node;;
 match value with
 | JNull => Some None
 | _ => option_map (@Some N) (natural value)
 end.

(** The selection editor owns only declarations it can reproduce exactly.
    Custom rules and nodes remain editable as JSON. *)
Definition observe_handoff value : option handoff :=
 name <- string_field "name" value;;
 nodes <- array_field "nodes" value;;
 match nodes with
 | [source; target] =>
   origin <- endpoint source;;
   destination <- endpoint target;;
   let draft := Handoff name origin destination in
   (* An explicit self-route remains editable in JSON. *)
   let distinct := match origin, destination with
    | Some from, Some to => negb (N.eqb from to)
    | _, _ => true end in
   if distinct && Json.equal value (handoff_declaration draft) then Some draft else None
 | _ => None
 end.
