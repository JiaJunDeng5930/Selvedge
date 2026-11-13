From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json TextJson Utf8.
From Selvedge.Interaction Require Import Codec.
From Selvedge.Interaction Require ServiceConfiguration.
From Selvedge.Adapters Require Common ProviderCatalog.
From Selvedge.Adapters Require Configuration.
From Selvedge.Programming Require Import Resource.
Import ListNotations.
Open Scope string_scope.
Module Config := ServiceConfiguration.

Record draft := Draft { draft_path : list string; draft_input : string }.
Inductive form_mode := FormFields | NewItem (name : string) (value : json).
Record form_editor := FormEditor {
  preferred_item : option string;
  form_mode_current : form_mode;
  details_choice : option bool
}.

Record state := State {
  catalog : resource unit Config.snapshot;
  current_draft : option draft;
  writing : resource unit unit;
  form_editor_current : form_editor
}.

Definition initial_form_editor := FormEditor None FormFields None.
Definition initial := State Dormant None Dormant initial_form_editor.
Definition pending s := match writing s with Loading _ _ => true | _ => false end.
Definition reading s := match catalog s with Loading _ _ => true | _ => false end.
Definition available s := match catalog s with Loaded _ _ value => Some value | _ => None end.
Definition editing s :=
  current <- available s ;;
  draft <- current_draft s ;;
  entry <- Config.find_setting (draft_path draft) current ;;
  Some (current, draft, entry).

Definition matches_path path draft :=
  String.eqb (Config.setting_key path) (Config.setting_key (draft_path draft)).
Definition dirty s :=
  match editing s with
  | Some (_, draft, entry) => negb (String.eqb (draft_input draft) (Config.initial_input entry))
  | None => false
  end.
Definition new_item s :=
  match form_mode_current (form_editor_current s) with
  | NewItem name value => Some (name, value)
  | _ => None
  end.
Definition collection_seed path :=
  match path with
  | ["mcp"] | ["plugins"] => JObject [("command", JString "")]
  | ["chatgpt_plugin"] => JObject [("token_env", JString ""); ("project_ids", JArray [])]
  | _ => JObject []
  end.
Definition has_unsaved_work s :=
  dirty s ||
  match new_item s, current_draft s with
  | Some (name, value), Some draft =>
      negb (String.eqb name "" &&
        String.eqb (TextJson.render_json value) (TextJson.render_json (collection_seed (draft_path draft))))
  | _, _ => false
  end.
Definition can_select path s :=
  negb (pending s) &&
  match current_draft s with
  | Some draft => matches_path path draft || negb (has_unsaved_work s)
  | None => true
  end.
Definition select path s :=
  let already_selected := match current_draft s with
    | Some draft => matches_path path draft
    | None => false
    end in
  if already_selected || negb (can_select path s) then s else
  match bind (available s) (Config.find_setting path) with
  | Some entry => State (catalog s) (Some (Draft path (Config.initial_input entry))) Dormant
      initial_form_editor
  | None => s
  end.
Definition write_input raw s :=
  if pending s then s else
  match current_draft s with
  | Some draft => State (catalog s) (Some (Draft (draft_path draft) raw)) Dormant
      (form_editor_current s)
  | None => s
  end.
Definition edit_at path edit s :=
  let selected := select path s in
  match current_draft selected with
  | Some draft => if matches_path path draft then edit selected else s
  | None => s
  end.
Definition write_input_at path raw := edit_at path (write_input raw).
Definition cancel s :=
  if pending s then s else State (catalog s) None Dormant initial_form_editor.
Definition begin_read ticket := State (Loading ticket tt) None Dormant initial_form_editor.
Definition read_finished ticket outcome s :=
  State (settle ticket outcome (catalog s)) (current_draft s) (writing s) (form_editor_current s).
Definition begin_write ticket s :=
  State (catalog s) (current_draft s) (Loading ticket tt) (form_editor_current s).

(* Explicit form tasks finish when their write succeeds. Direct scalar
   edits keep their draft identity so the row can report the result. *)
Definition focused_editor (entry : Config.setting) : bool :=
  match Config.setting_input entry, Config.setting_path entry with
  | _, ["skills"] => false
  | Config.Structured, _ | _, ["instructions"] => true
  | _, _ => false
  end.

Definition write_finished ticket outcome s :=
  match writing s with
  | Loading current _ => if N.eqb current ticket then
      match outcome with
      | inl reason => State (catalog s) (current_draft s) (Failed ticket tt reason)
          (form_editor_current s)
      | inr snapshot =>
          let retained := draft <- current_draft s ;;
            entry <- Config.find_setting (draft_path draft) snapshot ;;
            if focused_editor entry then None
            else Some (Draft (draft_path draft) (Config.initial_input entry)) in
          State (Loaded ticket tt snapshot) retained (Loaded ticket tt tt) initial_form_editor
      end else s
  | _ => s
  end.

Definition collection_root path :=
  match path with
  | ["profiles"] | ["reasoning_evaluators"] | ["mcp"] | ["plugins"] => Some None
  | ["chatgpt_plugin"] => Some (Some "connections")
  | _ => None
  end.
Definition parsed_draft s :=
  draft <- current_draft s ;;
  TextJson.parse_json (draft_input draft).
Definition collection_object s :=
  draft <- current_draft s ;;
  wrapper <- collection_root (draft_path draft) ;;
  value <- parsed_draft s ;;
  match value, wrapper with
  | JNull, _ =>
      match draft_path draft with ["reasoning_evaluators"] | ["chatgpt_plugin"] => Some [] | _ => None end
  | JObject _, None => as_object value
  | JObject _, Some key =>
      match field key value with None => Some [] | Some entries => as_object entries end
  | _, _ => None
  end.
Definition collection_entries s := value_or [] (collection_object s).

Definition details_open s initial := value_or initial (details_choice (form_editor_current s)).
Definition with_form_editor editor s :=
  State (catalog s) (current_draft s) (writing s) editor.
Definition editable_collection s :=
  if pending s then None else collection_object s.
Definition update_collection change s :=
  match editable_collection s with
  | Some entries => change entries s
  | None => s
  end.

Definition select_item name :=
  update_collection (fun entries s =>
    match new_item s with
    | None => if existsb (fun entry => String.eqb name (fst entry)) entries then
        with_form_editor (FormEditor (Some name) FormFields None) s else s
    | Some _ => s
    end).
Definition begin_add_item :=
  update_collection (fun _ s =>
    match new_item s, current_draft s with
    | None, Some draft =>
        with_form_editor (FormEditor None (NewItem "" (collection_seed (draft_path draft))) None) s
    | _, _ => s
    end).
Definition change_new_item name value s :=
  State (catalog s) (current_draft s) Dormant
    (FormEditor None (NewItem name value) (details_choice (form_editor_current s))).
Definition edit_item_name name :=
  update_collection (fun _ s => match new_item s with
    | Some (_, value) => change_new_item name value s
    | None => s
    end).
Definition valid_item_name name (entries : list (string * json)) :=
  Utf8.nonblank name && negb (existsb (fun entry => String.eqb name (fst entry)) entries).
Definition collection_value entries s :=
  match bind (current_draft s) (fun draft => collection_root (draft_path draft)) with
  | Some None => Some (JObject entries)
  | Some (Some key) =>
      let current := value_or [] (bind (parsed_draft s) as_object) in
      Some (JObject (set_field key (JObject entries) current))
  | None => None
  end.
Definition write_collection entries s :=
  match collection_value entries s with
  | Some value => write_input (TextJson.render_json value) s
  | None => s
  end.
Definition valid_collection_item path value :=
  match path with
  | ["profiles"] =>
      let model :=
        fields <- as_object value ;;
        selected <- lookup "model" fields ;;
        as_string selected in
      match ProviderCatalog.backend value, model with
      | Some _, Some model => Utf8.nonblank model
      | _, _ => false
      end
  | _ => true
  end.
Definition new_collection_entries s :=
  item <- new_item s ;;
  draft <- current_draft s ;;
  entries <- editable_collection s ;;
  if valid_item_name (fst item) entries && valid_collection_item (draft_path draft) (snd item)
  then Some (entries ++ [item])%list else None.
Definition can_add_item s :=
  match new_collection_entries s with Some _ => true | None => false end.
Definition compaction_targets_admitted targets s :=
  current <- available s ;;
  policy <- Config.find_setting ["compaction"] current ;;
  profiles <- Config.find_setting ["profiles"] current ;;
  let proposed := Common.set (Config.setting_value policy) "targets" targets in
  Selvedge.Adapters.Configuration.admit_policy
    (JObject [("compaction", proposed)]) (Config.setting_value profiles).
Definition assignment entry draft s :=
  match new_item s with
  | Some _ => bind (new_collection_entries s) (fun entries => collection_value entries s)
  | None =>
    value <- Config.interpret_setting_input entry (draft_input draft) ;;
    match Config.setting_path entry with
    | ["compaction"; "targets"] =>
      option_map (fun _ => value) (compaction_targets_admitted value s)
    | ["skills"] =>
      if Selvedge.Adapters.Configuration.configured_paths_admitted value then Some value else None
    | _ => Some value
    end
  end.
Definition can_assign s :=
  match editing s with
  | Some (_, draft, entry) => match assignment entry draft s with Some _ => true | None => false end
  | None => false
  end.
Definition remove_item name :=
  update_collection (fun entries s =>
    match lookup name entries with
    | Some _ => write_collection (remove_field name entries) s
    | None => s
    end).

(* Keep existing positions so editing a field does not move the profile row. *)
Fixpoint put_member key (value : json) entries :=
  match entries with
  | [] => [(key, value)]
  | (name, previous) :: rest =>
      if String.eqb key name then (name, value) :: rest
      else (name, previous) :: put_member key value rest
  end.
Definition optional_profile_field field raw value entries :=
  if String.eqb raw "" then remove_field field entries else put_member field value entries.
Definition write_model_profile_field field raw entries :=
  match field with
  | "provider" | "model" => Some (put_member field (JString raw) entries)
  | "endpoint" | "api_key_env" | "auth_file" | "issuer" =>
      Some (optional_profile_field field raw (JString raw) entries)
  | "timeout_ms" =>
      (* Keep incomplete input editable and let service admission reject it on apply. *)
      let value := value_or (JString raw) (Config.interpret_input Config.Number raw) in
      Some (optional_profile_field field raw value entries)
  | _ => None
  end.
Definition edit_item_value (edit : json -> option json) :=
  update_collection (fun entries s =>
    match new_item s with
    | Some (name, source) =>
        match edit source with Some value => change_new_item name value s | None => s end
    | None =>
        let updated :=
          name <- preferred_item (form_editor_current s) ;;
          value <- bind (lookup name entries) edit ;;
          Some (put_member name value entries) in
        match updated with Some values => write_collection values s | None => s end
    end).
Definition replace_item_value value := edit_item_value (fun _ => Some value).
Definition edit_model_profile_field field raw :=
  edit_item_value (fun value =>
    profile <- as_object value ;;
    option_map JObject (write_model_profile_field field raw profile)).
Definition show_details (show : bool) s :=
  if pending s then s else
  match editing s with
  | Some (_, _, entry) => if focused_editor entry then
      let editor := form_editor_current s in
      with_form_editor (FormEditor (preferred_item editor) (form_mode_current editor) (Some show)) s
    else s
  | None => s
  end.
Definition encode_unit (_ : unit) := JNull.
Definition decode_unit j := match j with JNull => Some tt | _ => None end.
Definition encode_draft value := JObject
  [("path", Config.encode_path (draft_path value)); ("input", JString (draft_input value))].
Definition decode_draft j :=
  path <- list_field as_string "path" j ;;
  raw <- string_field "input" j ;;
  Some (Draft path raw).
Definition encode_optional_profile_text value :=
  match value with Some text => JString text | None => JNull end.
Definition decode_optional_profile_text j :=
  match j with JString text => Some (Some text) | JNull => Some None | _ => None end.
Definition encode_form_editor editor :=
  JObject
    [("selected", encode_optional_profile_text (preferred_item editor));
     ("details", match details_choice editor with Some show => JBool show | None => JNull end);
     ("mode", match form_mode_current editor with
      | FormFields => JObject [("kind", JString "fields")]
      | NewItem name value => JObject
          [("kind", JString "new_item"); ("name", JString name); ("value", value)]
      end)].
Definition decode_form_editor j :=
  selected <- bind (field "selected" j) decode_optional_profile_text ;;
  details <- bind (field "details" j) (fun value =>
    match value with JBool show => Some (Some show) | JNull => Some None | _ => None end) ;;
  mode <- field "mode" j ;;
  kind <- string_field "kind" mode ;;
  editor <- match kind with
    | "fields" => Some FormFields
    | "new_item" =>
        name <- string_field "name" mode ;;
        option_map (NewItem name) (field "value" mode)
    | _ => None
    end ;;
  Some (FormEditor selected editor details).
Definition encode s := JObject
  [("catalog", encode_resource encode_unit Config.encode_snapshot (catalog s));
   ("draft", match current_draft s with None => JNull | Some value => encode_draft value end);
   ("writing", encode_resource encode_unit encode_unit (writing s));
   ("form_editor", encode_form_editor (form_editor_current s))].
Definition decode j :=
  source <- bind (field "catalog" j) (decode_resource decode_unit Config.decode_snapshot) ;;
  draft <- bind (field "draft" j) (fun raw => match raw with
    | JNull => Some None | _ => option_map (@Some draft) (decode_draft raw)
    end) ;;
  write <- bind (field "writing" j) (decode_resource decode_unit decode_unit) ;;
  editor <- bind (field "form_editor" j) decode_form_editor ;;
  Some (State source draft write editor).
