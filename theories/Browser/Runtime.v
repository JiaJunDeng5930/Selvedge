From Stdlib Require Import String List Bool Arith NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Browser Require Import Document Native FieldSession.
From Selvedge.Interaction Require Import CodeBlock.
Import ListNotations.
Open Scope string_scope.

Definition natural_field (name : string) (source : json) : option nat :=
  match number_field name source with Some text => parse_nat text | None => None end.
Definition binary_field (name : string) (source : json) : option N :=
  match number_field name source with Some text => parse_natural text | None => None end.
Definition binary_json (value : N) := JNumber (show_natural value).
Definition bool_value (name : string) (source : json) :=
  match bool_field name source with Some value => value | None => false end.
Definition nat_json (value : nat) := JNumber (show_nat value).
Definition invalid (message : string) := failure "TypeError" message.
Definition native_key (source : json) : json :=
  match string_field "keyboard" source with
  | None => invalid "Native key requires keyboard"
  | Some key =>
      let ime := match natural_field "key_code" source with
        Some code => Nat.eqb code 229 | None => false end in
      let input := KeyObservation key (bool_value "composing" source) ime
        (bool_value "shift" source) (bool_value "alt" source) (bool_value "modified" source) in
      let decision := normalize_key input (bool_value "multiline" source) (bool_value "enabled" source) (bool_value "pending" source) in
      success (JObject [("submit", JBool (submit decision));
        ("prevent_default", JBool (prevent_default decision))])
  end.
Definition native_key_action (source : json) : json :=
  match string_field "keyboard" source, field "bindings" source with
  | Some key, Some bindings =>
      if bool_value "composing" source || bool_value "modified" source || bool_value "shift" source || bool_value "alt" source ||
        (match natural_field "key_code" source with Some code => Nat.eqb code 229 | None => false end)
      then success JNull
      else success (match field key bindings with Some action => action | None => JNull end)
  | _, _ => invalid "Native key action requires keyboard and bindings"
  end.
Definition layout (source : json) : json :=
  match natural_field "viewport" source, natural_field "navigation" source,
      natural_field "content" source, natural_field "rail" source, natural_field "gap" source with
  | Some width, Some navigation, Some content, Some rail, Some gap =>
      let requirements := Allocation navigation content rail gap in
      success (JObject [("mode", JString
        (match allocate width requirements with Simultaneous => "simultaneous" | Sequential => "sequential" end));
        ("minimum", nat_json (simultaneous_minimum requirements))])
  | _, _, _, _, _ => invalid "Browser layout requires nonnegative pixel observations"
  end.
Definition publication_state (source : json) : option publication :=
  match binary_field "semantic" source, binary_field "document" source, binary_field "published" source,
      string_field "namespace" source, binary_field "sequence" source with
  | Some semantic, Some document, Some published, Some namespace, Some sequence =>
      Some (Publication semantic document published namespace sequence)
  | _, _, _, _, _ => None
  end.
Definition publication_json (state : publication) : json := JObject
  [("semantic", binary_json (semantic_generation state)); ("document", binary_json (document_generation state)); ("published", binary_json (published_generation state));
   ("namespace", JString (namespace state)); ("sequence", binary_json (sequence state))].
Definition publication_call (source : json) : json :=
  match publication_state source, string_field "event" source with
  | Some state, Some "advance" => success (publication_json (advance_semantics state))
  | Some state, Some "ready" => success (JBool (fresh state))
  | Some state, Some "document" => match binary_field "generation" source with
      Some generation => success (publication_json (accept_document generation state))
      | None => invalid "Document publication requires generation" end
  | Some state, Some "publish" => match binary_field "generation" source with
      Some generation => success (publication_json (accept_publication generation state))
      | None => invalid "Publication requires generation" end
  | Some state, Some "admit" => match binary_field "generation" source with
      | Some generation => success (JBool (admit_generation generation state))
      | None => invalid "Event admission requires its publication generation" end
  | Some state, Some "refresh" =>
      match string_field "source_namespace" source, binary_field "source_sequence" source with
      | Some namespace, Some sequence => success
          (JBool (refresh_needed namespace sequence (bool_value "sources_fresh" source) state))
      | _, _ => invalid "Commit notice requires namespace and sequence"
      end
  | _, _ => invalid "Browser publication requires current state and event"
  end.
Definition snapshot_call source :=
  match publication_state source, string_field "expected_namespace" source,
      string_field "incoming_namespace" source, binary_field "incoming_sequence" source with
  | Some state, Some expected, Some incoming, Some cursor => success (JBool
      (admit_snapshot (if bool_value "authenticating" source then Authentication else ExistingSession)
        expected incoming cursor state))
  | _, _, _, _ => invalid "Snapshot requires request scope and namespace/sequence observations" end.
Fixpoint text_observations (values : list json) : option (list string) :=
  match values with
  | [] => Some []
  | JString value :: rest => option_map (cons value) (text_observations rest)
  | _ => None end.
Definition target_observation (value : json) : option Native.target_observation :=
  match string_field "key" value, array_field "aliases" value, string_field "view" value with
  | Some key, Some aliases, Some view => option_map (fun aliases => TargetObservation key aliases view) (text_observations aliases)
  | _, _, _ => None end.
Fixpoint target_observations (values : list json) : option (list Native.target_observation) :=
  match values with
  | [] => Some []
  | value :: rest => match target_observation value, target_observations rest with
      | Some value, Some rest => Some (value :: rest) | _, _ => None end
  end.
Definition resolve_target_call (source : json) : json :=
  match string_field "target" source, string_field "view" source, array_field "candidates" source with
  | Some target, Some view, Some candidates =>
      match target_observations candidates with
      | Some candidates => success (match (match string_field "fallback" source with
          | Some fallback => resolve_focus_target target fallback view candidates
          | None => resolve_target target view candidates end) with
          | Some key => JString key | None => JNull end)
      | None => invalid "Physical target candidates require key, aliases and view" end
  | _, _, _ => invalid "Target resolution requires target, view and observed candidates" end.
Definition focus_call (source : json) : json :=
  match string_field "current" source, array_field "targets" source with
  | Some current, Some targets =>
      match text_observations targets with
      | Some targets => success
          (match cycle (bool_value "backward" source) current targets with
          Some key => JString key | None => JNull end)
      | None => invalid "Focus targets must be strings"
      end
  | _, _ => invalid "Focus cycle requires current and targets"
  end.
Definition reading_state (source : json) : option Native.reading_state :=
  match string_field "intent" source with
  | Some mode =>
      let anchor := match field "anchor" source with
        | Some value => match string_field "key" value, string_field "offset" value with
          | Some key, Some offset => Some (Anchor key offset) | _, _ => None end
        | None => None end in
      match mode with
      | "follow" => Some (ReadingState FollowLatest anchor)
      | "history" => Some (ReadingState ReadHistory anchor)
      | _ => None end
  | None => None end.
Definition anchor_json (value : anchor) := JObject
  [("key", JString (anchor_key value)); ("offset", JString (offset value))].
Definition reading_json (state : Native.reading_state) := JObject
  [("intent", JString (match intent state with FollowLatest => "follow" | ReadHistory => "history" end));
   ("anchor", match bookmark state with Some value => anchor_json value | None => JNull end)].
Definition reading_effect_json (effect : reading_effect) :=
  match effect with
  | AlignLatest => JObject [("type", JString "align_latest")]
  | PreserveAnchor value => JObject [("type", JString "preserve_anchor"); ("anchor", anchor_json value)]
  | MeasureAnchor => JObject [("type", JString "measure_anchor")]
  | LocateMessage index => JObject [("type", JString "locate_message"); ("index", nat_json index)]
  end.
Definition reading_call (source : json) :=
  match field "state" source, string_field "event" source with
  | Some encoded, Some name => match reading_state encoded with
    | None => invalid "Reading state requires follow or history intent"
    | Some state =>
      let event := match name with
        | "scroll" => Some BeginScroll | "follow" => Some Follow | "layout" => Some LayoutChanged
        | "anchor" => match field "anchor" source with
            Some value => match string_field "key" value, string_field "offset" value with
              Some key, Some offset => Some (AtAnchor (Anchor key offset)) | _, _ => None end
            | None => None end
        | "locate" => option_map JumpToMessage (natural_field "index" source)
        | "key" => option_map (fun key => ReadingKey key (bool_value "editable" source))
            (string_field "keyboard" source)
        | _ => None end in
      match event with
      | Some event => let '(state, effects) := read_step event state in
          success (JObject [("state", reading_json state); ("effects", JArray (map reading_effect_json effects))])
      | None => invalid "Unknown reading event or invalid observation" end
    end
  | _, _ => invalid "Reading event requires state and event"
  end.

Definition call (operation : string) (source : json) : json :=
  match operation with
  | "render" => match field "scene" source, natural_field "viewport" source, natural_field "font_pixels" source with
      | Some scene, Some viewport, Some font => document viewport font (bool_value "system_dark" source) scene
      | _, _, _ => invalid "Browser render requires scene and native viewport/font pixel observations" end
  | "key" => native_key source
  | "key_action" => native_key_action source
  | "field_session" => FieldSession.field_session_call source
  | "layout" => layout source
  | "publication" => publication_call source
  | "snapshot" => snapshot_call source
  | "focus_cycle" => focus_call source
  | "resolve_target" => resolve_target_call source
  | "reading" => reading_call source
  | "code_initial" => CodeBlock.code_block_call "initial" source
  | "code_step" => CodeBlock.code_block_call "step" source
  | "code_key" => match string_field "key" source, binary_field "ordinal" source with
      | Some key, Some ordinal => success (JString (key ++ "/code/" ++ show_natural ordinal))
      | _, _ => invalid "Code identity requires source key and ordinal"
      end
  | _ => failure "RangeError" "Unknown browser operation"
  end.
