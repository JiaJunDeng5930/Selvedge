From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json TextJson.
From Selvedge.Adapters Require Common ProviderCatalog.
From Selvedge.Programming Require DeclarationRegistry.
From Selvedge.Browser.Session Require Import Input Services.
From Selvedge.Browser.Scene Require Import Surface Model Construction.
From Selvedge.Browser.Presentation Require Roles.
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

Definition field parent key label multiline raw choices enabled
    (input : string -> Services.service_input) : node Input.input :=
 Node (part parent key) key label Roles.Field
   (ConfigurationField multiline raw choices enabled
     (fun value => option_map (fun text => Input.ServiceInput (input text)) (as_string value))) [].

(* Paths and addresses benefit from the whole form measure. Keep their
   span explicit in the form instead of selecting their keys in CSS. *)
Definition wide_field parent (value : node Input.input) : node Input.input :=
 Node (part parent ("wide-" ++ semantic_key value)) "settings-wide-field" "" Roles.Section Region [value].

Definition profile_fields parent enabled profile : list (node Input.input) :=
 let edit key label choices :=
   field parent key label false (value_text (Common.get profile key)) choices enabled
     (Services.EditModelProfileField key) in
 let backend := ProviderCatalog.backend profile in
 (* DEFENSE: Profiles are loaded as a raw object and can name a provider outside the registry. *)
 let choices := match backend with
   | Some _ => providers
   | None => Fields.ChoiceValue (value_text (Common.get profile "provider")) "Choose a provider" :: providers
   end in
 ([edit "provider" "Provider" (Some choices); edit "model" "Model" None]
 ++ (match backend with
     | Some (ProviderCatalog.EnvironmentSSE _ _ _) | Some (ProviderCatalog.WebConnection _ _) =>
       [wide_field parent (edit "endpoint" "Endpoint" None);
        edit "api_key_env" "API key environment variable" None;
        edit "timeout_ms" "Timeout (ms)" None]
     | Some ProviderCatalog.AccountSSE =>
       [wide_field parent (edit "auth_file" "Auth file" None);
        wide_field parent (edit "issuer" "Issuer" None); edit "timeout_ms" "Timeout (ms)" None]
     | _ => match Common.get profile "timeout_ms" with
            | JNull => [] | _ => [edit "timeout_ms" "Timeout (ms)" None] end
     end))%list.
