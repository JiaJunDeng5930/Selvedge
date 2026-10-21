From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema TextJson.
From Selvedge.Interaction Require Import Codec Identity Forms Experience ExperienceObservation
  ExperienceAssessment Activities ApplicationState Input Scene SceneBuilders.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition value_text value := match value with
| JString value => value | JNull => "Use default" | JBool true => "Enabled"
| JBool false => "Disabled" | _ => TextJson.render_json value end.
Definition information_text value := match value with
| Present value => value_text value | OptionalAbsence => "Not set"
| RequiredAbsence reason | Unavailable reason | NotApplicable reason => reason end.
Definition provenance_text := provenance_description.
Definition subject_label {e} (subject : subject e) := label(subject_description subject).
Definition subject_attributes {e} (subject : subject e) := JObject [
 ("data-subject",JString(subject_key subject));
 ("data-owner",JString(object_key(subject_object subject)))].
Definition readonly_observation {e} prefix (observed : observation e) :=
 let subject:=observed_subject observed in
 node Scene.Field_role (prefix++"/"++subject_name subject)
  [("label",JsonProperty(JString(subject_label subject)));
   ("specification",FieldProperty(Schema.Field(subject_name subject)KText));
   ("value",JsonProperty(JString(information_text(observed_information observed))));
   ("attrs",JsonProperty(subject_attributes subject))] [].
Definition source_entry {e} occurrence (observed : observation e) :=
 let name:=subject_name(observed_subject observed)in
 let target:=SourceView name in
 button(view_entry_key e occurrence target) "Source"
  (invoke(Input.ActivityView occurrence target))false.
Definition source_details {e} occurrence (observed : observation e) :=
 let key:=view_entry_key e occurrence(SourceView(subject_name(observed_subject observed)))in
 group key [readonly_observation key observed;
  text_node(key++"/provenance")(provenance_text(observed_provenance observed))].
Definition property_entry d world committed family :=
 match observe_property d world committed family with
 |None=>[]
 |Some property=>let observed:=principal property in
  match observed_information observed with NotApplicable _=>[]|_=>
   let key:=(editor_key(owner d)++"/property/"++family_name family)%string in
   [Scene.ActionButton key
    [("label",JString(subject_label(observed_subject observed)));
     ("layout",JString "setting-entry");("attrs",subject_attributes(observed_subject observed))]
    (Some(Input.OpenActivity(owner d)(match family with PermissionFamily=>Explain family|_=>Compare family end)key))false
    [text_node(key++"/value")(information_text(observed_information observed))]]
  end
 end.
Definition obstruction_scene {e} (identity:action_identity e) index (obstruction:obstruction e) :=
 let key:=(action_key identity++"/obstruction/"++show_natural(N.of_nat index))%string in
 let attrs:=JObject[("data-action",JString(action_key identity));("data-code",JString(obstruction_code obstruction))]in
 node Scene.Group_role key[("attrs",JsonProperty attrs)]
  (text_node(key++"/reason")(obstruction_message obstruction)::
   if obstruction_actionable obstruction then
    match obstruction_target obstruction with
    |RepairField subject=>[button(key++"/repair")("Review "++subject_label subject)
      (invoke(Input.RepairSubject e(action_revision identity)(subject_name subject)(key++"/repair")))false]
    |RepairEditor=>if String.eqb(obstruction_code obstruction)"assessment_failed"then
      [button(key++"/retry")"Retry availability check"(invoke(Input.ServiceInput(Services.RetryAssessment e)))false]
      else [] end
   else []).
Definition assessment_scene {e} (assessed:assessment e) :=
 let requirements:=assessment_obstructions assessed in
 map(fun '(index,obstruction)=>obstruction_scene(assessment_identity assessed)index obstruction)
  (combine(seq 0(List.length requirements))requirements).
Definition alternative_scene {e} occurrence (decision:decision e)
    index (candidate:alternative(decision_subject decision)) :=
 let subject:=decision_subject decision in
 let value:=encode_value(subject_kind subject)(alternative_value candidate)in
 let selected:=match decision_selected decision with
  |Some selected=>Json.equal value(encode_value _ selected)|None=>false end in
 let key:=(view_entry_key e occurrence(DecisionView(subject_name subject))++"/choice/"++show_natural(N.of_nat index))%string in
 node Scene.Group_role(key++"/row")[("layout",JsonProperty(JString "activity-row"))]
  [Scene.ActionButton key
    [("label",JString(alternative_label candidate));("attrs",JObject
      [("aria-pressed",JString(if selected then "true"else "false"));
       ("data-subject",JString(subject_key subject))])]
    (Some(Input.ActivitySelect occurrence(subject_name subject)value))
    (match alternative_refusal candidate with None=>false|Some _=>true end)[];
   text_node(key++"/explanation")(alternative_explanation candidate);
   text_node(key++"/refusal")(match alternative_refusal candidate with None=>""|Some reason=>reason end)].
Definition filtered_choices {e} occurrence (decision:decision e) query :=
 let candidates:=visible_alternatives decision query in
 map(fun '(index,candidate)=>alternative_scene occurrence decision index candidate)
  (combine(seq 0(List.length candidates))candidates).
Definition decision_choices {e} occurrence (decision:decision e) :=
 map(fun '(index,candidate)=>alternative_scene occurrence decision index candidate)
  (combine(seq 0(List.length(decision_alternatives decision)))(decision_alternatives decision)).
Definition information_entry {e} (include_source:bool) occurrence (activity:activity e) (observed:observation e) :=
 let subject:=observed_subject observed in
 let name:=subject_name subject in
 let decision:=find(fun decision=>String.eqb name(subject_name(decision_subject decision)))(activity_decisions activity)in
 let parameter:=find(fun parameter=>String.eqb name(subject_name(fst parameter)))(activity_parameters activity)in
 let target:=match decision,parameter with
 |Some _,_=>Some(DecisionView name)
 |None,Some(_,OpenEntry)=>Some(ParameterView name(information_text(observed_information observed)))
 |_,_=>None end in
 let key:=view_entry_key e occurrence(DecisionView name)in
 group(key++"/entry")
  ((match target with
   |None=>[readonly_observation key observed]
   |Some target=>[Scene.ActionButton(view_entry_key e occurrence target)
     [("label",JString(subject_label subject));("layout",JString "setting-entry");("attrs",subject_attributes subject)]
     (Some(Input.ActivityView occurrence target))false
     [text_node(key++"/value")(information_text(observed_information observed))]]end)++
   if include_source then [source_entry occurrence observed]else []).
Definition principal_information {e} occurrence (activity:activity e) :=
 match activity_group activity with
 |None=>[]
 |Some group=>let name:=subject_name(decision_subject(root_decision group))in
  flat_map(fun observed=>
   if String.eqb name(subject_name(observed_subject observed))then []else
   match observed_information observed with NotApplicable _=>[]|_=>[information_entry false occurrence activity observed]end)
   (activity_information activity)
 end.
Definition activity_label {e} request (activity:activity e) := match request with
|EditObject=>match e with Project None=>"New project"|Project(Some _)=>"Edit project"
 |Agent None=>"New agent"|Agent(Some _)=>"Edit agent"|Card None=>"New card"|Card(Some _)=>"Edit card"
 |TaskGraph None _=>"New task graph"|TaskGraph(Some _) _=>"Edit task graph"
 |WorkName _=>"Rename Work"|TitlePrompts=>"Title generation"|Fork _=>"Fork task"
 |Compact _=>"Compact history"|Message _=>"Message"|Execution _=>"Execution settings"|NewTask _=>"New task"end
|_=>match activity_property activity with Some property=>subject_label(observed_subject(principal property))|None=>"Settings"end end.
Definition view_label {e} request (activity:activity e) (view:admitted_view e) :=
 match admitted_subject view with Some subject=>subject_label subject|None=>activity_label request activity end.
Definition return_control e occurrence :=
 button(view_entry_key e occurrence PrincipalView++"/back")"Back"(invoke(Input.ActivityView occurrence PrincipalView))false.
Definition directory_collection d world occurrence :=
 let e:=owner d in
 let key:=(editor_key e++"/roots")%string in
 let workspace:=value_or JNull(resolved_workspace d world)in
 let paths:=flat_map(fun value=>match as_string value with Some value=>[value]|None=>[]end)(items "roots" workspace)in
 let primary:=text "primary_root" workspace in
 node Scene.Group_role key[("label",JsonProperty(JString "Workspace directories"));
  ("attrs",JsonProperty(JObject[("tabindex",JString "-1")]))]
  [heading(key++"/title")"Workspace directories";
   node Scene.ListView_role(key++"/entries")[]
    (map(fun path=>group(key++"/"++path)
     [text_node(key++"/"++path++"/path")path;
      Scene.ActionButton(key++"/"++path++"/primary")
       [("label",JString "Primary directory");("attrs",JObject[("aria-pressed",JString(if String.eqb path primary then "true"else "false"))])]
       (Some(Input.ActivityWorkspaceChange occurrence(ChoosePrimary path)))false[];
      button(key++"/"++path++"/remove")"Remove"(invoke(Input.ActivityWorkspaceChange occurrence(RemoveDirectory path)))false])paths);
   node Scene.Group_role(editor_key e++"/primary_root")
    [("attrs",JsonProperty(JObject[("tabindex",JString "-1")]))]
    [text_node(key++"/current-primary")("Primary directory: "++primary)]] .
Definition workspace_editor (field_view:draft->json->ApplicationState.state->form_field->Scene.scene Input.input)
    (d:draft) world s occurrence :=
 let e:=owner d in
 let entry:=filter(fun f=>String.eqb(field_name(specification f))"directory_entry")(form_fields e)in
 [directory_collection d world occurrence]++
 (if workspace_inheritable e&&negb(workspace_inherited d)then
  [button(editor_key e++"/directory/inherit")"Use inherited workspace"(invoke(Input.ActivityWorkspaceChange occurrence UseInheritedWorkspace))false]else [])++
 map(field_view d world s)entry++
 [button(editor_key e++"/directory/add")"Add directory"(invoke(Input.ActivityWorkspaceChange occurrence AddDirectory))false;
  button(editor_key e++"/directory/clear")"Clear directory entry"(invoke(Input.ActivityWorkspaceChange occurrence ClearDirectoryEntry))false].
Definition project_editor (field_view:draft->json->ApplicationState.state->form_field->Scene.scene Input.input)
    (d:draft) world s occurrence (assessed:assessment(owner d)) (original:option json) :=
 let e:=owner d in
 let fields:=filter(fun f=>negb(existsb(String.eqb(field_name(specification f)))["roots";"primary_root";"directory_entry"])) (form_fields e)in
 node Scene.Form_role(editor_key e++"/activity/"++show_natural occurrence++"/edit")
  [("label",JsonProperty(JString "Project settings"));("action",InputProperty(invoke(Input.ActivityComplete occurrence)))]
  ((match original with None=>[]|Some original=>[text_node(editor_key e++"/original")("Saved project: "++text "name" original)]end)++
   map(field_view d world s)fields++workspace_editor field_view d world s occurrence++feedback_scene d++assessment_scene assessed++
   [button(view_entry_key e occurrence InspectionView)"Details"(invoke(Input.ActivityView occurrence InspectionView))false;
    button(editor_key e++"/activity/save")"Save"(invoke(Input.ActivityComplete occurrence))(negb(can_prepare assessed));
    button(editor_key e++"/activity/cancel")"Cancel"(invoke Input.ClosePanel)false]).
Definition render_activity
    (field_view:draft->json->ApplicationState.state->form_field->Scene.scene Input.input)
    (ordinary_form:editor->json->ApplicationState.state->Scene.scene Input.input)
    e request intent occurrence trigger world s :=
 match find_draft e s with
 |None=>text_node "activity/unavailable" "This editor is no longer available"
 |Some d=>match build_activity request d world(service_state s)(editor_pending e s)with
  |None=>text_node "activity/unavailable" "This property is no longer available"
  |Some activity=>match admit_view activity intent with
   |None=>text_node "activity/unavailable" "This view is no longer available"
   |Some view=>let key:=(editor_key e++"/activity/"++show_natural occurrence)%string in
    let children:=match intent with
    |PrincipalView=>match activity_group activity,activity_editing activity with
      |Some group,_=>(match request with
       |Compare WorkspaceFamily|Explain WorkspaceFamily=>workspace_editor field_view d world s occurrence++
          (match activity_property activity with None=>[]|Some property=>[source_entry occurrence(principal property)]end)
       |_=>decision_choices occurrence(root_decision group)++(match request with Compare _=>principal_information occurrence activity|_=>[]end)end)++
       [button(view_entry_key e occurrence InspectionView)"Details"(invoke(Input.ActivityView occurrence InspectionView))false]
      |_,Some edit=>match e with Project _=>[project_editor field_view d world s occurrence(activity_assessment activity)(editing_original edit)]
        |_=>[ordinary_form e world s;button(view_entry_key e occurrence InspectionView)"Details"(invoke(Input.ActivityView occurrence InspectionView))false;button(key++"/close")"Cancel"(invoke Input.ClosePanel)false]end
      |_,_=>[]end
    |SearchView query=>match activity_group activity with None=>[]|Some group=>
      [node Scene.Field_role(key++"/search")[("label",JsonProperty(JString "Search models"));
        ("specification",FieldProperty(Schema.Field "query" KText));("value",JsonProperty(JString query));
        ("action",InputProperty(invoke(Input.ActivitySearch occurrence ""))) ][]]++
      filtered_choices occurrence(root_decision group)query++principal_information occurrence activity++
      [button(view_entry_key e occurrence InspectionView)"Details"(invoke(Input.ActivityView occurrence InspectionView))false]end
    |InspectionView=>return_control e occurrence::map(information_entry true occurrence activity)(activity_information activity)
    |DecisionView name=>return_control e occurrence::
       flat_map(fun decision=>if String.eqb name(subject_name(decision_subject decision))then decision_choices occurrence decision else [])(activity_decisions activity)
    |ParameterView name buffer=>[return_control e occurrence;
       node Scene.Field_role(view_entry_key e occurrence intent++"/value")
        [("label",JsonProperty(JString(view_label request activity view)));
         ("specification",FieldProperty(Schema.Field name KText));("value",JsonProperty(JString buffer));
         ("action",InputProperty(invoke(Input.ActivityParameter occurrence "")))][];
       button(key++"/apply")"Apply"(invoke(Input.ActivityComplete occurrence))(match complete_parameter activity name buffer world with Some _=>false|None=>true end)]
    |SourceView name=>return_control e occurrence::
      flat_map(fun observed=>if String.eqb name(subject_name(observed_subject observed))then [source_details occurrence observed]else [])(activity_information activity)
    end in
    node Scene.Dialog_role(activity_panel_key e occurrence)
     [("label",JsonProperty(JString(view_label request activity view)));
      ("layout",JsonProperty(JString(match intent,request with SourceView _,_=>"anchored-menu"|_,EditObject=>"compound-editor"|_,_=>"anchored-menu"end)));
      ("attrs",JsonProperty(JObject[("data-anchor",JString trigger)]));("dismiss_action",InputProperty(invoke Input.ClosePanel))]
     ((match intent,request with PrincipalView,Compare _=>[]|_,_=>[heading(key++"/title")(view_label request activity view)]end)++children)
   end end end.
