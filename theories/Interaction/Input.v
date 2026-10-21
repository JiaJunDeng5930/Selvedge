From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema.
From Selvedge.Kernel Require Import Commands.
From Selvedge.Interaction Require Import Codec Identity Services Speech ApplicationState SkillMention Activities.
Import ListNotations.
Open Scope string_scope.
Inductive input :=
| ResetTitlePrompts
| ToggleProjectGroup(project:N) | BeginProjectTask(project:N)
| BeginVoiceNew(origin:editor) | SelectSharedTask(work:N)(task:option N)
| OpenNavigation(kind:navigation_panel)(trigger:string)
| OpenObjectActions(subject:menu_subject)(trigger:string)
| MenuAction(subject:menu_subject)(key:string)(occurrence:N)
| RetryMenuAssessment(subject:menu_subject)(key:string)(occurrence:N)
| RepairSubject(owner:editor)(revision:N)(field trigger:string)
| OpenActivity(owner:editor)(request:activity_request)(trigger:string)
| ActivityView(occurrence:N)(view:view_intent)
| ActivitySelect(occurrence:N)(field:string)(value:json)
| ActivitySearch(occurrence:N)(query:string)
| ActivityParameter(occurrence:N)(buffer:string) | ActivityComplete(occurrence:N)
| ActivityWorkspaceChange(occurrence:N)(change:workspace_change)
| Navigate(destination:route) | SelectWork(work:option N) | CreateWork
| OpenEditor(owner:editor)(trigger:string) | Edit(owner:editor)(name:string)(value:json)(selection:option(N*N*bool))
| RetryWorkspace(owner:editor)(trigger:string) | DirectoriesCompleted(ticket:N)(outcome:sum string json)
| Submit(owner:editor)(trigger:string) | RemoveAttachment(owner:editor)(id:string) | Command(command:public_command)
| Completed(ticket:N)(outcome:sum string json) | ServiceInput(input:service_input) | SpeechInput(input:speech_input)
| InspectSource(owner:editor)(name trigger:string)
| ClosePanel | OpenInformation(kind:string)(subject:json)(trigger:string) | Confirm
| Confirmation(command:public_command)(trigger:string)
| BeginSide(task:N)(trigger:string) | ShowSide(task:N)(trigger:string) | CloseSide | NavigationExpanded(value:bool)
| WriteHistoryQuery(query:string) | ChooseHistoryScope(project:bool)(scope:option N)
| SubmitHistorySearch(after:N) | OpenHistoryMessage(task index:N)
| FollowLatest(task:N) | SetDisclosure(task group occurrence:N)(expanded:bool)
| CardPlaced(id revision observed_at:N)(status:string)(before:option N)
| CardField(id revision observed_at:N)(name value:string) | BoardProfile(value:string)
| BoardQuery(value:string) | BoardTab(value:string) | BoardToggle(category value:string)
| RetainedOutput(identity:string)(toggle:bool)
| Snapshot | Stream(value:json) | CodeObserved(observation:json) | Interactive(value:Selvedge.Interaction.Interactive.Types.input)
| AppearanceRestored(appearance:appearance) | Viewport(width height:N)
| LoadSkills(owner:editor) | SkillsLoaded(owner:editor)(ticket:N)(outcome:sum string(list SkillMention.skill)) | SkillSelected(owner:editor)(path:string)
| SkillSelection(owner:editor)(selection:N*N*bool)
| SkillMove(owner:editor)(backward:bool) | SkillDismiss(owner:editor).
Definition decode_editor_field j:=bind(field "editor" j)decode_editor.
Definition trigger_field fallback j:=match field "trigger" j with None=>Some fallback|Some value=>as_string value end.
Definition decode_selection j:=a<-natural_field "start" j;;b<-natural_field "end" j;;c<-bool_field "composing" j;;Some(a,b,c).
Definition input_decoders : list (string * (json -> option input)) := [
  ("reset_title_prompts", fun j => Some ResetTitlePrompts);
  ("toggle_project_group", fun j => option_map ToggleProjectGroup(natural_field "project_id" j));
  ("begin_project_task", fun j => option_map BeginProjectTask(natural_field "project_id" j));
  ("begin_voice_new", fun j => option_map BeginVoiceNew(decode_editor_field j));
  ("select_shared_task", fun j => w<-natural_field "work_id" j;;t<-(match field "value" j with Some(JString "")=>Some None|Some(JString raw)=>option_map (@Some N)(Numbers.parse_natural raw)|_=>id_field "value" j end);;Some(SelectSharedTask w t));
  ("navigate", fun j => option_map Navigate(bind(field "route" j)decode_route));
  ("select_work", fun j => option_map SelectWork(id_field "work" j));
  ("create_work", fun j => Some CreateWork);
  ("menu_action", fun j => subject<-bind(field "subject" j)decode_menu_subject;;key<-string_field "key" j;;occurrence<-natural_field "occurrence" j;;Some(MenuAction subject key occurrence));
  ("retry_menu_assessment", fun j => subject<-bind(field "subject" j)decode_menu_subject;;key<-string_field "key" j;;occurrence<-natural_field "occurrence" j;;Some(RetryMenuAssessment subject key occurrence));
  ("open_object_actions", fun j => subject<-bind(field "subject" j)decode_menu_subject;;trigger<-trigger_field "main" j;;Some(OpenObjectActions subject trigger));
  ("open_navigation", fun j => kind<-bind(string_field "navigation" j)decode_navigation_panel;;trigger<-trigger_field "navigation-header" j;;Some(OpenNavigation kind trigger));
  ("repair_subject", fun j => e<-decode_editor_field j;;revision<-natural_field "revision" j;;name<-string_field "field" j;;trigger<-trigger_field "main" j;;Some(RepairSubject e revision name trigger));
  ("open_activity", fun j => e<-decode_editor_field j;;request<-bind(field "request" j)decode_request;;trigger<-trigger_field "main" j;;Some(OpenActivity e request trigger));
  ("activity_view", fun j => occurrence<-natural_field "occurrence" j;;view<-bind(field "view" j)decode_view;;Some(ActivityView occurrence view));
  ("activity_select", fun j => occurrence<-natural_field "occurrence" j;;name<-string_field "field" j;;value<-field "value" j;;Some(ActivitySelect occurrence name value));
  ("activity_search", fun j => occurrence<-natural_field "occurrence" j;;query<-string_field "value" j;;Some(ActivitySearch occurrence query));
  ("activity_parameter", fun j => occurrence<-natural_field "occurrence" j;;buffer<-string_field "value" j;;Some(ActivityParameter occurrence buffer));
  ("activity_complete", fun j => option_map ActivityComplete(natural_field "occurrence" j));
  ("activity_workspace", fun j => occurrence<-natural_field "occurrence" j;;change<-bind(field "change" j)decode_workspace_change;;Some(ActivityWorkspaceChange occurrence change));
  ("open_editor", fun j => e<-decode_editor_field j;;t<-trigger_field(editor_key e)j;;Some(OpenEditor e t));
  ("edit", fun j => e<-decode_editor_field j;;f<-string_field "field" j;;v<-field "value" j;;selection<-(match field "selection" j with None=>Some None|Some selection=>option_map (@Some (N*N*bool)) (decode_selection selection)end);;Some(Edit e f v selection));
  ("retry_workspace", fun j => e<-decode_editor_field j;;trigger<-string_field "trigger" j;;Some(RetryWorkspace e trigger));
  ("directories_completed", fun j => t<-natural_field "ticket" j;;outcome<-decode_outcome (fun value=>Some value) j;;Some(DirectoriesCompleted t outcome));
  ("submit", fun j => e<-decode_editor_field j;;trigger<-string_field "trigger" j;;Some(Submit e trigger));
  ("remove_attachment", fun j => e<-decode_editor_field j;;id<-string_field "id" j;;Some(RemoveAttachment e id));
  ("command", fun j => option_map Command(bind(field "command" j)(decode_command command_specs)));
  ("completed", fun j => t<-natural_field "ticket" j;;r<-decode_outcome(fun v=>Some v)j;;Some(Completed t r));
  ("inspect_source", fun j => e<-decode_editor_field j;;name<-string_field "field" j;;trigger<-trigger_field "main" j;;Some(InspectSource e name trigger));
  ("close_panel", fun j => Some ClosePanel);
  ("open_information", fun j => k<-string_field "kind" j;;v<-field "subject" j;;t<-trigger_field "main" j;;Some(OpenInformation k v t));
  ("confirm", fun j => Some Confirm);
  ("confirmation", fun j => c<-bind(field "command" j)(decode_command command_specs);;t<-string_field "trigger" j;;Some(Confirmation c t));
  ("begin_side", fun j => task<-natural_field "task_id" j;;trigger<-string_field "trigger" j;;Some(BeginSide task trigger));
  ("show_side", fun j => task<-natural_field "task_id" j;;trigger<-string_field "trigger" j;;Some(ShowSide task trigger));
  ("close_side", fun j => Some CloseSide);
  ("navigation_expanded", fun j => option_map NavigationExpanded(bool_field "value" j));
  ("write_history_query", fun j => option_map WriteHistoryQuery(string_field "value" j));
  ("choose_history_scope", fun j => p<-bool_field "project" j;;w<-(match field "value" j with Some(JString "")=>Some None|Some(JString raw)=>option_map (@Some N)(Numbers.parse_natural raw)|_=>id_field "value" j end);;Some(ChooseHistoryScope p w));
  ("submit_history_search", fun j => option_map SubmitHistorySearch(natural_field "after" j));
  ("open_history_message", fun j => t<-natural_field "task_id" j;;i<-natural_field "message_index" j;;Some(OpenHistoryMessage t i));
  ("follow_latest", fun j => option_map FollowLatest(natural_field "task_id" j));
  ("disclosure", fun j => t<-natural_field "task_id" j;;g<-natural_field "group" j;;o<-natural_field "occurrence" j;;e<-bool_field "expanded" j;;Some(SetDisclosure t g o e));
  ("card_placed", fun j => id<-natural_field "card_id" j;;r<-natural_field "revision" j;;now<-natural_field "observed_at" j;;stage<-string_field "status" j;;before<-id_field "before_card" j;;Some(CardPlaced id r now stage before));
  ("card_field", fun j => id<-natural_field "card_id" j;;r<-natural_field "revision" j;;t<-natural_field "observed_at" j;;n<-string_field "name" j;;v<-string_field "value" j;;Some(CardField id r t n v));
  ("board_profile", fun j => option_map BoardProfile(string_field "value" j));
  ("board_query", fun j => option_map BoardQuery(string_field "value" j));
  ("board_tab", fun j => option_map BoardTab(string_field "value" j));
  ("board_toggle", fun j => c<-string_field "category" j;;v<-string_field "value" j;;Some(BoardToggle c v));
  ("retained_output", fun j => key<-string_field "key" j;;toggle<-bool_field "toggle" j;;Some(RetainedOutput key toggle));
  ("snapshot", fun j => Some Snapshot);
  ("stream", fun j => option_map Stream(field "value" j));
  ("code_observed", fun j => Some(CodeObserved j));
  ("interactive", fun j => option_map Interactive(bind(field "input" j)Selvedge.Interaction.Interactive.Types.decode_input));
  ("appearance_restored", fun j => value<-string_field "value" j;;
    match decode_appearance value with Some appearance=>Some(AppearanceRestored appearance)
    |None=>Some(ServiceInput(StorageProblem "无法恢复外观设置：存储内容无效。"))end);
  ("viewport", fun j => w<-natural_field "width" j;;h<-natural_field "height" j;;Some(Viewport w h));
  ("load_skills", fun j => option_map LoadSkills(decode_editor_field j));
  ("skill_catalog", fun j => e<-decode_editor_field j;;t<-natural_field "ticket" j;;xs<-list_field decode_skill "skills" j;;Some(SkillsLoaded e t(inr xs)));
  ("skill_catalog_failed", fun j => e<-decode_editor_field j;;t<-natural_field "ticket" j;;error<-string_field "error" j;;Some(SkillsLoaded e t(inl error)));
  ("skill_select", fun j => e<-decode_editor_field j;;p<-string_field "path" j;;Some(SkillSelected e p));
  ("skill_selection", fun j => e<-decode_editor_field j;;selection<-bind(field "selection" j)decode_selection;;Some(SkillSelection e selection));
  ("skill_move", fun j => e<-decode_editor_field j;;b<-bool_field "backward" j;;Some(SkillMove e b));
  ("skill_dismiss", fun j => option_map SkillDismiss(decode_editor_field j))
].
Definition decode_input j : option input :=
  let fallback (_ : unit) := match decode_service_input j with Some v=>Some(ServiceInput v)|None=>option_map SpeechInput(Speech.decode_input j)end in
  match string_field "type" j with
  | Some name => match find (fun entry => String.eqb (fst entry) name) input_decoders with
      | Some (_, decode) => decode j | None => fallback tt end
  | None => fallback tt
  end.

Definition scope_triggers scope input :=
 let physical key:=String.append scope(String.append "/" key)in
 match input with
 |RetryWorkspace e trigger=>RetryWorkspace e(physical trigger)
 |Submit e trigger=>Submit e(physical trigger)
 |BeginSide task trigger=>BeginSide task(physical trigger)
 |ShowSide task trigger=>ShowSide task(physical trigger)
 |OpenEditor e trigger=>OpenEditor e(physical trigger)
 |OpenActivity e request trigger=>OpenActivity e request(physical trigger)
 |OpenObjectActions subject trigger=>OpenObjectActions subject(physical trigger)
 |OpenNavigation kind trigger=>OpenNavigation kind(physical trigger)
 |OpenInformation kind subject trigger=>OpenInformation kind subject(physical trigger)
 |InspectSource e name trigger=>InspectSource e name(physical trigger)
 |RepairSubject e revision name trigger=>RepairSubject e revision name(physical trigger)
 |Input.Confirmation command trigger=>Input.Confirmation command(physical trigger)
 |ServiceInput(Services.OpenPreview attachment trigger)=>ServiceInput(Services.OpenPreview attachment(physical trigger))
 |ServiceInput(Services.OpenDirectory e path trigger)=>ServiceInput(Services.OpenDirectory e path(physical trigger))
 |other=>other end.
