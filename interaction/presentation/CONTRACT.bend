import Base
import ../../harness/COMMANDS.bend as Commands
import ../../harness/MODEL.bend as M
import ../../harness/DOMAIN.bend as D
import ../../harness/reasoning/MODEL.bend as Reasoning
import ../submission/FIELDS.bend as Forms
import ../IDENTITY.bend as Identity
import ../STATE.bend as Core
import ./PROGRAM.bend as Model
import ./MODEL.bend as V
import ../services/CONTEXT.bend as Context
import ../INPUT.bend as U
import ../session/MODEL.bend as E
import ../../features/board/MODEL.bend as B
import ../MODEL.bend as ModelModel
import ../TYPES.bend as InteractionTypes
import ./SURFACE.bend as SurfaceTypes
import ./VIEW.bend as View
import ../submission/field-options.bend as Options
import ../../harness/transport/schema.bend as Schema
import ../../features/board/filter.bend as Filter
import ../../harness/features/MODEL.bend as F
import ../../harness/workspace/PROJECTS.bend as Projects
import ../../bendlib/association-map.bend as Finite
import ../../features/board/STATE.bend as Board
import ./COMPOSITION.bend as Composition
import ../conversation/MODEL.bend as Conversation
import ../conversation/CODE.bend as Code
import ../services/MODEL.bend as Services
import ../session/PROGRAM.bend as ExperienceProgram
import ../../harness/tasks/PROGRAM.bend as Tasks
import ../../bendlib/json.bend as J
import ../../harness/workspace/WORKSPACE.bend as W
import ../conversation/OUTPUT.bend as Live
import ../../harness/conversation/PROGRAM.bend as Conversation2

# Observe the production payload without duplicating its node tree.
def meaning(node: SurfaceTypes.Node) -> SurfaceTypes.Meaning:
  SurfaceTypes.Node{key, semantic, label, role, value, children} = node
  value

def control_input(control: InteractionTypes.Control) -> InteractionTypes.Input:
  InteractionTypes.Control{identity, label, prominence, input, availability} = control
  input

def control_availability(control: InteractionTypes.Control) -> V.Availability:
  InteractionTypes.Control{identity, label, prominence, input, availability} = control
  availability

def choice_identity(choice: Forms.ChoiceValue) -> String:
  Forms.ChoiceValue{value, label} = choice
  value

def choice_caption(choice: Forms.ChoiceValue) -> String:
  Forms.ChoiceValue{value, label} = choice
  label

def filter_classification(choice: Filter.Choice) -> Filter.Classification:
  Filter.Choice{value, label, classification} = choice
  classification

def filter_value(choice: Filter.Choice) -> String:
  Filter.Choice{value, label, classification} = choice
  value

type ChoiceRequirements is Type:
  ChoiceRequirements{
    press_binding: @kind:SurfaceTypes.ChoiceKind -> @classification:Maybe<&2,Filter.Classification> -> @selected:Bool -> @description:String -> @+input:InteractionTypes.Input -> @+availability:V.Availability ->
      {Model.bind(SurfaceTypes.Choice{kind, classification, selected, description, input, availability}, SurfaceTypes.Press{}) == Model.when_available(Model.available(availability), input) : Maybe<&2,InteractionTypes.Input>},
    availability: @kind:SurfaceTypes.ChoiceKind -> @classification:Maybe<&2,Filter.Classification> -> @selected:Bool -> @description:String -> @input:InteractionTypes.Input -> @+availability:V.Availability ->
      {Model.focusable(SurfaceTypes.Choice{kind, classification, selected, description, input, availability}) == Model.available(availability) : Bool},
    filter_payload: @+choice:Filter.Choice -> @+category:String -> @+filter:B.Filter -> @parent: Identity.Key -> @+state:InteractionTypes.State ->
      {meaning(Model.filter_option_node(choice, category, filter, parent, state)) ==
        SurfaceTypes.Choice{SurfaceTypes.MultipleChoice{}, Some{filter_classification(choice)},
          Schema.contains(Filter.values(category, filter), filter_value(choice)), "",
          control_input(Core.control(state, Model.filter_option_declaration(choice, category, filter))),
          control_availability(Core.control(state, Model.filter_option_declaration(choice, category, filter)))} : SurfaceTypes.Meaning},
    owner_identity: @+owner:B.Owner -> @world:M.World() ->
      {choice_identity(View.card_owner_choice(owner, world)) == B.owner_name(owner) : String},
    owner_caption: @+owner:B.Owner -> @+world:M.World() ->
      {choice_caption(View.card_owner_choice(owner, world)) == View.face_owner(owner, world) : String},
    card_owner_options: @value:B.Draft -> @projects:+List<V.ProjectChoice> -> @stages:+List<B.Stage> -> @priorities:+List<B.Priority> -> @+owners:+List<Forms.ChoiceValue> ->
      {Options.group_options("card-owner", V.CardContentInput{value, projects, stages, priorities, owners}) == owners : +List<Forms.ChoiceValue>},
    card_priority_options: @value:B.Draft -> @projects:+List<V.ProjectChoice> -> @stages:+List<B.Stage> -> @+priorities:+List<B.Priority> -> @owners:+List<Forms.ChoiceValue> ->
      {Options.group_options("card-priority", V.CardContentInput{value, projects, stages, priorities, owners}) == Options.priority_options(priorities) : +List<Forms.ChoiceValue>}
  }

law choice_evidence:
  ChoiceRequirements

def face_id(face: V.CardFace) -> Nat:
  match face:
    case V.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated}: id

def face_title(face: V.CardFace) -> String:
  match face:
    case V.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated}: title

def face_description(face: V.CardFace) -> String:
  match face:
    case V.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated}: description

def face_priority(face: V.CardFace) -> B.Priority:
  match face:
    case V.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated}: priority

def face_pinned(face: V.CardFace) -> Bool:
  match face:
    case V.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated}: pinned

def face_status(face: V.CardFace) -> String:
  match face:
    case V.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated}: status

def face_project(face: V.CardFace) -> String:
  match face:
    case V.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated}: project

def face_labels(face: V.CardFace) -> +List<String>:
  match face:
    case V.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated}: labels

def face_owner(face: V.CardFace) -> String:
  match face:
    case V.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated}: owner

def face_updated(face: V.CardFace) -> String:
  match face:
    case V.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated}: updated

def action_stage(control: V.ControlDeclaration) -> Maybe<&2, B.Stage>:
  V.ControlDeclaration{identity, label, prominence, input, availability} = control
  match input:
    case U.Activate{U.NewCard{stage}}: Some{stage}
    case _: None{}

def action_prominence(control: V.ControlDeclaration) -> V.Prominence:
  V.ControlDeclaration{identity, label, prominence, input, availability} = control
  prominence

def page_global_create_stage(page: V.Page) -> Maybe<&2, B.Stage>:
  match page:
    case V.BoardPage{filter, columns, create, working, settings, filters, archive}: action_stage(create)
    case _: None{}

def page_global_create_prominence(page: V.Page) -> Maybe<&2, V.Prominence>:
  match page:
    case V.BoardPage{filter, columns, create, working, settings, filters, archive}: Some{action_prominence(create)}
    case _: None{}

def first_lane_create_stage(columns: +List<V.BoardColumn>) -> Maybe<&2, B.Stage>:
  match columns:
    case Nil{}: None{}
    case Con{V.BoardColumn{stage, cards, create}, rest}: action_stage(create)

def first_lane_create_prominence(columns: +List<V.BoardColumn>) -> Maybe<&2, V.Prominence>:
  match columns:
    case Nil{}: None{}
    case Con{V.BoardColumn{stage, cards, create}, rest}: Some{action_prominence(create)}

def card_scene_ids(cards: +List<V.CardScene>) -> +List<Nat>:
  match cards:
    case Nil{}: Nil{}
    case Con{V.CardScene{id, value, open, actions, linked, destinations, candidates}, rest}: id <> card_scene_ids(rest)

def board_entry_ids(entries: +List<Finite.Entry(B.Card)>) -> +List<Nat>:
  match entries:
    case Nil{}: Nil{}
    case Con{(id, card), rest}: id <> board_entry_ids(rest)

def card_scene_identity(scene: V.CardScene) -> Nat:
  match scene:
    case V.CardScene{id, value, open, actions, linked, destinations, candidates}: id

def first_lane_card_count(nodes: +List<SurfaceTypes.Node>) -> Maybe<&2, Nat>:
  match nodes:
    case Nil{}: None{}
    case Con{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.BoardLane{stage, count}, children}, rest}: Some{count}
    case Con{node, rest}: None{}

def first_lane_child_count(nodes: +List<SurfaceTypes.Node>) -> Maybe<&2, Nat>:
  match nodes:
    case Nil{}: None{}
    case Con{SurfaceTypes.Node{key, semantic, label, role, meaning, children}, rest}: Some{List.length(&2, SurfaceTypes.Node, children)}

def work_status_child_key(nodes: +List<SurfaceTypes.Node>) -> Maybe<&2, String>:
  match nodes:
    case Nil{}: None{}
    case Con{node, rest}:
      match node:
        case SurfaceTypes.Node{key, semantic, label, role, meaning, children}:
          match meaning:
            case SurfaceTypes.BoardGroup{grouping}:
              match grouping:
                case SurfaceTypes.WorkStatus{}:
                  match children:
                    case Nil{}: None{}
                    case Con{child, _}:
                      match child:
                        case SurfaceTypes.Node{key, semantic, label, role, meaning, children}: Some{Identity.encode(key)}
                case _: work_status_child_key(rest)
            case _: work_status_child_key(rest)

def navigation_header_node(navigation: SurfaceTypes.Node) -> Maybe<&2, SurfaceTypes.Node>:
  match navigation:
    case SurfaceTypes.Node{key, semantic, label, role, meaning, children}:
      match children:
        case Nil{}: None{}
        case Con{header, rest}:
          match header:
            case SurfaceTypes.Node{key, semantic, label, role, meaning, children}:
              match role:
                case SurfaceTypes.NavigationHeader{}: Some{header}
                case _: None{}

def navigation_header_label_of(header: Maybe<&2, SurfaceTypes.Node>) -> Maybe<&2, String>:
  match header:
    case None{}: None{}
    case Some{header}:
      match header:
        case SurfaceTypes.Node{key, semantic, label, role, meaning, children}: Some{label}

def navigation_header_children_of(header: Maybe<&2, SurfaceTypes.Node>) -> Maybe<&2, +List<SurfaceTypes.Node>>:
  match header:
    case None{}: None{}
    case Some{header}:
      match header:
        case SurfaceTypes.Node{key, semantic, label, role, meaning, children}: Some{children}

def navigation_header_label(navigation: SurfaceTypes.Node) -> Maybe<&2, String>:
  navigation_header_label_of(navigation_header_node(navigation))

def navigation_header_children(navigation: SurfaceTypes.Node) -> Maybe<&2, +List<SurfaceTypes.Node>>:
  navigation_header_children_of(navigation_header_node(navigation))

def navigation_toggle_control(navigation: V.Navigation) -> V.ControlDeclaration:
  V.Navigation{expanded, create, destinations, projects, tasks, toggle} = navigation
  toggle

def choose_column_ids(matches: Bool, cards: +List<Nat>, rest: +List<Nat>) -> +List<Nat>:
  match matches:
    case True{}: cards
    case False{}: rest

def page_column_ids(columns: +List<V.BoardColumn>, +target: B.Stage) -> +List<Nat>:
  match columns:
    case Nil{}: Nil{}
    case Con{V.BoardColumn{stage, cards, create}, rest}:
      choose_column_ids(String.eq(B.stage_name(stage), B.stage_name(target)), card_scene_ids(cards), page_column_ids(rest, target))

def board_page_column_ids(page: V.Page, target: B.Stage) -> +List<Nat>:
  match page:
    case V.BoardPage{filter, columns, create, working, settings, filters, archive}: page_column_ids(columns, target)
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
  B.Filter{view, search, Model.toggled_filter(status, value), priority, date, assignee, creator, project, label}

def toggled_priority_filter(+value: String, +filter: B.Filter) -> B.Filter:
  B.Filter{view, search, status, priority, date, assignee, creator, project, label} = filter
  B.Filter{view, search, status, Model.toggled_filter(priority, value), date, assignee, creator, project, label}

def toggled_date_filter(+value: String, +filter: B.Filter) -> B.Filter:
  B.Filter{view, search, status, priority, date, assignee, creator, project, label} = filter
  B.Filter{view, search, status, priority, Model.toggled_filter(date, value), assignee, creator, project, label}

def toggled_assignee_filter(+value: String, +filter: B.Filter) -> B.Filter:
  B.Filter{view, search, status, priority, date, assignee, creator, project, label} = filter
  B.Filter{view, search, status, priority, date, Model.toggled_filter(assignee, value), creator, project, label}

def toggled_creator_filter(+value: String, +filter: B.Filter) -> B.Filter:
  B.Filter{view, search, status, priority, date, assignee, creator, project, label} = filter
  B.Filter{view, search, status, priority, date, assignee, Model.toggled_filter(creator, value), project, label}

def toggled_project_filter(+value: String, +filter: B.Filter) -> B.Filter:
  B.Filter{view, search, status, priority, date, assignee, creator, project, label} = filter
  B.Filter{view, search, status, priority, date, assignee, creator, Model.toggled_filter(project, value), label}

def toggled_label_filter(+value: String, +filter: B.Filter) -> B.Filter:
  B.Filter{view, search, status, priority, date, assignee, creator, project, label} = filter
  B.Filter{view, search, status, priority, date, assignee, creator, project, Model.toggled_filter(label, value)}

def declaration_input(declaration: V.ControlDeclaration) -> U.Input:
  V.ControlDeclaration{identity, label, prominence, input, availability} = declaration
  input

def navigation_create_control(navigation: V.Navigation) -> V.ControlDeclaration:
  V.Navigation{expanded, create, destinations, projects, tasks, toggle} = navigation
  create

def navigation_board_control(navigation: V.Navigation) -> Maybe<&2, V.ControlDeclaration>:
  V.Navigation{expanded, create, destinations, projects, tasks, toggle} = navigation
  match destinations:
    case Con{board, rest}: Some{board}
    case Nil{}: None{}

def navigation_projects_control(navigation: V.Navigation) -> Maybe<&2, V.ControlDeclaration>:
  V.Navigation{expanded, create, destinations, projects, tasks, toggle} = navigation
  match destinations:
    case Con{board, Con{collection, rest}}: Some{collection}
    case _: None{}

def navigation_agents_control(navigation: V.Navigation) -> Maybe<&2, V.ControlDeclaration>:
  V.Navigation{expanded, create, destinations, projects, tasks, toggle} = navigation
  match destinations:
    case Con{board, Con{collection, Con{agents, rest}}}: Some{agents}
    case _: None{}

def selected_control(found: Maybe<&2, V.ControlDeclaration>, route: U.Route) -> Bool:
  match found:
    case None{}: False{}
    case Some{control}: Model.navigation_action_selected(route, declaration_input(control))

def board_navigation_selected(+route: U.Route, +world: M.World(), +session: E.Session) -> Bool:
  selected_control(navigation_board_control(View.navigation(True{}, route, world, session)), route)

def projects_navigation_selected(+route: U.Route, +world: M.World(), +session: E.Session) -> Bool:
  selected_control(navigation_projects_control(View.navigation(True{}, route, world, session)), route)

def agents_navigation_selected(+route: U.Route, +world: M.World(), +session: E.Session) -> Bool:
  selected_control(navigation_agents_control(View.navigation(True{}, route, world, session)), route)

def create_navigation_selected(+route: U.Route, +world: M.World(), +session: E.Session) -> Bool:
  Model.navigation_action_selected(route, declaration_input(navigation_create_control(View.navigation(True{}, route, world, session))))

def settings_state_law(-board: B.State, -world: M.World()) -> Type:
  {View.board_settings(board, world) ==
    V.BoardSettings{B.automatic(board), B.draft_profile(board), Board.profiles(world),
      View.board_control("board/automatic", "自动排期",
        B.Settings{Bool.not(B.automatic(board)), B.draft_profile(board)}, world)} : V.LayerContent}

type BoardPresentationRequirements is Type:
  BoardPresentationRequirements{
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
    card_root_count: @+entries:+List<V.CardScene> -> @+parent: Identity.Key -> @+state:InteractionTypes.State ->
      {List.length(&2, SurfaceTypes.Node, Model.cards(entries, parent, state)) == List.length(&2, V.CardScene, entries) : Nat},
    lane_count: @stage:B.Stage -> @+entries:+List<V.CardScene> -> @+create:V.ControlDeclaration -> @+parent: Identity.Key -> @+state:InteractionTypes.State ->
      {first_lane_card_count(Model.columns([V.BoardColumn{stage, entries, create}], parent, state)) ==
        Some{List.length(&2, V.CardScene, entries)} : Maybe<&2, Nat>},
    lane_children: @stage:B.Stage -> @+entries:+List<V.CardScene> -> @+create:V.ControlDeclaration -> @+parent: Identity.Key -> @+state:InteractionTypes.State ->
      {first_lane_child_count(Model.columns([V.BoardColumn{stage, entries, create}], parent, state)) ==
        Some{(1n + List.length(&2, V.CardScene, entries) : Nat)} : Maybe<&2, Nat>},
    toolbar_work_status_identity: @+filter:B.Filter -> @working:Nat -> @create:V.ControlDeclaration ->
      @settings:V.ControlDeclaration -> @filters:V.ControlDeclaration -> @archive:V.ControlDeclaration ->
      @+parent: Identity.Key -> @+state:InteractionTypes.State ->
      {work_status_child_key(Model.board_toolbar(filter, working, create, settings, filters, archive, parent, state)) ==
        Some{Identity.encode(Identity.Part{Identity.Part{parent, "work-status"}, "view/working"})} : Maybe<&2, String>},
    navigation_header_brand: @+navigation:V.Navigation -> @+state:InteractionTypes.State ->
      {navigation_header_label(Model.navigation(navigation, state)) == Some{"Selvedge"} : Maybe<&2, String>},
    navigation_header_toggle: @+navigation:V.Navigation -> @+state:InteractionTypes.State ->
      {navigation_header_children(Model.navigation(navigation, state)) ==
        Some{[Model.declared(Identity.Place{"/navigation"}, navigation_toggle_control(navigation), state)]} : Maybe<&2, +List<SurfaceTypes.Node>>},
    pinned_order: @+board:B.State -> {Board.display_cards(board) == pinned_partition(board) : +List<Finite.Entry(B.Card)>},
    board_column_ids: @+board:B.State -> @+filter:B.Filter -> @+route:U.Route -> @+now:U32 -> @+world:M.World() -> @target:B.Stage ->
      {board_page_column_ids(View.board_page(board, filter, route, now, world), target) ==
        board_entry_ids(Filter.column(Filter.filtered(pinned_partition(board), filter, now, world), B.stage_name(target))) : +List<Nat>},
    project_none: @+world:M.World() -> {View.face_project(None{}, world) == "" : String},
    project_missing: @+id:Nat -> @+world:M.World() ->
      @absent:{Projects.find(Projects.registry(F.State(), world), id) == None{} : Maybe<&2, D.Project>} ->
      {View.face_project(Some{id}, world) == "项目 #" ++ Nat.show(id) ++ " 不可用" : String},
    profile_missing: @+key: String -> @+world:M.World() ->
      @absent:{D.find_profile(Board.profiles(world), key) == None{} : Maybe<&2, D.Profile>} ->
      {View.face_owner(B.Profile{key}, world) == "配置 " ++ key ++ " 不可用" : String},
    agent_missing: @id:Nat -> @+world:M.World() ->
      @absent:{B.find_agent(Board.registry(world), id) == None{} : Maybe<&2, B.AgentProfile>} ->
      {View.face_owner(B.Agent{id}, world) == "智能体 #" ++ Nat.show(id) ++ " 不可用" : String},
    search_facets: @+search:String -> @+filter:B.Filter ->
      {Model.with_search(search, filter) == search_filter(search, filter) : B.Filter},
    status_facets: @+value:String -> @+filter:B.Filter ->
      {Model.toggle_filter("status", value, filter) == toggled_status_filter(value, filter) : B.Filter},
    priority_facets: @+value:String -> @+filter:B.Filter ->
      {Model.toggle_filter("priority", value, filter) == toggled_priority_filter(value, filter) : B.Filter},
    date_facets: @+value:String -> @+filter:B.Filter ->
      {Model.toggle_filter("date", value, filter) == toggled_date_filter(value, filter) : B.Filter},
    assignee_facets: @+value:String -> @+filter:B.Filter ->
      {Model.toggle_filter("assignee", value, filter) == toggled_assignee_filter(value, filter) : B.Filter},
    creator_facets: @+value:String -> @+filter:B.Filter ->
      {Model.toggle_filter("creator", value, filter) == toggled_creator_filter(value, filter) : B.Filter},
    project_facets: @+value:String -> @+filter:B.Filter ->
      {Model.toggle_filter("project", value, filter) == toggled_project_filter(value, filter) : B.Filter},
    label_facets: @+value:String -> @+filter:B.Filter ->
      {Model.toggle_filter("label", value, filter) == toggled_label_filter(value, filter) : B.Filter},
    global_create_stage: @board:B.State -> @+filter:B.Filter -> @+route:U.Route -> @+now:U32 -> @+world:M.World() ->
      {page_global_create_stage(View.board_page(board, filter, route, now, world)) == Some{B.Todo{}} : Maybe<&2, B.Stage>},
    global_create_prominence: @board:B.State -> @+filter:B.Filter -> @+route:U.Route -> @+now:U32 -> @+world:M.World() ->
      {page_global_create_prominence(View.board_page(board, filter, route, now, world)) == Some{V.Primary{}} : Maybe<&2, V.Prominence>},
    lane_create_stage: @stage:B.Stage -> @+route:U.Route -> @+now:U32 -> @+world:M.World() ->
      {first_lane_create_stage(View.columns([stage], Nil{}, route, now, world)) == Some{stage} : Maybe<&2, B.Stage>},
    lane_create_prominence: @stage:B.Stage -> @+route:U.Route -> @+now:U32 -> @+world:M.World() ->
      {first_lane_create_prominence(View.columns([stage], Nil{}, route, now, world)) == Some{V.Secondary{}} : Maybe<&2, V.Prominence>},
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
    selected_navigation_role: @route:U.Route -> @+parent: Identity.Key -> @+declaration:V.ControlDeclaration -> @+state:InteractionTypes.State ->
      {Model.node_role(Model.selected_declaration(route, parent, declaration, state)) ==
        Model.node_role(Model.selected_node(Model.navigation_action_selected(route, declaration_input(declaration)),
          Model.declared(parent, declaration, state))) : SurfaceTypes.Role},
    settings_state: @+board:B.State -> @+world:M.World() ->
      settings_state_law(board, world),
    settings_layer: @+session:E.Session -> @+world:M.World() ->
      {View.layer_content(U.BoardSettings{}, session, world) == View.board_settings(Board.registry(world), world) : V.LayerContent},
    create_draft: @stage:B.Stage -> @+application:E.Application ->
      {E.activate_selected(U.NewCard{stage}, application) == E.new_card(stage, application) : E.Decision},
    create_body: @stage:B.Stage ->
      {E.new_card_body(stage) == U.Card{None{}, 0n, B.Draft{"", "", stage, B.NoPriority{}, B.Unassigned{}, None{}, Nil{}, Nil{}}, False{}, "", False{}} : U.Body},
    edit_saved_card: @id:Nat -> @+application:E.Application ->
      {E.activate_selected(U.EditCard{id}, application) == E.card_editor(id, application) : E.Decision}
  }

law board_presentation_evidence:
  BoardPresentationRequirements

# Only direct page regions participate; an entry's ordinary heading is never promoted.
def observed_regions(nodes: +List<SurfaceTypes.Node>) -> +List<Composition.PositionedRegion>:
  match nodes:
    case Nil{}: Nil{}
    case Con{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.PageRegion{region, position}, children}, rest}:
      Composition.PositionedRegion{position, region} <> observed_regions(rest)
    case Con{node, rest}: observed_regions(rest)

def required_regions(page: V.Page) -> +List<Composition.PositionedRegion>:
  Composition.ordered_regions(Composition.structure(Composition.recipe(View.page_composition(page))))

def only_regions(nodes: +List<SurfaceTypes.Node>) -> Bool:
  match nodes:
    case Nil{}: True{}
    case Con{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.PageRegion{region, position}, children}, rest}: only_regions(rest)
    case Con{node, rest}: False{}

def region_children(node: SurfaceTypes.Node) -> +List<SurfaceTypes.Node>:
  SurfaceTypes.Node{key, semantic, label, role, meaning, children} = node
  children

def select_region(matches: Bool, children: +List<SurfaceTypes.Node>, rest: Maybe<&2, +List<SurfaceTypes.Node>>) -> Maybe<&2, +List<SurfaceTypes.Node>>:
  match matches:
    case True{}: Some{children}
    case False{}: rest

def find_region(nodes: +List<SurfaceTypes.Node>, +region: Composition.Region) -> Maybe<&2, +List<SurfaceTypes.Node>>:
  match nodes:
    case Nil{}: None{}
    case Con{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.PageRegion{part, position}, children}, rest}:
      select_region(String.eq(Composition.region_name(part), Composition.region_name(region)), children, find_region(rest, region))
    case Con{node, rest}: find_region(rest, region)

def task_title_text(value: V.TaskScene) -> String:
  V.TaskScene{id, title, status, context, timeline, previews, composer, details, actions} = value
  title

def task_title_key(value: V.TaskScene, parent: Identity.Key) -> Identity.Key:
  V.TaskScene{id, title, status, context, timeline, previews, composer, details, actions} = value
  Identity.Entity{parent, "task", Nat.show(id)}

def project_title_text(value: V.ProjectScene) -> String:
  V.ProjectScene{id, name, workspace, guidance, tasks, actions} = value
  name

def layer_label(nodes: +List<SurfaceTypes.Node>) -> Maybe<&2, String>:
  match nodes:
    case Nil{}: None{}
    case Con{SurfaceTypes.Node{key, semantic, label, role, meaning, children}, rest}: Some{label}

def layer_semantic(nodes: +List<SurfaceTypes.Node>) -> Maybe<&2, String>:
  match nodes:
    case Nil{}: None{}
    case Con{SurfaceTypes.Node{key, semantic, label, role, meaning, children}, rest}: Some{semantic}

type LayerTitleRequirements is Type:
  LayerTitleRequirements{
    new_task: {View.editor_title(U.NewTaskEditor{}) == "New task" : String},
    message: @task:Nat -> {View.editor_title(U.MessageEditor{task}) == "Message" : String},
    new_project: {View.editor_title(U.ProjectEditor{None{}}) == "New project" : String},
    edit_project: @id:Nat -> {View.editor_title(U.ProjectEditor{Some{id}}) == "Edit project" : String},
    new_card: {View.editor_title(U.CardEditor{None{}}) == "New card" : String},
    edit_card: @id:Nat -> {View.editor_title(U.CardEditor{Some{id}}) == "Edit card" : String},
    new_agent: {View.editor_title(U.AgentEditor{None{}}) == "New agent" : String},
    edit_agent: @id:Nat -> {View.editor_title(U.AgentEditor{Some{id}}) == "Edit agent" : String},
    fork: @task:Nat -> {View.editor_title(U.ForkEditor{task}) == "Fork task" : String},
    compact: @task:Nat -> {View.editor_title(U.CompactEditor{task}) == "Compact history" : String},
    actions: @actions:+List<V.ControlDeclaration> -> {View.layer_title(V.ObjectActions{actions}) == "Actions" : String},
    archived: @cards:+List<V.CardScene> -> {View.layer_title(V.ArchivedCards{cards}) == "Archived cards" : String},
    board_settings: @automatic:Bool -> @selected:String -> @profiles:+List<D.Profile> -> @automation:V.ControlDeclaration ->
      {View.layer_title(V.BoardSettings{automatic, selected, profiles, automation}) == "看板设置" : String},
    board_filters: @filter:B.Filter -> {View.layer_title(V.BoardFilters{filter}) == "筛选任务" : String},
    unavailable: {View.layer_title(V.ObjectEditor{None{}}) == "Editor unavailable" : String},
    editor: @identity:U.Editor -> @revision:Nat -> @groups:+List<V.InputGroup> -> @sections:+List<Forms.Section> -> @submit:V.ControlDeclaration -> @feedback:U.Feedback -> @pending:Bool -> {View.layer_title(V.ObjectEditor{Some{V.EditorScene{identity, revision, groups, sections, submit, feedback, pending}}}) == View.editor_title(identity) : String},
    workspace: @editor:U.Editor -> @fields:+List<V.InputGroup> -> {View.layer_title(V.WorkspaceSettings{editor, fields}) == "Working directories" : String},
    permissions: @editor:U.Editor -> @fields:+List<V.InputGroup> -> {View.layer_title(V.PermissionSettings{editor, fields}) == "Permissions" : String},
    committed: @context:Maybe<&2, Context.EffectiveContext> -> {View.layer_title(V.CommittedContext{context}) == "Execution context" : String},
    models: @editor:U.Editor -> @query:String -> @fields:+List<V.InputGroup> -> {View.layer_title(V.ModelSelection{editor, query, fields}) == "Choose model" : String},
    delivery: @editor:U.Editor -> @fields:+List<V.InputGroup> -> {View.layer_title(V.DeliverySelection{editor, fields}) == "Delivery options" : String},
    details: @task:Maybe<&2, V.TaskScene> -> {View.layer_title(V.ExecutionDetails{task}) == "Task details" : String},
    confirmation: @title:String -> @confirm:V.ControlDeclaration -> @cancel:V.ControlDeclaration -> {View.layer_title(V.Confirmation{title, confirm, cancel}) == title : String}
  }

def surface_base(value: SurfaceTypes.Surface) -> +List<SurfaceTypes.Node>:
  SurfaceTypes.Surface{content, base, overlays, active} = value
  base

def navigation_head(values: +List<SurfaceTypes.Node>) -> SurfaceTypes.Node:
  match values:
    case Con{node, rest}: node
    case Nil{}: SurfaceTypes.Node{Identity.Place{""}, "", "", SurfaceTypes.Section{}, SurfaceTypes.Region{}, Nil{}}

def content_navigation(value: InteractionTypes.Scene) -> V.Navigation:
  InteractionTypes.Scene{V.Scene{nav, main, layers, arrangement, attention}, settings, transfers, preview, code, directory_picker} = value
  nav

def content_navigation_placement(value: InteractionTypes.Scene) -> V.NavigationPlacement:
  InteractionTypes.Scene{V.Scene{nav, main, layers, V.Arrangement{placement}, attention}, settings, transfers, preview, code, directory_picker} = value
  placement

def owned_page_context(page: V.Page) -> Maybe<&2, Conversation.Identity>:
  match page:
    case V.TaskPage{V.TaskScene{id, title, status, context, timeline, previews, input, details, actions}}: Some{Conversation.identity(timeline)}
    case _: None{}

def task_reading(+value: V.TaskScene, +parent: Identity.Key, +state: InteractionTypes.State) -> Type:
  V.TaskScene{+id, title, status, context, Conversation.Timeline{task, generation, groups, live, decisions, reading, return_latest}, previews, input, details, actions} = value
  +owner : Identity.Key = Identity.Entity{parent, "task", Nat.show(id)}
  {find_region(Model.page_contents(V.TaskPage{value}, parent, state), Composition.TimelineContent{}) ==
    Some{[Model.region(owner, "timeline", "Conversation", SurfaceTypes.Timeline{},
      List.append(&2, SurfaceTypes.Node, Model.groups(groups, id, Identity.Part{owner, "timeline"}, state),
        List.append(&2, SurfaceTypes.Node, Model.live_outputs(previews, owner, state), Model.operations(live, owner, state))))]} : Maybe<&2, +List<SurfaceTypes.Node>>}

type PageRegionRequirements is Type:
  PageRegionRequirements{
    page_payload: @+page:V.Page -> @+state:InteractionTypes.State ->
      {Model.page(page, state) == SurfaceTypes.Node{Identity.Place{"/main"}, "main", "Content", SurfaceTypes.Main{}, SurfaceTypes.PageContext{owned_page_context(page)}, Model.page_contents(page, Identity.Place{"/main"}, state)} : SurfaceTypes.Node},
    collapsed_navigation_single: @+toggle: V.ControlDeclaration -> @expanded: Bool -> @create: V.ControlDeclaration -> @destinations: +List<V.ControlDeclaration> -> @projects: +List<V.ProjectEntry> -> @tasks: +List<V.TaskEntry> -> @+state: InteractionTypes.State -> {Model.base_navigation_at(V.CollapsedNavigation{}, V.Navigation{expanded, create, destinations, projects, tasks, toggle}, state) ==
    [Model.declared(Identity.Place{"/navigation"}, toggle, state)] : +List<SurfaceTypes.Node>},
    collapsed_assembly: @+content: InteractionTypes.Scene -> @+state: InteractionTypes.State -> @collapsed: {content_navigation_placement(content) == V.CollapsedNavigation{} : V.NavigationPlacement} -> {navigation_head(surface_base(Model.assemble(content, state))) ==
    navigation_head(Model.collapsed_navigation_toggle(content_navigation(content), state)) : SurfaceTypes.Node},

    layer_titles: LayerTitleRequirements,
    layer_name: @+kind:V.LayerKind -> @+content:V.LayerContent -> @+initial:String -> @+restore:String -> @+close:V.Dismissal -> @+state:InteractionTypes.State ->
      {layer_label(Model.layers([V.Layer{kind, content, initial, restore, close}], state)) == Some{View.layer_title(content)} : Maybe<&2, String>},
    attention_independent: @+kind:V.LayerKind -> @+content:V.LayerContent -> @+first:String -> @+second:String -> @+restore:String -> @+close:V.Dismissal -> @+state:InteractionTypes.State ->
      {layer_label(Model.layers([V.Layer{kind, content, first, restore, close}], state)) ==
        layer_label(Model.layers([V.Layer{kind, content, second, restore, close}], state)) : Maybe<&2, String>},
    attention_identity: @+kind:V.LayerKind -> @+content:V.LayerContent -> @+initial:String -> @+restore:String -> @+close:V.Dismissal -> @+state:InteractionTypes.State ->
      {layer_semantic(Model.layers([V.Layer{kind, content, initial, restore, close}], state)) == Some{initial} : Maybe<&2, String>},
    page_sequence: @+page:V.Page -> @+parent: Identity.Key -> @+state:InteractionTypes.State ->
      {observed_regions(Model.page_contents(page, parent, state)) == required_regions(page) : +List<Composition.PositionedRegion>},
    only_regions: @+page:V.Page -> @+parent: Identity.Key -> @+state:InteractionTypes.State ->
      {only_regions(Model.page_contents(page, parent, state)) == True{} : Bool},
    projects_title: @+projects:+List<V.ProjectScene> -> @+create:V.ControlDeclaration -> @+parent: Identity.Key -> @+state:InteractionTypes.State ->
      {find_region(Model.page_contents(V.ProjectsPage{projects, create}, parent, state), Composition.CollectionTitle{}) ==
        Some{[Model.region(parent, "heading", "Projects", SurfaceTypes.Heading{}, Nil{})]} : Maybe<&2, +List<SurfaceTypes.Node>>},
    agents_title: @+agents:+List<V.AgentScene> -> @+create:V.ControlDeclaration -> @+parent: Identity.Key -> @+state:InteractionTypes.State ->
      {find_region(Model.page_contents(V.AgentsPage{agents, create}, parent, state), Composition.CollectionTitle{}) ==
        Some{[Model.region(parent, "heading", "Agents", SurfaceTypes.Heading{}, Nil{})]} : Maybe<&2, +List<SurfaceTypes.Node>>},
    board_title: @+filter:B.Filter -> @+columns:+List<V.BoardColumn> -> @+create:V.ControlDeclaration -> @working:Nat ->
      @+settings:V.ControlDeclaration -> @+filters:V.ControlDeclaration -> @+archive:V.ControlDeclaration -> @+parent: Identity.Key -> @+state:InteractionTypes.State ->
      {find_region(Model.page_contents(V.BoardPage{filter, columns, create, working, settings, filters, archive}, parent, state), Composition.BoardTitle{}) ==
        Some{[Model.region(parent, "heading", "Board", SurfaceTypes.Heading{}, Nil{})]} : Maybe<&2, +List<SurfaceTypes.Node>>},
    creation_title: @+heading:String -> @+summary:String -> @+context:Maybe<&2, Context.Preview> -> @+project:Maybe<&2, V.ProjectChoice> -> @+choose:V.ControlDeclaration -> @+parent: Identity.Key -> @+state:InteractionTypes.State ->
      {find_region(Model.creation_introduction_nodes(V.CreationIntroduction{heading, summary, context, project, choose}, parent, state), Composition.CreationIntroduction{}) ==
        Some{[SurfaceTypes.Node{Identity.Part{Identity.Part{Identity.Part{Identity.Part{parent, "creation"}, "introduction"}, "creation"}, "title"}, "creation/title", heading, SurfaceTypes.Heading{}, SurfaceTypes.ReadOnly{heading}, Nil{}}, Model.creation_project_node(V.CreationIntroduction{heading, summary, context, project, choose}, parent, state)]} : Maybe<&2, +List<SurfaceTypes.Node>>},
    task_reading: @+value:V.TaskScene -> @+parent:Identity.Key -> @+state:InteractionTypes.State -> task_reading(value, parent, state),
    task_title: @+value:V.TaskScene -> @+parent: Identity.Key -> @+state:InteractionTypes.State ->
      {find_region(Model.page_contents(V.TaskPage{value}, parent, state), Composition.ConversationTitle{}) ==
        Some{[Model.region(task_title_key(value, parent), "heading", task_title_text(value), SurfaceTypes.Heading{}, Nil{})]} : Maybe<&2, +List<SurfaceTypes.Node>>},
    project_title: @+value:V.ProjectScene -> @+parent: Identity.Key -> @+state:InteractionTypes.State ->
      {find_region(Model.page_contents(V.ProjectPage{value}, parent, state), Composition.ProjectTitle{}) ==
        Some{[Model.region(parent, "heading", project_title_text(value), SurfaceTypes.Heading{}, Nil{})]} : Maybe<&2, +List<SurfaceTypes.Node>>},
    passive: @region:Composition.Region -> @position:Composition.Position -> @gesture:SurfaceTypes.Gesture ->
      {Model.bind(SurfaceTypes.PageRegion{region, position}, gesture) == None{} : Maybe<&2, InteractionTypes.Input>},
    children: @+parent: Identity.Key -> @+region:Composition.Region -> @+position:Composition.Position -> @+nodes:+List<SurfaceTypes.Node> ->
      {region_children(Model.page_region(parent, region, position, nodes)) == nodes : +List<SurfaceTypes.Node>},
    identity: @+parent: Identity.Key -> @+region:Composition.Region -> @+position:Composition.Position -> @+nodes:+List<SurfaceTypes.Node> ->
      {Model.node_key(Model.page_region(parent, region, position, nodes)) == Identity.encode(Identity.Part{Identity.Part{parent, "region"}, Composition.region_name(region)}) : String}
  }

law page_region_evidence:
  PageRegionRequirements

type SpeechProjection is Data:
  SpeechProjection{key: Identity.Key, semantic: String, label: String, role: SurfaceTypes.Role, meaning: SurfaceTypes.Meaning}

def has_composer(composer: Maybe<&2, V.ComposerScene>) -> Bool:
  match composer:
    case None{}: False{}
    case Some{scene}: True{}

def expected_bottom_composer(present: Bool) -> Composition.Composer:
  match present:
    case True{}: Composition.BottomInput{}
    case False{}: Composition.NoComposer{}

def expected_decisions(present: Bool) -> Composition.Decisions:
  match present:
    case True{}: Composition.BeforeComposer{}
    case False{}: Composition.NoDecisions{}

def expected_latest(present: Bool) -> Composition.Latest:
  match present:
    case True{}: Composition.AboveComposer{}
    case False{}: Composition.NoLatest{}

def conversation_recipe_law(-composer: Bool, -approvals: Bool, -return_latest: Bool) -> Type:
  {Composition.recipe(Composition.Conversation{composer, approvals, return_latest}) ==
      Composition.Recipe{Composition.ReadingMeasure{}, Composition.ConversationHeading{}, Composition.ChronologicalReading{},
        expected_bottom_composer(composer), expected_decisions(approvals), expected_latest(return_latest)} : Composition.Recipe}

def expected_task_recipe(task: V.TaskScene) -> Composition.Recipe:
  V.TaskScene{id, title, status, context, timeline, previews, composer, details, actions} = task
  Conversation.Timeline{task_id, generation, groups, operations, approvals, reading, return_to_latest} = timeline
  Composition.Recipe{Composition.ReadingMeasure{}, Composition.ConversationHeading{}, Composition.ChronologicalReading{},
    expected_bottom_composer(has_composer(composer)), expected_decisions(View.has_decisions(approvals)), expected_latest(View.has_return_latest(return_to_latest))}

def expected_action_role(prominence: V.Prominence) -> SurfaceTypes.Role:
  match prominence:
    case V.Primary{}: SurfaceTypes.PrimaryButton{}
    case V.Destructive{}: SurfaceTypes.DestructiveButton{}
    case V.Secondary{}: SurfaceTypes.Button{}

def expected_action(parent: Identity.Key, control: InteractionTypes.Control) -> SurfaceTypes.Node:
  InteractionTypes.Control{+identity, label, prominence, input, availability} = control
  SurfaceTypes.Node{Identity.Part{parent, identity}, identity, label, expected_action_role(prominence),
    SurfaceTypes.Activate{input, availability}, Nil{}}

def expected_speaker_role(speaker: Conversation.Speaker) -> SurfaceTypes.Role:
  match speaker:
    case Conversation.UserSpeech{}: SurfaceTypes.UserMessage{}
    case Conversation.AssistantSpeech{}: SurfaceTypes.AssistantMessage{}

def first_speech_projection(nodes: +List<SurfaceTypes.Node>) -> Maybe<&2, SpeechProjection>:
  match nodes:
    case Nil{}: None{}
    case Con{SurfaceTypes.Node{key, semantic, label, role, meaning, children}, rest}:
      Some{SpeechProjection{key, semantic, label, role, meaning}}

def expected_structure(recipe: Composition.Recipe) -> Composition.Structure:
  match recipe:
    case Composition.Recipe{measure, heading, Composition.CenteredCreation{}, composer, decisions, latest}:
      Composition.Structure{Nil{}, Composition.CreationIntroduction{} <> Composition.CreationContext{} <> Composition.centered_composer_region(composer), Nil{}}
    case Composition.Recipe{measure, heading, Composition.ChronologicalReading{}, composer, decisions, latest}:
      Composition.Structure{[Composition.ConversationTitle{}, Composition.TaskActions{}],
        [Composition.TimelineContent{}],
        List.append(&2, Composition.Region, Composition.latest_region(latest),
          List.append(&2, Composition.Region, Composition.decisions_region(decisions), Composition.bottom_composer_region(composer)))}
    case Composition.Recipe{measure, heading, Composition.ProjectSections{}, composer, decisions, latest}:
      Composition.Structure{[Composition.ProjectTitle{}, Composition.ProjectActions{}],
        [Composition.DefaultWorkspace{}, Composition.ProjectGuidance{}, Composition.ProjectTasks{}], Nil{}}
    case Composition.Recipe{measure, heading, Composition.ProjectRows{}, composer, decisions, latest}:
      Composition.Structure{[Composition.CollectionTitle{}, Composition.CollectionActions{}], [Composition.ProjectEntries{}], Nil{}}
    case Composition.Recipe{measure, heading, Composition.StageColumns{}, composer, decisions, latest}:
      Composition.Structure{[Composition.BoardTitle{}, Composition.BoardControls{}], [Composition.BoardStages{}], Nil{}}
    case Composition.Recipe{measure, heading, Composition.AgentRows{}, composer, decisions, latest}:
      Composition.Structure{[Composition.CollectionTitle{}, Composition.CollectionActions{}], [Composition.AgentEntries{}], Nil{}}
    case Composition.Recipe{measure, heading, Composition.UnavailableNotice{}, composer, decisions, latest}:
      Composition.Structure{Nil{}, [Composition.UnavailableMessage{}], Nil{}}

def introduction_context(value: V.CreationIntroduction) -> Maybe<&2, Context.Preview>:
  V.CreationIntroduction{heading, summary, context, project, choose} = value
  context

def introduction_project(value: V.CreationIntroduction) -> Maybe<&2, V.ProjectChoice>:
  V.CreationIntroduction{heading, summary, context, project, choose} = value
  project

def composer_footer(view: Maybe<&2, V.ComposerScene>) -> +List<V.ComposerControl>:
  match view:
    case None{}: Nil{}
    case Some{V.ComposerScene{identity, revision, message, footer, context, submit, feedback, pending}}: footer

type CompositionRequirements is Type:
  CompositionRequirements{
    production_regions: PageRegionRequirements,
    observed_page: @navigation:V.Navigation -> @main:V.Page -> @layers:+List<V.Layer> ->
      @placement:V.NavigationPlacement -> @attention:String ->
      {View.scene_page(V.Scene{navigation, main, layers, V.Arrangement{placement}, attention}) ==
        View.page_composition(main) : Composition.Page},
    task_page: @task:V.TaskScene ->
      {Composition.recipe(View.page_composition(V.TaskPage{task})) == expected_task_recipe(task) : Composition.Recipe},
    conversation_recipe: @composer:Bool -> @approvals:Bool -> @return_latest:Bool ->
      conversation_recipe_law(composer, approvals, return_latest),
    unavailable_page: @message:String ->
      {Composition.recipe(View.page_composition(V.MissingObject{message})) ==
        Composition.Recipe{Composition.ReadingMeasure{}, Composition.NoHeading{}, Composition.UnavailableNotice{},
          Composition.NoComposer{}, Composition.NoDecisions{}, Composition.NoLatest{}} : Composition.Recipe},
    action_prominence: @parent: Identity.Key -> @control:InteractionTypes.Control ->
      {Model.action(parent, control) == expected_action(parent, control) : SurfaceTypes.Node},
    visible_speaker: @+id:Nat -> @speaker:Conversation.Speaker -> @text:String -> @source:D.Message ->
      @+task:Nat -> @+parent: Identity.Key -> @+state:InteractionTypes.State ->
      {first_speech_projection(Model.groups([Conversation.VisibleSpeech{id, speaker, text, source}], task, parent, state)) ==
        Some{SpeechProjection{Identity.Entity{parent, "message", Nat.show(id)}, "message/" ++ Nat.show(id), "Message",
          expected_speaker_role(speaker), SurfaceTypes.RichText{Code.Message{task, id}, text}}} : Maybe<&2, SpeechProjection>},
    activity_payload: @+id:Nat -> @attention:Maybe<&2, Nat> -> @+expanded:Bool -> @summary:String -> @audit:+List<Conversation.AuditFace> -> @expand:U.Input -> @collapse:U.Input -> @+task:Nat -> @+parent: Identity.Key -> @+state:InteractionTypes.State ->
      {Model.groups([Conversation.VisibleActivity{id, attention, expanded, summary, audit, expand, collapse}], task, parent, state) ==
        [SurfaceTypes.Node{Identity.Entity{parent, "activity", Nat.show(id)}, "activity/" ++ Nat.show(id), summary, SurfaceTypes.Activity{}, SurfaceTypes.ActivityContent{expanded, audit},
          [Model.user_action(Identity.Entity{parent, "activity", Nat.show(id)}, "disclosure", Model.disclosure_label(expanded), Model.disclosure_input(expanded, expand, collapse), True{}, state)]}] : +List<SurfaceTypes.Node>},
    composer_tree: @view:Maybe<&2, V.ComposerScene> -> @+parent: Identity.Key -> @+state:InteractionTypes.State ->
      {Model.composer(view, parent, state) == Model.expected_composer(view, parent, state) : +List<SurfaceTypes.Node>},
    structure_order: @recipe:Composition.Recipe ->
      {Composition.structure(recipe) == expected_structure(recipe) : Composition.Structure},
    creation_project: @+context:Maybe<&2, Context.Preview> -> @+world:M.World() ->
      {introduction_project(View.creation_introduction_fields(context, world)) == View.creation_selected_project(context, world) : Maybe<&2, V.ProjectChoice>},
    creation_context: @+identity:U.Editor -> @revision:Nat -> @message:U.Text -> @+footer:+List<V.ComposerControl> ->
      @+context:Maybe<&2, Context.Preview> -> @submit:V.ControlDeclaration -> @feedback:U.Feedback -> @pending:Bool -> @+world:M.World() ->
      {introduction_context(View.creation_introduction(Some{V.ComposerScene{identity, revision, message, footer, View.preview_observation(context), submit, feedback, pending}}, world)) == context : Maybe<&2, Context.Preview>},
    creation_page: @+input:Maybe<&2, V.ComposerScene> -> @+parent: Identity.Key -> @+world:M.World() ->
      @+session:E.Session -> @+services:Services.State ->
      {Model.page_contents(V.StartPage{input}, parent, Core.from_application(E.from_program(world, session), services)) ==
        List.append(&2, SurfaceTypes.Node,
          Model.creation_introduction_nodes(View.creation_introduction(input, world), parent, Core.from_application(E.from_program(world, session), services)),
          Model.page_composer(input, parent, parent, Core.from_application(E.from_program(world, session), services), Composition.BodyPosition{})) : +List<SurfaceTypes.Node>},
    context_admission: @+declaration:V.ControlDeclaration -> @+rest:+List<V.ControlDeclaration> -> @+parent: Identity.Key -> @+state:InteractionTypes.State ->
      {Model.controls(declaration <> rest, parent, state) == Model.declared(parent, declaration, state) <> Model.controls(rest, parent, state) : +List<SurfaceTypes.Node>},
    composer_context: @+message:U.Text -> @+profile:String -> @reasoning:String -> @+context:Context.Configuration -> @+scene:V.EditorScene -> @+world:M.World() ->
      {composer_footer(View.composer_scene(U.NewTask{message, profile, reasoning, context}, scene, world)) ==
        [V.ComposerControl{V.ModelSubject{}, View.control("composer/model", View.profile_label(D.find_profile(Board.profiles(world), profile), profile), U.OpenPanel{U.ModelPicker{U.NewTaskEditor{}}, "composer/model"})},
         V.ComposerControl{V.WorkspaceSubject{}, View.context_control("composer/workspace/new-task", View.observation_workspace(Context.DraftExecution{Context.preview(context, world)}), U.WorkspaceConfiguration{U.NewTaskEditor{}})},
         V.ComposerControl{V.PermissionsSubject{}, View.context_control("composer/permissions/new-task", View.observation_permissions(Context.DraftExecution{Context.preview(context, world)}, Board.profiles(world)), U.PermissionsConfiguration{U.NewTaskEditor{}})}] : +List<V.ComposerControl>},
    model_label: @fallback:String -> {View.profile_label(None{}, fallback) == "Choose model" : String}
  }

law composition_evidence:
  CompositionRequirements

type DirectoryEntryRequirements is Type:
  DirectoryEntryRequirements{
    typing: @+revision:Nat -> @+body:U.Body -> @feedback:U.Feedback -> @old:String -> @+path:String -> @world:M.World() ->
      {U.edit_draft(U.WriteDirectory{path}, U.Draft{revision, body, feedback, old}, world) == Done{U.Draft{(revision + 1n : Nat), body, U.Editing{}, path}} : Result<&2, &2, String, U.Draft>},
    literal_entry: @revision:Nat -> @body:U.Body -> @feedback:U.Feedback -> @+path:String ->
      {Model.draft_directory(Some{U.Draft{revision, body, feedback, path}}) == path : String},
    browse_primary: @roots:+List<String> -> @+path:String ->
      {Model.browse_workspace(Some{D.Workspace{roots, Some{path}}}) == path : String},
    browse_no_primary: @roots:+List<String> ->
      {Model.browse_workspace(Some{D.Workspace{roots, None{}}}) == "" : String},
    browse_unobserved: {Model.browse_workspace(None{}) == "" : String},
    confirmed: @+revision:Nat -> @+body:U.Body -> @feedback:U.Feedback -> @+path:String -> @+world:M.World() ->
      @admitted:{U.can_confirm_directory(U.Draft{revision, body, feedback, path}) == True{} : Bool} ->
      {U.edit_draft(U.ConfirmDirectory{}, U.Draft{revision, body, feedback, path}, world) == U.edited_body(U.apply_edit(U.EditWorkspace{Context.AddRoot{path}}, body, world), revision, "") : Result<&2, &2, String, U.Draft>},
    unconfirmed: @+draft:U.Draft -> @+world:M.World() -> @denied:{U.can_confirm_directory(draft) == False{} : Bool} ->
      {U.edit_draft(U.ConfirmDirectory{}, draft, world) == Done{draft} : Result<&2, &2, String, U.Draft>},
    model_entry: @revision:Nat -> @+text:U.Text -> @old_profile:String -> @old_reasoning:String -> @+context:Context.Configuration -> @feedback:U.Feedback -> @+entry:String -> @+profile:String -> @+reasoning:String -> @world:M.World() ->
      {U.edit_draft(U.ChooseModel{profile, reasoning}, U.Draft{revision, U.NewTask{text, old_profile, old_reasoning, context}, feedback, entry}, world) == Done{U.Draft{(revision + 1n : Nat), U.NewTask{text, profile, reasoning, context}, U.Editing{}, entry}} : Result<&2, &2, String, U.Draft>},
    project_entry: @revision:Nat -> @+text:U.Text -> @+profile:String -> @+reasoning:String -> @+context:Context.Configuration -> @feedback:U.Feedback -> @+entry:String -> @+origin:Context.Origin -> @world:M.World() ->
      {U.edit_draft(U.ConfigureContext{Context.ChooseOrigin{origin}}, U.Draft{revision, U.NewTask{text, profile, reasoning, context}, feedback, entry}, world) ==
        Done{U.Draft{(revision + 1n : Nat), U.NewTask{text, profile, reasoning, Context.edit(context, Context.ChooseOrigin{origin})}, U.Editing{}, entry}} : Result<&2, &2, String, U.Draft>},
    empty_entry: @revision:Nat -> @body:U.Body -> @feedback:U.Feedback -> @+world:M.World() -> @+session:E.Session ->
      {E.edit_existing(U.ConfirmDirectory{}, U.Draft{revision, body, feedback, ""}, world, session) == E.unchanged(E.from_program(world, session)) : E.Decision},
    unsupported_entry: @revision:Nat -> @+body:U.Body -> @feedback:U.Feedback -> @+entry:String -> @+world:M.World() -> @+session:E.Session -> @unsupported:{U.workspace_capable(body) == False{} : Bool} ->
      {E.edit_existing(U.ConfirmDirectory{}, U.Draft{revision, body, feedback, entry}, world, session) == E.unchanged(E.from_program(world, session)) : E.Decision},
    selected_project_entry: @+revision:Nat -> @+text:U.Text -> @+profile:String -> @+reasoning:String -> @+context:Context.Configuration -> @feedback:U.Feedback -> @+entry:String -> @+origin:Context.Origin -> @+world:M.World() -> @+session:E.Session ->
      {E.begin_existing(Some{U.Draft{revision, U.NewTask{text, profile, reasoning, context}, feedback, entry}}, origin, E.from_program(world, session)) ==
        E.navigate_with_attention(U.Start{}, "composer/" ++ U.editor_key(U.NewTaskEditor{}), E.from_program(world, E.with_draft(session, U.Draft{(revision + 1n : Nat), U.NewTask{text, profile, reasoning, Context.edit(context, Context.ChooseOrigin{origin})}, U.Editing{}, entry}))) : E.Decision},
    production_noop: @+draft:U.Draft -> @+world:M.World() -> @+session:E.Session -> @denied:{U.can_confirm_directory(draft) == False{} : Bool} ->
      {E.edit_existing(U.ConfirmDirectory{}, draft, world, session) == E.unchanged(E.from_program(world, session)) : E.Decision},
    input_binding: @+editor:U.Editor -> @text:String -> @+path:String ->
      {Model.bind(SurfaceTypes.EnterDirectory{editor, text}, SurfaceTypes.Directory{path}) == Some{InteractionTypes.ApplicationInput{E.UserInput{U.EditDraft{editor, U.WriteDirectory{path}}}}} : Maybe<&2, InteractionTypes.Input>},
    button_declaration: @+editor:U.Editor -> @+parent: Identity.Key -> @+state:InteractionTypes.State ->
      {Model.directory_confirm(editor, parent, state) == Model.declared(parent, V.ControlDeclaration{"workspace/confirm", "Add folder", V.Secondary{}, U.EditDraft{editor, U.ConfirmDirectory{}}, Model.availability(Model.directory_ready(state, editor))}, state) : SurfaceTypes.Node},
    button_activation: @+editor:U.Editor ->
      {Model.bind(SurfaceTypes.Activate{InteractionTypes.ApplicationInput{E.UserInput{U.EditDraft{editor, U.ConfirmDirectory{}}}}, V.Available{}}, SurfaceTypes.Press{}) == Some{InteractionTypes.ApplicationInput{E.UserInput{U.EditDraft{editor, U.ConfirmDirectory{}}}}} : Maybe<&2, InteractionTypes.Input>},
    confirm_binding: @+editor:U.Editor -> @text:String ->
      {Model.bind(SurfaceTypes.EnterDirectory{editor, text}, SurfaceTypes.ConfirmDirectory{}) == Some{InteractionTypes.ApplicationInput{E.UserInput{U.EditDraft{editor, U.ConfirmDirectory{}}}}} : Maybe<&2, InteractionTypes.Input>}
  }

law directory_entry_evidence:
  DirectoryEntryRequirements

type DirectoryPickerRequirements is Type:
  DirectoryPickerRequirements{
    closed: @+state:Services.State -> {Services.step(Services.CloseDirectoryPicker{}, state) == Services.Decision{Services.replace_directory(state, Services.NoDirectoryPicker{}), Nil{}} : Services.Decision},
    closed_completion: @+ticket:Nat -> @+result:Result<&2, &2, String, Services.DirectoryCatalog> -> @+state:Services.State -> {Services.directory_listed(Services.NoDirectoryPicker{}, ticket, result, state) == Services.Decision{state, Nil{}} : Services.Decision},
    stale: @+current:Nat -> @editor:U.Editor -> @path:String -> @trigger:String -> @+ticket:Nat -> @+result:Result<&2, &2, String, Services.DirectoryCatalog> -> @+state:Services.State -> @stale:{Nat.is_eq(current, ticket) == False{} : Bool} -> {Services.directory_listed(Services.LoadingDirectory{current, editor, path, trigger}, ticket, result, state) == Services.Decision{state, Nil{}} : Services.Decision},
    owned: @ticket:Nat -> @+editor:U.Editor -> @entered:String -> @+trigger:String -> @+path:String -> @+parent:Maybe<&2, String> -> @+entries:+List<Services.DirectoryEntry> -> @+truncated:Bool -> @+state:Services.State -> {Services.finish_directory(True{}, ticket, editor, entered, trigger, Done{Services.DirectoryCatalog{path, parent, entries, truncated}}, state) ==
        Services.Decision{Services.replace_directory(state, Services.ReadyDirectory{ticket, editor, Services.DirectoryCatalog{path, parent, entries, truncated}, path, trigger}), Nil{}} : Services.Decision},
    selected_catalog: @ticket:Nat -> @+editor:U.Editor -> @+path:String -> @parent:Maybe<&2, String> -> @entries:+List<Services.DirectoryEntry> -> @truncated:Bool -> @location:String -> @trigger:String -> @+state:Services.State -> {Services.choose_directory(Services.ReadyDirectory{ticket, editor, Services.DirectoryCatalog{path, parent, entries, truncated}, location, trigger}, state) ==
        Services.Decision{Services.replace_directory(state, Services.NoDirectoryPicker{}), [Services.DirectoryChosen{editor, path}]} : Services.Decision},
    internal: @editor:U.Editor -> @path:String -> {Core.external_effect(Services.DirectoryChosen{editor, path}) == False{} : Bool},
    bridge: @+editor:U.Editor -> @+path:String -> @+application:E.Application -> @rest:+List<Services.Effect> -> {Core.service_effects(Services.DirectoryChosen{editor, path} <> rest, application) == Core.service_effects(rest, Core.directory_chosen(editor, path, application)) : E.Application},
    unavailable: @+editor:U.Editor -> @path:String -> @+application:E.Application -> @unavailable:{Core.accepts_directory(editor, application) == False{} : Bool} -> {Core.directory_chosen(editor, path, application) == application : E.Application},
    draft: @+editor:U.Editor -> @+path:String -> @+application:E.Application -> @accepted:{Core.accepts_directory(editor, application) == True{} : Bool} -> {Core.directory_chosen(editor, path, application) == Core.attached(ExperienceProgram.step(E.UserInput{U.EditDraft{editor, U.ConfirmDirectory{}}}, Core.attached(ExperienceProgram.step(E.UserInput{U.EditDraft{editor, U.WriteDirectory{path}}}, application)))) : E.Application}}

law directory_picker_requirements:
  DirectoryPickerRequirements

def spatial_identity(node: SurfaceTypes.Node) -> Identity.Key:
  SurfaceTypes.Node{key, semantic, label, role, meaning, children} = node
  key

def first_spatial_identity(nodes: +List<SurfaceTypes.Node>) -> Identity.Key:
  match nodes:
    case Nil{}: Identity.Place{""}
    case Con{node, rest}: spatial_identity(node)

type DirectoryIdentityRequirements is Type:
  DirectoryIdentityRequirements{
    row: @+path:String -> @primary:Bool -> @choose:V.ControlDeclaration -> @remove:V.ControlDeclaration -> @+parent:Identity.Key -> @state:InteractionTypes.State ->
      {spatial_identity(Model.directory_node(V.WorkspaceRoot{path, primary, choose, remove}, parent, state)) == Identity.Entity{parent, "directory", path} : Identity.Key},
    primary: @+path:String -> @control:V.ControlDeclaration -> @+parent:Identity.Key -> @state:InteractionTypes.State ->
      {first_spatial_identity(Model.directory_primary_controls(True{}, control, Identity.Entity{parent, "directory", path}, state)) == Identity.Part{Identity.Entity{parent, "directory", path}, "primary"} : Identity.Key},
    slot_not_directory: @path:String -> @primary:Bool -> @choose:V.ControlDeclaration -> @remove:V.ControlDeclaration -> @+parent:Identity.Key -> @state:InteractionTypes.State -> @other:String -> @name:String ->
      {Identity.same(Identity.Part{spatial_identity(Model.directory_node(V.WorkspaceRoot{path, primary, choose, remove}, parent, state)), name}, Identity.Entity{parent, "directory", other}) == False{} : Bool},
    directory_not_slot: @path:String -> @primary:Bool -> @choose:V.ControlDeclaration -> @remove:V.ControlDeclaration -> @+parent:Identity.Key -> @state:InteractionTypes.State -> @other:String -> @name:String ->
      {Identity.same(Identity.Entity{parent, "directory", other}, Identity.Part{spatial_identity(Model.directory_node(V.WorkspaceRoot{path, primary, choose, remove}, parent, state)), name}) == False{} : Bool}}

law directory_identity_requirements:
  DirectoryIdentityRequirements

law directory_ready_regions:
  for ticket: Nat
  for editor: U.Editor
  for path: String
  for parent: Maybe<&2, String>
  for +entries: +List<Services.DirectoryEntry>
  for truncated: Bool
  for location: String
  for trigger: String
  {Model.directory_ready_content(Services.ReadyDirectory{ticket, editor, Services.DirectoryCatalog{path, parent, entries, truncated}, location, trigger}) ==
    [Model.region(Identity.Place{"/layers/directory-picker"}, "folders", "Folders", SurfaceTypes.Section{},
       List.append(&2, SurfaceTypes.Node, Model.directory_entries(entries), Model.directory_truncated(truncated))),
     Model.dialog_actions(Identity.Place{"/layers/directory-picker"}, [SurfaceTypes.Node{Identity.Part{Identity.Place{"/layers/directory-picker"}, "use"}, "directory-picker/use", "Use this folder", SurfaceTypes.PrimaryButton{},
       SurfaceTypes.Activate{InteractionTypes.ServiceInput{Services.ChooseDirectory{}}, V.Available{}}, Nil{}}])] : +List<SurfaceTypes.Node>}

law directory_location_navigation_regions:
  for ticket: Nat
  for editor: U.Editor
  for path: String
  for parent: Maybe<&2, String>
  for entries: +List<Services.DirectoryEntry>
  for truncated: Bool
  for location: String
  for trigger: String
  {Model.directory_picker_content(Services.ReadyDirectory{ticket, editor, Services.DirectoryCatalog{path, parent, entries, truncated}, location, trigger}) ==
    [SurfaceTypes.Node{Identity.Part{Identity.Place{"/layers/directory-picker"}, "location"}, "directory-picker/location", "Folder path", SurfaceTypes.Field{}, SurfaceTypes.DirectoryBrowserLocation{location}, Nil{}},
     Model.region(Identity.Place{"/layers/directory-picker"}, "navigation", "Folder navigation", SurfaceTypes.Toolbar{},
       List.append(&2, SurfaceTypes.Node, [Model.product_action(Identity.Place{"/layers/directory-picker"}, "go", "Go", InteractionTypes.ServiceInput{Services.GoDirectory{}}, True{})], Model.directory_parent(parent)))] : +List<SurfaceTypes.Node>}

def disclosure(state: E.NavigationState) -> +List<Nat>:
  E.NavigationState{intent, collapsed} = state
  collapsed

def intro_chooser(value: V.CreationIntroduction) -> V.ControlDeclaration:
  V.CreationIntroduction{heading, summary, context, project, chooser} = value
  chooser

def picker_nodes(+values: +List<V.ProjectChoice>, +selected: Maybe<&2, Nat>, +parent: Identity.Key, +state: InteractionTypes.State) -> Type:
  {Model.project_choice_nodes(values, selected, parent, state) ==
    [SurfaceTypes.Node{Identity.Part{parent, "choices"}, "project/choices", "Projects", SurfaceTypes.Section{}, SurfaceTypes.ChoiceGroup{},
      Model.project_picker_choice(View.control("project/select/none", "No project", U.SelectProject{None{}}), View.same_project(selected, None{}), "Use environment defaults", parent, state) <>
        Model.project_registered_choices(values, selected, parent, state)},
     Model.declared(parent, View.control("project/create", "New project", U.EditProject{None{}}), state)] : +List<SurfaceTypes.Node>}

type ProjectInteractionRequirements is Type:
  ProjectInteractionRequirements{
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
      {List.length(&2, V.ProjectChoice, View.project_choices(entries)) == List.length(&2, Finite.Entry(D.Project), entries) : Nat},
    picker_filter_keeps_selection: @+query:String -> @+selected:Maybe<&2, Nat> -> @+projects:+List<V.ProjectChoice> ->
      {View.search_content(V.ProjectSelection{"", selected, projects}, query) ==
    V.ProjectSelection{query, selected, View.matching_projects(projects, query)} : V.LayerContent},
    project_actions: @+id:Nat -> @+name:String -> @+workspace:D.Workspace -> @guidance:D.ProjectContext -> @+tasks:+List<D.Task> -> @+route:U.Route -> @+selected:Maybe<&2, Nat> -> @+navigation:E.NavigationState ->
      {View.project_entry(id, D.Project{name, workspace, guidance}, tasks, route, selected, navigation) ==
        V.ProjectEntry{id, name, workspace, View.selected_project(selected, id), Bool.not(E.project_collapsed(navigation, id)), View.task_entries(View.project_tasks(tasks, Some{id}), route),
          View.control("project/" ++ Nat.show(id), name, U.SelectProject{Some{id}}), View.control("project/new-task/" ++ Nat.show(id), "New task", U.BeginTask{Some{id}}),
          View.control("project/toggle/" ++ Nat.show(id), "Toggle project tasks", U.ToggleProjectGroup{id}),
          View.context_control("project/more/" ++ Nat.show(id), "More", U.ObjectActions{U.ProjectSubject{id}})} : V.ProjectEntry},
    details_entry: @+id:Nat -> @+now:U32 -> @+world:M.World() ->
      {View.subject_controls(U.ProjectSubject{id}, now, world) ==
        [View.control("project/details/" ++ Nat.show(id), "Project details", U.Navigate{U.ProjectHome{id}}),
         View.control("project/edit/" ++ Nat.show(id), "Edit project", U.EditProject{Some{id}}),
         View.native("project/delete/" ++ Nat.show(id), "Delete project", V.Destructive{}, U.DeleteProject{id}, world)] : +List<V.ControlDeclaration>},
    chooser_single_name: @+id:Nat -> @+name:String -> @+workspace:D.Workspace ->
      {(View.creation_heading(Some{V.ProjectChoice{id, name, workspace}}), View.project_choice_label(Some{V.ProjectChoice{id, name, workspace}})) ==
    ("Work on", name) : Sigma<&2, &2, String, (_ => String)>},
    task_status_visible: @+id:Nat -> @title:String -> @+status:V.TaskStatus -> @+selected:Bool -> @+open:V.ControlDeclaration -> @+parent: Identity.Key -> @+state:InteractionTypes.State ->
      {Model.task_entries([V.TaskEntry{id, title, status, selected, open}], parent, state) ==
        [SurfaceTypes.Node{Identity.Entity{parent, "task", Nat.show(id)}, "task-row", "", SurfaceTypes.Section{}, SurfaceTypes.TaskRow{id, status, selected},
          [Model.selected_node(selected, Model.declared(Identity.Entity{parent, "task", Nat.show(id)}, open, state)),
           SurfaceTypes.Node{Identity.Part{Identity.Entity{parent, "task", Nat.show(id)}, "status"}, "task-status", "Task status", SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{View.task_status_label(status)}, Nil{}}]}] : +List<SurfaceTypes.Node>},
    deletion_retains_other: @+prefix:+List<Nat> -> @+other:Nat -> @+suffix:+List<Nat> -> @+id:Nat -> @distinct:{Nat.is_eq(id, other) == False{} : Bool} ->
      {List.contains(~Nat, ~Nat.is_eq, E.without_collapsed_project(List.append(&2, Nat, prefix, other <> suffix), id), other) == True{} : Bool},
    toggle_retains_other: @+intent:E.NavigationIntent -> @+prefix:+List<Nat> -> @+other:Nat -> @+suffix:+List<Nat> -> @+id:Nat -> @distinct:{Nat.is_eq(id, other) == False{} : Bool} ->
      {E.project_collapsed(E.toggle_project_navigation(id, E.NavigationState{intent, List.append(&2, Nat, prefix, other <> suffix)}), other) == True{} : Bool},
    toggle_preserves_visibility: @+id:Nat -> @+intent:E.NavigationIntent -> @collapsed:+List<Nat> ->
      {E.navigation_visibility(E.toggle_project_navigation(id, E.NavigationState{intent, collapsed})) == intent : E.NavigationIntent},
    picker_complete_nodes: @+values:+List<V.ProjectChoice> -> @+selected:Maybe<&2, Nat> -> @+parent:Identity.Key -> @+state:InteractionTypes.State -> picker_nodes(values, selected, parent, state),
    chooser_activation: @+context:Maybe<&2, Context.Preview> -> @+world:M.World() ->
      {intro_chooser(View.creation_introduction_fields(context, world)) ==
        V.ControlDeclaration{"composer/project", View.project_choice_label(View.creation_selected_project(context, world)), V.Secondary{},
          U.Activate{U.OpenPanel{U.ProjectPicker{}, "composer/project"}}, V.Available{}} : V.ControlDeclaration},
    picker_search_preserves_session: @+session:E.Session -> @+query:String -> @+world:M.World() -> @+trigger:String -> @+initial:String -> @previous:String -> @+layer_occurrence:Nat -> @+rest:+List<E.Layer> ->
      @observed_layers:{E.layers(session) == E.Layer{U.ProjectPicker{}, trigger, initial, previous, layer_occurrence} <> rest : +List<E.Layer>} ->
       {E.search_choices(query, E.from_program(world, session)) ==
        E.local(world, E.with_layers(E.Layer{U.ProjectPicker{}, trigger, initial, query, layer_occurrence} <> rest, session), Nil{}) : E.Decision},
    project_group_single_title: @+id:Nat -> @name:String -> @workspace:D.Workspace -> @+selected:Bool -> @+expanded:Bool -> @+tasks:+List<V.TaskEntry> -> @+open:V.ControlDeclaration -> @+create:V.ControlDeclaration -> @+toggle:V.ControlDeclaration -> @+more:V.ControlDeclaration -> @+parent: Identity.Key -> @+state:InteractionTypes.State ->
      {Model.project_entries([V.ProjectEntry{id, name, workspace, selected, expanded, tasks, open, create, toggle, more}], parent, state) ==
        [SurfaceTypes.Node{Identity.Entity{parent, "project", Nat.show(id)}, "project-group", "", SurfaceTypes.Section{}, SurfaceTypes.ProjectGroup{id, selected, expanded},
          Model.region(Identity.Entity{parent, "project", Nat.show(id)}, "actions", "", SurfaceTypes.Section{},
            [Model.declared(Identity.Entity{parent, "project", Nat.show(id)}, toggle, state), Model.selected_node(selected, Model.declared(Identity.Entity{parent, "project", Nat.show(id)}, open, state)),
             Model.declared(Identity.Entity{parent, "project", Nat.show(id)}, create, state), Model.declared(Identity.Entity{parent, "project", Nat.show(id)}, more, state)]) <>
          Model.disclosed_tasks(expanded, tasks, Identity.Entity{parent, "project", Nat.show(id)}, state)}] : +List<SurfaceTypes.Node>},
    committed_is_not_draft: @context:Context.EffectiveContext ->
      {View.draft_preview(Some{Context.CommittedExecution{context}}) == None{} : Maybe<&2, Context.Preview>},
    empty_project_collection: @+parent: Identity.Key -> @state:InteractionTypes.State ->
      {Model.project_collection_entries(Nil{}, parent, state) ==
        [SurfaceTypes.Node{Identity.Part{Identity.Part{parent, "projects"}, "empty"}, "projects/empty", "", SurfaceTypes.Content{},
          SurfaceTypes.ReadOnly{"Create a project to group tasks and choose default working folders."}, Nil{}}] : +List<SurfaceTypes.Node>},
    populated_project_collection: @+first:V.ProjectScene -> @+rest:+List<V.ProjectScene> -> @+parent: Identity.Key -> @+state:InteractionTypes.State ->
      {Model.project_collection_entries(Con{first, rest}, parent, state) ==
    Model.projects(Con{first, rest}, parent, state) : +List<SurfaceTypes.Node>},
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
    task_status_source: @+task:D.Task -> {View.task_status(task) == V.TaskStatus{D.task_status(task), Conversation2.working(D.task_phase(task), D.task_operations(task))} : V.TaskStatus},
    task_status_label: @+lifecycle:D.Status -> @+working:Bool -> {View.task_status_label(V.TaskStatus{lifecycle, working}) == Conversation2.status_label(lifecycle, working) : String},
    task_status_caption: @+task:D.Task -> {View.task_status_label(View.task_status(task)) == Conversation2.status(task) : String}}

law project_interaction_evidence:
  ProjectInteractionRequirements

def opening(scene: V.CardScene) -> U.Input:
  V.CardScene{id, value, V.ControlDeclaration{identity, label, prominence, input, availability}, actions, linked, destinations, candidates} = scene
  input

type BoardCapabilityRequirements is Type:
  BoardCapabilityRequirements{
    card_opens_details: @+id: Nat -> @card: B.Card -> @route: U.Route -> @now: U32 -> @world: M.World() ->
      {opening(View.card_scene(id, card, route, now, world)) ==
    U.Activate{U.OpenPanel{U.CardDetails{id}, "card/" ++ Nat.show(id)}} : U.Input},
    working_keeps_facets: @+view: String -> @+search: String -> @+status: +List<String> -> @+priority: +List<String> -> @+date: +List<String> -> @+assignee: +List<String> -> @+creator: +List<String> -> @+project: +List<String> -> @+labels: +List<String> -> @+parent: Identity.Key -> @+state: InteractionTypes.State ->
      {Model.view_choice("working", "工作中", B.Filter{view, search, status, priority, date, assignee, creator, project, labels}, parent, state) ==
       Model.selected_node(String.eq(view, "working"), Model.declared(parent,
         V.ControlDeclaration{"view/working", "工作中", V.Secondary{},
           U.FilterBoard{B.Filter{"working", search, status, priority, date, assignee, creator, project, labels}}, V.Available{}}, state)) : SurfaceTypes.Node},
    linked_conversation_control: @+id: Nat -> @+title: String -> @+status: V.TaskStatus -> @+selected: Bool -> @+open: V.ControlDeclaration -> @+parent: Identity.Key -> @+state: InteractionTypes.State ->
      {Model.linked_card_controls(Some{V.TaskEntry{id, title, status, selected, open}}, parent, state) ==
    [Model.declared(parent, open, state)] : +List<SurfaceTypes.Node>},
    unlinked_has_no_conversation: @parent: Identity.Key -> @state: InteractionTypes.State ->
      {Model.linked_card_controls(None{}, parent, state) == Nil{} : +List<SurfaceTypes.Node>},
    failed_generation_is_observed: @+reason: String ->
      {Model.enrichment_observation(B.EnrichmentFailed{reason}) == reason : String},
    actual_card_errors: @+card:B.Card -> @+parent: Identity.Key ->
      {Model.card_error_observations(card, parent) ==
        [Model.project_fact(Identity.Part{parent, "enrichment"}, "生成", Model.enrichment_observation(B.enrichment(card))),
         Model.project_fact(Identity.Part{parent, "start-error"}, "启动错误", B.start_error(card))] : +List<SurfaceTypes.Node>},
    missing_card_is_unavailable: @+parent: Identity.Key -> @state: InteractionTypes.State ->
      {Model.card_details_nodes(None{}, parent, state) ==
    [Model.project_fact(Identity.Part{parent, "missing"}, "Unavailable", "The card no longer exists")] : +List<SurfaceTypes.Node>},
    archived_has_no_archive_drop: @id: Nat -> @revision: Nat -> @state: InteractionTypes.State ->
      {Model.archive_placement(True{}, id, revision, state) == Nil{} : +List<SurfaceTypes.Placement>},
    agent_row_observes_profile: @+agent:B.AgentProfile -> @+id: Nat -> @+edit: V.ControlDeclaration -> @+parent: Identity.Key -> @+world: M.World() -> @+session: E.Session -> @+services: Services.State ->
      {Model.agent_observation(id, agent, edit, parent, Core.from_application(E.from_program(world, session), services)) ==
        SurfaceTypes.Node{Identity.Entity{parent, "agent", Nat.show(id)}, "agent/" ++ Nat.show(id), B.agent_name(agent), SurfaceTypes.Section{}, SurfaceTypes.Region{}, [Model.project_fact(Identity.Part{Identity.Entity{parent, "agent", Nat.show(id)}, "profile"}, "模型", B.agent_profile(agent)),
           Model.project_fact(Identity.Part{Identity.Entity{parent, "agent", Nat.show(id)}, "reasoning"}, "推理", B.agent_reasoning(agent)),
           Model.project_fact(Identity.Part{Identity.Entity{parent, "agent", Nat.show(id)}, "instructions"}, "指令", B.agent_instructions(agent)),
           Model.project_fact(Identity.Part{Identity.Entity{parent, "agent", Nat.show(id)}, "concurrency"}, "并发上限", Nat.show(B.agent_concurrency(agent))),
           Model.project_fact(Identity.Part{Identity.Entity{parent, "agent", Nat.show(id)}, "active"}, "工作中", Nat.show(Board.active_for(B.cards(Board.registry(world)), B.Agent{id}, world))),
           Model.declared(Identity.Entity{parent, "agent", Nat.show(id)}, edit, Core.from_application(E.from_program(world, session), services)),
           Model.more(U.AgentSubject{id}, Identity.Entity{parent, "agent", Nat.show(id)}, Core.from_application(E.from_program(world, session), services))]} : SurfaceTypes.Node}}

law board_capability_evidence:
  BoardCapabilityRequirements

type Receipt is Data:
  Receipt{runtime: M.Decision(), services: Services.State,
    interaction: +List<E.Effect>, service_effects: +List<Services.Effect>, durable: Bool}

def receipt(+decision: InteractionTypes.Decision) -> Receipt:
  InteractionTypes.Decision{+observed_state, reply, runtime, interaction, service_effects, durable} = decision
  services = Core.services(observed_state)
  Receipt{Core.runtime(decision), services, interaction, service_effects, durable}

def quiet_decision(+state: InteractionTypes.State) -> InteractionTypes.Decision:
  application = Core.application(state)
  services = Core.services(state)
  InteractionTypes.Decision{Core.from_application(application, services), D.success(J.Null{}), Nil{}, Nil{}, Nil{}, False{}}

type SurfaceRequirements is Type:
  SurfaceRequirements{
    absent_element: @capacity:V.Capacity -> @+state:InteractionTypes.State -> @key:String -> @gesture:SurfaceTypes.Gesture ->
      @absent:{Model.find_node(Model.active_nodes(ModelModel.observe(capacity, state)), key) == None{} : Maybe<&2, SurfaceTypes.Node>} ->
      {ModelModel.step(ModelModel.Element{capacity, key, gesture}, state) == quiet_decision(state) : InteractionTypes.Decision},
    disabled_element: @capacity:V.Capacity -> @+state:InteractionTypes.State -> @key:String -> @+input:InteractionTypes.Input ->
      @reason:String -> @node_key: Identity.Key -> @semantic:String -> @label:String -> @role:SurfaceTypes.Role -> @+children:+List<SurfaceTypes.Node> ->
      @found:{Model.find_node(Model.active_nodes(ModelModel.observe(capacity, state)), key) ==
        Some{SurfaceTypes.Node{node_key, semantic, label, role, SurfaceTypes.Activate{input, V.Unavailable{reason}}, children}} : Maybe<&2, SurfaceTypes.Node>} ->
      {ModelModel.step(ModelModel.Element{capacity, key, SurfaceTypes.Press{}}, state) == quiet_decision(state) : InteractionTypes.Decision},
    absent_composer: @capacity:V.Capacity -> @+state:InteractionTypes.State -> @editor:U.Editor ->
      @absent:{Model.submission(Model.active_nodes(ModelModel.observe(capacity, state)), editor) == None{} : Maybe<&2, SurfaceTypes.Node>} ->
      {ModelModel.step(ModelModel.SubmitComposer{capacity, editor}, state) == quiet_decision(state) : InteractionTypes.Decision},
    element_receipt: @capacity:V.Capacity -> @+state:InteractionTypes.State -> @key:String -> @gesture:SurfaceTypes.Gesture ->
      {receipt(ModelModel.step(ModelModel.Element{capacity, key, gesture}, state)) ==
        receipt(Model.apply_input(Model.resolve(ModelModel.observe(capacity, state), key, gesture), state)) : Receipt},
    available_element: @capacity:V.Capacity -> @+state:InteractionTypes.State -> @key:String -> @+input:InteractionTypes.Input ->
      @node_key: Identity.Key -> @semantic:String -> @label:String -> @role:SurfaceTypes.Role -> @+children:+List<SurfaceTypes.Node> ->
      @found:{Model.find_node(Model.active_nodes(ModelModel.observe(capacity, state)), key) ==
        Some{SurfaceTypes.Node{node_key, semantic, label, role, SurfaceTypes.Activate{input, V.Available{}}, children}} : Maybe<&2, SurfaceTypes.Node>} ->
      {receipt(ModelModel.step(ModelModel.Element{capacity, key, SurfaceTypes.Press{}}, state)) == receipt(Core.step(input, state)) : Receipt},
    existing_layer_trigger: @+previous:+List<E.Layer> -> @origin:String -> @+panel:U.Panel -> @trigger:String ->
      @initial_attention:String -> @query:String -> @+layer_occurrence:Nat -> @+rest:+List<E.Layer> ->
      @present:{Model.layer_present(previous, E.panel_target(panel)) == True{} : Bool} ->
      {Model.record_layer(E.Layer{panel, trigger, initial_attention, query, layer_occurrence} <> rest, previous, origin) ==
        E.Layer{panel, trigger, initial_attention, query, layer_occurrence} <> rest : +List<E.Layer>},
    new_layer_trigger: @+previous:+List<E.Layer> -> @origin:String -> @+panel:U.Panel -> @trigger:String ->
      @initial_attention:String -> @query:String -> @+layer_occurrence:Nat -> @+rest:+List<E.Layer> ->
      @absent:{Model.layer_present(previous, E.panel_target(panel)) == False{} : Bool} ->
      {Model.record_layer(E.Layer{panel, trigger, initial_attention, query, layer_occurrence} <> rest, previous, origin) ==
        E.Layer{panel, origin, initial_attention, query, layer_occurrence} <> rest : +List<E.Layer>}}

law surface_evidence:
  SurfaceRequirements

law composer_tree_present_agreement:
  for +identity: U.Editor
  for revision: Nat
  for message: U.Text
  for footer: +List<V.ComposerControl>
  for context: Maybe<&2, Context.Observation>
  for submit: V.ControlDeclaration
  for feedback: U.Feedback
  for pending: Bool
  for +parent: Identity.Key
  for +state: InteractionTypes.State
  {Model.composer(Some{V.ComposerScene{identity, revision, message, footer, context, submit, feedback, pending}}, parent, state) ==
      Model.expected_composer(Some{V.ComposerScene{identity, revision, message, footer, context, submit, feedback, pending}}, parent, state) : +List<SurfaceTypes.Node>}

law composer_tree_agreement:
  for view: Maybe<&2, V.ComposerScene>
  for +parent: Identity.Key
  for +state: InteractionTypes.State
  {Model.composer(view, parent, state) == Model.expected_composer(view, parent, state) : +List<SurfaceTypes.Node>}

law relocated_valid_content:
  for valid: Bool
  for +node: SurfaceTypes.Node
  for +scene: InteractionTypes.Scene
  for +base: +List<SurfaceTypes.Node>
  for +overlays: +List<SurfaceTypes.Node>
  {Model.content(Model.relocate_valid_trigger(valid, node, scene, base, overlays)) == scene : InteractionTypes.Scene}

law relocated_found_content:
  for found: Maybe<&2, SurfaceTypes.Node>
  for +target: Nat
  for +scene: InteractionTypes.Scene
  for +base: +List<SurfaceTypes.Node>
  for +overlays: +List<SurfaceTypes.Node>
  {Model.content(Model.relocate_found_trigger(found, target, scene, base, overlays)) == scene : InteractionTypes.Scene}

law relocated_key_content:
  for found: Maybe<&2, String>
  for +target: Nat
  for +scene: InteractionTypes.Scene
  for +base: +List<SurfaceTypes.Node>
  for +overlays: +List<SurfaceTypes.Node>
  {Model.content(Model.relocate_trigger_key(found, target, scene, base, overlays)) == scene : InteractionTypes.Scene}

law relocated_content:
  for trigger: Maybe<&2, SurfaceTypes.PersistentTrigger>
  for +scene: InteractionTypes.Scene
  for +base: +List<SurfaceTypes.Node>
  for +overlays: +List<SurfaceTypes.Node>
  {Model.content(Model.relocate_persistent_trigger(trigger, scene, base, overlays)) == scene : InteractionTypes.Scene}

law assembled_content:
  for +scene: InteractionTypes.Scene
  for +state: InteractionTypes.State
  {Model.content(Model.assemble(scene, state)) == scene : InteractionTypes.Scene}

law placement_destination_authority:
  for +key: Identity.Key
  for +semantic: String
  for +label: String
  for +role: SurfaceTypes.Role
  for +destinations: +List<SurfaceTypes.Placement>
  for +face: V.CardFace
  for +children: +List<SurfaceTypes.Node>
  for +target: String
  for +surface: SurfaceTypes.Surface
  {Model.resolve_present(SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.MovableCard{destinations, face}, children}, SurfaceTypes.Place{target}, surface) == Model.placement_input(destinations, target) : Maybe<&2, InteractionTypes.Input>}

law placement_filtered_destination_accepted:
  for +key: Identity.Key
  for +semantic: String
  for +label: String
  for +role: SurfaceTypes.Role
  for +destinations: +List<SurfaceTypes.Placement>
  for +face: V.CardFace
  for +children: +List<SurfaceTypes.Node>
  for +target: String
  for +surface: SurfaceTypes.Surface
  for +input: InteractionTypes.Input
  for hidden: {Model.find_node(Model.active_nodes(surface), target) == None{} : Maybe<&2, SurfaceTypes.Node>}
  for accepted: {Model.placement_input(destinations, target) == Some{input} : Maybe<&2, InteractionTypes.Input>}
  {Model.resolve_present(SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.MovableCard{destinations, face}, children}, SurfaceTypes.Place{target}, surface) == Some{input} : Maybe<&2, InteractionTypes.Input>}

law placement_rejected_destination:
  for +key: Identity.Key
  for +semantic: String
  for +label: String
  for +role: SurfaceTypes.Role
  for +destinations: +List<SurfaceTypes.Placement>
  for +face: V.CardFace
  for +children: +List<SurfaceTypes.Node>
  for +target: String
  for +surface: SurfaceTypes.Surface
  for rejected: {Model.placement_input(destinations, target) == None{} : Maybe<&2, InteractionTypes.Input>}
  {Model.resolve_present(SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.MovableCard{destinations, face}, children}, SurfaceTypes.Place{target}, surface) == None{} : Maybe<&2, InteractionTypes.Input>}

law fixed_reasoning_catalogue_entry:
  for key: String
  for provider: String
  for name: String
  for options: D.ReasoningOptions
  {Model.profile_effort_entry(D.Profile{key, provider, name, Reasoning.Fixed{}, Some{options}}) == Forms.Choice{} : Forms.Entry}

law fixed_reasoning_open_entry:
  for key: String
  for provider: String
  for name: String
  {Model.profile_effort_entry(D.Profile{key, provider, name, Reasoning.Fixed{}, None{}}) == Forms.SingleLine{} : Forms.Entry}

law retained_profile_effort:
  for +profile: D.Profile
  for +previous: String
  for permitted: {D.profile_permitted(profile, previous) == True{} : Bool}
  {Forms.selected_profile_effort(D.profile_permitted(profile, previous), previous, profile) == previous : String}

law reset_profile_effort:
  for +profile: D.Profile
  for +previous: String
  for denied: {D.profile_permitted(profile, previous) == False{} : Bool}
  {Forms.selected_profile_effort(D.profile_permitted(profile, previous), previous, profile) == D.profile_default(profile) : String}

law rejected_reasoning_edit:
  for +profile: String
  for +reasoning: String
  {Forms.permitted_model_edit(False{}, profile, reasoning) == None{} : Maybe<&2, U.Edit>}

law accepted_reasoning_edit:
  for +profile: String
  for +reasoning: String
  {Forms.permitted_model_edit(True{}, profile, reasoning) == Some{U.ChooseModel{profile, reasoning}} : Maybe<&2, U.Edit>}

law selected_model_permission:
  for +profile: D.Profile
  for reasoning: String
  {U.selected_model_permitted(Some{profile}, reasoning) == D.profile_permitted(profile, D.profile_selection(reasoning, profile)) : Bool}

law rejected_profile_choice:
  {Model.model_choice_availability(False{}) == V.Unavailable{"The model has no permitted reasoning selection"} : V.Availability}

law new_task_model_permission:
  for message: U.Text
  for +profile: String
  for reasoning: String
  for context: Context.Configuration
  for world: M.World()
  {U.model_permitted(U.NewTask{message, profile, reasoning, context}, world) == U.selected_model_permitted(D.find_profile(Commands.configured(Commands.settings(world)), profile), reasoning) : Bool}

law agent_model_permission:
  for agent: Maybe<&2, Nat>
  for revision: Nat
  for name: String
  for +profile: String
  for reasoning: String
  for instructions: String
  for context: Context.Configuration
  for concurrency: Nat
  for world: M.World()
  {U.model_permitted(U.Agent{agent, revision, name, profile, reasoning, instructions, context, concurrency}, world) == U.selected_model_permitted(D.find_profile(Commands.configured(Commands.settings(world)), profile), reasoning) : Bool}

law modal_navigation_preserved:
  for +nav: V.Navigation
  for +state: InteractionTypes.State
  {Model.modal_navigation_at(V.ModalNavigation{}, nav, state) == [Model.navigation(nav, state)] : +List<SurfaceTypes.Node>}

law overlay_navigation_scope:
  for +key: Identity.Key
  for semantic: String
  for label: String
  for meaning: SurfaceTypes.Meaning
  for children: +List<SurfaceTypes.Node>
  for rest: +List<SurfaceTypes.Node>
  {Model.active_scope(SurfaceTypes.Node{key, semantic, label, SurfaceTypes.Navigation{}, meaning, children} <> rest) == Some{Identity.encode(key)} : Maybe<&2, String>}

law dialog_actions_region:
  for +parent: Identity.Key
  for +children: +List<SurfaceTypes.Node>
  {Model.dialog_actions(parent, children) == SurfaceTypes.Node{Identity.Part{parent, "@actions"}, "@actions", "Actions", SurfaceTypes.DialogActions{}, SurfaceTypes.Region{}, children} : SurfaceTypes.Node}

law editor_submit_region:
  for identity: U.Editor
  for revision: Nat
  for groups: +List<V.InputGroup>
  for structure: +List<Forms.Section>
  for submit: V.ControlDeclaration
  for feedback: U.Feedback
  for pending: Bool
  for +parent: Identity.Key
  for +state: InteractionTypes.State
  {Model.editor(Some{V.EditorScene{identity, revision, groups, structure, submit, feedback, pending}}, parent, state) ==
    List.append(&2, SurfaceTypes.Node, Model.sections(structure, identity, parent, 0n, state, groups),
      List.append(&2, SurfaceTypes.Node, Model.feedback_nodes(parent, feedback), [Model.dialog_actions(parent, [Model.declared(parent, submit, state)])])) : +List<SurfaceTypes.Node>}

law confirmation_actions_region:
  for title: String
  for confirm: V.ControlDeclaration
  for cancel: V.ControlDeclaration
  for +parent: Identity.Key
  for +state: InteractionTypes.State
  {Model.layer_content(V.Confirmation{title, confirm, cancel}, parent, state) ==
    [Model.dialog_actions(parent, [Model.declared(parent, confirm, state), Model.declared(parent, cancel, state)])] : +List<SurfaceTypes.Node>}

def expected_card(view: V.CardScene, +parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  V.CardScene{+id, +value, open, actions, linked, destinations, candidates} = view
  +observed_application = Core.application(state)
  world = E.program(observed_application)
  +observed_session = E.session(observed_application)
  +now = E.now(observed_session)
  +key : Identity.Key = Identity.Entity{parent, "card", Nat.show(id)}
  +face : V.CardFace = View.card_face(id, value, now, world)
  +offered : +List<SurfaceTypes.Placement> = List.append(&2, SurfaceTypes.Placement, Model.placements(destinations, id, B.revision(value), state), Model.archive_placement(B.archived(value), id, B.revision(value), state))
  SurfaceTypes.Node{key, "card/" ++ Nat.show(id), B.title(B.draft(value)), SurfaceTypes.Card{}, SurfaceTypes.CardContent{face},
    [Model.declared(key, open, state), Model.more(U.CardSubject{id}, key, state),
      SurfaceTypes.Node{Identity.part(key, "movement"), "card/" ++ Nat.show(id) ++ "/movement", "Move " ++ B.title(B.draft(value)), SurfaceTypes.Field{}, SurfaceTypes.MovableCard{offered, face}, Nil{}}]}

law card_ordered_movement:
  for +view: V.CardScene
  for +parent: Identity.Key
  for +state: InteractionTypes.State
  {Model.card(view, parent, state) == expected_card(view, parent, state) : SurfaceTypes.Node}

law card_surface_placement:
  for +key: Identity.Key
  for semantic: String
  for label: String
  for +face: V.CardFace
  for +children: +List<SurfaceTypes.Node>
  for target: String
  {Model.placement_source(SurfaceTypes.Node{key, semantic, label, SurfaceTypes.Card{}, SurfaceTypes.CardContent{face}, children}, target) == Model.placement_input(Model.card_placements(children), target) : Maybe<&2, InteractionTypes.Input>}

law card_movement_placement:
  for +key: Identity.Key
  for semantic: String
  for label: String
  for +face: V.CardFace
  for +destinations: +List<SurfaceTypes.Placement>
  for target: String
  {Model.placement_source(SurfaceTypes.Node{key, semantic, label, SurfaceTypes.Field{}, SurfaceTypes.MovableCard{destinations, face}, Nil{}}, target) == Model.placement_input(destinations, target) : Maybe<&2, InteractionTypes.Input>}

law project_fact_structure:
  for +key: Identity.Key
  for +label: String
  for value: String
  {Model.project_fact(key, label, value) == SurfaceTypes.Node{key, Identity.encode(key), label, SurfaceTypes.Content{}, SurfaceTypes.Fact{value}, Nil{}} : SurfaceTypes.Node}

law interface_input:
  for +input: InteractionTypes.Input
  for +state: InteractionTypes.State
  {ModelModel.step(ModelModel.InterfaceInput{input}, state) == Core.step(input, state) : InteractionTypes.Decision}

type InterfaceRequirements is Type:
  InterfaceRequirements{
    interface_input: @+input:InteractionTypes.Input -> @+state:InteractionTypes.State ->
      {ModelModel.step(ModelModel.InterfaceInput{input}, state) == Core.step(input, state) : InteractionTypes.Decision}
  }

law interface_evidence:
  InterfaceRequirements

type SettingsFields is Data:
  SettingsFields{workspace: J.Json, guidance: J.Json, project_id: J.Json,
    sandbox: J.Json, approval: J.Json}

def settings_fields(~value:J.Json) -> SettingsFields:
  SettingsFields{J.get(value, "workspace"), J.get(value, "guidance"),
    J.get(value, "project_id"), J.get(value, "sandbox"), J.get(value, "approval")}

def settings_observations_law(-config: Context.Configuration, -workspace: D.Workspace,
  -guidance: D.ProjectContext) -> Type:
  {settings_fields(Context.observed_settings(config, Context.DirectoryObservation{workspace, guidance})) ==
    SettingsFields{D.workspace_json(workspace), D.project_json(guidance),
      J.get(Context.settings(config), "project_id"),
      J.get(Context.settings(config), "sandbox"),
      J.get(Context.settings(config), "approval")} : SettingsFields}

type BoundaryRequirements is Type:
  BoundaryRequirements{
    accepted_auth: @+state:Services.State -> @ticket:Nat ->
      @owned:{Services.expected_access(Services.access(state), ticket) == True{} : Bool} ->
      {Services.step(Services.Authenticated{ticket, Done{Unit{}}}, state) ==
        Services.Decision{Services.with_settings_open(False{}, Services.with_credential("", Services.with_access(Services.Connected{}, state))), [Services.SessionReady{}]} : Services.Decision},
    failed_auth: @+state:Services.State -> @reason:String ->
      {Services.authentication(True{}, state, Fail{reason}) ==
        Services.Decision{Services.with_settings_open(True{}, Services.with_credential("", Services.with_access(Services.CredentialRejected{reason}, state))), Nil{}} : Services.Decision},
    unowned_auth: @+state:Services.State -> @result:Result<&2, &2, String, Unit> ->
      {Services.authentication(False{}, state, result) == Services.Decision{state, Nil{}} : Services.Decision},
    readiness_attention: @+state:Services.State -> @+application:E.Application ->
      {Core.service_result(Services.authentication(True{}, state, Done{Unit{}}), application) ==
        InteractionTypes.Decision{Core.from_application(application, Services.with_settings_open(False{}, Services.with_credential("", Services.with_access(Services.Connected{}, state)))), D.success(J.Null{}), Nil{}, [E.Attend{Core.session_attention(application)}], Nil{}, False{}} : InteractionTypes.Decision},
    failed_auth_no_attention: @+state:Services.State -> @reason:String -> @application:E.Application ->
      {Core.service_result(Services.authentication(True{}, state, Fail{reason}), application) ==
        Core.application_result_with_services(E.unchanged(application), Services.with_settings_open(True{}, Services.with_credential("", Services.with_access(Services.CredentialRejected{reason}, state))), Nil{}) : InteractionTypes.Decision},
    unowned_auth_no_attention: @state:Services.State -> @result:Result<&2, &2, String, Unit> -> @application:E.Application ->
      {Core.service_result(Services.authentication(False{}, state, result), application) == Core.application_result_with_services(E.unchanged(application), state, Nil{}) : InteractionTypes.Decision},
    readiness_is_internal: {Core.external_effect(Services.SessionReady{}) == False{} : Bool},
    stale_auth: @+state:Services.State -> @ticket:Nat -> @+result:Result<&2, &2, String, Unit> ->
      @observed_directory_picker:{Services.directory_picker(state) == Services.NoDirectoryPicker{} : Services.DirectoryPicker} ->
      @stale:{Services.expected_access(Services.access(state), ticket) == False{} : Bool} ->
      {Services.step(Services.Authenticated{ticket, result}, state) ==
        Services.Decision{state, Nil{}} : Services.Decision},
    missing_upload: @+state:Services.State -> @ticket:Nat -> @+result:Result<&2, &2, String, B.Attachment> ->
      @observed_directory_picker:{Services.directory_picker(state) == Services.NoDirectoryPicker{} : Services.DirectoryPicker} ->
      @missing:{Finite.find(~Services.Transfer, Services.transfers(state), ticket) == None{} : Maybe<&2, Services.Transfer>} ->
      {Services.step(Services.Uploaded{ticket, result}, state) ==
        Services.Decision{state, Nil{}} : Services.Decision},
    upload_destination: @+state:Services.State -> @ticket:Nat -> @+editor:U.Editor -> @+file:Services.SelectedFile ->
      @+attachment:B.Attachment ->
      @observed_directory_picker:{Services.directory_picker(state) == Services.NoDirectoryPicker{} : Services.DirectoryPicker} ->
      @found:{Finite.find(~Services.Transfer, Services.transfers(state), ticket) ==
        Some{Services.Uploading{editor, file}} : Maybe<&2, Services.Transfer>} ->
      {Services.step(Services.Uploaded{ticket, Done{attachment}}, state) ==
        Services.Decision{Services.with_transfers(Finite.remove(~Services.Transfer, Services.transfers(state), ticket), state),
          [Services.AttachToDraft{editor, attachment}]} : Services.Decision},
    closed_preview: @+state:Services.State -> @ticket:Nat -> @+result:Result<&2, &2, String, String> ->
      @observed_preview:{Services.preview(state) == Services.NoPreview{} : Services.Preview} ->
      @observed_directory_picker:{Services.directory_picker(state) == Services.NoDirectoryPicker{} : Services.DirectoryPicker} ->
      {Services.step(Services.Previewed{ticket, result}, state) ==
        Services.Decision{state, Nil{}} : Services.Decision},
    stale_preview: @+state:Services.State -> @current:Nat -> @+file:B.Attachment -> @trigger:String -> @ticket:Nat ->
      @+result:Result<&2, &2, String, String> ->
      @observed_preview:{Services.preview(state) == Services.LoadingPreview{current, file, trigger} : Services.Preview} ->
      @observed_directory_picker:{Services.directory_picker(state) == Services.NoDirectoryPicker{} : Services.DirectoryPicker} ->
      @different:{Nat.is_eq(current, ticket) == False{} : Bool} ->
      {Services.step(Services.Previewed{ticket, result}, state) ==
        Services.Decision{state, Nil{}} : Services.Decision},
    stale_copy: @+identity:Code.Identity -> @source:String -> @+wrap:Bool -> @+copy:Code.CopyState ->
      @next:Nat -> @ticket:Nat -> @success:Bool ->
      @stale:{Code.same_ticket(copy, ticket) == False{} : Bool} ->
      {Code.step(Code.Block{identity, source, Code.CodeView{wrap, copy}, next},
        Code.Copied{ticket, success}) ==
        Code.Decision{Code.Block{identity, source, Code.CodeView{wrap, copy}, next}, Nil{}} : Code.Decision},
    stale_copy_expiry: @+identity:Code.Identity -> @source:String -> @+wrap:Bool -> @+copy:Code.CopyState ->
      @next:Nat -> @ticket:Nat ->
      @stale:{Code.feedback_ticket(copy, ticket) == False{} : Bool} ->
      {Code.step(Code.Block{identity, source, Code.CodeView{wrap, copy}, next},
        Code.ExpireFeedback{ticket}) ==
        Code.Decision{Code.Block{identity, source, Code.CodeView{wrap, copy}, next}, Nil{}} : Code.Decision},
    copy_snapshot: @+identity:Code.Identity -> @source:String -> @+wrap:Bool -> @copy:Code.CopyState ->
      @next:Nat ->
      @can_copy:{Code.code_can_copy(Code.CodeView{wrap, copy}) == True{} : Bool} ->
      {Code.step(Code.Block{identity, source, Code.CodeView{wrap, copy}, next}, Code.Copy{}) ==
        Code.Decision{Code.Block{identity, source, Code.CodeView{wrap, Code.CopyPending{next}},
          (next + 1n : Nat)}, [Code.WriteClipboard{next, source}]} : Code.Decision},
    toggle_preserves_transfer: @+identity:Code.Identity -> @source:String -> @+wrap:Bool ->
      @copy:Code.CopyState -> @next:Nat ->
      {Code.step(Code.Block{identity, source, Code.CodeView{wrap, copy}, next}, Code.ToggleWrap{}) ==
        Code.Decision{Code.Block{identity, source,
          Code.CodeView{Bool.not(wrap), copy}, next}, Nil{}} : Code.Decision},
    effective_contract: @+model:D.Model -> @+tools:+List<D.Tool> -> @max_fork:Nat ->
      @max_descendants:Nat -> @+plugins:+List<D.Plugin> -> @+context:D.TaskContext -> @task:Nat ->
      {Context.effective_contract(D.Contract{model, tools, max_fork, max_descendants, plugins, context}, task) ==
        Context.EffectiveContext{task, context, D.model_guidance(model), W.default_access(context)} : Context.EffectiveContext},
    preview_override: @origin:Context.Origin -> @+workspace:D.Workspace -> @+sandbox:D.Sandbox ->
      @approval:D.ApprovalPolicy -> @project:Maybe<&2, Nat> -> @+guidance:D.ProjectContext ->
      @+entered_workspace:D.Workspace -> @+entered_sandbox:D.Sandbox ->
      @entered_approval:Context.ApprovalChoice ->
      {Context.preview_selected(Done{W.Selection{D.TaskContext{workspace, sandbox, approval, project}, guidance}},
        Context.Configuration{origin, Some{entered_workspace}, Some{entered_sandbox}, Some{entered_approval}}) ==
        Context.ProspectiveContext{origin, project, Context.EnteredWorkspace{entered_workspace},
          Context.ChosenSandbox{entered_sandbox}, Context.ChosenApproval{entered_approval},
          Context.AwaitingDirectoryGuidance{}} : Context.Preview},
    project_prepared: @project:Maybe<&2, Nat> -> @+name:String -> @+old_workspace:D.Workspace ->
      @+workspace:D.Workspace -> @+guidance:D.ProjectContext -> @now:U32 ->
      {U.prepared_command(U.Project{project, name, old_workspace},
        Context.DirectoryObservation{workspace, guidance}, now) ==
        U.project_command(project, name,
          D.workspace_json(workspace), D.project_json(guidance)) : M.Command},
    project_create: @+name:String -> @+workspace:D.Workspace -> @+guidance:D.ProjectContext ->
      {U.project_command(None{}, name, D.workspace_json(workspace), D.project_json(guidance)) ==
        M.CreateProject{name, D.workspace_json(workspace), D.project_json(guidance)} : M.Command},
    project_update: @project:Nat -> @+name:String -> @+workspace:D.Workspace -> @+guidance:D.ProjectContext ->
      {U.project_command(Some{project}, name, D.workspace_json(workspace), D.project_json(guidance)) ==
        M.UpdateProject{project, Some{name}, D.workspace_json(workspace), D.project_json(guidance)} : M.Command},
    task_prepared: @+text:U.Text -> @profile:String -> @reasoning:String ->
      @+config:Context.Configuration -> @+observation:Context.DirectoryObservation -> @now:U32 ->
      {U.prepared_command(U.NewTask{text, profile, reasoning, config}, observation, now) ==
        M.Create{profile, reasoning, U.text(text), Context.observed_settings(config, observation)} : M.Command},
    settings_observations: @+config:Context.Configuration -> @+workspace:D.Workspace ->
      @+guidance:D.ProjectContext ->
      settings_observations_law(config, workspace, guidance),
    inactive_stream_removed: @+task:Nat -> @+operation:Nat -> @+parts:+List<Live.Part> ->
      @+outputs:+List<Live.Output> -> @+world:M.World() ->
      @inactive:{Live.active(Live.Output{task, operation, parts}, world) == False{} : Bool} ->
      {Live.observe(Live.PartialOutput{Live.Output{task, operation, parts}}, outputs, world) ==
        Live.remove(outputs, task, operation) : +List<Live.Output>},
    active_stream_retained: @+task:Nat -> @+operation:Nat -> @+parts:+List<Live.Part> ->
      @+outputs:+List<Live.Output> -> @+world:M.World() ->
      @active:{Live.active(Live.Output{task, operation, parts}, world) == True{} : Bool} ->
      {Live.observe(Live.PartialOutput{Live.Output{task, operation, parts}}, outputs, world) ==
        Live.Output{task, operation, parts} <> Live.remove(outputs, task, operation) : +List<Live.Output>}
  }

law boundary_evidence:
  BoundaryRequirements
