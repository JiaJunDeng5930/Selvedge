import ../submission/field-options.bend as FieldOptions
import ../experience/PROGRAM.bend as UX
import ../experience/MODEL.bend as Experience
import ../experience/ACTIVITY.bend as Activity
import ./INFORMATION.bend as Information
import Base
import ../../harness/COMMANDS.bend as Commands
import ../../harness/tasks/PROGRAM.bend as T
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
import ../../features/task_graph/MODEL.bend as G
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

def navigation_task_graphs_control(navigation: V.Navigation) -> Maybe<&2, V.ControlDeclaration>:
  V.Navigation{expanded, create, destinations, projects, tasks, toggle} = navigation
  match destinations:
    case Con{board, Con{collection, Con{agents, Con{graphs, rest}}}}: Some{graphs}
    case _: None{}

def task_graphs_navigation_selected(+route: U.Route, +world: M.World(), +session: E.Session) -> Bool:
  selected_control(navigation_task_graphs_control(View.navigation(True{}, route, world, session)), route)

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
    new_task_graph: {View.editor_title(U.TaskGraphEditor{None{}}) == "New task graph" : String},
    edit_task_graph: @id:Nat -> {View.editor_title(U.TaskGraphEditor{Some{id}}) == "Edit task graph" : String},
    fork: @task:Nat -> {View.editor_title(U.ForkEditor{task}) == "Fork task" : String},
    compact: @task:Nat -> {View.editor_title(U.CompactEditor{task}) == "Compact history" : String},
    actions: @actions:+List<V.ControlDeclaration> -> {View.layer_title(V.ObjectActions{actions}) == "Actions" : String},
    archived: @cards:+List<V.CardScene> -> {View.layer_title(V.ArchivedCards{cards}) == "Archived cards" : String},
    board_settings: @automatic:Bool -> @selected:String -> @profiles:+List<D.Profile> -> @automation:V.ControlDeclaration ->
      {View.layer_title(V.BoardSettings{automatic, selected, profiles, automation}) == "看板设置" : String},
    board_filters: @filter:B.Filter -> {View.layer_title(V.BoardFilters{filter}) == "筛选任务" : String},
    unavailable: {View.layer_title(V.ObjectEditor{None{}}) == "Editor unavailable" : String},
    editor: @identity:U.Editor -> @revision:Nat -> @groups:+List<V.InputGroup> -> @sections:+List<Forms.Section> -> @assessment:Experience.Assessment -> @submit:V.ControlDeclaration -> @feedback:U.Feedback -> @pending:Bool -> {View.layer_title(V.ObjectEditor{Some{V.EditorScene{identity, revision, groups, sections, assessment, submit, feedback, pending}}}) == View.editor_title(identity) : String},
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

def task_graph_value(scene: V.TaskGraphScene) -> G.Graph:
  V.TaskGraphScene{id, value, nodes, edit, remove} = scene
  value

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
      {layer_label(Model.layers([V.Layer{kind, content, initial, restore, close}], state)) == Some{Model.activity_layer_label(Model.layer_activity(content, state), View.layer_title(content), state)} : Maybe<&2, String>},
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
    task_graphs_title: @+graphs:+List<V.TaskGraphScene> -> @+create:V.ControlDeclaration -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
      {find_region(Model.page_contents(V.TaskGraphsPage{graphs, create}, parent, state), Composition.CollectionTitle{}) ==
        Some{[Model.region(parent, "heading", "Task graphs", SurfaceTypes.Heading{}, Nil{})]} : Maybe<&2, +List<SurfaceTypes.Node>>},
    task_graphs_nav_selected: @+world:M.World() -> @+session:E.Session ->
      {task_graphs_navigation_selected(U.TaskGraphs{}, world, session) == True{} : Bool},
    task_graph_declaration: @+id:Nat -> @+value:G.Graph -> @route:U.Route -> @+world:M.World() ->
      {task_graph_value(View.task_graph_scene(id, value, route, world)) == value : G.Graph},
    board_title: @+filter:B.Filter -> @+columns:+List<V.BoardColumn> -> @+create:V.ControlDeclaration -> @working:Nat ->
      @+settings:V.ControlDeclaration -> @+filters:V.ControlDeclaration -> @+archive:V.ControlDeclaration -> @+parent: Identity.Key -> @+state:InteractionTypes.State ->
      {find_region(Model.page_contents(V.BoardPage{filter, columns, create, working, settings, filters, archive}, parent, state), Composition.BoardTitle{}) ==
        Some{[Model.region(parent, "heading", "Board", SurfaceTypes.Heading{}, Nil{})]} : Maybe<&2, +List<SurfaceTypes.Node>>},
    creation_title: @+heading:String -> @+summary:String -> @+context:Maybe<&2, Context.Preview> -> @+project:Maybe<&2, V.ProjectChoice> -> @+choose:V.ControlDeclaration -> @+parent: Identity.Key -> @+state:InteractionTypes.State ->
      {find_region(Model.creation_introduction_nodes(V.CreationIntroduction{heading, summary, context, project, choose}, parent, state), Composition.CreationIntroduction{}) ==
        Some{[SurfaceTypes.Node{Identity.Part{Identity.Part{Identity.Part{Identity.Part{parent, "creation"}, "introduction"}, "creation"}, "title"}, "creation/title", heading, SurfaceTypes.Heading{}, SurfaceTypes.InformationText{Information.IntroductionTitle{}}, Nil{}}]} : Maybe<&2, +List<SurfaceTypes.Node>>},
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
  InteractionTypes.Control{+identity, label, prominence, input, +availability} = control
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
      Composition.Structure{Nil{}, Composition.CreationIntroduction{} <> Composition.centered_composer_region(composer), Nil{}}
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
    case Composition.Recipe{measure, heading, Composition.TaskGraphRows{}, composer, decisions, latest}:
      Composition.Structure{[Composition.CollectionTitle{}, Composition.CollectionActions{}], [Composition.TaskGraphEntries{}], Nil{}}
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
    case Some{V.ComposerScene{identity, revision, message, phase, creation_context, execution_controls, context, assessment, submit, feedback, pending}}: execution_controls

def composer_phase(value: Maybe<&2, V.ComposerScene>) -> Maybe<&2, V.ComposerPhase>:
  match value:
    case None{}: None{}
    case Some{V.ComposerScene{identity, revision, message, phase, creation_context, execution_controls, context, assessment, submit, feedback, pending}}: Some{phase}

def composer_creation_controls(value: Maybe<&2, V.ComposerScene>) -> +List<V.ComposerControl>:
  match value:
    case None{}: Nil{}
    case Some{V.ComposerScene{identity, revision, message, phase, creation_context, execution_controls, context, assessment, submit, feedback, pending}}: creation_context

def first_node_meaning(nodes: +List<SurfaceTypes.Node>) -> Maybe<&2, SurfaceTypes.Meaning>:
  match nodes:
    case Nil{}: None{}
    case Con{node, rest}: Some{meaning(node)}

def collection_instruction(nodes: +List<SurfaceTypes.Node>) -> Maybe<&2, SurfaceTypes.Meaning>:
  match nodes:
    case Con{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.WorkspaceCollection{collection}, children}, rest}: first_node_meaning(children)
    case _: None{}

def expected_collection_instruction(found: Maybe<&2, D.Workspace>) -> Maybe<&2, SurfaceTypes.Meaning>:
  match found:
    case None{}: None{}
    case Some{workspace}: Some{SurfaceTypes.InformationText{Information.Description{}}}

def composer_enclosure_children(nodes: +List<SurfaceTypes.Node>) -> Maybe<&2, +List<SurfaceTypes.Node>>:
  match nodes:
    case Nil{}: None{}
    case Con{SurfaceTypes.Node{key, semantic, label, role, meaning, children}, rest}:
      match role:
        case SurfaceTypes.Composer{}: Some{children}
        case _: composer_enclosure_children(rest)

def expected_composer_enclosure_children(view: Maybe<&2, V.ComposerScene>, +parent: Identity.Key, +state: InteractionTypes.State) -> Maybe<&2, +List<SurfaceTypes.Node>>:
  match view:
    case None{}: None{}
    case Some{V.ComposerScene{+identity, +revision, message, phase, creation_context, execution_controls, context, +assessment, +submit, feedback, +pending}}:
      +key : Identity.Key = Identity.Entity{parent, "composer", U.editor_key(identity)}
      Some{Model.field_node(Forms.FieldScene{Forms.MessageText{}, "Message", Forms.Multiline{}}, identity, key, state, Nil{}) <>
        List.append(&2, SurfaceTypes.Node, List.append(&2, SurfaceTypes.Node, Model.canonical_explanation(UX.action(identity, revision, pending), assessment, submit, key, state), Model.action_feedback_nodes(identity, feedback, key)), [Model.action_footer(execution_controls, UX.action(identity, revision, pending), assessment, submit, key, state)])}

def expected_committed_permission_summary(context: Maybe<&2, Context.EffectiveContext>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match context:
    case Some{+value}: [Model.permission_context_summary(U.MessageEditor{View.context_task(value)}, Context.CommittedExecution{value}, parent, state)]
    case None{}: Model.unavailable_context("Task execution context is unavailable", parent)

def expected_permission_menu_group(+editor: U.Editor, group: V.InputGroup, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match group:
    case V.ExecutionInput{config, Context.ContextUnavailable{reason}, controls, projects, reviewers}: Model.unavailable_context(reason, parent)
    case V.ExecutionInput{+config, Context.ProspectiveContext{+origin, +project, +workspace, +sandbox, +approval, +guidance}, controls, projects, reviewers}:
      List.append(&2, SurfaceTypes.Node,
        Model.permission_summary(editor, Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, parent, state),
        List.append(&2, SurfaceTypes.Node, Model.permission_decisions(editor, Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, reviewers, parent, state),
        Model.permission_resets(editor, config, parent, state)))
    case _: Nil{}

def expanded_navigation_placement(beside: Bool) -> V.NavigationPlacement:
  match beside:
    case True{}: V.LeadingNavigation{}
    case False{}: V.ModalNavigation{}

type CompositionRequirements is Type:
  CompositionRequirements{
    production_regions: PageRegionRequirements,
    expanded_navigation: @beside:Bool -> {View.navigation_placement(beside, True{}) == expanded_navigation_placement(beside) : V.NavigationPlacement},
    collapsed_navigation: @beside:Bool -> {View.navigation_placement(beside, False{}) == V.CollapsedNavigation{} : V.NavigationPlacement},
    committed_permission_summary: @task:Nat -> @preview:Context.Preview -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
      {Model.permission_summary(U.MessageEditor{task}, preview, parent, state) ==
        expected_committed_permission_summary(View.committed_context(T.find(Commands.entries(E.program(Core.application(state))), task)), parent, state) : +List<SurfaceTypes.Node>},
    task_permission_resets: @task:Nat -> @config:Context.Configuration -> @parent:Identity.Key -> @state:InteractionTypes.State ->
      {Model.permission_resets(U.MessageEditor{task}, config, parent, state) == Nil{} : +List<SurfaceTypes.Node>},
    permission_menu: @+editor:U.Editor -> @group:V.InputGroup -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
      {Model.permission_menu_group(editor, group, parent, state) == expected_permission_menu_group(editor, group, parent, state) : +List<SurfaceTypes.Node>},
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
    workspace_description: @+editor:U.Editor -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
      {collection_instruction(Model.field_children(Forms.WorkspaceDirectories{}, editor, parent, state)) ==
        expected_collection_instruction(Model.workspace_observed(Model.field_value(state, editor, Forms.WorkspaceDirectories{}))) : Maybe<&2, SurfaceTypes.Meaning>},
    composer_enclosure: @view:Maybe<&2, V.ComposerScene> -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
      {composer_enclosure_children(Model.composer(view, parent, state)) == expected_composer_enclosure_children(view, parent, state) : Maybe<&2, +List<SurfaceTypes.Node>>},
    structure_order: @recipe:Composition.Recipe ->
      {Composition.structure(recipe) == expected_structure(recipe) : Composition.Structure},
    creation_project: @+context:Maybe<&2, Context.Preview> -> @+world:M.World() ->
      {introduction_project(View.creation_introduction_fields(context, world)) == View.creation_selected_project(context, world) : Maybe<&2, V.ProjectChoice>},
    creation_context: @+identity:U.Editor -> @revision:Nat -> @message:U.Text -> @+footer:+List<V.ComposerControl> ->
      @+context:Maybe<&2, Context.Preview> -> @assessment:Experience.Assessment -> @submit:V.ControlDeclaration -> @feedback:U.Feedback -> @pending:Bool -> @+world:M.World() ->
      {introduction_context(View.creation_introduction(Some{V.ComposerScene{identity, revision, message, V.Creation{}, Nil{}, footer, View.preview_observation(context), assessment, submit, feedback, pending}}, world)) == context : Maybe<&2, Context.Preview>},
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
        [View.model_composer_control(profile, reasoning, world),
         V.ComposerControl{UX.permissions_property(U.NewTaskEditor{}, Context.DraftExecution{Context.preview(context, world)}), View.context_control("composer/permissions/new-task", View.observation_permissions(Context.DraftExecution{Context.preview(context, world)}, Board.profiles(world)), U.PermissionsConfiguration{U.NewTaskEditor{}})}] : +List<V.ComposerControl>},
    model_label: @fallback:String -> {View.profile_label(None{}, fallback) == "Choose model" : String},
    creation_phase: @message:U.Text -> @profile:String -> @reasoning:String -> @context:Context.Configuration -> @scene:V.EditorScene -> @world:M.World() ->
      {composer_phase(View.composer_scene(U.NewTask{message, profile, reasoning, context}, scene, world)) == Some{V.Creation{}} : Maybe<&2, V.ComposerPhase>},
    conversation_phase: @+task:Nat -> @message:U.Text -> @delivery:U.Delivery -> @scene:V.EditorScene -> @world:M.World() ->
      {composer_phase(View.composer_scene(U.Message{task, message, delivery}, scene, world)) == Some{V.Conversation{task}} : Maybe<&2, V.ComposerPhase>},
    conversation_has_no_creation_context: @task:Nat -> @message:U.Text -> @delivery:U.Delivery -> @scene:V.EditorScene -> @world:M.World() ->
      {composer_creation_controls(View.composer_scene(U.Message{task, message, delivery}, scene, world)) == Nil{} : +List<V.ComposerControl>},
    creation_context_controls: @message:U.Text -> @profile:String -> @reasoning:String -> @+context:Context.Configuration -> @scene:V.EditorScene -> @+world:M.World() ->
      {composer_creation_controls(View.composer_scene(U.NewTask{message, profile, reasoning, context}, scene, world)) ==
        [V.ComposerControl{UX.project_property(U.NewTaskEditor{}, View.observation_project(Context.DraftExecution{Context.preview(context, world)}), world), View.context_control("composer/project", View.project_choice_label(View.creation_selected_project(Some{Context.preview(context, world)}, world)), U.ProjectPicker{})},
         V.ComposerControl{UX.workspace_property(U.NewTaskEditor{}, Context.DraftExecution{Context.preview(context, world)}, world), View.context_control("composer/workspace/new-task", View.observation_workspace(Context.DraftExecution{Context.preview(context, world)}), U.WorkspaceConfiguration{U.NewTaskEditor{}})}] : +List<V.ComposerControl>}

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
    owned: @ticket:Nat -> @+editor:U.Editor -> @entered:String -> @+trigger:String -> @+path:String -> @+parent:Maybe<&2, String> -> @+entries:+List<Services.DirectoryEntry> -> @+truncated:Bool -> @+state:Services.State -> {Services.directory_calculation(ticket, editor, entered, trigger, Done{Services.DirectoryCatalog{path, parent, entries, truncated}}, state) ==
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
    row: @+path:String -> @collection:Experience.Collection -> @+parent:Identity.Key -> @state:InteractionTypes.State ->
      {spatial_identity(Model.collection_member(collection, path, parent, state)) == Identity.Entity{parent, "directory", path} : Identity.Key},
    primary: @+path:String -> @collection:Experience.Collection -> @+parent:Identity.Key -> @state:InteractionTypes.State ->
      {first_spatial_identity(Model.collection_primary_controls(True{}, collection, path, Identity.Entity{parent, "directory", path}, state)) == Identity.Part{Identity.Entity{parent, "directory", path}, "primary"} : Identity.Key},
    slot_not_directory: @path:String -> @collection:Experience.Collection -> @+parent:Identity.Key -> @state:InteractionTypes.State -> @other:String -> @name:String ->
      {Identity.same(Identity.Part{spatial_identity(Model.collection_member(collection, path, parent, state)), name}, Identity.Entity{parent, "directory", other}) == False{} : Bool},
    directory_not_slot: @path:String -> @collection:Experience.Collection -> @+parent:Identity.Key -> @state:InteractionTypes.State -> @other:String -> @name:String ->
      {Identity.same(Identity.Entity{parent, "directory", other}, Identity.Part{spatial_identity(Model.collection_member(collection, path, parent, state)), name}) == False{} : Bool}}

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
    ("Work on " ++ name, name) : Sigma<&2, &2, String, (_ => String)>},
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
      @observed_layers:{E.layers(session) == E.Layer{U.ProjectPicker{}, trigger, initial, previous, layer_occurrence, False{}, None{}, None{}} <> rest : +List<E.Layer>} ->
       {E.search_choices(query, E.from_program(world, session)) ==
        E.local(world, E.with_layers(E.Layer{U.ProjectPicker{}, trigger, initial, query, layer_occurrence, False{}, None{}, None{}} <> rest, session), Nil{}) : E.Decision},
    project_group_single_title: @+id:Nat -> @name:String -> @workspace:D.Workspace -> @+selected:Bool -> @+expanded:Bool -> @+tasks:+List<V.TaskEntry> -> @+open:V.ControlDeclaration -> @+create:V.ControlDeclaration -> @+toggle:V.ControlDeclaration -> @+more:V.ControlDeclaration -> @+parent: Identity.Key -> @+state:InteractionTypes.State ->
      {Model.project_entries([V.ProjectEntry{id, name, workspace, selected, expanded, tasks, open, create, toggle, more}], parent, state) ==
        [SurfaceTypes.Node{Identity.Entity{parent, "project", Nat.show(id)}, "project-group", "", SurfaceTypes.Section{}, SurfaceTypes.ProjectGroup{id, selected, expanded},
          Model.region(Identity.Entity{parent, "project", Nat.show(id)}, "actions", "", SurfaceTypes.Section{},
            [Model.declared(Identity.Entity{parent, "project", Nat.show(id)}, toggle, state), Model.selected_node(selected, Model.declared(Identity.Entity{parent, "project", Nat.show(id)}, open, state)),
             Model.declared(Identity.Entity{parent, "project", Nat.show(id)}, create, state), Model.declared(Identity.Entity{parent, "project", Nat.show(id)}, more, state)]) <>
          Model.disclosed_tasks(expanded, tasks, Identity.Entity{parent, "project", Nat.show(id)}, state)}] : +List<SurfaceTypes.Node>},
    independent_source: @+expanded:Bool -> @+route:U.Route -> @+world:M.World() -> @+session:E.Session ->
      {View.navigation(expanded, route, world, session) == V.Navigation{expanded, View.control("new-task", "新任务", U.BeginTask{None{}}),
        [View.control("board", "任务看板", U.Navigate{U.TaskBoard{}}), View.control("projects", "项目", U.Navigate{U.ProjectCollection{}}), View.control("agents", "智能体", U.Navigate{U.AgentCollection{}}), View.control("task-graphs", "Task graphs", U.Navigate{U.TaskGraphs{}})],
        View.project_entries(Projects.entries(Projects.registry(F.State(), world)), Commands.entries(world), route, View.active_project(route, session, world), E.navigation(session)), View.task_entries(View.project_tasks(Commands.entries(world), None{}), route),
        V.ControlDeclaration{"navigation/toggle", "Toggle sidebar", V.Secondary{}, U.SetNavigation{Bool.not(expanded)}, V.Available{}}} : V.Navigation},
    navigation_entry_fields: @+key:Identity.Key -> @+semantic:String -> @+label:String -> @role:SurfaceTypes.Role -> @+meaning:SurfaceTypes.Meaning -> @+children:+List<SurfaceTypes.Node> -> @+selected:Bool ->
      {Model.replace_role(SurfaceTypes.Node{key, semantic, label, role, meaning, children}, SurfaceTypes.NavigationEntry{selected}) ==
        SurfaceTypes.Node{key, semantic, label, SurfaceTypes.NavigationEntry{selected}, meaning, children} : SurfaceTypes.Node},
    navigation_declaration_binding: @+route:U.Route -> @+parent:Identity.Key -> @+identity:String -> @+label:String -> @+prominence:V.Prominence -> @+input:U.Input -> @+availability:V.Availability -> @+state:InteractionTypes.State ->
      {Model.navigation_declaration(route, parent, V.ControlDeclaration{identity, label, prominence, input, availability}, state) ==
        Model.replace_role(Model.selected_declaration(route, parent, V.ControlDeclaration{identity, label, prominence, input, availability}, state), SurfaceTypes.NavigationEntry{Model.navigation_action_selected(route, input)}) : SurfaceTypes.Node},
    navigation_controls_empty: @+route:U.Route -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
      {Model.navigation_controls(route, Nil{}, parent, state) == Nil{} : +List<SurfaceTypes.Node>},
    navigation_controls_complete: @+route:U.Route -> @+first:V.ControlDeclaration -> @+rest:+List<V.ControlDeclaration> -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
      {Model.navigation_controls(route, first <> rest, parent, state) == Model.navigation_declaration(route, parent, first, state) <> Model.navigation_controls(route, rest, parent, state) : +List<SurfaceTypes.Node>},
    navigation_destinations_complete: @+route:U.Route -> @+create:V.ControlDeclaration -> @+destinations:+List<V.ControlDeclaration> -> @+state:InteractionTypes.State ->
      {Model.navigation_destinations(route, create, destinations, state) ==
        SurfaceTypes.Node{Identity.Part{Identity.Place{"/navigation"}, "destinations"}, "navigation-destinations", "", SurfaceTypes.NavigationSection{}, SurfaceTypes.Region{},
          Model.navigation_declaration(route, Identity.Place{"/navigation"}, create, state) <> Model.navigation_controls(route, destinations, Identity.Place{"/navigation"}, state)} : SurfaceTypes.Node},
    independent_empty: @+parent:Identity.Key -> @+state:InteractionTypes.State ->
      {Model.independent_task_entries(Nil{}, parent, state) == Nil{} : +List<SurfaceTypes.Node>},
    independent_populated: @+first:V.TaskEntry -> @+rest:+List<V.TaskEntry> -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
      {Model.independent_task_entries(Con{first, rest}, parent, state) == [Model.region(parent, "independent-tasks", "", SurfaceTypes.NavigationSection{},
        SurfaceTypes.Node{Identity.Part{Identity.Part{parent, "independent-tasks"}, "title"}, "independent-tasks/title", "Tasks without a project", SurfaceTypes.Heading{}, SurfaceTypes.InformationText{Information.NavigationCaption{}}, Nil{}} <>
        Model.task_entries(Con{first, rest}, parent, state))] : +List<SurfaceTypes.Node>},
    navigation_closed: @+route:U.Route -> @+create:V.ControlDeclaration -> @+destinations:+List<V.ControlDeclaration> -> @+projects:+List<V.ProjectEntry> -> @+tasks:+List<V.TaskEntry> -> @+state:InteractionTypes.State ->
      {Model.navigation_contents(False{}, route, create, destinations, projects, tasks, state) == Nil{} : +List<SurfaceTypes.Node>},
    navigation_open: @+route:U.Route -> @+create:V.ControlDeclaration -> @+destinations:+List<V.ControlDeclaration> -> @+projects:+List<V.ProjectEntry> -> @+tasks:+List<V.TaskEntry> -> @+state:InteractionTypes.State ->
      {Model.navigation_contents(True{}, route, create, destinations, projects, tasks, state) ==
        [SurfaceTypes.Node{Identity.Part{Identity.Place{"/navigation"}, "contents"}, "navigation-content", "", SurfaceTypes.NavigationCollection{}, SurfaceTypes.Region{},
          Model.navigation_destinations(route, create, destinations, state) <> List.append(&2, SurfaceTypes.Node,
            Model.project_entries(projects, Identity.Place{"/navigation"}, state), Model.independent_task_entries(tasks, Identity.Place{"/navigation"}, state))}] : +List<SurfaceTypes.Node>},
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
      @valid_manual:{E.manual_model(session) && E.permitted_preference(D.find_profile(Board.profiles(world), profile), reasoning) == True{} : Bool} ->
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
      {receipt(ModelModel.step(ModelModel.Element{capacity, key, SurfaceTypes.Press{}}, state)) == receipt(Core.step(Model.activity_requested_input(input, state), state)) : Receipt},
    existing_layer_trigger: @+previous:+List<E.Layer> -> @origin:String -> @+panel:U.Panel -> @trigger:String ->
      @initial_attention:String -> @query:String -> @+layer_occurrence:Nat -> @+source_expanded:Bool -> @+decision_field:Maybe<&2, Forms.Field> -> @+parameter_buffer:Maybe<&2, String> -> @+rest:+List<E.Layer> ->
      @present:{Model.layer_present(previous, E.panel_target(panel)) == True{} : Bool} ->
      {Model.record_layer(E.Layer{panel, trigger, initial_attention, query, layer_occurrence, source_expanded, decision_field, parameter_buffer} <> rest, previous, origin) ==
        E.Layer{panel, trigger, initial_attention, query, layer_occurrence, source_expanded, decision_field, parameter_buffer} <> rest : +List<E.Layer>},
    new_layer_trigger: @+previous:+List<E.Layer> -> @origin:String -> @+panel:U.Panel -> @trigger:String ->
      @initial_attention:String -> @query:String -> @+layer_occurrence:Nat -> @+source_expanded:Bool -> @+decision_field:Maybe<&2, Forms.Field> -> @+parameter_buffer:Maybe<&2, String> -> @+rest:+List<E.Layer> ->
      @absent:{Model.layer_present(previous, E.panel_target(panel)) == False{} : Bool} ->
      {Model.record_layer(E.Layer{panel, trigger, initial_attention, query, layer_occurrence, source_expanded, decision_field, parameter_buffer} <> rest, previous, origin) ==
        E.Layer{panel, origin, initial_attention, query, layer_occurrence, source_expanded, decision_field, parameter_buffer} <> rest : +List<E.Layer>}}

law surface_evidence:
  SurfaceRequirements

law composer_tree_present_agreement:
  for +identity: U.Editor
  for revision: Nat
  for message: U.Text
  for phase: V.ComposerPhase
  for creation_context: +List<V.ComposerControl>
  for execution_controls: +List<V.ComposerControl>
  for context: Maybe<&2, Context.Observation>
  for +assessment: Experience.Assessment
  for submit: V.ControlDeclaration
  for feedback: U.Feedback
  for pending: Bool
  for +parent: Identity.Key
  for +state: InteractionTypes.State
  {Model.composer(Some{V.ComposerScene{identity, revision, message, phase, creation_context, execution_controls, context, assessment, submit, feedback, pending}}, parent, state) ==
      Model.expected_composer(Some{V.ComposerScene{identity, revision, message, phase, creation_context, execution_controls, context, assessment, submit, feedback, pending}}, parent, state) : +List<SurfaceTypes.Node>}

law composer_tree_agreement:
  for view: Maybe<&2, V.ComposerScene>
  for +parent: Identity.Key
  for +state: InteractionTypes.State
  {Model.composer(view, parent, state) == Model.expected_composer(view, parent, state) : +List<SurfaceTypes.Node>}

law composer_enclosure_present_agreement:
  for +identity: U.Editor
  for revision: Nat
  for message: U.Text
  for phase: V.ComposerPhase
  for creation_context: +List<V.ComposerControl>
  for execution_controls: +List<V.ComposerControl>
  for context: Maybe<&2, Context.Observation>
  for +assessment: Experience.Assessment
  for submit: V.ControlDeclaration
  for feedback: U.Feedback
  for pending: Bool
  for +parent: Identity.Key
  for +state: InteractionTypes.State
  {composer_enclosure_children(Model.composer(Some{V.ComposerScene{identity, revision, message, phase, creation_context, execution_controls, context, assessment, submit, feedback, pending}}, parent, state)) ==
    expected_composer_enclosure_children(Some{V.ComposerScene{identity, revision, message, phase, creation_context, execution_controls, context, assessment, submit, feedback, pending}}, parent, state) : Maybe<&2, +List<SurfaceTypes.Node>>}

law composer_enclosure_agreement:
  for view: Maybe<&2, V.ComposerScene>
  for +parent: Identity.Key
  for +state: InteractionTypes.State
  {composer_enclosure_children(Model.composer(view, parent, state)) == expected_composer_enclosure_children(view, parent, state) : Maybe<&2, +List<SurfaceTypes.Node>>}

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
  {Forms.model_edit_admitted(None{}) == None{} : Maybe<&2, U.Edit>}

law accepted_reasoning_edit:
  for +profile: String
  for +reasoning: String
  {Forms.model_edit_value(profile, reasoning) == Some{U.ChooseModel{profile, reasoning}} : Maybe<&2, U.Edit>}

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
  for +assessment: Experience.Assessment
  for submit: V.ControlDeclaration
  for feedback: U.Feedback
  for pending: Bool
  for +parent: Identity.Key
  for +state: InteractionTypes.State
  {Model.ordinary_editor(Some{V.EditorScene{identity, revision, groups, structure, assessment, submit, feedback, pending}}, parent, state) ==
    List.append(&2, SurfaceTypes.Node, Model.sections(structure, identity, parent, 0n, state, groups),
      List.append(&2, SurfaceTypes.Node, List.append(&2, SurfaceTypes.Node, Model.canonical_explanation(UX.action(identity, revision, pending), assessment, submit, parent, state), Model.action_feedback_nodes(identity, feedback, parent)), [Model.dialog_actions(parent, [Model.canonical_commit(UX.action(identity, revision, pending), assessment, submit, parent, state)])])) : +List<SurfaceTypes.Node>}

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
        Services.Decision{Services.with_settings_open(False{}, Services.with_access(Services.Connected{}, state)), [Services.SessionReady{}]} : Services.Decision},
    failed_auth: @+state:Services.State -> @reason:String ->
      {Services.authentication_calculation(state, Fail{reason}) ==
        Services.Decision{Services.with_settings_open(True{}, Services.with_access(Services.ConnectionLost{reason}, state)), Nil{}} : Services.Decision},
    unowned_auth: @+state:Services.State -> @result:Result<&2, &2, String, Unit> ->
      {Services.authentication_admitted(None{}, state) == Services.Decision{state, Nil{}} : Services.Decision},
    readiness_attention: @+state:Services.State -> @+application:E.Application ->
      {Core.service_result(Services.authentication_calculation(state, Done{Unit{}}), application) ==
        InteractionTypes.Decision{Core.from_application(application, Services.with_settings_open(False{}, Services.with_access(Services.Connected{}, state))), D.success(J.Null{}), Nil{}, [E.Attend{Core.session_attention(application)}], Nil{}, False{}} : InteractionTypes.Decision},
    failed_auth_no_attention: @+state:Services.State -> @reason:String -> @application:E.Application ->
      {Core.service_result(Services.authentication_calculation(state, Fail{reason}), application) ==
        Core.application_result_with_services(E.unchanged(application), Services.with_settings_open(True{}, Services.with_access(Services.ConnectionLost{reason}, state)), Nil{}) : InteractionTypes.Decision},
    unowned_auth_no_attention: @state:Services.State -> @result:Result<&2, &2, String, Unit> -> @application:E.Application ->
      {Core.service_result(Services.authentication_admitted(None{}, state), application) == Core.application_result_with_services(E.unchanged(application), state, Nil{}) : InteractionTypes.Decision},
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
      @max_descendants:Nat -> @+plugins:+List<D.Plugin> -> @+context:D.TaskContext -> @task:Nat -> @+guidance:D.ProjectContext ->
      {Context.effective_contract(D.Contract{model, tools, max_fork, max_descendants, plugins, context}, task, guidance) ==
        Context.EffectiveContext{task, context, guidance, W.default_access(context)} : Context.EffectiveContext},
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

law committed_permission_summary_agreement:
  @task:Nat -> @preview:Context.Preview -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
  {Model.permission_summary(U.MessageEditor{task}, preview, parent, state) ==
    expected_committed_permission_summary(View.committed_context(T.find(Commands.entries(E.program(Core.application(state))), task)), parent, state) : +List<SurfaceTypes.Node>}

law task_permission_resets_absent:
  @task:Nat -> @config:Context.Configuration -> @parent:Identity.Key -> @state:InteractionTypes.State ->
  {Model.permission_resets(U.MessageEditor{task}, config, parent, state) == Nil{} : +List<SurfaceTypes.Node>}

law permission_menu_agreement:
  @+editor:U.Editor -> @group:V.InputGroup -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
  {Model.permission_menu_group(editor, group, parent, state) == expected_permission_menu_group(editor, group, parent, state) : +List<SurfaceTypes.Node>}

def expected_supporting_binding(support: Experience.Support, input: InteractionTypes.Input, availability: V.Availability, gesture: SurfaceTypes.Gesture) -> Maybe<&2, InteractionTypes.Input>:
  match gesture:
    case SurfaceTypes.Press{}: Model.when_available(UX.support_visible(support) && Model.available(availability), input)
    case _: None{}

def expected_supporting_submission(support: Experience.Support, input: InteractionTypes.Input, availability: V.Availability, editor: U.Editor) -> Bool:
  match input:
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.Submit{owner}}}}: UX.support_visible(support) && Model.available(availability) && U.same_editor(owner, editor)
    case _: False{}

def expected_model_effort_surface(entry: Forms.Entry, +observation: Forms.Observed, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State, groups: +List<V.InputGroup>) -> SurfaceTypes.Node:
  match entry:
    case Forms.Choice{}: Model.decision_surface(UX.decision(Experience.Subject{editor, Forms.ReasoningEffort{}}, observation, "Reasoning effort", Model.effort_alternatives(FieldOptions.choices(Forms.ReasoningEffort{}, observation, groups))), parent, state)
    case Forms.SingleLine{}: Model.field_node(Forms.FieldScene{Forms.ReasoningEffort{}, "Reasoning effort", Forms.SingleLine{}}, editor, parent, state, groups)
    case Forms.DisplayOnly{}: Model.field_node(Forms.FieldScene{Forms.ReasoningEffort{}, "Reasoning effort", Forms.DisplayOnly{}}, editor, parent, state, groups)
    case Forms.Multiline{}: Model.field_node(Forms.FieldScene{Forms.ReasoningEffort{}, "Reasoning effort", Forms.Multiline{}}, editor, parent, state, groups)
    case Forms.StructuredText{}: Model.field_node(Forms.FieldScene{Forms.ReasoningEffort{}, "Reasoning effort", Forms.StructuredText{}}, editor, parent, state, groups)
    case Forms.MultipleChoices{}: Model.field_node(Forms.FieldScene{Forms.ReasoningEffort{}, "Reasoning effort", Forms.MultipleChoices{}}, editor, parent, state, groups)
    case Forms.PositiveInteger{}: Model.field_node(Forms.FieldScene{Forms.ReasoningEffort{}, "Reasoning effort", Forms.PositiveInteger{}}, editor, parent, state, groups)
    case Forms.DirectoryCollection{}: Model.field_node(Forms.FieldScene{Forms.ReasoningEffort{}, "Reasoning effort", Forms.DirectoryCollection{}}, editor, parent, state, groups)
    case Forms.FileCollection{}: Model.field_node(Forms.FieldScene{Forms.ReasoningEffort{}, "Reasoning effort", Forms.FileCollection{}}, editor, parent, state, groups)


def expected_action_commit(assessment: Experience.Assessment, +parent: Identity.Key, control: InteractionTypes.Control) -> SurfaceTypes.Node:
  InteractionTypes.Control{+identity, label, prominence, input, +availability} = control
  SurfaceTypes.Node{Identity.Part{parent, identity}, identity, label, Model.action_role(prominence), SurfaceTypes.ActionCommit{Model.final_assessment(availability, assessment), input, availability}, Nil{}}

type ExperienceRequirements is Type:
  ExperienceRequirements{
    effort_entry_surface: @+entry:Forms.Entry -> @+observation:Forms.Observed -> @+editor:U.Editor -> @+parent:Identity.Key -> @+state:InteractionTypes.State -> @+groups:+List<V.InputGroup> ->
      {Model.model_effort_surface(entry, observation, editor, parent, state, groups) == expected_model_effort_surface(entry, observation, editor, parent, state, groups) : SurfaceTypes.Node},
    model_decisions_complete: @+profile:String -> @+reasoning:String -> @+choices:+List<D.Profile> -> @+editor:U.Editor -> @+parent:Identity.Key -> @+state:InteractionTypes.State -> @+groups:+List<V.InputGroup> ->
      {Model.model_decisions(profile, reasoning, choices, editor, parent, state, groups) == Model.decision_surface(UX.decision(Experience.Subject{editor, Forms.ModelProfile{}}, Forms.ModelValue{profile, reasoning}, "Model", Model.admitted_model_alternatives(Experience.Subject{editor, Forms.ModelProfile{}}, Forms.ModelValue{profile, reasoning}, choices)), parent, state) <> [Model.model_effort_surface(Model.actual_entry(Forms.ReasoningEffort{}, Forms.Choice{}, Forms.ModelValue{profile, reasoning}, state), Forms.ModelValue{profile, reasoning}, editor, parent, state, groups)] : +List<SurfaceTypes.Node>},
    action_footer_groups: @+controls:+List<V.ComposerControl> -> @+action:Experience.ActionUnit -> @+assessment:Experience.Assessment -> @+submit:V.ControlDeclaration -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
      {Model.action_footer(controls, action, assessment, submit, parent, state) == SurfaceTypes.Node{Identity.Part{parent, "actions"}, "actions", "Actions", SurfaceTypes.ComposerActions{}, SurfaceTypes.Region{}, [SurfaceTypes.Node{Identity.Part{parent, "supporting-controls"}, "supporting-controls", "Supporting controls", SurfaceTypes.Toolbar{}, SurfaceTypes.Region{}, Model.supporting_controls(controls, action, parent, state)}, Model.canonical_commit(action, assessment, submit, parent, state)]} : SurfaceTypes.Node},
    supporting_binding: @+support:Experience.Support -> @+property:Experience.Property -> @+input:InteractionTypes.Input -> @+availability:V.Availability -> @+gesture:SurfaceTypes.Gesture ->
      {Model.bind(SurfaceTypes.SupportingControl{support, property, input, availability}, gesture) == expected_supporting_binding(support, input, availability, gesture) : Maybe<&2, InteractionTypes.Input>},
    supporting_available: @+support:Experience.Support -> @+property:Experience.Property -> @input:InteractionTypes.Input -> @+availability:V.Availability ->
      {Model.focusable(SurfaceTypes.SupportingControl{support, property, input, availability}) == UX.support_visible(support) && Model.available(availability) : Bool},
    supporting_submission: @+support:Experience.Support -> @+property:Experience.Property -> @+input:InteractionTypes.Input -> @+availability:V.Availability -> @+editor:U.Editor ->
      {Model.submits(SurfaceTypes.SupportingControl{support, property, input, availability}, editor) == expected_supporting_submission(support, input, availability, editor) : Bool},
    empty_model_mapping: @subject:Experience.Subject -> @observed:Forms.Observed -> {Model.admitted_model_alternatives(subject, observed, Nil{}) == Nil{} : +List<Experience.Alternative>},
    model_picker_tree: @+profile:String -> @+reasoning:String -> @+choices:+List<D.Profile> -> @+rest:+List<V.InputGroup> -> @+editor:U.Editor -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
      {Model.picker_fields(V.ModelInput{profile, reasoning, choices} <> rest, editor, parent, state) == List.append(&2, SurfaceTypes.Node, Model.model_decisions(profile, reasoning, choices, editor, parent, state, V.ModelInput{profile, reasoning, choices} <> rest), Model.picker_fields(rest, editor, parent, state)) : +List<SurfaceTypes.Node>},
    object_group_owner: @+title:String -> @+entries:+List<Forms.FieldScene> -> @+rest:+List<Forms.Section> -> @+editor:U.Editor -> @+parent:Identity.Key -> @+ordinal:Nat -> @+state:InteractionTypes.State -> @+groups:+List<V.InputGroup> ->
      {Model.sections(Forms.Section{title, entries} <> rest, editor, parent, ordinal, state, groups) == SurfaceTypes.Node{Identity.Entity{parent, "section", Nat.show(ordinal)}, "section/" ++ Nat.show(ordinal), title, SurfaceTypes.Section{}, SurfaceTypes.ObjectGroup{UX.group_owner(editor, Model.section_fields(entries))}, Model.fields(entries, editor, Identity.Entity{parent, "section", Nat.show(ordinal)}, state, groups)} <> Model.sections(rest, editor, parent, (ordinal + 1n : Nat), state, groups) : +List<SurfaceTypes.Node>},
    supporting_action: @+property:Experience.Property -> @+declaration:V.ControlDeclaration -> @+rest:+List<V.ComposerControl> -> @+action:Experience.ActionUnit -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
      {Model.supporting_controls(V.ComposerControl{property, declaration} <> rest, action, parent, state) == List.append(&2, SurfaceTypes.Node, List.append(&2, SurfaceTypes.Node, Model.supporting_control_owned(UX.property_support(action, property), property, parent, Core.control(state, declaration), state), Model.supporting_property_repair(UX.support_visible(UX.property_support(action, property)), property, parent, state)), Model.supporting_controls(rest, action, parent, state)) : +List<SurfaceTypes.Node>},
    admitted_model_mapping: @+subject:Experience.Subject -> @+observed:Forms.Observed -> @+profile:D.Profile -> @+rest:+List<D.Profile> ->
      {Model.admitted_model_alternatives(subject, observed, profile <> rest) == List.append(&2, Experience.Alternative, UX.decision_alternatives(UX.decision(subject, observed, "Model", Model.profile_alternatives([profile]))), Model.admitted_model_alternatives(subject, observed, rest)) : +List<Experience.Alternative>},
    decision_construction: @+decision:Experience.Decision -> @+parent:Identity.Key -> @state:InteractionTypes.State ->
      {Model.decision_surface(decision, parent, state) == SurfaceTypes.Node{Identity.Part{parent, UX.subject_key(UX.decision_subject(decision))}, "decision/" ++ UX.subject_key(UX.decision_subject(decision)), UX.decision_question(decision), SurfaceTypes.Section{}, SurfaceTypes.DecisionGroup{decision}, Model.decision_content(UX.decision_availability(decision), decision, Identity.Part{parent, UX.subject_key(UX.decision_subject(decision))}, state)} : SurfaceTypes.Node},
    alternative_input_selection: @+decision:Experience.Decision -> @+label:String -> @+explanation:String -> @+value:Experience.Value -> @+input:U.Input -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
      {Model.decision_choice_resolved(Some{input}, decision, Experience.Alternative{label, explanation, value}, parent, state) == Model.declared_choice(UX.selected(decision, value), explanation, V.ControlDeclaration{UX.value_key(value), label, V.Secondary{}, input, V.Available{}}, parent, state) : SurfaceTypes.Node},
    collection_member: @+collection:Experience.Collection -> @+path:String -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
      {Model.collection_member(collection, path, parent, state) == SurfaceTypes.Node{Identity.Entity{parent, "directory", path}, "directory/" ++ path, path, SurfaceTypes.Content{}, SurfaceTypes.WorkspaceMember{collection, path}, List.append(&2, SurfaceTypes.Node, Model.collection_primary_controls(UX.is_primary(collection, path), collection, path, Identity.Entity{parent, "directory", path}, state), Model.collection_control(UX.remove_member(collection, path), "directory/remove", "Remove", V.Destructive{}, Identity.Entity{parent, "directory", path}, state))} : SurfaceTypes.Node},
    canonical_commit: @+action:Experience.ActionUnit -> @+assessment:Experience.Assessment -> @+identity:String -> @+label:String -> @+prominence:V.Prominence -> @input:U.Input -> @+availability:V.Availability -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
      {Model.canonical_commit(action, assessment, V.ControlDeclaration{identity, label, prominence, input, availability}, parent, state) == expected_action_commit(assessment, parent, Core.control(state, V.ControlDeclaration{identity, label, prominence, UX.commit(action), availability})) : SurfaceTypes.Node},
    feedback_identity: @+editor:U.Editor -> @+revision:Nat -> @+reason:String -> @+parent:Identity.Key ->
      {Model.action_feedback_nodes(editor, U.Rejected{revision, reason}, parent) == [SurfaceTypes.Node{Identity.Part{parent, "feedback"}, "submission-feedback", "Submission failed", SurfaceTypes.Alert{}, SurfaceTypes.ActionFeedback{Experience.Feedback{editor, revision, reason}}, [SurfaceTypes.Node{Identity.Part{parent, "reason"}, "submission-feedback/reason", reason, SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{reason}, Nil{}}]}] : +List<SurfaceTypes.Node>},
    supporting_identity: @+support:Experience.Support -> @+property:Experience.Property -> @+parent:Identity.Key -> @+identity:String -> @+label:String -> @+prominence:V.Prominence -> @+input:InteractionTypes.Input -> @+availability:V.Availability ->
      {Model.supporting_node(True{}, support, property, parent, InteractionTypes.Control{identity, label, prominence, input, availability}) == [SurfaceTypes.Node{Identity.Part{parent, identity}, identity, label, Model.action_role(prominence), SurfaceTypes.SupportingControl{support, property, input, availability}, Nil{}}] : +List<SurfaceTypes.Node>}}

law experience_evidence:
  ExperienceRequirements

def expected_assessed_editor_scene(+revision: Nat, +body: U.Body, +feedback: U.Feedback, entry: String, +waiting: Bool, now: U32, +world: M.World()) -> V.EditorScene:
  +identity = U.owner(body)
  +assessment = UX.assessed_requirements(UX.draft_requirements(U.Draft{revision, body, feedback, entry}, waiting, world), body, revision, now, world)
  V.EditorScene{identity, revision, View.input_groups(body, world), Forms.structure(body), assessment,
    V.ControlDeclaration{"submit/" ++ U.editor_key(identity), View.submit_label(body), V.Primary{}, U.Activate{U.Submit{identity}},
      View.assessment_availability(assessment)}, feedback, waiting}

law assessed_editor_scene:
  @+revision:Nat -> @+body:U.Body -> @+feedback:U.Feedback -> @entry:String -> @+pending:+List<E.Pending> -> @+now:U32 -> @+world:M.World() ->
  {View.editor_scene(U.Draft{revision, body, feedback, entry}, pending, now, world) ==
    expected_assessed_editor_scene(revision, body, feedback, entry, E.busy(pending, U.owner(body)), now, world) : V.EditorScene}

law available_assessment_preserved:
  @+assessment:Experience.Assessment ->
  {Model.final_assessment(V.Available{}, assessment) == assessment : Experience.Assessment}

law directory_assessment_preserved:
  @+assessment:Experience.Assessment ->
  {Model.final_assessment(V.NeedsDirectoryObservation{}, assessment) == assessment : Experience.Assessment}

law unavailable_assessment_uses_actual_reason:
  @+assessment:Experience.Assessment -> @+reason:String ->
  {Model.final_assessment(V.Unavailable{reason}, assessment) == Model.restrict_different_reason(String.eq(reason, UX.assessment_reason(assessment)), assessment, reason) : Experience.Assessment}

law duplicate_assessment_reason_preserved:
  @+assessment:Experience.Assessment -> @reason:String ->
  {Model.restrict_different_reason(True{}, assessment, reason) == assessment : Experience.Assessment}

law distinct_assessment_reason_retained:
  @+assessment:Experience.Assessment -> @+reason:String ->
  {Model.restrict_different_reason(False{}, assessment, reason) == UX.restricted(assessment, reason) : Experience.Assessment}

law commit_explanation_observes_same_assessment:
  @+assessment:Experience.Assessment -> @+parent:Identity.Key -> @identity:String -> @label:String -> @prominence:V.Prominence -> @input:InteractionTypes.Input -> @+availability:V.Availability ->
  {Model.action_control_explanation(assessment, parent, InteractionTypes.Control{identity, label, prominence, input, availability}) ==
    Model.action_explanation(Model.final_assessment(availability, assessment), parent) : +List<SurfaceTypes.Node>}


law context_permission_facts:
  @+observation:Context.Observation ->
  {Model.observation_facts(observation) == "Permissions · " ++ UX.permission_value(observation) ++ " · " ++ UX.permission_detail(observation) ++ "; " ++ UX.permission_source_detail(observation) : String}

law context_summary_labels:
  @+observation:Context.Observation -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
  {Model.context_summary_node(observation, parent, state) ==
    SurfaceTypes.Node{Identity.Part{parent, "source"}, "context/source", "Execution context", SurfaceTypes.Content{}, SurfaceTypes.ContextSummary{observation},
      [SurfaceTypes.Node{Identity.Part{Identity.Part{parent, "source"}, "workspace-source"}, "context/workspace-source", "Working directories · " ++ View.execution_source_summary(observation, E.program(Core.application(state))), SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{"Working directories · " ++ View.execution_source_summary(observation, E.program(Core.application(state)))}, Nil{}},
       SurfaceTypes.Node{Identity.Part{Identity.Part{parent, "source"}, "permissions"}, "context/permissions", Model.observation_facts(observation), SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{Model.observation_facts(observation)}, Nil{}}]} : SurfaceTypes.Node}

law passive_obstruction_has_no_paragraph:
  @+obstruction:Experience.Obstruction -> @+assessment:Experience.Assessment -> @+parent:Identity.Key -> @passive:{UX.passive_obstruction(obstruction) == True{} : Bool} ->
  {Model.visible_action_obstruction_selected(UX.passive_obstruction(obstruction), obstruction, assessment, parent) == Nil{} : +List<SurfaceTypes.Node>}

law workspace_failure_is_not_global_feedback:
  @editor:U.Editor -> @revision:Nat -> @reason:String -> @parent:Identity.Key ->
  {Model.action_feedback_nodes(editor, U.WorkspaceRejected{revision, reason}, parent) == Nil{} : +List<SurfaceTypes.Node>}

law property_source_hidden_until_requested:
  @property:Experience.Property -> @parent:Identity.Key ->
  {Model.property_source_details(False{}, property, parent) == Nil{} : +List<SurfaceTypes.Node>}

law requested_property_source_is_owner_observation:
  @+property:Experience.Property -> @+parent:Identity.Key ->
  {Model.property_source_details(True{}, property, parent) == [Model.approval_fact(parent, "property-source/details", "Source", UX.property_source_description(property))] : +List<SurfaceTypes.Node>}

law property_source_uses_actual_top_layer:
  @+property:Experience.Property -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
  {Model.property_source_nodes(property, parent, state) ==
    Model.approval_fact(parent, "property-scope", "Scope", Model.property_scope(UX.property_editor(property))) <>
      Model.property_source_controls(property, parent, state) : +List<SurfaceTypes.Node>}

law property_source_controls_use_actual_top_layer:
  @+property:Experience.Property -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
  {Model.property_source_controls(property, parent, state) ==
    Model.property_source_entry_layers(E.layers(E.session(Core.application(state))), UX.property_editor(property), parent, state) : +List<SurfaceTypes.Node>}

law workspace_current_retains_context_observation:
  @+preview:Context.Preview -> @+parent:Identity.Key ->
  {Model.workspace_current_context(preview, parent) == SurfaceTypes.Node{Identity.Part{parent, "workspace/current"}, "workspace/current", UX.workspace_paths(Model.context_workspace(preview)), SurfaceTypes.Content{}, SurfaceTypes.ContextSummary{Context.DraftExecution{preview}}, Nil{}} : SurfaceTypes.Node}

law permission_scope_retains_context_observation:
  @+editor:U.Editor -> @+observation:Context.Observation -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
  {Model.permission_context_summary(editor, observation, parent, state) == SurfaceTypes.Node{Identity.Part{parent, "property-scope"}, "property-scope", Model.property_scope(editor), SurfaceTypes.Content{}, SurfaceTypes.ContextSummary{observation}, Model.property_source_controls(UX.permissions_property(editor, observation), parent, state)} : SurfaceTypes.Node}

law property_source_toggle_uses_actual_control:
  @+editor:U.Editor -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
  {Model.property_source_toggle(editor, parent, state) ==
    Model.property_source_toggle_control(E.property_source_expanded(E.layers(E.session(Core.application(state))), editor), parent,
      Core.control(state, V.ControlDeclaration{"property-source/" ++ U.editor_key(editor), "Source of these settings", V.Secondary{}, U.TogglePropertySource{editor}, V.Available{}})) : SurfaceTypes.Node}

law property_source_toggle_exposes_expansion:
  @+identity:String -> @label:String -> @+prominence:V.Prominence -> @input:InteractionTypes.Input -> @availability:V.Availability -> @expanded:Bool -> @+parent:Identity.Key ->
  {Model.property_source_toggle_control(expanded, parent, InteractionTypes.Control{identity, label, prominence, input, availability}) ==
    SurfaceTypes.Node{Identity.Part{parent, identity}, identity, label, Model.action_role(prominence), SurfaceTypes.PanelToggle{expanded, input, availability}, Nil{}} : SurfaceTypes.Node}

law model_search_retains_complete_catalog:
  @+editor:U.Editor -> @old:String -> @+groups:+List<V.InputGroup> -> @+query:String ->
  {View.search_content(V.ModelSelection{editor, old, groups}, query) == V.ModelSelection{editor, query, groups} : V.LayerContent}

law model_layer_uses_actual_activity:
  @+editor:U.Editor -> @+query:String -> @+groups:+List<V.InputGroup> -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
  {Model.layer_content(V.ModelSelection{editor, query, groups}, parent, state) ==
    Model.activity_or_content(Model.model_activity_groups(groups, editor, state), query, parent, state, Nil{}) : +List<SurfaceTypes.Node>}

law policy_layer_uses_actual_activity:
  @+editor:U.Editor -> @+groups:+List<V.InputGroup> -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
  {Model.layer_content(V.PermissionSettings{editor, groups}, parent, state) ==
    Model.activity_or_content(Model.policy_activity_groups(groups, editor, state), "", parent, state, Model.permission_menu(groups, editor, parent, state)) : +List<SurfaceTypes.Node>}

law object_editor_uses_actual_editing_activity:
  @+scene:Maybe<&2, V.EditorScene> -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
  {Model.editor(scene, parent, state) ==
    Model.activity_or_content(Model.project_activity_scene(scene, state), "", parent, state, Model.ordinary_editor(scene, parent, state)) : +List<SurfaceTypes.Node>}

law activity_layer_preserves_outside_and_escape:
  @+activity:Activity.Activity -> @+action:U.Action ->
  {Model.layer_meaning(Some{activity}, V.OutsideOrEscape{action}) ==
    SurfaceTypes.ActivityGroup{activity, InteractionTypes.ApplicationInput{E.UserInput{U.Activate{action}}}, True{}, True{}} : SurfaceTypes.Meaning}

law activity_layer_preserves_trigger_dismissal:
  @+activity:Activity.Activity -> @+action:U.Action ->
  {Model.layer_meaning(Some{activity}, V.ByTrigger{action}) ==
    SurfaceTypes.ActivityGroup{activity, InteractionTypes.ApplicationInput{E.UserInput{U.Activate{action}}}, False{}, False{}} : SurfaceTypes.Meaning}

law activity_interpreter_consumes_actual_relation_fold:
  @+activity:Activity.Activity -> @+query:String -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
  {Model.activity_content(activity, query, parent, state) ==
    List.append(&2, SurfaceTypes.Node, Model.activity_search(Activity.search_required(activity, Model.activity_current_view(activity, state)), query, parent),
      Model.activity_flatten(Activity.fold_relations(~Model.ActivityRenderContext, ~(+List<SurfaceTypes.Node>), ~Model.activity_relation_handler,
        Model.ActivityRenderContext{activity, query, Model.activity_focus_layers(Model.activity_observation_layers(E.layers(E.session(Core.application(state)))), Activity.scope(activity)), parent, state},
        Activity.relations(activity)))) : +List<SurfaceTypes.Node>}

law persistent_details_trigger_uses_actual_layer_behavior:
  @+found:Maybe<&2, Activity.Activity> -> @+task:Nat -> @+trigger:String -> @+key:Identity.Key -> @+semantic:String -> @+label:String -> @+children:+List<SurfaceTypes.Node> ->
  {Model.persistent_details_trigger([SurfaceTypes.Node{key, semantic, label, SurfaceTypes.Dialog{},
    Model.layer_meaning(found, V.ByTrigger{U.TogglePanel{U.TaskDetails{task}, trigger}}), children}]) == Some{SurfaceTypes.PersistentTrigger{task, trigger}} : Maybe<&2, SurfaceTypes.PersistentTrigger>}

law activity_row_preserves_actual_descendant:
  @role:SurfaceTypes.ActivityRowRole -> @+key:Identity.Key -> @+semantic:String -> @label:String -> @original_role:SurfaceTypes.Role -> @meaning:SurfaceTypes.Meaning -> @children:+List<SurfaceTypes.Node> ->
  {Model.activity_row(role, SurfaceTypes.Node{key, semantic, label, original_role, meaning, children}) ==
    SurfaceTypes.Node{Identity.Part{key, "activity-row"}, semantic ++ "/row", "", SurfaceTypes.Content{}, SurfaceTypes.ActivityRow{role}, [SurfaceTypes.Node{key, semantic, label, original_role, meaning, children}]} : SurfaceTypes.Node}

law hidden_activity_relation_retains_child_traversal:
  @view:Activity.RelationView -> @+children:+List<+List<SurfaceTypes.Node>> -> @activity:Activity.Activity -> @current:Activity.View -> @query:String -> @parent:Identity.Key -> @state:InteractionTypes.State ->
  {Model.activity_exposed_relation(Activity.HiddenRelation{}, view, children, activity, current, query, parent, state) == Model.activity_flatten(children) : +List<SurfaceTypes.Node>}

law selected_subject_uses_actual_canonical_candidates:
  @+subject:Experience.Subject -> @+decision:Experience.Decision -> @+activity:Activity.Activity -> @+query:String -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
  {Model.activity_coverage_present(Activity.SelectedSubject{subject, decision}, activity, query, parent, state) ==
    Model.activity_decision_candidates(activity, decision, query, Identity.Part{parent, UX.subject_key(subject)}, state) : +List<SurfaceTypes.Node>}

law required_activity_property_consumes_subject_coverage:
  @+activity:Activity.Activity -> @+property:Experience.Property -> @+query:String -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
  {Model.activity_required_property(activity, property, query, parent, state) ==
    Model.activity_coverage_nodes(Activity.information_expressions(activity, Model.activity_current_view(activity, state), Activity.coverage(activity, Model.activity_current_view(activity, state), property)), activity, query, parent, state) : +List<SurfaceTypes.Node>}

law principal_choice_has_no_independent_commit:
  @title:String -> @editor:U.Editor -> @parent:Identity.Key -> @state:InteractionTypes.State ->
  {Model.activity_view_completion_controls(Activity.ApplyAndDismiss{}, title, editor, parent, state) == Nil{} : +List<SurfaceTypes.Node>}

law requested_open_parameter_writes_only_buffer:
  @+editor:U.Editor -> @profile:String -> @reasoning:String -> @input:InteractionTypes.Input ->
  {Model.activity_requested_field_bound(Some{Forms.ReasoningEffort{}}, editor, Forms.ReasoningEffort{}, Forms.Model{profile, reasoning}, input) ==
    InteractionTypes.ApplicationInput{E.UserInput{U.WriteDecisionParameter{editor, reasoning}}} : InteractionTypes.Input}

law readonly_parameter_has_no_apply_action:
  @editor:U.Editor -> @parent:Identity.Key -> @state:InteractionTypes.State ->
  {Model.activity_parameter_apply_entry(Forms.DisplayOnly{}, editor, parent, state) == Nil{} : +List<SurfaceTypes.Node>}

law activity_projection_consumes_completion:
  @+activity:Activity.Activity -> @+query:String -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
  {Model.activity_nodes(activity, query, parent, state) ==
    List.append(&2, SurfaceTypes.Node, Model.activity_view_completion_controls(Activity.completion(activity, Model.activity_current_view(activity, state)), Model.activity_view_title(Model.activity_current_view(activity, state), Activity.property(activity)), Activity.scope(activity), parent, state),
      List.append(&2, SurfaceTypes.Node, Model.activity_content(activity, query, parent, state),
        List.append(&2, SurfaceTypes.Node, Model.activity_view_parameter_completion(Activity.completion(activity, Model.activity_current_view(activity, state)), Activity.scope(activity), parent, state), Model.activity_view_inspection_entry(Model.activity_current_view(activity, state), Activity.property(activity), parent, state)))) : +List<SurfaceTypes.Node>}


law activity_layer_label_consumes_actual_goal:
  @+activity:Activity.Activity -> @+fallback:String -> @+state:InteractionTypes.State ->
  {Model.activity_layer_label(Some{activity}, fallback, state) == Model.activity_layer_view_label(Model.activity_view_title(Model.activity_current_view(activity, state), Activity.property(activity)), Activity.purpose(activity), fallback) : String}

law choosing_goal_does_not_repeat_owner_title:
  @fallback:String ->
  {Model.activity_goal_label(Activity.Comparison{}, fallback) == "" : String}

law inspection_goal_does_not_repeat_owner_title:
  @fallback:String ->
  {Model.activity_goal_label(Activity.EffectExplanation{}, fallback) == "" : String}

law compound_goal_preserves_actual_activity_title:
  @+fallback:String ->
  {Model.activity_goal_label(Activity.ObjectEditing{}, fallback) == fallback : String}

law original_identity_remains_supporting_saved_context:
  @+name:String -> @workspace:D.Workspace -> @guidance:D.ProjectContext -> @+parent:Identity.Key ->
  {Model.activity_original_context(Some{D.Project{name, workspace, guidance}}, parent) ==
    [Model.activity_row(SurfaceTypes.SupportingRow{}, Model.approval_fact(parent, "object", "Original project", name))] : +List<SurfaceTypes.Node>}

law new_object_has_no_fabricated_original_identity:
  @parent:Identity.Key ->
  {Model.activity_original_context(None{}, parent) == Nil{} : +List<SurfaceTypes.Node>}


law readonly_activity_field_retains_subject_caption_and_value:
  @+editor:U.Editor -> @+field:Forms.Field -> @value:Forms.Observed -> @+parent:Identity.Key ->
  {Model.activity_readonly_field(Experience.Subject{editor, field}, value, parent) ==
    SurfaceTypes.Node{Identity.Part{parent, "fact/" ++ UX.subject_key(Experience.Subject{editor, field})}, "fact/" ++ UX.subject_key(Experience.Subject{editor, field}), "", SurfaceTypes.Content{}, SurfaceTypes.Region{},
      [SurfaceTypes.Node{Identity.Part{Identity.Part{parent, "fact/" ++ UX.subject_key(Experience.Subject{editor, field})}, "label"}, "fact/label", Model.activity_subject_title(Experience.Subject{editor, field}), SurfaceTypes.Content{}, SurfaceTypes.InformationText{Information.FieldLabel{}}, Nil{}},
       SurfaceTypes.Node{Identity.Part{Identity.Part{parent, "fact/" ++ UX.subject_key(Experience.Subject{editor, field})}, "value"}, "fact/value", Model.activity_subject_title(Experience.Subject{editor, field}), SurfaceTypes.Field{}, SurfaceTypes.Edit{editor, field, Forms.DisplayOnly{}, value, Nil{}}, Nil{}}]} : SurfaceTypes.Node}

law readonly_activity_fact_cannot_mutate_its_observation:
  @editor:U.Editor -> @field:Forms.Field -> @value:Forms.Observed -> @next:Forms.Value ->
  {Model.bind(SurfaceTypes.Edit{editor, field, Forms.DisplayOnly{}, value, Nil{}}, SurfaceTypes.Change{next}) == None{} : Maybe<&2,InteractionTypes.Input>}

law requested_choice_names_actual_subject:
  @+subject:Experience.Subject -> @+parent:Identity.Key ->
  {Model.activity_requested_decision_caption(True{}, subject, parent) ==
    [Model.activity_row(SurfaceTypes.SupportingRow{}, SurfaceTypes.Node{Identity.Part{parent, "subject"}, "decision/subject", Model.activity_subject_title(subject), SurfaceTypes.Content{}, SurfaceTypes.InformationText{Information.FieldLabel{}}, Nil{}})] : +List<SurfaceTypes.Node>}

law principal_choice_adds_no_requested_caption:
  @subject:Experience.Subject -> @parent:Identity.Key ->
  {Model.activity_requested_decision_caption(False{}, subject, parent) == Nil{} : +List<SurfaceTypes.Node>}

law owned_collection_actions_do_not_terminate_activity:
  @+editor:U.Editor -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
  {Model.activity_collection_editing_actions(editor, parent, state) ==
    Model.region(parent, "directory-entry-actions", "", SurfaceTypes.Toolbar{},
      [Model.directory_confirm(editor, parent, state), Model.user_action(parent, "workspace/clear", "Clear", U.EditDraft{editor, U.WriteDirectory{""}}, True{}, state), Model.directory_browse(editor, parent, state)]) : SurfaceTypes.Node}

law compound_terminal_retains_actual_commit_and_discard:
  @+action:Experience.ActionUnit -> @+assessment:Experience.Assessment -> @+submit:V.ControlDeclaration -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
  {Model.activity_compound_terminal(action, assessment, submit, parent, state) ==
    Model.activity_row(SurfaceTypes.TerminalRow{}, Model.dialog_actions(parent,
      [Model.user_action(parent, "cancel", "Cancel", U.Activate{U.ClosePanel{}}, True{}, state), Model.canonical_commit(action, assessment, submit, parent, state)])) : SurfaceTypes.Node}

law compound_action_uses_actual_completion_boundary:
  @+activity:Activity.Activity -> @+current:Activity.View -> @+action:Experience.ActionUnit -> @+assessment:Experience.Assessment -> @children:+List<+List<SurfaceTypes.Node>> -> @query:String -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
  {Model.activity_exposed_relation(Activity.CompoundContent{}, Activity.AssessedActionView{action, assessment}, children, activity, current, query, parent, state) ==
    Model.activity_compound_completion(Activity.completion(activity, current), action, assessment, parent, state) : +List<SurfaceTypes.Node>}

law returning_inspection_has_no_compound_commit:
  @action:Experience.ActionUnit -> @assessment:Experience.Assessment -> @parent:Identity.Key -> @state:InteractionTypes.State ->
  {Model.activity_compound_completion(Activity.ReturnToOwner{}, action, assessment, parent, state) == Nil{} : +List<SurfaceTypes.Node>}

law returning_inspection_has_no_parameter_apply:
  @editor:U.Editor -> @parent:Identity.Key -> @state:InteractionTypes.State ->
  {Model.activity_view_parameter_completion(Activity.ReturnToOwner{}, editor, parent, state) == Nil{} : +List<SurfaceTypes.Node>}

law open_parameter_terminal_retains_whole_value_completion:
  @+editor:U.Editor -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
  {Model.activity_parameter_apply_entry(Forms.SingleLine{}, editor, parent, state) ==
    [Model.activity_row(SurfaceTypes.TerminalRow{}, Model.user_action(parent, "parameter/apply", "Apply", U.CompleteDecisionParameter{editor}, True{}, state))] : +List<SurfaceTypes.Node>}

# Expanded information is interpreted from the same admission and observation
# used by subject coverage, not from a rendered caption or an empty string.
law activity_expression_consumes_information_requirement:
  @+expression:Activity.SubjectExpression -> @+activity:Activity.Activity -> @+query:String -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
  {Model.activity_coverage_expression(expression, activity, query, parent, state) ==
    Model.activity_coverage_information(Activity.information_status(activity, Model.activity_current_view(activity, state), Activity.property(activity), Activity.expression_subject(expression)), expression, activity, query, parent, state) : +List<SurfaceTypes.Node>}

law not_applicable_information_has_no_mutation_control:
  @+reason:String -> @+expression:Activity.SubjectExpression -> @activity:Activity.Activity -> @query:String -> @+parent:Identity.Key -> @state:InteractionTypes.State ->
  {Model.activity_coverage_information(Experience.NotApplicable{reason}, expression, activity, query, parent, state) ==
    Model.activity_information_notice(Experience.NotApplicable{reason}, Activity.expression_subject(expression), parent) : +List<SurfaceTypes.Node>}

law setting_entry_retains_subject_value_and_input:
  @+editor:U.Editor -> @+field:Forms.Field -> @+value:String -> @+parent:Identity.Key -> @state:InteractionTypes.State ->
  {Model.activity_dependency_summary(Experience.Subject{editor, field}, value, parent, state) ==
    [Model.activity_row(SurfaceTypes.DependencyRow{}, SurfaceTypes.Node{Identity.Part{parent, "decision/" ++ Forms.key(field)}, "decision/" ++ Forms.key(field), Model.activity_subject_title(Experience.Subject{editor, field}) ++ " · " ++ value, SurfaceTypes.Button{},
      SurfaceTypes.SettingEntry{Experience.Subject{editor, field}, value, InteractionTypes.ApplicationInput{E.UserInput{U.EnterDecision{editor, Forms.key(field)}}}, V.Available{}}, Nil{}})] : +List<SurfaceTypes.Node>}

law setting_entry_activates_its_original_input:
  @subject:Experience.Subject -> @value:String -> @+input:InteractionTypes.Input ->
  {Model.bind(SurfaceTypes.SettingEntry{subject, value, input, V.Available{}}, SurfaceTypes.Press{}) == Some{input} : Maybe<&2, InteractionTypes.Input>}

law setting_entry_respects_unavailability:
  @subject:Experience.Subject -> @value:String -> @input:InteractionTypes.Input -> @reason:String ->
  {Model.bind(SurfaceTypes.SettingEntry{subject, value, input, V.Unavailable{reason}}, SurfaceTypes.Press{}) == None{} : Maybe<&2, InteractionTypes.Input>}

law returning_view_constructs_navigation_and_current_identity:
  @+title:String -> @+editor:U.Editor -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
  {Model.activity_view_header(title, editor, parent, state) ==
    [Model.activity_row(SurfaceTypes.NavigationRow{}, Model.region(parent, "view/header", "", SurfaceTypes.Toolbar{},
      [Model.user_action(parent, "view/back", "Back", U.LeaveDecision{editor}, True{}, state),
       SurfaceTypes.Node{Identity.Part{parent, "view/title"}, "view/title", title, SurfaceTypes.Heading{}, SurfaceTypes.InformationText{Information.SurfaceTitle{}}, Nil{}}]))] : +List<SurfaceTypes.Node>}

law dependent_view_identity_comes_from_actual_subject:
  @+subject:Experience.Subject -> @property:Experience.Property ->
  {Model.activity_view_title(Activity.DependentView{subject}, property) == Model.activity_subject_title(subject) : String}

law inspection_view_identity_comes_from_actual_property:
  @+property:Experience.Property ->
  {Model.activity_view_title(Activity.InspectionView{None{}}, property) == Model.activity_inspection_title(property) : String}

law settings_inspection_keeps_source_details_requested:
  @+property:Experience.Property -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
  {Model.activity_requested_support(Activity.InspectionView{None{}}, property, parent, state) ==
    List.append(&2, SurfaceTypes.Node, [Model.activity_row(SurfaceTypes.SupportingRow{}, Model.approval_fact(parent, "property-scope", "Scope", Model.property_scope(UX.property_editor(property))))], Model.property_source_controls(property, parent, state)) : +List<SurfaceTypes.Node>}

law source_entry_retains_actual_owner_panel:
  @+origin:U.Panel -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
  {Model.property_source_entry_for_owner(True{}, origin, parent, state) ==
    [Model.activity_row(SurfaceTypes.InspectionRow{}, Model.user_action(parent, "source/open", "Configuration source…", U.Activate{U.OpenPanel{U.PropertySource{origin}, Identity.encode(Identity.Part{parent, "source/open"})}}, True{}, state))] : +List<SurfaceTypes.Node>}

law source_subactivity_uses_stack_return_and_owner_observation:
  @+origin:V.LayerContent -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
  {Model.layer_content(V.PropertySource{origin}, parent, state) ==
    List.append(&2, SurfaceTypes.Node, Model.activity_navigation_header("Configuration source", U.Activate{U.ClosePanel{}}, parent, state), Model.property_source_observation(Model.layer_property(origin, state), parent)) : +List<SurfaceTypes.Node>}

law source_subactivity_names_actual_request:
  @origin:V.LayerContent ->
  {View.layer_title(V.PropertySource{origin}) == "Configuration source" : String}

law source_subactivity_reads_the_same_owner_activity:
  @+activity:Activity.Activity -> @+parent:Identity.Key ->
  {Model.property_source_observation(Some{Activity.property(activity)}, parent) ==
    [Model.activity_row(SurfaceTypes.SupportingRow{}, Model.approval_fact(parent, "source/owner", "Settings", UX.property_title(Activity.property(activity)))),
     Model.activity_row(SurfaceTypes.SupportingRow{}, Model.approval_fact(parent, "source/details", "Source", UX.property_source_description(Activity.property(activity))))] : +List<SurfaceTypes.Node>}

law workspace_source_uses_actual_execution_observation:
  @config:Context.Configuration -> @+preview:Context.Preview -> @controls:V.WorkspaceControls -> @projects:+List<V.ProjectChoice> -> @reviewers:+List<D.Profile> -> @rest:+List<V.InputGroup> -> @+editor:U.Editor -> @+state:InteractionTypes.State ->
  {Model.workspace_source_property(V.ExecutionInput{config, preview, controls, projects, reviewers} <> rest, editor, state) == Some{UX.workspace_property(editor, Context.DraftExecution{preview}, E.program(Core.application(state)))} : Maybe<&2, Experience.Property>}

law workspace_layer_source_preserves_observation_owner:
  @+editor:U.Editor -> @+fields:+List<V.InputGroup> -> @+state:InteractionTypes.State ->
  {Model.layer_property(V.WorkspaceSettings{editor, fields}, state) == Model.workspace_source_property(fields, editor, state) : Maybe<&2, Experience.Property>}

law activity_layer_source_preserves_property_observation:
  @+activity:Activity.Activity ->
  {Model.layer_activity_property(Some{activity}) == Some{Activity.property(activity)} : Maybe<&2, Experience.Property>}

law source_child_preserves_owner_view_observation:
  @origin:U.Panel -> @trigger:String -> @initial:String -> @query:String -> @occurrence:Nat -> @expanded:Bool -> @field:Maybe<&2, Forms.Field> -> @buffer:Maybe<&2, String> -> @+rest:+List<E.Layer> ->
  {Model.activity_observation_layers(E.Layer{U.PropertySource{origin}, trigger, initial, query, occurrence, expanded, field, buffer} <> rest) == Model.activity_observation_layers(rest) : +List<E.Layer>}

law source_projection_replaces_only_its_real_owner:
  @+origin:U.Panel -> @+owner:U.Panel -> @trigger:String -> @initial:String -> @query:String -> @occurrence:Nat -> @expanded:Bool -> @field:Maybe<&2, Forms.Field> -> @buffer:Maybe<&2, String> -> @rest:+List<E.Layer> -> @+shown:+List<V.Layer> ->
  {View.source_origin_projection(origin, E.Layer{owner, trigger, initial, query, occurrence, expanded, field, buffer} <> rest, shown) ==
    View.source_parent_projection(String.eq(E.panel_target(origin), E.panel_target(owner)), shown) : +List<V.Layer>}

law source_projection_keeps_return_parent_out_of_the_visible_stack:
  @owner:V.Layer -> @+rest:+List<V.Layer> ->
  {View.source_parent_projection(True{}, owner <> rest) == rest : +List<V.Layer>}

law source_projection_reuses_owning_visible_anchor:
  @+owner:String -> @original:String ->
  {View.source_anchor_when(True{}, owner, original) == owner : String}

law inspection_readonly_dependency_uses_its_actual_relation:
  @owner:Experience.Decision -> @+subject:Experience.Subject -> @profile:D.Profile -> @children:+List<+List<SurfaceTypes.Node>> -> @+activity:Activity.Activity -> @current:Activity.View -> @query:String -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
  {Model.activity_exposed_relation(Activity.DependencySummary{}, Activity.FieldSpecificationView{owner, subject, Forms.DisplayOnly{}, profile}, children, activity, current, query, parent, state) ==
    Model.activity_inline_expression(subject, Activity.property(activity), parent, state) : +List<SurfaceTypes.Node>}

law inspection_root_precedes_its_retained_dependencies:
  @+decision:Experience.Decision -> @actual:+List<Activity.Relation> -> @+children:+List<+List<SurfaceTypes.Node>> -> @+activity:Activity.Activity -> @current:Activity.View -> @query:String -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
  {Model.activity_exposed_relation(Activity.DependencySummary{}, Activity.RootDecisionView{decision, actual}, children, activity, current, query, parent, state) ==
    List.append(&2, SurfaceTypes.Node, Model.activity_decision_summary(False{}, activity, decision, parent, state), Model.activity_flatten(children)) : +List<SurfaceTypes.Node>}
