From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Browser Require Import Focus.
Import ListNotations.
Open Scope string_scope.

(** This is the native IO vocabulary, not the product's presentation model.
    Element input names a current semantic element and gesture; it cannot carry
    an arbitrary internal application command back into the model. *)
Inductive input_target :=
| ElementTarget (key gesture : string) (generation : N)
| CodeTarget (request : json)
| RetryRendering.
Record event_binding := Binding {
  event_name : string; native_kind : string; input : input_target
}.
Definition properties_json (values : list (string * string)) :=
  JArray (map (fun item => JObject [("name", JString (fst item));
    ("value", JString (snd item))]) values).
Definition input_json value := match value with
  | ElementTarget key gesture generation => JObject [("op",JString "element");
      ("key",JString key);("gesture",JString gesture);
      ("generation",JNumber (show_natural generation))]
  | CodeTarget request => JObject [("op",JString "code");("input",request)]
  | RetryRendering => JObject [("op",JString "retry_render")]
  end.
Definition binding_json value := JObject [
  ("event", JString (event_name value)); ("kind", JString (native_kind value));
  ("action", input_json (input value))].

Inductive node : Type :=
| Text (value : string)
| Element (key tag : string) (attributes styles : list (string * string))
    (events : list event_binding) (metadata : json) (children : list node)
| Markdown (key value : string) (complete : bool) (metadata : json)
| Mount (target : string) (children : list node).
Fixpoint encode_node value : json := match value with
  | Text text => JObject [("kind", JString "text"); ("value", JString text)]
  | Element key tag attributes styles events metadata children => JObject [
      ("kind", JString "element"); ("key", JString key); ("tag", JString tag);
      ("attributes", properties_json (if String.eqb key "" then attributes else ("data-key",key)::attributes)); ("styles", properties_json styles);
      ("events", JArray (map binding_json events)); ("metadata", metadata);
      ("children", JArray (map encode_node children))]
  | Markdown key text complete metadata => JObject [("kind", JString "markdown");
      ("key", JString key); ("value", JString text); ("complete", JBool complete);
      ("metadata", metadata)]
  | Mount target children => JObject [("kind", JString "portal");
      ("target", JString target); ("children", JArray (map encode_node children))]
  end.
Record target_update := UpdateTarget {
  target : string; attributes : list (string * string); styles : list (string * string)
}.
Definition update_json value := JObject [("target", JString (target value));
  ("attributes", properties_json (attributes value)); ("styles", properties_json (styles value))].
Definition scope_json value := match value with
  | Document => JObject [("type", JString "document")]
  | Temporary identity initial restore fallback occurrence => JObject [("type", JString "temporary");
      ("identity", JString identity); ("initial", JString initial); ("restore", JString restore); ("fallback", JString fallback);
      ("occurrence", match occurrence with Some value => JNumber (show_natural value) | None => JNull end)]
  end.
Record document := Document {
  root : node; title : string; document_generation : N;
  measurement_pending : bool; updates : list target_update; focus_scope : list Focus.scope
}.
Definition encode value := JObject [("root", encode_node (root value));
  ("title", JString (title value)); ("generation", JNumber (show_natural (document_generation value)));
  ("measurement_pending", JBool (measurement_pending value));
  ("target_updates", JArray (map update_json (updates value)));
  ("focus_scope", JArray(map scope_json (focus_scope value)))].
