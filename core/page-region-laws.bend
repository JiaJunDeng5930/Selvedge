import Base
import ./composition.bend as Composition
import ./interface.bend as Interface
import ./ui-world.bend as View
import ./user-input.bend as U
import ./form-fields.bend as Forms
import ./SYSTEM.bend as Core
import ./user-conversation.bend as Conversation
import ./user-experience.bend as Experience
import ./client-services.bend as Services
import ./user-context.bend as Context
import ../BOARD.bend as B
import ../bendlib/domain.bend as D

# Only direct page regions participate; an entry's ordinary heading is never promoted.
def observed_regions(nodes: +List<Interface.Node>) -> +List<Composition.PositionedRegion>:
  match nodes:
    case Nil{}: Nil{}
    case Con{Interface.Node{key, semantic, label, role, Interface.PageRegion{region, position}, children}, rest}:
      Composition.PositionedRegion{position, region} <> observed_regions(rest)
    case Con{node, rest}: observed_regions(rest)

def required_regions(page: View.Page) -> +List<Composition.PositionedRegion>:
  Composition.ordered_regions(Composition.structure(Composition.recipe(View.page_composition(page))))

def page_sequence(+page: View.Page, +parent: String, +state: Core.State) ->
  {observed_regions(Interface.page_contents(page, parent, state)) == required_regions(page) : +List<Composition.PositionedRegion>}:
  match page:
    case View.StartPage{None{}}:
      Core.State{Experience.Application{world, session}, services} = state
      {==}
    case View.StartPage{Some{scene}}:
      Core.State{Experience.Application{world, session}, services} = state
      {==}
    case View.TaskPage{View.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Nil{}, reading, None{}}, previews, None{}, details, View.TaskActions{detail, overflow}}}: {==}
    case View.TaskPage{View.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Nil{}, reading, Some{input}}, previews, None{}, details, View.TaskActions{detail, overflow}}}: {==}
    case View.TaskPage{View.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Con{first, rest}, reading, None{}}, previews, None{}, details, View.TaskActions{detail, overflow}}}: {==}
    case View.TaskPage{View.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Con{first, rest}, reading, Some{input}}, previews, None{}, details, View.TaskActions{detail, overflow}}}: {==}
    case View.TaskPage{View.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Nil{}, reading, None{}}, previews, Some{scene}, details, View.TaskActions{detail, overflow}}}: {==}
    case View.TaskPage{View.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Nil{}, reading, Some{input}}, previews, Some{scene}, details, View.TaskActions{detail, overflow}}}: {==}
    case View.TaskPage{View.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Con{first, rest}, reading, None{}}, previews, Some{scene}, details, View.TaskActions{detail, overflow}}}: {==}
    case View.TaskPage{View.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Con{first, rest}, reading, Some{input}}, previews, Some{scene}, details, View.TaskActions{detail, overflow}}}: {==}
    case View.ProjectPage{View.ProjectScene{id, name, D.Workspace{roots, primary}, guidance, tasks, actions}}: {==}
    case View.ProjectsPage{projects, create}: {==}
    case View.BoardPage{filter, columns, create, working, settings, filters, archive}: {==}
    case View.AgentsPage{agents, create}: {==}
    case View.MissingObject{message}: {==}

def only_regions(nodes: +List<Interface.Node>) -> Bool:
  match nodes:
    case Nil{}: True{}
    case Con{Interface.Node{key, semantic, label, role, Interface.PageRegion{region, position}, children}, rest}: only_regions(rest)
    case Con{node, rest}: False{}

def page_only_regions(+page: View.Page, +parent: String, +state: Core.State) ->
  {only_regions(Interface.page_contents(page, parent, state)) == True{} : Bool}:
  match page:
    case View.StartPage{None{}}:
      Core.State{Experience.Application{world, session}, services} = state
      {==}
    case View.StartPage{Some{scene}}:
      Core.State{Experience.Application{world, session}, services} = state
      {==}
    case View.TaskPage{View.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Nil{}, reading, None{}}, previews, None{}, details, View.TaskActions{detail, overflow}}}: {==}
    case View.TaskPage{View.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Nil{}, reading, Some{input}}, previews, None{}, details, View.TaskActions{detail, overflow}}}: {==}
    case View.TaskPage{View.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Con{first, rest}, reading, None{}}, previews, None{}, details, View.TaskActions{detail, overflow}}}: {==}
    case View.TaskPage{View.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Con{first, rest}, reading, Some{input}}, previews, None{}, details, View.TaskActions{detail, overflow}}}: {==}
    case View.TaskPage{View.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Nil{}, reading, None{}}, previews, Some{scene}, details, View.TaskActions{detail, overflow}}}: {==}
    case View.TaskPage{View.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Nil{}, reading, Some{input}}, previews, Some{scene}, details, View.TaskActions{detail, overflow}}}: {==}
    case View.TaskPage{View.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Con{first, rest}, reading, None{}}, previews, Some{scene}, details, View.TaskActions{detail, overflow}}}: {==}
    case View.TaskPage{View.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Con{first, rest}, reading, Some{input}}, previews, Some{scene}, details, View.TaskActions{detail, overflow}}}: {==}
    case View.ProjectPage{View.ProjectScene{id, name, D.Workspace{roots, primary}, guidance, tasks, actions}}: {==}
    case View.ProjectsPage{projects, create}: {==}
    case View.BoardPage{filter, columns, create, working, settings, filters, archive}: {==}
    case View.AgentsPage{agents, create}: {==}
    case View.MissingObject{message}: {==}

def region_children(node: Interface.Node) -> +List<Interface.Node>:
  Interface.Node{key, semantic, label, role, meaning, children} = node
  children

def region_key(node: Interface.Node) -> String:
  Interface.Node{key, semantic, label, role, meaning, children} = node
  key

def region_keeps_children(+parent: String, +region: Composition.Region, +position: Composition.Position, +children: +List<Interface.Node>) ->
  {region_children(Interface.page_region(parent, region, position, children)) == children : +List<Interface.Node>}:
  {==}

def region_has_key(+parent: String, +region: Composition.Region, +position: Composition.Position, +children: +List<Interface.Node>) ->
  {region_key(Interface.page_region(parent, region, position, children)) == parent ++ "/region/" ++ Composition.region_name(region) : String}:
  {==}

def select_region(matches: Bool, children: +List<Interface.Node>, rest: Maybe<&2, +List<Interface.Node>>) -> Maybe<&2, +List<Interface.Node>>:
  match matches:
    case True{}: Some{children}
    case False{}: rest

def find_region(nodes: +List<Interface.Node>, +region: Composition.Region) -> Maybe<&2, +List<Interface.Node>>:
  match nodes:
    case Nil{}: None{}
    case Con{Interface.Node{key, semantic, label, role, Interface.PageRegion{part, position}, children}, rest}:
      select_region(String.eq(Composition.region_name(part), Composition.region_name(region)), children, find_region(rest, region))
    case Con{node, rest}: find_region(rest, region)

def projects_title(+projects: +List<View.ProjectScene>, +create: View.ControlDeclaration, +parent: String, +state: Core.State) ->
  {find_region(Interface.page_contents(View.ProjectsPage{projects, create}, parent, state), Composition.CollectionTitle{}) ==
    Some{[Interface.region(parent, "heading", "Projects", Interface.Heading{}, Nil{})]} : Maybe<&2, +List<Interface.Node>>}:
  {==}

def agents_title(+agents: +List<View.AgentScene>, +create: View.ControlDeclaration, +parent: String, +state: Core.State) ->
  {find_region(Interface.page_contents(View.AgentsPage{agents, create}, parent, state), Composition.CollectionTitle{}) ==
    Some{[Interface.region(parent, "heading", "Agents", Interface.Heading{}, Nil{})]} : Maybe<&2, +List<Interface.Node>>}:
  {==}

def board_title(+filter: B.Filter, +columns: +List<View.BoardColumn>, +create: View.ControlDeclaration, working: Nat,
  +settings: View.ControlDeclaration, +filters: View.ControlDeclaration, +archive: View.ControlDeclaration, +parent: String, +state: Core.State) ->
  {find_region(Interface.page_contents(View.BoardPage{filter, columns, create, working, settings, filters, archive}, parent, state), Composition.BoardTitle{}) ==
    Some{[Interface.region(parent, "heading", "Board", Interface.Heading{}, Nil{})]} : Maybe<&2, +List<Interface.Node>>}:
  {==}

def creation_introduction_title(+heading: String, +summary: String, +context: Maybe<&2, Context.Preview>, +project: Maybe<&2, View.ProjectChoice>, +choose: View.ControlDeclaration, +parent: String, +state: Core.State) ->
  {find_region(Interface.creation_introduction_nodes(View.CreationIntroduction{heading, summary, context, project, choose}, parent, state), Composition.CreationIntroduction{}) ==
    Some{[Interface.Node{parent ++ "/creation/introduction/creation/title", "creation/title", heading, Interface.Heading{}, Interface.ReadOnly{heading}, Nil{}}, Interface.creation_project_node(View.CreationIntroduction{heading, summary, context, project, choose}, parent, state)]} : Maybe<&2, +List<Interface.Node>>}:
  {==}

def task_title_text(value: View.TaskScene) -> String:
  View.TaskScene{id, title, status, context, timeline, previews, composer, details, actions} = value
  title

def task_title_key(value: View.TaskScene, parent: String) -> String:
  View.TaskScene{id, title, status, context, timeline, previews, composer, details, actions} = value
  parent ++ "/task/" ++ Nat.show(id)

def task_title(+value: View.TaskScene, +parent: String, +state: Core.State) ->
  {find_region(Interface.page_contents(View.TaskPage{value}, parent, state), Composition.ConversationTitle{}) ==
    Some{[Interface.region(task_title_key(value, parent), "heading", task_title_text(value), Interface.Heading{}, Nil{})]} : Maybe<&2, +List<Interface.Node>>}:
  match value:
    case View.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, approvals, reading, latest}, previews, composer, details, View.TaskActions{detail, overflow}}: {==}

def project_title_text(value: View.ProjectScene) -> String:
  View.ProjectScene{id, name, workspace, guidance, tasks, actions} = value
  name

def project_title(+value: View.ProjectScene, +parent: String, +state: Core.State) ->
  {find_region(Interface.page_contents(View.ProjectPage{value}, parent, state), Composition.ProjectTitle{}) ==
    Some{[Interface.region(parent, "heading", project_title_text(value), Interface.Heading{}, Nil{})]} : Maybe<&2, +List<Interface.Node>>}:
  match value:
    case View.ProjectScene{id, name, D.Workspace{roots, primary}, guidance, tasks, actions}: {==}

def passive_region(region: Composition.Region, position: Composition.Position, gesture: Interface.Gesture) ->
  {Interface.bind(Interface.PageRegion{region, position}, gesture) == None{} : Maybe<&2, Core.Input>}:
  {==}

def layer_label(nodes: +List<Interface.Node>) -> Maybe<&2, String>:
  match nodes:
    case Nil{}: None{}
    case Con{Interface.Node{key, semantic, label, role, meaning, children}, rest}: Some{label}

def layer_semantic(nodes: +List<Interface.Node>) -> Maybe<&2, String>:
  match nodes:
    case Nil{}: None{}
    case Con{Interface.Node{key, semantic, label, role, meaning, children}, rest}: Some{semantic}

def single_layer_title(+kind: View.LayerKind, +content: View.LayerContent, +initial: String, +restore: String,
  +close: View.ControlDeclaration, +state: Core.State) ->
  {layer_label(Interface.layers([View.Layer{kind, content, initial, restore, close}], state)) == Some{View.layer_title(content)} : Maybe<&2, String>}:
  {==}

def layer_title_ignores_attention(+kind: View.LayerKind, +content: View.LayerContent, +first: String, +second: String,
  +restore: String, +close: View.ControlDeclaration, +state: Core.State) ->
  {layer_label(Interface.layers([View.Layer{kind, content, first, restore, close}], state)) ==
    layer_label(Interface.layers([View.Layer{kind, content, second, restore, close}], state)) : Maybe<&2, String>}:
  {==}

def single_layer_semantic(+kind: View.LayerKind, +content: View.LayerContent, +initial: String, +restore: String,
  +close: View.ControlDeclaration, +state: Core.State) ->
  {layer_semantic(Interface.layers([View.Layer{kind, content, initial, restore, close}], state)) == Some{initial} : Maybe<&2, String>}:
  {==}

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
    actions: @actions:+List<View.ControlDeclaration> -> {View.layer_title(View.ObjectActions{actions}) == "Actions" : String},
    archived: @cards:+List<View.CardScene> -> {View.layer_title(View.ArchivedCards{cards}) == "Archived cards" : String},
    board_settings: @automatic:Bool -> @selected:String -> @profiles:+List<D.Profile> -> @automation:View.ControlDeclaration ->
      {View.layer_title(View.BoardSettings{automatic, selected, profiles, automation}) == "看板设置" : String},
    board_filters: @filter:B.Filter -> {View.layer_title(View.BoardFilters{filter}) == "筛选任务" : String},
    unavailable: {View.layer_title(View.ObjectEditor{None{}}) == "Editor unavailable" : String},
    editor: @identity:U.Editor -> @revision:Nat -> @groups:+List<View.InputGroup> -> @sections:+List<Forms.Section> -> @submit:View.ControlDeclaration -> @feedback:U.Feedback -> @pending:Bool -> {View.layer_title(View.ObjectEditor{Some{View.EditorScene{identity, revision, groups, sections, submit, feedback, pending}}}) == View.editor_title(identity) : String},
    workspace: @editor:U.Editor -> @fields:+List<View.InputGroup> -> {View.layer_title(View.WorkspaceSettings{editor, fields}) == "Working directories" : String},
    permissions: @editor:U.Editor -> @fields:+List<View.InputGroup> -> {View.layer_title(View.PermissionSettings{editor, fields}) == "Permissions" : String},
    committed: @context:Maybe<&2, Context.EffectiveContext> -> {View.layer_title(View.CommittedContext{context}) == "Execution context" : String},
    models: @editor:U.Editor -> @query:String -> @fields:+List<View.InputGroup> -> {View.layer_title(View.ModelSelection{editor, query, fields}) == "Choose model" : String},
    delivery: @editor:U.Editor -> @fields:+List<View.InputGroup> -> {View.layer_title(View.DeliverySelection{editor, fields}) == "Delivery options" : String},
    details: @task:Maybe<&2, View.TaskScene> -> {View.layer_title(View.ExecutionDetails{task}) == "Task details" : String},
    confirmation: @title:String -> @confirm:View.ControlDeclaration -> @cancel:View.ControlDeclaration -> {View.layer_title(View.Confirmation{title, confirm, cancel}) == title : String}
  }

def layer_title_evidence() -> LayerTitleRequirements:
  LayerTitleRequirements{
    {==},
    task => {==},
    {==},
    id => {==},
    {==},
    id => {==},
    {==},
    id => {==},
    task => {==},
    task => {==},
    actions => {==},
    cards => {==},
    automatic => selected => profiles => automation => {==},
    filter => {==},
    {==},
    identity => revision => groups => sections => submit => feedback => pending => {==},
    editor => fields => {==},
    editor => fields => {==},
    context => {==},
    editor => query => fields => {==},
    editor => fields => {==},
    task => {==},
    title => confirm => cancel => {==}}

def surface_base(value: Interface.Surface) -> +List<Interface.Node>:
  Interface.Surface{content, base, overlays, active} = value
  base

def navigation_head(values: +List<Interface.Node>) -> Interface.Node:
  match values:
    case Con{node, rest}: node
    case Nil{}: Interface.Node{"", "", "", Interface.Section{}, Interface.Region{}, Nil{}}

def content_navigation(value: Core.Scene) -> View.Navigation:
  Core.Scene{View.Scene{nav, main, layers, arrangement, attention}, settings, transfers, preview, code} = value
  nav

def content_navigation_placement(value: Core.Scene) -> View.NavigationPlacement:
  Core.Scene{View.Scene{nav, main, layers, View.Arrangement{placement, page}, attention}, settings, transfers, preview, code} = value
  placement

def collapsed_navigation_single(+toggle: View.ControlDeclaration, expanded: Bool, create: View.ControlDeclaration,
  destinations: +List<View.ControlDeclaration>, projects: +List<View.ProjectEntry>, tasks: +List<View.TaskEntry>, +state: Core.State) ->
  {Interface.base_navigation_at(View.CollapsedNavigation{}, View.Navigation{expanded, create, destinations, projects, tasks, toggle}, state) ==
    [Interface.declared("/navigation", toggle, state)] : +List<Interface.Node>}:
  {==}

def collapsed_assembly(+content: Core.Scene, +state: Core.State,
  collapsed: {content_navigation_placement(content) == View.CollapsedNavigation{} : View.NavigationPlacement}) ->
  {navigation_head(surface_base(Interface.assemble(content, state))) ==
    navigation_head(Interface.collapsed_navigation_toggle(content_navigation(content), state)) : Interface.Node}:
  match content:
    case Core.Scene{View.Scene{View.Navigation{+expanded, +create, +destinations, +projects, +tasks, +toggle}, +main, +layers, View.Arrangement{+placement, +page}, +attention}, +settings, +transfers, +preview, +code}:
      +nav: View.Navigation = View.Navigation{expanded, create, destinations, projects, tasks, toggle}
      Equal.cong(View.NavigationPlacement, Interface.Node,
        (position => navigation_head(surface_base(Interface.assemble(Core.Scene{View.Scene{nav, main, layers,
          View.Arrangement{position, page}, attention}, settings, transfers, preview, code}, state)))),
        placement, View.CollapsedNavigation{}, collapsed)

type Requirements is Type:
  Requirements{
    collapsed_navigation_single: @+toggle: View.ControlDeclaration -> @expanded: Bool -> @create: View.ControlDeclaration -> @destinations: +List<View.ControlDeclaration> -> @projects: +List<View.ProjectEntry> -> @tasks: +List<View.TaskEntry> -> @+state: Core.State -> {Interface.base_navigation_at(View.CollapsedNavigation{}, View.Navigation{expanded, create, destinations, projects, tasks, toggle}, state) ==
    [Interface.declared("/navigation", toggle, state)] : +List<Interface.Node>},
    collapsed_assembly: @+content: Core.Scene -> @+state: Core.State -> @collapsed: {content_navigation_placement(content) == View.CollapsedNavigation{} : View.NavigationPlacement} -> {navigation_head(surface_base(Interface.assemble(content, state))) ==
    navigation_head(Interface.collapsed_navigation_toggle(content_navigation(content), state)) : Interface.Node},

    layer_titles: LayerTitleRequirements,
    layer_name: @+kind:View.LayerKind -> @+content:View.LayerContent -> @+initial:String -> @+restore:String -> @+close:View.ControlDeclaration -> @+state:Core.State ->
      {layer_label(Interface.layers([View.Layer{kind, content, initial, restore, close}], state)) == Some{View.layer_title(content)} : Maybe<&2, String>},
    attention_independent: @+kind:View.LayerKind -> @+content:View.LayerContent -> @+first:String -> @+second:String -> @+restore:String -> @+close:View.ControlDeclaration -> @+state:Core.State ->
      {layer_label(Interface.layers([View.Layer{kind, content, first, restore, close}], state)) ==
        layer_label(Interface.layers([View.Layer{kind, content, second, restore, close}], state)) : Maybe<&2, String>},
    attention_identity: @+kind:View.LayerKind -> @+content:View.LayerContent -> @+initial:String -> @+restore:String -> @+close:View.ControlDeclaration -> @+state:Core.State ->
      {layer_semantic(Interface.layers([View.Layer{kind, content, initial, restore, close}], state)) == Some{initial} : Maybe<&2, String>},
    page_sequence: @+page:View.Page -> @+parent:String -> @+state:Core.State ->
      {observed_regions(Interface.page_contents(page, parent, state)) == required_regions(page) : +List<Composition.PositionedRegion>},
    only_regions: @+page:View.Page -> @+parent:String -> @+state:Core.State ->
      {only_regions(Interface.page_contents(page, parent, state)) == True{} : Bool},
    projects_title: @+projects:+List<View.ProjectScene> -> @+create:View.ControlDeclaration -> @+parent:String -> @+state:Core.State ->
      {find_region(Interface.page_contents(View.ProjectsPage{projects, create}, parent, state), Composition.CollectionTitle{}) ==
        Some{[Interface.region(parent, "heading", "Projects", Interface.Heading{}, Nil{})]} : Maybe<&2, +List<Interface.Node>>},
    agents_title: @+agents:+List<View.AgentScene> -> @+create:View.ControlDeclaration -> @+parent:String -> @+state:Core.State ->
      {find_region(Interface.page_contents(View.AgentsPage{agents, create}, parent, state), Composition.CollectionTitle{}) ==
        Some{[Interface.region(parent, "heading", "Agents", Interface.Heading{}, Nil{})]} : Maybe<&2, +List<Interface.Node>>},
    board_title: @+filter:B.Filter -> @+columns:+List<View.BoardColumn> -> @+create:View.ControlDeclaration -> @working:Nat ->
      @+settings:View.ControlDeclaration -> @+filters:View.ControlDeclaration -> @+archive:View.ControlDeclaration -> @+parent:String -> @+state:Core.State ->
      {find_region(Interface.page_contents(View.BoardPage{filter, columns, create, working, settings, filters, archive}, parent, state), Composition.BoardTitle{}) ==
        Some{[Interface.region(parent, "heading", "Board", Interface.Heading{}, Nil{})]} : Maybe<&2, +List<Interface.Node>>},
    creation_title: @+heading:String -> @+summary:String -> @+context:Maybe<&2, Context.Preview> -> @+project:Maybe<&2, View.ProjectChoice> -> @+choose:View.ControlDeclaration -> @+parent:String -> @+state:Core.State ->
      {find_region(Interface.creation_introduction_nodes(View.CreationIntroduction{heading, summary, context, project, choose}, parent, state), Composition.CreationIntroduction{}) ==
        Some{[Interface.Node{parent ++ "/creation/introduction/creation/title", "creation/title", heading, Interface.Heading{}, Interface.ReadOnly{heading}, Nil{}}, Interface.creation_project_node(View.CreationIntroduction{heading, summary, context, project, choose}, parent, state)]} : Maybe<&2, +List<Interface.Node>>},
    task_title: @+value:View.TaskScene -> @+parent:String -> @+state:Core.State ->
      {find_region(Interface.page_contents(View.TaskPage{value}, parent, state), Composition.ConversationTitle{}) ==
        Some{[Interface.region(task_title_key(value, parent), "heading", task_title_text(value), Interface.Heading{}, Nil{})]} : Maybe<&2, +List<Interface.Node>>},
    project_title: @+value:View.ProjectScene -> @+parent:String -> @+state:Core.State ->
      {find_region(Interface.page_contents(View.ProjectPage{value}, parent, state), Composition.ProjectTitle{}) ==
        Some{[Interface.region(parent, "heading", project_title_text(value), Interface.Heading{}, Nil{})]} : Maybe<&2, +List<Interface.Node>>},
    passive: @region:Composition.Region -> @position:Composition.Position -> @gesture:Interface.Gesture ->
      {Interface.bind(Interface.PageRegion{region, position}, gesture) == None{} : Maybe<&2, Core.Input>},
    children: @+parent:String -> @+region:Composition.Region -> @+position:Composition.Position -> @+nodes:+List<Interface.Node> ->
      {region_children(Interface.page_region(parent, region, position, nodes)) == nodes : +List<Interface.Node>},
    identity: @+parent:String -> @+region:Composition.Region -> @+position:Composition.Position -> @+nodes:+List<Interface.Node> ->
      {region_key(Interface.page_region(parent, region, position, nodes)) == parent ++ "/region/" ++ Composition.region_name(region) : String}
  }

def evidence() -> Requirements:
  Requirements{collapsed_navigation_single, collapsed_assembly,
    layer_title_evidence(),
    kind => content => initial => restore => close => state => single_layer_title(kind, content, initial, restore, close, state),
    kind => content => first => second => restore => close => state => layer_title_ignores_attention(kind, content, first, second, restore, close, state),
    kind => content => initial => restore => close => state => single_layer_semantic(kind, content, initial, restore, close, state),
    page => parent => state => page_sequence(page, parent, state),
    page => parent => state => page_only_regions(page, parent, state),
    projects => create => parent => state => projects_title(projects, create, parent, state),
    agents => create => parent => state => agents_title(agents, create, parent, state),
    filter => columns => create => working => settings => filters => archive => parent => state => board_title(filter, columns, create, working, settings, filters, archive, parent, state),
    heading => summary => context => project => choose => parent => state => creation_introduction_title(heading, summary, context, project, choose, parent, state),
    value => parent => state => task_title(value, parent, state),
    value => parent => state => project_title(value, parent, state),
    region => position => gesture => passive_region(region, position, gesture),
    parent => region => position => children => region_keeps_children(parent, region, position, children),
    parent => region => position => children => region_has_key(parent, region, position, children)}
