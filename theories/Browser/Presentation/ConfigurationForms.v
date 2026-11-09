From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers TextJson.
From Selvedge.Adapters Require Common Configuration.
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

Definition button parent key label enabled input : node Input.input :=
 ModelProfiles.profile_button parent key label enabled input.
Definition description parent key label : node Input.input := information parent key Information.Description label.
Definition group parent key label (body : list (node Input.input)) : node Input.input :=
 let id := part parent key in
 region parent key "" Roles.Section (group_title id label :: body).
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
Definition named_choice parent key selected (enabled : bool) action :=
 Node (part parent key) "collection-item" key Roles.Button
   (Choice SingleChoice selected ""
     (Control key key Secondary (Input.ServiceInput action)
       (if enabled then Available else Unavailable "Finish saving before changing selection")))
   [information (part parent key) "name" Information.OptionLabel key].

Definition indexed {A} (values : list A) := combine (seq 0 (List.length values)) values.
Definition index_label index := show_natural (N.of_nat (S index)).
Definition replace_at {A} index (value : A) values :=
 map (fun '(i, previous) => if Nat.eqb i index then value else previous) (indexed values).
Definition remove_at {A} index (values : list A) :=
 map snd (filter (fun entry => negb (Nat.eqb index (fst entry))) (indexed values)).

Definition value_list parent key label item empty values enabled parse commit :=
 let panel := part parent key in
 group parent key label
   (map (fun '(index, value) =>
     let row := part panel (index_label index) in
     region panel (index_label index) "" Roles.Section
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

Definition collection_spec path : option (string * json) :=
 match path with
 | ["reasoning_evaluators"] => Some ("evaluator", JObject [])
 | ["mcp"] => Some ("server", JObject [("command", JString "")])
 | ["plugins"] => Some ("plugin", JObject [("command", JString "")])
 | ["chatgpt_plugin"] => Some ("connection", JObject [("token_env", JString ""); ("project_ids", JArray [])])
 | _ => None
 end.

Definition collection_item_fields path parent source enabled commit : list (node Input.input) :=
 let text key label := optional_field parent key label source enabled empty_text commit in
 let number key label := optional_field parent key label source enabled optional_number commit in
 match path with
 | ["reasoning_evaluators"] =>
   let providers := map (fun provider =>
     let name := Selvedge.Adapters.Configuration.evaluator_name provider in Fields.ChoiceValue name name)
     Selvedge.Adapters.Configuration.evaluator_providers in
   [select_field parent "provider" "Provider"
      (match Common.get source "provider" with JString name => name | _ => "vercel" end)
      providers enabled (fun raw => commit (set_member "provider" (JString raw) source));
    text "model" "Model override"; text "endpoint" "Endpoint override";
    text "api_key_env" "API key environment variable"; number "timeout_ms" "Timeout (ms)";
    number "max_attempts" "Maximum attempts"]
 | ["chatgpt_plugin"] =>
   [text_field parent "token_env" "Token environment variable" source enabled commit;
    list_member parent "project_ids" "Allowed projects" "project ID" (JString "") source enabled
      (fun raw => value_or (JString raw) (Config.interpret_input Config.Number raw)) commit]
 | _ =>
   ([text_field parent "command" "Command" source enabled commit;
     text "cwd" "Working directory"; number "timeout_ms" "Timeout (ms)"]
    ++ (if list_eq_dec String.string_dec path ["plugins"] then
      [number "event_timeout_ms" "Event timeout (ms)"; number "event_queue" "Event queue size"] else [])
    ++ [list_member parent "args" "Arguments" "argument" (JString "") source enabled JString commit])%list
 end.

Definition collection_form path parent item seed view enabled : list (node Input.input) :=
 let layout := part parent "collection-layout" in
 let list_id := part layout "collection-nav" in
 let choices := part list_id "collection-choices" in
 let entries := Draft.collection_entries view in
 let selected := Draft.selected_item view in
 let editing := Draft.new_item_name view in
 let nav := region layout "collection-nav" "" Roles.Section
   ([Node choices "collection-choices" "Configured entries" Roles.Section ChoiceGroup
      (map (fun entry =>
        named_choice choices (fst entry)
          (match selected, editing with Some name, None => String.eqb name (fst entry) | _, _ => false end)
          enabled (Services.SelectConfigurationItem (fst entry))) entries)]
    ++ (match editing with Some _ => [] | None =>
       [button list_id "begin-add" ("Add " ++ item) enabled Services.BeginAddConfigurationItem] end))%list in
 let body :=
   match editing with
   | Some name =>
     let panel := part layout "collection-detail" in
     [region layout "collection-detail" "" Roles.Section
       [group_title panel ("New " ++ item);
        ModelProfiles.field panel "item-name" (item ++ " name") false name None enabled
          Services.EditConfigurationItemName;
        region panel "item-actions" "" Roles.DialogActions
          [button panel "cancel-add" "Cancel" enabled Services.CancelAddConfigurationItem;
           button panel "add" "Add" (enabled && Draft.can_add_item view)
             (Services.AddConfigurationItem seed)]]]
   | None =>
     match selected with
     | Some name =>
       match lookup name entries with
       | Some source =>
         let panel := part layout "collection-detail" in
         let members := match Draft.collection_root path with
           | Some (Some key) => [key; name] | _ => [name] end in
         let current := value_or (JObject []) (Draft.parsed_draft view) in
         let commit value := assign path
           (match members with
            | [key; name] => set_member key (set_member name value (Common.get current key)) current
            | _ => set_member name value current end) in
         [region layout "collection-detail" "" Roles.Section
           ([group_title panel name;
             region panel "form-fields" "" Roles.Section (collection_item_fields path (part panel "form-fields") source enabled commit);
             button panel "remove-item" ("Remove " ++ item) enabled (Services.RemoveConfigurationItem name)])]
       | None => []
       end
     | None => []
     end
   end in
 match entries, editing with
 | [], None =>
   [button parent "begin-add" ("Add " ++ item) enabled Services.BeginAddConfigurationItem]
 | [], Some _ => body
 | _, _ => [region parent "collection-layout" "" Roles.Section (nav :: body)]
 end.

Definition account_form parent saved source view enabled : list (node Input.input) :=
 let path := ["chatgpt"] in
 let active := match source with JBool false => false | _ => true end in
 let scope := part parent "account-access" in
 let choice key current value :=
   named_choice scope key current enabled (assign path value) in
 let allow := match saved with JObject _ => saved | _ => JObject [] end in
 let mode := Node scope "account-access" "ChatGPT model access" Roles.Section ChoiceGroup
   [choice "Allow account models" active (if active then source else allow);
    choice "Disable account models" (negb active) (JBool false)] in
 let details := Draft.overrides_open view in
 let edit key label parse := optional_field parent key label source enabled parse (assign path) in
 ([mode] ++ if active then
   [description parent "account-sign-in" "Sign in using the login command on the machine running Selvedge.";
    Node (part parent "connection-overrides") "connection-overrides" "Connection overrides" Roles.Button
      (PanelToggle details (Control "connection-overrides"
        (if details then "Hide connection overrides" else "Connection overrides") Secondary
        (Input.ServiceInput (Services.ShowConnectionOverrides (negb details)))
        (if enabled then Available else Unavailable "Finish saving first"))) []]
    ++ (if details then
      [description parent "override-hint" "Blank fields use the default connection settings.";
       region parent "form-fields" "" Roles.Section
         [edit "endpoint" "Responses endpoint" empty_text;
          edit "issuer" "Issuer" empty_text;
          edit "auth_file" "Credential file path" empty_text;
          edit "timeout_ms" "Timeout (ms)" optional_number]] else [])
   else match saved with
   | JObject (_ :: _) => [description parent "account-off" "Saving removes the current connection overrides and disables account model access."]
   | _ => [] end)%list.

Definition relay_form parent source enabled : list (node Input.input) :=
 [input parent "relay-url" "Relay URL" (Common.get source "relay_url") enabled
    (fun raw => assign ["remote"] (if String.eqb raw "" then JBool false else JObject [("relay_url", JString raw)]));
  description parent "relay-help"
    "Enter the relay's HTTPS origin. Leave blank to remove the relay. Pair controllers with the remote command after restarting the service."].

Definition cloud_form parent source enabled : list (node Input.input) :=
 let path := ["cloud"] in
 let backend := "tencent_cvm" in
 match source with
 | JObject _ =>
   let config := Common.get source backend in
   let commit value := assign path (set_member backend value source) in
   let section key label fields :=
     group parent key label [region (part parent key) "form-fields" "" Roles.Section
       (fields (part (part parent key) "form-fields"))] in
   let fields panel names :=
     map (fun '(key, label) => text_field panel key label config enabled commit) names in
   [section "cloud-compute" "Compute" (fun panel => fields panel
      [("region", "Region"); ("zone", "Zone"); ("image_id", "Image ID");
       ("instance_type", "Instance type"); ("spot_max_price", "Maximum spot price")]);
    section "cloud-network" "Network" (fun panel =>
      (fields panel [("vpc_id", "VPC ID"); ("subnet_id", "Subnet ID")]
      ++ [list_member panel "security_group_ids" "Security groups" "security group ID" (JString "") config enabled JString commit])%list);
    section "cloud-ssh" "SSH" (fun panel =>
      (fields panel [("key_id", "SSH key ID"); ("ssh_private_key", "Private key path")]
      ++ [optional_field panel "ssh_user" "SSH user" config enabled empty_text commit;
          optional_field panel "ssh_port" "SSH port" config enabled optional_number commit])%list);
    section "cloud-options" "Connection options" (fun panel =>
      [select_field panel "address_type" "Address type" (value_text (Common.get config "address_type"))
         [Fields.ChoiceValue "" "Default"; Fields.ChoiceValue "public" "Public"; Fields.ChoiceValue "private" "Private"]
         enabled (fun raw => commit (optional_member "address_type" (empty_text raw) config));
       optional_field panel "api_endpoint" "API endpoint override" config enabled empty_text commit;
       optional_field panel "internet_max_bandwidth_out" "Outbound bandwidth (Mbps)" config enabled optional_number commit;
       optional_field panel "startup_timeout_ms" "Startup timeout (ms)" config enabled optional_number commit]);
    button parent "remove-cloud" "Remove cloud configuration" enabled (assign path (JBool false))]
 | _ =>
   [description parent "cloud-empty" "Add Tencent Cloud compute, network and SSH settings to provision workspaces. Credentials are supplied by the local service environment.";
    button parent "configure-cloud" "Set up Tencent Cloud" enabled
      (assign path (JObject [("backend", JString backend); (backend, JObject [])]))]
 end.

Definition targets_form parent source enabled : list (node Input.input) :=
 let path := ["compaction"; "targets"] in
 let targets := Common.items source in
 (map (fun '(index, target) =>
   let key := ("target-" ++ index_label index)%string in
   let panel := part parent key in
   let fields := part panel "form-fields" in
   let commit value := assign path (JArray (replace_at index value targets)) in
   group parent key ("Target " ++ index_label index)
     [region panel "form-fields" "" Roles.Section
       [text_field fields "profile" "Profile name" target enabled commit;
        optional_field fields "window_tokens" "Context window (tokens)" target enabled optional_number commit;
        optional_field fields "output_reserve_tokens" "Output reserve (tokens)" target enabled optional_number commit;
        optional_field fields "cache_ttl_ms" "Cache lifetime (ms)" target enabled optional_number commit;
        select_field fields "method" "Method" (value_text (Common.get target "method"))
          [Fields.ChoiceValue "" "Default"; Fields.ChoiceValue "auto" "Automatic"; Fields.ChoiceValue "summary" "Summary"]
          enabled (fun raw => commit (optional_member "method" (empty_text raw) target))];
      button panel "remove-value" ("Remove target " ++ index_label index) enabled
        (assign path (JArray (remove_at index targets)))]) (indexed targets)
  ++ [button parent "add-value" "Add target" enabled
       (assign path (JArray (targets ++ [JObject [("profile", JString "")]])))])%list.

Definition structured_form path parent saved source view enabled : option (list (node Input.input)) :=
 match collection_spec path with
 | Some (name, seed) => Some (collection_form path parent name seed view enabled)
 | None =>
   match path with
   | ["chatgpt"] => Some (account_form parent saved source view enabled)
   | ["remote"] => Some (relay_form parent source enabled)
   | ["cloud"] => Some (cloud_form parent source enabled)
   | ["compaction"; "targets"] => Some (targets_form parent source enabled)
   | _ => match source with JArray values =>
       if forallb is_string values then Some
         [value_list parent "paths" "Files and directories" "path" (JString "") values enabled JString (assign path)]
       else None
     | _ => None end
   end
 end.
