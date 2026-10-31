From Stdlib Require Import String List Bool NArith ZArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Programming Require Import Schema.
From Selvedge.Kernel Require Import Commands.
From Selvedge.Interaction Require Import Codec Identity Services Speech SkillMention.
From Selvedge.Interaction.Experience Require Import Model Activity.
From Selvedge.Interaction.Session Require State Draft.
From Selvedge.Interaction.Interactive Require Types.
Import ListNotations.
Open Scope string_scope.
Inductive workspace_change := AddDirectory (path:string) | RemoveDirectory (path:string)
| ChoosePrimaryDirectory (path:string) | InheritWorkspace.
Inductive selection_change := SelectionChanged | SelectionFocused | SelectionBlurred.
Inductive input :=
| ResetTitlePrompts
| ToggleProjectGroup(project:N) | BeginTask(project:option N)
| BeginVoiceNew(origin:editor) | SelectSharedTask(work:N)(task:option N)
| OpenNavigation(kind:navigation_panel)(trigger:string)
| OpenObjectActions(subject:menu_subject)(trigger:string)
| MenuAction(subject:menu_subject)(key:string)(occurrence:N)
| RetryMenuAssessment(subject:menu_subject)(key:string)(occurrence:N)
| RepairSubject(owner:editor)(revision:N)(field trigger:string)
| OpenActivity(owner:editor)(request:activity_request)(trigger:string)
| ActivityFocus(occurrence:N)(owner:editor)(focus:option(Model.subject owner))
| ActivityAssignment(occurrence:N)(owner:editor)(value:assignment owner)
| ActivitySearch(occurrence:N)(query:string)
| ActivityParameter(occurrence:N)(buffer:string) | ActivityComplete(occurrence:N)
| ActivityWorkspaceChange(occurrence:N)(change:workspace_change)
| Navigate(destination:route) | SelectWork(work:option N) | CreateWork
| NewCard(stage:Selvedge.Features.Domain.board_stage)(trigger:string)
| OpenEditor(owner:editor)(trigger:string) | OpenBoard(kind:State.board_panel)(trigger:string)
| ApplyAssignment(owner:editor)(value:assignment owner)
| AttachFiles(owner:editor)(files:list Attachments.selected_file)
| RetryWorkspace(owner:editor)(trigger:string) | DirectoriesCompleted(ticket:N)(outcome:sum string json)
| Submit(owner:editor)(trigger:string) | RemoveAttachment(owner:editor)(id:string)
| Command(command:State.public_command)
| Completed(ticket:N)(outcome:sum string json) | CompletionUnknown(ticket:N)(reason:string)
| NativeFailed(reason:string)
| ServiceInput(input:service_input) | SpeechInput(input:speech_input)
| TogglePropertySource(owner:editor)(occurrence:N)
| InspectSource(owner:editor)(request:activity_request)(trigger:string)
| ClosePanel | OpenInformation(kind:State.information_panel)(trigger:string) | Confirm
| Confirmation(command:State.public_command)(caption:string)(destination:route)(trigger:string)
| BeginSide(task:N)(trigger:string) | ShowSide(task:N)(trigger:string) | CloseSide
| NavigationExpanded(value:bool) | TaskListVisible(value:bool)
| WriteHistoryQuery(query:string) | ChooseHistoryScope(project:bool)(scope:option N)
| SubmitHistorySearch(after:N) | OpenHistoryMessage(task index:N)
| ReadTimeline(task generation:N)(intent:State.reading_intent)
| FollowLatest(task:N) | SetDisclosure(task group occurrence:N)(expanded:bool)
| CardPlaced(id revision observed_at:N)(status:string)(before:option N)
| CardField(id revision:N)(name:string)(value:json) | BoardProfile(profile:string)
| BoardQuery(query:string) | BoardTab(tab:string) | BoardToggle(category value:string) | BoardClear
| RetainedOutput(identity:string)(toggle:bool) | ClearDiscarded(task:N)
| ClockObserved(now:N) | EnvironmentObserved | Snapshot | Stream(message:json) | CodeObserved(observation:json)
| Interactive(input:Types.input) | AppearanceRestored(theme:appearance)
| LoadSkills(owner:editor)(explicit:bool) | SkillsLoaded(ticket:N)(outcome:sum string json)
| SkillSelected(owner:editor)(path:string)
| EditorSelection(owner:editor)(start finish:N)(direction:Draft.selection_direction)(composing:bool)(change:selection_change)
| SkillMove(owner:editor)(offset:Z) | SkillDismiss(owner:editor).

(* Geometry, motion, parser and reading observations change presentation, without
   making already published product content semantically stale. *)
Definition semantic_change incoming := match incoming with
 |EnvironmentObserved|CodeObserved _|ReadTimeline _ _ _|FollowLatest _=>false
 |_=>true end.

(* Only semantic user actions acknowledge a displayed command receipt. Focus,
   selection, layout, and IO observations can also be delivered without intent. *)
Definition acknowledges_feedback (incoming:input) := match incoming with
|Completed _ _|CompletionUnknown _ _|NativeFailed _|DirectoriesCompleted _ _|ClockObserved _|EnvironmentObserved
|Snapshot|Stream _|CodeObserved _|AppearanceRestored _|SkillsLoaded _ _
|ActivityFocus _ _ _|EditorSelection _ _ _ _ _ _|ReadTimeline _ _ _=>false
|LoadSkills _ explicit=>explicit
|ServiceInput service=>match service with
 |Services.CommandAssessed _ _|Services.RestoreModelPreference _
 |Services.StorageProblem _|Services.WorkspaceGitCompleted _ _|Services.Connect
 |Services.Authenticated _ _|Services.Disconnected _ _ _|Services.RetryConnection _
 |Services.Uploaded _ _|Services.Previewed _ _|Services.DirectoryListed _ _=>false
 |_=>true end
|SpeechInput speech=>match speech with
 |Speech.Refresh|Speech.Capabilities _|Speech.CapabilitiesFailed _
 |Speech.Captured _ _ _|Speech.Transcribed _ _|Speech.TaskCreated _ _
 |Speech.VoiceReady _|Speech.LiveText _ _|Speech.Failed _ _|Speech.Ended _ _
 |Speech.Released=>false
 |_=>true end
|Interactive language=>match language with
 |Types.ValueChanged _ _|Types.ActionClicked _|Types.ViewChanged _ _
 |Types.SourceDisclosure _|Types.CopyDefinition _=>true
 |_=>false end
|_=>true end.

Definition assign_subject {e} (subject:Model.subject e) (incoming:json) : option input :=
 if Parameters.editable e(Model.subject_declaration subject)then
 value<-Parameters.decode_input e (Model.subject_declaration subject) incoming;;
 Some(ApplyAssignment e (Activity.Assignment subject value))else None.
Definition assign_activity {e} occurrence (subject:Model.subject e) incoming : option input :=
 if Parameters.editable e(Model.subject_declaration subject)then
 value<-Schema.decode_value(Model.subject_kind subject)incoming;;
 Some(ActivityAssignment occurrence e (Activity.Assignment subject value))else None.
Definition selection_input {e} (subject:Model.subject e) incoming : option input :=
 caret<-natural_field "start" incoming;;
 finish<-natural_field "end" incoming;;composing<-bool_field "composing" incoming;;
 direction<-bind(string_field "direction"incoming)Draft.decode_direction;;
 Some(EditorSelection e caret finish direction composing
 (if match bool_field "blur" incoming with Some true=>true|_=>false end then SelectionBlurred
 else if match bool_field "refocus" incoming with Some true=>true|_=>false end then SelectionFocused else SelectionChanged)).

Definition assignment_selection {e} (assignment:Activity.assignment e) raw : option input :=
 match assignment with Activity.Assignment subject _=>
 match Model.subject_declaration subject with Fields.MessageText=>
  observed<-field "selection" raw;;selection_input subject observed
 |_=>None end end.
Definition native_selection incoming raw := match incoming with
 |ApplyAssignment _ assignment=>assignment_selection assignment raw
 |ActivityAssignment _ _ assignment=>assignment_selection assignment raw
 |_=>None end.

Definition attach_files owner incoming:option input:=
 files<-match incoming with JArray files=>traverse Attachments.decode_file files|value=>option_map(fun value=>[value])(Attachments.decode_file value)end;;
 Some(AttachFiles owner files).
Definition skill_key owner (mention:SkillMention.mention_state)(skills:list SkillMention.skill) incoming:option input:=
 key<-string_field "key" incoming;;
 match mention with SkillMention.Suggesting _ _=>match key with
 |"ArrowDown"=>_ <- SkillMention.highlighted skills mention;;Some(SkillMove owner 1%Z)
 |"ArrowUp"=>_ <- SkillMention.highlighted skills mention;;Some(SkillMove owner (-1)%Z)
 |"Escape"=>Some(SkillDismiss owner)
 |"Enter"|"Tab"=>skill<-SkillMention.highlighted skills mention;;Some(SkillSelected owner(SkillMention.skill_path skill))
 |_=>None end|_=>None end.
