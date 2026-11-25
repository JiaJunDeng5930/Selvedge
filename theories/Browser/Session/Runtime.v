From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Programming Require Import Schema.
From Selvedge.Kernel Require Import Commands Streams.
From Selvedge.Generated Require Commands.
From Selvedge.Features Require BoardFilter.
From Selvedge.Browser Require Import NavigationIdentity.
From Selvedge.Interaction Require Import Codec Identity.
From Selvedge.Browser.Session Require Configuration.
From Selvedge.Browser.Session Require Import Input.
From Selvedge.Programming Require Import Resource.
From Selvedge.Browser.Session Require Import Services Speech ObjectActions.
From Selvedge.Interaction Require Import Origin.
From Selvedge.Browser Require Import Documents DocumentState.
From Selvedge.Interaction.Submission Require Draft.
From Selvedge.Browser.Session Require State Navigation Context Authoring Observation.
From Selvedge.Interaction.Submission Require Fields Parameters Values Command.
From Selvedge.Interaction.Experience Require Model Activity.
From Selvedge.Interaction.Interactive Require Types State Expand Runtime Language.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Browser.Session Require Import EditorContext.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Module EM:=Selvedge.Interaction.Experience.Model.
Module SS:=Selvedge.Browser.Session.State.
Module SO:=Selvedge.Browser.Session.Observation.
Module CX:=Selvedge.Browser.Session.Context.
Module IS:=Selvedge.Interaction.Interactive.State.
Module IT:=Selvedge.Interaction.Interactive.Types.
Definition context namespace snapshot state:=CX.document_context namespace snapshot state.
Definition visible namespace snapshot state owner:=Documents.visible_owner(context namespace snapshot state)owner(SS.document_retention state).
Definition native_language namespace snapshot state input:=
 let ctx:=context namespace snapshot state in
 let node identity:=match IS.find_block(IT.event_owner identity)(IS.blocks(SS.interactive_state state))with
 |Some block=>Selvedge.Interaction.Interactive.Runtime.event_node block(Documents.environment ctx false)identity
 |None=>None end in
 match input with
 |IT.ValueChanged identity _=>visible namespace snapshot state(IT.event_owner identity)&&
    match node identity with Some(Expand.Mounted _ _ (Expand.FieldLink _ true) _)=>true|_=>false end
 |IT.ActionClicked identity=>visible namespace snapshot state(IT.event_owner identity)&&
    match node identity with Some(Expand.Mounted _ _ (Expand.ActionLink _ Expand.Enabled) _)=>true|_=>false end
 |IT.ViewChanged identity _=>visible namespace snapshot state(IT.event_owner identity)&&
    match node identity with Some(Expand.Mounted _ _ (Expand.Passive true) _)=>true|_=>false end
 |IT.SourceDisclosure owner|IT.CopyDefinition owner=>visible namespace snapshot state owner
 |IT.Continue _|IT.Feedback _ _ _ _ _|IT.Restore _ _ _ _|IT.StorageResult _ _ _ _=>true
 |IT.SourceChanged _ _ _ _ _|IT.ExternalChanged _ _|IT.EnvironmentChanged|IT.Remove _=>false end.
Definition callback_owner input:=match input with
 |IT.Continue owner|IT.Feedback owner _ _ _ _|IT.Restore owner _ _ _|IT.StorageResult owner _ _ _=>Some owner
 |_=>None end.
Definition language_step namespace snapshot lagged input state:=
 let ctx:=context namespace snapshot state in
 let admitted:=match callback_owner input with
 |Some owner=>Documents.known_owner ctx owner(SS.document_retention state)
 |None=>true end in
 if admitted then Language.step_visible(visible namespace snapshot state)input(SS.interactive_state state)(Documents.environment ctx lagged)
 else IS.Decision(SS.interactive_state state)[].
Definition language_feedback namespace snapshot lagged owner path ticket success message state:=
 let decision:=language_step namespace snapshot lagged(IT.Feedback owner path ticket success message)state in
 Authoring.changed(SS.with_interactive_state(IS.next_state decision)state)(map IT.encode_effect(IS.effects decision)).
Definition language_failure namespace snapshot lagged owner path ticket message state:=
 language_feedback namespace snapshot lagged owner path ticket false message state.
Definition language_send_command task text:=
 Schema.decode_command command_specs(JObject[("op",JString "send");("task_id",number task);("message",JString text)]).
Definition interpret_language namespace snapshot lagged effect state:Authoring.result:=
 let ctx:=context namespace snapshot state in
 match effect with
 |IT.FillDraft owner path ticket text=>
  let refused:=language_failure namespace snapshot lagged owner path ticket in
  match Documents.owning_task ctx owner(SS.document_retention state)with
  |None=>refused "当前没有可填写的输入框。" state
  |Some task=>if Documents.externally_allowed ctx owner(SS.document_retention state)then
    let editor:=Identity.Message task in let state:=Authoring.ensure_draft snapshot editor state in
    let draft:=SS.current_draft state editor in
    match Authoring.draft_text draft with
    |Some previous=>match previous with
      |Draft.Text "" []=>match Authoring.with_text(Draft.Text text [])draft with
        |Some draft=>let saved:=SS.save_draft draft state in
          Authoring.append (Authoring.changed saved[Authoring.focus(Authoring.message_focus saved editor)])
            (language_feedback namespace snapshot lagged owner path ticket true "" saved)
        |None=>refused "当前没有可填写的输入框。" state end
      |_=>refused "输入框已有草稿，已保留。清空后可重试。" state end
    |None=>refused "当前没有可填写的输入框。" state end
   else refused "此交互内容为只读。" state end
 |IT.SendMessage owner path ticket text=>match Documents.owning_task ctx owner(SS.document_retention state)with
  |None=>Authoring.fail state "The interactive document has no current recipient."
  |Some task=>if Documents.externally_allowed ctx owner(SS.document_retention state)then
    let editor:=Identity.Message task in
    let refused:=language_failure namespace snapshot lagged owner path ticket in
    if negb(Services.connected(SS.service_state state))then refused "Connect to continue."state
    else if SS.pending_editor editor state then
      refused "Wait for the current submission to finish."state
    else match language_send_command task text with
    |None=>refused "The interactive message is not a valid command."state
    |Some command=>if SS.pending_command command state then
       refused "This command is already pending."state
      else Authoring.issue command(SS.LanguageSubmission editor owner path ticket)state
    end
   else Authoring.fail state "This interactive document is read only."end
 |_=>Authoring.changed state[IT.encode_effect effect]end.
Definition apply_language_decision namespace snapshot lagged decision state:=
 fold_left(fun result effect=>Authoring.append result(interpret_language namespace snapshot lagged effect(Authoring.result_state result)))
 (IS.effects decision)(Authoring.keep(SS.with_interactive_state(IS.next_state decision)state)).
Definition apply_language namespace snapshot lagged input state:=
 apply_language_decision namespace snapshot lagged(language_step namespace snapshot lagged input state)state.
Definition synchronize_language namespace snapshot lagged state:=
 let ctx:=context namespace snapshot state in
 let retained:=SS.document_retention state in
 let language:=SS.interactive_state state in
 (* A refresh can ask for the same document visibility for every authored block. *)
 let documents:=match IS.blocks language with []=>[]|_=>Documents.visible_documents ctx retained end in
 let visible owner:=Documents.visible_owner_in ctx owner retained documents in
 let decision:=Language.step_visible visible IT.EnvironmentChanged language (Documents.environment ctx lagged) in
 apply_language_decision namespace snapshot lagged decision state.
Definition apply_document_retention namespace snapshot retained state:=
 let ctx:=context namespace snapshot state in
 let state:=SS.with_retention retained state in
 (* Inactive owners stay cached; removed documents and replaced epochs do not. *)
 SS.with_interactive_state(IS.State(filter(fun block=>
   Documents.known_owner ctx(IS.block_owner block)retained)(IS.blocks(SS.interactive_state state))))state.
Definition synchronize_documents namespace snapshot lagged state:=
 let ctx:=context namespace snapshot state in
 let retained:=Documents.synchronize_documents ctx lagged(SS.document_retention state)in
 let state:=apply_document_retention namespace snapshot retained state in
 let definition:=Documents.shared_definition(context namespace snapshot state)retained in
 let initial:=match definition with Some input=>apply_language namespace snapshot lagged input state|None=>Authoring.keep state end in
 Authoring.append initial(synchronize_language namespace snapshot lagged(Authoring.result_state initial)).
Definition complete namespace snapshot lagged ticket outcome state:=
 match find(fun pending=>N.eqb ticket(SS.ticket pending))(SS.awaiting(SS.authoring_state state))with
 |None=>Authoring.keep state
 |Some pending=>let state:=SS.with_authoring
   (set SS.awaiting(filter(fun pending=>negb(N.eqb ticket(SS.ticket pending))))(SS.authoring_state state))state in
  match SS.purpose pending with
  |SS.LanguageSubmission _ owner path transaction=>apply_language namespace snapshot lagged
    (IT.Feedback owner path transaction(Authoring.completion_success outcome)(if Authoring.completion_success outcome then "Sent"else Authoring.completion_message outcome))state
  |purpose=>match Navigation.complete snapshot purpose outcome state with
   |Some decision=>let adopted:=Authoring.adopt_navigation snapshot decision in
     match purpose,Navigation.result_error decision with
     |SS.SideCreation _ _ _ _,Some _=>
       set Authoring.result_visible_error(fun _=>true)adopted
     |_,_=>adopted end
   |None=>match Authoring.complete snapshot(SS.accepted_command pending)purpose outcome state with Some result=>result|None=>Authoring.keep state end end end end.
Definition owns_action_panel subject panel :=
 match panel,subject with
 |SS.ObjectActionsPanel actual,_=>if Identity.object_subject_eq_dec actual subject then true else false
 |SS.CardDecisionPanel card _,CardActions source=>N.eqb card source
 |_,_=>false end.
Definition menu_action snapshot subject key occurrence state:=
 match SS.layers(SS.navigation_state state)with
 |layer::_=>if N.eqb occurrence(SS.layer_occurrence layer) && owns_action_panel subject(SS.layer_panel layer) then
   match ObjectActions.resolve snapshot state subject key with
   |None=>Authoring.fail state "The action is no longer available."
   |Some action=>let handoff open_next:=Authoring.adopt_navigation snapshot
      (Navigation.handoff open_next layer state) in
    match ObjectActions.action_operation action with
    |ObjectActions.NativeCommand command=>match ObjectActions.action_status action with
      |ObjectActions.Available=>match ObjectActions.action_confirmation action with
       |Some(caption,destination)=>Authoring.adopt_navigation snapshot(Navigation.open_panel(SS.Confirmation command caption destination)(SS.layer_trigger layer)state)
       |None=>let cleared:=Navigation.modify_top occurrence
          (fun layer=>Some(set SS.layer_feedback(fun _=>None)layer))state in
         Authoring.issue command (SS.MenuSubmission occurrence) (Navigation.result_state cleared) end
      |_=>Authoring.fail state "This action has not been admitted against the current state."end
    |ObjectActions.Destination route=>Authoring.adopt_navigation snapshot(Navigation.visit snapshot route state)
    |ObjectActions.Editor owner=>handoff(Navigation.edit_object snapshot owner)
    |ObjectActions.SideConversation task=>Authoring.adopt_navigation snapshot(Navigation.begin_side snapshot task(SS.layer_trigger layer)state)
    |ObjectActions.InspectCard card=>handoff(Navigation.open_panel(SS.InformationPanel(SS.CardDetails card)))
    end end
   else Authoring.keep state
 |[]=>Authoring.keep state end.
Definition board_step snapshot input state:option Authoring.result:=match input with
|Input.BoardClear=>Some(Authoring.keep(SS.with_board BoardFilter.empty state))
|Input.BoardQuery query=>Some(Authoring.keep(SS.with_board(BoardFilter.set_query query(SS.board_selection state))state))
|Input.BoardTab tab=>Some(Authoring.keep(SS.with_board(BoardFilter.set_tab tab(SS.board_selection state))state))
|Input.BoardToggle category value=>Some(Authoring.keep(SS.with_board(BoardFilter.toggle category value(SS.board_selection state))state))
|Input.BoardProfile _|Input.CardPlaced _ _ _ _ _|Input.CardField _ _ _ _=>
 Some(match Authoring.input_command snapshot state input with
 |None=>Authoring.fail state "The board action is not valid."
 |Some command=>match Authoring.input_availability snapshot state input with
  |EM.Available=>Authoring.issue command SS.DirectSubmission state
  |EM.Unavailable reason=>Authoring.fail state reason end end)
|_=>None end.
Definition begin_task snapshot project state:=
 let available:=match project with None=>true|Some project=>match DocumentState.find_world "projects" "id" project snapshot with Some _=>true|None=>false end end in
 if available then
 let owner:=Identity.NewTask(SS.active_work(SS.navigation_state state))in
 let state:=Authoring.ensure_draft snapshot owner state in
 let draft:=SS.current_draft state owner in
 let origin:=JString(match project with None=>"environment"|Some project=>String.append "project/" (show_natural project)end)in
 match Values.update_body snapshot(Draft.contents draft)Fields.ContextOrigin origin with
 |None=>Authoring.fail state "The task context is not available."
 |Some body=>let state:=SS.save_draft(Draft.with_body body draft)state in
  let decision:=Navigation.visit snapshot NavigationIdentity.Start state in
  let target:=NavigationIdentity.key_part(NavigationIdentity.editor_key owner)"message"in
  Authoring.adopt_navigation snapshot
   (set Navigation.result_effects(map(fun effect=>match effect with Navigation.Attend _=>Navigation.Attend target|effect=>effect end))decision)
 end else Authoring.fail state "The project is no longer available.".
Definition begin_new_voice snapshot owner state:=
 let state:=Authoring.ensure_draft snapshot owner state in
 let draft:=SS.current_draft state owner in
 match owner,Authoring.current_voice_command state draft with
 |Identity.NewTask _,Some command=>match Authoring.new_voice_availability state owner with
   |EM.Available=>Authoring.speech_step snapshot
     (Speech.BeginNewVoice owner(Draft.revision draft)(SS.generation(SS.navigation_state state))command)state
   |EM.Unavailable reason=>Authoring.fail state reason end
 |_,_=>Authoring.fail state "A valid task draft is required to start a voice session."end.
Definition voice_created snapshot ticket task state:=match Speech.current(SS.speech_state state)with
|Speech.CreatingTask current owner revision generation=>if N.eqb ticket current then
 if N.eqb generation(SS.generation(SS.navigation_state state)) &&
 N.eqb revision(Draft.revision(SS.current_draft state owner))then
  let draft:=SS.current_draft state owner in
  let decision:=Authoring.speech_step snapshot(Speech.TaskCreated ticket task)
   (SS.save_draft(Authoring.clear_accepted(JObject[("task_id",number task)])draft)state)in
  Authoring.append decision(Authoring.adopt_navigation snapshot(Navigation.visit snapshot(NavigationIdentity.Conversation task)(Authoring.result_state decision)))
 else Authoring.speech_step snapshot Speech.Cancel state
 else Authoring.keep state|_=>Authoring.keep state end.
Definition decode_stream_observation namespace source:=
 Streams.decode_event_in_namespace (Origin.valid_namespace namespace) namespace source.
Definition apply_stream_observation event state:=match event with
 |Some event=>let '(streams,_) :=Streams.step Streams.browser_configuration event(SS.stream_state state)in Authoring.keep(SS.with_streams streams state)
 |None=>Authoring.fail state "The stream observation is not valid."end.
Definition core namespace snapshot lagged input state:Authoring.result:=match input with
|Input.NewCard stage trigger=>let owner:=Identity.Card None in
 let discarded:=Authoring.discard_editor owner state in
 let state:=Authoring.result_state discarded in
 let draft:=Draft.Draft(SS.next_layer state)(Draft.new_card (Identity.BoardCard None) "" stage None)Draft.Editing "" None in
 Authoring.append discarded(Authoring.adopt_navigation snapshot
   (Navigation.edit_object snapshot owner trigger(SS.save_draft draft state)))
|Input.BeginTask project=>begin_task snapshot project state
|Input.BeginVoiceNew owner=>begin_new_voice snapshot owner state
|Input.SpeechInput(Speech.TaskCreated ticket task)=>voice_created snapshot ticket task state
|Input.RepairSubject owner revision field trigger=>if N.eqb revision(Draft.revision(SS.current_draft state owner))then
 if String.eqb field ""then Authoring.adopt_navigation snapshot(Navigation.edit_object snapshot owner trigger state)
 else Authoring.adopt_navigation snapshot(Navigation.open_activity snapshot owner(Activity.SubjectActivity field)trigger state)
 else Authoring.keep state
|Input.Completed ticket outcome=>complete namespace snapshot lagged ticket outcome state
|Input.CompletionReceived ticket=>Authoring.keep(SS.with_authoring
 (set SS.awaiting(map(SS.receive_request ticket))(SS.authoring_state state))state)
|Input.CompletionUnknown ticket reason=>Authoring.keep(SS.with_authoring
 (set SS.awaiting(map(SS.unknown_outcome ticket reason))(SS.authoring_state state))state)
|Input.NativeFailed reason=>Authoring.alert_diagnostic state(JString reason)
|Input.CopyPath path=>Authoring.changed state[Authoring.emit "clipboard"[("text",JString path)]]
|Input.Snapshot=>Authoring.resume_history_location snapshot state
|Input.EnvironmentObserved=>Authoring.keep state
|Input.Stream source=>apply_stream_observation (decode_stream_observation namespace source) state
|Input.CodeObserved source=>match Documents.admit_observation(context namespace snapshot state)source(SS.document_retention state)with
 |Documents.AdmittedObservation input retained=>apply_language namespace snapshot lagged input(SS.with_retention retained state)
 |Documents.IrrelevantObservation=>Authoring.keep state
 |Documents.MalformedObservation=>Authoring.fail state "The document observation does not belong to the current output."end
|Input.Interactive input=>if native_language namespace snapshot state input then apply_language namespace snapshot lagged input state
 else Authoring.keep state
|Input.RetainedOutput identity toggle=>Authoring.keep(SS.with_retention
 (Documents.edit_retained(context namespace snapshot state)identity toggle(SS.document_retention state))state)
|Input.ClearDiscarded task=>Authoring.keep(SS.with_retention
 (Documents.clear_discarded task(SS.document_retention state))state)
|Input.MenuAction subject key occurrence=>menu_action snapshot subject key occurrence state
|Input.RequestCommand command=>Authoring.request_command state command
|Input.Command command=>match Authoring.command_availability state command with
 |EM.Available=>Authoring.issue command SS.DirectSubmission state
 |EM.Unavailable reason=>Authoring.fail state reason end
|Input.SubmitHistorySearch after=>Authoring.adopt_navigation snapshot(Navigation.submit_search after state)
|Input.OpenEditor owner trigger=>let state:=match owner,Services.settings_return(SS.service_state state)with
 |Identity.TitlePrompts Identity.ConversationTitles,_|_,None=>state
 |_,Some _=>SS.with_services(Services.with_settings_return None(SS.service_state state))
    (SS.with_navigation(set SS.generation N.succ(SS.navigation_state state))state) end in
 Authoring.adopt_navigation snapshot(Navigation.edit_object snapshot owner trigger state)
|_=>match Authoring.step snapshot input state with Some result=>result|None=>
 match Navigation.step snapshot input state with Some decision=>match Authoring.input_availability snapshot state input with
 |EM.Available=>Authoring.adopt_navigation snapshot decision|EM.Unavailable reason=>Authoring.fail state reason end|None=>
 match board_step snapshot input state with Some result=>result|None=>Authoring.fail state "The input is not applicable to the current state."end end end end.
Definition retire_namespace namespace state:=
 if String.eqb namespace(DocumentState.retention_namespace(SS.document_retention state))then Authoring.keep state else
 let previous:=SS.service_state state in
 let services:=Services.Services(Services.connection previous)(Services.settings_return previous)(Services.settings_section previous)
   (Services.theme previous)(Services.next_ticket previous)
   [] Resource.Dormant Resource.Dormant ""(Services.model_preference previous)(Services.storage_problem previous)
   [] Resource.Dormant Resource.Dormant [] Configuration.initial in
 let stopped:=Speech.speech_step Speech.Cancel(SS.speech_state state)in
 let closed:=Speech.close_login(Speech.speech_state stopped)in
 let speech:=Speech.idle_with_notice ""(Speech.speech_state closed)in
 let layers:=SS.layers(SS.navigation_state state)in
 let keep_draft draft:=match Draft.draft_feedback draft with
  |Draft.Accepted _ _=>
   let owner:=Draft.owner draft in
   negb(Navigation.discard_draft_on_dismiss owner) ||
   existsb(fun layer=>match SS.layer_panel layer with
    |SS.EditorPanel current|SS.PropertyPanel current _=>Identity.same_editor owner current
    |_=>false end)layers
  |_=>true end in
 (* Closed editors with accepted saves reopen from the latest committed world. *)
 let authoring:=set SS.history_search(fun search=>SS.Search(SS.keyword search)None None None None None)
   (set SS.awaiting(fun _=>[])
    (set SS.drafts(fun drafts=>map(Draft.with_feedback Draft.Editing)(filter keep_draft drafts))
      (SS.authoring_state state)))in
 let fresh:=SS.with_authoring authoring
  (SS.with_services services(SS.with_speech speech(SS.with_streams[]
  (SS.with_interactive_state IS.initial
  (SS.with_retention(DocumentState.Retention namespace(DocumentState.retention_next_epoch(SS.document_retention state))[][])state)))))in
 let aborts:=fold_right(fun resource effects=>match resource with Resource.Loading ticket _=>Services.AbortUpload ticket::effects|_=>effects end)[](Services.uploads previous)in
 Authoring.changed fresh(map Services.encode_effect(aborts++Services.release_preview previous)++
   map Speech.encode_effect(Speech.speech_effects stopped++Speech.speech_effects closed)).
Definition composer_editor input := match input with
 |Input.ApplyAssignment owner assignment|Input.ActivityAssignment _ owner assignment=>
   match EM.subject_declaration(Activity.assignment_subject assignment) with
   |Fields.MessageText=>Some owner|_=>None end
 |Input.EditorSelection owner _ _ _ _ _|Input.LoadSkills owner _
 |Input.SkillSelected owner _|Input.SkillMove owner _|Input.SkillDismiss owner=>Some owner
 |_=>None end.

Fixpoint same_document_views left right := match left,right with
 |[],[]=>true
 |PrimaryTask a::ls,PrimaryTask b::rs|SideTask a::ls,SideTask b::rs=>
   N.eqb a b && same_document_views ls rs
 |_,_=>false end.
Definition same_shared_occurrence left right := match left,right with
 |None,None=>true
 |Some a,Some b=>N.eqb (DocumentState.shared_work a) (DocumentState.shared_work b) &&
   Navigation.same_work (DocumentState.shared_selected_task a) (DocumentState.shared_selected_task b)
 |_,_=>false end.

(* Only observations of the document source or changes to its visible owners
   can invalidate retention and authored mounts. A local edit cannot change
   the server snapshot or the stream that supplied those documents. *)
Definition documents_changed input before after := match input with
 |Input.Snapshot|Input.RetainedOutput _ _=>true
 |Input.Stream _=>false
 |Input.ClockObserved _|Input.EnvironmentObserved=>
   (* A lagged source observation may leave an interrupted stream open until
      its next settled observation. Completed documents require no retry. *)
   existsb(fun stamp=>Documents.same_ending (document_ending stamp) Types.Open)
     (document_lifetimes(SS.document_retention after))
 |_=>
   let old:=SS.service_state before in let current:=SS.service_state after in
   negb(same_document_views(Navigation.visible_task_views before)(Navigation.visible_task_views after) &&
     same_shared_occurrence(Navigation.shared_occurrence before)(Navigation.shared_occurrence after) &&
     Navigation.same_work (SS.active_work(SS.navigation_state before)) (SS.active_work(SS.navigation_state after)) &&
     Bool.eqb (Services.connected old) (Services.connected current) &&
     Bool.eqb (Services.connection_revoked(Services.connection old)) (Services.connection_revoked(Services.connection current)))
 end.

Definition prepares_authoring input before := match input with
 |Input.ToggleProjectGroup _|Input.ToggleTaskBranches _|Input.OpenNavigation _ _
 |Input.OpenObjectActions _ _|Input.OpenInformation _ _|Input.InspectSource _ _ _
 |Input.NavigationExpanded _|Input.TaskListVisible _|Input.ReadTimeline _ _ _
 |Input.FollowLatest _|Input.SetDisclosure _ _ _ _|Input.SkillsLoaded _ _
 |Input.ActivityFocus _ _ _|Input.ActivitySearch _ _|Input.CodeObserved _
 |Input.Interactive _|Input.Stream _|Input.ServiceInput(Services.CommandAssessed _ _)=>false
 |Input.ClosePanel=>match SS.layers(SS.navigation_state before) with
  |top::_=>match SS.layer_panel top with
   |SS.EditorPanel _|SS.PropertyPanel _ _|SS.SideConversationPanel _=>true
   |_=>false end
  |[]=>false end
 |_=>match composer_editor input with Some _=>false|None=>true end
 end.

Definition stream_document_viewers event before after := match event with
 |Some (Streams.Start key)|Some (Streams.Finish key)
 |Some (Streams.Delta key _ _)|Some (Streams.Snapshot key _ _)=>[Streams.stream_task key]
 |Some (Streams.Restore _)=>nodup N.eq_dec (map (fun entry=>Streams.stream_task(Streams.stream_identity entry))
   (SS.stream_state before++SS.stream_state after))
 |Some Streams.Ignore|None=>[] end.

Definition step namespace snapshot lagged input state:=
 let retired:=retire_namespace namespace state in
 let current:=Authoring.result_state retired in
 let '(stepped,event):=match input with
  |Input.Stream source=>let event:=decode_stream_observation namespace source in
    (apply_stream_observation event current,event)
  |_=> (core namespace snapshot lagged input current,None) end in
 let decision:=Authoring.append retired stepped in
 let authoring:=prepares_authoring input current in
 let prepare state:=if authoring then
   let skills:=Authoring.synchronize_skills snapshot state in
   Authoring.append skills(Authoring.prepare snapshot(Authoring.result_state skills))
  else Authoring.keep state in
 let decision:=Authoring.append decision(prepare(Authoring.result_state decision))in
 let next:=Authoring.result_state decision in
 let documents:=documents_changed input current next in
 let retention:=match stream_document_viewers event current next with
  |[]=>None
  |viewers=>Documents.synchronize_stream_documents (context namespace snapshot current)
    (context namespace snapshot next) lagged viewers (SS.document_retention next) end in
 match retention with
 |Some retained=>Authoring.append decision(synchronize_language namespace snapshot lagged
    (apply_document_retention namespace snapshot retained next))
 |None=>if documents then
    Authoring.append decision(synchronize_documents namespace snapshot lagged next) else decision
 end.

Definition admitted_document_step namespace snapshot lagged input retained state :=
 apply_language namespace snapshot lagged input (SS.with_retention retained state).
