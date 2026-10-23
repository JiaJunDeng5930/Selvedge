From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json TextJson.
From Selvedge.Kernel Require Domain Codec.
From Selvedge.Features Require Domain BoardParameters.
From Selvedge.Interaction.Submission Require Fields.
From Selvedge.Interaction Require Import Codec Identity Context DocumentState Services ModelSelection.
From Selvedge.Interaction.Session Require Draft DraftCodec Observation.
Import ListNotations.
Open Scope string_scope.
Definition initial_model snapshot services := match Services.model_preference services with
|Some preference=>if ModelSelection.valid_preference snapshot preference then Some preference else
 option_map(fun profile=>(Selvedge.Kernel.Domain.profile_key profile,"default"))(ModelSelection.initial_profile(Observation.catalog snapshot))
|None=>option_map(fun profile=>(Selvedge.Kernel.Domain.profile_key profile,"default"))(ModelSelection.initial_profile(Observation.catalog snapshot))end.
Definition board_object collection id snapshot:=board<-field "board" snapshot;;DocumentState.find_world collection "id" id board.
Definition materialize_body snapshot services e :option Draft.body:=match e with
|Identity.NewTask work=>model<-initial_model snapshot services;;Some(Draft.NewTaskBody Draft.empty_text(fst model)(snd model)Context.initial Draft.CurrentWorkspace work)
|Identity.Message task=>match DocumentState.find_task task snapshot with Some _=>Some(Draft.MessageBody task Draft.empty_text Fields.Send)|None=>None end
|Identity.Project None=>Some(Draft.new_body e)
|Identity.Project(Some id)=>project<-Observation.project_by_id id snapshot;;name<-string_field "name" project;;workspace<-bind(field "workspace" project)Codec.parse_workspace;;worktree<-bool_field "create_worktree" project;;Some(Draft.ProjectBody(Some id)name workspace worktree)
|Identity.Card None=>Some(Draft.CardBody None 0 (Selvedge.Features.Domain.CardDraft "" "" Selvedge.Features.Domain.Todo Selvedge.Features.Domain.NoPriority Selvedge.Features.Domain.Unassigned None [] [])false "" false)
|Identity.Card(Some id)=>card<-board_object "cards" id snapshot;;revision<-natural_field "revision" card;;project<-bind(string_field "project" card)Selvedge.Features.BoardParameters.optional_project;;value<-DraftCodec.decode_card(replace "project"(optional_id project)card);;Some(Draft.CardBody(Some id)revision value false "" false)
|Identity.Agent None=>model<-initial_model snapshot services;;Some(Draft.AgentBody None 0 ""(fst model)(snd model)""Context.initial 1)
|Identity.Agent(Some id)=>agent<-board_object "agents" id snapshot;;revision<-natural_field "revision" agent;;name<-string_field "name" agent;;profile<-string_field "profile" agent;;reasoning<-string_field "reasoning" agent;;instructions<-string_field "instructions" agent;;count<-natural_field "concurrency" agent;;configuration<-bind(field "settings" agent)DraftCodec.configuration_of_settings;;Some(Draft.AgentBody(Some id)revision name profile reasoning instructions configuration count)
|Identity.Fork task=>settings<-Observation.task_settings task snapshot;;Some(Draft.ForkBody task 1 [] (Context.Configuration(Context.ParentTask task)None None None))
|Identity.Compact task=>match DocumentState.find_task task snapshot with Some _=>Some(Draft.CompactBody task None)|None=>None end
|Identity.TaskGraph None work=>Some(Draft.TaskGraphBody None (TextJson.render_json(JObject[("name",JString "Task graph");("nodes",JArray []);("rules",JArray [])])) None work)
|Identity.TaskGraph(Some id)work=>graph<-DocumentState.find_world "graphs" "graph_id" id snapshot;;name<-field "name" graph;;nodes<-field "nodes" graph;;rules<-field "rules" graph;;let declaration:=JObject[("name",name);("nodes",nodes);("rules",rules)]in Some(Draft.TaskGraphBody(Some id)(TextJson.render_json declaration)(Some declaration)work)
|Identity.WorkName work=>value<-DocumentState.find_work work snapshot;;name<-string_field "name" value;;Some(Draft.WorkNameBody work name)
|Identity.TitlePrompts=>settings<-field "title_settings" snapshot;;revision<-natural_field "revision" settings;;task<-string_field "task_prompt" settings;;agent<-string_field "agent_prompt" settings;;Some(Draft.TitlePromptsBody revision task agent)end.
Definition materialize snapshot services e:=body<-materialize_body snapshot services e;;Some(Draft.Draft 0 body Draft.Editing "").
