From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json TextJson.
From Selvedge.Kernel Require Domain Codec.
From Selvedge.Features Require Domain BoardParameters.
From Selvedge.Interaction.Submission Require Fields.
From Selvedge.Interaction Require Import Codec Identity Context ModelSelection.
From Selvedge.Interaction Require World.
From Selvedge.Interaction.Submission Require Draft DraftCodec GraphAuthoring.
From Selvedge.Interaction.Submission Require Observation.
Import ListNotations.
Open Scope string_scope.
Definition initial_model snapshot preference := match preference with
|Some preference=>if ModelSelection.valid_preference snapshot preference then Some preference else
 option_map(fun profile=>(Selvedge.Kernel.Domain.profile_key profile,"default"))(ModelSelection.initial_profile(Observation.catalog snapshot))
|None=>option_map(fun profile=>(Selvedge.Kernel.Domain.profile_key profile,"default"))(ModelSelection.initial_profile(Observation.catalog snapshot))end.
Definition materialize_body snapshot preference e :option Draft.body:=match e with
|Identity.NewTask work=>model<-initial_model snapshot preference;;Some(Draft.NewTaskBody Draft.empty_text(fst model)(snd model)Context.initial Draft.CurrentWorkspace work)
|Identity.Message task=>match World.find_task task snapshot with Some _=>Some(Draft.MessageBody task Draft.empty_text Fields.Send)|None=>None end
|Identity.Project None=>Some(Draft.new_body e)
|Identity.Project(Some id)=>project<-Observation.project_by_id id snapshot;;name<-string_field "name" project;;workspace<-bind(field "workspace" project)Codec.parse_workspace;;worktree<-bool_field "create_worktree" project;;Some(Draft.ProjectBody(Some id)name workspace worktree)
|Identity.Card None=>Some(Draft.CardBody None 0 (Selvedge.Features.Domain.CardDraft "" "" Selvedge.Features.Domain.Todo Selvedge.Features.Domain.NoPriority Selvedge.Features.Domain.Unassigned None [] [])false "" false)
|Identity.Card(Some id)=>card<-World.board_object "cards" id snapshot;;revision<-natural_field "revision" card;;project<-bind(string_field "project" card)Selvedge.Features.BoardParameters.optional_project;;value<-DraftCodec.decode_card(replace "project"(optional_id project)card);;Some(Draft.CardBody(Some id)revision value false "" false)
|Identity.Fork task=>settings<-Observation.task_settings task snapshot;;Some(Draft.ForkBody task 1 [] (Context.Configuration(Context.ParentTask task)None None None))
|Identity.Compact task=>match World.find_task task snapshot with Some _=>Some(Draft.CompactBody task None)|None=>None end
|Identity.TaskGraph None work=>
 let declaration := GraphAuthoring.handoff_declaration GraphAuthoring.empty_handoff in
 Some(Draft.TaskGraphBody None (TextJson.render_json declaration) (Some declaration) work)
|Identity.TaskGraph(Some id)work=>graph<-World.find_world "graphs" "graph_id" id snapshot;;name<-field "name" graph;;nodes<-field "nodes" graph;;rules<-field "rules" graph;;let declaration:=JObject[("name",name);("nodes",nodes);("rules",rules)]in Some(Draft.TaskGraphBody(Some id)(TextJson.render_json declaration)(Some declaration)work)
|Identity.WorkName work=>value<-World.find_work work snapshot;;name<-string_field "name" value;;Some(Draft.WorkNameBody work name)
|Identity.TitlePrompts=>settings<-field "title_settings" snapshot;;revision<-natural_field "revision" settings;;task<-string_field "task_prompt" settings;;agent<-string_field "agent_prompt" settings;;
 profile<-bind(field "agent_profile" settings)DraftCodec.decode_option_text;;Some(Draft.TitlePromptsBody revision task agent profile)end.
Definition materialize snapshot preference e:=body<-materialize_body snapshot preference e;;Some(Draft.Draft 0 body Draft.Editing "" None).
