From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Interaction Require Import Scene.
Import ListNotations.
Open Scope string_scope.

Inductive copy_state := Idle | Pending (ticket : N) | Feedback (ticket : N) (succeeded : bool).
Record block := Block { key : string; literal : string; wrap : bool; copy : copy_state; next : N }.
Inductive input := SourceChanged (value : string) | ToggleWrap | Copy
  | Copied (ticket : N) (success : bool) | Expire (ticket : N).
Inductive effect := Clipboard (ticket : N) (value : string) | Expiry (ticket : N).
Definition initial key text := Block key text false Idle 0.
Definition copy_enabled state := match copy state with Pending _ => false | _ => true end.
Definition with_copy value state := Block (key state) (literal state) (wrap state) value (next state).
Definition step event state : block * list effect :=
  match event with
  | SourceChanged value =>
      if String.eqb value (literal state) then (state, [])
      else (Block (key state) value (wrap state) Idle (next state), [])
  | ToggleWrap => (Block (key state) (literal state) (negb (wrap state)) (copy state) (next state), [])
  | Copy => match copy state with
      | Pending _ => (state, [])
      | _ => (Block (key state) (literal state) (wrap state) (Pending (next state)) (N.succ (next state)),
          [Clipboard (next state) (literal state)]) end
  | Copied ticket succeeded => match copy state with
      | Pending current => if N.eqb ticket current then
          (with_copy (Feedback ticket succeeded) state, [Expiry ticket]) else (state, [])
      | _ => (state, []) end
  | Expire ticket => match copy state with
      | Feedback current _ => if N.eqb ticket current then (with_copy Idle state, []) else (state, [])
      | _ => (state, []) end
  end.
Definition nat_json value := JNumber (show_natural value).
Definition encode_copy value := match value with
  | Idle => JObject [("type", JString "idle")]
  | Pending ticket => JObject [("type", JString "pending"); ("ticket", nat_json ticket)]
  | Feedback ticket succeeded => JObject [("type", JString "feedback"); ("ticket", nat_json ticket); ("success", JBool succeeded)] end.
Definition encode_state state := JObject [("key", JString (key state)); ("literal", JString (literal state));
  ("wrap", JBool (wrap state)); ("copy", encode_copy (copy state)); ("next", nat_json (next state))].
Definition natural_field name source := match number_field name source with Some text => parse_natural text | None => None end.
Definition decode_copy source := match string_field "type" source with
  | Some "idle" => Some Idle
  | Some "pending" => option_map Pending (natural_field "ticket" source)
  | Some "feedback" => match natural_field "ticket" source, bool_field "success" source with
      Some ticket, Some success => Some (Feedback ticket success) | _, _ => None end
  | _ => None end.
Definition decode_state source := match string_field "key" source, string_field "literal" source,
    bool_field "wrap" source, field "copy" source, natural_field "next" source with
  | Some key, Some text, Some wrap, Some copy, Some next => option_map (fun copy => Block key text wrap copy next) (decode_copy copy)
  | _, _, _, _, _ => None end.
Definition decode_input source := match string_field "type" source with
  | Some "source" => option_map SourceChanged (string_field "value" source)
  | Some "wrap" => Some ToggleWrap | Some "copy" => Some Copy
  | Some "copied" => match natural_field "ticket" source, bool_field "success" source with
      Some ticket, Some success => Some (Copied ticket success) | _, _ => None end
  | Some "expire" => option_map Expire (natural_field "ticket" source)
  | _ => None end.
Definition encode_effect effect := match effect with
  | Clipboard ticket text => JObject [("type", JString "clipboard"); ("ticket", nat_json ticket); ("text", JString text)]
  | Expiry ticket => JObject [("type", JString "expiry"); ("ticket", nat_json ticket); ("milliseconds", JNumber "1800")] end.
Inductive toolbar_action := CopyAction | WrapAction.
Definition button state suffix label event disabled : Scene.scene toolbar_action :=
  ActionButton (key state ++ "/" ++ suffix) [("label", JString label)] (Some event) disabled [].
Definition observe state : Scene.scene toolbar_action :=
  Container CGroup (key state ++ "/controls") [("layout", JString "row")] None
    [button state "copy" (match copy state with
      | Idle => "Copy code" | Pending _ => "Copying…" | Feedback _ true => "Copied" | Feedback _ false => "Copy failed" end)
      CopyAction (negb (copy_enabled state));
     button state "wrap" (if wrap state then "Unwrap code" else "Wrap code") WrapAction false].
Definition encode_toolbar_input state event :=
  JObject [("type", JString "code"); ("key", JString (key state));
    ("input", JObject [("type", JString (match event with
      CopyAction => "copy" | WrapAction => "wrap" end))])].
Definition result state effects := success (JObject [("state", encode_state state); ("scene", Scene.encode (encode_toolbar_input state) (observe state));
  ("wrap", JBool (wrap state)); ("effects", JArray (map encode_effect effects));
  ("code_styles", JArray
    [JObject [("name", JString "white-space"); ("value", JString (if wrap state then "pre-wrap" else "pre"))];
     JObject [("name", JString "overflow-wrap"); ("value", JString (if wrap state then "anywhere" else "normal"))]])]).
Definition code_block_call operation source := match operation with
  | "initial" => match string_field "key" source, string_field "text" source with
      Some key, Some text => result (initial key text) []
      | _, _ => failure "TypeError" "Code block requires key and literal source" end
  | "step" => match field "state" source, field "input" source with
      Some state, Some event => match decode_state state, decode_input event with
        Some state, Some event => let '(state, effects) := step event state in result state effects
        | _, _ => failure "TypeError" "Invalid code block state or event" end
      | _, _ => failure "TypeError" "Code block event requires state and input" end
  | _ => failure "RangeError" "Unknown code block operation" end.
