From Stdlib Require Import String List.
From Selvedge.Foundation Require Import Json Schema.
From Selvedge.Kernel Require Import ModelDeclarations.
From Selvedge.Features Require Import Domain.
From Selvedge.Host Require RemoteTransport RemoteConnectorSession.
Module RT := Selvedge.Host.RemoteTransport.
Module RC := Selvedge.Host.RemoteConnectorSession.
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
Inductive exception_kind := TypeErrorKind | RangeErrorKind.
Definition exception_value (kind : exception_kind) : denote (KEnum "TypeError" ["RangeError"]) :=
 match kind with
 | TypeErrorKind => exist _ "TypeError" (or_introl eq_refl)
 | RangeErrorKind => exist _ "RangeError" (or_intror (or_introl eq_refl)) end.
Inductive http_action := Http_observe_host | Http_parse_url | Http_observe_connection_authorization | Http_connection_method_origin | Http_observe_local_authorization | Http_local_origin | Http_asset | Http_audio_capabilities | Http_audio_transcribe | Http_audio_events | Http_audio_stop | Http_attachment_upload | Http_attachment_download | Http_browser_state | Http_describe | Http_remote_status | Http_remote_pending | Http_events | Http_event_page | Http_health | Http_account_refresh | Http_audio_create | Http_audio_login | Http_remote_pair | Http_remote_enable | Http_remote_disable | Http_remote_approve | Http_remote_revoke | Http_browser_command | Http_browser_observation | Http_command | Http_assess | Http_connection_command.
(** The wire name and body policy are one declaration, shared by routes and metadata. *)
Definition http_action_spec (value : http_action) := match value with
 | Http_observe_host => ("observe_host",false)
 | Http_parse_url => ("parse_url",false)
 | Http_observe_connection_authorization => ("observe_connection_authorization",false)
 | Http_connection_method_origin => ("connection_method_origin",false)
 | Http_observe_local_authorization => ("observe_local_authorization",false)
 | Http_local_origin => ("local_origin",false)
 | Http_asset => ("asset",false)
 | Http_audio_capabilities => ("audio_capabilities",false)
 | Http_audio_transcribe => ("audio_transcribe",false)
 | Http_audio_events => ("audio_events",false)
 | Http_audio_stop => ("audio_stop",false)
 | Http_attachment_upload => ("attachment_upload",false)
 | Http_attachment_download => ("attachment_download",false)
 | Http_browser_state => ("browser_state",false)
 | Http_describe => ("describe",false)
 | Http_remote_status => ("remote_status",false)
 | Http_remote_pending => ("remote_pending",false)
 | Http_events => ("events",false)
 | Http_event_page => ("event_page",false)
 | Http_health => ("health",false)
 | Http_account_refresh => ("account_refresh",true)
 | Http_audio_create => ("audio_create",true)
 | Http_audio_login => ("audio_login",true)
 | Http_remote_pair => ("remote_pair",true)
 | Http_remote_enable => ("remote_enable",true)
 | Http_remote_disable => ("remote_disable",true)
 | Http_remote_approve => ("remote_approve",true)
 | Http_remote_revoke => ("remote_revoke",true)
 | Http_browser_command => ("browser_command",true)
 | Http_browser_observation => ("browser_observation",true)
 | Http_command => ("command",true)
 | Http_assess => ("assess",true)
 | Http_connection_command => ("connection_command",true)
 end.
Definition all_http_actions := [Http_observe_host;Http_parse_url;Http_observe_connection_authorization;Http_connection_method_origin;Http_observe_local_authorization;Http_local_origin;Http_asset;Http_audio_capabilities;Http_audio_transcribe;Http_audio_events;Http_audio_stop;Http_attachment_upload;Http_attachment_download;Http_browser_state;Http_describe;Http_remote_status;Http_remote_pending;Http_events;Http_event_page;Http_health;Http_account_refresh;Http_audio_create;Http_audio_login;Http_remote_pair;Http_remote_enable;Http_remote_disable;Http_remote_approve;Http_remote_revoke;Http_browser_command;Http_browser_observation;Http_command;Http_assess;Http_connection_command].
Definition http_action_name value := fst (http_action_spec value).
Definition http_action_has_body value := snd (http_action_spec value).
Definition http_action_declaration value := variant "action" (http_action_name value)
 (if http_action_has_body value then [OmittableField "body" KJson] else []) [].
Definition http_body_actions := map http_action_declaration (filter http_action_has_body all_http_actions).
Definition body_actions := map name http_body_actions.
Definition http_observe_content_type := variant "action" "observe_content_type" [Field "target" (KEnum "account_refresh" (tl body_actions))] [].
Definition http_action_of_name value := find (fun action => String.eqb value (http_action_name action)) all_http_actions.
Definition http_plans := [http_respond;http_throw;http_observe_content_type] ++ map http_action_declaration all_http_actions.
Definition task := [OmittableField "task_id" KJson].
Definition browser_streams := variant "kind" "streams" [] [].
Definition browser_workspace_git := variant "kind" "workspace-git" (Field "primary" KText::task) [].
Definition browser_browse_directories := variant "kind" "browse-directories" ([Field "path" KJson;Field "default_path" KBool;Field "project_root" KJson]++task) [].
Definition browser_directories := variant "kind" "directories" (Field "workspace" KJson::task) [].
Definition browser_skill_catalog := variant "kind" "skill-catalog" (Field "workspace" KJson::task) [].
Definition browser_plans := [browser_streams;browser_workspace_git;browser_browse_directories;browser_directories;browser_skill_catalog].
Definition cloud_readiness_probe := variant "kind" "probe" [Field "timeout" KNatural] [].
Definition cloud_readiness_delay := variant "kind" "delay" [Field "milliseconds" KNatural] [].
Definition cloud_readiness_connected := variant "kind" "connected" [] [].
Definition cloud_readiness_reject := variant "kind" "reject" [Field "message" KText] [].
Definition cloud_readiness_actions := [cloud_readiness_probe;cloud_readiness_delay;cloud_readiness_connected;cloud_readiness_reject].
Definition cloud_readiness_transition := [Field "state" KJson;Field "actions" (KArray KJson)].
Definition dispatch_start := variant "kind" "start" [Field "generation" KNatural] [].
Definition dispatch_rollback_workspace := variant "kind" "rollback_workspace" [] [].
Definition dispatch_retain_workspace := variant "kind" "retain_workspace" [] [].
Definition dispatch_await := variant "kind" "await" [Field "generation" KNatural] [].
Definition dispatch_cancel := variant "kind" "cancel" [Field "generation" KNatural;Field "provider" KBool] [].
Definition dispatch_retry_failure := variant "kind" "retry_failure" [] [].
Definition dispatch_settled := variant "kind" "settled" [] [].
Definition dispatch_retire := variant "kind" "retire" [] [].
Definition dispatch_actions := [dispatch_start;dispatch_rollback_workspace;dispatch_retain_workspace;dispatch_await;dispatch_cancel;dispatch_retry_failure;dispatch_settled;dispatch_retire].
Definition audio_emit := variant "type" "emit" [Field "event" KJson] [].
Definition audio_journal := variant "type" "journal" [Field "token" KJson;Field "command" KJson] [].
Definition audio_context := variant "type" "context" [Field "context" KJson] [].
Definition audio_contexts := variant "type" "contexts" [Field "token" KJson;Field "contexts" (KArray KJson)] [].
Definition audio_read := variant "type" "read" [Field "token" KJson;Field "after" KNatural] [].
Definition audio_stop := variant "type" "stop" [] [].
Definition audio_release := variant "type" "release" [] [].
Definition audio_timer := variant "type" "timer" [] [].
Definition audio_connect_timer := variant "type" "connect_timer" [] [].
Definition audio_reject := variant "type" "reject" [Field "message" KText] [].
Definition audio_transport_connect := variant "type" "connect" [Field "attempt" KNatural] [].
Definition audio_transport_retry := variant "type" "retry" [Field "attempt" KNatural;Field "delay" KNatural] [].
Definition audio_transport_ready := variant "type" "ready" [] [].
Definition audio_transport_emit := variant "type" "emit" [Field "event" KJson] [].
Definition audio_transport_close := variant "type" "close" [Field "event" KJson] [].
Definition audio_transport_actions := [audio_transport_connect;audio_transport_retry;audio_transport_ready;audio_transport_emit;audio_transport_close].
Definition audio_actions := [audio_emit;audio_journal;audio_context;audio_contexts;audio_read;audio_stop;audio_release;audio_timer;audio_connect_timer;audio_reject].
(** Remote transport state and observations are closed over their phase. *)
Definition remote_generation := Field "generation" KNatural.
Definition remote_state tag fields := variant "phase" tag (remote_generation::fields)
 ("generation"::map field_name fields).
Definition remote_stopped := remote_state "stopped" [].
Definition remote_connecting := remote_state "connecting" [Field "attempt" KNatural].
Definition remote_negotiating := remote_state "negotiating" [Field "attempt" KNatural].
Definition remote_online := remote_state "online" [Field "last_pong" KNatural].
Definition remote_retrying := remote_state "retrying" [Field "attempt" KNatural;Field "deadline" KNatural].
Definition remote_auth_failed := remote_state "auth_failed" [].
Definition remote_state_decoders : list (ModelDeclarations.decoder RT.state) := [
 ModelDeclarations.Decoder remote_stopped (fun values => Some (RT.Stopped (head values)));
 ModelDeclarations.Decoder remote_connecting (fun values => Some (RT.Connecting (head values) (head (tail values))));
 ModelDeclarations.Decoder remote_negotiating (fun values => Some (RT.Negotiating (head values) (head (tail values))));
 ModelDeclarations.Decoder remote_online (fun values => Some (RT.Online (head values) (head (tail values))));
 ModelDeclarations.Decoder remote_retrying (fun values => Some (RT.Retrying (head values) (head (tail values)) (head (tail (tail values)))));
 ModelDeclarations.Decoder remote_auth_failed (fun values => Some (RT.AuthenticationFailed (head values)))].
Definition remote_transport_states := map ModelDeclarations.decoder_declaration remote_state_decoders.
Definition remote_action tag fields := variant "kind" tag fields (map field_name fields).
Definition remote_connect := remote_action "connect" [remote_generation].
Definition remote_open := remote_action "open" [remote_generation].
Definition remote_retry := remote_action "retry" [remote_generation;Field "deadline" KNatural].
Definition remote_heartbeat := remote_action "heartbeat" [remote_generation;Field "deadline" KNatural].
Definition remote_mark_online := remote_action "online" [remote_generation].
Definition remote_ping := remote_action "ping" [remote_generation].
Definition remote_retire := remote_action "retire" [].
Definition remote_mark_stopped := remote_action "stopped" [].
Definition remote_mark_auth_failed := remote_action "auth_failed" [].
Definition remote_transport_actions := [remote_connect;remote_open;remote_retry;remote_heartbeat;remote_mark_online;
 remote_ping;remote_retire;remote_mark_stopped;remote_mark_auth_failed].
Definition remote_observation tag fields := variant "kind" tag fields (map field_name fields).
Definition remote_timed := [remote_generation;Field "now" KNatural].
Definition remote_sampled := remote_timed ++ [Field "sample" KNatural].
Definition remote_observation_decoders : list (ModelDeclarations.decoder RT.observation) := [
 ModelDeclarations.Decoder (remote_observation "enable" []) (fun _ => Some RT.Enable);
 ModelDeclarations.Decoder (remote_observation "stop" []) (fun _ => Some RT.Stop);
 ModelDeclarations.Decoder (remote_observation "probe" (remote_sampled ++ [Field "status" KNatural]))
   (fun v => Some (RT.Probe (head v) (head (tail (tail (tail v)))) (head (tail v)) (head (tail (tail v)))));
 ModelDeclarations.Decoder (remote_observation "lost" remote_sampled)
   (fun v => Some (RT.Lost (head v) (head (tail v)) (head (tail (tail v)))));
 ModelDeclarations.Decoder (remote_observation "rejected" [remote_generation]) (fun v => Some (RT.Rejected (head v)));
 ModelDeclarations.Decoder (remote_observation "negotiated" remote_timed) (fun v => Some (RT.Negotiated (head v) (head (tail v))));
 ModelDeclarations.Decoder (remote_observation "pong" remote_timed) (fun v => Some (RT.Pong (head v) (head (tail v))));
 ModelDeclarations.Decoder (remote_observation "heartbeat" remote_sampled)
   (fun v => Some (RT.Heartbeat (head v) (head (tail v)) (head (tail (tail v)))));
 ModelDeclarations.Decoder (remote_observation "retry" remote_timed) (fun v => Some (RT.Retry (head v) (head (tail v))))].
Definition remote_transport_observations := map ModelDeclarations.decoder_declaration remote_observation_decoders.
Definition authorization_name state := match state with
 | RT.FirstCheck => "first" | RT.SecondCheck => "second" | RT.ThirdCheck => "third" | RT.LastCheck => "last"
 | RT.Authorized => "authorized" | RT.Denied => "denied" | RT.RevisionChanged => "revision_changed" end.
Definition remote_authorization_decoders := map (fun state =>
 ModelDeclarations.Decoder (variant "phase" (authorization_name state) [] []) (fun _ => Some state))
 [RT.FirstCheck;RT.SecondCheck;RT.ThirdCheck;RT.LastCheck;RT.Authorized;RT.Denied;RT.RevisionChanged].
Definition remote_authorization_states := map ModelDeclarations.decoder_declaration remote_authorization_decoders.
Definition grant_action_name action := match action with
 | RT.CheckAgain => "check" | RT.Capture => "capture" | RT.Deny => "deny" | RT.Disconnect => "disconnect" end.
Definition remote_authorization_actions := map (fun action => variant "kind" (grant_action_name action) [] [])
 [RT.CheckAgain;RT.Capture;RT.Deny;RT.Disconnect].
Definition remote_connector_actions := RC.action_kind.
Definition remote_connector_states := map ModelDeclarations.decoder_declaration RC.state_decoders.
Definition remote_connector_observations := map ModelDeclarations.decoder_declaration RC.event_decoders.
Definition unions := [("RemoteConnectorSessionState",remote_connector_states);("RemoteConnectorSessionObservation",remote_connector_observations);("CloudReadinessAction",cloud_readiness_actions);("RemoteTransportState",remote_transport_states);("RemoteTransportAction",remote_transport_actions);
 ("RemoteTransportObservation",remote_transport_observations);("RemoteAuthorizationState",remote_authorization_states);
 ("RemoteAuthorizationAction",remote_authorization_actions);("HttpPlan",http_plans);("BrowserObservationPlan",browser_plans);
 ("DispatchAction",dispatch_actions);("AudioAction",audio_actions);("AudioTransportAction",audio_transport_actions)].
Definition workspace_command_fields := [Field "root_task" KBool;Field "worktree" KBool;Field "selections" (KArray KJson)].
Definition workspace_selection_fields := [Field "value" KJson;Field "resolve_project" KBool].
Definition workspace_settings_fields := [Field "project_id" (KOptional KNatural);Field "observe_workspace" KBool].
Definition http_permissions_fields := Selvedge.Features.Domain.rights_fields.
Definition resource_action_name := KEnum "persist" ["allocate";"prepare";"credentials";"scan";"terminate";"finish";
 "local_reserve";"local_create";"local_prepare";"local_classify";"local_release";"local_remove";"local_archive";"local_observe";
 "local_sync_registration";"local_sync_ready";"local_sync_archive";"local_sync_release"].
Definition resource_transition_fields := [Field "state" KJson;Field "effects" (KArray resource_action_name)].
Definition records : list (string * schema) := [
 ("RemoteConnectorSessionTransition",[Field "state" KJson;Field "action" remote_connector_actions]);("CloudReadinessTransition",cloud_readiness_transition);
 ("ResourceTransition",resource_transition_fields);
 ("RemoteTransportTransition",[Field "state" KJson;Field "actions" (KArray KJson)]);
 ("RemoteAuthorizationTransition",[Field "state" KJson;Field "action" KJson]);
 ("WorkspaceCommandPlan",workspace_command_fields);
 ("WorkspaceSelectionPlan",workspace_selection_fields);
 ("WorkspaceSettingsPlan",workspace_settings_fields);
 ("BrowserPath",[Field "path" KJson;Field "canonicalize" KBool]);
 ("DispatchTransition",[Field "state" KJson;Field "effects" (KArray KJson)]);
 ("AudioTransportBegin",[Field "token" KNatural;Field "effect" KJson]);
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
