From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json TextJson.
From Selvedge.Adapters Require Common ProviderCatalog.
From Selvedge.Programming Require DeclarationRegistry.
From Selvedge.Browser.Session Require Import Input Services.
From Selvedge.Browser.Scene Require Import Surface Model Construction.
From Selvedge.Browser.Presentation Require Roles.
Import ListNotations.
Open Scope string_scope.

Definition provider_label (provider : ProviderCatalog.provider) :=
 match provider with
 | ProviderCatalog.Offline => "Offline echo"
 | ProviderCatalog.EnvironmentSSE _ _ _ => "Responses API"
 | ProviderCatalog.AccountSSE => "ChatGPT"
 | ProviderCatalog.WebConnection _ _ => "ChatGPT Web"
 end.

Definition value_text value :=
 match value with JNull => "" | JString text | JNumber text => text | _ => render_json value end.

Definition field parent key label multiline raw choices enabled
    (input : string -> Services.service_input) : node Input.input :=
 Node (part parent key) key label Roles.Field
   (ConfigurationField multiline raw choices enabled
     (fun value => option_map (fun text => Input.ServiceInput (input text)) (as_string value))) [].

(* Paths and addresses benefit from the whole form measure. Keep their
   span explicit in the form instead of selecting their keys in CSS. *)
Definition wide_field parent (value : node Input.input) : node Input.input :=
 Node (part parent ("wide-" ++ semantic_key value)) "settings-wide-field" "" Roles.Section Region [value].

(* A provider selects which inputs the rest of the profile needs. Keep the
   alternatives visible before those inputs, in registry order. *)
Definition provider_choices parent (enabled : bool) profile : node Input.input :=
 let id := part parent "provider" in
 let group := part id "options" in
 let current := value_text (Common.get profile "provider") in
 let providers := filter (fun provider => match provider with
   | ProviderCatalog.Offline => String.eqb current (ProviderCatalog.provider_name ProviderCatalog.Offline)
   | _ => true
   end) (DeclarationRegistry.values ProviderCatalog.registered) in
 let choice provider :=
   let key := ProviderCatalog.provider_name provider in
   let label := provider_label provider in
   Node (part group key) "settings-provider-option" label Roles.Button
     (Choice SingleChoice (String.eqb key current) ""
       (Control key label Secondary (Input.ServiceInput (Services.EditModelProfileField "provider" key))
         (if enabled then Available else Unavailable "Finish saving first"))) [] in
 (* DEFENSE: The configuration can contain a provider outside the registry.
    Keep it in the draft until the user chooses a replacement. *)
 let unregistered := match ProviderCatalog.backend profile with
   | None => if String.eqb current "" then [] else
       [information id "unregistered-provider" Information.Description ("Current provider: " ++ current)]
   | Some _ => []
   end in
 Node id "settings-provider" "" Roles.Section Region
   ([information id "provider-label" Information.FieldLabel "Provider"] ++ unregistered ++
    [Node group "settings-provider-options" "Provider" Roles.Section ChoiceGroup
      (map choice providers)])%list.
