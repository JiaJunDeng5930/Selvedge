import ../board-presentation-laws.bend as Rule
import Base
import ../ui-identity.bend as Identity
import ../../MODEL.bend as M
import ../../BOARD.bend as B
import ../../FEATURES.bend as F
import ../../PROJECTS.bend as Projects
import ../../bendlib/domain.bend as D
import ../../bendlib/association-map.bend as Finite
import ../../bendlib/board-state.bend as Board
import ../../bendlib/board-filter.bend as Filter
import ../SYSTEM.bend as Core
import ../interface.bend as Interface
import ../ui-world.bend as View
import ../user-input.bend as U
import ../user-experience.bend as E

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

def card_scene_ids_cons(head: View.CardScene, +rest: +List<View.CardScene>) ->
  {Rule.card_scene_ids(head <> rest) == Rule.card_scene_identity(head) <> Rule.card_scene_ids(rest) : +List<Nat>}:
  View.CardScene{id, value, open, actions, linked, destinations, candidates} = head
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

def card_roots_keep_length(+entries: +List<View.CardScene>, +parent: Identity.Key, +state: Core.State) ->
  {List.length(&2, Interface.Node, Interface.cards(entries, parent, state)) == List.length(&2, View.CardScene, entries) : Nat}:
  match entries:
    case Nil{}: {==}
    case Con{+entry, +rest}:
      Equal.cong(Nat, Nat, (tail => (1n + tail : Nat)),
        List.length(&2, Interface.Node, Interface.cards(rest, parent, state)),
        List.length(&2, View.CardScene, rest), card_roots_keep_length(rest, parent, state))

def lane_children_are_create_plus_cards(stage: B.Stage, +entries: +List<View.CardScene>, +create: View.ControlDeclaration,
  +parent: Identity.Key, +state: Core.State) ->
  {Rule.first_lane_child_count(Interface.columns([View.BoardColumn{stage, entries, create}], parent, state)) ==
    Some{(1n + List.length(&2, View.CardScene, entries) : Nat)} : Maybe<&2, Nat>}:
  +lane_key: Identity.Key = Identity.Part{parent, B.stage_name(stage)}
  children_count = card_roots_keep_length(entries, lane_key, state)
  Equal.cong(Nat, Maybe<&2, Nat>, (cards => Some{(1n + cards : Nat)}),
    List.length(&2, Interface.Node, Interface.cards(entries, lane_key, state)),
    List.length(&2, View.CardScene, entries), children_count)

def selected_work_child_identity(selected: Bool, +node: Interface.Node, +parent: Identity.Key, rest: +List<Interface.Node>) ->
  {Rule.work_status_child_key(Interface.board_group(parent, "work-status", Interface.WorkStatus{}, [Interface.selected_node(selected, node)]) <> rest) ==
    Some{Interface.node_key(node)} : Maybe<&2, String>}:
  match selected:
    case True{}:
      Interface.Node{key, semantic, label, role, meaning, children} = node
      {==}
    case False{}:
      Interface.Node{key, semantic, label, role, meaning, children} = node
      {==}

def board_toolbar_work_status_identity(+filter: B.Filter, working: Nat, create: View.ControlDeclaration,
  settings: View.ControlDeclaration, filters: View.ControlDeclaration, archive: View.ControlDeclaration,
  +parent: Identity.Key, +state: Core.State) ->
  {Rule.work_status_child_key(Interface.board_toolbar(filter, working, create, settings, filters, archive, parent, state)) ==
    Some{Identity.encode(Identity.Part{Identity.Part{parent, "work-status"}, "view/working"})} : Maybe<&2, String>}:
  B.Filter{+view, search, status, priority, date, assignee, creator, project, labels} = filter
  Core.State{application, services} = state
  selected_work_child_identity(String.eq(view, "working"),
    Interface.declared(Identity.Part{parent, "work-status"},
      View.ControlDeclaration{"view/working", "正在运行的任务 " ++ Nat.show(working), View.Secondary{},
        U.FilterBoard{B.Filter{"working", search, status, priority, date, assignee, creator, project, labels}}, View.Available{}},
      Core.State{application, services}), parent,
    [Interface.board_group(parent, "secondary-actions", Interface.SecondaryActions{},
      [Interface.declared(parent, filters, Core.State{application, services}), Interface.declared(parent, settings, Core.State{application, services}),
       Interface.archive_destination(archive, parent, Core.State{application, services})]),
     Interface.board_group(parent, "primary-action", Interface.PrimaryAction{}, [Interface.declared(parent, create, Core.State{application, services})])])

def navigation_header_keeps_brand(+navigation: View.Navigation, +state: Core.State) ->
  {Rule.navigation_header_label(Interface.navigation(navigation, state)) == Some{"Selvedge"} : Maybe<&2, String>}:
  View.Navigation{expanded, create, destinations, projects, tasks, toggle} = navigation
  Core.State{E.Application{world, E.Session{route, drafts, readers, layers, attention, stored_navigation,
    filter, now, next, pending, previews, code, next_layer}}, services} = state
  {==}

def navigation_header_contains_only_toggle(+navigation: View.Navigation, +state: Core.State) ->
  {Rule.navigation_header_children(Interface.navigation(navigation, state)) ==
    Some{[Interface.declared(Identity.Place{"/navigation"}, Rule.navigation_toggle_control(navigation), state)]} : Maybe<&2, +List<Interface.Node>>}:
  View.Navigation{expanded, create, destinations, projects, tasks, toggle} = navigation
  Core.State{E.Application{world, E.Session{route, drafts, readers, layers, attention, stored_navigation,
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
  {Interface.with_search(search, filter) == Rule.search_filter(search, filter) : B.Filter}:
  match filter:
    case B.Filter{view, old_search, status, priority, date, assignee, creator, project, label}: {==}

def status_toggle_preserves_other_facets(+value: String, +filter: B.Filter) ->
  {Interface.toggle_filter("status", value, filter) == Rule.toggled_status_filter(value, filter) : B.Filter}:
  match filter:
    case B.Filter{view, search, status, priority, date, assignee, creator, project, label}: {==}

def priority_toggle_preserves_other_facets(+value: String, +filter: B.Filter) ->
  {Interface.toggle_filter("priority", value, filter) == Rule.toggled_priority_filter(value, filter) : B.Filter}:
  match filter:
    case B.Filter{view, search, status, priority, date, assignee, creator, project, label}: {==}

def date_toggle_preserves_other_facets(+value: String, +filter: B.Filter) ->
  {Interface.toggle_filter("date", value, filter) == Rule.toggled_date_filter(value, filter) : B.Filter}:
  match filter:
    case B.Filter{view, search, status, priority, date, assignee, creator, project, label}: {==}

def assignee_toggle_preserves_other_facets(+value: String, +filter: B.Filter) ->
  {Interface.toggle_filter("assignee", value, filter) == Rule.toggled_assignee_filter(value, filter) : B.Filter}:
  match filter:
    case B.Filter{view, search, status, priority, date, assignee, creator, project, label}: {==}

def creator_toggle_preserves_other_facets(+value: String, +filter: B.Filter) ->
  {Interface.toggle_filter("creator", value, filter) == Rule.toggled_creator_filter(value, filter) : B.Filter}:
  match filter:
    case B.Filter{view, search, status, priority, date, assignee, creator, project, label}: {==}

def project_toggle_preserves_other_facets(+value: String, +filter: B.Filter) ->
  {Interface.toggle_filter("project", value, filter) == Rule.toggled_project_filter(value, filter) : B.Filter}:
  match filter:
    case B.Filter{view, search, status, priority, date, assignee, creator, project, label}: {==}

def label_toggle_preserves_other_facets(+value: String, +filter: B.Filter) ->
  {Interface.toggle_filter("label", value, filter) == Rule.toggled_label_filter(value, filter) : B.Filter}:
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
  declaration: View.ControlDeclaration, +state: Core.State) ->
  {Interface.node_role(Interface.selected_declaration(route, parent, declaration, state)) ==
    Interface.node_role(Interface.selected_node(Interface.navigation_action_selected(route, Rule.declaration_input(declaration)),
      Interface.declared(parent, declaration, state))) : Interface.Role}:
  match declaration:
    case View.ControlDeclaration{identity, label, prominence, input, availability}:
      {==}

def board_settings_preserve_state(+board: B.State, +world: M.World()) ->
  Rule.settings_state_law(board, world):
  match board:
    case B.State{cards, next_card, agents, next_agent, automatic, draft_profile}: {==}

def Rule.evidence():
  Rule.Requirements{
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
