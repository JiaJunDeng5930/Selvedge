import Base
import ../../features/board/MODEL.bend as B
import ../INPUT.bend as U
import ../../harness/MODEL.bend as M
import ./CONTRACT.bend as Rule
import ./VIEW.bend as View
import ../IDENTITY.bend as Identity
import ./PROGRAM.bend as Model
import ./SURFACE.bend as SurfaceTypes
import ./MODEL.bend as V
import ../session/MODEL.bend as E
import ../services/MODEL.bend as Services
import ../STATE.bend as Core
import ../../features/board/STATE.bend as Board
import ../../features/board/filter.bend as Filter
import ../../bendlib/association-map.bend as Finite
import ../TYPES.bend as InteractionTypes
import ../../harness/DOMAIN.bend as D
import ../../harness/workspace/PROJECTS.bend as Projects
import ../../harness/features/MODEL.bend as F
import ../../harness/transport/schema.bend as Schema
import ../../bendlib/stdlib.bend as Std
import ../services/CONTEXT.bend as Context
import ../submission/PROOF.bend as SubmissionProof

def card_opens_details(+id: Nat, card: B.Card, route: U.Route, now: U32, world: M.World()) ->
  {Rule.opening(View.card_scene(id, card, route, now, world)) ==
    U.Activate{U.OpenPanel{U.CardDetails{id}, "card/" ++ Nat.show(id)}} : U.Input}:
  B.Card{revision, draft, task, archived, created, updated, enrichment, error, pinned} = card
  {==}

def actual_card_errors(+card: B.Card, +parent: Identity.Key) ->
  {Model.card_error_observations(card, parent) ==
        [Model.project_fact(Identity.Part{parent, "enrichment"}, "生成", Model.enrichment_observation(B.enrichment(card))),
         Model.project_fact(Identity.Part{parent, "start-error"}, "启动错误", B.start_error(card))] : +List<SurfaceTypes.Node>}:
  B.Card{revision, draft, task, archived, created, updated, enrichment, error, pinned} = card
  {==}

def agent_row_observes_profile(+agent: B.AgentProfile, +id: Nat, +edit: V.ControlDeclaration, +parent: Identity.Key, +world: M.World(), +session: E.Session, +services: Services.State) ->
  {Model.agent_observation(id, agent, edit, parent, Core.from_application(E.from_program(world, session), services)) ==
        SurfaceTypes.Node{Identity.Entity{parent, "agent", Nat.show(id)}, "agent/" ++ Nat.show(id), B.agent_name(agent), SurfaceTypes.Section{}, SurfaceTypes.Region{}, [Model.project_fact(Identity.Part{Identity.Entity{parent, "agent", Nat.show(id)}, "profile"}, "模型", B.agent_profile(agent)),
           Model.project_fact(Identity.Part{Identity.Entity{parent, "agent", Nat.show(id)}, "reasoning"}, "推理", B.agent_reasoning(agent)),
           Model.project_fact(Identity.Part{Identity.Entity{parent, "agent", Nat.show(id)}, "instructions"}, "指令", B.agent_instructions(agent)),
           Model.project_fact(Identity.Part{Identity.Entity{parent, "agent", Nat.show(id)}, "concurrency"}, "并发上限", Nat.show(B.agent_concurrency(agent))),
           Model.project_fact(Identity.Part{Identity.Entity{parent, "agent", Nat.show(id)}, "active"}, "工作中", Nat.show(Board.active_for(B.cards(Board.registry(world)), B.Agent{id}, world))),
           Model.declared(Identity.Entity{parent, "agent", Nat.show(id)}, edit, Core.from_application(E.from_program(world, session), services)),
           Model.more(U.AgentSubject{id}, Identity.Entity{parent, "agent", Nat.show(id)}, Core.from_application(E.from_program(world, session), services))]} : SurfaceTypes.Node}:
  B.AgentProfile{revision, name, profile, reasoning, instructions, settings, concurrency} = agent
  {==}

def Rule.board_capability_evidence():
  Rule.BoardCapabilityRequirements{
    card_opens_details,
    +view => +search => +status => +priority => +date => +assignee => +creator => +project => +labels => +parent => +state => {==},
    +id => +title => +status => +selected => +open => +parent => +state => {==},
    parent => state => {==},
    +reason => {==},
    actual_card_errors,
    +parent => state => {==},
    id => revision => state => {==},
    agent_row_observes_profile}

def card_title_is_preserved(+id: Nat, +card: B.Card, +now: U32, +world: M.World()) ->
  {Rule.face_title(View.card_face(id, card, now, world)) == B.title(B.draft(card)) : String}:
  {==}

def card_description_is_preserved(+id: Nat, +card: B.Card, +now: U32, +world: M.World()) ->
  {Rule.face_description(View.card_face(id, card, now, world)) == B.description(B.draft(card)) : String}:
  {==}

def card_priority_is_preserved(+id: Nat, +card: B.Card, +now: U32, +world: M.World()) ->
  {Rule.face_priority(View.card_face(id, card, now, world)) == B.card_priority(B.draft(card)) : B.Priority}:
  {==}

def card_pin_is_preserved(+id: Nat, +card: B.Card, +now: U32, +world: M.World()) ->
  {Rule.face_pinned(View.card_face(id, card, now, world)) == B.pinned(card) : Bool}:
  {==}

def card_status_is_observed(+id: Nat, +card: B.Card, +now: U32, +world: M.World()) ->
  {Rule.face_status(View.card_face(id, card, now, world)) == Board.activity_label(Board.activity(card, world)) : String}:
  {==}

def card_project_is_resolved(+id: Nat, +card: B.Card, +now: U32, +world: M.World()) ->
  {Rule.face_project(View.card_face(id, card, now, world)) == View.face_project(B.project(B.draft(card)), world) : String}:
  {==}

def card_labels_are_preserved(+id: Nat, +card: B.Card, +now: U32, +world: M.World()) ->
  {Rule.face_labels(View.card_face(id, card, now, world)) == B.labels(B.draft(card)) : +List<String>}:
  {==}

def card_owner_is_resolved(+id: Nat, +card: B.Card, +now: U32, +world: M.World()) ->
  {Rule.face_owner(View.card_face(id, card, now, world)) == View.face_owner(B.card_owner(B.draft(card)), world) : String}:
  {==}

def card_updated_uses_elapsed_clock(+id: Nat, +card: B.Card, +now: U32, +world: M.World()) ->
  {Rule.face_updated(View.card_face(id, card, now, world)) == View.elapsed_label(Filter.elapsed(now, B.updated(card))) : String}:
  {==}

def card_scene_ids_cons(head: V.CardScene, +rest: +List<V.CardScene>) ->
  {Rule.card_scene_ids(head <> rest) == Rule.card_scene_identity(head) <> Rule.card_scene_ids(rest) : +List<Nat>}:
  V.CardScene{id, value, open, actions, linked, destinations, candidates} = head
  {==}

def card_scene_identity_is_input(id: Nat, revision: Nat, draft: B.Draft, task: Maybe<&2, Nat>, archived: Bool,
  created: U32, updated: U32, enrichment: B.Enrichment, start_error: String, pinned: Bool,
  route: U.Route, +now: U32, +world: M.World()) ->
  {Rule.card_scene_identity(View.card_scene(id, B.Card{revision, draft, task, archived, created, updated, enrichment, start_error, pinned}, route, now, world)) == id : Nat}:
  {==}

def card_scenes_keep_ids(+entries: +List<Finite.Entry(B.Card)>, +route: U.Route, +now: U32, +world: M.World()) ->
  {Rule.card_scene_ids(View.card_scenes(entries, route, now, world)) == Rule.board_entry_ids(entries) : +List<Nat>}:
  match entries:
    case Nil{}: {==}
    case Con{(+id, +card), +rest}:
      B.Card{revision, draft, task, archived, created, updated, enrichment, start_error, pinned} = card
      +materialized: B.Card = B.Card{revision, draft, task, archived, created, updated, enrichment, start_error, pinned}
      Equal.trans(+List<Nat>,
        Rule.card_scene_ids(View.card_scene(id, materialized, route, now, world) <> View.card_scenes(rest, route, now, world)),
        Rule.card_scene_identity(View.card_scene(id, materialized, route, now, world)) <> Rule.card_scene_ids(View.card_scenes(rest, route, now, world)),
        id <> Rule.board_entry_ids(rest),
        card_scene_ids_cons(View.card_scene(id, materialized, route, now, world), View.card_scenes(rest, route, now, world)),
        Equal.trans(+List<Nat>,
          Rule.card_scene_identity(View.card_scene(id, materialized, route, now, world)) <> Rule.card_scene_ids(View.card_scenes(rest, route, now, world)),
          id <> Rule.card_scene_ids(View.card_scenes(rest, route, now, world)), id <> Rule.board_entry_ids(rest),
          Equal.cong(Nat, +List<Nat>, (head_id => head_id <> Rule.card_scene_ids(View.card_scenes(rest, route, now, world))),
            Rule.card_scene_identity(View.card_scene(id, materialized, route, now, world)), id,
            card_scene_identity_is_input(id, revision, draft, task, archived, created, updated, enrichment, start_error, pinned, route, now, world)),
          Equal.cong(+List<Nat>, +List<Nat>, (tail => id <> tail), Rule.card_scene_ids(View.card_scenes(rest, route, now, world)),
            Rule.board_entry_ids(rest), card_scenes_keep_ids(rest, route, now, world))))

def card_roots_keep_length(+entries: +List<V.CardScene>, +parent: Identity.Key, +state: InteractionTypes.State) ->
  {List.length(&2, SurfaceTypes.Node, Model.cards(entries, parent, state)) == List.length(&2, V.CardScene, entries) : Nat}:
  match entries:
    case Nil{}: {==}
    case Con{+entry, +rest}:
      Equal.cong(Nat, Nat, (tail => (1n + tail : Nat)),
        List.length(&2, SurfaceTypes.Node, Model.cards(rest, parent, state)),
        List.length(&2, V.CardScene, rest), card_roots_keep_length(rest, parent, state))

def lane_children_are_create_plus_cards(stage: B.Stage, +entries: +List<V.CardScene>, +create: V.ControlDeclaration,
  +parent: Identity.Key, +state: InteractionTypes.State) ->
  {Rule.first_lane_child_count(Model.columns([V.BoardColumn{stage, entries, create}], parent, state)) ==
    Some{(1n + List.length(&2, V.CardScene, entries) : Nat)} : Maybe<&2, Nat>}:
  +lane_key: Identity.Key = Identity.Part{parent, B.stage_name(stage)}
  children_count = card_roots_keep_length(entries, lane_key, state)
  Equal.cong(Nat, Maybe<&2, Nat>, (cards => Some{(1n + cards : Nat)}),
    List.length(&2, SurfaceTypes.Node, Model.cards(entries, lane_key, state)),
    List.length(&2, V.CardScene, entries), children_count)

def selected_work_child_identity(selected: Bool, +node: SurfaceTypes.Node, +parent: Identity.Key, rest: +List<SurfaceTypes.Node>) ->
  {Rule.work_status_child_key(Model.board_group(parent, "work-status", SurfaceTypes.WorkStatus{}, [Model.selected_node(selected, node)]) <> rest) ==
    Some{Model.node_key(node)} : Maybe<&2, String>}:
  match selected:
    case True{}:
      SurfaceTypes.Node{key, semantic, label, role, meaning, children} = node
      {==}
    case False{}:
      SurfaceTypes.Node{key, semantic, label, role, meaning, children} = node
      {==}

def board_toolbar_work_status_identity(+filter: B.Filter, working: Nat, create: V.ControlDeclaration,
  settings: V.ControlDeclaration, filters: V.ControlDeclaration, archive: V.ControlDeclaration,
  +parent: Identity.Key, +state: InteractionTypes.State) ->
  {Rule.work_status_child_key(Model.board_toolbar(filter, working, create, settings, filters, archive, parent, state)) ==
    Some{Identity.encode(Identity.Part{Identity.Part{parent, "work-status"}, "view/working"})} : Maybe<&2, String>}:
  B.Filter{+view, search, status, priority, date, assignee, creator, project, labels} = filter
  InteractionTypes.State{application, services} = state
  selected_work_child_identity(String.eq(view, "working"),
    Model.declared(Identity.Part{parent, "work-status"},
      V.ControlDeclaration{"view/working", "正在运行的任务 " ++ Nat.show(working), V.Secondary{},
        U.FilterBoard{B.Filter{"working", search, status, priority, date, assignee, creator, project, labels}}, V.Available{}},
      InteractionTypes.State{application, services}), parent,
    [Model.board_group(parent, "secondary-actions", SurfaceTypes.SecondaryActions{},
      [Model.declared(parent, filters, InteractionTypes.State{application, services}), Model.declared(parent, settings, InteractionTypes.State{application, services}),
       Model.archive_destination(archive, parent, InteractionTypes.State{application, services})]),
     Model.board_group(parent, "primary-action", SurfaceTypes.PrimaryAction{}, [Model.declared(parent, create, InteractionTypes.State{application, services})])])

def navigation_header_keeps_brand(+navigation: V.Navigation, +state: InteractionTypes.State) ->
  {Rule.navigation_header_label(Model.navigation(navigation, state)) == Some{"Selvedge"} : Maybe<&2, String>}:
  V.Navigation{expanded, create, destinations, projects, tasks, toggle} = navigation
  InteractionTypes.State{E.Application{world, E.Session{route, drafts, readers, layers, attention, stored_navigation,
    filter, now, next, pending, previews, code, next_layer}}, services} = state
  {==}

def navigation_header_contains_only_toggle(+navigation: V.Navigation, +state: InteractionTypes.State) ->
  {Rule.navigation_header_children(Model.navigation(navigation, state)) ==
    Some{[Model.declared(Identity.Place{"/navigation"}, Rule.navigation_toggle_control(navigation), state)]} : Maybe<&2, +List<SurfaceTypes.Node>>}:
  V.Navigation{expanded, create, destinations, projects, tasks, toggle} = navigation
  InteractionTypes.State{E.Application{world, E.Session{route, drafts, readers, layers, attention, stored_navigation,
    filter, now, next, pending, previews, code, next_layer}}, services} = state
  {==}

def display_cards_are_pinned_partition(+board: B.State) ->
  {Board.display_cards(board) == Rule.pinned_partition(board) : +List<Finite.Entry(B.Card)>}:
  {==}

def board_page_column_ids_match_display(+board: B.State, +filter: B.Filter, +route: U.Route,
  +now: U32, +world: M.World(), target: B.Stage) ->
  {Rule.board_page_column_ids(View.board_page(board, filter, route, now, world), target) ==
    Rule.board_entry_ids(Filter.column(Filter.filtered(Board.display_cards(board), filter, now, world), B.stage_name(target))) : +List<Nat>}:
  match target:
    case B.Backlog{}: card_scenes_keep_ids(Filter.column(Filter.filtered(Board.display_cards(board), filter, now, world), B.stage_name(B.Backlog{})), route, now, world)
    case B.Todo{}: card_scenes_keep_ids(Filter.column(Filter.filtered(Board.display_cards(board), filter, now, world), B.stage_name(B.Todo{})), route, now, world)
    case B.InProgress{}: card_scenes_keep_ids(Filter.column(Filter.filtered(Board.display_cards(board), filter, now, world), B.stage_name(B.InProgress{})), route, now, world)
    case B.InReview{}: card_scenes_keep_ids(Filter.column(Filter.filtered(Board.display_cards(board), filter, now, world), B.stage_name(B.InReview{})), route, now, world)
    case B.Completed{}: card_scenes_keep_ids(Filter.column(Filter.filtered(Board.display_cards(board), filter, now, world), B.stage_name(B.Completed{})), route, now, world)
    case B.Blocked{}: card_scenes_keep_ids(Filter.column(Filter.filtered(Board.display_cards(board), filter, now, world), B.stage_name(B.Blocked{})), route, now, world)

def search_change_preserves_filter_facets(+search: String, +filter: B.Filter) ->
  {Model.with_search(search, filter) == Rule.search_filter(search, filter) : B.Filter}:
  match filter:
    case B.Filter{view, old_search, status, priority, date, assignee, creator, project, label}: {==}

def status_toggle_preserves_other_facets(+value: String, +filter: B.Filter) ->
  {Model.toggle_filter("status", value, filter) == Rule.toggled_status_filter(value, filter) : B.Filter}:
  match filter:
    case B.Filter{view, search, status, priority, date, assignee, creator, project, label}: {==}

def priority_toggle_preserves_other_facets(+value: String, +filter: B.Filter) ->
  {Model.toggle_filter("priority", value, filter) == Rule.toggled_priority_filter(value, filter) : B.Filter}:
  match filter:
    case B.Filter{view, search, status, priority, date, assignee, creator, project, label}: {==}

def date_toggle_preserves_other_facets(+value: String, +filter: B.Filter) ->
  {Model.toggle_filter("date", value, filter) == Rule.toggled_date_filter(value, filter) : B.Filter}:
  match filter:
    case B.Filter{view, search, status, priority, date, assignee, creator, project, label}: {==}

def assignee_toggle_preserves_other_facets(+value: String, +filter: B.Filter) ->
  {Model.toggle_filter("assignee", value, filter) == Rule.toggled_assignee_filter(value, filter) : B.Filter}:
  match filter:
    case B.Filter{view, search, status, priority, date, assignee, creator, project, label}: {==}

def creator_toggle_preserves_other_facets(+value: String, +filter: B.Filter) ->
  {Model.toggle_filter("creator", value, filter) == Rule.toggled_creator_filter(value, filter) : B.Filter}:
  match filter:
    case B.Filter{view, search, status, priority, date, assignee, creator, project, label}: {==}

def project_toggle_preserves_other_facets(+value: String, +filter: B.Filter) ->
  {Model.toggle_filter("project", value, filter) == Rule.toggled_project_filter(value, filter) : B.Filter}:
  match filter:
    case B.Filter{view, search, status, priority, date, assignee, creator, project, label}: {==}

def label_toggle_preserves_other_facets(+value: String, +filter: B.Filter) ->
  {Model.toggle_filter("label", value, filter) == Rule.toggled_label_filter(value, filter) : B.Filter}:
  match filter:
    case B.Filter{view, search, status, priority, date, assignee, creator, project, label}: {==}

def board_route_selects_board_nav(+world: M.World(), +session: E.Session) ->
  {Rule.board_navigation_selected(U.TaskBoard{}, world, session) == True{} : Bool}:
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code, next_layer} = session
  {==}

def projects_route_selects_projects_nav(+world: M.World(), +session: E.Session) ->
  {Rule.projects_navigation_selected(U.ProjectCollection{}, world, session) == True{} : Bool}:
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code, next_layer} = session
  {==}

def agents_route_selects_agents_nav(+world: M.World(), +session: E.Session) ->
  {Rule.agents_navigation_selected(U.AgentCollection{}, world, session) == True{} : Bool}:
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code, next_layer} = session
  {==}

def start_route_selects_create_nav(+world: M.World(), +session: E.Session) ->
  {Rule.create_navigation_selected(U.Start{}, world, session) == True{} : Bool}:
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code, next_layer} = session
  {==}

def board_route_rejects_other_nav(+world: M.World(), +session: E.Session) ->
  {(Rule.projects_navigation_selected(U.TaskBoard{}, world, session), Rule.agents_navigation_selected(U.TaskBoard{}, world, session)) ==
    (False{}, False{}) : Bool & Bool}:
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code, next_layer} = session
  {==}

def projects_route_rejects_other_nav(+world: M.World(), +session: E.Session) ->
  {(Rule.board_navigation_selected(U.ProjectCollection{}, world, session), Rule.agents_navigation_selected(U.ProjectCollection{}, world, session)) ==
    (False{}, False{}) : Bool & Bool}:
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code, next_layer} = session
  {==}

def agents_route_rejects_other_nav(+world: M.World(), +session: E.Session) ->
  {(Rule.board_navigation_selected(U.AgentCollection{}, world, session), Rule.projects_navigation_selected(U.AgentCollection{}, world, session)) ==
    (False{}, False{}) : Bool & Bool}:
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code, next_layer} = session
  {==}

def start_route_rejects_destination_nav(+world: M.World(), +session: E.Session) ->
  {(Rule.board_navigation_selected(U.Start{}, world, session), Rule.projects_navigation_selected(U.Start{}, world, session), Rule.agents_navigation_selected(U.Start{}, world, session)) ==
    (False{}, (False{}, False{})) : Bool & (Bool & Bool)}:
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code, next_layer} = session
  {==}

def selected_declaration_role_tracks_predicate(+route: U.Route, +parent: Identity.Key,
  declaration: V.ControlDeclaration, +state: InteractionTypes.State) ->
  {Model.node_role(Model.selected_declaration(route, parent, declaration, state)) ==
    Model.node_role(Model.selected_node(Model.navigation_action_selected(route, Rule.declaration_input(declaration)),
      Model.declared(parent, declaration, state))) : SurfaceTypes.Role}:
  match declaration:
    case V.ControlDeclaration{identity, label, prominence, input, availability}:
      {==}

def board_settings_preserve_state(+board: B.State, +world: M.World()) ->
  Rule.settings_state_law(board, world):
  match board:
    case B.State{cards, next_card, agents, next_agent, automatic, draft_profile}: {==}

def Rule.board_presentation_evidence():
  Rule.BoardPresentationRequirements{
    +id => +card => +now => +world => {==},
    id => card => now => world =>
      (card_title_is_preserved(id, card, now, world), card_description_is_preserved(id, card, now, world),
       card_priority_is_preserved(id, card, now, world), card_pin_is_preserved(id, card, now, world),
       card_labels_are_preserved(id, card, now, world)),
    id => card => now => world =>
      (card_status_is_observed(id, card, now, world), card_project_is_resolved(id, card, now, world),
       card_owner_is_resolved(id, card, now, world), card_updated_uses_elapsed_clock(id, card, now, world)),
    entries => route => now => world => card_scenes_keep_ids(entries, route, now, world),
    entries => parent => state => card_roots_keep_length(entries, parent, state),
    stage => +entries => +create => +parent => +state => {==},
    stage => entries => create => parent => state => lane_children_are_create_plus_cards(stage, entries, create, parent, state),
    filter => working => create => settings => filters => archive => parent => state =>
      board_toolbar_work_status_identity(filter, working, create, settings, filters, archive, parent, state),
    navigation => state => navigation_header_keeps_brand(navigation, state),
    navigation => state => navigation_header_contains_only_toggle(navigation, state),
    board => display_cards_are_pinned_partition(board),
    +board => +filter => +route => +now => +world => target =>
      Equal.trans(+List<Nat>,
        Rule.board_page_column_ids(View.board_page(board, filter, route, now, world), target),
        Rule.board_entry_ids(Filter.column(Filter.filtered(Board.display_cards(board), filter, now, world), B.stage_name(target))),
        Rule.board_entry_ids(Filter.column(Filter.filtered(Rule.pinned_partition(board), filter, now, world), B.stage_name(target))),
        board_page_column_ids_match_display(board, filter, route, now, world, target),
        Equal.cong(+List<Finite.Entry(B.Card)>, +List<Nat>,
          (entries => Rule.board_entry_ids(Filter.column(Filter.filtered(entries, filter, now, world), B.stage_name(target)))),
          Board.display_cards(board), Rule.pinned_partition(board), display_cards_are_pinned_partition(board)))
    ,
    +world => {==},
    +id => +world => absent =>
      Equal.cong(Maybe<&2, D.Project>, String,
        (found => View.face_project_name(found, id)),
        Projects.find(Projects.registry(F.State(), world), id), None{}, absent)
    ,
    +key => +world => absent =>
      Equal.cong(Maybe<&2, D.Profile>, String,
        (found => View.face_profile_name(found, key)), D.find_profile(Board.profiles(world), key), None{}, absent)
    ,
    id => +world => absent =>
      Equal.cong(Maybe<&2, B.AgentProfile>, String,
        (found => View.face_agent_name(found, id)), B.find_agent(Board.registry(world), id), None{}, absent)
    ,
    search => filter => search_change_preserves_filter_facets(search, filter),
    value => filter => status_toggle_preserves_other_facets(value, filter),
    value => filter => priority_toggle_preserves_other_facets(value, filter),
    value => filter => date_toggle_preserves_other_facets(value, filter),
    value => filter => assignee_toggle_preserves_other_facets(value, filter),
    value => filter => creator_toggle_preserves_other_facets(value, filter),
    value => filter => project_toggle_preserves_other_facets(value, filter),
    value => filter => label_toggle_preserves_other_facets(value, filter),
    board => +filter => +route => +now => +world => {==},
    board => +filter => +route => +now => +world => {==},
    stage => +route => +now => +world => {==},
    stage => +route => +now => +world => {==},
    world => session => board_route_selects_board_nav(world, session),
    world => session => projects_route_selects_projects_nav(world, session),
    world => session => agents_route_selects_agents_nav(world, session),
    world => session => start_route_selects_create_nav(world, session),
    world => session => board_route_rejects_other_nav(world, session),
    world => session => projects_route_rejects_other_nav(world, session),
    world => session => agents_route_rejects_other_nav(world, session),
    world => session => start_route_rejects_destination_nav(world, session),
    route => parent => declaration => state => selected_declaration_role_tracks_predicate(route, parent, declaration, state),
    board => world => board_settings_preserve_state(board, world),
    +session => +world => {==},
    stage => +application => {==},
    stage => {==},
    id => +application => {==}
  }

def finite_choice_payload(+kind: SurfaceTypes.ChoiceKind, +classification: Maybe<&2,Filter.Classification>, +selected: Bool, +description: String, +control: InteractionTypes.Control, parent: Identity.Key) ->
  {Rule.meaning(Model.finite_choice_control(kind, classification, selected, description, control, parent)) ==
    SurfaceTypes.Choice{kind, classification, selected, description, Rule.control_input(control), Rule.control_availability(control)} : SurfaceTypes.Meaning}:
  match selected:
    case True{}:
      InteractionTypes.Control{identity, label, prominence, input, availability} = control
      {==}
    case False{}:
      InteractionTypes.Control{identity, label, prominence, input, availability} = control
      {==}

def filter_payload(+choice: Filter.Choice, +category: String, +filter: B.Filter, parent: Identity.Key, +state: InteractionTypes.State) ->
  {Rule.meaning(Model.filter_option_node(choice, category, filter, parent, state)) ==
    SurfaceTypes.Choice{SurfaceTypes.MultipleChoice{}, Some{Rule.filter_classification(choice)},
      Schema.contains(Filter.values(category, filter), Rule.filter_value(choice)), "",
      Rule.control_input(Core.control(state, Model.filter_option_declaration(choice, category, filter))),
      Rule.control_availability(Core.control(state, Model.filter_option_declaration(choice, category, filter)))} : SurfaceTypes.Meaning}:
  Filter.Choice{+value, label, classification} = choice
  finite_choice_payload(SurfaceTypes.MultipleChoice{}, Some{classification},
    Schema.contains(Filter.values(category, filter), value), "",
    Core.control(state, Model.filter_option_declaration(choice, category, filter)), Identity.Entity{parent, "filter-option", value})

def Rule.choice_evidence():
  Rule.ChoiceRequirements{
    kind => classification => selected => description => +input => +availability => {==},
    kind => classification => selected => description => input => +availability => {==},
    choice => category => filter => parent => state => filter_payload(choice, category, filter, parent, state),
    +owner => world => {==},
    +owner => +world => {==},
    value => projects => stages => priorities => +owners => {==},
    value => projects => stages => +priorities => owners => {==}}

# Only direct page regions participate; an entry's ordinary heading is never promoted.

def registered_choices_complete(+entries: +List<Finite.Entry(D.Project)>) ->
  {List.length(&2, V.ProjectChoice, View.project_choices(entries)) == List.length(&2, Finite.Entry(D.Project), entries) : Nat}:
  match entries:
    case Nil{}: {==}
    case Con{(id, D.Project{name, workspace, guidance}), +rest}:
      Equal.cong(Nat, Nat, (n => (1n + n : Nat)), List.length(&2, V.ProjectChoice, View.project_choices(rest)), List.length(&2, Finite.Entry(D.Project), rest), registered_choices_complete(rest))

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

def picker_complete_nodes(+values: +List<V.ProjectChoice>, +selected: Maybe<&2, Nat>, +parent: Identity.Key, +state: InteractionTypes.State) -> Rule.picker_nodes(values, selected, parent, state):
  {==}

def encapsulated_missing_draft_focus(+session: E.Session, +project: Maybe<&2, Nat>, +world: M.World(), observed_drafts: {E.drafts(session) == Nil{} : +List<U.Draft>}) ->
  {E.activate_selected(U.SelectProject{project}, E.from_program(world, session)) ==
        E.local(world, E.with_navigation(E.navigation_after_visit(E.navigation(session)), E.with_attention("composer/" ++ U.editor_key(U.NewTaskEditor{}), E.with_layers(Nil{}, E.with_route(U.Start{}, session)))),
          [E.Attend{"composer/" ++ U.editor_key(U.NewTaskEditor{})}]) : E.Decision}:
  E.Session{+route, +stored_drafts, +readers, +layers, +attention, +navigation, +filter, +now, +next, +pending, +previews, +code, +next_layer} = session
  backwards_drafts = Equal.sym(E.Session, session, E.with_drafts(Nil{}, session),
    Equal.cong(+List<U.Draft>, E.Session, value => E.with_drafts(value, session), E.drafts(session), Nil{}, observed_drafts))
  %backwards_drafts : {E.activate_selected(U.SelectProject{project}, E.from_program(world, _)) ==
        E.local(world, E.with_navigation(E.navigation_after_visit(E.navigation(_)), E.with_attention("composer/" ++ U.editor_key(U.NewTaskEditor{}), E.with_layers(Nil{}, E.with_route(U.Start{}, _)))),
          [E.Attend{"composer/" ++ U.editor_key(U.NewTaskEditor{})}]) : E.Decision}
  {==}

def encapsulated_select_focus_and_input(+session: E.Session, +project: Maybe<&2, Nat>, +world: M.World(), +revision: Nat, +message: U.Text, +profile: String, +reasoning: String, +old: Context.Origin, +workspace: Maybe<&2, D.Workspace>, +sandbox: Maybe<&2, D.Sandbox>, +approval: Maybe<&2, Context.ApprovalChoice>, +feedback: U.Feedback, +directory_entry: String, +rest: +List<U.Draft>, observed_drafts: {E.drafts(session) == U.Draft{revision, U.NewTask{message, profile, reasoning, Context.Configuration{old, workspace, sandbox, approval}}, feedback, directory_entry} <> rest : +List<U.Draft>}) ->
  {E.activate_selected(U.SelectProject{project}, E.from_program(world, session)) ==
        E.local(world, E.with_navigation(E.navigation_after_visit(E.navigation(session)), E.with_attention("composer/" ++ U.editor_key(U.NewTaskEditor{}), E.with_layers(Nil{}, E.with_drafts(E.put_draft(U.Draft{(revision + 1n : Nat), U.NewTask{message, profile, reasoning, Context.Configuration{E.context_project(project), workspace, sandbox, approval}}, U.Editing{}, directory_entry},
            U.Draft{revision, U.NewTask{message, profile, reasoning, Context.Configuration{old, workspace, sandbox, approval}}, feedback, directory_entry} <> rest), E.with_route(U.Start{}, session))))),
          [E.Attend{"composer/" ++ U.editor_key(U.NewTaskEditor{})}]) : E.Decision}:
  E.Session{+route, +stored_drafts, +readers, +layers, +attention, +navigation, +filter, +now, +next, +pending, +previews, +code, +next_layer} = session
  backwards_drafts = Equal.sym(E.Session, session, E.with_drafts(U.Draft{revision, U.NewTask{message, profile, reasoning, Context.Configuration{old, workspace, sandbox, approval}}, feedback, directory_entry} <> rest, session),
    Equal.cong(+List<U.Draft>, E.Session, value => E.with_drafts(value, session), E.drafts(session), U.Draft{revision, U.NewTask{message, profile, reasoning, Context.Configuration{old, workspace, sandbox, approval}}, feedback, directory_entry} <> rest, observed_drafts))
  %backwards_drafts : {E.activate_selected(U.SelectProject{project}, E.from_program(world, _)) ==
        E.local(world, E.with_navigation(E.navigation_after_visit(E.navigation(_)), E.with_attention("composer/" ++ U.editor_key(U.NewTaskEditor{}), E.with_layers(Nil{}, E.with_drafts(E.put_draft(U.Draft{(revision + 1n : Nat), U.NewTask{message, profile, reasoning, Context.Configuration{E.context_project(project), workspace, sandbox, approval}}, U.Editing{}, directory_entry},
            U.Draft{revision, U.NewTask{message, profile, reasoning, Context.Configuration{old, workspace, sandbox, approval}}, feedback, directory_entry} <> rest), E.with_route(U.Start{}, _))))),
          [E.Attend{"composer/" ++ U.editor_key(U.NewTaskEditor{})}]) : E.Decision}
  {==}

def encapsulated_picker_search_preserves_session(+session: E.Session, +query: String, +world: M.World(), +trigger: String, +initial: String, previous: String, +layer_occurrence: Nat, +rest: +List<E.Layer>, observed_layers: {E.layers(session) == E.Layer{U.ProjectPicker{}, trigger, initial, previous, layer_occurrence} <> rest : +List<E.Layer>}) ->
  {E.search_choices(query, E.from_program(world, session)) ==
        E.local(world, E.with_layers(E.Layer{U.ProjectPicker{}, trigger, initial, query, layer_occurrence} <> rest, session), Nil{}) : E.Decision}:
  E.Session{+route, +drafts, +readers, +stored_layers, +attention, +navigation, +filter, +now, +next, +pending, +previews, +code, +next_layer} = session
  backwards_layers = Equal.sym(E.Session, session, E.with_layers(E.Layer{U.ProjectPicker{}, trigger, initial, previous, layer_occurrence} <> rest, session),
    Equal.cong(+List<E.Layer>, E.Session, value => E.with_layers(value, session), E.layers(session), E.Layer{U.ProjectPicker{}, trigger, initial, previous, layer_occurrence} <> rest, observed_layers))
  %backwards_layers : {E.search_choices(query, E.from_program(world, _)) ==
        E.local(world, E.with_layers(E.Layer{U.ProjectPicker{}, trigger, initial, query, layer_occurrence} <> rest, _), Nil{}) : E.Decision}
  {==}

def encapsulated_toggle_keeps_location(+session: E.Session, +project: Nat, +world: M.World()) ->
  {E.toggle_project(project, E.from_program(world, session)) ==
        E.local(world, E.with_navigation(E.toggle_project_navigation(project, E.navigation(session)), session), Nil{}) : E.Decision}:
  E.Session{+route, +drafts, +readers, +layers, +attention, +navigation, +filter, +now, +next, +pending, +previews, +code, +next_layer} = session
  {==}

def Rule.project_interaction_evidence():
  Rule.ProjectInteractionRequirements{
    +origin => +message => +profile => +reasoning => +old => +workspace => +sandbox => +approval => world => {==},
    +project => +application => {==},
    expanded => intent => +collapsed => {==},
    intent => +collapsed => {==},
    encapsulated_toggle_keeps_location,
    +id => drafts => +world => {==},
    +drafts => +world => {==},
    entries => registered_choices_complete(entries),
    +query => +selected => +projects => {==},
    +id => +name => +workspace => guidance => +tasks => +route => +selected => +navigation => {==},
    +id => +now => +world => {==},
    +id => +name => +workspace => {==},
    +id => title => +status => +selected => +open => +parent => +state => {==},
    prefix => other => suffix => id => distinct => deletion_retains_other(prefix, other, suffix, id, distinct),
    +intent => +prefix => +other => +suffix => +id => distinct => toggle_retains_case(E.project_collapsed(E.NavigationState{intent, List.append(&2, Nat, prefix, other <> suffix)}, id), prefix, other, suffix, id, distinct),
    +id => +intent => collapsed => {==},
    picker_complete_nodes,
    +context => +world => {==},
    encapsulated_picker_search_preserves_session,
    +id => name => workspace => +selected => +expanded => +tasks => +open => +create => +toggle => +more => +parent => +state => {==},
    context => {==},
    +parent => state => {==},
    +first => +rest => +parent => +state => {==},
    encapsulated_select_focus_and_input,
    encapsulated_missing_draft_focus,
    +task => {==},
    +lifecycle => +working => {==},
    +task => {==}
  }

def production_noop(+draft: U.Draft, +world: M.World(), +session: E.Session,
  denied: {U.can_confirm_directory(draft) == False{} : Bool}) ->
  {E.edit_existing(U.ConfirmDirectory{}, draft, world, session) == E.unchanged(E.Application{world, session}) : E.Decision}:
  Equal.cong(Bool, E.Decision, admitted => E.confirm_found(admitted, draft, world, session),
    U.can_confirm_directory(draft), False{}, denied)

def Rule.directory_entry_evidence():
  Rule.DirectoryEntryRequirements{+revision => +body => feedback => old => +path => world => {==}, revision => body => feedback => +path => {==}, roots => +path => {==}, roots => {==}, {==}, +revision => +body => feedback => +path => +world => admitted =>
      Equal.cong(Bool, Result<&2, &2, String, U.Draft>,
        accepted => U.confirm_directory(accepted, U.Draft{revision, body, feedback, path}, world),
        U.can_confirm_directory(U.Draft{revision, body, feedback, path}), True{}, admitted)
    , +draft => +world => denied =>
      Equal.cong(Bool, Result<&2, &2, String, U.Draft>, accepted => U.confirm_directory(accepted, draft, world),
        U.can_confirm_directory(draft), False{}, denied)
    , revision => +text => old_profile => old_reasoning => +context => feedback => +entry => +profile => +reasoning => world => {==}, revision => +text => +profile => +reasoning => +context => feedback => +entry => +origin => world => {==}, revision => body => feedback => +world => +session => {==}, revision => +body => feedback => +entry => +world => +session => unsupported =>
      production_noop(U.Draft{revision, body, feedback, entry}, world, session,
        SubmissionProof.conjunction_right_false(Bool.not(String.eq(entry, "")), U.workspace_capable(body), unsupported))
    , +revision => +text => +profile => +reasoning => +context => feedback => +entry => +origin => +world => +session => {==}, production_noop, +editor => text => +path => {==}, +editor => +parent => +state => {==}, +editor => {==}, +editor => text => {==}}

# Service completion ownership and selection use the actual production functions.

def picker_closed(+state: Services.State) ->
  {Services.step(Services.CloseDirectoryPicker{}, state) == Services.Decision{Services.replace_directory(state, Services.NoDirectoryPicker{}), Nil{}} : Services.Decision}:
  Services.State{access, credential, settings, appearance, next, transfers, preview, picker} = state
  {==}

def Rule.directory_picker_requirements():
  Rule.DirectoryPickerRequirements{picker_closed, +ticket => +result => +state => {==}, +current => editor => path => trigger => +ticket => +result => +state => stale =>
      Equal.cong(Bool, Services.Decision, (owned => Services.finish_directory(owned, current, editor, path, trigger, result, state)),
        Nat.is_eq(current, ticket), False{}, stale)
    , ticket => +editor => entered => +trigger => +path => +parent => +entries => +truncated => +state => {==}, ticket => +editor => +path => parent => entries => truncated => location => trigger => +state => {==}, editor => path => {==}, +editor => +path => +application => rest => {==}, +editor => path => +application => unavailable =>
      Equal.cong(Bool, E.Application,
        (accepted => Core.directory_chosen_accepted(accepted, editor, path, application)),
        Core.accepts_directory(editor, application), False{}, unavailable)
    , +editor => +path => +application => accepted =>
      Equal.cong(Bool, E.Application,
        (allowed => Core.directory_chosen_accepted(allowed, editor, path, application)),
        Core.accepts_directory(editor, application), True{}, accepted)
    }

def Rule.directory_identity_requirements():
  Rule.DirectoryIdentityRequirements{
    +path => primary => choose => remove => +parent => state => {==},
    +path => control => +parent => state => {==},
    path => primary => choose => remove => +parent => state => other => name => {==},
    path => primary => choose => remove => +parent => state => other => name => {==}}

def Rule.directory_ready_regions(ticket, editor, path, parent, entries, truncated, location, trigger):
  {==}

def Rule.directory_location_navigation_regions(ticket, editor, path, parent, entries, truncated, location, trigger):
  {==}
