import Base
import ../IDENTITY.bend as Identity
import ../conversation/CODE.bend as Content
import ../conversation/OUTPUT.bend as Live
import ../session/MODEL.bend as E
import ../INPUT.bend as U
import ../services/CONTEXT.bend as Context
import ./MODEL.bend as View
import ./PROGRAM.bend as Interface
import ../STATE.bend as Core
import ../../harness/MODEL.bend as M
import ../../features/board/MODEL.bend as B
import ../../harness/COMMANDS.bend as Commands
import ../../harness/DOMAIN.bend as D
import ../../harness/tasks/PROGRAM.bend as Tasks
import ../../harness/conversation/PROGRAM.bend as Conversation
import ../../bendlib/association-map.bend as Finite

def disclosure(state: E.NavigationState) -> +List<Nat>:
  E.NavigationState{intent, collapsed} = state
  collapsed

def intro_chooser(value: View.CreationIntroduction) -> View.ControlDeclaration:
  View.CreationIntroduction{heading, summary, context, project, chooser} = value
  chooser

def picker_nodes(+values: +List<View.ProjectChoice>, +selected: Maybe<&2, Nat>, +parent: Identity.Key, +state: Core.State) -> Type:
  {Interface.project_choice_nodes(values, selected, parent, state) ==
    [Interface.Node{Identity.Part{parent, "choices"}, "project/choices", "Projects", Interface.Section{}, Interface.ChoiceGroup{},
      Interface.project_picker_choice(View.control("project/select/none", "No project", U.SelectProject{None{}}), View.same_project(selected, None{}), "Use environment defaults", parent, state) <>
        Interface.project_registered_choices(values, selected, parent, state)},
     Interface.declared(parent, View.control("project/create", "New project", U.EditProject{None{}}), state)] : +List<Interface.Node>}

type Requirements is Type:
  Requirements{
    switch_preserves_input: @+origin:Context.Origin -> @+message:U.Text -> @+profile:String -> @+reasoning:String -> @+old:Context.Origin -> @+workspace:Maybe<&2, D.Workspace> -> @+sandbox:Maybe<&2, D.Sandbox> -> @+approval:Maybe<&2, Context.ApprovalChoice> -> @world:M.World() ->
      {U.apply_edit(U.ConfigureContext{Context.ChooseOrigin{origin}}, U.NewTask{message, profile, reasoning, Context.Configuration{old, workspace, sandbox, approval}}, world) ==
        Done{U.NewTask{message, profile, reasoning, Context.Configuration{origin, workspace, sandbox, approval}}} : Result<&2, &2, String, U.Body>},
    select_reuses_draft: @+project:Maybe<&2, Nat> -> @+application:E.Application ->
      {E.activate_selected(U.SelectProject{project}, application) == E.begin_task(project, application) : E.Decision},
    visibility_preserves_disclosure: @expanded:Bool -> @intent:E.NavigationIntent -> @+collapsed:+List<Nat> ->
      {disclosure(E.set_navigation(expanded, E.NavigationState{intent, collapsed})) == collapsed : +List<Nat>},
    visit_preserves_disclosure: @intent:E.NavigationIntent -> @+collapsed:+List<Nat> ->
      {disclosure(E.navigation_after_visit(E.NavigationState{intent, collapsed})) == collapsed : +List<Nat>},
    toggle_keeps_location: @+session:E.Session -> @+project:Nat -> @+world:M.World() -> {E.toggle_project(project, E.from_program(world, session)) ==
        E.local(world, E.with_navigation(E.toggle_project_navigation(project, E.navigation(session)), session), Nil{}) : E.Decision},
    task_ownership: @+id:Nat -> @drafts:+List<U.Draft> -> @+world:M.World() ->
      {View.route_project(U.Conversation{id}, drafts, world) ==
    View.validate_project(View.task_project(Tasks.find(Commands.entries(world), id)), world) : Maybe<&2, Nat>},
    draft_ownership: @+drafts:+List<U.Draft> -> @+world:M.World() ->
      {View.route_project(U.Start{}, drafts, world) ==
    View.draft_project(E.find_draft(drafts, U.NewTaskEditor{}), world) : Maybe<&2, Nat>},
    registered_choices_complete: @+entries:+List<Finite.Entry(D.Project)> ->
      {List.length(&2, View.ProjectChoice, View.project_choices(entries)) == List.length(&2, Finite.Entry(D.Project), entries) : Nat},
    picker_filter_keeps_selection: @+query:String -> @+selected:Maybe<&2, Nat> -> @+projects:+List<View.ProjectChoice> ->
      {View.search_content(View.ProjectSelection{"", selected, projects}, query) ==
    View.ProjectSelection{query, selected, View.matching_projects(projects, query)} : View.LayerContent},
    project_actions: @+id:Nat -> @+name:String -> @+workspace:D.Workspace -> @guidance:D.ProjectContext -> @+tasks:+List<D.Task> -> @+route:U.Route -> @+selected:Maybe<&2, Nat> -> @+navigation:E.NavigationState ->
      {View.project_entry(id, D.Project{name, workspace, guidance}, tasks, route, selected, navigation) ==
        View.ProjectEntry{id, name, workspace, View.selected_project(selected, id), Bool.not(E.project_collapsed(navigation, id)), View.task_entries(View.project_tasks(tasks, Some{id}), route),
          View.control("project/" ++ Nat.show(id), name, U.SelectProject{Some{id}}), View.control("project/new-task/" ++ Nat.show(id), "New task", U.BeginTask{Some{id}}),
          View.control("project/toggle/" ++ Nat.show(id), "Toggle project tasks", U.ToggleProjectGroup{id}),
          View.context_control("project/more/" ++ Nat.show(id), "More", U.ObjectActions{U.ProjectSubject{id}})} : View.ProjectEntry},
    details_entry: @+id:Nat -> @+now:U32 -> @+world:M.World() ->
      {View.subject_controls(U.ProjectSubject{id}, now, world) ==
        [View.control("project/details/" ++ Nat.show(id), "Project details", U.Navigate{U.ProjectHome{id}}),
         View.control("project/edit/" ++ Nat.show(id), "Edit project", U.EditProject{Some{id}}),
         View.native("project/delete/" ++ Nat.show(id), "Delete project", View.Destructive{}, U.DeleteProject{id}, world)] : +List<View.ControlDeclaration>},
    chooser_single_name: @+id:Nat -> @+name:String -> @+workspace:D.Workspace ->
      {(View.creation_heading(Some{View.ProjectChoice{id, name, workspace}}), View.project_choice_label(Some{View.ProjectChoice{id, name, workspace}})) ==
    ("Work on", name) : Sigma<&2, &2, String, (_ => String)>},
    task_status_visible: @+id:Nat -> @title:String -> @+status:View.TaskStatus -> @+selected:Bool -> @+open:View.ControlDeclaration -> @+parent: Identity.Key -> @+state:Core.State ->
      {Interface.task_entries([View.TaskEntry{id, title, status, selected, open}], parent, state) ==
        [Interface.Node{Identity.Entity{parent, "task", Nat.show(id)}, "task-row", "", Interface.Section{}, Interface.TaskRow{id, status, selected},
          [Interface.selected_node(selected, Interface.declared(Identity.Entity{parent, "task", Nat.show(id)}, open, state)),
           Interface.Node{Identity.Part{Identity.Entity{parent, "task", Nat.show(id)}, "status"}, "task-status", "Task status", Interface.Content{}, Interface.ReadOnly{View.task_status_label(status)}, Nil{}}]}] : +List<Interface.Node>},
    deletion_retains_other: @+prefix:+List<Nat> -> @+other:Nat -> @+suffix:+List<Nat> -> @+id:Nat -> @distinct:{Nat.is_eq(id, other) == False{} : Bool} ->
      {List.contains(~Nat, ~Nat.is_eq, E.without_collapsed_project(List.append(&2, Nat, prefix, other <> suffix), id), other) == True{} : Bool},
    toggle_retains_other: @+intent:E.NavigationIntent -> @+prefix:+List<Nat> -> @+other:Nat -> @+suffix:+List<Nat> -> @+id:Nat -> @distinct:{Nat.is_eq(id, other) == False{} : Bool} ->
      {E.project_collapsed(E.toggle_project_navigation(id, E.NavigationState{intent, List.append(&2, Nat, prefix, other <> suffix)}), other) == True{} : Bool},
    toggle_preserves_visibility: @+id:Nat -> @+intent:E.NavigationIntent -> @collapsed:+List<Nat> ->
      {E.navigation_visibility(E.toggle_project_navigation(id, E.NavigationState{intent, collapsed})) == intent : E.NavigationIntent},
    picker_complete_nodes: @+values:+List<View.ProjectChoice> -> @+selected:Maybe<&2, Nat> -> @+parent:Identity.Key -> @+state:Core.State -> picker_nodes(values, selected, parent, state),
    chooser_activation: @+context:Maybe<&2, Context.Preview> -> @+world:M.World() ->
      {intro_chooser(View.creation_introduction_fields(context, world)) ==
        View.ControlDeclaration{"composer/project", View.project_choice_label(View.creation_selected_project(context, world)), View.Secondary{},
          U.Activate{U.OpenPanel{U.ProjectPicker{}, "composer/project"}}, View.Available{}} : View.ControlDeclaration},
    picker_search_preserves_session: @+session:E.Session -> @+query:String -> @+world:M.World() -> @+trigger:String -> @+initial:String -> @previous:String -> @+layer_occurrence:Nat -> @+rest:+List<E.Layer> ->
      @observed_layers:{E.layers(session) == E.Layer{U.ProjectPicker{}, trigger, initial, previous, layer_occurrence} <> rest : +List<E.Layer>} ->
       {E.search_choices(query, E.from_program(world, session)) ==
        E.local(world, E.with_layers(E.Layer{U.ProjectPicker{}, trigger, initial, query, layer_occurrence} <> rest, session), Nil{}) : E.Decision},
    project_group_single_title: @+id:Nat -> @name:String -> @workspace:D.Workspace -> @+selected:Bool -> @+expanded:Bool -> @+tasks:+List<View.TaskEntry> -> @+open:View.ControlDeclaration -> @+create:View.ControlDeclaration -> @+toggle:View.ControlDeclaration -> @+more:View.ControlDeclaration -> @+parent: Identity.Key -> @+state:Core.State ->
      {Interface.project_entries([View.ProjectEntry{id, name, workspace, selected, expanded, tasks, open, create, toggle, more}], parent, state) ==
        [Interface.Node{Identity.Entity{parent, "project", Nat.show(id)}, "project-group", "", Interface.Section{}, Interface.ProjectGroup{id, selected, expanded},
          Interface.region(Identity.Entity{parent, "project", Nat.show(id)}, "actions", "", Interface.Section{},
            [Interface.declared(Identity.Entity{parent, "project", Nat.show(id)}, toggle, state), Interface.selected_node(selected, Interface.declared(Identity.Entity{parent, "project", Nat.show(id)}, open, state)),
             Interface.declared(Identity.Entity{parent, "project", Nat.show(id)}, create, state), Interface.declared(Identity.Entity{parent, "project", Nat.show(id)}, more, state)]) <>
          Interface.disclosed_tasks(expanded, tasks, Identity.Entity{parent, "project", Nat.show(id)}, state)}] : +List<Interface.Node>},
    committed_is_not_draft: @context:Context.EffectiveContext ->
      {View.draft_preview(Some{Context.CommittedExecution{context}}) == None{} : Maybe<&2, Context.Preview>},
    empty_project_collection: @+parent: Identity.Key -> @state:Core.State ->
      {Interface.project_collection_entries(Nil{}, parent, state) ==
        [Interface.Node{Identity.Part{Identity.Part{parent, "projects"}, "empty"}, "projects/empty", "", Interface.Content{},
          Interface.ReadOnly{"Create a project to group tasks and choose default working folders."}, Nil{}}] : +List<Interface.Node>},
    populated_project_collection: @+first:View.ProjectScene -> @+rest:+List<View.ProjectScene> -> @+parent: Identity.Key -> @+state:Core.State ->
      {Interface.project_collection_entries(Con{first, rest}, parent, state) ==
    Interface.projects(Con{first, rest}, parent, state) : +List<Interface.Node>},
    select_focus_and_input: @+session:E.Session -> @+project:Maybe<&2, Nat> -> @+world:M.World() -> @+revision:Nat -> @+message:U.Text -> @+profile:String -> @+reasoning:String -> @+old:Context.Origin -> @+workspace:Maybe<&2, D.Workspace> -> @+sandbox:Maybe<&2, D.Sandbox> -> @+approval:Maybe<&2, Context.ApprovalChoice> -> @+feedback:U.Feedback -> @+directory_entry:String -> @+rest:+List<U.Draft> ->
      @observed_drafts:{E.drafts(session) == U.Draft{revision, U.NewTask{message, profile, reasoning, Context.Configuration{old, workspace, sandbox, approval}}, feedback, directory_entry} <> rest : +List<U.Draft>} ->
       {E.activate_selected(U.SelectProject{project}, E.from_program(world, session)) ==
        E.local(world, E.with_navigation(E.navigation_after_visit(E.navigation(session)), E.with_attention("composer/" ++ U.editor_key(U.NewTaskEditor{}), E.with_layers(Nil{}, E.with_drafts(E.put_draft(U.Draft{(revision + 1n : Nat), U.NewTask{message, profile, reasoning, Context.Configuration{E.context_project(project), workspace, sandbox, approval}}, U.Editing{}, directory_entry},
            U.Draft{revision, U.NewTask{message, profile, reasoning, Context.Configuration{old, workspace, sandbox, approval}}, feedback, directory_entry} <> rest), E.with_route(U.Start{}, session))))),
          [E.Attend{"composer/" ++ U.editor_key(U.NewTaskEditor{})}]) : E.Decision},
    missing_draft_focus: @+session:E.Session -> @+project:Maybe<&2, Nat> -> @+world:M.World() ->
      @observed_drafts:{E.drafts(session) == Nil{} : +List<U.Draft>} ->
       {E.activate_selected(U.SelectProject{project}, E.from_program(world, session)) ==
        E.local(world, E.with_navigation(E.navigation_after_visit(E.navigation(session)), E.with_attention("composer/" ++ U.editor_key(U.NewTaskEditor{}), E.with_layers(Nil{}, E.with_route(U.Start{}, session)))),
          [E.Attend{"composer/" ++ U.editor_key(U.NewTaskEditor{})}]) : E.Decision},
    task_status_source: @+task:D.Task -> {View.task_status(task) == View.TaskStatus{D.task_status(task), Conversation.working(D.task_phase(task), D.task_operations(task))} : View.TaskStatus},
    task_status_label: @+lifecycle:D.Status -> @+working:Bool -> {View.task_status_label(View.TaskStatus{lifecycle, working}) == Conversation.status_label(lifecycle, working) : String},
    task_status_caption: @+task:D.Task -> {View.task_status_label(View.task_status(task)) == Conversation.status(task) : String}}

law evidence:
  Requirements
