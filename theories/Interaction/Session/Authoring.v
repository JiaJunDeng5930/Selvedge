From Stdlib Require Import String List Bool NArith ZArith.
From Selvedge.Foundation Require Import Json Numbers Schema TextJson.
From Selvedge.Kernel Require Import Commands Streams Images.
From Selvedge.Kernel Require Domain Codec ModelCapabilities.
From Selvedge.Features Require Domain BoardFilter Titles.
From Selvedge.Interaction Require Import Codec Identity Input Resource Services Speech SkillMention CommandAssessment DocumentState ObjectActions AuditReading.
From Selvedge.Interaction.Session Require Import Draft State.
From Selvedge.Interaction.Session Require DraftCodec Initialize Observation Navigation.
From Selvedge.Interaction.Submission Require Fields Parameters Values Command.
From Selvedge.Interaction.Experience Require Model Activity Observation.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Module EM := Selvedge.Interaction.Experience.Model.
Module SS := Selvedge.Interaction.Session.State.
Module EO := Selvedge.Interaction.Experience.Observation.
Module SO := Selvedge.Interaction.Session.Observation.
Record result:=Result{result_state:SS.state;result_effects:list json;
 result_error:option json;result_visible_error:bool}.
Definition keep state:=Result state [] None false.
Definition fail state reason:=Result state [] (Some(JString reason))false.
Definition fail_diagnostic state diagnostic:=Result state [](Some diagnostic)false.
Definition alert_diagnostic state diagnostic:=Result state [](Some diagnostic)true.
Definition emit kind fields:=JObject(("type",JString kind)::fields).
Definition focus key:=emit "focus"[("key",JString key)].
Definition changed state effects:=Result state effects None false.
Definition ensure_draft snapshot owner state:=match Draft.find_draft owner(SS.drafts(SS.authoring_state state))with
|Some _=>state|None=>match Initialize.materialize snapshot(SS.service_state state)owner with
 Some value=>SS.save_draft value state|None=>state end end.
Definition reopen_draft snapshot owner state:=
 match Draft.find_draft owner(SS.drafts(SS.authoring_state state))with
 |Some previous=>match Draft.draft_feedback previous with
  |Draft.Accepted _ _=>match Initialize.materialize snapshot(SS.service_state state)owner with
   |Some fresh=>SS.save_draft(Draft.Draft(N.succ(Draft.revision previous))(Draft.contents fresh)Draft.Editing "")state
   |None=>state end
  |_=>state end
 |None=>match Initialize.materialize snapshot(SS.service_state state)owner with
   |Some fresh=>let fresh:=match owner with
     |Identity.Project _|Identity.TitlePrompts=>Draft.Draft(SS.next_layer state)(Draft.contents fresh)Draft.Editing ""
     |_=>fresh end in SS.save_draft fresh state
   |None=>state end end.
Definition pending_for_editor owner pending:=match SS.purpose pending with
|SS.DraftSubmission draft _ _ _|SS.LiveConfiguration draft _ _|SS.ProjectPreference draft _ _ _ _=>
 same_editor owner(Draft.owner draft)
|_=>false end.
(** A cancelled settings editor invalidates captured session requests as well as
    workspace observations. The monotone layer ticket reserves the next draft
    revision, so a late reply cannot settle a reopened editor with the same owner. *)
Definition discard_editor owner state:=
 let authoring:=SS.authoring_state state in
 let previous:=Draft.find_draft owner(SS.drafts authoring)in
 let next_layer:=match previous with
  |Some draft=>N.max(N.succ(Draft.revision draft))(N.succ(SS.next_layer state))
  |None=>N.succ(SS.next_layer state)end in
 let authoring:=set SS.awaiting
  (fun _=>filter(fun pending=>negb(pending_for_editor owner pending))(SS.awaiting authoring))
  (set SS.drafts(fun drafts=>filter(fun draft=>negb(same_editor owner(Draft.owner draft)))drafts)authoring)in
 let services:=SS.service_state state in
 let services:=fold_left(fun services resource=>match resource_ticket resource with
  |Some ticket=>Services.forget_preparation ticket services|None=>services end)
  (filter(Services.preparation_owned owner)(Services.preparations services))services in
 let services:=Services.cancel_editor owner services in
 SS.with_next_layer next_layer(SS.with_services services(SS.with_authoring authoring state)).
Definition issue command purpose state:=
 (* DEFENSE: Two visible controls or interactive owners can submit the same
    command before its first IO receipt; only the first owns execution. *)
 if SS.pending_command command state then fail state "This command is already pending."else
 let authoring:=SS.authoring_state state in let ticket:=SS.next authoring in
 let authoring:=set SS.next(fun _=>N.succ ticket)
 (set SS.awaiting(fun pending=>SS.Pending ticket command purpose None::pending)authoring)in
 changed(SS.with_authoring authoring state)
 [emit "command"[("ticket",number ticket);("command",Schema.encode_command command)]].
Definition reserve command purpose state:=
 if SS.pending_command command state then fail state "This command is already pending."else
 let authoring:=SS.authoring_state state in let ticket:=SS.next authoring in
 let authoring:=set SS.next(fun _=>N.succ ticket)
  (set SS.awaiting(fun pending=>SS.Pending ticket command purpose None::pending)authoring)in
 keep(SS.with_authoring authoring state).
Definition adopt_service decision state:=
 changed(SS.with_services(Services.service_state decision)state)
 (map Services.encode_effect(Services.service_effects decision)).
Definition current_preparation draft state:=find(SO.matching_directory draft)(Services.preparations(SS.service_state state)).
Definition preparation_request snapshot draft intent trigger state:=
 Services.Preparation draft(SS.generation(SS.navigation_state state))(SS.next_layer state)trigger intent
 (match intent with Services.CommitPrepared=>SO.worktree_preference snapshot state draft|Services.PreviewContext=>None end).
Definition ensure_workspace snapshot draft intent trigger state:=match Draft.explicit_workspace draft with
|None=>keep state
|Some workspace=>match current_preparation draft state with
 |Some(Resource.Loaded _ _ _)|Some(Resource.Loading _ _)=>keep state
 |Some(Resource.Failed _ _ _)=>keep state
 |_=>let services:=SS.service_state state in let ticket:=Services.next_ticket services in
  let request:=preparation_request snapshot draft intent trigger state in
  let services:=Services.with_next(N.succ ticket)(Services.with_preparations
   (Resource.Loading ticket request::filter(fun resource=>negb(Services.replaceable_preparation(Draft.owner draft)resource))(Services.preparations services))services)in
  changed(SS.with_services services state)
   [Services.encode_effect(Services.ObserveDirectories ticket(Selvedge.Kernel.Codec.workspace_json workspace)(Draft.owner draft))]end end.
Definition current_command state draft:=match Draft.explicit_workspace draft with
|None=>Command.command(SS.now state)draft
|Some _=>match current_preparation draft state with
 |Some(Resource.Loaded _ _ observation)=>Command.observed_command(SS.now state)draft
   (Services.observed_workspace observation,Services.observed_guidance observation)
 |_=>None end end.
Definition current_voice_command state draft:=match Draft.explicit_workspace draft with
|None=>Command.voice_command draft
|Some _=>match current_preparation draft state with
 |Some(Resource.Loaded _ _ observation)=>Command.observed_voice_command draft(Services.observed_workspace observation,Services.observed_guidance observation)
 |_=>None end end.
Definition voice_owner (command:SS.public_command):=CommandAssessment.DirectOwner(CommandAssessment.command_identity command).
Definition new_voice_availability snapshot state owner:=let draft:=SS.current_draft state owner in
 match current_voice_command state draft with
 |Some command=>EO.admission snapshot state(voice_owner command)(Draft.revision draft)command
 |None=>EM.Unavailable "Create the cloud task before starting voice, or finish observing its workspace."end.
Definition canonical_ready snapshot state owner revision command:=
 match EO.admission snapshot state owner revision command with EM.Available=>true|EM.Unavailable _=>false end.
Definition command_owner snapshot state command:=match ObjectActions.descriptor_for_command snapshot state command with
|Some(subject,action)=>ObjectActions.action_owner subject action
|None=>CommandAssessment.DirectOwner(CommandAssessment.command_identity command)end.
Definition command_availability snapshot state command:EM.availability:=
 EO.admission snapshot state(command_owner snapshot state command)(ObjectActions.assessment_revision state)command.
Definition submission_obstruction snapshot draft state:option string:=
 if negb(Services.connected(SS.service_state state))then Some "Connect to continue."else
 if negb(SO.worktree_submission_allowed snapshot state draft)then Some "Wait for Git verification of the primary workspace before creating a worktree."else
 match EO.project_precondition snapshot state draft with
 |Some(_,_,reason)=>Some reason
 |None=>let owner:=Draft.owner draft in
 if SS.pending_editor owner state || Services.preparing owner(SS.service_state state) || Services.blocks owner(SS.service_state state)then
 Some "Wait for the current submission or file transfer to finish."else None end.
Definition issue_draft snapshot draft trigger state:=
 match submission_obstruction snapshot draft state with
 |Some reason=>fail state reason
 |None=>let owner:=Draft.owner draft in
 match current_command state draft with
 |None=>fail state "The draft is waiting for a valid command and workspace observation."
 |Some command=>if canonical_ready snapshot state(CommandAssessment.DraftOwner owner)(Draft.revision draft)command
  then match SO.worktree_preference snapshot state draft with
  |None=>issue command(SS.DraftSubmission draft(SS.generation(SS.navigation_state state))(SS.next_layer state)trigger)state
  |Some update=>if canonical_ready snapshot state(CommandAssessment.DirectOwner(CommandAssessment.command_identity update))
      (SS.generation(SS.navigation_state state))update
    then issue update(SS.ProjectPreference draft command(SS.generation(SS.navigation_state state))(SS.next_layer state)trigger)state
    else fail state "The project worktree preference has not been admitted against the current state."end
  else fail state "This action has not been admitted against the current state."end end.
Definition capture_workspace snapshot draft trigger state:=
 match submission_obstruction snapshot draft state with
 |Some reason=>fail state reason
 |None=>match current_preparation draft state with
  |Some(Resource.Loading ticket _)=>
   let request:=preparation_request snapshot draft Services.CommitPrepared trigger state in
   keep(SS.with_services(Services.with_preparations(map(fun resource=>match resource with
    |Resource.Loading actual _=>if N.eqb ticket actual then Resource.Loading actual request else resource
    |_=>resource end)(Services.preparations(SS.service_state state)))(SS.service_state state))state)
  |_=>ensure_workspace snapshot draft Services.CommitPrepared trigger state end end.
Definition submit snapshot owner trigger state:=
 let state:=ensure_draft snapshot owner state in
 match Draft.find_draft owner(SS.drafts(SS.authoring_state state))with
 |None=>fail state "The object being edited is no longer available."
 |Some draft=>match Draft.explicit_workspace draft,current_preparation draft state with
  |Some _,None|Some _,Some(Resource.Loading _ _)=>capture_workspace snapshot draft trigger state
  |Some _,Some(Resource.Failed _ _ reason)=>fail state reason
  |_,_=>issue_draft snapshot draft trigger state end end.
Definition set_mention owner mention state:=SS.with_authoring
 (set SS.mentions(fun values=>(owner,mention)::filter(fun value=>negb(same_editor owner(fst value)))values)
  (SS.authoring_state state))state.
Definition mention_for owner state:=match find(fun value=>same_editor owner(fst value))(SS.mentions(SS.authoring_state state))with
|Some value=>snd value|None=>SkillMention.Inactive end.
Definition draft_text draft:=match Draft.contents draft with
|Draft.NewTaskBody value _ _ _ _ _|Draft.MessageBody _ value _=>Some value|_=>None end.
Definition with_text value draft:=match Draft.contents draft with
|Draft.NewTaskBody previous profile reasoning configuration mode work=>Some(Draft.with_body(Draft.NewTaskBody value profile reasoning configuration mode work)draft)
|Draft.MessageBody task previous delivery=>Some(Draft.with_body(Draft.MessageBody task value delivery)draft)|_=>None end.
Definition attachment_list draft:=match Draft.contents draft with
|Draft.NewTaskBody text _ _ _ _ _|Draft.MessageBody _ text _=>Draft.text_images text
|Draft.CardBody _ _ card _ _ _=>Selvedge.Features.Domain.draft_attachments card|_=>[]end.
Definition with_attachments files draft:=match Draft.contents draft with
|Draft.NewTaskBody text _ _ _ _ _|Draft.MessageBody _ text _=>with_text(Draft.Text(Draft.text_value text)files)draft
|Draft.CardBody card revision value assist profile keep=>Some(Draft.with_body(Draft.CardBody card revision
 (Selvedge.Features.Domain.CardDraft(Selvedge.Features.Domain.draft_title value)(Selvedge.Features.Domain.draft_description value)
 (Selvedge.Features.Domain.draft_stage value)(Selvedge.Features.Domain.draft_priority value)(Selvedge.Features.Domain.draft_owner value)
 (Selvedge.Features.Domain.draft_project value)(Selvedge.Features.Domain.draft_labels value)files)assist profile keep)draft)
|_=>None end.
Definition attached snapshot owner file state:=let state:=ensure_draft snapshot owner state in
 let draft:=SS.current_draft state owner in
 if existsb(fun current=>String.eqb(asset_id current)(asset_id file))(attachment_list draft)then state else
 match with_attachments(attachment_list draft++[file])draft with Some draft=>SS.save_draft draft state|None=>state end.
Definition valid_image_attachment file:=Images.valid_image_asset
 (Images.image_json(Selvedge.Kernel.Domain.ImageAsset
  (Selvedge.Features.Domain.attachment_id file)
  (Selvedge.Features.Domain.attachment_mime file)
  (Selvedge.Features.Domain.attachment_bytes file)
  Selvedge.Kernel.Domain.ImageAuto)).
Definition admitted_upload input state:=match input with
|Services.Uploaded ticket(inr file)=>
 match find(Services.ticket_matches ticket)(Services.uploads(SS.service_state state))with
 |Some(Resource.Loading _ request)=>match Services.upload_editor request with
  |Identity.NewTask _|Identity.Message _=>if valid_image_attachment file then input else
    Services.Uploaded ticket(inl "Select a PNG, JPEG, GIF or WebP image up to 10 MiB")
  |_=>input end
 |_=>input end
|_=>input end.
Definition skill_request_current snapshot state owner request:=
 same_editor owner(SS.skill_editor request)&&match SO.workspace_for snapshot(SS.current_draft state owner)with
 |Some workspace=>Json.equal(Selvedge.Kernel.Codec.workspace_json workspace)(Selvedge.Kernel.Codec.workspace_json(SS.skill_workspace request))|None=>false end.
Definition skill_resource snapshot state owner:=find(fun resource=>match resource_request resource with
|Some request=>skill_request_current snapshot state owner request|None=>false end)(SS.skill_catalogs(SS.authoring_state state)).
Record skill_view_data:=SkillView{skill_mention:SkillMention.mention_state;skill_items:list SkillMention.skill;
 skill_loading:bool;skill_error:option string;skill_unrequested:bool}.
Definition skill_view snapshot state owner:=
 let resource:=skill_resource snapshot state owner in
 SkillView(mention_for owner state)(match resource with Some(Resource.Loaded _ _ values)=>values|_=>[]end)
 (match resource with Some(Resource.Loading _ _)=>true|_=>false end)
 (match resource with Some(Resource.Failed _ _ reason)=>Some reason|_=>match SO.workspace_for snapshot(SS.current_draft state owner)with Some _=>None|None=>Some "The selected workspace is not available."end end)
 (match resource with None|Some Resource.Dormant=>true|_=>false end).
Definition refresh_skill_catalog owner state:=
 let authoring:=SS.authoring_state state in
 SS.with_authoring(set SS.skill_catalogs(fun resources=>filter(fun resource=>match resource_request resource with
  |Some request=>negb(same_editor owner(SS.skill_editor request))|None=>true end)resources)authoring)state.
Definition load_skills snapshot owner (explicit:bool) state:=
 let state:=ensure_draft snapshot owner state in
 let draft:=SS.current_draft state owner in
 match draft_text draft,SO.workspace_for snapshot draft with
 |Some text,Some workspace=>
 let state:=if explicit then match mention_for owner state with
  |SkillMention.Suggesting _ _=>state
  |_=>refresh_skill_catalog owner(set_mention owner(SkillMention.Suggesting(SkillMention.Trigger(String.length(Draft.text_value text))(String.length(Draft.text_value text))"")0)state)end else state in
 match skill_resource snapshot state owner with Some(Resource.Loading _ _)|Some(Resource.Loaded _ _ _)=>keep state
 |_=>let authoring:=SS.authoring_state state in let ticket:=SS.next authoring in
  let request:=SS.SkillRequest owner workspace in
  let authoring:=set SS.next(fun _=>N.succ ticket)(set SS.skill_catalogs
   (fun resources=>Resource.Loading ticket request::filter(fun resource=>match resource_request resource with
    |Some request=>negb(same_editor owner(SS.skill_editor request))|None=>true end)resources)authoring)in
  changed(SS.with_authoring authoring state)
  [emit "skill_catalog"(Identity.task_observation_fields owner[("ticket",number ticket);("editor",encode_editor owner);("workspace",Selvedge.Kernel.Codec.workspace_json workspace)])]end
 |_,_=>fail state "A message and an observed workspace are required for skills."end.
Definition splice start finish insert text:=String.append(String.substring 0 start text)(String.append insert(String.substring finish(String.length text)text)).
Definition message_focus state owner:=match owner with
|Identity.Message task=>match find(fun view=>N.eqb task(Identity.task_view_task view))(Navigation.visible_task_views state)with
 |Some view=>Identity.message_key view|None=>""end
|_=>Identity.key_part(Identity.editor_key owner)"message"end.
Definition choose_skill snapshot owner path state:=
 let view:=skill_view snapshot state owner in
 match skill_mention view,draft_text(SS.current_draft state owner),find(fun skill=>String.eqb path(SkillMention.skill_path skill))(skill_items view)with
 |SkillMention.Suggesting trigger _,Some text,Some skill=>
  let inserted:=SkillMention.insert(Draft.text_value text)trigger skill in
  match with_text(Draft.Text(SkillMention.insertion_text inserted)(Draft.text_images text))(SS.current_draft state owner)with
  |Some draft=>changed(set_mention owner SkillMention.Inactive(SS.save_draft draft state))
    [focus(message_focus state owner);emit "selection_bytes"[("key",JString(message_focus state owner));("start",number(N.of_nat(SkillMention.insertion_caret inserted)));("end",number(N.of_nat(SkillMention.insertion_caret inserted)))]]
  |None=>fail state "This object does not contain a message."end
 |_,_,_=>fail state "The skill suggestion is no longer current."end.
Definition append first second:=Result(result_state second)(result_effects first++result_effects second)
 (match result_error second with Some error=>Some error|None=>result_error first end)
 (result_visible_error first||result_visible_error second).
Definition adopt_navigation snapshot decision:=
 fold_left(fun result effect=>let state:=result_state result in
 append result(match effect with
 |Navigation.Attend target=>changed state[focus target]
 |Navigation.EnsureDraft owner=>keep(reopen_draft snapshot owner state)
 |Navigation.CancelEditor owner=>keep(discard_editor owner state)
 |Navigation.Issue command purpose=>issue command purpose state
 |Navigation.FollowTaskLatest task=>match find(fun view=>N.eqb task(Identity.task_view_task view))(Navigation.visible_task_views state)with
   |Some view=>changed state[emit "follow_latest"[("key",JString(Identity.task_view_key view "timeline"))]]|None=>keep state end
 |Navigation.LocateHistoryMessage task index=>match DocumentState.find_task task snapshot with
   |None=>fail state "The history task is no longer available."
   |Some value=>match nth_error(Selvedge.Interaction.Codec.items "history" value)(N.to_nat index)with
    |None=>fail state "The history message is no longer available."
    |Some message=>changed state[emit "scroll_to_message"[("key",JString(AuditReading.history_target(DocumentState.retention_namespace(SS.document_retention state))task index message));("message_index",number index);("task_id",number task);("reader_generation",number(SS.reader_generation(Navigation.reader_for state task)))]]end end end))
 (Navigation.result_effects decision)(Result(Navigation.result_state decision)[](Navigation.result_error decision)false).
Definition draft_current snapshot state:=match Draft.find_draft(Draft.owner snapshot)(SS.drafts(SS.authoring_state state))with
|Some current=>N.eqb(Draft.revision current)(Draft.revision snapshot)|None=>false end.
Definition clear_accepted reply draft:=
 let body:=match Draft.contents draft with
 |Draft.NewTaskBody message profile reasoning configuration mode work=>Draft.NewTaskBody Draft.empty_text profile reasoning configuration mode work
 |Draft.MessageBody task message delivery=>Draft.MessageBody task Draft.empty_text delivery
 |Draft.CardBody None revision value assist profile true=>Draft.CardBody None 0
  (Selvedge.Features.Domain.CardDraft "" ""(Selvedge.Features.Domain.draft_stage value)(Selvedge.Features.Domain.draft_priority value)
   (Selvedge.Features.Domain.draft_owner value)(Selvedge.Features.Domain.draft_project value)(Selvedge.Features.Domain.draft_labels value)[])assist profile true
 |body=>body end in
 Draft.Draft(N.succ(Draft.revision draft))body(Draft.Accepted(Draft.revision draft)reply)(Draft.directory_entry draft).
Definition completion_success (outcome:sum string json):=match outcome with inr reply=>flag "ok" reply|_=>false end.
Definition completion_value (outcome:sum string json):=match outcome with inr reply=>field "result" reply|_=>None end.
Definition completion_error (outcome:sum string json):=Selvedge.Interaction.Codec.command_failure outcome.
Definition completion_message outcome:=Selvedge.Interaction.Codec.diagnostic_message(completion_error outcome).
Definition complete_draft snapshot captured navigation layer trigger outcome state:=
 let current:=draft_current captured state in
 if completion_success outcome then
 let reply:=value_or JNull(completion_value outcome)in
 let state:=if current then
   let state:=SS.save_draft(clear_accepted reply captured)state in
   match Draft.contents captured with
   |Draft.NewTaskBody _ _ _ _ _ _|Draft.MessageBody _ _ _=>
     refresh_skill_catalog(Draft.owner captured)(set_mention(Draft.owner captured)SkillMention.Inactive state)
   |_=>state end
  else state in
 let foreground:=N.eqb navigation(SS.generation(SS.navigation_state state))&&N.eqb layer(SS.next_layer state)in
 if foreground && current then match Draft.contents captured with
 |Draft.NewTaskBody _ _ _ _ _ _=>match natural_field "task_id" reply with
   |Some task=>adopt_navigation snapshot(Navigation.visit snapshot(Identity.Conversation task)state)
   |None=>fail state "Task creation did not return its task identity."end
 |Draft.MessageBody task message _=>match Command.side_question(Draft.text_value message)with
   |Some _=>if Navigation.task_visible state task then match natural_field "task_id" reply with
     |Some side=>adopt_navigation snapshot(Navigation.open_side_window side trigger state)
     |None=>fail state "Side conversation creation did not return its task identity."end else keep state
   |None=>adopt_navigation snapshot(Navigation.follow_latest task state)end
 |Draft.CardBody None _ _ _ _ true=>changed state[focus(Identity.key_part(Identity.editor_key(Identity.Card None))"title")]
 |_=>match SS.layers(SS.navigation_state state)with
   |top::_=>match SS.layer_panel top with SS.EditorPanel owner|SS.PropertyPanel owner _=>if same_editor owner(Draft.owner captured)then adopt_navigation snapshot(Navigation.close_panel state)else keep state|_=>keep state end
   |[]=>keep state end end else keep state
 else let diagnostic:=completion_error outcome in
 let state:=if current then SS.save_draft(Draft.with_feedback(Draft.Rejected(Draft.revision captured)diagnostic)captured)state else state in
 fail_diagnostic state diagnostic.
Definition complete snapshot (executed:SS.public_command) purpose outcome state:=match purpose with
|SS.DraftSubmission captured navigation layer trigger=>Some(complete_draft snapshot captured navigation layer trigger outcome state)
|SS.LiveConfiguration captured occurrence remember=>
 let remembered:=if completion_success outcome&&remember then match Draft.owner captured with
  |Identity.Message task=>match SO.task_profile task snapshot,DocumentState.find_task task snapshot with
   |Some profile,Some observed=>match (match string_field "reasoning"(Schema.encode_command executed)with Some requested=>Some requested|None=>string_field "reasoning" observed end)with
    |Some reasoning=>let key:=Selvedge.Kernel.Domain.profile_key profile in
      changed(SS.with_services(Services.with_model_preference(Some(key,reasoning))(SS.service_state state))state)
       [emit "persist_model_preference"[("profile",JString key);("reasoning",JString reasoning)]]
    |None=>keep state end|_,_=>keep state end|_=>keep state end else keep state in
 let state:=result_state remembered in
 let state:=if completion_success outcome then state else
   if draft_current captured state then SS.save_draft(Draft.with_feedback(Draft.Rejected(Draft.revision captured)(completion_error outcome))captured)state else state in
 Some(append remembered(match occurrence with
 |None=>if completion_success outcome then keep state else fail_diagnostic state(completion_error outcome)
 |Some occurrence=>match SS.layers(SS.navigation_state state)with
 |top::_=>if N.eqb occurrence(SS.layer_occurrence top)then
   if completion_success outcome then adopt_navigation snapshot(match SS.layer_decision_field top with
    |Some _=>Navigation.leave_request occurrence(Draft.owner captured)state|None=>Navigation.close_panel state end)
   else let navigation:=SS.navigation_state state in
    let diagnostic:=completion_error outcome in
    let top:=set SS.layer_pending(fun _=>false)(set SS.layer_feedback(fun _=>Some diagnostic)top)in
    fail_diagnostic(SS.with_navigation(set SS.layers(fun layers=>match layers with []=>[]|_::rest=>top::rest end)navigation)state)diagnostic
   else keep state|[]=>keep state end end))
|SS.DirectSubmission=>Some(if completion_success outcome then keep state else alert_diagnostic state(completion_error outcome))
|SS.ProjectPreference captured command generation layer trigger=>Some(if completion_success outcome then
 issue command(SS.DraftSubmission captured generation layer trigger)state
 else complete_draft snapshot captured generation layer trigger outcome state)
|_=>None end.
Definition apply_field snapshot (owner:editor) (assignment:Activity.assignment owner) state:=
 if Parameters.live_configuration owner(EM.subject_declaration(Activity.assignment_subject assignment)) && SS.pending_editor owner state
 then fail state "Wait for the current configuration change to finish."else
 let state:=ensure_draft snapshot owner state in
 let current:=SS.current_draft state owner in
 match EO.assignment_available snapshot state assignment with
 |EM.Unavailable reason=>fail state reason
 |EM.Available=>
 let field:=EM.subject_declaration(Activity.assignment_subject assignment)in
 if Parameters.live_configuration owner field then
 match Values.candidate_command snapshot(SS.now state)current assignment with
 |Some command=>if canonical_ready snapshot state(EO.candidate_owner(Activity.assignment_subject assignment)
    (Schema.encode_value(EM.subject_kind(Activity.assignment_subject assignment))(Activity.assignment_value assignment)))(Draft.revision current)command
   then issue command(SS.LiveConfiguration current None(match field with Fields.ModelProfile|Fields.ReasoningEffort=>true|_=>false end))state else fail state "This configuration change has not been admitted against the current state."
 |None=>fail state "This configuration change is not valid."end
 else match Values.apply_assignment snapshot current assignment with
 |None=>fail state "The field value is not valid for this object."
 |Some updated=>let state:=SS.save_draft updated state in
  let state:=if Parameters.field_eq_dec field Fields.MessageText then set_mention owner SkillMention.Inactive state else state in
  let state:=SS.with_services(Services.forget_assessment owner(SS.service_state state))state in
  match owner,field,Draft.contents updated with
  |Identity.NewTask _,Fields.ModelProfile,Draft.NewTaskBody _ profile reasoning _ _ _
  |Identity.NewTask _,Fields.ReasoningEffort,Draft.NewTaskBody _ profile reasoning _ _ _=>
    let state:=SS.with_services(Services.with_model_preference(Some(profile,reasoning))(SS.service_state state))state in
    let state:=match owner with Identity.NewTask None=>SS.with_authoring(set SS.draft_model_manual(fun _=>true)(SS.authoring_state state))state|_=>state end in
    changed state[emit "persist_model_preference"[("profile",JString profile);("reasoning",JString reasoning)]]
  |_,_,_=>keep state end end end.
Definition activity_owner occurrence state:=match SS.layers(SS.navigation_state state)with
|layer::_=>if N.eqb occurrence(SS.layer_occurrence layer)then match SS.layer_panel layer with
 |SS.PropertyPanel owner request=>Some(owner,request)
 |SS.EditorPanel(Identity.Project project)=>Some(Identity.Project project,Activity.PropertyActivity EM.ProjectProperty)
 |_=>None end else None|[]=>None end.
Definition apply_activity snapshot occurrence (owner:editor) (assignment:Activity.assignment owner) state:=
 if Parameters.live_configuration owner(EM.subject_declaration(Activity.assignment_subject assignment)) && SS.pending_editor owner state
 then fail state "Wait for the current configuration change to finish."else
 match activity_owner occurrence state with
 |Some(actual,request)=>if same_editor owner actual then
 let current:=SS.current_draft state owner in
 if Parameters.live_configuration owner(EM.subject_declaration(Activity.assignment_subject assignment))then
 match Values.candidate_command snapshot(SS.now state)current assignment with
 |None=>fail state "This choice cannot form a configuration command."
 |Some command=>let incoming:=Schema.encode_value(EM.subject_kind(Activity.assignment_subject assignment))(Activity.assignment_value assignment)in
  if canonical_ready snapshot state(EO.candidate_owner(Activity.assignment_subject assignment)incoming)(Draft.revision current)command then
    let navigation:=SS.navigation_state state in
    let navigation:=set SS.layers(fun layers=>match layers with []=>[]|layer::rest=>set SS.layer_pending(fun _=>true)(set SS.layer_feedback(fun _=>None)layer)::rest end)navigation in
    issue command(SS.LiveConfiguration current(Some occurrence)(match EM.subject_declaration(Activity.assignment_subject assignment)with Fields.ModelProfile|Fields.ReasoningEffort=>true|_=>false end))(SS.with_navigation navigation state)
  else fail state "This configuration choice has not been admitted against the current state."end
 else match EO.assignment_available snapshot state assignment with
 |EM.Unavailable reason=>fail state reason
 |EM.Available=>let updated:=apply_field snapshot owner assignment state in
  match EO.activity_completion snapshot state owner request with
  |EO.ApplyAndDismiss=>append updated(adopt_navigation snapshot(Navigation.close_panel(result_state updated)))
  |EO.ApplyAndReturn=>append updated(adopt_navigation snapshot(Navigation.leave_request occurrence owner(result_state updated)))
  |_=>updated end end
 else keep state|None=>keep state end.
Definition change_workspace snapshot owner change state:=
 if Parameters.editable owner Fields.WorkspaceDirectories then
 let draft:=SS.current_draft state owner in
 match change with Input.InheritWorkspace=>match SO.draft_context draft with
  |Some configuration=>let configuration:=Values.with_context_workspace None configuration in
    keep(SS.save_draft(Draft.with_body(Values.with_configuration configuration(Draft.contents draft))draft)state)
  |None=>fail state "The committed workspace cannot be inherited again."end
 |change=>match SO.workspace_for snapshot draft with
  |None=>fail state "The working directories have not been observed."
  |Some workspace=>let roots:=Selvedge.Kernel.Domain.workspace_roots workspace in
   let incoming:=match change with
    |Input.AddDirectory path=>JArray(map JString(if existsb(String.eqb path)roots then roots else roots++[path]))
    |Input.RemoveDirectory path=>JArray(map JString(filter(fun root=>negb(String.eqb path root))roots))
    |Input.ChoosePrimaryDirectory path=>JString path|_=>JNull end in
   let field:=match change with Input.ChoosePrimaryDirectory _=>Fields.WorkspacePrimary|_=>Fields.WorkspaceDirectories end in
   match Values.update_body snapshot(Draft.contents draft)field incoming with
   |Some body=>let updated:=SS.save_draft(Draft.with_body body draft)state in
    let updated:=match change with Input.AddDirectory _=>
      let updated:=SS.save_draft(set Draft.directory_entry(fun _=>"")(SS.current_draft updated owner))updated in
      SS.with_navigation(set SS.layers(fun layers=>match layers with
       |layer::rest=>match SS.layer_panel layer with
         |SS.PropertyPanel actual _|SS.EditorPanel actual=>if same_editor owner actual then set SS.layer_parameter_buffer(fun _=>None)layer::rest else layers
         |_=>layers end|[]=>[]end)(SS.navigation_state updated))updated
      |_=>updated end in keep updated
   |None=>fail state "The working directory change is not valid."end end end
 else fail state "A running task keeps its committed workspace.".
(** Git observations describe an editor's current primary directory. A failed
    observation can revoke its local-worktree choice, but cannot edit another
    draft or a primary directory selected after the request. *)
Definition unavailable_local_workspace snapshot owner path state:=
 match Draft.find_draft owner(SS.drafts(SS.authoring_state state))with
 |Some draft=>match bind(SO.workspace_for snapshot draft)Selvedge.Kernel.Domain.workspace_primary,
   Draft.contents draft with
  |Some current,Draft.NewTaskBody message profile reasoning configuration
    (Draft.ManagedWorkspace Selvedge.Kernel.WorkspaceBackend.Local)work=>
    if String.eqb current path then SS.save_draft
     (Draft.with_body(Draft.NewTaskBody message profile reasoning configuration Draft.CurrentWorkspace work)draft)state
    else state
  |_,_=>state end
 |None=>state end.
Definition workspace_git_completed snapshot input previous state:=
 match input,Services.workspace_git(SS.service_state previous)with
 |Services.WorkspaceGitCompleted ticket outcome,Resource.Loading current(owner,path)=>
   if N.eqb ticket current then match outcome with
    |inr true=>state|_=>unavailable_local_workspace snapshot owner path state end
   else state
 |_,_=>state end.
Definition service_step snapshot input state:=
 let state:=match input with
 |Services.OpenSettings=>let navigation:=SS.navigation_state state in
   let state:=match SS.layers navigation with
    |layer::rest=>match SS.layer_panel layer with SS.NavigationPanel GlobalMenu=>
      SS.with_next_layer(N.succ(SS.next_layer state))(SS.with_navigation(set SS.layers(fun _=>rest)navigation)state)
     |_=>state end|[]=>state end in
   SS.with_navigation(set SS.generation N.succ(SS.navigation_state state))state
 |Services.CloseSettings=>SS.with_navigation(set SS.generation N.succ(SS.navigation_state state))state
 |_=>state end in
 let decision:=Services.service_step(admitted_upload input state)(SS.service_state state)in
 let state:=workspace_git_completed snapshot input state
   (SS.with_services(Services.service_state decision)state)in
 let state:=match Services.attached decision with Some(owner,file)=>attached snapshot owner file state|None=>state end in
 fold_left(fun result effect=>match effect with
 |Services.DirectoryChosen owner path=>append result(change_workspace snapshot owner(Input.AddDirectory path)(result_state result))
 |_=>append result(changed(result_state result)[Services.encode_effect effect])end)
 (Services.service_effects decision)(keep state).
Definition directories_completed (snapshot:json) ticket outcome state:=
 let services:=SS.service_state state in
 match find(fun resource=>match resource with Resource.Loading actual _=>N.eqb ticket actual|_=>false end)(Services.preparations services)with
 |Some(Resource.Loading _ request)=>
  let admitted:=match outcome with inl reason=>inl reason|inr value=>match Command.admit_directories value with
   |Some(workspace,guidance)=>inr(Services.DirectoryObservation workspace guidance)
   |None=>inl "The directory observation did not contain a valid workspace and guidance."end end in
  let resources:=map(Resource.settle ticket admitted)(Services.preparations services)in
  let state:=SS.with_services(Services.with_preparations resources services)state in
  match admitted with
  |inl reason=>let captured:=Services.preparation_draft request in
    let state:=if draft_current captured state then SS.save_draft(Draft.with_feedback(Draft.WorkspaceRejected(Draft.revision captured)reason)captured)state else state in
    fail state reason
  |inr _=>keep state end
 | _=>keep state end.
Definition insert_transcript (snapshot:json) (explicit:bool) capture text state:=
 let owner:=Speech.target_editor capture in
 if SS.pending_editor owner state then
  SS.with_speech(Speech.with_notice "Wait for the current submission before inserting the transcript."(SS.speech_state state))state else
 let draft:=SS.current_draft state owner in
 match draft_text draft with
 |None=>state
 |Some message=>if explicit || N.eqb(Speech.target_revision capture)(Draft.revision draft)then
  let source:=Draft.text_value message in
  let start:=if explicit then String.length source else N.to_nat(Speech.selection_start capture)in
  let finish:=if explicit then start else N.to_nat(Speech.selection_end capture)in
  match with_text(Draft.Text(splice start finish text source)(Draft.text_images message))draft with
  |Some updated=>SS.save_draft updated(SS.with_speech(Speech.acknowledge(SS.speech_state state))state)|None=>state end
 else SS.with_speech(Speech.with_notice "The draft changed; insert the transcript explicitly."(SS.speech_state state))state end.
Definition speech_step snapshot input state:=
 let decision:=Speech.speech_step input(SS.speech_state state)in
 let state:=SS.with_speech(Speech.speech_state decision)state in
 let state:=match Speech.transcript decision with
 |Some(capture,text)=>insert_transcript snapshot(match input with Speech.InsertTranscript=>true|_=>false end)capture text state|None=>state end in
 changed state(map Speech.encode_effect(Speech.speech_effects decision)).
Definition skills_loaded ticket outcome state:=
 let admitted:=match outcome with inl reason=>inl reason|inr value=>match as_array value with
 |Some values=>match traverse SkillMention.decode_skill values with Some values=>inr values|None=>inl "The skill catalog contains an invalid entry."end
 |None=>match array_field "skills" value with Some values=>match traverse SkillMention.decode_skill values with Some values=>inr values|None=>inl "The skill catalog contains an invalid entry."end|None=>inl "The skill catalog observation is missing its entries."end end end in
 keep(SS.with_authoring(set SS.skill_catalogs(map(Resource.settle ticket admitted))(SS.authoring_state state))state).
Definition step snapshot input state:option result:=match input with
|Input.ApplyAssignment owner assignment=>Some(apply_field snapshot owner assignment state)
|Input.ActivityAssignment occurrence owner assignment=>Some(apply_activity snapshot occurrence owner assignment state)
|Input.ActivityWorkspaceChange occurrence change=>Some(match activity_owner occurrence state with Some(owner,_)=>change_workspace snapshot owner change state|None=>keep state end)
|Input.ActivityComplete occurrence=>Some(match activity_owner occurrence state with
 |Some(owner,request)=>if EO.activity_complete snapshot state owner request then
   match SS.layers(SS.navigation_state state)with
   |top::_=>match EO.activity_completion snapshot state owner request with
    |EO.CommitOrDiscard=>submit snapshot owner(SS.layer_trigger top)state
    |EO.ApplyAndDismiss=>adopt_navigation snapshot(Navigation.close_panel state)
    |EO.ReturnToOwner|EO.ApplyAndReturn=>adopt_navigation snapshot(Navigation.leave_request occurrence owner state)end
   |[]=>keep state end
   else fail state "Complete the required setting before closing this activity."|None=>keep state end)
|Input.Submit owner trigger=>Some(submit snapshot owner trigger state)
|Input.RetryWorkspace owner trigger=>let draft:=SS.current_draft state owner in
 let services:=Services.with_preparations(filter(fun resource=>negb(Services.replaceable_preparation owner resource))(Services.preparations(SS.service_state state)))(SS.service_state state)in
 Some(capture_workspace snapshot draft trigger(SS.with_services services state))
|Input.DirectoriesCompleted ticket outcome=>Some(directories_completed snapshot ticket outcome state)
|Input.ServiceInput input=>Some(service_step snapshot input state)
|Input.SpeechInput input=>Some(speech_step snapshot input state)
|Input.AppearanceRestored appearance=>Some(keep(SS.with_services(Services.with_theme appearance(SS.service_state state))state))
|Input.AttachFiles owner files=>Some(fold_left(fun result file=>append result(service_step snapshot(Services.AddFile owner file)(result_state result)))files(keep state))
|Input.RemoveAttachment owner identity=>let draft:=SS.current_draft state owner in
 Some(match with_attachments(filter(fun file=>negb(String.eqb identity(asset_id file)))(attachment_list draft))draft with Some draft=>keep(SS.save_draft draft state)|None=>keep state end)
|Input.LoadSkills owner explicit=>Some(load_skills snapshot owner explicit state)
|Input.SkillsLoaded ticket outcome=>Some(skills_loaded ticket outcome state)
|Input.SkillSelected owner path=>Some(choose_skill snapshot owner path state)
|Input.SkillRefocus owner caret finish composing=>Some(match draft_text(SS.current_draft state owner)with
 |Some text=>let mention:=SkillMention.observe_mention(Draft.text_value text)(N.to_nat caret)(N.to_nat finish)composing(mention_for owner state)in
  let state:=set_mention owner mention state in
  match mention with SkillMention.Suggesting trigger _=>
   let state:=set_mention owner(SkillMention.Suggesting trigger 0)state in
   load_skills snapshot owner false(refresh_skill_catalog owner state)
  |_=>keep state end
 |None=>keep state end)
|Input.SkillSelection owner caret finish composing=>Some(match draft_text(SS.current_draft state owner)with
 |Some text=>let mention:=SkillMention.observe_mention(Draft.text_value text)(N.to_nat caret)(N.to_nat finish)composing(mention_for owner state)in
  let previously_open:=match mention_for owner state with SkillMention.Suggesting _ _=>true|_=>false end in
  let state:=set_mention owner mention state in match mention with SkillMention.Suggesting _ _=>
   load_skills snapshot owner false(if previously_open then state else refresh_skill_catalog owner state)
  |_=>keep state end
 |None=>keep state end)
|Input.SkillMove owner offset=>let view:=skill_view snapshot state owner in
 Some(keep(set_mention owner(SkillMention.move_mention(Z.ltb offset 0)(skill_items view)(skill_mention view))state))
|Input.SkillDismiss owner=>Some(keep(set_mention owner(SkillMention.dismiss_mention(mention_for owner state))state))
|Input.ClockObserved now=>Some(keep(SS.with_now(Some now)state))
|Input.ResetTitlePrompts=>let state:=ensure_draft snapshot Identity.TitlePrompts state in
 let draft:=SS.current_draft state Identity.TitlePrompts in
 Some(match Draft.contents draft with
 |Draft.TitlePromptsBody revision _ _=>keep(SS.save_draft(Draft.with_body(Draft.TitlePromptsBody revision Selvedge.Features.Titles.instructions Selvedge.Features.Titles.instructions)draft)state)
 |_=>keep state end)
|_=>None end.
Definition visible_editors state:=
 let navigation:=SS.navigation_state state in
 let main:=match SS.location navigation with
 |Identity.Start=>[Identity.NewTask(SS.active_work navigation)]
 |_=>[]end in
 let tasks:=map(fun view=>Identity.Message(Identity.task_view_task view))(Navigation.visible_task_views state)in
 let layers:=fold_right(fun layer rest=>match SS.layer_panel layer with
 |SS.EditorPanel owner|SS.PropertyPanel owner _=>owner::rest|_=>rest end)[](SS.layers navigation)in
 fold_right(fun owner rest=>if existsb(same_editor owner)rest then rest else owner::rest)[](main++tasks++layers).
Definition resolve_creation_model snapshot state:=
 let owner:=Identity.NewTask(SS.active_work(SS.navigation_state state))in
 let state:=ensure_draft snapshot owner state in
 let draft:=SS.current_draft state owner in
 match Draft.contents draft with
 |Draft.NewTaskBody message profile reasoning configuration mode work=>
  let chosen:=match work with Some _=>true|None=>SS.draft_model_manual(SS.authoring_state state)end in
  if chosen && ModelSelection.valid_preference snapshot(profile,reasoning)then state else
  match Initialize.initial_model snapshot(SS.service_state state)with
  |Some(selected,effort)=>SS.save_draft(Draft.Draft(Draft.revision draft)
    (Draft.NewTaskBody message selected effort configuration mode work)(Draft.draft_feedback draft)(Draft.directory_entry draft))state
  |None=>state end
 |_=>state end.
Definition ensure_workspace_git snapshot state:=
 let owner:=Identity.NewTask(SS.active_work(SS.navigation_state state))in
 let services:=SS.service_state state in
 let selected:=bind(SO.workspace_for snapshot(SS.current_draft state owner))Selvedge.Kernel.Domain.workspace_primary in
 match selected with
 |None=>keep(SS.with_services(Services.with_workspace_git Resource.Dormant services)state)
 |Some path=>let current:=Services.workspace_git services in
  let matches:=match resource_request current with Some(previous,root)=>same_editor owner previous && String.eqb path root|None=>false end in
  if matches then keep state else
  let ticket:=Services.next_ticket services in
  changed(SS.with_services(Services.with_next(N.succ ticket)
    (Services.with_workspace_git(Resource.Loading ticket(owner,path))services))state)
    [Services.encode_effect(Services.ObserveWorkspaceGit ticket path owner)]end.
Definition ensure_request snapshot owner revision command state:=match natural_field "sequence" snapshot with
|None=>keep state
|Some sequence=>adopt_service(Services.ensure_assessment owner revision sequence command(SS.service_state state))state end.
Definition preparation_owner ticket command:=CommandAssessment.PreparationOwner ticket(CommandAssessment.command_identity command).
Definition assessed_command snapshot owner revision command state:option(sum string unit):=
 match natural_field "sequence" snapshot with
 |None=>None
 |Some sequence=>match find(Services.owned_assessment owner)(Services.command_assessments(SS.service_state state))with
  |Some(Resource.Loaded _ request observation)=>
   if CommandAssessment.matches owner revision sequence command request && CommandAssessment.current_owned owner revision sequence observation
   then Some(match CommandAssessment.observed_admission observation with
    |CommandAssessment.Admitted=>inr tt|CommandAssessment.Refused _ reason=>inl reason end)else None
  |Some(Resource.Failed _ request reason)=>if CommandAssessment.matches owner revision sequence command request then Some(inl reason)else None
  |_=>None end end.
Definition preparation_finished ticket state:=SS.with_services(Services.forget_preparation ticket(SS.service_state state))state.
Definition preparation_failed ticket request reason state:=
 let captured:=Services.preparation_draft request in
 let state:=preparation_finished ticket state in
 let state:=if draft_current captured state then SS.save_draft(Draft.with_feedback(Draft.Rejected(Draft.revision captured)(JString reason))captured)state else state in
 fail state reason.
Definition issue_prepared ticket request command state:=
 let captured:=Services.preparation_draft request in
 let generation:=Services.preparation_generation request in
 let layer:=Services.preparation_layer request in
 let trigger:=Services.preparation_trigger request in
 let purpose:=match Services.preparation_preference request with
 |None=>SS.DraftSubmission captured generation layer trigger
 |Some _=>SS.ProjectPreference captured command generation layer trigger end in
 issue(match Services.preparation_preference request with Some update=>update|None=>command end)
  purpose(preparation_finished ticket state).
Definition continue_preparation snapshot ticket request observation state:=
 let captured:=Services.preparation_draft request in
 match Command.observed_command(SS.now state)captured(Services.observed_workspace observation,Services.observed_guidance observation)with
 |None=>preparation_failed ticket request "The prepared draft does not form a valid command."state
 |Some command=>
  let revision:=Draft.revision captured in
  let checked:=ensure_request snapshot(preparation_owner ticket command)revision command state in
  let checked:=match Services.preparation_preference request with
   |None=>checked
   |Some update=>append checked(ensure_request snapshot(preparation_owner ticket update)revision update(result_state checked))end in
  let state:=result_state checked in
  let ready:=match assessed_command snapshot(preparation_owner ticket command)revision command state with
   |None=>keep state
   |Some(inl reason)=>preparation_failed ticket request reason state
   |Some(inr _)=>match Services.preparation_preference request with
    |None=>issue_prepared ticket request command state
    |Some update=>match assessed_command snapshot(preparation_owner ticket update)revision update state with
     |None=>keep state
     |Some(inl reason)=>preparation_failed ticket request reason state
     |Some(inr _)=>issue_prepared ticket request command state end end end in
  append checked ready end.
Definition continue_preparations snapshot state:=fold_left(fun result resource=>match resource with
 |Resource.Loaded ticket request observation=>match Services.preparation_intent_of request with
  |Services.CommitPrepared=>append result(continue_preparation snapshot ticket request observation(result_state result))
  |Services.PreviewContext=>result end
 |_=>result end)(Services.preparations(SS.service_state state))(keep state).
Definition prepare snapshot state:=
 let state:=resolve_creation_model snapshot state in
 let prepared:=fold_left(fun result owner=>let state:=ensure_draft snapshot owner(result_state result)in
 append result(ensure_workspace snapshot(SS.current_draft state owner)Services.PreviewContext "" state))
 (visible_editors state)(keep state)in
 let prepared:=append prepared(ensure_workspace_git snapshot(result_state prepared))in
 append prepared(continue_preparations snapshot(result_state prepared)).
Definition input_command snapshot state input:option SS.public_command:=
 let raw:=match input with
 |Input.BoardProfile profile=>match field "board" snapshot with
  |Some board=>option_map(fun automatic=>JObject[("op",JString "board_settings");("automatic",JBool automatic);("draft_profile",JString profile)])(bool_field "automatic" board)
  |None=>None end
 |Input.CardPlaced card revision observed status before=>Some(JObject[("op",JString "move_card");("card_id",number card);("revision",number revision);("observed_at",JString(show_natural observed));("status",JString status);("before_card",JString(match before with None=>""|Some id=>show_natural id end))])
 |Input.CardField card revision name value=>Some(JObject[("op",JString "update_card");("card_id",number card);("revision",number revision);(name,value)])
 |_=>None end in
 match raw with
 |Some raw=>Schema.decode_command command_specs raw
 |None=>match Navigation.step snapshot input state with
  |Some decision=>fold_right(fun effect rest=>match effect with Navigation.Issue command _=>Some command|_=>rest end)None(Navigation.result_effects decision)
  |None=>None end end.
Definition command_input_availability snapshot state command:EM.availability:=
 if SS.pending_command command state then EM.Unavailable "This command is already pending."else
 command_availability snapshot state command.
Definition confirmation_availability snapshot state command:EM.availability:=
 if SS.pending_command command state then EM.Unavailable "This command is already pending."else
 if Services.connected(SS.service_state state)then command_availability snapshot state command
 else EM.Unavailable "Connect to continue.".
Definition input_availability snapshot state input:EM.availability:=
 match input_command snapshot state input with
 |Some command=>match input with
  |Input.Confirm=>confirmation_availability snapshot state command
  |_=>command_input_availability snapshot state command end
 |None=>EM.Available end.
Definition refresh_input snapshot input state:=match input with
|Input.BeginVoiceNew owner=>let draft:=SS.current_draft state owner in
 match current_voice_command state draft with Some command=>ensure_request snapshot(voice_owner command)(Draft.revision draft)command state|None=>keep state end
|Input.Submit owner _=>let draft:=SS.current_draft state owner in
 if SS.pending_editor owner state then keep state else
 let checked:=match current_command state draft with Some command=>ensure_request snapshot(CommandAssessment.DraftOwner owner)(Draft.revision draft)command state|None=>keep state end in
 match SO.worktree_preference snapshot state draft with
 |Some update=>append checked(ensure_request snapshot(CommandAssessment.DirectOwner(CommandAssessment.command_identity update))
   (SS.generation(SS.navigation_state state))update(result_state checked))
 |None=>checked end
|Input.ActivityAssignment _ owner assignment|Input.ApplyAssignment owner assignment=>
 let current:=SS.current_draft state owner in
 if Parameters.live_configuration owner(EM.subject_declaration(Activity.assignment_subject assignment))then
 match Values.candidate_command snapshot(SS.now state)current assignment with
 |Some command=>ensure_request snapshot(EO.candidate_owner(Activity.assignment_subject assignment)
 (Schema.encode_value(EM.subject_kind(Activity.assignment_subject assignment))(Activity.assignment_value assignment)))(Draft.revision current)command state|None=>keep state end else keep state
|Input.MenuAction subject key _|Input.RetryMenuAssessment subject key _=>match ObjectActions.resolve snapshot state subject key with
 |Some action=>match ObjectActions.command action with Some command=>ensure_request snapshot(ObjectActions.action_owner subject action)(ObjectActions.assessment_revision state)command state|None=>keep state end|None=>keep state end
|Input.Command command|Input.Confirmation command _ _ _=>ensure_request snapshot(command_owner snapshot state command)(ObjectActions.assessment_revision state)command state
|Input.Confirm=>match SS.layers(SS.navigation_state state)with
 |layer::_=>match SS.layer_panel layer with SS.Confirmation command _ _=>ensure_request snapshot(command_owner snapshot state command)(ObjectActions.assessment_revision state)command state|_=>keep state end|[]=>keep state end
|_=>match input_command snapshot state input with
 |Some command=>ensure_request snapshot(command_owner snapshot state command)(ObjectActions.assessment_revision state)command state
 |None=>keep state end end.
Definition refresh snapshot inputs state:=fold_left(fun result input=>append result(refresh_input snapshot input(result_state result)))inputs(keep state).
