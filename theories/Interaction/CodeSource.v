From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Interaction Require Import Codec Origin.
Import ListNotations.
Open Scope string_scope.

(** A code fence belongs to the document that produced it, independently of the
    physical Markdown node currently displaying that document. *)
Inductive source :=
| SharedDocument (namespace owner : string)
| Message (task message : N)
| StreamingPart (task operation part : N)
| Generated (namespace : string) (viewer : N)
    (provenance : Origin.output_origin) (complete : bool).
Record identity := CodeIdentity { document_source : source; ordinal : N }.

Definition source_key value := match value with
| SharedDocument namespace owner =>
    "shared/" ++ show_nat (String.length namespace) ++ ":" ++ namespace ++
    "/" ++ show_nat (String.length owner) ++ ":" ++ owner
| Message task message => "task/" ++ show_natural task ++ "/message/" ++ show_natural message
| StreamingPart task operation part => "task/" ++ show_natural task ++ "/stream/" ++
    show_natural operation ++ "/part/" ++ show_natural part
| Generated namespace viewer provenance _ => Origin.content_key namespace viewer provenance
end.
Definition complete value := match value with StreamingPart _ _ _ => false
| Generated _ _ _ closed => closed | _ => true end.
Definition key value := source_key value.(document_source) ++ "/code/" ++ show_natural value.(ordinal).
Definition owner_key value := source_key value.(document_source) ++ "/fence/" ++ show_natural value.(ordinal).
Definition same left right := String.eqb (key left) (key right).
Definition belongs value owner := String.eqb (source_key value.(document_source)) (source_key owner).

Definition encode_source value := match value with
| SharedDocument namespace owner => JObject [("type",JString "shared");
    ("namespace",JString namespace);("owner",JString owner)]
| Message task message => JObject [("type",JString "message");
    ("task",number task);("message",number message)]
| StreamingPart task operation part => JObject [("type",JString "stream");
    ("task",number task);("operation",number operation);("part",number part)]
| Generated namespace viewer provenance closed => JObject [("type",JString "generated");
    ("namespace",JString namespace);("viewer",number viewer);
    ("origin",Origin.encode_origin provenance);("complete",JBool closed)]
end.
(* DEFENSE: Markdown source identities enter the pure runtime through its JSON
   boundary; an incomplete identity cannot name a document or receive controls. *)
Definition decode_source value : option source :=
 kind <- string_field "type" value;;
 match kind with
 | "shared" => namespace <- string_field "namespace" value;;owner <- string_field "owner" value;;
     Some (SharedDocument namespace owner)
 | "message" => task <- natural_field "task" value;;message <- natural_field "message" value;;
     Some (Message task message)
 | "stream" => task <- natural_field "task" value;;operation <- natural_field "operation" value;;
     part <- natural_field "part" value;;Some (StreamingPart task operation part)
 | "generated" => namespace <- string_field "namespace" value;;viewer <- natural_field "viewer" value;;
     provenance <- bind (field "origin" value) Origin.decode_origin;;closed <- bool_field "complete" value;;
     Some (Generated namespace viewer provenance closed)
 | _ => None
 end.
Definition encode_identity value := JObject [("source",encode_source value.(document_source));
 ("ordinal",number value.(ordinal))].
Definition decode_identity value := source <- bind (field "source" value) decode_source;;
 ordinal <- natural_field "ordinal" value;;Some (CodeIdentity source ordinal).
