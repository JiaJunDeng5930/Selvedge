From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema.
From Selvedge.Kernel Require Import Commands Streams.
From Selvedge.Generated Require Commands.
From Selvedge.Features Require BoardFilter.
From Selvedge.Interaction Require Import Codec Identity Input Resource Services Speech Origin Documents DocumentState ObjectActions CommandAssessment.
From Selvedge.Interaction.Session Require Draft State Navigation Context Authoring Observation.
From Selvedge.Interaction.Submission Require Fields Parameters Values Command.
From Selvedge.Interaction.Experience Require Model Activity.
From Selvedge.Interaction.Interactive Require Types State Runtime Language.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Module EM:=Selvedge.Interaction.Experience.Model.
Module SS:=Selvedge.Interaction.Session.State.
Module SO:=Selvedge.Interaction.Session.Observation.
Module CX:=Selvedge.Interaction.Session.Context.
Module IS:=Selvedge.Interaction.Interactive.State.
Module IT:=Selvedge.Interaction.Interactive.Types.
Definition context namespace snapshot state:=CX.document_context namespace snapshot state.
Definition visible namespace snapshot state owner:=Documents.visible_owner(context namespace snapshot state)owner(SS.document_retention state).
Definition native_language namespace snapshot state input:=match input with
|IT.ValueChanged identity _|IT.ActionClicked identity|IT.ViewChanged identity _=>visible namespace snapshot state(IT.event_owner identity)
|IT.SourceDisclosure owner|IT.CopyDefinition owner=>visible namespace snapshot state owner
|IT.Continue _|IT.Feedback _ _ _ _ _|IT.Restore _ _ _ _|IT.StorageResult _ _ _ _=>true
|IT.SourceChanged _ _ _ _ _|IT.ExternalChanged _ _|IT.EnvironmentChanged|IT.Remove _=>false end.
Definition language_failure namespace snapshot lagged owner path ticket message state:=
 let ctx:=context namespace snapshot state in
 let decision:=Language.step_visible(visible namespace snapshot state)(IT.Feedback owner path ticket false message)
   (SS.interactive_state state)(Documents.environment ctx lagged)in
 Authoring.changed(SS.with_interactive_state(IS.next_state decision)state)(map IT.encode_effect(IS.effects decision)).
Definition language_admission_draft task revision text:=
 Draft.Draft revision(Draft.MessageBody task(Draft.Text text [])Fields.Send)Draft.Editing "".
Definition language_send_command task text:=
 Schema.decode_command command_specs(JObject[("op",JString "send");("task_id",number task);("message",JString text)]).
Definition forget_pending ticket state:=
 let authoring:=SS.authoring_state state in
 SS.with_authoring(set SS.awaiting(fun pending=>filter(fun current=>negb(N.eqb ticket(SS.ticket current)))pending)
  authoring)state.
Definition promote_language_admission pending editor owner path language_ticket state:=
 let authoring:=SS.authoring_state state in
 let awaiting:=map(fun current=>if N.eqb(SS.ticket pending)(SS.ticket current)then
  SS.Pending(SS.ticket current)(SS.accepted_command current)(SS.LanguageSubmission editor owner path language_ticket)(SS.outcome_unknown current)else current)
  (SS.awaiting authoring)in
 Authoring.changed(SS.with_authoring(set SS.awaiting(fun _=>awaiting)authoring)state)
  [Authoring.emit "command"[("ticket",number(SS.ticket pending));("command",Schema.encode_command(SS.accepted_command pending))]].
Definition pending_command_except ticket command state:=existsb(fun pending=>
 negb(N.eqb ticket(SS.ticket pending))&&CommandAssessment.same_command command(SS.accepted_command pending))
 (SS.awaiting(SS.authoring_state state)).
Definition reject_language_admission namespace snapshot lagged pending owner path language_ticket message state:=
 language_failure namespace snapshot lagged owner path language_ticket message(forget_pending(SS.ticket pending)state).
Definition continue_language_admission namespace snapshot lagged pending state:=
 match SS.purpose pending with
 |SS.LanguageAdmission task revision text owner path language_ticket=>
  let editor:=Identity.Message task in
  let draft:=language_admission_draft task revision text in
  let ctx:=context namespace snapshot state in
  match Documents.owning_task ctx owner(SS.document_retention state)with
  |None=>reject_language_admission namespace snapshot lagged pending owner path language_ticket
     "The interactive document has no current recipient."state
  |Some actual=>if negb(N.eqb actual task)then
      reject_language_admission namespace snapshot lagged pending owner path language_ticket
       "The interactive document has no current recipient."state
   else if negb(Documents.externally_allowed ctx owner(SS.document_retention state))then
      reject_language_admission namespace snapshot lagged pending owner path language_ticket
       "This interactive document is read only."state
   else
    let without_self:=forget_pending(SS.ticket pending)state in
    match Authoring.submission_obstruction snapshot draft without_self with
    |Some reason=>reject_language_admission namespace snapshot lagged pending owner path language_ticket reason state
    |None=>match language_send_command task text with
     |None=>reject_language_admission namespace snapshot lagged pending owner path language_ticket
       "The draft is waiting for a valid command and workspace observation."state
     |Some command=>if negb(CommandAssessment.same_command command(SS.accepted_command pending))then
        reject_language_admission namespace snapshot lagged pending owner path language_ticket
         "The interactive message is no longer current."state
       else if pending_command_except(SS.ticket pending)command state then
        reject_language_admission namespace snapshot lagged pending owner path language_ticket
         "This command is already pending."state
       else match natural_field "sequence" snapshot with
        |None=>reject_language_admission namespace snapshot lagged pending owner path language_ticket
          "The current state has not been observed."state
        |Some _=>let assessment_owner:=CommandAssessment.DraftOwner editor in
         let checked:=Authoring.ensure_request snapshot assessment_owner revision command state in
         let checked_state:=Authoring.result_state checked in
         match Authoring.assessed_command snapshot assessment_owner revision command checked_state with
         |None=>Authoring.append checked(Authoring.keep checked_state)
         |Some(inl reason)=>Authoring.append checked(reject_language_admission namespace snapshot lagged pending owner path language_ticket reason checked_state)
         |Some(inr _)=>if Authoring.canonical_ready snapshot checked_state assessment_owner revision command
           then Authoring.append checked(promote_language_admission pending editor owner path language_ticket checked_state)
           else Authoring.append checked(reject_language_admission namespace snapshot lagged pending owner path language_ticket
             "This action has not been admitted against the current state."checked_state)
         end end end end end
 | _=>Authoring.keep state end.
Definition continue_language_admissions namespace snapshot lagged state:=
 fold_left(fun result pending=>match SS.purpose pending with
  |SS.LanguageAdmission _ _ _ _ _ _=>Authoring.append result
    (continue_language_admission namespace snapshot lagged pending(Authoring.result_state result))
  |_=>result end)(SS.awaiting(SS.authoring_state state))(Authoring.keep state).
Definition interpret_language namespace snapshot lagged effect state:Authoring.result:=
 let ctx:=context namespace snapshot state in
 match effect with
 |IT.FillDraft owner _ text=>match Documents.owning_task ctx owner(SS.document_retention state)with
  |None=>Authoring.fail state "The interactive document has no current recipient."
  |Some task=>if Documents.externally_allowed ctx owner(SS.document_retention state)then
    let editor:=Identity.Message task in let state:=Authoring.ensure_draft snapshot editor state in
    let draft:=SS.current_draft state editor in
    match Authoring.draft_text draft with
    |Some previous=>match previous with
      |Draft.Text "" []=>match Authoring.with_text(Draft.Text text [])draft with
        |Some draft=>Authoring.changed(SS.save_draft draft state)[Authoring.focus(Authoring.message_focus state editor)]
        |None=>Authoring.fail state "The recipient does not have a message draft."end
      |_=>Authoring.fail state "The current task composer is not empty." end
    |None=>Authoring.fail state "The recipient does not have a message draft."end
   else Authoring.fail state "This interactive document is read only."end
 |IT.SendMessage owner path ticket text=>match Documents.owning_task ctx owner(SS.document_retention state)with
  |None=>Authoring.fail state "The interactive document has no current recipient."
  |Some task=>if Documents.externally_allowed ctx owner(SS.document_retention state)then
    let editor:=Identity.Message task in
    let draft:=language_admission_draft task(Draft.revision(SS.current_draft state editor))text in
    match Authoring.submission_obstruction snapshot draft state with
    |Some reason=>language_failure namespace snapshot lagged owner path ticket reason state
    |None=>match language_send_command task text with
     |None=>Authoring.fail state "The interactive message is not a valid command."
     |Some command=>if SS.pending_command command state then
       language_failure namespace snapshot lagged owner path ticket "This command is already pending."state
      else match natural_field "sequence" snapshot with
       |None=>language_failure namespace snapshot lagged owner path ticket "The current state has not been observed."state
       |Some _=>let assessment_owner:=CommandAssessment.DraftOwner editor in
        let checked:=Authoring.ensure_request snapshot assessment_owner(Draft.revision draft)command state in
        let checked_state:=Authoring.result_state checked in
        match Authoring.assessed_command snapshot assessment_owner(Draft.revision draft)command checked_state with
        |Some(inl reason)=>Authoring.append checked(language_failure namespace snapshot lagged owner path ticket reason checked_state)
        |Some(inr _)=>if Authoring.canonical_ready snapshot checked_state assessment_owner(Draft.revision draft)command
          then Authoring.append checked(Authoring.issue command(SS.LanguageSubmission editor owner path ticket)checked_state)
          else Authoring.append checked(language_failure namespace snapshot lagged owner path ticket
            "This action has not been admitted against the current state."checked_state)
        |None=>Authoring.append checked(Authoring.reserve command
          (SS.LanguageAdmission task(Draft.revision draft)text owner path ticket)checked_state)
        end end end end
   else Authoring.fail state "This interactive document is read only."end
 |_=>Authoring.changed state[IT.encode_effect effect]end.
Definition apply_language namespace snapshot lagged input state:=
 let ctx:=context namespace snapshot state in
 let decision:=Language.step_visible(visible namespace snapshot state)input(SS.interactive_state state)(Documents.environment ctx lagged)in
 fold_left(fun result effect=>Authoring.append result(interpret_language namespace snapshot lagged effect(Authoring.result_state result)))
 (IS.effects decision)(Authoring.keep(SS.with_interactive_state(IS.next_state decision)state)).
Definition synchronize namespace snapshot lagged state:=
 let skills:=Authoring.synchronize_skills snapshot state in
 let state:=Authoring.result_state skills in
 let ctx:=context namespace snapshot state in
 let retained:=Documents.synchronize_documents ctx lagged(SS.document_retention state)in
 let state:=SS.with_retention retained state in
 let definition:=Documents.shared_definition(context namespace snapshot state)retained in
 let initial:=match definition with Some input=>apply_language namespace snapshot lagged input state|None=>Authoring.keep state end in
 Authoring.append skills(Authoring.append initial(apply_language namespace snapshot lagged IT.EnvironmentChanged(Authoring.result_state initial))).
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
     |SS.WorkCreation _ _,Some _|SS.SideCreation _ _ _ _,Some _=>
       set Authoring.result_visible_error(fun _=>true)adopted
     |_,_=>adopted end
   |None=>match Authoring.complete snapshot(SS.accepted_command pending)purpose outcome state with Some result=>result|None=>Authoring.keep state end end end end.
Definition menu_action snapshot subject key occurrence state:=
 match SS.layers(SS.navigation_state state)with
 |layer::_=>if N.eqb occurrence(SS.layer_occurrence layer)then
  match SS.layer_panel layer with
  |SS.ObjectActionsPanel actual=>if CommandAssessment.menu_subject_eq_dec actual subject then
    match ObjectActions.resolve snapshot state subject key with
    |None=>Authoring.fail state "The action is no longer available."
    |Some action=>match ObjectActions.action_operation action with
     |ObjectActions.NativeCommand command=>match ObjectActions.action_status action with
       |ObjectActions.Available=>match ObjectActions.action_confirmation action with
        |Some(caption,destination)=>Authoring.adopt_navigation snapshot(Navigation.open_panel(SS.Confirmation command caption destination)(SS.layer_trigger layer)state)
        |None=>Authoring.issue command SS.DirectSubmission state end
       |_=>Authoring.fail state "This action has not been admitted against the current state."end
     |ObjectActions.Destination route=>Authoring.adopt_navigation snapshot(Navigation.visit snapshot route state)
     |ObjectActions.Editor owner=>Authoring.adopt_navigation snapshot(Navigation.edit_object snapshot owner(SS.layer_trigger layer)state)
     |ObjectActions.SideConversation task=>Authoring.adopt_navigation snapshot(Navigation.begin_side snapshot task(SS.layer_trigger layer)state)
     end end else Authoring.keep state
  |_=>Authoring.keep state end else Authoring.keep state
 |[]=>Authoring.keep state end.
Definition board_step snapshot input state:option Authoring.result:=match input with
|Input.BoardQuery query=>Some(Authoring.keep(SS.with_board(BoardFilter.set_query query(SS.board_selection state))state))
|Input.BoardTab tab=>Some(Authoring.keep(SS.with_board(BoardFilter.set_tab tab(SS.board_selection state))state))
|Input.BoardToggle category value=>Some(Authoring.keep(SS.with_board(BoardFilter.toggle category value(SS.board_selection state))state))
|Input.BoardProfile _|Input.CardPlaced _ _ _ _ _|Input.CardField _ _ _ _=>
 Some(match Authoring.input_command snapshot state input with
 |None=>Authoring.fail state "The board action is not valid."
 |Some command=>match Authoring.command_availability snapshot state command with
  |EM.Available=>Authoring.issue command SS.DirectSubmission state
  |EM.Unavailable reason=>Authoring.fail state reason end end)
|_=>None end.
Definition begin_task snapshot project state:=
 let available:=match project with None=>true|Some project=>match DocumentState.find_world "projects" "id" project snapshot with Some _=>true|None=>false end end in
 if available then
 let owner:=Identity.NewTask(SS.active_work(SS.navigation_state state))in
 let state:=Authoring.ensure_draft snapshot owner state in
 let draft:=SS.current_draft state owner in
 let origin:=match project with None=>JNull|Some project=>number project end in
 match Values.update_body snapshot(Draft.contents draft)Fields.ContextOrigin origin with
 |None=>Authoring.fail state "The task context is not available."
 |Some body=>let state:=SS.save_draft(Draft.with_body body draft)state in
  let decision:=Navigation.visit snapshot Identity.Start state in
  let target:=Identity.key_part(Identity.editor_key owner)"message"in
  Authoring.adopt_navigation snapshot
   (set Navigation.result_effects(map(fun effect=>match effect with Navigation.Attend _=>Navigation.Attend target|effect=>effect end))decision)
 end else Authoring.fail state "The project is no longer available.".
Definition begin_new_voice snapshot owner state:=
 let state:=Authoring.ensure_draft snapshot owner state in
 let draft:=SS.current_draft state owner in
 match owner,Authoring.current_voice_command state draft with
 |Identity.NewTask _,Some command=>if Authoring.canonical_ready snapshot state(Authoring.voice_owner command)(Draft.revision draft)command then
   Authoring.speech_step snapshot(Speech.BeginNewVoice owner(Draft.revision draft)(SS.generation(SS.navigation_state state))command)state
   else Authoring.fail state "The voice task has not been admitted against the current state."
 |_,_=>Authoring.fail state "A valid task draft is required to start a voice session."end.
Definition voice_created snapshot ticket task state:=match Speech.current(SS.speech_state state)with
|Speech.CreatingTask current owner revision generation=>if N.eqb ticket current then
 if N.eqb generation(SS.generation(SS.navigation_state state)) &&
 N.eqb revision(Draft.revision(SS.current_draft state owner))then
  let draft:=SS.current_draft state owner in
  let decision:=Authoring.speech_step snapshot(Speech.TaskCreated ticket task)
   (SS.save_draft(Authoring.clear_accepted(JObject[("task_id",number task)])draft)state)in
  Authoring.append decision(Authoring.adopt_navigation snapshot(Navigation.visit snapshot(Identity.Conversation task)(Authoring.result_state decision)))
 else Authoring.speech_step snapshot Speech.Cancel state
 else Authoring.keep state|_=>Authoring.keep state end.
Definition core namespace snapshot lagged input state:Authoring.result:=match input with
|Input.NewCard stage trigger=>let owner:=Identity.Card None in
 let state:=Authoring.ensure_draft snapshot owner state in
 let draft:=SS.current_draft state owner in
 let state:=match Draft.contents draft with
 |Draft.CardBody None revision value assist profile keep=>SS.save_draft
   (Draft.with_body(Draft.CardBody None 0(Selvedge.Features.Domain.CardDraft "" "" stage Selvedge.Features.Domain.NoPriority Selvedge.Features.Domain.Unassigned None [] [])assist profile keep)draft)state
 |_=>state end in
 Authoring.adopt_navigation snapshot(Navigation.edit_object snapshot owner trigger state)
|Input.BeginTask project=>begin_task snapshot project state
|Input.BeginVoiceNew owner=>begin_new_voice snapshot owner state
|Input.SpeechInput(Speech.TaskCreated ticket task)=>voice_created snapshot ticket task state
|Input.RepairSubject owner revision field trigger=>if N.eqb revision(Draft.revision(SS.current_draft state owner))then
 if String.eqb field ""then Authoring.adopt_navigation snapshot(Navigation.edit_object snapshot owner trigger state)
 else Authoring.adopt_navigation snapshot(Navigation.open_activity snapshot owner(Activity.SubjectActivity field)trigger state)
 else Authoring.keep state
|Input.Completed ticket outcome=>complete namespace snapshot lagged ticket outcome state
|Input.CompletionUnknown ticket reason=>Authoring.keep(SS.with_authoring
 (set SS.awaiting(map(SS.unknown_outcome ticket reason))(SS.authoring_state state))state)
|Input.NativeFailed reason=>Authoring.alert_diagnostic state(JString reason)
|Input.Snapshot|Input.EnvironmentObserved=>Authoring.keep state
|Input.Stream source=>match Streams.decode_event_in_namespace (Origin.valid_namespace namespace) namespace source with
 |Some event=>let '(streams,_) :=Streams.step Streams.browser_configuration event(SS.stream_state state)in Authoring.keep(SS.with_streams streams state)
 |None=>Authoring.fail state "The stream observation is not valid."end
|Input.CodeObserved source=>match Documents.admit_observation(context namespace snapshot state)source(SS.document_retention state)with
 |Documents.AdmittedObservation input retained=>apply_language namespace snapshot lagged input(SS.with_retention retained state)
 |Documents.IrrelevantObservation=>Authoring.keep state
 |Documents.MalformedObservation=>Authoring.fail state "The document observation does not belong to the current output."end
|Input.Interactive input=>if native_language namespace snapshot state input then apply_language namespace snapshot lagged input state
 else Authoring.fail state "The interactive input is not accepted from this source."
|Input.RetainedOutput identity toggle=>Authoring.keep(SS.with_retention
 (Documents.edit_retained(context namespace snapshot state)identity toggle(SS.document_retention state))state)
|Input.ClearDiscarded task=>Authoring.keep(SS.with_retention
 (Documents.clear_discarded task(SS.document_retention state))state)
|Input.MenuAction subject key occurrence=>menu_action snapshot subject key occurrence state
|Input.RetryMenuAssessment subject key occurrence=>Authoring.keep(SS.with_services
 (Services.forget_owned_assessment(CommandAssessment.MenuOwner subject key)(SS.service_state state))state)
|Input.Command command=>match Authoring.command_availability snapshot state command with
 |EM.Available=>Authoring.issue command SS.DirectSubmission state
 |EM.Unavailable reason=>Authoring.fail state reason end
|Input.OpenEditor owner trigger=>let state:=match Services.settings_return(SS.service_state state)with
 |Some _=>SS.with_navigation(set SS.generation N.succ(SS.navigation_state state))state|None=>state end in
 let state:=SS.with_services(Services.with_settings_return None(SS.service_state state))state in
 Authoring.adopt_navigation snapshot(Navigation.edit_object snapshot owner trigger state)
|_=>match Authoring.step snapshot input state with Some result=>result|None=>
 match Navigation.step snapshot input state with Some decision=>match Authoring.input_availability snapshot state input with
 |EM.Available=>Authoring.adopt_navigation snapshot decision|EM.Unavailable reason=>Authoring.fail state reason end|None=>
 match board_step snapshot input state with Some result=>result|None=>Authoring.fail state "The input is not applicable to the current state."end end end end.
Definition retire_namespace namespace state:=
 if String.eqb namespace(DocumentState.retention_namespace(SS.document_retention state))then Authoring.keep state else
 let previous:=SS.service_state state in
 let services:=Services.Services(Services.connection previous)(Services.settings_return previous)(Services.theme previous)(Services.next_ticket previous)
   [] Resource.Dormant Resource.Dormant ""(Services.model_preference previous)(Services.storage_problem previous)
   [] Resource.Dormant []in
 let stopped:=Speech.speech_step Speech.Cancel(SS.speech_state state)in
 let speech:=Speech.Speech(Speech.connections(Speech.speech_state stopped))(Speech.selected(Speech.speech_state stopped))
   (Speech.next(Speech.speech_state stopped))Speech.Idle "" ""in
 let authoring:=set SS.awaiting(fun _=>[])
   (set SS.drafts(map(Draft.with_feedback Draft.Editing))(SS.authoring_state state))in
 let fresh:=SS.with_authoring authoring
  (SS.with_services services(SS.with_speech speech(SS.with_streams[]
  (SS.with_interactive_state IS.initial
  (SS.with_retention(DocumentState.Retention namespace(DocumentState.retention_next_epoch(SS.document_retention state))[][])state)))))in
 let aborts:=fold_right(fun resource effects=>match resource with Resource.Loading ticket _=>Services.AbortUpload ticket::effects|_=>effects end)[](Services.uploads previous)in
 Authoring.changed fresh(map Services.encode_effect(aborts++Services.release_preview previous)++map Speech.encode_effect(Speech.speech_effects stopped)).
Definition step namespace snapshot lagged input state:=
 let retired:=retire_namespace namespace state in
 let current:=Authoring.append retired(synchronize namespace snapshot lagged(Authoring.result_state retired))in
 let decision:=core namespace snapshot lagged input(Authoring.result_state current)in
 let decision:=Authoring.append current decision in
 let prepared:=Authoring.prepare snapshot(Authoring.result_state decision)in
 let decision:=Authoring.append decision prepared in
 let synchronized:=Authoring.append decision(synchronize namespace snapshot lagged(Authoring.result_state decision))in
 Authoring.append synchronized(continue_language_admissions namespace snapshot lagged(Authoring.result_state synchronized)).
