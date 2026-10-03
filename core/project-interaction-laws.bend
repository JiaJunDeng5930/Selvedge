import Base
import ./code-block.bend as Content
import ./live-output.bend as Live
import ./user-experience.bend as E
import ./user-input.bend as U
import ./user-context.bend as Context
import ./ui-world.bend as View
import ./interface.bend as Interface
import ./SYSTEM.bend as Core
import ../MODEL.bend as M
import ../BOARD.bend as B
import ../COMMANDS.bend as Commands
import ../PROJECTS.bend as Projects
import ../FEATURES.bend as F
import ../bendlib/domain.bend as D
import ../bendlib/tasks.bend as Tasks
import ../bendlib/association-map.bend as Finite
import ../bendlib/stdlib.bend as Std

def disclosure(state: E.NavigationState) -> +List<Nat>:
  E.NavigationState{intent, collapsed} = state
  collapsed

def switch_preserves_input_law(-origin: Context.Origin, -message: U.Text, -profile: String,
  -reasoning: String, -old: Context.Origin, -workspace: Maybe<&2, D.Workspace>,
  -sandbox: Maybe<&2, D.Sandbox>, -approval: Maybe<&2, Context.ApprovalChoice>, -world: M.World()) -> Type:
  {U.apply_edit(U.ConfigureContext{Context.ChooseOrigin{origin}}, U.NewTask{message, profile, reasoning, Context.Configuration{old, workspace, sandbox, approval}}, world) ==
    Done{U.NewTask{message, profile, reasoning, Context.Configuration{origin, workspace, sandbox, approval}}} : Result<&2, &2, String, U.Body>}

def switch_preserves_input(+origin: Context.Origin, +message: U.Text, +profile: String, +reasoning: String,
  +old: Context.Origin, +workspace: Maybe<&2, D.Workspace>, +sandbox: Maybe<&2, D.Sandbox>, +approval: Maybe<&2, Context.ApprovalChoice>, world: M.World()) ->
  switch_preserves_input_law(origin, message, profile, reasoning, old, workspace, sandbox, approval, world):
  {==}

def select_reuses_draft(+project: Maybe<&2, Nat>, +application: E.Application) ->
  {E.activate_selected(U.SelectProject{project}, application) == E.begin_task(project, application) : E.Decision}:
  {==}

def visibility_preserves_disclosure(expanded: Bool, intent: E.NavigationIntent, +collapsed: +List<Nat>) ->
  {disclosure(E.set_navigation(expanded, E.NavigationState{intent, collapsed})) == collapsed : +List<Nat>}:
  {==}

def visit_preserves_disclosure(intent: E.NavigationIntent, +collapsed: +List<Nat>) ->
  {disclosure(E.navigation_after_visit(E.NavigationState{intent, collapsed})) == collapsed : +List<Nat>}:
  {==}

def toggle_keeps_location_law(-project: Nat, -world: M.World(), -route: U.Route,
  -drafts: +List<U.Draft>, -readers: +List<Finite.Entry(E.Reader)>, -layers: +List<E.Layer>,
  -attention: String, -navigation: E.NavigationState, -filter: B.Filter, -now: U32, -next: Nat,
  -pending: +List<E.Pending>, -previews: +List<Live.Output>, -code: +List<Content.Block>) -> Type:
  {E.toggle_project(project, E.Application{world, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code}}) ==
    E.local(world, E.Session{route, drafts, readers, layers, attention, E.toggle_project_navigation(project, navigation), filter, now, next, pending, previews, code}, Nil{}) : E.Decision}

def toggle_keeps_location(+project: Nat, +world: M.World(), +route: U.Route, +drafts: +List<U.Draft>, +readers: +List<Finite.Entry(E.Reader)>,
  +layers: +List<E.Layer>, +attention: String, +navigation: E.NavigationState, +filter: B.Filter, +now: U32, +next: Nat,
  +pending: +List<E.Pending>, +previews: +List<Live.Output>, +code: +List<Content.Block>) ->
  toggle_keeps_location_law(project, world, route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code):
  {==}

def task_ownership(+id: Nat, drafts: +List<U.Draft>, +world: M.World()) ->
  {View.route_project(U.Conversation{id}, drafts, world) ==
    View.validate_project(View.task_project(Tasks.find(Commands.entries(world), id)), world) : Maybe<&2, Nat>}:
  {==}

def draft_ownership(+drafts: +List<U.Draft>, +world: M.World()) ->
  {View.route_project(U.Start{}, drafts, world) ==
    View.draft_project(E.find_draft(drafts, U.NewTaskEditor{}), world) : Maybe<&2, Nat>}:
  {==}

def registered_choices_complete(+entries: +List<Finite.Entry(D.Project)>) ->
  {List.length(&2, View.ProjectChoice, View.project_choices(entries)) == List.length(&2, Finite.Entry(D.Project), entries) : Nat}:
  match entries:
    case Nil{}: {==}
    case Con{(id, D.Project{name, workspace, guidance}), +rest}:
      Equal.cong(Nat, Nat, (n => (1n + n : Nat)), List.length(&2, View.ProjectChoice, View.project_choices(rest)), List.length(&2, Finite.Entry(D.Project), rest), registered_choices_complete(rest))

def picker_filter_keeps_selection(+query: String, +selected: Maybe<&2, Nat>, +projects: +List<View.ProjectChoice>) ->
  {View.search_content(View.ProjectSelection{"", selected, projects}, query) ==
    View.ProjectSelection{query, selected, View.matching_projects(projects, query)} : View.LayerContent}:
  {==}

def project_actions_law(-id: Nat, -name: String, -workspace: D.Workspace,
  -guidance: D.ProjectContext, -tasks: +List<D.Task>, -route: U.Route, -selected: Maybe<&2, Nat>,
  -navigation: E.NavigationState) -> Type:
  {View.project_entry(id, D.Project{name, workspace, guidance}, tasks, route, selected, navigation) ==
    View.ProjectEntry{id, name, workspace, View.selected_project(selected, id), Bool.not(E.project_collapsed(navigation, id)), View.task_entries(View.project_tasks(tasks, Some{id}), route),
      View.control("project/" ++ Nat.show(id), name, U.SelectProject{Some{id}}), View.control("project/new-task/" ++ Nat.show(id), "New task", U.BeginTask{Some{id}}),
      View.control("project/toggle/" ++ Nat.show(id), "Toggle project tasks", U.ToggleProjectGroup{id}),
      View.context_control("project/more/" ++ Nat.show(id), "More", U.ObjectActions{U.ProjectSubject{id}})} : View.ProjectEntry}

def project_actions(+id: Nat, +name: String, +workspace: D.Workspace, guidance: D.ProjectContext, +tasks: +List<D.Task>, +route: U.Route,
  +selected: Maybe<&2, Nat>, +navigation: E.NavigationState) ->
  project_actions_law(id, name, workspace, guidance, tasks, route, selected, navigation):
  {==}

def details_entry_law(-id: Nat, -now: U32, -world: M.World()) -> Type:
  {View.subject_controls(U.ProjectSubject{id}, now, world) ==
    [View.control("project/details/" ++ Nat.show(id), "Project details", U.Navigate{U.ProjectHome{id}}),
     View.control("project/edit/" ++ Nat.show(id), "Edit project", U.EditProject{Some{id}}),
     View.native("project/delete/" ++ Nat.show(id), "Delete project", View.Destructive{}, U.DeleteProject{id}, world)] : +List<View.ControlDeclaration>}

def details_entry(+id: Nat, +now: U32, +world: M.World()) ->
  details_entry_law(id, now, world):
  {==}

def chooser_single_name(+id: Nat, +name: String, +workspace: D.Workspace) ->
  {(View.creation_heading(Some{View.ProjectChoice{id, name, workspace}}), View.project_choice_label(Some{View.ProjectChoice{id, name, workspace}})) ==
    ("Work on", name) : Sigma<&2, &2, String, (_ => String)>}:
  {==}

def task_status_visible_law(-id: Nat, -title: String, -status: String, -selected: Bool,
  -open: View.ControlDeclaration, -parent: String, -state: Core.State) -> Type:
  {Interface.task_entries([View.TaskEntry{id, title, status, selected, open}], parent, state) ==
    [Interface.Node{parent ++ "/task/" ++ Nat.show(id), "task-row", "", Interface.Section{}, Interface.TaskRow{id, status, selected},
      [Interface.selected_node(selected, Interface.declared(parent ++ "/task/" ++ Nat.show(id), open, state)),
       Interface.Node{parent ++ "/task/" ++ Nat.show(id) ++ "/status", "task-status", "Task status", Interface.Content{}, Interface.ReadOnly{status}, Nil{}}]}] : +List<Interface.Node>}

def task_status_visible(+id: Nat, title: String, +status: String, +selected: Bool, +open: View.ControlDeclaration, +parent: String, +state: Core.State) ->
  task_status_visible_law(id, title, status, selected, open, parent, state):
  {==}

def nat_same(+value: Nat) -> {Nat.is_eq(value, value) == True{} : Bool}:
  match value:
    case 0n: {==}
    case 1n+rest: nat_same(rest)

def deletion_retains_head(+other: Nat, +id: Nat, +tail: +List<Nat>, distinct: {Nat.is_eq(id, other) == False{} : Bool}) ->
  {List.contains(~Nat, ~Nat.is_eq, E.without_collapsed_project(other <> tail, id), other) == True{} : Bool}:
  backwards = Equal.sym(Bool, Nat.is_eq(id, other), False{}, distinct)
  %backwards : {List.contains(~Nat, ~Nat.is_eq, Std.map(~Finite.Entry(Nat), ~Nat, ~(entry => E.project_disclosure_value(entry)),
    Finite.keep(~Nat, Bool.not(_), other, 0n, Finite.remove(~Nat, Std.map(~Nat, ~Finite.Entry(Nat), ~(current => (current, 0n)), tail), id))), other) == True{} : Bool}
  same = Equal.sym(Bool, Nat.is_eq(other, other), True{}, nat_same(other))
  %same : {Bool.or(_, List.contains(~Nat, ~Nat.is_eq, E.without_collapsed_project(tail, id), other)) == True{} : Bool}
  {==}

def deletion_retains_step(hit: Bool, +head: Nat, +tail: +List<Nat>, +id: Nat, +other: Nat,
  observed: {Nat.is_eq(id, head) == hit : Bool},
  induction: {List.contains(~Nat, ~Nat.is_eq, E.without_collapsed_project(tail, id), other) == True{} : Bool}) ->
  {List.contains(~Nat, ~Nat.is_eq, E.without_collapsed_project(head <> tail, id), other) == True{} : Bool}:
  match hit:
    case True{}:
      backwards = Equal.sym(Bool, Nat.is_eq(id, head), True{}, observed)
      %backwards : {List.contains(~Nat, ~Nat.is_eq, Std.map(~Finite.Entry(Nat), ~Nat, ~(entry => E.project_disclosure_value(entry)),
        Finite.keep(~Nat, Bool.not(_), head, 0n, Finite.remove(~Nat, Std.map(~Nat, ~Finite.Entry(Nat), ~(current => (current, 0n)), tail), id))), other) == True{} : Bool}
      induction
    case False{}:
      backwards = Equal.sym(Bool, Nat.is_eq(id, head), False{}, observed)
      %backwards : {List.contains(~Nat, ~Nat.is_eq, Std.map(~Finite.Entry(Nat), ~Nat, ~(entry => E.project_disclosure_value(entry)),
        Finite.keep(~Nat, Bool.not(_), head, 0n, Finite.remove(~Nat, Std.map(~Nat, ~Finite.Entry(Nat), ~(current => (current, 0n)), tail), id))), other) == True{} : Bool}
      prior = Equal.sym(Bool, List.contains(~Nat, ~Nat.is_eq, E.without_collapsed_project(tail, id), other), True{}, induction)
      %prior : {Bool.or(Nat.is_eq(head, other), _) == True{} : Bool}
      Std.orb_true_r(Nat.is_eq(head, other))

def deletion_retains_other(+prefix: +List<Nat>, +other: Nat, +suffix: +List<Nat>, +id: Nat,
  distinct: {Nat.is_eq(id, other) == False{} : Bool}) ->
  {List.contains(~Nat, ~Nat.is_eq, E.without_collapsed_project(List.append(&2, Nat, prefix, other <> suffix), id), other) == True{} : Bool}:
  match prefix:
    case Nil{}: deletion_retains_head(other, id, suffix, distinct)
    case Con{+head, +rest}: deletion_retains_step(Nat.is_eq(id, head), head, List.append(&2, Nat, rest, other <> suffix), id, other, {==}, deletion_retains_other(rest, other, suffix, id, distinct))

def existing_other_head(+other: Nat, +suffix: +List<Nat>) ->
  {List.contains(~Nat, ~Nat.is_eq, other <> suffix, other) == True{} : Bool}:
  backwards = Equal.sym(Bool, Nat.is_eq(other, other), True{}, nat_same(other))
  %backwards : {Bool.or(_, List.contains(~Nat, ~Nat.is_eq, suffix, other)) == True{} : Bool}
  {==}

def existing_other(+prefix: +List<Nat>, +other: Nat, +suffix: +List<Nat>) ->
  {List.contains(~Nat, ~Nat.is_eq, List.append(&2, Nat, prefix, other <> suffix), other) == True{} : Bool}:
  match prefix:
    case Nil{}: existing_other_head(other, suffix)
    case Con{+head, +rest}:
      backwards = Equal.sym(Bool, List.contains(~Nat, ~Nat.is_eq, List.append(&2, Nat, rest, other <> suffix), other), True{}, existing_other(rest, other, suffix))
      %backwards : {Bool.or(Nat.is_eq(head, other), _) == True{} : Bool}
      Std.orb_true_r(Nat.is_eq(head, other))

def toggle_retains_case(hit: Bool, +prefix: +List<Nat>, +other: Nat, +suffix: +List<Nat>, +id: Nat,
  distinct: {Nat.is_eq(id, other) == False{} : Bool}) ->
  {List.contains(~Nat, ~Nat.is_eq, E.toggle_collapsed(hit, id, List.append(&2, Nat, prefix, other <> suffix)), other) == True{} : Bool}:
  match hit:
    case True{}: deletion_retains_other(prefix, other, suffix, id, distinct)
    case False{}:
      backwards = Equal.sym(Bool, List.contains(~Nat, ~Nat.is_eq, List.append(&2, Nat, prefix, other <> suffix), other), True{}, existing_other(prefix, other, suffix))
      %backwards : {Bool.or(Nat.is_eq(id, other), _) == True{} : Bool}
      Std.orb_true_r(Nat.is_eq(id, other))

def toggle_retains_other(+intent: E.NavigationIntent, +prefix: +List<Nat>, +other: Nat, +suffix: +List<Nat>, +id: Nat,
  distinct: {Nat.is_eq(id, other) == False{} : Bool}) ->
  {E.project_collapsed(E.toggle_project_navigation(id, E.NavigationState{intent, List.append(&2, Nat, prefix, other <> suffix)}), other) == True{} : Bool}:
  toggle_retains_case(E.project_collapsed(E.NavigationState{intent, List.append(&2, Nat, prefix, other <> suffix)}, id), prefix, other, suffix, id, distinct)

def toggle_preserves_visibility(+id: Nat, +intent: E.NavigationIntent, collapsed: +List<Nat>) ->
  {E.navigation_visibility(E.toggle_project_navigation(id, E.NavigationState{intent, collapsed})) == intent : E.NavigationIntent}:
  {==}

def picker_complete_nodes_law(-values: +List<View.ProjectChoice>, -selected: Maybe<&2, Nat>,
  -parent: String, -state: Core.State) -> Type:
  {Interface.project_choice_nodes(values, selected, parent, state) ==
    Interface.project_picker_choice(View.control("project/select/none", "No project", U.SelectProject{None{}}), View.same_project(selected, None{}), "Use environment defaults", parent, state) <>
      List.append(&2, Interface.Node, Interface.project_registered_choices(values, selected, parent, state),
        [Interface.declared(parent, View.control("project/create", "New project", U.EditProject{None{}}), state)]) : +List<Interface.Node>}

def picker_complete_nodes(+values: +List<View.ProjectChoice>, +selected: Maybe<&2, Nat>, +parent: String, +state: Core.State) ->
  picker_complete_nodes_law(values, selected, parent, state):
  {==}

def intro_chooser(value: View.CreationIntroduction) -> View.ControlDeclaration:
  View.CreationIntroduction{heading, summary, context, project, chooser} = value
  chooser

def chooser_activation_law(-context: Maybe<&2, Context.Preview>, -world: M.World()) -> Type:
  {intro_chooser(View.creation_introduction_fields(context, world)) ==
    View.ControlDeclaration{"composer/project", View.project_choice_label(View.creation_selected_project(context, world)), View.Secondary{},
      U.Activate{U.OpenPanel{U.ProjectPicker{}, "composer/project"}}, View.Available{}} : View.ControlDeclaration}

def chooser_activation(+context: Maybe<&2, Context.Preview>, +world: M.World()) ->
  chooser_activation_law(context, world):
  {==}

def picker_search_preserves_session_law(-query: String, -world: M.World(), -route: U.Route,
  -drafts: +List<U.Draft>, -readers: +List<Finite.Entry(E.Reader)>, -trigger: String,
  -initial: String, -previous: String, -rest: +List<E.Layer>, -attention: String,
  -navigation: E.NavigationState, -filter: B.Filter, -now: U32, -next: Nat,
  -pending: +List<E.Pending>, -previews: +List<Live.Output>, -code: +List<Content.Block>) -> Type:
  {E.search_choices(query, E.Application{world, E.Session{route, drafts, readers, E.Layer{U.ProjectPicker{}, trigger, initial, previous} <> rest,
    attention, navigation, filter, now, next, pending, previews, code}}) ==
    E.local(world, E.Session{route, drafts, readers, E.Layer{U.ProjectPicker{}, trigger, initial, query} <> rest,
      attention, navigation, filter, now, next, pending, previews, code}, Nil{}) : E.Decision}

def picker_search_preserves_session(+query: String, +world: M.World(), +route: U.Route, +drafts: +List<U.Draft>, +readers: +List<Finite.Entry(E.Reader)>,
  +trigger: String, +initial: String, previous: String, +rest: +List<E.Layer>, +attention: String, +navigation: E.NavigationState, +filter: B.Filter,
  +now: U32, +next: Nat, +pending: +List<E.Pending>, +previews: +List<Live.Output>, +code: +List<Content.Block>) ->
  picker_search_preserves_session_law(query, world, route, drafts, readers, trigger, initial, previous, rest, attention, navigation, filter, now, next, pending, previews, code):
  {==}

def project_group_single_title_law(-id: Nat, -name: String, -workspace: D.Workspace, -selected: Bool,
  -expanded: Bool, -tasks: +List<View.TaskEntry>, -open: View.ControlDeclaration,
  -create: View.ControlDeclaration, -toggle: View.ControlDeclaration, -more: View.ControlDeclaration,
  -parent: String, -state: Core.State) -> Type:
  {Interface.project_entries([View.ProjectEntry{id, name, workspace, selected, expanded, tasks, open, create, toggle, more}], parent, state) ==
    [Interface.Node{parent ++ "/project/" ++ Nat.show(id), "project-group", "", Interface.Section{}, Interface.ProjectGroup{id, selected, expanded},
      Interface.region(parent ++ "/project/" ++ Nat.show(id), "actions", "", Interface.Section{},
        [Interface.declared(parent ++ "/project/" ++ Nat.show(id), toggle, state), Interface.selected_node(selected, Interface.declared(parent ++ "/project/" ++ Nat.show(id), open, state)),
         Interface.declared(parent ++ "/project/" ++ Nat.show(id), create, state), Interface.declared(parent ++ "/project/" ++ Nat.show(id), more, state)]) <>
      Interface.disclosed_tasks(expanded, tasks, parent ++ "/project/" ++ Nat.show(id), state)}] : +List<Interface.Node>}

def project_group_single_title(+id: Nat, name: String, workspace: D.Workspace, +selected: Bool, +expanded: Bool,
  +tasks: +List<View.TaskEntry>, +open: View.ControlDeclaration, +create: View.ControlDeclaration, +toggle: View.ControlDeclaration,
  +more: View.ControlDeclaration, +parent: String, +state: Core.State) ->
  project_group_single_title_law(id, name, workspace, selected, expanded, tasks, open, create, toggle, more, parent, state):
  {==}

def committed_is_not_draft(context: Context.EffectiveContext) ->
  {View.draft_preview(Some{Context.CommittedExecution{context}}) == None{} : Maybe<&2, Context.Preview>}:
  {==}

def empty_project_collection_law(-parent: String, -state: Core.State) -> Type:
  {Interface.project_collection_entries(Nil{}, parent, state) ==
    [Interface.Node{parent ++ "/projects/empty", "projects/empty", "", Interface.Content{},
      Interface.ReadOnly{"Create a project to group tasks and choose default working folders."}, Nil{}}] : +List<Interface.Node>}

def empty_project_collection(+parent: String, state: Core.State) ->
  empty_project_collection_law(parent, state):
  {==}

def populated_project_collection(+first: View.ProjectScene, +rest: +List<View.ProjectScene>, +parent: String, +state: Core.State) ->
  {Interface.project_collection_entries(Con{first, rest}, parent, state) ==
    Interface.projects(Con{first, rest}, parent, state) : +List<Interface.Node>}:
  {==}

def select_focus_and_input_law(-project: Maybe<&2, Nat>, -world: M.World(), -route: U.Route,
  -revision: Nat, -message: U.Text, -profile: String, -reasoning: String, -old: Context.Origin,
  -workspace: Maybe<&2, D.Workspace>, -sandbox: Maybe<&2, D.Sandbox>,
  -approval: Maybe<&2, Context.ApprovalChoice>, -feedback: U.Feedback, -directory_entry: String,
  -rest: +List<U.Draft>, -readers: +List<Finite.Entry(E.Reader)>, -layers: +List<E.Layer>,
  -attention: String, -navigation: E.NavigationState, -filter: B.Filter, -now: U32, -next: Nat,
  -pending: +List<E.Pending>, -previews: +List<Live.Output>, -code: +List<Content.Block>) -> Type:
  {E.activate_selected(U.SelectProject{project}, E.Application{world, E.Session{route,
    U.Draft{revision, U.NewTask{message, profile, reasoning, Context.Configuration{old, workspace, sandbox, approval}}, feedback, directory_entry} <> rest,
    readers, layers, attention, navigation, filter, now, next, pending, previews, code}}) ==
    E.local(world, E.Session{U.Start{},
      E.put_draft(U.Draft{(revision + 1n : Nat), U.NewTask{message, profile, reasoning, Context.Configuration{E.context_project(project), workspace, sandbox, approval}}, U.Editing{}, directory_entry},
        U.Draft{revision, U.NewTask{message, profile, reasoning, Context.Configuration{old, workspace, sandbox, approval}}, feedback, directory_entry} <> rest),
      readers, Nil{}, "composer/" ++ U.editor_key(U.NewTaskEditor{}), E.navigation_after_visit(navigation), filter, now, next, pending, previews, code},
      [E.Attend{"composer/" ++ U.editor_key(U.NewTaskEditor{})}]) : E.Decision}

def select_focus_and_input(+project: Maybe<&2, Nat>, +world: M.World(), route: U.Route, +revision: Nat, +message: U.Text,
  +profile: String, +reasoning: String, +old: Context.Origin, +workspace: Maybe<&2, D.Workspace>, +sandbox: Maybe<&2, D.Sandbox>,
  +approval: Maybe<&2, Context.ApprovalChoice>, +feedback: U.Feedback, +directory_entry: String, +rest: +List<U.Draft>, +readers: +List<Finite.Entry(E.Reader)>,
  layers: +List<E.Layer>, attention: String, +navigation: E.NavigationState, +filter: B.Filter, +now: U32, +next: Nat,
  +pending: +List<E.Pending>, +previews: +List<Live.Output>, +code: +List<Content.Block>) ->
  select_focus_and_input_law(project, world, route, revision, message, profile, reasoning, old, workspace, sandbox, approval, feedback, directory_entry, rest, readers, layers, attention, navigation, filter, now, next, pending, previews, code):
  {==}

def missing_draft_focus_law(-project: Maybe<&2, Nat>, -world: M.World(), -route: U.Route,
  -readers: +List<Finite.Entry(E.Reader)>, -layers: +List<E.Layer>, -attention: String,
  -navigation: E.NavigationState, -filter: B.Filter, -now: U32, -next: Nat,
  -pending: +List<E.Pending>, -previews: +List<Live.Output>, -code: +List<Content.Block>) -> Type:
  {E.activate_selected(U.SelectProject{project}, E.Application{world, E.Session{route, Nil{}, readers, layers, attention, navigation, filter, now, next, pending, previews, code}}) ==
    E.local(world, E.Session{U.Start{}, Nil{}, readers, Nil{}, "composer/" ++ U.editor_key(U.NewTaskEditor{}), E.navigation_after_visit(navigation), filter, now, next, pending, previews, code},
      [E.Attend{"composer/" ++ U.editor_key(U.NewTaskEditor{})}]) : E.Decision}

def missing_draft_focus(+project: Maybe<&2, Nat>, +world: M.World(), route: U.Route, +readers: +List<Finite.Entry(E.Reader)>,
  layers: +List<E.Layer>, attention: String, +navigation: E.NavigationState, +filter: B.Filter, +now: U32, +next: Nat,
  +pending: +List<E.Pending>, +previews: +List<Live.Output>, +code: +List<Content.Block>) ->
  missing_draft_focus_law(project, world, route, readers, layers, attention, navigation, filter, now, next, pending, previews, code):
  {==}

type Requirements is Type:
  Requirements{
    switch_preserves_input: @+origin:Context.Origin -> @+message:U.Text -> @+profile:String -> @+reasoning:String -> @+old:Context.Origin -> @+workspace:Maybe<&2, D.Workspace> -> @+sandbox:Maybe<&2, D.Sandbox> -> @+approval:Maybe<&2, Context.ApprovalChoice> -> @world:M.World() ->
      switch_preserves_input_law(origin, message, profile, reasoning, old, workspace, sandbox, approval, world),
    select_reuses_draft: @+project:Maybe<&2, Nat> -> @+application:E.Application ->
      {E.activate_selected(U.SelectProject{project}, application) == E.begin_task(project, application) : E.Decision},
    visibility_preserves_disclosure: @expanded:Bool -> @intent:E.NavigationIntent -> @+collapsed:+List<Nat> ->
      {disclosure(E.set_navigation(expanded, E.NavigationState{intent, collapsed})) == collapsed : +List<Nat>},
    visit_preserves_disclosure: @intent:E.NavigationIntent -> @+collapsed:+List<Nat> ->
      {disclosure(E.navigation_after_visit(E.NavigationState{intent, collapsed})) == collapsed : +List<Nat>},
    toggle_keeps_location: @+project:Nat -> @+world:M.World() -> @+route:U.Route -> @+drafts:+List<U.Draft> -> @+readers:+List<Finite.Entry(E.Reader)> -> @+layers:+List<E.Layer> -> @+attention:String -> @+navigation:E.NavigationState -> @+filter:B.Filter -> @+now:U32 -> @+next:Nat -> @+pending:+List<E.Pending> -> @+previews:+List<Live.Output> -> @+code:+List<Content.Block> ->
      toggle_keeps_location_law(project, world, route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code),
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
      project_actions_law(id, name, workspace, guidance, tasks, route, selected, navigation),
    details_entry: @+id:Nat -> @+now:U32 -> @+world:M.World() ->
      details_entry_law(id, now, world),
    chooser_single_name: @+id:Nat -> @+name:String -> @+workspace:D.Workspace ->
      {(View.creation_heading(Some{View.ProjectChoice{id, name, workspace}}), View.project_choice_label(Some{View.ProjectChoice{id, name, workspace}})) ==
    ("Work on", name) : Sigma<&2, &2, String, (_ => String)>},
    task_status_visible: @+id:Nat -> @title:String -> @+status:String -> @+selected:Bool -> @+open:View.ControlDeclaration -> @+parent:String -> @+state:Core.State ->
      task_status_visible_law(id, title, status, selected, open, parent, state),
    deletion_retains_other: @+prefix:+List<Nat> -> @+other:Nat -> @+suffix:+List<Nat> -> @+id:Nat -> @distinct:{Nat.is_eq(id, other) == False{} : Bool} ->
      {List.contains(~Nat, ~Nat.is_eq, E.without_collapsed_project(List.append(&2, Nat, prefix, other <> suffix), id), other) == True{} : Bool},
    toggle_retains_other: @+intent:E.NavigationIntent -> @+prefix:+List<Nat> -> @+other:Nat -> @+suffix:+List<Nat> -> @+id:Nat -> @distinct:{Nat.is_eq(id, other) == False{} : Bool} ->
      {E.project_collapsed(E.toggle_project_navigation(id, E.NavigationState{intent, List.append(&2, Nat, prefix, other <> suffix)}), other) == True{} : Bool},
    toggle_preserves_visibility: @+id:Nat -> @+intent:E.NavigationIntent -> @collapsed:+List<Nat> ->
      {E.navigation_visibility(E.toggle_project_navigation(id, E.NavigationState{intent, collapsed})) == intent : E.NavigationIntent},
    picker_complete_nodes: @+values:+List<View.ProjectChoice> -> @+selected:Maybe<&2, Nat> -> @+parent:String -> @+state:Core.State ->
      picker_complete_nodes_law(values, selected, parent, state),
    chooser_activation: @+context:Maybe<&2, Context.Preview> -> @+world:M.World() ->
      chooser_activation_law(context, world),
    picker_search_preserves_session: @+query:String -> @+world:M.World() -> @+route:U.Route -> @+drafts:+List<U.Draft> -> @+readers:+List<Finite.Entry(E.Reader)> -> @+trigger:String -> @+initial:String -> @previous:String -> @+rest:+List<E.Layer> -> @+attention:String -> @+navigation:E.NavigationState -> @+filter:B.Filter -> @+now:U32 -> @+next:Nat -> @+pending:+List<E.Pending> -> @+previews:+List<Live.Output> -> @+code:+List<Content.Block> ->
      picker_search_preserves_session_law(query, world, route, drafts, readers, trigger, initial, previous, rest, attention, navigation, filter, now, next, pending, previews, code),
    project_group_single_title: @+id:Nat -> @name:String -> @workspace:D.Workspace -> @+selected:Bool -> @+expanded:Bool -> @+tasks:+List<View.TaskEntry> -> @+open:View.ControlDeclaration -> @+create:View.ControlDeclaration -> @+toggle:View.ControlDeclaration -> @+more:View.ControlDeclaration -> @+parent:String -> @+state:Core.State ->
      project_group_single_title_law(id, name, workspace, selected, expanded, tasks, open, create, toggle, more, parent, state),
    committed_is_not_draft: @context:Context.EffectiveContext ->
      {View.draft_preview(Some{Context.CommittedExecution{context}}) == None{} : Maybe<&2, Context.Preview>},
    empty_project_collection: @+parent:String -> @state:Core.State ->
      empty_project_collection_law(parent, state),
    populated_project_collection: @+first:View.ProjectScene -> @+rest:+List<View.ProjectScene> -> @+parent:String -> @+state:Core.State ->
      {Interface.project_collection_entries(Con{first, rest}, parent, state) ==
    Interface.projects(Con{first, rest}, parent, state) : +List<Interface.Node>},
    select_focus_and_input: @+project:Maybe<&2, Nat> -> @+world:M.World() -> @route:U.Route -> @+revision:Nat -> @+message:U.Text -> @+profile:String -> @+reasoning:String -> @+old:Context.Origin -> @+workspace:Maybe<&2, D.Workspace> -> @+sandbox:Maybe<&2, D.Sandbox> -> @+approval:Maybe<&2, Context.ApprovalChoice> -> @+feedback:U.Feedback -> @+directory_entry:String -> @+rest:+List<U.Draft> -> @+readers:+List<Finite.Entry(E.Reader)> -> @layers:+List<E.Layer> -> @attention:String -> @+navigation:E.NavigationState -> @+filter:B.Filter -> @+now:U32 -> @+next:Nat -> @+pending:+List<E.Pending> -> @+previews:+List<Live.Output> -> @+code:+List<Content.Block> ->
      select_focus_and_input_law(project, world, route, revision, message, profile, reasoning, old, workspace, sandbox, approval, feedback, directory_entry, rest, readers, layers, attention, navigation, filter, now, next, pending, previews, code),
    missing_draft_focus: @+project:Maybe<&2, Nat> -> @+world:M.World() -> @route:U.Route -> @+readers:+List<Finite.Entry(E.Reader)> -> @layers:+List<E.Layer> -> @attention:String -> @+navigation:E.NavigationState -> @+filter:B.Filter -> @+now:U32 -> @+next:Nat -> @+pending:+List<E.Pending> -> @+previews:+List<Live.Output> -> @+code:+List<Content.Block> ->
      missing_draft_focus_law(project, world, route, readers, layers, attention, navigation, filter, now, next, pending, previews, code)}

def evidence() -> Requirements:
  Requirements{
    origin => message => profile => reasoning => old => workspace => sandbox => approval => world => switch_preserves_input(origin, message, profile, reasoning, old, workspace, sandbox, approval, world),
    project => application => select_reuses_draft(project, application),
    expanded => intent => collapsed => visibility_preserves_disclosure(expanded, intent, collapsed),
    intent => collapsed => visit_preserves_disclosure(intent, collapsed),
    project => world => route => drafts => readers => layers => attention => navigation => filter => now => next => pending => previews => code => toggle_keeps_location(project, world, route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code),
    id => drafts => world => task_ownership(id, drafts, world),
    drafts => world => draft_ownership(drafts, world),
    entries => registered_choices_complete(entries),
    query => selected => projects => picker_filter_keeps_selection(query, selected, projects),
    id => name => workspace => guidance => tasks => route => selected => navigation => project_actions(id, name, workspace, guidance, tasks, route, selected, navigation),
    id => now => world => details_entry(id, now, world),
    id => name => workspace => chooser_single_name(id, name, workspace),
    id => title => status => selected => open => parent => state => task_status_visible(id, title, status, selected, open, parent, state),
    prefix => other => suffix => id => distinct => deletion_retains_other(prefix, other, suffix, id, distinct),
    intent => prefix => other => suffix => id => distinct => toggle_retains_other(intent, prefix, other, suffix, id, distinct),
    id => intent => collapsed => toggle_preserves_visibility(id, intent, collapsed),
    values => selected => parent => state => picker_complete_nodes(values, selected, parent, state),
    context => world => chooser_activation(context, world),
    query => world => route => drafts => readers => trigger => initial => previous => rest => attention => navigation => filter => now => next => pending => previews => code => picker_search_preserves_session(query, world, route, drafts, readers, trigger, initial, previous, rest, attention, navigation, filter, now, next, pending, previews, code),
    id => name => workspace => selected => expanded => tasks => open => create => toggle => more => parent => state => project_group_single_title(id, name, workspace, selected, expanded, tasks, open, create, toggle, more, parent, state),
    context => committed_is_not_draft(context),
    parent => state => empty_project_collection(parent, state),
    first => rest => parent => state => populated_project_collection(first, rest, parent, state),
    project => world => route => revision => message => profile => reasoning => old => workspace => sandbox => approval => feedback => directory_entry => rest => readers => layers => attention => navigation => filter => now => next => pending => previews => code => select_focus_and_input(project, world, route, revision, message, profile, reasoning, old, workspace, sandbox, approval, feedback, directory_entry, rest, readers, layers, attention, navigation, filter, now, next, pending, previews, code),
    project => world => route => readers => layers => attention => navigation => filter => now => next => pending => previews => code => missing_draft_focus(project, world, route, readers, layers, attention, navigation, filter, now, next, pending, previews, code)}
