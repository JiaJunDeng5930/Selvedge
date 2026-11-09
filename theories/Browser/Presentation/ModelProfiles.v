From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json TextJson.
From Selvedge.Adapters Require Common ProviderCatalog.
From Selvedge.Programming Require DeclarationRegistry.
From Selvedge.Browser.Session Require Import Input Services.
From Selvedge.Browser.Session Require Configuration.
From Selvedge.Browser.Scene Require Import Surface Model Construction.
From Selvedge.Browser.Presentation Require Information Roles.
From Selvedge.Interaction.Submission Require Fields.
Import ListNotations.
Open Scope string_scope.

Definition provider_label (provider : ProviderCatalog.provider) :=
 match provider with
 | ProviderCatalog.Offline => "Offline echo"
 | ProviderCatalog.EnvironmentSSE _ _ _ => "Responses API"
 | ProviderCatalog.AccountSSE => "ChatGPT"
 | ProviderCatalog.WebConnection _ _ => "ChatGPT Web"
 end.

Definition providers :=
 map (fun provider => Fields.ChoiceValue (ProviderCatalog.provider_name provider) (provider_label provider))
   (DeclarationRegistry.values ProviderCatalog.registered).

Definition value_text value :=
 match value with JNull => "" | JString text | JNumber text => text | _ => render_json value end.

Definition profile_button parent key label (enabled : bool) input : node Input.input :=
 declared parent Roles.Button
   (Control key label Secondary (Input.ServiceInput input)
     (if enabled then Available else Unavailable "Unavailable in the current state")).

Definition field parent key label multiline raw choices enabled
    (input : string -> Services.service_input) : node Input.input :=
 Node (part parent key) key label Roles.Field
   (ConfigurationField multiline raw choices enabled
     (fun value => option_map (fun text => Input.ServiceInput (input text)) (as_string value))) [].

Definition profile_choice parent selected (enabled : bool) (entry : string * json) : node Input.input :=
 let '(name, profile) := entry in
 let key := part parent name in
 let current := match selected with Some item => String.eqb item name | None => false end in
 let caption := match ProviderCatalog.backend profile with
   | Some provider => provider_label provider | None => "Choose a provider"
   end in
 Node key "model-profile-choice" name Roles.Button
   (Choice SingleChoice current ""
     (Control name name Secondary (Input.ServiceInput (Services.SelectModelProfile name))
       (if enabled then Available else Unavailable "Profile changes are being applied")))
   [information key "name" Information.OptionLabel name;
    information key "provider" Information.Description caption].

Definition profile_fields parent enabled name profile : list (node Input.input) :=
 let edit key label choices :=
   field parent key label false (value_text (Common.get profile key)) choices enabled
     (Services.EditModelProfileField name key) in
 let backend := ProviderCatalog.backend profile in
 (* DEFENSE: Advanced JSON can contain a provider outside the registry while the draft is unsaved. *)
 let choices := match backend with
   | Some _ => providers
   | None => Fields.ChoiceValue (value_text (Common.get profile "provider")) "Choose a provider" :: providers
   end in
 ([edit "provider" "Provider" (Some choices); edit "model" "Model" None]
 ++ (match backend with
     | Some (ProviderCatalog.EnvironmentSSE _ _ _) | Some (ProviderCatalog.WebConnection _ _) =>
       [edit "endpoint" "Endpoint" None; edit "api_key_env" "API key environment variable" None;
        edit "timeout_ms" "Timeout (ms)" None]
     | Some ProviderCatalog.AccountSSE =>
       [edit "auth_file" "Auth file" None; edit "issuer" "Issuer" None; edit "timeout_ms" "Timeout (ms)" None]
     | _ => match Common.get profile "timeout_ms" with
            | JNull => [] | _ => [edit "timeout_ms" "Timeout (ms)" None] end
     end))%list.

Definition profile_form parent view enabled (entries : list (string * json)) : list (node Input.input) :=
 match Configuration.profile_new_name view with
 | Some name =>
   let panel := part parent "new-profile" in
   [region parent "new-profile" "" Roles.Section
     [field panel "profile-name" "Profile name" false name None enabled Services.EditNewModelProfileName;
      region panel "model-profile-actions" "" Roles.Section
        [profile_button panel "cancel-add" "Cancel adding profile" enabled Services.CancelAddModelProfile;
         profile_button panel "add" "Add" (enabled && Configuration.can_add_model_profile view) Services.AddModelProfile]]]
 | None =>
   match Configuration.selected_profile view with
   | Some name =>
     match find (fun entry => String.eqb (fst entry) name) entries with
     | Some (_, profile) =>
       let panel := part parent ("profile/" ++ name) in
       [Node panel "model-profile-form" "" Roles.Section Region
         [region panel "model-profile-fields" "" Roles.Section
           (profile_fields (part panel "model-profile-fields") enabled name profile);
          profile_button panel "remove-profile" "Remove profile" enabled (Services.RemoveModelProfile name)]]
     | None => []
     end
   | None => []
   end
 end.

Definition editor parent view raw enabled : node Input.input :=
 let key := part parent "model-profile-editor" in
 let entries := Configuration.profile_entries view in
 let structured := Configuration.profile_form_available view in
 let advanced := Configuration.profile_json_mode view in
 let layout := part key "model-profile-layout" in
 let list_key := part layout "model-profile-list" in
 let choices := part list_key "model-profile-choices" in
 region parent "model-profile-editor" "" Roles.Section
  (if advanced then
    ([field key "profile-json" "Model profiles JSON" true raw None enabled
        (Services.EditConfigurationAt Configuration.profiles_path)]
     ++ (if structured then [] else
         [information key "profile-json-error" Information.Status "Enter a JSON object containing profile objects to return to the form."]))%list
   else
    [region key "model-profile-layout" "" Roles.Section
      ([region layout "model-profile-list" "" Roles.Section
        [Node choices "model-profile-choices" "Profiles" Roles.Section ChoiceGroup
           (map (profile_choice choices (Configuration.selected_profile view) enabled) entries);
         profile_button list_key "begin-add" "Add profile" enabled Services.BeginAddModelProfile]]
       ++ profile_form layout view enabled entries)%list]).

Definition mode_control parent view enabled :=
 if Configuration.profile_json_mode view then
   profile_button parent "back-to-profile-form" "Back to profile form"
     (enabled && Configuration.profile_form_available view) (Services.ShowModelProfilesJSON false)
 else profile_button parent "advanced-json" "Advanced JSON" enabled (Services.ShowModelProfilesJSON true).
