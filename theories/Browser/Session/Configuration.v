From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json TextJson Utf8.
From Selvedge.Adapters Require ProviderCatalog.
From Selvedge.Interaction Require Import Codec.
From Selvedge.Interaction Require ServiceConfiguration.
From Selvedge.Programming Require Import Resource.
Import ListNotations.
Open Scope string_scope.
Module Config := ServiceConfiguration.

Record draft := Draft { draft_path : list string; draft_input : string }.
Inductive profile_mode := ProfileFields (new_name : option string) | ProfileJSON.
Record profile_editor := ProfileEditor {
  preferred_profile : option string;
  profile_mode_current : profile_mode
}.

Record state := State {
  catalog : resource unit Config.snapshot;
  current_draft : option draft;
  writing : resource unit unit;
  profile_editor_current : profile_editor
}.

Definition initial_profile_editor := ProfileEditor None (ProfileFields None).
Definition initial := State Dormant None Dormant initial_profile_editor.
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
Definition can_select path s :=
  negb (pending s) &&
  match current_draft s with
  | Some draft => matches_path path draft || negb (dirty s)
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
      initial_profile_editor
  | None => s
  end.
Definition write_input raw s :=
  if pending s then s else
  match current_draft s with
  | Some draft => State (catalog s) (Some (Draft (draft_path draft) raw)) Dormant
      (profile_editor_current s)
  | None => s
  end.
Definition write_input_at path raw s :=
  let selected := select path s in
  match current_draft selected with
  | Some draft => if matches_path path draft then write_input raw selected else s
  | None => s
  end.
Definition cancel s :=
  if pending s then s else State (catalog s) None Dormant initial_profile_editor.
Definition begin_read ticket := State (Loading ticket tt) None Dormant initial_profile_editor.
Definition read_finished ticket outcome s :=
  State (settle ticket outcome (catalog s)) (current_draft s) (writing s) (profile_editor_current s).
Definition begin_write ticket s :=
  State (catalog s) (current_draft s) (Loading ticket tt) (profile_editor_current s).
Definition write_finished ticket outcome s :=
  match writing s with
  | Loading current _ => if N.eqb current ticket then
      match outcome with
      | inl reason => State (catalog s) (current_draft s) (Failed ticket tt reason)
          (profile_editor_current s)
      | inr snapshot =>
          let retained := bind (current_draft s) (fun draft =>
            option_map (fun entry => Draft (draft_path draft) (Config.initial_input entry))
              (Config.find_setting (draft_path draft) snapshot)) in
          State (Loaded ticket tt snapshot) retained (Loaded ticket tt tt) (profile_editor_current s)
      end else s
  | _ => s
  end.

Definition profiles_path := ["profiles"].
Definition profiles_draft s :=
  current <- editing s ;;
  let '(_, draft, _) := current in
  if matches_path profiles_path draft then Some draft else None.
Definition profile_object s :=
  draft <- profiles_draft s ;;
  value <- TextJson.parse_json (draft_input draft) ;;
  as_object value.
Definition profile_entries s := value_or [] (profile_object s).

Definition profile_form_available s :=
  match profile_object s with
  | Some entries => forallb (fun entry => is_object (snd entry)) entries
  | None => false
  end.
Definition selected_profile s :=
  let entries := profile_entries s in
  let first := option_map fst (hd_error entries) in
  match preferred_profile (profile_editor_current s) with
  | Some name => if existsb (fun entry => String.eqb name (fst entry)) entries
      then Some name else first
  | None => first
  end.
Definition profile_json_mode s :=
  match profile_mode_current (profile_editor_current s) with
  | ProfileJSON => true
  | ProfileFields _ => false
  end.
Definition profile_new_name s :=
  match profile_mode_current (profile_editor_current s) with
  | ProfileFields name => name
  | ProfileJSON => None
  end.
Definition with_profile_editor editor s :=
  State (catalog s) (current_draft s) (writing s) editor.
Definition with_profile_mode mode s :=
  with_profile_editor (ProfileEditor (preferred_profile (profile_editor_current s)) mode) s.
Definition editable_profiles s :=
  if pending s || profile_json_mode s then None else profile_object s.
Definition update_profile_editor change s :=
  match editable_profiles s with
  | Some entries => change entries s
  | None => s
  end.

Definition select_model_profile name :=
  update_profile_editor (fun entries s =>
    if existsb (fun entry => String.eqb name (fst entry)) entries then
      with_profile_editor (ProfileEditor (Some name) (profile_mode_current (profile_editor_current s))) s
    else s).
Definition begin_add_model_profile :=
  update_profile_editor (fun _ s => with_profile_mode (ProfileFields (Some "")) s).
Definition edit_new_model_profile_name name :=
  update_profile_editor (fun _ s => match profile_new_name s with
    | Some _ => with_profile_mode (ProfileFields (Some name)) s
    | None => s
    end).
Definition cancel_add_model_profile :=
  update_profile_editor (fun _ s => with_profile_mode (ProfileFields None) s).
Definition valid_new_profile_name name (entries : list (string * json)) :=
  Utf8.nonblank name && negb (existsb (fun entry => String.eqb name (fst entry)) entries).
Definition can_add_model_profile s :=
  match profile_new_name s, editable_profiles s with
  | Some name, Some entries => valid_new_profile_name name entries
  | _, _ => false
  end.
Definition write_profiles entries s := write_input (TextJson.render_json (JObject entries)) s.
Definition add_model_profile :=
  update_profile_editor (fun entries s =>
    match profile_new_name s with
    | Some name => if valid_new_profile_name name entries then
        let offline := ProviderCatalog.provider_name ProviderCatalog.Offline in
        let profile := JObject [("provider", JString offline); ("model", JString "echo")] in
        with_profile_editor (ProfileEditor (Some name) (ProfileFields None))
          (write_profiles (entries ++ [(name, profile)])%list s)
      else s
    | None => s
    end).
Definition remove_model_profile name :=
  update_profile_editor (fun entries s =>
    match lookup name entries with
    | Some _ =>
        let kept := match preferred_profile (profile_editor_current s) with
          | Some selected => if String.eqb name selected then None else Some selected
          | None => None
          end in
        with_profile_editor (ProfileEditor kept (profile_mode_current (profile_editor_current s)))
          (write_profiles (remove_field name entries) s)
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
Definition edit_model_profile_field name field raw :=
  update_profile_editor (fun entries s =>
    let updated :=
      profile <- bind (lookup name entries) as_object ;;
      updated <- write_model_profile_field field raw profile ;;
      Some (put_member name (JObject updated) entries) in
    match updated with Some entries => write_profiles entries s | None => s end).
Definition show_model_profiles_json (show : bool) s :=
  if pending s then s else
  match profiles_draft s with
  | Some _ =>
      if show then with_profile_mode ProfileJSON s
      else if profile_json_mode s && profile_form_available s then
        with_profile_mode (ProfileFields None) s
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
Definition encode_profile_editor editor :=
  JObject
    [("selected", encode_optional_profile_text (preferred_profile editor));
     ("mode", match profile_mode_current editor with
      | ProfileJSON => JObject [("kind", JString "json")]
      | ProfileFields name => JObject
          [("kind", JString "fields"); ("new_name", encode_optional_profile_text name)]
      end)].
Definition decode_profile_editor j :=
  selected <- bind (field "selected" j) decode_optional_profile_text ;;
  mode <- field "mode" j ;;
  kind <- string_field "kind" mode ;;
  editor <- match kind with
    | "json" => Some ProfileJSON
    | "fields" => option_map ProfileFields (bind (field "new_name" mode) decode_optional_profile_text)
    | _ => None
    end ;;
  Some (ProfileEditor selected editor).
Definition encode s := JObject
  [("catalog", encode_resource encode_unit Config.encode_snapshot (catalog s));
   ("draft", match current_draft s with None => JNull | Some value => encode_draft value end);
   ("writing", encode_resource encode_unit encode_unit (writing s));
   ("profile_editor", encode_profile_editor (profile_editor_current s))].
Definition decode j :=
  source <- bind (field "catalog" j) (decode_resource decode_unit Config.decode_snapshot) ;;
  draft <- bind (field "draft" j) (fun raw => match raw with
    | JNull => Some None | _ => option_map (@Some draft) (decode_draft raw)
    end) ;;
  write <- bind (field "writing" j) (decode_resource decode_unit decode_unit) ;;
  editor <- bind (field "profile_editor" j) decode_profile_editor ;;
  Some (State source draft write editor).
