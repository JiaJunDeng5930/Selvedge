From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema.
From Selvedge.Kernel Require Import Commands Streams.
From Selvedge.Features Require BoardFilter.
From Selvedge.Interaction.Interactive Require Types State Codec.
From Selvedge.Interaction.Interactive Require Bounds.
From Selvedge.Interaction Require Import Codec Identity Services Forms Speech SkillMention Resource Origin Activities.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Definition public_command := command_value command_specs.
Inductive panel := ActivityPanel(e:editor)(request:activity_request)(view:view_intent)(occurrence:N)(trigger:string)
| NavigationPanel(kind:navigation_panel)(trigger:string)
| ObjectActionsPanel(subject:menu_subject)(trigger:string)
| InformationPanel(kind:string)(subject:json)(trigger:string)
| Confirmation(command:public_command)(caption:string)(destination:route)(trigger:string)(feedback:option string).
Definition panel_trigger value := match value with
 |ActivityPanel _ _ _ _ trigger|NavigationPanel _ trigger|ObjectActionsPanel _ trigger
 |InformationPanel _ _ trigger|Confirmation _ _ _ trigger _=>trigger end.
Record side_presentation := SideWindow { window_task:N; window_trigger:string }.
Definition encode_side value := match value with None=>JNull|Some window=>JObject[("task",number(window_task window));("trigger",JString(window_trigger window))]end.
Definition decode_side source := match source with JNull=>Some None|_=>task<-natural_field "task" source;;trigger<-string_field "trigger" source;;Some(Some(SideWindow task trigger))end.
Record navigation := Navigation { location:route; active_work:option N; visits:list(option N*route); expanded:bool; generation:N; layers:list panel; side_window:option side_presentation }.
Definition side_task n := option_map window_task(side_window n).
Inductive pending_purpose := DraftSubmission(snapshot:draft)(navigation_generation:N)(trigger:string)
| ConfirmationSubmission(navigation_generation:N)
| ActivitySelection(snapshot:draft)(view_occurrence:N)
| ProjectPreference(snapshot:draft)(prepared:public_command)(navigation_generation:N)(trigger:string)
| LanguageSubmission(owner:Selvedge.Interaction.Interactive.Types.owner)(path:string)(language_ticket:N)
| SideCreation(parent navigation_generation:N)(trigger:string)
| SearchSubmission(query:string)(project work:option N) | WorkCreation(navigation_generation:N) | ExecutionSelection | DirectSubmission.
Record pending := Pending { ticket:N; accepted_command:public_command; purpose:pending_purpose }.
Record search := Search { keyword:string; project_filter:option N; work_filter:option N; search_result:option json }.
Record skill_request := SkillRequest { skill_editor:editor; skill_workspace:json }.
Record authoring := Authoring { drafts:list draft; next:N; awaiting:list pending; history_search:search; skill_catalogs:list(resource skill_request(list SkillMention.skill)); mentions:list(editor*SkillMention.mention_state) }.
Record reader := Reader { reading_task:N; disclosures:list(N*N*bool) }.
Record document_fence := DocumentFence { fence_ordinal:N; fence_code:string; fence_closed:bool }.
Record document_lifetime := DocumentLifetime {
 document_namespace:string; document_viewer:N; document_origin:Origin.output_origin;
 document_epoch:N; document_source:string; document_ending:Selvedge.Interaction.Interactive.Types.ending;
 document_archived:bool; document_revealed:bool; document_observed_prefix:nat; document_observations:list document_fence }.
Definition document_fences stamp := map fence_ordinal(document_observations stamp).
Definition document_identity stamp:=Origin.content_key(document_namespace stamp)(document_viewer stamp)(document_origin stamp).
Record retention := Retention { retention_namespace:string; retention_next_epoch:N; retention_documents:list document_lifetime; retention_discarded:list(N*N) }.
Record state := State { navigation_state:navigation; authoring_state:authoring; service_state:services; speech_state:speech; stream_state:Streams.state; readers:list reader; interactive_state:Selvedge.Interaction.Interactive.State.state; board_selection:BoardFilter.filter; document_retention:retention; collapsed_projects:list N }.
Definition initial := State(Navigation Start None[]true 0[]None)(Authoring[new_draft(NewTask None)]0[](Search "" None None None)[][])Services.initial Speech.initial[][]Selvedge.Interaction.Interactive.State.initial BoardFilter.empty(Retention "" 1[][])[].
Definition with_navigation value s := set navigation_state (fun _ => value) s.
Definition with_authoring value s := set authoring_state (fun _ => value) s.
Definition with_services value s := set service_state (fun _ => value) s.
Definition with_speech value s := set speech_state (fun _ => value) s.
Definition with_streams value s := set stream_state (fun _ => value) s.
Definition with_readers value s := set readers (fun _ => value) s.
Definition with_interactive value s := set interactive_state (fun _ => value) s.
Definition with_board_selection value s := set board_selection (fun _ => value) s.
Definition with_collapsed_projects value s := set collapsed_projects (fun _ => value) s.
Definition document_lifetimes s := retention_documents(document_retention s).
Definition discarded_outputs s := retention_discarded(document_retention s).
Definition with_retention value s := set document_retention (fun _ => value) s.
Definition with_document_lifetimes values s := let r:=document_retention s in with_retention(Retention(retention_namespace r)(retention_next_epoch r)values(discarded_outputs s))s.
Definition epoch_for_key key s := match find(fun stamp=>String.eqb key(document_identity stamp))(document_lifetimes s)with Some stamp=>document_epoch stamp|None=>0 end.
Definition encode_document_lifetime d:=JObject[
 ("key",JString(document_identity d));("viewer",number(document_viewer d));("origin",Origin.encode_origin(document_origin d));
 ("epoch",number(document_epoch d));("source",JString(document_source d));("ending",JString(Selvedge.Interaction.Interactive.Types.ending_name(document_ending d)));
 ("archived",JBool(document_archived d));("revealed",JBool(document_revealed d));("observed_prefix",number(N.of_nat(document_observed_prefix d)));
 ("fences",JArray(map(fun f=>JObject[("ordinal",number(fence_ordinal f));("code",JString(fence_code f));("closed",JBool(fence_closed f))])(document_observations d)))].
Definition decode_document_lifetime namespace j:=key<-string_field "key" j;;viewer<-natural_field "viewer" j;;origin<-bind(field "origin" j)Origin.decode_origin;;
 epoch<-natural_field "epoch" j;;source<-string_field "source" j;;ending<-bind(string_field "ending" j)Selvedge.Interaction.Interactive.Types.decode_ending;;
 archived<-bool_field "archived" j;;revealed<-bool_field "revealed" j;;observed<-natural_field "observed_prefix" j;;
 fences<-list_field(fun f=>ordinal<-natural_field "ordinal" f;;code<-string_field "code" f;;closed<-bool_field "closed" f;;Some(DocumentFence ordinal code closed))"fences" j;;
 let stamp:=DocumentLifetime namespace viewer origin epoch source ending archived revealed(N.to_nat observed)fences in
 (* DEFENSE: The public state carries a convenient derived key; it cannot
    override the namespace, viewer or provenance decoded for the document. *)
 if String.eqb key(document_identity stamp)then Some stamp else None.
Definition encode_retention r:=JObject[("namespace",JString(retention_namespace r));("next_epoch",number(retention_next_epoch r));("documents",JArray(map encode_document_lifetime(retention_documents r)));
 ("discarded",JArray(map(fun '(task,count)=>JArray[number task;number count])(retention_discarded r)))].
Definition valid_document_lifetime namespace next_epoch d:=
 Origin.interactive_origin(document_origin d)&&
 String.eqb namespace(document_namespace d)&&
 N.ltb(document_epoch d)next_epoch&&negb(N.eqb(document_epoch d)0)&&
 Nat.leb(document_observed_prefix d)(String.length(document_source d))&&
 Nat.leb(List.length(document_observations d))Bounds.interactive_fences_per_document&&
 Nat.eqb(List.length(nodup N.eq_dec(document_fences d)))(List.length(document_fences d))&&
 (negb(document_archived d)||match document_ending d with Selvedge.Interaction.Interactive.Types.Interrupted=>true|_=>false end).
Definition valid_retention r:=
 (Origin.valid_namespace(retention_namespace r)||
  (String.eqb(retention_namespace r)""&&match retention_documents r,retention_discarded r with [],[]=>true|_,_=>false end))&&
 negb(N.eqb(retention_next_epoch r)0)&&Schema.unique_names(map document_identity(retention_documents r))&&
 forallb(valid_document_lifetime(retention_namespace r)(retention_next_epoch r))(retention_documents r).
Definition decode_retention j:=namespace<-string_field "namespace" j;;next_epoch<-natural_field "next_epoch" j;;documents<-list_field(decode_document_lifetime namespace)"documents" j;;
 discarded<-list_field(fun j=>match j with JArray[a;b]=>a<-natural a;;b<-natural b;;Some(a,b)|_=>None end)"discarded" j;;
 let r:=Retention namespace next_epoch documents discarded in
 (* DEFENSE: Public calls decode client state; forged epochs, duplicate owners or
    prefixes beyond the actual source must not enter the lifetime allocator. *)
 if valid_retention r then Some r else None.
Definition find_draft e s := find(fun d=>same_editor e(owner d))(drafts(authoring_state s)).
Definition save_draft d s := let a:=authoring_state s in with_authoring(Authoring(d::filter(fun old=>negb(same_editor(owner d)(owner old)))(drafts a))(next a)(awaiting a)(history_search a)(skill_catalogs a)(mentions a))s.
Definition set_pending ps n s := let a:=authoring_state s in with_authoring(Authoring(drafts a)n ps(history_search a)(skill_catalogs a)(mentions a))s.
Definition set_search search s := let a:=authoring_state s in with_authoring(Authoring(drafts a)(next a)(awaiting a)search(skill_catalogs a)(mentions a))s.
Definition editor_pending e s := existsb(fun p=>match purpose p with DraftSubmission d _ _|ProjectPreference d _ _ _|ActivitySelection d _=>same_editor e(owner d)|_=>false end)(awaiting(authoring_state s)).
Definition visible_tasks s :=
  let primary:=match location(navigation_state s)with Conversation t=>[t]|_=>[]end in
  match side_task(navigation_state s)with None=>primary|Some t=>if existsb(N.eqb t)primary then primary else primary++[t]end.
Definition find_world field_name id_key id world := find(fun j=>match natural_field id_key j with Some n=>N.eqb id n|None=>false end)(items field_name world).
Definition find_task id world := find_world "tasks" "id" id world.
Definition find_project id world := find_world "projects" "project_id" id world.
Definition find_work id world := find_world "works" "work_id" id world.
Definition first_profile world := match Activities.model_catalog world with []=>None|profile::_=>Some(Selvedge.Kernel.Domain.profile_key profile)end.
Definition profile_choices world := map(fun p=>JObject[("value",value_or JNull(field "key" p));("label",JString(text "name" p))])(items "profiles" world).
Definition task_belongs work task world := match find_task task world with Some found=>match work with None=>true|Some w=>match natural_field "work_id" found with Some id=>N.eqb w id|None=>false end end|None=>false end.
Definition record_visit (work:option N) (r:route) (visits:list(option N*route)) := (work,r)::filter(fun v=>negb(match work,fst v with None,None=>true|Some a,Some b=>N.eqb a b|_,_=>false end))visits.
Definition same_scope a b:=match a,b with None,None=>true|Some a,Some b=>N.eqb a b|_,_=>false end.
Definition information_panel_key (kind:string) (subject:json) : string :=
 String.append "panel/" (String.append kind
  (if String.eqb kind "task_details"then match natural_field(if String.eqb kind "task_details"then "task_id"else "card_id")subject with
   |Some task=>String.append "/task/"(show_natural task)|None=>""end else "")).
Definition encode_panel p := match p with
|ActivityPanel e request view occurrence trigger=>JObject[("kind",JString "activity");("editor",encode_editor e);("request",encode_request request);("view",encode_view view);("occurrence",number occurrence);("trigger",JString trigger)]
|ObjectActionsPanel subject trigger=>JObject[("kind",JString "object_actions");("subject",encode_menu_subject subject);("trigger",JString trigger)]
|NavigationPanel kind trigger=>JObject[("kind",JString "navigation");("navigation",JString(navigation_panel_name kind));("trigger",JString trigger)]
|InformationPanel kind subject trigger=>JObject[("kind",JString kind);("subject",subject);("trigger",JString trigger)]
|Confirmation c caption destination trigger feedback=>JObject[("kind",JString "confirmation");("command",encode_command c);("caption",JString caption);("destination",encode_route destination);("trigger",JString trigger);("feedback",match feedback with None=>JNull|Some reason=>JString reason end)]end.
Definition decode_panel j := trigger<-string_field "trigger" j;;match string_field "kind" j with
|Some "activity"=>e<-bind(field "editor" j)decode_editor;;request<-bind(field "request" j)decode_request;;view<-bind(field "view" j)decode_view;;occurrence<-natural_field "occurrence" j;;Some(ActivityPanel e request view occurrence trigger)
|Some "object_actions"=>subject<-bind(field "subject" j)decode_menu_subject;;Some(ObjectActionsPanel subject trigger)
|Some "navigation"=>kind<-bind(string_field "navigation" j)decode_navigation_panel;;Some(NavigationPanel kind trigger)
|Some "confirmation"=>c<-bind(field "command" j)(decode_command command_specs);;caption<-string_field "caption" j;;r<-bind(field "destination" j)decode_route;;feedback<-field "feedback" j;;feedback<-(match feedback with JNull=>Some None|JString reason=>Some(Some reason)|_=>None end);;Some(Confirmation c caption r trigger feedback)
|Some kind=>subject<-field "subject" j;;Some(InformationPanel kind subject trigger)|_=>None end.
Definition encode_navigation n := JObject[("route",encode_route(location n));("work",optional_id(active_work n));("visits",JArray(map(fun v=>JObject[("work",optional_id(fst v));("route",encode_route(snd v))])(visits n)));("expanded",JBool(expanded n));("generation",number(generation n));("layers",JArray(map encode_panel(layers n)));("side",encode_side(side_window n))].
Definition decode_visit j := w<-id_field "work" j;;r<-bind(field "route" j)decode_route;;Some(w,r).
Definition decode_navigation j := r<-bind(field "route" j)decode_route;;w<-id_field "work" j;;vs<-list_field decode_visit "visits" j;;e<-bool_field "expanded" j;;g<-natural_field "generation" j;;ls<-list_field decode_panel "layers" j;;side<-bind(field "side" j)decode_side;;Some(Navigation r w vs e g ls side).
Definition encode_purpose p:=match p with DraftSubmission d g trigger=>JObject[("kind",JString "draft");("draft",encode_draft d);("generation",number g);("trigger",JString trigger)]
|ProjectPreference d prepared g trigger=>JObject[("kind",JString "project_preference");("draft",encode_draft d);("command",encode_command prepared);("generation",number g);("trigger",JString trigger)]
|ConfirmationSubmission occurrence=>JObject[("kind",JString "confirmation");("generation",number occurrence)]
|ActivitySelection d occurrence=>JObject[("kind",JString "activity_selection");("draft",encode_draft d);("occurrence",number occurrence)]
|SideCreation parent g trigger=>JObject[("kind",JString "side");("parent",number parent);("generation",number g);("trigger",JString trigger)]
|SearchSubmission q p w=>JObject[("kind",JString "search");("query",JString q);("project",optional_id p);("work",optional_id w)]
|LanguageSubmission owner path ticket=>JObject[("kind",JString "language");("owner",Selvedge.Interaction.Interactive.Types.encode_owner owner);("path",JString path);("ticket",number ticket)]
|WorkCreation g=>JObject[("kind",JString "work");("generation",number g)]
|ExecutionSelection=>JObject[("kind",JString "execution_selection")]|DirectSubmission=>JObject[("kind",JString "direct")]end.
Definition decode_purpose j:=match string_field "kind" j with
|Some "draft"=>d<-bind(field "draft" j)decode_draft;;g<-natural_field "generation" j;;trigger<-string_field "trigger" j;;Some(DraftSubmission d g trigger)
|Some "project_preference"=>d<-bind(field "draft" j)decode_draft;;prepared<-bind(field "command" j)(decode_command command_specs);;g<-natural_field "generation" j;;trigger<-string_field "trigger" j;;Some(ProjectPreference d prepared g trigger)
|Some "confirmation"=>option_map ConfirmationSubmission(natural_field "generation" j)
|Some "activity_selection"=>d<-bind(field "draft" j)decode_draft;;occurrence<-natural_field "occurrence" j;;Some(ActivitySelection d occurrence)
|Some "side"=>p<-natural_field "parent" j;;g<-natural_field "generation" j;;trigger<-string_field "trigger" j;;Some(SideCreation p g trigger)
|Some "search"=>q<-string_field "query" j;;p<-id_field "project" j;;w<-id_field "work" j;;Some(SearchSubmission q p w)
|Some "language"=>owner<-bind(field "owner" j)Selvedge.Interaction.Interactive.Types.decode_owner;;path<-string_field "path" j;;ticket<-natural_field "ticket" j;;Some(LanguageSubmission owner path ticket)
|Some "work"=>option_map WorkCreation(natural_field "generation" j)|Some "execution_selection"=>Some ExecutionSelection|Some "direct"=>Some DirectSubmission|_=>None end.
Definition encode_pending p:=JObject[("ticket",number(ticket p));("command",encode_command(accepted_command p));("purpose",encode_purpose(purpose p))].
Definition decode_pending j:=t<-natural_field "ticket" j;;c<-bind(field "command" j)(decode_command command_specs);;p<-bind(field "purpose" j)decode_purpose;;Some(Pending t c p).
Definition encode_search s:=JObject[("query",JString(keyword s));("project",optional_id(project_filter s));("work",optional_id(work_filter s));("result",match search_result s with None=>JNull|Some r=>r end)].
Definition decode_search j:=q<-string_field "query" j;;p<-id_field "project" j;;w<-id_field "work" j;;r<-field "result" j;;Some(Search q p w(match r with JNull=>None|_=>Some r end)).
Definition encode_skill_request r:=JObject[("editor",encode_editor(skill_editor r));("workspace",skill_workspace r)].
Definition decode_skill_request j:=e<-bind(field "editor" j)decode_editor;;w<-field "workspace" j;;Some(SkillRequest e w).
Definition encode_authoring a:=JObject[("drafts",JArray(map encode_draft(drafts a)));("next",number(next a));("pending",JArray(map encode_pending(awaiting a)));("search",encode_search(history_search a));("skills",JArray(map(encode_resource encode_skill_request(fun xs=>JArray(map encode_skill xs)))(skill_catalogs a)));("mentions",JArray(map(fun p=>JObject[("editor",encode_editor(fst p));("state",encode_mention(snd p))])(mentions a)))].
Definition decode_authoring j:=ds<-list_field decode_draft "drafts" j;;n<-natural_field "next" j;;ps<-list_field decode_pending "pending" j;;s<-bind(field "search" j)decode_search;;cs<-list_field(decode_resource decode_skill_request(fun j=>xs<-as_array j;;traverse decode_skill xs))"skills" j;;ms<-list_field(fun j=>e<-bind(field "editor" j)decode_editor;;m<-bind(field "state" j)decode_mention;;Some(e,m))"mentions" j;;Some(Authoring ds n ps s cs ms).
Definition encode_reader r:=JObject[("task_id",number(reading_task r));("disclosures",JArray(map(fun '(a,b,c)=>JArray[number a;number b;JBool c])(disclosures r)))].
Definition decode_disclosure j:=match j with JArray[a;b;JBool c]=>a<-natural a;;b<-natural b;;Some(a,b,c)|_=>None end.
Definition decode_reader j:=t<-natural_field "task_id" j;;ds<-list_field decode_disclosure "disclosures" j;;Some(Reader t ds).
Definition encode_state s:=JObject[("navigation",encode_navigation(navigation_state s));("authoring",encode_authoring(authoring_state s));("services",encode_services(service_state s));("speech",encode_speech(speech_state s));("streams",Streams.state_json(stream_state s));("readers",JArray(map encode_reader(readers s)));("interactive",Selvedge.Interaction.Interactive.Codec.encode_state(interactive_state s));("board_filter",BoardFilter.encode(board_selection s));("retention",encode_retention(document_retention s));("collapsed_projects",JArray(map number(collapsed_projects s)))].
Definition decode_state j:=n<-bind(field "navigation" j)decode_navigation;;a<-bind(field "authoring" j)decode_authoring;;sv<-bind(field "services" j)decode_services;;sp<-bind(field "speech" j)decode_speech;;ps<-bind(field "streams" j)Streams.decode_state;;rs<-list_field decode_reader "readers" j;;im<-bind(field "interactive" j)Selvedge.Interaction.Interactive.Codec.decode_state;;f<-field "board_filter" j;;docs<-bind(field "retention" j)decode_retention;;groups<-list_field natural "collapsed_projects" j;;Some(State n a sv sp ps rs im(BoardFilter.decode f)docs groups).

Definition confirmation_pending s :=
 existsb(fun pending=>match purpose pending with ConfirmationSubmission occurrence=>
  N.eqb occurrence(generation(navigation_state s))|_=>false end)(awaiting(authoring_state s)).
