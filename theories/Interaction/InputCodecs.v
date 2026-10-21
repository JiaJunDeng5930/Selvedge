From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema.
From Selvedge.Interaction Require Import Codec Identity Services Speech ApplicationState Input SkillMention Activities.
From Selvedge.Interaction Require CommandAssessment.
Import ListNotations.
Open Scope string_scope.
Definition record_input kind props:=JObject(("type",JString kind)::props).
Definition ticket_input kind t:=record_input kind[("ticket",number t)].
Definition encode_outcome {A} (encode:A->json) (outcome:sum string A):=match outcome with inl error=>[("ok",JBool false);("error",JString error)]|inr value=>[("ok",JBool true);("value",encode value)]end.
Definition encode_service_input input:=match input with
|CommandAssessed t outcome=>record_input "command_assessed"(("ticket",number t)::encode_outcome CommandAssessment.encode_observation outcome)
|RetryAssessment e=>record_input "retry_assessment"[("editor",encode_editor e)]
|WorkspaceGitCompleted t outcome=>record_input "workspace_git_completed"(("ticket",number t)::encode_outcome JBool outcome)
|RestoreModelPreference raw=>record_input "model_preference_restored"[("value",JString raw)]
|StorageProblem message=>record_input "storage_problem"[("message",JString message)]
|DismissStorageProblem=>record_input "dismiss_storage_problem"[]
|OpenSettings=>record_input "open_settings"[]|CloseSettings=>record_input "close_settings"[]|Connect=>record_input "connect"[]
|Authenticated t r=>record_input "authenticated"(("ticket",number t)::encode_outcome encode_unit r)
|Disconnected t error revoked=>record_input "disconnected"[("ticket",number t);("error",JString error);("revoked",JBool revoked)]
|RetryConnection t=>ticket_input "retry_connection" t
|ChooseAppearance a=>record_input "appearance"[("value",JString(appearance_name a))]
|AddFile e f=>record_input "add_file"[("editor",encode_editor e);("file",encode_file f)]
|RetryUpload t=>ticket_input "retry_upload" t|CancelUpload t=>ticket_input "cancel_upload" t
|Uploaded t r=>record_input "uploaded"(("ticket",number t)::encode_outcome encode_attachment r)
|OpenPreview a trigger=>record_input "open_preview"[("file",encode_attachment a);("trigger",JString trigger)]
|Previewed t r=>record_input "previewed"(("ticket",number t)::encode_outcome JString r)
|ClosePreview=>record_input "close_preview"[]|Download a=>record_input "download"[("file",encode_attachment a)]
|OpenDirectory e path trigger=>record_input "open_directory"[("editor",encode_editor e);("path",JString path);("trigger",JString trigger)]
|WriteDirectoryLocation value=>record_input "write_directory"[("value",JString value)]
|VisitDirectory path=>record_input "visit_directory"[("path",JString path)]|GoDirectory=>record_input "go_directory"[]
|DirectoryListed t r=>record_input "directory_listed"(("ticket",number t)::encode_outcome(fun j=>j)r)
|ChooseDirectory=>record_input "choose_directory"[]|CloseDirectory=>record_input "close_directory"[]end.
Definition encode_speech_input input:=match input with
|Authorize=>record_input "audio_authorize"[]|Refresh=>record_input "audio_refresh"[]
|Capabilities cs=>record_input "audio_capabilities"[("connections",JArray(map encode_connection cs))]
|CapabilitiesFailed error=>record_input "audio_capabilities_failed"[("error",JString error)]
|Select id=>record_input "audio_select"[("value",JString id)]
|BeginDictation e rev=>record_input "dictate"[("editor",encode_editor e);("revision",number rev)]
|Captured t start finish=>record_input "audio_captured"[("ticket",number t);("start",number start);("end",number finish)]
|FinishDictation=>record_input "finish_dictation"[]|Transcribed t text=>record_input "audio_transcribed"[("ticket",number t);("text",JString text)]
|InsertTranscript=>record_input "insert_transcript"[]|DismissTranscript=>record_input "dismiss_transcript"[]
|BeginVoice t=>record_input "begin_voice"[("task_id",number t)]|BeginNewVoice e r g c=>record_input "begin_new_voice"[("editor",encode_editor e);("revision",number r);("generation",number g);("command",encode_command c)]
|TaskCreated t task=>record_input "voice_task_created"[("ticket",number t);("task_id",number task)]
|VoiceReady t=>ticket_input "voice_ready" t|LiveText t text=>record_input "voice_text"[("ticket",number t);("text",JString text)]
|ToggleInputMute=>record_input "voice_input_mute"[]|ToggleOutputMute=>record_input "voice_output_mute"[]|Cancel=>record_input "audio_cancel"[]
|Failed t error=>record_input "audio_failed"[("ticket",number t);("error",JString error)]
|Ended t error=>record_input "audio_ended"[("ticket",number t);("error",JString error)]|Released=>record_input "audio_released"[]end.
Definition encode_input i:=match i with
|ResetTitlePrompts=>record_input "reset_title_prompts"[]
|ToggleProjectGroup id=>record_input "toggle_project_group"[("project_id",number id)]
|BeginProjectTask id=>record_input "begin_project_task"[("project_id",number id)]
|BeginVoiceNew e=>record_input "begin_voice_new"[("editor",encode_editor e)]
|SelectSharedTask work task=>record_input "select_shared_task"[("work_id",number work);("value",optional_id task)]
|Navigate r=>record_input "navigate"[("route",encode_route r)]|SelectWork w=>record_input "select_work"[("work",optional_id w)]|CreateWork=>record_input "create_work"[]
|MenuAction subject key occurrence=>record_input "menu_action"[("subject",encode_menu_subject subject);("key",JString key);("occurrence",number occurrence)]
|RetryMenuAssessment subject key occurrence=>record_input "retry_menu_assessment"[("subject",encode_menu_subject subject);("key",JString key);("occurrence",number occurrence)]
|OpenObjectActions subject trigger=>record_input "open_object_actions"[("subject",encode_menu_subject subject);("trigger",JString trigger)]
|OpenNavigation kind trigger=>record_input "open_navigation"[("navigation",JString(navigation_panel_name kind));("trigger",JString trigger)]
|RepairSubject e revision name trigger=>record_input "repair_subject"[("editor",encode_editor e);("revision",number revision);("field",JString name);("trigger",JString trigger)]
|OpenActivity e request trigger=>record_input "open_activity"[("editor",encode_editor e);("request",encode_request request);("trigger",JString trigger)]
|ActivityView occurrence view=>record_input "activity_view"[("occurrence",number occurrence);("view",encode_view view)]
|ActivitySelect occurrence name value=>record_input "activity_select"[("occurrence",number occurrence);("field",JString name);("value",value)]
|ActivitySearch occurrence query=>record_input "activity_search"[("occurrence",number occurrence);("value",JString query)]
|ActivityParameter occurrence buffer=>record_input "activity_parameter"[("occurrence",number occurrence);("value",JString buffer)]
|ActivityComplete occurrence=>record_input "activity_complete"[("occurrence",number occurrence)]
|ActivityWorkspaceChange occurrence change=>record_input "activity_workspace"[("occurrence",number occurrence);("change",encode_workspace_change change)]
|OpenEditor e trigger=>record_input "open_editor"[("editor",encode_editor e);("trigger",JString trigger)]
|Edit e name value selection=>record_input "edit"(("editor",encode_editor e)::("field",JString name)::("value",value)::match selection with None=>[]|Some(a,b,c)=>[("selection",JObject[("start",number a);("end",number b);("composing",JBool c)])]end)
|RetryWorkspace e trigger=>record_input "retry_workspace"[("editor",encode_editor e);("trigger",JString trigger)]
|DirectoriesCompleted t outcome=>record_input "directories_completed"(("ticket",number t)::encode_outcome (fun value=>value) outcome)
|Submit e trigger=>record_input "submit"[("editor",encode_editor e);("trigger",JString trigger)]
|RemoveAttachment e id=>record_input "remove_attachment"[("editor",encode_editor e);("id",JString id)]
|Command c=>record_input "command"[("command",encode_command c)]
|Completed t r=>record_input "completed"(("ticket",number t)::encode_outcome(fun j=>j)r)
|ServiceInput s=>encode_service_input s|SpeechInput s=>encode_speech_input s
|InspectSource e name trigger=>record_input "inspect_source"[("editor",encode_editor e);("field",JString name);("trigger",JString trigger)]
|ClosePanel=>record_input "close_panel"[]
|OpenInformation kind subject trigger=>record_input "open_information"[("kind",JString kind);("subject",subject);("trigger",JString trigger)]
|Confirm=>record_input "confirm"[]
|Input.Confirmation c trigger=>record_input "confirmation"[("command",encode_command c);("trigger",JString trigger)]
|BeginSide t trigger=>record_input "begin_side"[("task_id",number t);("trigger",JString trigger)]
|ShowSide t trigger=>record_input "show_side"[("task_id",number t);("trigger",JString trigger)]|CloseSide=>record_input "close_side"[]
|NavigationExpanded e=>record_input "navigation_expanded"[("value",JBool e)]
|WriteHistoryQuery q=>record_input "write_history_query"[("value",JString q)]
|ChooseHistoryScope p w=>record_input "choose_history_scope"[("project",JBool p);("value",optional_id w)]
|SubmitHistorySearch after=>record_input "submit_history_search"[("after",number after)]
|OpenHistoryMessage t i=>record_input "open_history_message"[("task_id",number t);("message_index",number i)]
|FollowLatest t=>record_input "follow_latest"[("task_id",number t)]
|SetDisclosure t g o e=>record_input "disclosure"[("task_id",number t);("group",number g);("occurrence",number o);("expanded",JBool e)]
|CardPlaced id revision now stage before=>record_input "card_placed"[("card_id",number id);("revision",number revision);("observed_at",number now);("status",JString stage);("before_card",optional_id before)]
|CardField id r t name value=>record_input "card_field"[("card_id",number id);("revision",number r);("observed_at",number t);("name",JString name);("value",JString value)]
|BoardProfile value=>record_input "board_profile"[("value",JString value)]
|BoardQuery v=>record_input "board_query"[("value",JString v)]
|BoardTab v=>record_input "board_tab"[("value",JString v)]
|BoardToggle c v=>record_input "board_toggle"[("category",JString c);("value",JString v)]
|RetainedOutput key toggle=>record_input "retained_output"[("key",JString key);("toggle",JBool toggle)]
|Snapshot=>record_input "snapshot"[]|Stream v=>record_input "stream"[("value",v)]|CodeObserved v=>v
|Interactive v=>record_input "interactive"[("input",Selvedge.Interaction.Interactive.Types.encode_input v)]
|AppearanceRestored a=>record_input "appearance_restored"[("value",JString(appearance_name a))]
|Viewport w h=>record_input "viewport"[("width",number w);("height",number h)]
|LoadSkills e=>record_input "load_skills"[("editor",encode_editor e)]
|SkillsLoaded e t outcome=>match outcome with inr skills=>record_input "skill_catalog"[("editor",encode_editor e);("ticket",number t);("skills",JArray(map SkillMention.encode_skill skills))]|inl error=>record_input "skill_catalog_failed"[("editor",encode_editor e);("ticket",number t);("error",JString error)]end
|SkillSelection e (a,b,c)=>record_input "skill_selection"[("editor",encode_editor e);("selection",JObject[("start",number a);("end",number b);("composing",JBool c)])]
|SkillMove e backward=>record_input "skill_move"[("editor",encode_editor e);("backward",JBool backward)]
|SkillDismiss e=>record_input "skill_dismiss"[("editor",encode_editor e)]
|SkillSelected e path=>record_input "skill_select"[("editor",encode_editor e);("path",JString path)]end.
