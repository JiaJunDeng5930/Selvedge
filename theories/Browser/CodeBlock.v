From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Interaction Require Import Codec CodeSource.
Import ListNotations.
Open Scope string_scope.

Inductive copy_state := Idle | Pending (ticket : N) | Feedback (ticket : N) (succeeded : bool).
Record block := Block {
 identity : CodeSource.identity;
 literal : string;
 wrap : bool;
 copy : copy_state;
 next : N
}.
Inductive input := SourceChanged (value : string) | ToggleWrap | Copy
 | Copied (ticket : N) (success : bool) | Expire (ticket : N).
Inductive effect := Clipboard (ticket : N) (value : string) | Expiry (ticket : N).
Inductive control := CopyControl | WrapControl.
Definition controls := [CopyControl; WrapControl].
Definition initial who text := Block who text false Idle 0.
Definition copy_enabled state := match copy state with Pending _ => false | _ => true end.
Definition with_copy value state := Block (identity state) (literal state) (wrap state) value (next state).
Definition step event state : block * list effect := match event with
 | SourceChanged value =>
     if String.eqb value (literal state) then (state, [])
     else (Block (identity state) value (wrap state) Idle (next state), [])
 | ToggleWrap => (Block (identity state) (literal state) (negb (wrap state)) (copy state) (next state), [])
 | Copy => match copy state with
     | Pending _ => (state, [])
     | _ => (Block (identity state) (literal state) (wrap state) (Pending (next state)) (N.succ (next state)),
         [Clipboard (next state) (literal state)]) end
 | Copied ticket succeeded => match copy state with
     | Pending current => if N.eqb ticket current then
         (with_copy (Feedback ticket succeeded) state, [Expiry ticket]) else (state, [])
     | _ => (state, []) end
 | Expire ticket => match copy state with
     | Feedback current _ => if N.eqb ticket current then (with_copy Idle state, []) else (state, [])
     | _ => (state, []) end
 end.

(** Presentation is an observation of this fence's current code state, not an
    unrelated toolbar. Availability and captions are derived from that state. *)
Record presentation := CodePresentation {
 presented_identity : CodeSource.identity;
 presented_literal : string;
 presented_wrap : bool;
 presented_copy : copy_state
}.
Definition observe state := CodePresentation (identity state) (literal state) (wrap state) (copy state).
Definition control_label view value := match value with
 | CopyControl => match presented_copy view with Idle=>"Copy code"|Pending _=>"Copying…"
     |Feedback _ true=>"Copied"|Feedback _ false=>"Copy failed" end
 | WrapControl => if presented_wrap view then "Unwrap code" else "Wrap code"
 end.
Definition control_enabled view value := match value with
 | CopyControl => match presented_copy view with Pending _=>false|_=>true end
 | WrapControl => true
 end.
Definition control_input value := match value with CopyControl=>Copy|WrapControl=>ToggleWrap end.

Definition encode_copy value := match value with
 | Idle => JObject [("type",JString "idle")]
 | Pending ticket => JObject [("type",JString "pending");("ticket",number ticket)]
 | Feedback ticket succeeded => JObject [("type",JString "feedback");("ticket",number ticket);("ok",JBool succeeded)]
 end.
Definition encode_state state := JObject [("identity",CodeSource.encode_identity (identity state));
 ("text",JString (literal state));("wrap",JBool (wrap state));("copy",encode_copy (copy state));("next",number (next state))].
(* DEFENSE: Browser-owned code state and receipts cross the runtime's JSON
   boundary. Missing provenance or an unknown receipt kind is rejected. *)
Definition decode_copy source := kind <- string_field "type" source;;match kind with
 | "idle" => Some Idle
 | "pending" => ticket <- natural_field "ticket" source;;Some (Pending ticket)
 | "feedback" => ticket <- natural_field "ticket" source;;ok <- bool_field "ok" source;;Some (Feedback ticket ok)
 | _ => None end.
Definition decode_state source := who <- bind (field "identity" source) CodeSource.decode_identity;;
 text <- string_field "text" source;;wrapped <- bool_field "wrap" source;;
 copied <- bind (field "copy" source) decode_copy;;ticket <- natural_field "next" source;;
 Some (Block who text wrapped copied ticket).
Definition decode_input source := kind <- string_field "type" source;;match kind with
 | "source" => option_map SourceChanged (string_field "text" source)
 | "wrap" => Some ToggleWrap
 | "copy" => Some Copy
 | "copied" => ticket <- natural_field "ticket" source;;ok <- bool_field "ok" source;;Some (Copied ticket ok)
 | "expire" => option_map Expire (natural_field "ticket" source)
 | _ => None end.
Definition encode_input value := match value with
 | SourceChanged text => JObject [("type",JString "source");("text",JString text)]
 | ToggleWrap => JObject [("type",JString "wrap")]
 | Copy => JObject [("type",JString "copy")]
 | Copied ticket ok => JObject [("type",JString "copied");("ticket",number ticket);("ok",JBool ok)]
 | Expire ticket => JObject [("type",JString "expire");("ticket",number ticket)]
 end.
Definition encode_effect value := match value with
 | Clipboard ticket text => JObject [("type",JString "clipboard");("ticket",number ticket);("text",JString text)]
 | Expiry ticket => JObject [("type",JString "expiry");("ticket",number ticket);("delay_ms",number 1800)] end.
Inductive execution := Executed (state : block) (effects : list effect)
 | Rejected (name message : string).
Definition execute operation source := match operation with
 | "initial" => match bind (field "identity" source) CodeSource.decode_identity, string_field "text" source with
     | Some who, Some text => Executed (initial who text) []
     | _, _ => Rejected "TypeError" "Code block requires a document identity and literal source" end
 | "step" => match bind (field "state" source) decode_state, bind (field "input" source) decode_input with
     | Some state, Some event => let '(state,effects):=step event state in Executed state effects
     | _, _ => Rejected "TypeError" "Invalid code block state or event" end
 | _ => Rejected "RangeError" "Unknown code block operation" end.
