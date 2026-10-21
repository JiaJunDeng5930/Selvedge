From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json.
Import ListNotations.
Open Scope string_scope.

Inductive phase := Idle | Composing | SupersededComposition | SupersededTail.
Record state := State { identity : string; canonical : string; session : phase }.
Inductive event := Rebind (value : string) | Synchronize (value : string) | Reject (value : string)
  | CompositionStarted | CompositionEnded | InputStarted | InputObserved.
Record decision := Decision { updated : state; deliver : bool; replace : bool }.
Definition supersede phase := match phase with Composing => SupersededComposition | _ => phase end.
Definition rebind phase := match phase with Composing => SupersededComposition | _ => SupersededTail end.
Definition step input current := match input with
  | Rebind value => if String.eqb value (identity current) then Decision current false false
      else Decision (State value (canonical current) (rebind (session current))) false true
  | Synchronize value => if String.eqb value (canonical current) then Decision current false false
      else Decision (State (identity current) value (supersede (session current))) false true
  | Reject value => Decision (State (identity current) value (supersede (session current))) false true
  | CompositionStarted => Decision (State (identity current) (canonical current) Composing) false false
  | InputStarted => Decision (State (identity current) (canonical current) Idle) false false
  | CompositionEnded => match session current with
      | Idle | Composing => Decision (State (identity current) (canonical current) Idle) true false
      | SupersededComposition | SupersededTail =>
          Decision (State (identity current) (canonical current) SupersededTail) false true end
  | InputObserved => match session current with
      | Idle => Decision current true false
      | Composing => Decision current false false
      | SupersededComposition | SupersededTail => Decision current false true end
  end.
Definition phase_name phase := match phase with
  | Idle => "idle" | Composing => "composing" | SupersededComposition => "superseded_composition" | SupersededTail => "superseded_tail" end.
Definition encode_state state := JObject [("identity", JString (identity state));
  ("canonical", JString (canonical state)); ("session", JString (phase_name (session state)))].
Definition decode_state value := match string_field "identity" value, string_field "canonical" value, string_field "session" value with
  | Some identity, Some canonical, Some phase =>
      match phase with
      | "idle" => Some (State identity canonical Idle) | "composing" => Some (State identity canonical Composing)
      | "superseded_composition" => Some (State identity canonical SupersededComposition)
      | "superseded_tail" => Some (State identity canonical SupersededTail) | _ => None end
  | _, _, _ => None end.
Definition decode_event value := match string_field "event" value with
  | Some "rebind" => option_map Rebind (string_field "value" value)
  | Some "synchronize" => option_map Synchronize (string_field "value" value)
  | Some "reject" => option_map Reject (string_field "value" value)
  | Some "composition_started" => Some CompositionStarted | Some "composition_ended" => Some CompositionEnded
  | Some "input_started" => Some InputStarted | Some "input_observed" => Some InputObserved | _ => None end.
Definition field_session_call source :=
  match field "state" source with
  | Some encoded => match decode_state encoded, decode_event source with
      | Some state, Some event => let next := step event state in success (JObject
          [("state", encode_state (updated next)); ("deliver", JBool (deliver next)); ("replace", JBool (replace next))])
      | _, _ => failure "TypeError" "Invalid native field session or event" end
  | None => match string_field "identity" source, string_field "value" source with
      | Some identity, Some value => success (JObject [("state", encode_state (State identity value Idle));
          ("deliver", JBool false); ("replace", JBool true)])
      | _, _ => failure "TypeError" "Native field initialization requires identity and value" end
  end.
