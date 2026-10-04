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

def first_lane_card_count(nodes: +List<Interface.Node>) -> Maybe<&2, Nat>:
  match nodes:
    case Nil{}: None{}
    case Con{Interface.Node{key, semantic, label, role, Interface.BoardLane{stage, count}, children}, rest}: Some{count}
    case Con{node, rest}: None{}

def first_lane_child_count(nodes: +List<Interface.Node>) -> Maybe<&2, Nat>:
  match nodes:
    case Nil{}: None{}
    case Con{Interface.Node{key, semantic, label, role, meaning, children}, rest}: Some{List.length(&2, Interface.Node, children)}

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

def settings_state_law(-board: B.State, -world: M.World()) -> Type:
  {View.board_settings(board, world) ==
    View.BoardSettings{B.automatic(board), B.draft_profile(board), Board.profiles(world),
      View.board_control("board/automatic", "自动排期",
        B.Settings{Bool.not(B.automatic(board)), B.draft_profile(board)}, world)} : View.LayerContent}

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

law evidence:
  Requirements
