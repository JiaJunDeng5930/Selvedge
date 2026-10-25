From Stdlib Require Import String List.
From Selvedge.Foundation Require Import Json Schema.
From Selvedge.Kernel Require Import ModelDeclarations.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition variant (field name : string) (fields : schema) (safe : list string) :=
 ModelDeclarations.Variant field (JString name) fields safe None.
Definition name (declaration : ModelDeclarations.variant) :=
 match declaration.(ModelDeclarations.tag_value) with JString value => value | _ => "" end.
Definition tag (declaration : ModelDeclarations.variant) :=
 (declaration.(ModelDeclarations.tag_field),declaration.(ModelDeclarations.tag_value)).
Definition http_respond := variant "action" "respond" [Field "status" KNatural;Field "value" KJson] ["status"].
Definition http_throw := variant "action" "throw" [Field "kind" (KEnum "TypeError" ["RangeError"]);Field "message" KText] [].
Definition http_account_refresh := variant "action" "account_refresh" [OmittableField "body" KJson] [].
Definition http_audio_create := variant "action" "audio_create" [OmittableField "body" KJson] [].
Definition http_audio_login := variant "action" "audio_login" [OmittableField "body" KJson] [].
Definition http_remote_pair := variant "action" "remote_pair" [OmittableField "body" KJson] [].
Definition http_remote_enable := variant "action" "remote_enable" [OmittableField "body" KJson] [].
Definition http_remote_disable := variant "action" "remote_disable" [OmittableField "body" KJson] [].
Definition http_remote_approve := variant "action" "remote_approve" [OmittableField "body" KJson] [].
Definition http_remote_revoke := variant "action" "remote_revoke" [OmittableField "body" KJson] [].
Definition http_browser_command := variant "action" "browser_command" [OmittableField "body" KJson] [].
Definition http_browser_observation := variant "action" "browser_observation" [OmittableField "body" KJson] [].
Definition http_command := variant "action" "command" [OmittableField "body" KJson] [].
Definition http_assess := variant "action" "assess" [OmittableField "body" KJson] [].
Definition http_connection_command := variant "action" "connection_command" [OmittableField "body" KJson] [].
Definition http_body_actions := [http_account_refresh;http_audio_create;http_audio_login;http_remote_pair;http_remote_enable;http_remote_disable;http_remote_approve;http_remote_revoke;http_browser_command;http_browser_observation;http_command;http_assess;http_connection_command].
Definition body_actions := map name http_body_actions.
Inductive exception_kind := TypeErrorKind | RangeErrorKind.
Definition exception_value (kind : exception_kind) : denote (KEnum "TypeError" ["RangeError"]) :=
 match kind with
 | TypeErrorKind => exist _ "TypeError" (or_introl eq_refl)
 | RangeErrorKind => exist _ "RangeError" (or_intror (or_introl eq_refl)) end.
Definition http_observe_content_type := variant "action" "observe_content_type" [Field "target" (KEnum "account_refresh" (tl body_actions))] [].
Definition http_observe_host := variant "action" "observe_host" [] [].
Definition http_parse_url := variant "action" "parse_url" [] [].
Definition http_observe_connection_authorization := variant "action" "observe_connection_authorization" [] [].
Definition http_connection_method_origin := variant "action" "connection_method_origin" [] [].
Definition http_observe_local_authorization := variant "action" "observe_local_authorization" [] [].
Definition http_local_origin := variant "action" "local_origin" [] [].
Definition http_asset := variant "action" "asset" [] [].
Definition http_audio_capabilities := variant "action" "audio_capabilities" [] [].
Definition http_audio_transcribe := variant "action" "audio_transcribe" [] [].
Definition http_audio_events := variant "action" "audio_events" [] [].
Definition http_audio_stop := variant "action" "audio_stop" [] [].
Definition http_attachment_upload := variant "action" "attachment_upload" [] [].
Definition http_attachment_download := variant "action" "attachment_download" [] [].
Definition http_browser_state := variant "action" "browser_state" [] [].
Definition http_describe := variant "action" "describe" [] [].
Definition http_remote_status := variant "action" "remote_status" [] [].
Definition http_remote_pending := variant "action" "remote_pending" [] [].
Definition http_events := variant "action" "events" [] [].
Definition http_event_page := variant "action" "event_page" [] [].
Definition http_health := variant "action" "health" [] [].
Definition http_actions := [http_observe_host;http_parse_url;http_observe_connection_authorization;http_connection_method_origin;http_observe_local_authorization;http_local_origin;http_asset;http_audio_capabilities;http_audio_transcribe;http_audio_events;http_audio_stop;http_attachment_upload;http_attachment_download;http_browser_state;http_describe;http_remote_status;http_remote_pending;http_events;http_event_page;http_health].
Inductive http_action := Http_observe_host | Http_parse_url | Http_observe_connection_authorization | Http_connection_method_origin | Http_observe_local_authorization | Http_local_origin | Http_asset | Http_audio_capabilities | Http_audio_transcribe | Http_audio_events | Http_audio_stop | Http_attachment_upload | Http_attachment_download | Http_browser_state | Http_describe | Http_remote_status | Http_remote_pending | Http_events | Http_event_page | Http_health | Http_account_refresh | Http_audio_create | Http_audio_login | Http_remote_pair | Http_remote_enable | Http_remote_disable | Http_remote_approve | Http_remote_revoke | Http_browser_command | Http_browser_observation | Http_command | Http_assess | Http_connection_command.
Definition http_action_declaration (value : http_action) := match value with
 | Http_observe_host => http_observe_host
 | Http_parse_url => http_parse_url
 | Http_observe_connection_authorization => http_observe_connection_authorization
 | Http_connection_method_origin => http_connection_method_origin
 | Http_observe_local_authorization => http_observe_local_authorization
 | Http_local_origin => http_local_origin
 | Http_asset => http_asset
 | Http_audio_capabilities => http_audio_capabilities
 | Http_audio_transcribe => http_audio_transcribe
 | Http_audio_events => http_audio_events
 | Http_audio_stop => http_audio_stop
 | Http_attachment_upload => http_attachment_upload
 | Http_attachment_download => http_attachment_download
 | Http_browser_state => http_browser_state
 | Http_describe => http_describe
 | Http_remote_status => http_remote_status
 | Http_remote_pending => http_remote_pending
 | Http_events => http_events
 | Http_event_page => http_event_page
 | Http_health => http_health
 | Http_account_refresh => http_account_refresh
 | Http_audio_create => http_audio_create
 | Http_audio_login => http_audio_login
 | Http_remote_pair => http_remote_pair
 | Http_remote_enable => http_remote_enable
 | Http_remote_disable => http_remote_disable
 | Http_remote_approve => http_remote_approve
 | Http_remote_revoke => http_remote_revoke
 | Http_browser_command => http_browser_command
 | Http_browser_observation => http_browser_observation
 | Http_command => http_command
 | Http_assess => http_assess
 | Http_connection_command => http_connection_command
 end.
Definition all_http_actions := [Http_observe_host;Http_parse_url;Http_observe_connection_authorization;Http_connection_method_origin;Http_observe_local_authorization;Http_local_origin;Http_asset;Http_audio_capabilities;Http_audio_transcribe;Http_audio_events;Http_audio_stop;Http_attachment_upload;Http_attachment_download;Http_browser_state;Http_describe;Http_remote_status;Http_remote_pending;Http_events;Http_event_page;Http_health;Http_account_refresh;Http_audio_create;Http_audio_login;Http_remote_pair;Http_remote_enable;Http_remote_disable;Http_remote_approve;Http_remote_revoke;Http_browser_command;Http_browser_observation;Http_command;Http_assess;Http_connection_command].
Definition http_action_name value := name (http_action_declaration value).
Definition http_action_of_name value := find (fun action => String.eqb value (http_action_name action)) all_http_actions.
Definition http_plans := [http_respond;http_throw;http_observe_content_type] ++ map http_action_declaration all_http_actions.
Definition task := [OmittableField "task_id" KJson].
Definition browser_streams := variant "kind" "streams" [] [].
Definition browser_workspace_git := variant "kind" "workspace-git" (Field "primary" KText::task) [].
Definition browser_browse_directories := variant "kind" "browse-directories" ([Field "path" KJson;Field "default_path" KBool;Field "project_root" KJson]++task) [].
Definition browser_directories := variant "kind" "directories" (Field "workspace" KJson::task) [].
Definition browser_skill_catalog := variant "kind" "skill-catalog" (Field "workspace" KJson::task) [].
Definition browser_plans := [browser_streams;browser_workspace_git;browser_browse_directories;browser_directories;browser_skill_catalog].
Definition dispatch_start := variant "kind" "start" [Field "generation" KNatural] [].
Definition dispatch_cancel := variant "kind" "cancel" [Field "generation" KNatural;Field "provider" KBool] [].
Definition dispatch_retry_failure := variant "kind" "retry_failure" [] [].
Definition dispatch_settled := variant "kind" "settled" [] [].
Definition dispatch_retire := variant "kind" "retire" [] [].
Definition dispatch_actions := [dispatch_start;dispatch_cancel;dispatch_retry_failure;dispatch_settled;dispatch_retire].
Definition audio_emit := variant "type" "emit" [Field "event" KJson] [].
Definition audio_journal := variant "type" "journal" [Field "token" KJson;Field "command" KJson] [].
Definition audio_context := variant "type" "context" [Field "context" KJson] [].
Definition audio_read := variant "type" "read" [Field "after" KNatural] [].
Definition audio_stop := variant "type" "stop" [] [].
Definition audio_release := variant "type" "release" [] [].
Definition audio_timer := variant "type" "timer" [] [].
Definition audio_connect_timer := variant "type" "connect_timer" [] [].
Definition audio_reject := variant "type" "reject" [Field "message" KText] [].
Definition audio_actions := [audio_emit;audio_journal;audio_context;audio_read;audio_stop;audio_release;audio_timer;audio_connect_timer;audio_reject].
Definition unions := [("HttpPlan",http_plans);("BrowserObservationPlan",browser_plans);
 ("DispatchAction",dispatch_actions);("AudioAction",audio_actions)].
Definition workspace_command_fields := [Field "root_task" KBool;Field "worktree" KBool;Field "selections" (KArray KJson)].
Definition workspace_selection_fields := [Field "value" KJson;Field "resolve_project" KBool].
Definition workspace_settings_fields := [Field "project_id" (KOptional KNatural);Field "observe_workspace" KBool].
Definition http_permissions_fields := [Field "read" KBool;Field "control" KBool;Field "configure" KBool;Field "approve" KBool].
Definition records : list (string * schema) := [
 ("WorkspaceCommandPlan",workspace_command_fields);
 ("WorkspaceSelectionPlan",workspace_selection_fields);
 ("WorkspaceSettingsPlan",workspace_settings_fields);
 ("BrowserPath",[Field "path" KJson;Field "canonicalize" KBool]);
 ("DispatchTransition",[Field "state" KJson;Field "effects" (KArray KJson)]);
 ("AudioTransition",[Field "state" KJson;Field "actions" (KArray KJson)]);
 ("HttpRemoteApprovalBody",[Field "request_id" KText;Field "permissions" KJson]);
 ("HttpRemotePermissions",http_permissions_fields);
 ("HttpRemoteRevokeBody",[Field "controller_id" KText]);
 ("HttpBrowserCommandBody",[Field "command" KJson])].
Definition schema_json := JObject [
 ("leaves",JArray [JObject [("name",JString "HttpReplyStatus");("type",ModelDeclarations.kind_json KNatural);("safe",JBool true)]]);
 ("unions",JArray (map (fun entry => JObject [("name",JString (fst entry));
 ("variants",JArray (map ModelDeclarations.variant_json (snd entry)))]) unions));
 ("records",JArray (map (fun entry => JObject [("name",JString (fst entry));
 ("fields",ModelDeclarations.fields_json (snd entry))]) records))].
