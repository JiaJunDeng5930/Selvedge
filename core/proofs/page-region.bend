import ../page-region-laws.bend as Rule
import Base
import ../composition.bend as Composition
import ../interface.bend as Interface
import ../ui-world.bend as View
import ../SYSTEM.bend as Core
import ../user-conversation.bend as Conversation
import ../user-experience.bend as Experience
import ../../bendlib/domain.bend as D

# Only direct page regions participate; an entry's ordinary heading is never promoted.
def page_sequence(+page: View.Page, +parent: String, +state: Core.State) ->
  {Rule.observed_regions(Interface.page_contents(page, parent, state)) == Rule.required_regions(page) : +List<Composition.PositionedRegion>}:
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

def page_only_regions(+page: View.Page, +parent: String, +state: Core.State) ->
  {Rule.only_regions(Interface.page_contents(page, parent, state)) == True{} : Bool}:
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

def task_title(+value: View.TaskScene, +parent: String, +state: Core.State) ->
  {Rule.find_region(Interface.page_contents(View.TaskPage{value}, parent, state), Composition.ConversationTitle{}) ==
    Some{[Interface.region(Rule.task_title_key(value, parent), "heading", Rule.task_title_text(value), Interface.Heading{}, Nil{})]} : Maybe<&2, +List<Interface.Node>>}:
  match value:
    case View.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, approvals, reading, latest}, previews, composer, details, View.TaskActions{detail, overflow}}: {==}

def project_title(+value: View.ProjectScene, +parent: String, +state: Core.State) ->
  {Rule.find_region(Interface.page_contents(View.ProjectPage{value}, parent, state), Composition.ProjectTitle{}) ==
    Some{[Interface.region(parent, "heading", Rule.project_title_text(value), Interface.Heading{}, Nil{})]} : Maybe<&2, +List<Interface.Node>>}:
  match value:
    case View.ProjectScene{id, name, D.Workspace{roots, primary}, guidance, tasks, actions}: {==}

def layer_title_evidence() -> Rule.LayerTitleRequirements:
  Rule.LayerTitleRequirements{
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

def collapsed_assembly(+content: Core.Scene, +state: Core.State,
  collapsed: {Rule.content_navigation_placement(content) == View.CollapsedNavigation{} : View.NavigationPlacement}) ->
  {Rule.navigation_head(Rule.surface_base(Interface.assemble(content, state))) ==
    Rule.navigation_head(Interface.collapsed_navigation_toggle(Rule.content_navigation(content), state)) : Interface.Node}:
  match content:
    case Core.Scene{View.Scene{View.Navigation{+expanded, +create, +destinations, +projects, +tasks, +toggle}, +main, +layers, View.Arrangement{+placement}, +attention}, +settings, +transfers, +preview, +code, directory_picker}:
      +nav: View.Navigation = View.Navigation{expanded, create, destinations, projects, tasks, toggle}
      Equal.cong(View.NavigationPlacement, Interface.Node,
        (position => Rule.navigation_head(Rule.surface_base(Interface.assemble(Core.Scene{View.Scene{nav, main, layers,
          View.Arrangement{position}, attention}, settings, transfers, preview, code, directory_picker}, state)))),
        placement, View.CollapsedNavigation{}, collapsed)

def page_payload(+page: View.Page, +state: Core.State) ->
  {Interface.page(page, state) == Interface.Node{"/main", "main", "Content", Interface.Main{}, Interface.PageContext{Rule.owned_page_context(page)}, Interface.page_contents(page, "/main", state)} : Interface.Node}:
  match page:
    case View.StartPage{composer}: {==}
    case View.TaskPage{View.TaskScene{id, title, status, context, timeline, previews, input, details, actions}}: {==}
    case View.ProjectPage{project}: {==}
    case View.ProjectsPage{projects, create}: {==}
    case View.BoardPage{filter, columns, create, working, settings, filters, archive}: {==}
    case View.AgentsPage{agents, create}: {==}
    case View.MissingObject{message}: {==}

def Rule.evidence():
  Rule.Requirements{page => state => page_payload(page, state), +toggle => expanded => create => destinations => projects => tasks => +state => {==}, collapsed_assembly,
    layer_title_evidence(),
    +kind => +content => +initial => +restore => +close => +state => {==},
    +kind => +content => +first => +second => +restore => +close => +state => {==},
    +kind => +content => +initial => +restore => +close => +state => {==},
    page => parent => state => page_sequence(page, parent, state),
    page => parent => state => page_only_regions(page, parent, state),
    +projects => +create => +parent => +state => {==},
    +agents => +create => +parent => +state => {==},
    +filter => +columns => +create => working => +settings => +filters => +archive => +parent => +state => {==},
    +heading => +summary => +context => +project => +choose => +parent => +state => {==},
    value => parent => state => task_title(value, parent, state),
    value => parent => state => project_title(value, parent, state),
    region => position => gesture => {==},
    +parent => +region => +position => +children => {==},
    +parent => +region => +position => +children => {==}}
