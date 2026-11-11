From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers TextJson.
From Selvedge.Adapters Require CloudConfiguration Common Configuration ProviderCatalog.
From Selvedge.Browser Require Import NavigationIdentity.
From Selvedge.Browser.Scene Require Import Surface Model Construction.
From Selvedge.Browser.Session Require Import Input Services.
From Selvedge.Browser.Presentation Require Import Projection.
From Selvedge.Browser.Presentation Require Information Roles ModelProfiles.
From Selvedge.Interaction Require Import Codec.
From Selvedge.Interaction.Submission Require Fields.
Import ListNotations.
Open Scope string_scope.

Module Draft := Selvedge.Browser.Session.Configuration.
Module Config := Draft.Config.

Definition button parent key label (enabled : bool) input : node Input.input :=
 declared parent Roles.Button
   (Control key label Secondary (Input.ServiceInput input)
     (if enabled then Available else Unavailable "Finish the current edit first")).
Definition description parent key label : node Input.input := information parent key Information.Description label.
(* Field groups organize different parts of a form. A repeated value list
   keeps each value with the action that removes it, at any column count. *)
Definition group semantic parent key label (body : list (node Input.input)) : node Input.input :=
 let id := part parent key in
 Node id semantic "" Roles.Section Region
   (if String.eqb label "" then body else group_title id label :: body).
Definition field_row parent key (fields : string -> list (node Input.input)) : node Input.input :=
 Node (part parent key) "settings-field-row" "" Roles.Section Region (fields (part parent key)).
Definition assign path value := Services.EditConfigurationAt path (render_json value).
Definition value_text value := ModelProfiles.value_text value.
Definition set_member name value source :=
 JObject (Draft.put_member name value (Common.object_fields source)).
Definition optional_member name value source :=
 match value with JNull => JObject (remove_field name (Common.object_fields source))
 | _ => set_member name value source end.
Definition empty_text raw := if String.eqb raw "" then JNull else JString raw.
Definition optional_number raw :=
 if String.eqb raw "" then JNull
 else value_or (JString raw) (Config.interpret_input Config.Number raw).

Definition input parent key label value enabled (receive : string -> service_input) :=
 ModelProfiles.field parent key label false (value_text value) None enabled receive.
Definition text_field parent key label source enabled commit :=
 input parent key label (Common.get source key) enabled
   (fun raw => commit (set_member key (JString raw) source)).
Definition optional_field parent key label source enabled parse commit :=
 input parent key label (Common.get source key) enabled
   (fun raw => commit (optional_member key (parse raw) source)).
Definition select_field parent key label raw options enabled receive :=
 ModelProfiles.field parent key label false raw (Some options) enabled receive.
Definition indexed {A} (values : list A) := combine (seq 0 (List.length values)) values.
Definition index_label index := show_natural (N.of_nat (S index)).
Definition replace_at {A} index (value : A) values :=
 map (fun '(i, previous) => if Nat.eqb i index then value else previous) (indexed values).
Definition remove_at {A} index (values : list A) :=
 map snd (filter (fun entry => negb (Nat.eqb index (fst entry))) (indexed values)).

Definition value_list parent key label item empty values enabled parse commit :=
 let panel := part parent key in
 group "settings-value-list" parent key label
   (map (fun '(index, value) =>
     let row := part panel (index_label index) in
     Node row "settings-value-row" "" Roles.Section Region
       [input row "list-value" (item ++ " " ++ index_label index) value enabled
          (fun raw => commit (JArray (replace_at index (parse raw) values)));
        button row "remove-value" ("Remove " ++ item ++ " " ++ index_label index)
          enabled (commit (JArray (remove_at index values)))])
     (indexed values)
    ++ [button panel "add-value" ("Add " ++ item) enabled
         (commit (JArray (values ++ [empty])))])%list.

Definition list_member parent key label item empty source enabled parse commit :=
 value_list parent key label item empty (Common.items (Common.get source key)) enabled parse
   (fun value => commit (set_member key value source)).

(* Keep the first view focused on the task's inputs. Show optional settings
   by default when they contain saved values. An explicit choice wins. *)
Definition optional_details parent key label view source keys (enabled : bool)
  (fields : string -> list (node Input.input)) : list (node Input.input) :=
 let open := Draft.details_open view (existsb (fun key => negb (is_null (Common.get source key))) keys) in
 let scope := part parent key in
 Node scope "settings-form-disclosure" label Roles.Button
   (PanelToggle open (Control key label Secondary
     (Input.ServiceInput (Services.ShowConfigurationDetails (negb open)))
     (if enabled then Available else Unavailable "Finish saving first"))) []
 :: if open then [region scope "form-fields" "" Roles.Section (fields (part scope "form-fields"))] else [].

Definition profile_fields parent enabled profile view : list (node Input.input) :=
 let edit fields key label := ModelProfiles.field fields key label false
   (value_text (Common.get profile key)) None enabled (Services.EditModelProfileField key) in
 let details keys fields := optional_details parent "connection-overrides" "Connection overrides"
   view profile keys enabled fields in
 ([ModelProfiles.provider_choices parent enabled profile; edit parent "model" "Model"] ++
  match ProviderCatalog.backend profile with
  | Some (ProviderCatalog.EnvironmentSSE _ _ _) | Some (ProviderCatalog.WebConnection _ _) =>
    details ["endpoint"; "api_key_env"; "timeout_ms"] (fun fields =>
      [ModelProfiles.wide_field fields (edit fields "endpoint" "Endpoint");
       edit fields "api_key_env" "API key environment variable"; edit fields "timeout_ms" "Timeout (ms)"])
  | Some ProviderCatalog.AccountSSE =>
    details ["auth_file"; "issuer"; "timeout_ms"] (fun fields =>
      [ModelProfiles.wide_field fields (edit fields "auth_file" "Auth file");
       ModelProfiles.wide_field fields (edit fields "issuer" "Issuer"); edit fields "timeout_ms" "Timeout (ms)"])
  | _ => match Common.get profile "timeout_ms" with
         | JNull => [] | _ => [edit parent "timeout_ms" "Timeout (ms)"] end
  end)%list.

Definition collection_item path : option string :=
 match path with
 | ["profiles"] => Some "profile"
 | ["reasoning_evaluators"] => Some "evaluator"
 | ["mcp"] => Some "server"
 | ["plugins"] => Some "plugin"
 | ["chatgpt_plugin"] => Some "connection"
 | _ => None
 end.

Definition collection_item_fields path parent source view enabled commit : list (node Input.input) :=
 let text panel key label := optional_field panel key label source enabled empty_text commit in
 let number panel key label := optional_field panel key label source enabled optional_number commit in
 match path with
 | ["reasoning_evaluators"] =>
   let providers := map (fun provider =>
     let name := Selvedge.Adapters.Configuration.evaluator_name provider in Fields.ChoiceValue name name)
     Selvedge.Adapters.Configuration.evaluator_providers in
   ([field_row parent "evaluator-model" (fun row =>
      [select_field row "provider" "Provider"
         (match Common.get source "provider" with JString name => name | _ => "vercel" end)
         providers enabled (fun raw => commit (set_member "provider" (JString raw) source));
       text row "model" "Model override"])]
    ++ optional_details parent "evaluator-options" "Connection and retries" view source
      ["endpoint"; "api_key_env"; "timeout_ms"; "max_attempts"] enabled (fun fields =>
      [description fields "override-hint" "Blank fields use the provider defaults.";
       ModelProfiles.wide_field fields (text fields "endpoint" "Endpoint override");
       text fields "api_key_env" "API key environment variable";
       field_row fields "evaluator-retries" (fun row =>
         [number row "timeout_ms" "Timeout (ms)"; number row "max_attempts" "Maximum attempts"])]))%list
 | ["chatgpt_plugin"] =>
   [text_field parent "token_env" "Token environment variable" source enabled commit;
    list_member parent "project_ids" "Allowed projects" "project ID" (JString "") source enabled
      (fun raw => value_or (JString raw) (Config.interpret_input Config.Number raw)) commit]
 | _ =>
   let plugin_options := if list_eq_dec String.string_dec path ["plugins"] then
     [("event_timeout_ms", "Event timeout (ms)"); ("event_queue", "Event queue size")] else [] in
   let launch := part parent "settings-command-fields" in
   ([region parent "settings-command-fields" "" Roles.Section
      [text_field launch "command" "Command" source enabled commit;
       list_member launch "args" "" "argument" (JString "") source enabled JString commit]]
    ++ optional_details parent "execution-options" "Execution options" view source
      (["cwd"; "timeout_ms"] ++ map fst plugin_options)%list enabled (fun fields =>
        let pair := part fields "settings-execution-fields" in
        [region fields "settings-execution-fields" "" Roles.Section
          [ModelProfiles.wide_field pair (optional_field pair "cwd" "Working directory" source enabled empty_text commit);
           optional_field pair "timeout_ms" "Timeout (ms)" source enabled optional_number commit]]
        ++ map (fun '(key, label) => optional_field fields key label source enabled optional_number commit) plugin_options))%list
 end.

Definition new_item_field parent name enabled : node Input.input :=
 ModelProfiles.field parent "item-name" "Name" false name None enabled
   Services.EditConfigurationItemName.

Definition item_fields path parent source view enabled : node Input.input :=
 let fields := part parent "form-fields" in
 region parent "form-fields" "" Roles.Section
   (match path with
    | ["profiles"] => profile_fields fields enabled source view
    | _ => collection_item_fields path fields source view enabled Services.EditConfigurationItemValue
    end).
Definition account_form parent saved source view (enabled : bool) : list (node Input.input) :=
 let path := ["chatgpt"] in
 let active := match source with JBool false => false | _ => true end in
 let allow := match saved with JObject _ => saved | _ => JObject [] end in
 let scope := part parent "account-access" in
 let key := "setting-switch" in
 let label := "Allow account models" in
 let mode := Node scope "settings-account-access" "" Roles.Section Region
   [information scope "label" Information.FieldLabel label;
    Node (part scope key) key label Roles.Button
      (Choice ToggleChoice active ""
        (Control key label Secondary
          (Input.ServiceInput (assign path (if active then JBool false else allow)))
          (if enabled then Available else Unavailable "Finish saving first"))) []] in
 let edit fields key label parse := optional_field fields key label source enabled parse (assign path) in
 ([mode] ++ if active then
   optional_details parent "connection-overrides" "Connection overrides" view source
      ["endpoint"; "issuer"; "auth_file"; "timeout_ms"] enabled (fun fields =>
      [description fields "override-hint" "Blank fields use the default connection settings.";
       edit fields "endpoint" "Responses endpoint" empty_text;
       edit fields "issuer" "Issuer" empty_text;
       edit fields "auth_file" "Credential file path" empty_text;
       edit fields "timeout_ms" "Timeout (ms)" optional_number])
   else match saved with
   | JObject (_ :: _) => [description parent "account-off" "Saving removes the current connection overrides and disables account model access."]
   | _ => [] end)%list.

Definition relay_form parent source enabled : list (node Input.input) :=
 [input parent "relay-url" "Relay URL" (Common.get source "relay_url") enabled
    (fun raw => assign ["remote"] (if String.eqb raw "" then JBool false else JObject [("relay_url", JString raw)]));
  description parent "relay-help"
    "Enter the relay's HTTPS origin. Leave blank to remove the relay. Pair controllers with the remote command after restarting the service."].

Definition cloud_form parent saved source view enabled : list (node Input.input) :=
 let path := ["cloud"] in
 let backend := "tencent_cvm" in
 match saved, source with
 | JObject _, JBool false =>
   [description parent "cloud-removal" "Saving removes the Tencent Cloud workspace configuration."]
 | _, _ =>
   (* An empty form previews the fields without changing the draft. The
      first field edit supplies the backend alongside the edited value. *)
   let draft := match source with JObject _ => source | _ => JObject [("backend", JString backend)] end in
   let config := Common.get draft backend in
   let commit value := assign path (set_member backend value draft) in
   let label := CloudConfiguration.setting_label in
   let section key label fields :=
     group "settings-form-group" parent key label [region (part parent key) "form-fields" "" Roles.Section
       (fields (part (part parent key) "form-fields"))] in
   let fields panel names :=
     map (fun key => text_field panel key (label key) config enabled commit) names in
   ([description parent "cloud-credentials" "Tencent Cloud API credentials come from the local service environment.";
     section "cloud-compute" "Compute" (fun panel =>
       [field_row panel "placement" (fun row => fields row ["region"; "zone"]);
        field_row panel "instance" (fun row => fields row ["image_id"; "instance_type"]);
        text_field panel "spot_max_price" (label "spot_max_price") config enabled commit]);
    section "cloud-network" "Network" (fun panel =>
      [field_row panel "network-ids" (fun row => fields row ["vpc_id"; "subnet_id"]);
       list_member panel "security_group_ids" (label "security_group_ids") "security group ID" (JString "") config enabled JString commit]);
    section "cloud-ssh" "SSH" (fun panel =>
      [field_row panel "authentication" (fun row =>
        [text_field row "key_id" (label "key_id") config enabled commit;
         ModelProfiles.wide_field row (text_field row "ssh_private_key" (label "ssh_private_key") config enabled commit)])])]
    ++ optional_details parent "cloud-options" "Connection options" view config
       ["ssh_user"; "ssh_port"; "address_type"; "api_endpoint"; "internet_max_bandwidth_out"; "startup_timeout_ms"]
       enabled (fun panel =>
      [field_row panel "ssh-connection" (fun row =>
        [optional_field row "ssh_user" (label "ssh_user") config enabled empty_text commit;
         optional_field row "ssh_port" (label "ssh_port") config enabled optional_number commit]);
       select_field panel "address_type" (label "address_type") (value_text (Common.get config "address_type"))
         [Fields.ChoiceValue "" "Default"; Fields.ChoiceValue "public" "Public"; Fields.ChoiceValue "private" "Private"]
         enabled (fun raw => commit (optional_member "address_type" (empty_text raw) config));
       ModelProfiles.wide_field panel
         (optional_field panel "api_endpoint" (label "api_endpoint") config enabled empty_text commit);
       optional_field panel "internet_max_bandwidth_out" (label "internet_max_bandwidth_out") config enabled optional_number commit;
       optional_field panel "startup_timeout_ms" (label "startup_timeout_ms") config enabled optional_number commit])
    ++ match saved with
       | JObject _ => [button parent "remove-cloud" "Remove cloud configuration" enabled (assign path (JBool false))]
       | _ => [] end)%list
 end.

Definition targets_form parent source enabled : list (node Input.input) :=
 let path := ["compaction"; "targets"] in
 let targets := Common.items source in
 (map (fun '(index, target) =>
   let key := ("target-" ++ index_label index)%string in
   let panel := part parent key in
   let fields := part panel "form-fields" in
   let commit value := assign path (JArray (replace_at index value targets)) in
   group "settings-form-record" parent key ("Target " ++ index_label index)
     [region panel "form-fields" "" Roles.Section
       [text_field fields "profile" "Profile name" target enabled commit;
        field_row fields "token-budget" (fun row =>
          [optional_field row "window_tokens" "Context window (tokens)" target enabled optional_number commit;
           optional_field row "output_reserve_tokens" "Output reserve (tokens)" target enabled optional_number commit]);
        field_row fields "compaction-policy" (fun row =>
          [optional_field row "cache_ttl_ms" "Cache lifetime (ms)" target enabled optional_number commit;
           select_field row "method" "Method" (value_text (Common.get target "method"))
             [Fields.ChoiceValue "" "Default"; Fields.ChoiceValue "auto" "Automatic"; Fields.ChoiceValue "summary" "Summary"]
             enabled (fun raw => commit (optional_member "method" (empty_text raw) target))])];
      button panel "remove-value" ("Remove target " ++ index_label index) enabled
        (assign path (JArray (remove_at index targets)))]) (indexed targets)
  ++ [button parent "add-value" "Add target" enabled
       (assign path (JArray (targets ++ [JObject [("profile", JString "")]])))])%list.

Definition structured_form path parent saved source view enabled : list (node Input.input) :=
 match path with
 | ["chatgpt"] => account_form parent saved source view enabled
 | ["remote"] => relay_form parent source enabled
 | ["cloud"] => cloud_form parent saved source view enabled
 | ["compaction"; "targets"] => targets_form parent source enabled
 | _ => [value_list parent "paths" "Files and directories" "path" (JString "")
           (Common.items source) enabled JString (assign path)]
 end.
