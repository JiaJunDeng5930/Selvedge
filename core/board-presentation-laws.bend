import Base
import ../MODEL.bend as M
import ../BOARD.bend as B
import ../FEATURES.bend as F
import ../PROJECTS.bend as Projects
import ../bendlib/domain.bend as D
import ../bendlib/association-map.bend as Finite
import ../bendlib/board-state.bend as Board
import ../bendlib/board-filter.bend as Filter
import ./SYSTEM.bend as Core
import ./interface.bend as Interface
import ./ui-world.bend as View
import ./user-input.bend as U
import ./user-experience.bend as E

def face_id(face: View.CardFace) -> Nat:
  match face:
    case View.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated}: id

def face_title(face: View.CardFace) -> String:
  match face:
    case View.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated}: title

def face_description(face: View.CardFace) -> String:
  match face:
    case View.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated}: description

def face_priority(face: View.CardFace) -> B.Priority:
  match face:
    case View.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated}: priority

def face_pinned(face: View.CardFace) -> Bool:
  match face:
    case View.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated}: pinned

def face_status(face: View.CardFace) -> String:
  match face:
    case View.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated}: status

def face_project(face: View.CardFace) -> String:
  match face:
    case View.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated}: project

def face_labels(face: View.CardFace) -> +List<String>:
  match face:
    case View.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated}: labels

def face_owner(face: View.CardFace) -> String:
  match face:
    case View.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated}: owner

def face_updated(face: View.CardFace) -> String:
  match face:
    case View.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated}: updated

def card_identity_is_preserved(+id: Nat, +card: B.Card, +now: U32, +world: M.World()) ->
  {face_id(View.card_face(id, card, now, world)) == id : Nat}:
  {==}

def card_title_is_preserved(+id: Nat, +card: B.Card, +now: U32, +world: M.World()) ->
  {face_title(View.card_face(id, card, now, world)) == B.title(B.draft(card)) : String}:
  {==}

def card_description_is_preserved(+id: Nat, +card: B.Card, +now: U32, +world: M.World()) ->
  {face_description(View.card_face(id, card, now, world)) == B.description(B.draft(card)) : String}:
  {==}

def card_priority_is_preserved(+id: Nat, +card: B.Card, +now: U32, +world: M.World()) ->
  {face_priority(View.card_face(id, card, now, world)) == B.card_priority(B.draft(card)) : B.Priority}:
  {==}

def card_pin_is_preserved(+id: Nat, +card: B.Card, +now: U32, +world: M.World()) ->
  {face_pinned(View.card_face(id, card, now, world)) == B.pinned(card) : Bool}:
  {==}

def card_status_is_observed(+id: Nat, +card: B.Card, +now: U32, +world: M.World()) ->
  {face_status(View.card_face(id, card, now, world)) == Board.activity_label(Board.activity(card, world)) : String}:
  {==}

def card_project_is_resolved(+id: Nat, +card: B.Card, +now: U32, +world: M.World()) ->
  {face_project(View.card_face(id, card, now, world)) == View.face_project(B.project(B.draft(card)), world) : String}:
  {==}

def card_labels_are_preserved(+id: Nat, +card: B.Card, +now: U32, +world: M.World()) ->
  {face_labels(View.card_face(id, card, now, world)) == B.labels(B.draft(card)) : +List<String>}:
  {==}

def card_owner_is_resolved(+id: Nat, +card: B.Card, +now: U32, +world: M.World()) ->
  {face_owner(View.card_face(id, card, now, world)) == View.face_owner(B.card_owner(B.draft(card)), world) : String}:
  {==}

def card_updated_uses_elapsed_clock(+id: Nat, +card: B.Card, +now: U32, +world: M.World()) ->
  {face_updated(View.card_face(id, card, now, world)) == View.elapsed_label(Filter.elapsed(now, B.updated(card))) : String}:
  {==}

def project_none_is_empty(+world: M.World()) ->
  {View.face_project(None{}, world) == "" : String}:
  {==}

def project_missing_name_is_identifiable(+id: Nat) ->
  {View.face_project_name(None{}, id) == "项目 #" ++ Nat.show(id) ++ " 不可用" : String}:
  {==}

def project_reference_missing_is_identifiable(+id: Nat, +world: M.World(),
  absent: {Projects.find(Projects.registry(F.State(), world), id) == None{} : Maybe<&2, D.Project>}) ->
  {View.face_project(Some{id}, world) == "项目 #" ++ Nat.show(id) ++ " 不可用" : String}:
  Equal.cong(Maybe<&2, D.Project>, String,
    (found => View.face_project_name(found, id)),
    Projects.find(Projects.registry(F.State(), world), id), None{}, absent)

def profile_missing_name_is_identifiable(+key: String) ->
  {View.face_profile_name(None{}, key) == "配置 " ++ key ++ " 不可用" : String}:
  {==}

def profile_reference_missing_is_identifiable(+key: String, +world: M.World(),
  absent: {D.find_profile(Board.profiles(world), key) == None{} : Maybe<&2, D.Profile>}) ->
  {View.face_owner(B.Profile{key}, world) == "配置 " ++ key ++ " 不可用" : String}:
  Equal.cong(Maybe<&2, D.Profile>, String,
    (found => View.face_profile_name(found, key)), D.find_profile(Board.profiles(world), key), None{}, absent)

def agent_missing_name_is_identifiable(id: Nat) ->
  {View.face_agent_name(None{}, id) == "智能体 #" ++ Nat.show(id) ++ " 不可用" : String}:
  {==}

def agent_reference_missing_is_identifiable(id: Nat, +world: M.World(),
  absent: {B.find_agent(Board.registry(world), id) == None{} : Maybe<&2, B.AgentProfile>}) ->
  {View.face_owner(B.Agent{id}, world) == "智能体 #" ++ Nat.show(id) ++ " 不可用" : String}:
  Equal.cong(Maybe<&2, B.AgentProfile>, String,
    (found => View.face_agent_name(found, id)), B.find_agent(Board.registry(world), id), None{}, absent)

def action_stage(control: View.ControlDeclaration) -> Maybe<&2, B.Stage>:
  View.ControlDeclaration{identity, label, prominence, input, availability} = control
  match input:
    case U.Activate{U.NewCard{stage}}: Some{stage}
    case _: None{}

def action_prominence(control: View.ControlDeclaration) -> View.Prominence:
  View.ControlDeclaration{identity, label, prominence, input, availability} = control
  prominence

def page_global_create_stage(page: View.Page) -> Maybe<&2, B.Stage>:
  match page:
    case View.BoardPage{filter, columns, create, working, settings, filters, archive}: action_stage(create)
    case _: None{}

def page_global_create_prominence(page: View.Page) -> Maybe<&2, View.Prominence>:
  match page:
    case View.BoardPage{filter, columns, create, working, settings, filters, archive}: Some{action_prominence(create)}
    case _: None{}

def first_lane_create_stage(columns: +List<View.BoardColumn>) -> Maybe<&2, B.Stage>:
  match columns:
    case Nil{}: None{}
    case Con{View.BoardColumn{stage, cards, create}, rest}: action_stage(create)

def first_lane_create_prominence(columns: +List<View.BoardColumn>) -> Maybe<&2, View.Prominence>:
  match columns:
    case Nil{}: None{}
    case Con{View.BoardColumn{stage, cards, create}, rest}: Some{action_prominence(create)}

def global_create_targets_todo(board: B.State, +filter: B.Filter, +route: U.Route, +now: U32, +world: M.World()) ->
  {page_global_create_stage(View.board_page(board, filter, route, now, world)) == Some{B.Todo{}} : Maybe<&2, B.Stage>}:
  {==}

def global_create_is_primary(board: B.State, +filter: B.Filter, +route: U.Route, +now: U32, +world: M.World()) ->
  {page_global_create_prominence(View.board_page(board, filter, route, now, world)) == Some{View.Primary{}} : Maybe<&2, View.Prominence>}:
  {==}

def lane_create_targets_requested_stage(stage: B.Stage, +route: U.Route, +now: U32, +world: M.World()) ->
  {first_lane_create_stage(View.columns([stage], Nil{}, route, now, world)) == Some{stage} : Maybe<&2, B.Stage>}:
  {==}

def lane_create_is_secondary(stage: B.Stage, +route: U.Route, +now: U32, +world: M.World()) ->
  {first_lane_create_prominence(View.columns([stage], Nil{}, route, now, world)) == Some{View.Secondary{}} : Maybe<&2, View.Prominence>}:
  {==}

def new_card_dispatches_to_stage_draft(stage: B.Stage, +application: E.Application) ->
  {E.activate_selected(U.NewCard{stage}, application) == E.new_card(stage, application) : E.Decision}:
  {==}

def new_card_body_starts_in_requested_stage(stage: B.Stage) ->
  {E.new_card_body(stage) == U.Card{None{}, 0n, B.Draft{"", "", stage, B.NoPriority{}, B.Unassigned{}, None{}, Nil{}, Nil{}}, False{}, "", False{}} : U.Body}:
  {==}

def edit_card_dispatches_to_saved_identity(id: Nat, +application: E.Application) ->
  {E.activate_selected(U.EditCard{id}, application) == E.card_editor(id, application) : E.Decision}:
  {==}

def card_scene_ids(cards: +List<View.CardScene>) -> +List<Nat>:
  match cards:
    case Nil{}: Nil{}
    case Con{View.CardScene{id, value, open, actions, linked, destinations, candidates}, rest}: id <> card_scene_ids(rest)

def board_entry_ids(entries: +List<Finite.Entry(B.Card)>) -> +List<Nat>:
  match entries:
    case Nil{}: Nil{}
    case Con{(id, card), rest}: id <> board_entry_ids(rest)

def card_scene_identity(scene: View.CardScene) -> Nat:
  match scene:
    case View.CardScene{id, value, open, actions, linked, destinations, candidates}: id

def card_scene_ids_cons(head: View.CardScene, +rest: +List<View.CardScene>) ->
  {card_scene_ids(head <> rest) == card_scene_identity(head) <> card_scene_ids(rest) : +List<Nat>}:
  View.CardScene{id, value, open, actions, linked, destinations, candidates} = head
  {==}

def card_scene_identity_is_input(id: Nat, revision: Nat, draft: B.Draft, task: Maybe<&2, Nat>, archived: Bool,
  created: U32, updated: U32, enrichment: B.Enrichment, start_error: String, pinned: Bool,
  route: U.Route, +now: U32, +world: M.World()) ->
  {card_scene_identity(View.card_scene(id, B.Card{revision, draft, task, archived, created, updated, enrichment, start_error, pinned}, route, now, world)) == id : Nat}:
  {==}

def card_scenes_keep_ids(+entries: +List<Finite.Entry(B.Card)>, +route: U.Route, +now: U32, +world: M.World()) ->
  {card_scene_ids(View.card_scenes(entries, route, now, world)) == board_entry_ids(entries) : +List<Nat>}:
  match entries:
    case Nil{}: {==}
    case Con{(+id, +card), +rest}:
      B.Card{revision, draft, task, archived, created, updated, enrichment, start_error, pinned} = card
      +materialized: B.Card = B.Card{revision, draft, task, archived, created, updated, enrichment, start_error, pinned}
      Equal.trans(+List<Nat>,
        card_scene_ids(View.card_scene(id, materialized, route, now, world) <> View.card_scenes(rest, route, now, world)),
        card_scene_identity(View.card_scene(id, materialized, route, now, world)) <> card_scene_ids(View.card_scenes(rest, route, now, world)),
        id <> board_entry_ids(rest),
        card_scene_ids_cons(View.card_scene(id, materialized, route, now, world), View.card_scenes(rest, route, now, world)),
        Equal.trans(+List<Nat>,
          card_scene_identity(View.card_scene(id, materialized, route, now, world)) <> card_scene_ids(View.card_scenes(rest, route, now, world)),
          id <> card_scene_ids(View.card_scenes(rest, route, now, world)), id <> board_entry_ids(rest),
          Equal.cong(Nat, +List<Nat>, (head_id => head_id <> card_scene_ids(View.card_scenes(rest, route, now, world))),
            card_scene_identity(View.card_scene(id, materialized, route, now, world)), id,
            card_scene_identity_is_input(id, revision, draft, task, archived, created, updated, enrichment, start_error, pinned, route, now, world)),
          Equal.cong(+List<Nat>, +List<Nat>, (tail => id <> tail), card_scene_ids(View.card_scenes(rest, route, now, world)),
            board_entry_ids(rest), card_scenes_keep_ids(rest, route, now, world))))

def card_roots_keep_length(+entries: +List<View.CardScene>, +parent: String, +state: Core.State) ->
  {List.length(&2, Interface.Node, Interface.cards(entries, parent, state)) == List.length(&2, View.CardScene, entries) : Nat}:
  match entries:
    case Nil{}: {==}
    case Con{+entry, +rest}:
      Equal.cong(Nat, Nat, (tail => (1n + tail : Nat)),
        List.length(&2, Interface.Node, Interface.cards(rest, parent, state)),
        List.length(&2, View.CardScene, rest), card_roots_keep_length(rest, parent, state))

def first_lane_card_count(nodes: +List<Interface.Node>) -> Maybe<&2, Nat>:
  match nodes:
    case Nil{}: None{}
    case Con{Interface.Node{key, semantic, label, role, Interface.BoardLane{stage, count}, children}, rest}: Some{count}
    case Con{node, rest}: None{}

def first_lane_child_count(nodes: +List<Interface.Node>) -> Maybe<&2, Nat>:
  match nodes:
    case Nil{}: None{}
    case Con{Interface.Node{key, semantic, label, role, meaning, children}, rest}: Some{List.length(&2, Interface.Node, children)}

def lane_count_is_visible_card_count(stage: B.Stage, +entries: +List<View.CardScene>, +create: View.ControlDeclaration,
  +parent: String, +state: Core.State) ->
  {first_lane_card_count(Interface.columns([View.BoardColumn{stage, entries, create}], parent, state)) ==
    Some{List.length(&2, View.CardScene, entries)} : Maybe<&2, Nat>}:
  {==}

def lane_children_are_create_plus_cards(stage: B.Stage, +entries: +List<View.CardScene>, +create: View.ControlDeclaration,
  +parent: String, +state: Core.State) ->
  {first_lane_child_count(Interface.columns([View.BoardColumn{stage, entries, create}], parent, state)) ==
    Some{(1n + List.length(&2, View.CardScene, entries) : Nat)} : Maybe<&2, Nat>}:
  +lane_key = parent ++ "/" ++ B.stage_name(stage)
  children_count = card_roots_keep_length(entries, lane_key, state)
  Equal.cong(Nat, Maybe<&2, Nat>, (cards => Some{(1n + cards : Nat)}),
    List.length(&2, Interface.Node, Interface.cards(entries, lane_key, state)),
    List.length(&2, View.CardScene, entries), children_count)

def work_status_child_key(nodes: +List<Interface.Node>) -> Maybe<&2, String>:
  match nodes:
    case Nil{}: None{}
    case Con{node, rest}:
      match node:
        case Interface.Node{key, semantic, label, role, meaning, children}:
          match meaning:
            case Interface.BoardGroup{grouping}:
              match grouping:
                case Interface.WorkStatus{}:
                  match children:
                    case Nil{}: None{}
                    case Con{child, _}:
                      match child:
                        case Interface.Node{key, semantic, label, role, meaning, children}: Some{key}
                case _: work_status_child_key(rest)
            case _: work_status_child_key(rest)

def selected_work_child_identity(selected: Bool, +node: Interface.Node, +parent: String, rest: +List<Interface.Node>) ->
  {work_status_child_key(Interface.board_group(parent, "work-status", Interface.WorkStatus{}, [Interface.selected_node(selected, node)]) <> rest) ==
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
  +parent: String, +state: Core.State) ->
  {work_status_child_key(Interface.board_toolbar(filter, working, create, settings, filters, archive, parent, state)) ==
    Some{(parent ++ "/work-status") ++ "/view/working"} : Maybe<&2, String>}:
  B.Filter{+view, search, status, priority, date, assignee, creator, project, labels} = filter
  Core.State{application, services} = state
  selected_work_child_identity(String.eq(view, "working"),
    Interface.declared(parent ++ "/work-status",
      View.ControlDeclaration{"view/working", "正在运行的任务 " ++ Nat.show(working), View.Secondary{},
        U.FilterBoard{B.Filter{"working", search, status, priority, date, assignee, creator, project, labels}}, View.Available{}},
      Core.State{application, services}), parent,
    [Interface.board_group(parent, "secondary-actions", Interface.SecondaryActions{},
      [Interface.declared(parent, filters, Core.State{application, services}), Interface.declared(parent, settings, Core.State{application, services}),
       Interface.archive_destination(archive, parent, Core.State{application, services})]),
     Interface.board_group(parent, "primary-action", Interface.PrimaryAction{}, [Interface.declared(parent, create, Core.State{application, services})])])

def navigation_header_node(navigation: Interface.Node) -> Maybe<&2, Interface.Node>:
  match navigation:
    case Interface.Node{key, semantic, label, role, meaning, children}:
      match children:
        case Nil{}: None{}
        case Con{header, rest}:
          match header:
            case Interface.Node{key, semantic, label, role, meaning, children}:
              match role:
                case Interface.NavigationHeader{}: Some{header}
                case _: None{}

def navigation_header_label_of(header: Maybe<&2, Interface.Node>) -> Maybe<&2, String>:
  match header:
    case None{}: None{}
    case Some{header}:
      match header:
        case Interface.Node{key, semantic, label, role, meaning, children}: Some{label}

def navigation_header_children_of(header: Maybe<&2, Interface.Node>) -> Maybe<&2, +List<Interface.Node>>:
  match header:
    case None{}: None{}
    case Some{header}:
      match header:
        case Interface.Node{key, semantic, label, role, meaning, children}: Some{children}

def navigation_header_label(navigation: Interface.Node) -> Maybe<&2, String>:
  navigation_header_label_of(navigation_header_node(navigation))

def navigation_header_children(navigation: Interface.Node) -> Maybe<&2, +List<Interface.Node>>:
  navigation_header_children_of(navigation_header_node(navigation))

def navigation_toggle_control(navigation: View.Navigation) -> View.ControlDeclaration:
  View.Navigation{expanded, create, destinations, projects, tasks, toggle} = navigation
  toggle

def navigation_header_keeps_brand(+navigation: View.Navigation, +state: Core.State) ->
  {navigation_header_label(Interface.navigation(navigation, state)) == Some{"Selvedge"} : Maybe<&2, String>}:
  View.Navigation{expanded, create, destinations, projects, tasks, toggle} = navigation
  Core.State{E.Application{world, E.Session{route, drafts, readers, layers, attention, stored_navigation,
    filter, now, next, pending, previews, code}}, services} = state
  {==}

def navigation_header_contains_only_toggle(+navigation: View.Navigation, +state: Core.State) ->
  {navigation_header_children(Interface.navigation(navigation, state)) ==
    Some{[Interface.declared("/navigation", navigation_toggle_control(navigation), state)]} : Maybe<&2, +List<Interface.Node>>}:
  View.Navigation{expanded, create, destinations, projects, tasks, toggle} = navigation
  Core.State{E.Application{world, E.Session{route, drafts, readers, layers, attention, stored_navigation,
    filter, now, next, pending, previews, code}}, services} = state
  {==}

def choose_column_ids(matches: Bool, cards: +List<Nat>, rest: +List<Nat>) -> +List<Nat>:
  match matches:
    case True{}: cards
    case False{}: rest

def page_column_ids(columns: +List<View.BoardColumn>, +target: B.Stage) -> +List<Nat>:
  match columns:
    case Nil{}: Nil{}
    case Con{View.BoardColumn{stage, cards, create}, rest}:
      choose_column_ids(String.eq(B.stage_name(stage), B.stage_name(target)), card_scene_ids(cards), page_column_ids(rest, target))

def board_page_column_ids(page: View.Page, target: B.Stage) -> +List<Nat>:
  match page:
    case View.BoardPage{filter, columns, create, working, settings, filters, archive}: page_column_ids(columns, target)
    case _: Nil{}

def pinned_partition(+board: B.State) -> +List<Finite.Entry(B.Card)>:
  List.append(&2, Finite.Entry(B.Card),
    List.filter(~Finite.Entry(B.Card), (entry => Board.pin_group(True{}, entry)), B.cards(board)),
    List.filter(~Finite.Entry(B.Card), (entry => Board.pin_group(False{}, entry)), B.cards(board)))

def display_cards_are_pinned_partition(+board: B.State) ->
  {Board.display_cards(board) == pinned_partition(board) : +List<Finite.Entry(B.Card)>}:
  {==}

def board_page_column_ids_match_display(+board: B.State, +filter: B.Filter, +route: U.Route,
  +now: U32, +world: M.World(), target: B.Stage) ->
  {board_page_column_ids(View.board_page(board, filter, route, now, world), target) ==
    board_entry_ids(Filter.column(Filter.filtered(Board.display_cards(board), filter, now, world), B.stage_name(target))) : +List<Nat>}:
  match target:
    case B.Backlog{}: card_scenes_keep_ids(Filter.column(Filter.filtered(Board.display_cards(board), filter, now, world), B.stage_name(B.Backlog{})), route, now, world)
    case B.Todo{}: card_scenes_keep_ids(Filter.column(Filter.filtered(Board.display_cards(board), filter, now, world), B.stage_name(B.Todo{})), route, now, world)
    case B.InProgress{}: card_scenes_keep_ids(Filter.column(Filter.filtered(Board.display_cards(board), filter, now, world), B.stage_name(B.InProgress{})), route, now, world)
    case B.InReview{}: card_scenes_keep_ids(Filter.column(Filter.filtered(Board.display_cards(board), filter, now, world), B.stage_name(B.InReview{})), route, now, world)
    case B.Completed{}: card_scenes_keep_ids(Filter.column(Filter.filtered(Board.display_cards(board), filter, now, world), B.stage_name(B.Completed{})), route, now, world)
    case B.Blocked{}: card_scenes_keep_ids(Filter.column(Filter.filtered(Board.display_cards(board), filter, now, world), B.stage_name(B.Blocked{})), route, now, world)

def board_page_column_ids_match_partition(+board: B.State, +filter: B.Filter, +route: U.Route,
  +now: U32, +world: M.World(), target: B.Stage) ->
  {board_page_column_ids(View.board_page(board, filter, route, now, world), target) ==
    board_entry_ids(Filter.column(Filter.filtered(pinned_partition(board), filter, now, world), B.stage_name(target))) : +List<Nat>}:
  Equal.trans(+List<Nat>,
    board_page_column_ids(View.board_page(board, filter, route, now, world), target),
    board_entry_ids(Filter.column(Filter.filtered(Board.display_cards(board), filter, now, world), B.stage_name(target))),
    board_entry_ids(Filter.column(Filter.filtered(pinned_partition(board), filter, now, world), B.stage_name(target))),
    board_page_column_ids_match_display(board, filter, route, now, world, target),
    Equal.cong(+List<Finite.Entry(B.Card)>, +List<Nat>,
      (entries => board_entry_ids(Filter.column(Filter.filtered(entries, filter, now, world), B.stage_name(target)))),
      Board.display_cards(board), pinned_partition(board), display_cards_are_pinned_partition(board)))

def view_filter(view: String, +filter: B.Filter) -> B.Filter:
  B.Filter{old_view, search, status, priority, date, assignee, creator, project, label} = filter
  B.Filter{view, search, status, priority, date, assignee, creator, project, label}

def search_filter(search: String, +filter: B.Filter) -> B.Filter:
  B.Filter{view, old_search, status, priority, date, assignee, creator, project, label} = filter
  B.Filter{view, search, status, priority, date, assignee, creator, project, label}

def toggled_status_filter(+value: String, +filter: B.Filter) -> B.Filter:
  B.Filter{view, search, status, priority, date, assignee, creator, project, label} = filter
  B.Filter{view, search, Interface.toggled_filter(status, value), priority, date, assignee, creator, project, label}

def toggled_priority_filter(+value: String, +filter: B.Filter) -> B.Filter:
  B.Filter{view, search, status, priority, date, assignee, creator, project, label} = filter
  B.Filter{view, search, status, Interface.toggled_filter(priority, value), date, assignee, creator, project, label}

def toggled_date_filter(+value: String, +filter: B.Filter) -> B.Filter:
  B.Filter{view, search, status, priority, date, assignee, creator, project, label} = filter
  B.Filter{view, search, status, priority, Interface.toggled_filter(date, value), assignee, creator, project, label}

def toggled_assignee_filter(+value: String, +filter: B.Filter) -> B.Filter:
  B.Filter{view, search, status, priority, date, assignee, creator, project, label} = filter
  B.Filter{view, search, status, priority, date, Interface.toggled_filter(assignee, value), creator, project, label}

def toggled_creator_filter(+value: String, +filter: B.Filter) -> B.Filter:
  B.Filter{view, search, status, priority, date, assignee, creator, project, label} = filter
  B.Filter{view, search, status, priority, date, assignee, Interface.toggled_filter(creator, value), project, label}

def toggled_project_filter(+value: String, +filter: B.Filter) -> B.Filter:
  B.Filter{view, search, status, priority, date, assignee, creator, project, label} = filter
  B.Filter{view, search, status, priority, date, assignee, creator, Interface.toggled_filter(project, value), label}

def toggled_label_filter(+value: String, +filter: B.Filter) -> B.Filter:
  B.Filter{view, search, status, priority, date, assignee, creator, project, label} = filter
  B.Filter{view, search, status, priority, date, assignee, creator, project, Interface.toggled_filter(label, value)}

def view_change_preserves_filter_facets(+view: String, +filter: B.Filter) ->
  {Interface.with_view(view, filter) == view_filter(view, filter) : B.Filter}:
  match filter:
    case B.Filter{old_view, search, status, priority, date, assignee, creator, project, label}: {==}

def search_change_preserves_filter_facets(+search: String, +filter: B.Filter) ->
  {Interface.with_search(search, filter) == search_filter(search, filter) : B.Filter}:
  match filter:
    case B.Filter{view, old_search, status, priority, date, assignee, creator, project, label}: {==}

def status_toggle_preserves_other_facets(+value: String, +filter: B.Filter) ->
  {Interface.toggle_filter("status", value, filter) == toggled_status_filter(value, filter) : B.Filter}:
  match filter:
    case B.Filter{view, search, status, priority, date, assignee, creator, project, label}: {==}

def priority_toggle_preserves_other_facets(+value: String, +filter: B.Filter) ->
  {Interface.toggle_filter("priority", value, filter) == toggled_priority_filter(value, filter) : B.Filter}:
  match filter:
    case B.Filter{view, search, status, priority, date, assignee, creator, project, label}: {==}

def date_toggle_preserves_other_facets(+value: String, +filter: B.Filter) ->
  {Interface.toggle_filter("date", value, filter) == toggled_date_filter(value, filter) : B.Filter}:
  match filter:
    case B.Filter{view, search, status, priority, date, assignee, creator, project, label}: {==}

def assignee_toggle_preserves_other_facets(+value: String, +filter: B.Filter) ->
  {Interface.toggle_filter("assignee", value, filter) == toggled_assignee_filter(value, filter) : B.Filter}:
  match filter:
    case B.Filter{view, search, status, priority, date, assignee, creator, project, label}: {==}

def creator_toggle_preserves_other_facets(+value: String, +filter: B.Filter) ->
  {Interface.toggle_filter("creator", value, filter) == toggled_creator_filter(value, filter) : B.Filter}:
  match filter:
    case B.Filter{view, search, status, priority, date, assignee, creator, project, label}: {==}

def project_toggle_preserves_other_facets(+value: String, +filter: B.Filter) ->
  {Interface.toggle_filter("project", value, filter) == toggled_project_filter(value, filter) : B.Filter}:
  match filter:
    case B.Filter{view, search, status, priority, date, assignee, creator, project, label}: {==}

def label_toggle_preserves_other_facets(+value: String, +filter: B.Filter) ->
  {Interface.toggle_filter("label", value, filter) == toggled_label_filter(value, filter) : B.Filter}:
  match filter:
    case B.Filter{view, search, status, priority, date, assignee, creator, project, label}: {==}

def declaration_input(declaration: View.ControlDeclaration) -> U.Input:
  View.ControlDeclaration{identity, label, prominence, input, availability} = declaration
  input

def navigation_create_control(navigation: View.Navigation) -> View.ControlDeclaration:
  View.Navigation{expanded, create, destinations, projects, tasks, toggle} = navigation
  create

def navigation_board_control(navigation: View.Navigation) -> Maybe<&2, View.ControlDeclaration>:
  View.Navigation{expanded, create, destinations, projects, tasks, toggle} = navigation
  match destinations:
    case Con{board, rest}: Some{board}
    case Nil{}: None{}

def navigation_projects_control(navigation: View.Navigation) -> Maybe<&2, View.ControlDeclaration>:
  View.Navigation{expanded, create, destinations, projects, tasks, toggle} = navigation
  match destinations:
    case Con{board, Con{collection, rest}}: Some{collection}
    case _: None{}

def navigation_agents_control(navigation: View.Navigation) -> Maybe<&2, View.ControlDeclaration>:
  View.Navigation{expanded, create, destinations, projects, tasks, toggle} = navigation
  match destinations:
    case Con{board, Con{collection, Con{agents, rest}}}: Some{agents}
    case _: None{}

def selected_control(found: Maybe<&2, View.ControlDeclaration>, route: U.Route) -> Bool:
  match found:
    case None{}: False{}
    case Some{control}: Interface.navigation_action_selected(route, declaration_input(control))

def board_navigation_selected(+route: U.Route, +world: M.World(), +session: E.Session) -> Bool:
  selected_control(navigation_board_control(View.navigation(True{}, route, world, session)), route)

def projects_navigation_selected(+route: U.Route, +world: M.World(), +session: E.Session) -> Bool:
  selected_control(navigation_projects_control(View.navigation(True{}, route, world, session)), route)

def agents_navigation_selected(+route: U.Route, +world: M.World(), +session: E.Session) -> Bool:
  selected_control(navigation_agents_control(View.navigation(True{}, route, world, session)), route)

def create_navigation_selected(+route: U.Route, +world: M.World(), +session: E.Session) -> Bool:
  Interface.navigation_action_selected(route, declaration_input(navigation_create_control(View.navigation(True{}, route, world, session))))

def board_route_selects_board_nav(+world: M.World(), +session: E.Session) ->
  {board_navigation_selected(U.TaskBoard{}, world, session) == True{} : Bool}:
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code} = session
  {==}

def projects_route_selects_projects_nav(+world: M.World(), +session: E.Session) ->
  {projects_navigation_selected(U.ProjectCollection{}, world, session) == True{} : Bool}:
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code} = session
  {==}

def agents_route_selects_agents_nav(+world: M.World(), +session: E.Session) ->
  {agents_navigation_selected(U.AgentCollection{}, world, session) == True{} : Bool}:
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code} = session
  {==}

def start_route_selects_create_nav(+world: M.World(), +session: E.Session) ->
  {create_navigation_selected(U.Start{}, world, session) == True{} : Bool}:
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code} = session
  {==}

def board_route_rejects_other_nav(+world: M.World(), +session: E.Session) ->
  {(projects_navigation_selected(U.TaskBoard{}, world, session), agents_navigation_selected(U.TaskBoard{}, world, session)) ==
    (False{}, False{}) : Bool & Bool}:
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code} = session
  {==}

def projects_route_rejects_other_nav(+world: M.World(), +session: E.Session) ->
  {(board_navigation_selected(U.ProjectCollection{}, world, session), agents_navigation_selected(U.ProjectCollection{}, world, session)) ==
    (False{}, False{}) : Bool & Bool}:
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code} = session
  {==}

def agents_route_rejects_other_nav(+world: M.World(), +session: E.Session) ->
  {(board_navigation_selected(U.AgentCollection{}, world, session), projects_navigation_selected(U.AgentCollection{}, world, session)) ==
    (False{}, False{}) : Bool & Bool}:
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code} = session
  {==}

def start_route_rejects_destination_nav(+world: M.World(), +session: E.Session) ->
  {(board_navigation_selected(U.Start{}, world, session), projects_navigation_selected(U.Start{}, world, session), agents_navigation_selected(U.Start{}, world, session)) ==
    (False{}, (False{}, False{})) : Bool & (Bool & Bool)}:
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code} = session
  {==}

def selected_declaration_role_tracks_predicate(+route: U.Route, +parent: String,
  declaration: View.ControlDeclaration, +state: Core.State) ->
  {Interface.node_role(Interface.selected_declaration(route, parent, declaration, state)) ==
    Interface.node_role(Interface.selected_node(Interface.navigation_action_selected(route, declaration_input(declaration)),
      Interface.declared(parent, declaration, state))) : Interface.Role}:
  match declaration:
    case View.ControlDeclaration{identity, label, prominence, input, availability}:
      {==}

def settings_state_law(-board: B.State, -world: M.World()) -> Type:
  {View.board_settings(board, world) ==
    View.BoardSettings{B.automatic(board), B.draft_profile(board), Board.profiles(world),
      View.board_control("board/automatic", "自动排期",
        B.Settings{Bool.not(B.automatic(board)), B.draft_profile(board)}, world)} : View.LayerContent}

def board_settings_preserve_state(+board: B.State, +world: M.World()) ->
  settings_state_law(board, world):
  match board:
    case B.State{cards, next_card, agents, next_agent, automatic, draft_profile}: {==}

def settings_layer_uses_registry(+session: E.Session, +world: M.World()) ->
  {View.layer_content(U.BoardSettings{}, session, world) == View.board_settings(Board.registry(world), world) : View.LayerContent}:
  {==}

type Requirements is Type:
  Requirements{
    card_identity: @+id:Nat -> @+card:B.Card -> @+now:U32 -> @+world:M.World() ->
      {face_id(View.card_face(id, card, now, world)) == id : Nat},
    card_content: @+id:Nat -> @+card:B.Card -> @+now:U32 -> @+world:M.World() ->
      {face_title(View.card_face(id, card, now, world)) == B.title(B.draft(card)) : String} &
      {face_description(View.card_face(id, card, now, world)) == B.description(B.draft(card)) : String} &
      {face_priority(View.card_face(id, card, now, world)) == B.card_priority(B.draft(card)) : B.Priority} &
      {face_pinned(View.card_face(id, card, now, world)) == B.pinned(card) : Bool} &
      {face_labels(View.card_face(id, card, now, world)) == B.labels(B.draft(card)) : +List<String>},
    card_context: @+id:Nat -> @+card:B.Card -> @+now:U32 -> @+world:M.World() ->
      {face_status(View.card_face(id, card, now, world)) == Board.activity_label(Board.activity(card, world)) : String} &
      {face_project(View.card_face(id, card, now, world)) == View.face_project(B.project(B.draft(card)), world) : String} &
      {face_owner(View.card_face(id, card, now, world)) == View.face_owner(B.card_owner(B.draft(card)), world) : String} &
      {face_updated(View.card_face(id, card, now, world)) == View.elapsed_label(Filter.elapsed(now, B.updated(card))) : String},
    card_scene_ids: @+entries:+List<Finite.Entry(B.Card)> -> @+route:U.Route -> @+now:U32 -> @+world:M.World() ->
      {card_scene_ids(View.card_scenes(entries, route, now, world)) == board_entry_ids(entries) : +List<Nat>},
    card_root_count: @+entries:+List<View.CardScene> -> @+parent:String -> @+state:Core.State ->
      {List.length(&2, Interface.Node, Interface.cards(entries, parent, state)) == List.length(&2, View.CardScene, entries) : Nat},
    lane_count: @stage:B.Stage -> @+entries:+List<View.CardScene> -> @+create:View.ControlDeclaration -> @+parent:String -> @+state:Core.State ->
      {first_lane_card_count(Interface.columns([View.BoardColumn{stage, entries, create}], parent, state)) ==
        Some{List.length(&2, View.CardScene, entries)} : Maybe<&2, Nat>},
    lane_children: @stage:B.Stage -> @+entries:+List<View.CardScene> -> @+create:View.ControlDeclaration -> @+parent:String -> @+state:Core.State ->
      {first_lane_child_count(Interface.columns([View.BoardColumn{stage, entries, create}], parent, state)) ==
        Some{(1n + List.length(&2, View.CardScene, entries) : Nat)} : Maybe<&2, Nat>},
    toolbar_work_status_identity: @+filter:B.Filter -> @working:Nat -> @create:View.ControlDeclaration ->
      @settings:View.ControlDeclaration -> @filters:View.ControlDeclaration -> @archive:View.ControlDeclaration ->
      @+parent:String -> @+state:Core.State ->
      {work_status_child_key(Interface.board_toolbar(filter, working, create, settings, filters, archive, parent, state)) ==
        Some{(parent ++ "/work-status") ++ "/view/working"} : Maybe<&2, String>},
    navigation_header_brand: @+navigation:View.Navigation -> @+state:Core.State ->
      {navigation_header_label(Interface.navigation(navigation, state)) == Some{"Selvedge"} : Maybe<&2, String>},
    navigation_header_toggle: @+navigation:View.Navigation -> @+state:Core.State ->
      {navigation_header_children(Interface.navigation(navigation, state)) ==
        Some{[Interface.declared("/navigation", navigation_toggle_control(navigation), state)]} : Maybe<&2, +List<Interface.Node>>},
    pinned_order: @+board:B.State -> {Board.display_cards(board) == pinned_partition(board) : +List<Finite.Entry(B.Card)>},
    board_column_ids: @+board:B.State -> @+filter:B.Filter -> @+route:U.Route -> @+now:U32 -> @+world:M.World() -> @target:B.Stage ->
      {board_page_column_ids(View.board_page(board, filter, route, now, world), target) ==
        board_entry_ids(Filter.column(Filter.filtered(pinned_partition(board), filter, now, world), B.stage_name(target))) : +List<Nat>},
    project_none: @+world:M.World() -> {View.face_project(None{}, world) == "" : String},
    project_missing: @+id:Nat -> @+world:M.World() ->
      @absent:{Projects.find(Projects.registry(F.State(), world), id) == None{} : Maybe<&2, D.Project>} ->
      {View.face_project(Some{id}, world) == "项目 #" ++ Nat.show(id) ++ " 不可用" : String},
    profile_missing: @+key:String -> @+world:M.World() ->
      @absent:{D.find_profile(Board.profiles(world), key) == None{} : Maybe<&2, D.Profile>} ->
      {View.face_owner(B.Profile{key}, world) == "配置 " ++ key ++ " 不可用" : String},
    agent_missing: @id:Nat -> @+world:M.World() ->
      @absent:{B.find_agent(Board.registry(world), id) == None{} : Maybe<&2, B.AgentProfile>} ->
      {View.face_owner(B.Agent{id}, world) == "智能体 #" ++ Nat.show(id) ++ " 不可用" : String},
    view_facets: @+view:String -> @+filter:B.Filter ->
      {Interface.with_view(view, filter) == view_filter(view, filter) : B.Filter},
    search_facets: @+search:String -> @+filter:B.Filter ->
      {Interface.with_search(search, filter) == search_filter(search, filter) : B.Filter},
    status_facets: @+value:String -> @+filter:B.Filter ->
      {Interface.toggle_filter("status", value, filter) == toggled_status_filter(value, filter) : B.Filter},
    priority_facets: @+value:String -> @+filter:B.Filter ->
      {Interface.toggle_filter("priority", value, filter) == toggled_priority_filter(value, filter) : B.Filter},
    date_facets: @+value:String -> @+filter:B.Filter ->
      {Interface.toggle_filter("date", value, filter) == toggled_date_filter(value, filter) : B.Filter},
    assignee_facets: @+value:String -> @+filter:B.Filter ->
      {Interface.toggle_filter("assignee", value, filter) == toggled_assignee_filter(value, filter) : B.Filter},
    creator_facets: @+value:String -> @+filter:B.Filter ->
      {Interface.toggle_filter("creator", value, filter) == toggled_creator_filter(value, filter) : B.Filter},
    project_facets: @+value:String -> @+filter:B.Filter ->
      {Interface.toggle_filter("project", value, filter) == toggled_project_filter(value, filter) : B.Filter},
    label_facets: @+value:String -> @+filter:B.Filter ->
      {Interface.toggle_filter("label", value, filter) == toggled_label_filter(value, filter) : B.Filter},
    global_create_stage: @board:B.State -> @+filter:B.Filter -> @+route:U.Route -> @+now:U32 -> @+world:M.World() ->
      {page_global_create_stage(View.board_page(board, filter, route, now, world)) == Some{B.Todo{}} : Maybe<&2, B.Stage>},
    global_create_prominence: @board:B.State -> @+filter:B.Filter -> @+route:U.Route -> @+now:U32 -> @+world:M.World() ->
      {page_global_create_prominence(View.board_page(board, filter, route, now, world)) == Some{View.Primary{}} : Maybe<&2, View.Prominence>},
    lane_create_stage: @stage:B.Stage -> @+route:U.Route -> @+now:U32 -> @+world:M.World() ->
      {first_lane_create_stage(View.columns([stage], Nil{}, route, now, world)) == Some{stage} : Maybe<&2, B.Stage>},
    lane_create_prominence: @stage:B.Stage -> @+route:U.Route -> @+now:U32 -> @+world:M.World() ->
      {first_lane_create_prominence(View.columns([stage], Nil{}, route, now, world)) == Some{View.Secondary{}} : Maybe<&2, View.Prominence>},
    board_nav_selected: @+world:M.World() -> @+session:E.Session -> {board_navigation_selected(U.TaskBoard{}, world, session) == True{} : Bool},
    projects_nav_selected: @+world:M.World() -> @+session:E.Session -> {projects_navigation_selected(U.ProjectCollection{}, world, session) == True{} : Bool},
    agents_nav_selected: @+world:M.World() -> @+session:E.Session -> {agents_navigation_selected(U.AgentCollection{}, world, session) == True{} : Bool},
    start_nav_selected: @+world:M.World() -> @+session:E.Session -> {create_navigation_selected(U.Start{}, world, session) == True{} : Bool},
    board_nav_mismatch: @+world:M.World() -> @+session:E.Session ->
      {(projects_navigation_selected(U.TaskBoard{}, world, session), agents_navigation_selected(U.TaskBoard{}, world, session)) == (False{}, False{}) : Bool & Bool},
    projects_nav_mismatch: @+world:M.World() -> @+session:E.Session ->
      {(board_navigation_selected(U.ProjectCollection{}, world, session), agents_navigation_selected(U.ProjectCollection{}, world, session)) == (False{}, False{}) : Bool & Bool},
    agents_nav_mismatch: @+world:M.World() -> @+session:E.Session ->
      {(board_navigation_selected(U.AgentCollection{}, world, session), projects_navigation_selected(U.AgentCollection{}, world, session)) == (False{}, False{}) : Bool & Bool},
    start_nav_mismatch: @+world:M.World() -> @+session:E.Session ->
      {(board_navigation_selected(U.Start{}, world, session), projects_navigation_selected(U.Start{}, world, session), agents_navigation_selected(U.Start{}, world, session)) ==
        (False{}, (False{}, False{})) : Bool & (Bool & Bool)},
    selected_navigation_role: @route:U.Route -> @+parent:String -> @+declaration:View.ControlDeclaration -> @+state:Core.State ->
      {Interface.node_role(Interface.selected_declaration(route, parent, declaration, state)) ==
        Interface.node_role(Interface.selected_node(Interface.navigation_action_selected(route, declaration_input(declaration)),
          Interface.declared(parent, declaration, state))) : Interface.Role},
    settings_state: @+board:B.State -> @+world:M.World() ->
      settings_state_law(board, world),
    settings_layer: @+session:E.Session -> @+world:M.World() ->
      {View.layer_content(U.BoardSettings{}, session, world) == View.board_settings(Board.registry(world), world) : View.LayerContent},
    create_draft: @stage:B.Stage -> @+application:E.Application ->
      {E.activate_selected(U.NewCard{stage}, application) == E.new_card(stage, application) : E.Decision},
    create_body: @stage:B.Stage ->
      {E.new_card_body(stage) == U.Card{None{}, 0n, B.Draft{"", "", stage, B.NoPriority{}, B.Unassigned{}, None{}, Nil{}, Nil{}}, False{}, "", False{}} : U.Body},
    edit_saved_card: @id:Nat -> @+application:E.Application ->
      {E.activate_selected(U.EditCard{id}, application) == E.card_editor(id, application) : E.Decision}
  }

def evidence() -> Requirements:
  Requirements{
    id => card => now => world => card_identity_is_preserved(id, card, now, world),
    id => card => now => world =>
      (card_title_is_preserved(id, card, now, world), card_description_is_preserved(id, card, now, world),
       card_priority_is_preserved(id, card, now, world), card_pin_is_preserved(id, card, now, world),
       card_labels_are_preserved(id, card, now, world)),
    id => card => now => world =>
      (card_status_is_observed(id, card, now, world), card_project_is_resolved(id, card, now, world),
       card_owner_is_resolved(id, card, now, world), card_updated_uses_elapsed_clock(id, card, now, world)),
    entries => route => now => world => card_scenes_keep_ids(entries, route, now, world),
    entries => parent => state => card_roots_keep_length(entries, parent, state),
    stage => entries => create => parent => state => lane_count_is_visible_card_count(stage, entries, create, parent, state),
    stage => entries => create => parent => state => lane_children_are_create_plus_cards(stage, entries, create, parent, state),
    filter => working => create => settings => filters => archive => parent => state =>
      board_toolbar_work_status_identity(filter, working, create, settings, filters, archive, parent, state),
    navigation => state => navigation_header_keeps_brand(navigation, state),
    navigation => state => navigation_header_contains_only_toggle(navigation, state),
    board => display_cards_are_pinned_partition(board),
    board => filter => route => now => world => target => board_page_column_ids_match_partition(board, filter, route, now, world, target),
    world => project_none_is_empty(world),
    id => world => absent => project_reference_missing_is_identifiable(id, world, absent),
    key => world => absent => profile_reference_missing_is_identifiable(key, world, absent),
    id => world => absent => agent_reference_missing_is_identifiable(id, world, absent),
    view => filter => view_change_preserves_filter_facets(view, filter),
    search => filter => search_change_preserves_filter_facets(search, filter),
    value => filter => status_toggle_preserves_other_facets(value, filter),
    value => filter => priority_toggle_preserves_other_facets(value, filter),
    value => filter => date_toggle_preserves_other_facets(value, filter),
    value => filter => assignee_toggle_preserves_other_facets(value, filter),
    value => filter => creator_toggle_preserves_other_facets(value, filter),
    value => filter => project_toggle_preserves_other_facets(value, filter),
    value => filter => label_toggle_preserves_other_facets(value, filter),
    board => filter => route => now => world => global_create_targets_todo(board, filter, route, now, world),
    board => filter => route => now => world => global_create_is_primary(board, filter, route, now, world),
    stage => route => now => world => lane_create_targets_requested_stage(stage, route, now, world),
    stage => route => now => world => lane_create_is_secondary(stage, route, now, world),
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
    session => world => settings_layer_uses_registry(session, world),
    stage => application => new_card_dispatches_to_stage_draft(stage, application),
    stage => new_card_body_starts_in_requested_stage(stage),
    id => application => edit_card_dispatches_to_saved_identity(id, application)
  }
