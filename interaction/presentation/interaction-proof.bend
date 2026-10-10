import Base
import ../../harness/DOMAIN.bend as D
import ../services/CONTEXT.bend as Context
import ./CONTRACT.bend as Rule
import ../../bendlib/json.bend as J
import ../conversation/CODE.bend as Code
import ../services/MODEL.bend as Services
import ../../features/board/MODEL.bend as B
import ../INPUT.bend as U
import ../../bendlib/association-map.bend as Finite
import ../session/MODEL.bend as E
import ../STATE.bend as Core
import ../TYPES.bend as InteractionTypes
import ../conversation/OUTPUT.bend as Live
import ./MODEL.bend as V
import ../IDENTITY.bend as Identity
import ./PROGRAM.bend as Model
import ./COMPOSITION.bend as Composition
import ../conversation/MODEL.bend as Conversation
import ./SURFACE.bend as SurfaceTypes
import ../MODEL.bend as ProductUI
import ./VIEW.bend as View
import ../../harness/MODEL.bend as M
import ../../features/board/STATE.bend as Board

def settings_fields_without_project(+previous:Maybe<&2, D.Workspace>, +sandbox:Maybe<&2, D.Sandbox>,
  +approval:Maybe<&2, Context.ApprovalChoice>, +workspace:D.Workspace, +guidance:D.ProjectContext) ->
  {Rule.settings_fields(Context.observed_settings(Context.Configuration{Context.EnvironmentDefaults{}, previous, sandbox, approval},
      Context.DirectoryObservation{workspace, guidance})) ==
    Rule.SettingsFields{D.workspace_json(workspace), D.project_json(guidance),
      J.get(Context.settings(Context.Configuration{Context.EnvironmentDefaults{}, previous, sandbox, approval}), "project_id"),
      J.get(Context.settings(Context.Configuration{Context.EnvironmentDefaults{}, previous, sandbox, approval}), "sandbox"),
      J.get(Context.settings(Context.Configuration{Context.EnvironmentDefaults{}, previous, sandbox, approval}), "approval")} : Rule.SettingsFields}:
  match previous sandbox approval:
    case None{} None{} None{}: {==}
    case None{} None{} Some{choice}: {==}
    case None{} Some{sandbox_value} None{}: {==}
    case None{} Some{sandbox_value} Some{choice}: {==}
    case Some{previous_value} None{} None{}: {==}
    case Some{previous_value} None{} Some{choice}: {==}
    case Some{previous_value} Some{sandbox_value} None{}: {==}
    case Some{previous_value} Some{sandbox_value} Some{choice}: {==}

def settings_fields_with_project(project:Nat, +previous:Maybe<&2, D.Workspace>, +sandbox:Maybe<&2, D.Sandbox>,
  +approval:Maybe<&2, Context.ApprovalChoice>, +workspace:D.Workspace, +guidance:D.ProjectContext) ->
  {Rule.settings_fields(Context.observed_settings(Context.Configuration{Context.ProjectDefaults{project}, previous, sandbox, approval},
      Context.DirectoryObservation{workspace, guidance})) ==
    Rule.SettingsFields{D.workspace_json(workspace), D.project_json(guidance),
      J.get(Context.settings(Context.Configuration{Context.ProjectDefaults{project}, previous, sandbox, approval}), "project_id"),
      J.get(Context.settings(Context.Configuration{Context.ProjectDefaults{project}, previous, sandbox, approval}), "sandbox"),
      J.get(Context.settings(Context.Configuration{Context.ProjectDefaults{project}, previous, sandbox, approval}), "approval")} : Rule.SettingsFields}:
  match previous sandbox approval:
    case None{} None{} None{}: {==}
    case None{} None{} Some{choice}: {==}
    case None{} Some{sandbox_value} None{}: {==}
    case None{} Some{sandbox_value} Some{choice}: {==}
    case Some{previous_value} None{} None{}: {==}
    case Some{previous_value} None{} Some{choice}: {==}
    case Some{previous_value} Some{sandbox_value} None{}: {==}
    case Some{previous_value} Some{sandbox_value} Some{choice}: {==}

def settings_projection(+config:Context.Configuration, +workspace:D.Workspace, +guidance:D.ProjectContext) ->
  Rule.settings_observations_law(config, workspace, guidance):
  match config:
    case Context.Configuration{Context.EnvironmentDefaults{}, previous, sandbox, approval}:
      settings_fields_without_project(previous, sandbox, approval, workspace, guidance)
    case Context.Configuration{Context.ParentTask{_}, previous, sandbox, approval}:
      settings_fields_without_project(previous, sandbox, approval, workspace, guidance)
    case Context.Configuration{Context.ProjectDefaults{project}, previous, sandbox, approval}:
      settings_fields_with_project(project, previous, sandbox, approval, workspace, guidance)
    case Context.Configuration{Context.ProjectForParent{task, project}, previous, sandbox, approval}:
      settings_fields_with_project(project, previous, sandbox, approval, workspace, guidance)

def stale_code_expiry(+identity: Code.Identity, source: String, +wrap: Bool, +copy: Code.CopyState,
  next: Nat, ticket: Nat, stale: {Code.feedback_ticket(copy, ticket) == False{} : Bool}) ->
  {Code.step(Code.Block{identity, source, Code.CodeView{wrap, copy}, next}, Code.ExpireFeedback{ticket}) ==
    Code.Decision{Code.Block{identity, source, Code.CodeView{wrap, copy}, next}, Nil{}} : Code.Decision}:
  match copy:
    case Code.CopyIdle{}: {==}
    case Code.CopyPending{current}: {==}
    case Code.CopySucceeded{+current}:
      Equal.cong(Bool, Code.Decision,
        owned => Code.expire_code_feedback(owned, Code.Block{identity, source,
          Code.CodeView{wrap, Code.CopySucceeded{current}}, next}),
        Nat.is_eq(current, ticket), False{}, stale)
    case Code.CopyFailed{+current}:
      Equal.cong(Bool, Code.Decision,
        owned => Code.expire_code_feedback(owned, Code.Block{identity, source,
          Code.CodeView{wrap, Code.CopyFailed{current}}, next}),
        Nat.is_eq(current, ticket), False{}, stale)

def restore_preview(value: Services.Preview, state: Services.State) -> Services.State:
  Services.State{access, credential, settings_open, appearance, next, transfers, preview, directory_picker} = state
  Services.State{access, credential, settings_open, appearance, next, transfers, value, directory_picker}

def restore_directory_picker(value: Services.DirectoryPicker, state: Services.State) -> Services.State:
  Services.State{access, credential, settings_open, appearance, next, transfers, preview, directory_picker} = state
  Services.State{access, credential, settings_open, appearance, next, transfers, preview, value}

def encapsulated_stale_preview(+state: Services.State, current: Nat, +file: B.Attachment, trigger: String, ticket: Nat, +result: Result<&2, &2, String, String>, observed_preview: {Services.preview(state) == Services.LoadingPreview{current, file, trigger} : Services.Preview}, observed_directory_picker: {Services.directory_picker(state) == Services.NoDirectoryPicker{} : Services.DirectoryPicker}, different: {Nat.is_eq(current, ticket) == False{} : Bool}) ->
  {Services.step(Services.Previewed{ticket, result}, state) ==
        Services.Decision{state, Nil{}} : Services.Decision}:
  Services.State{+access, +credential, +settings_open, +appearance, +next, +transfers, +stored_preview, +stored_directory_picker} = state
  backwards_preview = Equal.sym(Services.State, state, restore_preview(Services.LoadingPreview{current, file, trigger}, state),
    Equal.cong(Services.Preview, Services.State, value => restore_preview(value, state), Services.preview(state), Services.LoadingPreview{current, file, trigger}, observed_preview))
  %backwards_preview : {Services.step(Services.Previewed{ticket, result}, _) ==
        Services.Decision{_, Nil{}} : Services.Decision}
  backwards_directory_picker = Equal.sym(Services.State, restore_preview(Services.LoadingPreview{current, file, trigger}, state), restore_directory_picker(Services.NoDirectoryPicker{}, restore_preview(Services.LoadingPreview{current, file, trigger}, state)),
    Equal.cong(Services.DirectoryPicker, Services.State, value => restore_directory_picker(value, restore_preview(Services.LoadingPreview{current, file, trigger}, state)), Services.directory_picker(restore_preview(Services.LoadingPreview{current, file, trigger}, state)), Services.NoDirectoryPicker{}, observed_directory_picker))
  %backwards_directory_picker : {Services.step(Services.Previewed{ticket, result}, _) ==
        Services.Decision{_, Nil{}} : Services.Decision}
  Equal.cong(Bool, Services.Decision,
          owned => Services.finish_preview(owned,
            Services.State{access, credential, settings_open, appearance, next, transfers,
              Services.LoadingPreview{current, file, trigger}, Services.NoDirectoryPicker{}}, file, trigger, result),
          Nat.is_eq(current, ticket), False{}, different)

def encapsulated_closed_preview(+state: Services.State, ticket: Nat, +result: Result<&2, &2, String, String>, observed_preview: {Services.preview(state) == Services.NoPreview{} : Services.Preview}, observed_directory_picker: {Services.directory_picker(state) == Services.NoDirectoryPicker{} : Services.DirectoryPicker}) ->
  {Services.step(Services.Previewed{ticket, result}, state) ==
        Services.Decision{state, Nil{}} : Services.Decision}:
  Services.State{+access, +credential, +settings_open, +appearance, +next, +transfers, +stored_preview, +stored_directory_picker} = state
  backwards_preview = Equal.sym(Services.State, state, restore_preview(Services.NoPreview{}, state),
    Equal.cong(Services.Preview, Services.State, value => restore_preview(value, state), Services.preview(state), Services.NoPreview{}, observed_preview))
  %backwards_preview : {Services.step(Services.Previewed{ticket, result}, _) ==
        Services.Decision{_, Nil{}} : Services.Decision}
  backwards_directory_picker = Equal.sym(Services.State, restore_preview(Services.NoPreview{}, state), restore_directory_picker(Services.NoDirectoryPicker{}, restore_preview(Services.NoPreview{}, state)),
    Equal.cong(Services.DirectoryPicker, Services.State, value => restore_directory_picker(value, restore_preview(Services.NoPreview{}, state)), Services.directory_picker(restore_preview(Services.NoPreview{}, state)), Services.NoDirectoryPicker{}, observed_directory_picker))
  %backwards_directory_picker : {Services.step(Services.Previewed{ticket, result}, _) ==
        Services.Decision{_, Nil{}} : Services.Decision}
  {==}

def encapsulated_upload_destination(+state: Services.State, ticket: Nat, +editor: U.Editor, +file: Services.SelectedFile, +attachment: B.Attachment, observed_directory_picker: {Services.directory_picker(state) == Services.NoDirectoryPicker{} : Services.DirectoryPicker}, found: {Finite.find(~Services.Transfer, Services.transfers(state), ticket) ==
        Some{Services.Uploading{editor, file}} : Maybe<&2, Services.Transfer>}) ->
  {Services.step(Services.Uploaded{ticket, Done{attachment}}, state) ==
        Services.Decision{Services.with_transfers(Finite.remove(~Services.Transfer, Services.transfers(state), ticket), state),
          [Services.AttachToDraft{editor, attachment}]} : Services.Decision}:
  Services.State{+access, +credential, +settings_open, +appearance, +next, +transfers, +preview, +stored_directory_picker} = state
  backwards_directory_picker = Equal.sym(Services.State, state, restore_directory_picker(Services.NoDirectoryPicker{}, state),
    Equal.cong(Services.DirectoryPicker, Services.State, value => restore_directory_picker(value, state), Services.directory_picker(state), Services.NoDirectoryPicker{}, observed_directory_picker))
  %backwards_directory_picker : {Services.step(Services.Uploaded{ticket, Done{attachment}}, _) ==
        Services.Decision{Services.with_transfers(Finite.remove(~Services.Transfer, Services.transfers(_), ticket), _),
          [Services.AttachToDraft{editor, attachment}]} : Services.Decision}
  Equal.trans(Services.Decision,
          Services.step(Services.Uploaded{ticket, Done{attachment}},
            Services.State{access, credential, settings_open, appearance, next, transfers, preview, Services.NoDirectoryPicker{}}),
          Services.upload_finished(Some{Services.Uploading{editor, file}},
            Services.State{access, credential, settings_open, appearance, next, transfers, preview, Services.NoDirectoryPicker{}},
            ticket, Done{attachment}),
          Services.Decision{Services.State{access, credential, settings_open, appearance, next,
            Finite.remove(~Services.Transfer, transfers, ticket), preview, Services.NoDirectoryPicker{}},
            [Services.AttachToDraft{editor, attachment}]},
          Equal.cong(Maybe<&2, Services.Transfer>, Services.Decision,
            found => Services.upload_finished(found,
              Services.State{access, credential, settings_open, appearance, next, transfers, preview, Services.NoDirectoryPicker{}},
              ticket, Done{attachment}),
            Finite.find(~Services.Transfer, transfers, ticket),
            Some{Services.Uploading{editor, file}}, found),
          {==})

def encapsulated_missing_upload(+state: Services.State, ticket: Nat, +result: Result<&2, &2, String, B.Attachment>, observed_directory_picker: {Services.directory_picker(state) == Services.NoDirectoryPicker{} : Services.DirectoryPicker}, missing: {Finite.find(~Services.Transfer, Services.transfers(state), ticket) == None{} : Maybe<&2, Services.Transfer>}) ->
  {Services.step(Services.Uploaded{ticket, result}, state) ==
        Services.Decision{state, Nil{}} : Services.Decision}:
  Services.State{+access, +credential, +settings_open, +appearance, +next, +transfers, +preview, +stored_directory_picker} = state
  backwards_directory_picker = Equal.sym(Services.State, state, restore_directory_picker(Services.NoDirectoryPicker{}, state),
    Equal.cong(Services.DirectoryPicker, Services.State, value => restore_directory_picker(value, state), Services.directory_picker(state), Services.NoDirectoryPicker{}, observed_directory_picker))
  %backwards_directory_picker : {Services.step(Services.Uploaded{ticket, result}, _) ==
        Services.Decision{_, Nil{}} : Services.Decision}
  Equal.cong(Maybe<&2, Services.Transfer>, Services.Decision,
          found => Services.upload_finished(found,
            Services.State{access, credential, settings_open, appearance, next, transfers, preview, Services.NoDirectoryPicker{}}, ticket, result),
          Finite.find(~Services.Transfer, transfers, ticket), None{}, missing)

def encapsulated_stale_auth(+state: Services.State, ticket: Nat, +result: Result<&2, &2, String, Unit>, observed_directory_picker: {Services.directory_picker(state) == Services.NoDirectoryPicker{} : Services.DirectoryPicker}, stale: {Services.expected_access(Services.access(state), ticket) == False{} : Bool}) ->
  {Services.step(Services.Authenticated{ticket, result}, state) ==
        Services.Decision{state, Nil{}} : Services.Decision}:
  Services.State{+access, +credential, +settings_open, +appearance, +next, +transfers, +preview, +stored_directory_picker} = state
  backwards_directory_picker = Equal.sym(Services.State, state, restore_directory_picker(Services.NoDirectoryPicker{}, state),
    Equal.cong(Services.DirectoryPicker, Services.State, value => restore_directory_picker(value, state), Services.directory_picker(state), Services.NoDirectoryPicker{}, observed_directory_picker))
  %backwards_directory_picker : {Services.step(Services.Authenticated{ticket, result}, _) ==
        Services.Decision{_, Nil{}} : Services.Decision}
  Equal.cong(Bool, Services.Decision,
          owned => Services.authentication(owned,
            Services.State{access, credential, settings_open, appearance, next, transfers, preview, Services.NoDirectoryPicker{}}, result),
          Services.expected_access(access, ticket), False{}, stale)

def encapsulated_failed_auth_no_attention(+state: Services.State, reason: String, application: E.Application) ->
  {Core.service_result(Services.authentication(True{}, state, Fail{reason}), application) ==
        Core.application_result_with_services(E.unchanged(application), Services.with_settings_open(True{}, Services.with_credential("", Services.with_access(Services.CredentialRejected{reason}, state))), Nil{}) : InteractionTypes.Decision}:
  Services.State{+access, +credential, +settings_open, +appearance, +next, +transfers, +preview, +picker} = state
  {==}

def encapsulated_readiness_attention(+state: Services.State, +application: E.Application) ->
  {Core.service_result(Services.authentication(True{}, state, Done{Unit{}}), application) ==
        InteractionTypes.Decision{Core.from_application(application, Services.with_settings_open(False{}, Services.with_credential("", Services.with_access(Services.Connected{}, state)))), D.success(J.Null{}), Nil{}, [E.Attend{Core.session_attention(application)}], Nil{}, False{}} : InteractionTypes.Decision}:
  Services.State{+access, +credential, +settings_open, +appearance, +next, +transfers, +preview, +picker} = state
  {==}

def encapsulated_failed_auth(+state: Services.State, reason: String) ->
  {Services.authentication(True{}, state, Fail{reason}) ==
        Services.Decision{Services.with_settings_open(True{}, Services.with_credential("", Services.with_access(Services.CredentialRejected{reason}, state))), Nil{}} : Services.Decision}:
  Services.State{+access, +credential, +settings_open, +appearance, +next, +transfers, +preview, +picker} = state
  {==}

def encapsulated_accepted_auth(+state: Services.State, ticket: Nat, owned: {Services.expected_access(Services.access(state), ticket) == True{} : Bool}) ->
  {Services.step(Services.Authenticated{ticket, Done{Unit{}}}, state) ==
        Services.Decision{Services.with_settings_open(False{}, Services.with_credential("", Services.with_access(Services.Connected{}, state))), [Services.SessionReady{}]} : Services.Decision}:
  Services.State{+access, +credential, +settings_open, +appearance, +next, +transfers, +preview, +picker} = state
  Equal.cong(Bool, Services.Decision, owned => Services.authentication(owned, Services.State{access, credential, settings_open, appearance, next, transfers, preview, picker}, Done{Unit{}}), Services.expected_access(access, ticket), True{}, owned)

def Rule.boundary_evidence():
  Rule.BoundaryRequirements{
    encapsulated_accepted_auth,
    encapsulated_failed_auth,
    +state => result => {==},
    encapsulated_readiness_attention,
    encapsulated_failed_auth_no_attention,
    state => result => application => {==},
    {==},
    encapsulated_stale_auth,
    encapsulated_missing_upload,
    encapsulated_upload_destination,
    encapsulated_closed_preview,
    encapsulated_stale_preview,
    identity => source => wrap => copy => next => ticket => success => stale =>
      Equal.cong(Bool, Code.Decision,
        owned => Code.copy_result(owned, ticket, success, Code.Block{identity, source,
          Code.CodeView{wrap, copy}, next}),
        Code.same_ticket(copy, ticket), False{}, stale),
    identity => source => wrap => copy => next => ticket => stale =>
      stale_code_expiry(identity, source, wrap, copy, next, ticket, stale),
    identity => source => wrap => copy => next => can_copy =>
      Equal.cong(Bool, Code.Decision,
        allowed => Code.begin(allowed, Code.Block{identity, source,
          Code.CodeView{wrap, copy}, next}),
        Code.code_can_copy(Code.CodeView{wrap, copy}), True{}, can_copy),
    identity => source => wrap => copy => next => {==},
    model => tools => max_fork => max_descendants => plugins => context => task => {==},
    origin => workspace => sandbox => approval => project => guidance => entered_workspace => entered_sandbox => entered_approval => {==},
    project => name => old_workspace => workspace => guidance => now => {==},
    name => workspace => guidance => {==},
    project => name => workspace => guidance => {==},
    text => profile => reasoning => config => observation => now => {==},
    config => workspace => guidance => settings_projection(config, workspace, guidance),
    task => operation => parts => outputs => world => inactive =>
      Equal.cong(Bool, +List<Live.Output>,
        allowed => Live.keep(allowed, Live.Output{task, operation, parts},
          Live.remove(outputs, task, operation)),
        Live.active(Live.Output{task, operation, parts}, world), False{}, inactive),
    task => operation => parts => outputs => world => active =>
      Equal.cong(Bool, +List<Live.Output>,
        allowed => Live.keep(allowed, Live.Output{task, operation, parts},
          Live.remove(outputs, task, operation)),
        Live.active(Live.Output{task, operation, parts}, world), True{}, active)
  }

# Selection changes the node's role, never its bound choice payload.

def page_sequence(+page: V.Page, +parent: Identity.Key, +state: InteractionTypes.State) ->
  {Rule.observed_regions(Model.page_contents(page, parent, state)) == Rule.required_regions(page) : +List<Composition.PositionedRegion>}:
  match page:
    case V.StartPage{None{}}:
      InteractionTypes.State{E.Application{world, session}, services} = state
      {==}
    case V.StartPage{Some{scene}}:
      InteractionTypes.State{E.Application{world, session}, services} = state
      {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Nil{}, reading, None{}}, previews, None{}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Nil{}, reading, Some{input}}, previews, None{}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Con{first, rest}, reading, None{}}, previews, None{}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Con{first, rest}, reading, Some{input}}, previews, None{}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Nil{}, reading, None{}}, previews, Some{scene}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Nil{}, reading, Some{input}}, previews, Some{scene}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Con{first, rest}, reading, None{}}, previews, Some{scene}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Con{first, rest}, reading, Some{input}}, previews, Some{scene}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.ProjectPage{V.ProjectScene{id, name, D.Workspace{roots, primary}, guidance, tasks, actions}}: {==}
    case V.ProjectsPage{projects, create}: {==}
    case V.BoardPage{filter, columns, create, working, settings, filters, archive}: {==}
    case V.AgentsPage{agents, create}: {==}
    case V.MissingObject{message}: {==}

def page_only_regions(+page: V.Page, +parent: Identity.Key, +state: InteractionTypes.State) ->
  {Rule.only_regions(Model.page_contents(page, parent, state)) == True{} : Bool}:
  match page:
    case V.StartPage{None{}}:
      InteractionTypes.State{E.Application{world, session}, services} = state
      {==}
    case V.StartPage{Some{scene}}:
      InteractionTypes.State{E.Application{world, session}, services} = state
      {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Nil{}, reading, None{}}, previews, None{}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Nil{}, reading, Some{input}}, previews, None{}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Con{first, rest}, reading, None{}}, previews, None{}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Con{first, rest}, reading, Some{input}}, previews, None{}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Nil{}, reading, None{}}, previews, Some{scene}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Nil{}, reading, Some{input}}, previews, Some{scene}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Con{first, rest}, reading, None{}}, previews, Some{scene}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Con{first, rest}, reading, Some{input}}, previews, Some{scene}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.ProjectPage{V.ProjectScene{id, name, D.Workspace{roots, primary}, guidance, tasks, actions}}: {==}
    case V.ProjectsPage{projects, create}: {==}
    case V.BoardPage{filter, columns, create, working, settings, filters, archive}: {==}
    case V.AgentsPage{agents, create}: {==}
    case V.MissingObject{message}: {==}

def task_reading(+value: V.TaskScene, +parent: Identity.Key, +state: InteractionTypes.State) -> Rule.task_reading(value, parent, state):
  V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, live, decisions, reading, return_latest}, previews, input, details, V.TaskActions{detail, overflow}} = value
  {==}

def task_title(+value: V.TaskScene, +parent: Identity.Key, +state: InteractionTypes.State) ->
  {Rule.find_region(Model.page_contents(V.TaskPage{value}, parent, state), Composition.ConversationTitle{}) ==
    Some{[Model.region(Rule.task_title_key(value, parent), "heading", Rule.task_title_text(value), SurfaceTypes.Heading{}, Nil{})]} : Maybe<&2, +List<SurfaceTypes.Node>>}:
  match value:
    case V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, approvals, reading, latest}, previews, composer, details, V.TaskActions{detail, overflow}}: {==}

def project_title(+value: V.ProjectScene, +parent: Identity.Key, +state: InteractionTypes.State) ->
  {Rule.find_region(Model.page_contents(V.ProjectPage{value}, parent, state), Composition.ProjectTitle{}) ==
    Some{[Model.region(parent, "heading", Rule.project_title_text(value), SurfaceTypes.Heading{}, Nil{})]} : Maybe<&2, +List<SurfaceTypes.Node>>}:
  match value:
    case V.ProjectScene{id, name, D.Workspace{roots, primary}, guidance, tasks, actions}: {==}

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

def collapsed_assembly(+content: InteractionTypes.Scene, +state: InteractionTypes.State,
  collapsed: {Rule.content_navigation_placement(content) == V.CollapsedNavigation{} : V.NavigationPlacement}) ->
  {Rule.navigation_head(Rule.surface_base(Model.assemble(content, state))) ==
    Rule.navigation_head(Model.collapsed_navigation_toggle(Rule.content_navigation(content), state)) : SurfaceTypes.Node}:
  match content:
    case InteractionTypes.Scene{V.Scene{V.Navigation{+expanded, +create, +destinations, +projects, +tasks, +toggle}, +main, +layers, V.Arrangement{+placement}, +attention}, +settings, +transfers, +preview, +code, directory_picker}:
      +nav: V.Navigation = V.Navigation{expanded, create, destinations, projects, tasks, toggle}
      Equal.cong(V.NavigationPlacement, SurfaceTypes.Node,
        (position => Rule.navigation_head(Rule.surface_base(Model.assemble(InteractionTypes.Scene{V.Scene{nav, main, layers,
          V.Arrangement{position}, attention}, settings, transfers, preview, code, directory_picker}, state)))),
        placement, V.CollapsedNavigation{}, collapsed)

def page_payload(+page: V.Page, +state: InteractionTypes.State) ->
  {Model.page(page, state) == SurfaceTypes.Node{Identity.Place{"/main"}, "main", "Content", SurfaceTypes.Main{}, SurfaceTypes.PageContext{Rule.owned_page_context(page)}, Model.page_contents(page, Identity.Place{"/main"}, state)} : SurfaceTypes.Node}:
  match page:
    case V.StartPage{composer}: {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, timeline, previews, input, details, actions}}: {==}
    case V.ProjectPage{project}: {==}
    case V.ProjectsPage{projects, create}: {==}
    case V.BoardPage{filter, columns, create, working, settings, filters, archive}: {==}
    case V.AgentsPage{agents, create}: {==}
    case V.MissingObject{message}: {==}

def Rule.page_region_evidence():
  Rule.PageRegionRequirements{page => state => page_payload(page, state), +toggle => expanded => create => destinations => projects => tasks => +state => {==}, collapsed_assembly,
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
    task_reading,
    value => parent => state => task_title(value, parent, state),
    value => parent => state => project_title(value, parent, state),
    region => position => gesture => {==},
    +parent => +region => +position => +children => {==},
    +parent => +region => +position => +children => {==}}

def absent_input_is_quiet(+state: InteractionTypes.State) ->
  {Model.apply_input(None{}, state) == Rule.quiet_decision(state) : InteractionTypes.Decision}:
  InteractionTypes.State{application, services} = state
  {==}

def resolve_absent(+surface: SurfaceTypes.Surface, +key: String, +gesture: SurfaceTypes.Gesture,
  absent: {Model.find_node(Model.active_nodes(surface), key) == None{} : Maybe<&2, SurfaceTypes.Node>}) ->
  {Model.resolve(surface, key, gesture) == None{} : Maybe<&2, InteractionTypes.Input>}:
  Equal.cong(Maybe<&2, SurfaceTypes.Node>, Maybe<&2, InteractionTypes.Input>,
    source => Model.resolve_source(source, gesture, surface),
    Model.find_node(Model.active_nodes(surface), key), None{}, absent)

def resolve_unavailable(+surface: SurfaceTypes.Surface, +key: String, +input: InteractionTypes.Input, +reason: String,
  +node_key: Identity.Key, +semantic: String, +label: String, +role: SurfaceTypes.Role,
  +children: +List<SurfaceTypes.Node>,
  found: {Model.find_node(Model.active_nodes(surface), key) ==
    Some{SurfaceTypes.Node{node_key, semantic, label, role, SurfaceTypes.Activate{input, V.Unavailable{reason}}, children}} : Maybe<&2, SurfaceTypes.Node>}) ->
  {Model.resolve(surface, key, SurfaceTypes.Press{}) == None{} : Maybe<&2, InteractionTypes.Input>}:
  Equal.trans(Maybe<&2, InteractionTypes.Input>,
    Model.resolve(surface, key, SurfaceTypes.Press{}),
    Model.resolve_source(Some{SurfaceTypes.Node{node_key, semantic, label, role,
      SurfaceTypes.Activate{input, V.Unavailable{reason}}, children}}, SurfaceTypes.Press{}, surface),
    None{},
    Equal.cong(Maybe<&2, SurfaceTypes.Node>, Maybe<&2, InteractionTypes.Input>,
      source => Model.resolve_source(source, SurfaceTypes.Press{}, surface),
      Model.find_node(Model.active_nodes(surface), key),
      Some{SurfaceTypes.Node{node_key, semantic, label, role,
        SurfaceTypes.Activate{input, V.Unavailable{reason}}, children}}, found),
    {==})

def resolve_available(+surface: SurfaceTypes.Surface, +key: String, +input: InteractionTypes.Input,
  +node_key: Identity.Key, +semantic: String, +label: String, +role: SurfaceTypes.Role,
  +children: +List<SurfaceTypes.Node>,
  found: {Model.find_node(Model.active_nodes(surface), key) ==
    Some{SurfaceTypes.Node{node_key, semantic, label, role, SurfaceTypes.Activate{input, V.Available{}}, children}} : Maybe<&2, SurfaceTypes.Node>}) ->
  {Model.resolve(surface, key, SurfaceTypes.Press{}) == Some{input} : Maybe<&2, InteractionTypes.Input>}:
  Equal.trans(Maybe<&2, InteractionTypes.Input>,
    Model.resolve(surface, key, SurfaceTypes.Press{}),
    Model.resolve_source(Some{SurfaceTypes.Node{node_key, semantic, label, role,
      SurfaceTypes.Activate{input, V.Available{}}, children}}, SurfaceTypes.Press{}, surface),
    Some{input},
    Equal.cong(Maybe<&2, SurfaceTypes.Node>, Maybe<&2, InteractionTypes.Input>,
      source => Model.resolve_source(source, SurfaceTypes.Press{}, surface),
      Model.find_node(Model.active_nodes(surface), key),
      Some{SurfaceTypes.Node{node_key, semantic, label, role,
        SurfaceTypes.Activate{input, V.Available{}}, children}}, found),
    {==})

def element_without_resolution(+capacity: V.Capacity, +state: InteractionTypes.State, +key: String,
  +gesture: SurfaceTypes.Gesture,
  unresolved: {Model.resolve(ProductUI.observe(capacity, state), key, gesture) == None{} : Maybe<&2, InteractionTypes.Input>}) ->
  {ProductUI.step(ProductUI.Element{capacity, key, gesture}, state) == Rule.quiet_decision(state) : InteractionTypes.Decision}:
  Equal.trans(InteractionTypes.Decision,
    ProductUI.step(ProductUI.Element{capacity, key, gesture}, state),
    Model.perform(capacity, state, key, None{}),
    Rule.quiet_decision(state),
    Equal.cong(Maybe<&2, InteractionTypes.Input>, InteractionTypes.Decision,
      input => Model.perform(capacity, state, key, input),
      Model.resolve(ProductUI.observe(capacity, state), key, gesture), None{}, unresolved),
    Equal.trans(InteractionTypes.Decision,
      Model.perform(capacity, state, key, None{}),
      Model.apply_input(None{}, state),
      Rule.quiet_decision(state),
      {==}, absent_input_is_quiet(state)))

def receipt_source(+decision: InteractionTypes.Decision, previous: +List<E.Layer>, origin: String) ->
  {Rule.receipt(Model.source_decision(decision, previous, origin)) == Rule.receipt(decision) : Rule.Receipt}:
  InteractionTypes.Decision{InteractionTypes.State{E.Application{program, session}, services}, reply, runtime, interaction, service_effects, durable} = decision
  {==}

def receipt_record_source(+before: InteractionTypes.State, key: String, +decision: InteractionTypes.Decision) ->
  {Rule.receipt(Model.record_source(before, key, decision)) == Rule.receipt(decision) : Rule.Receipt}:
  InteractionTypes.State{E.Application{program, E.Session{route, drafts, readers, +layers, attention,
    navigation, filter, now, next, pending, previews, code, next_layer}}, services} = before
  receipt_source(decision, layers, Model.origin(layers, key))

def receipt_navigation_closed(+decision: InteractionTypes.Decision) ->
  {Rule.receipt(Model.navigation_closed(decision)) == Rule.receipt(decision) : Rule.Receipt}:
  InteractionTypes.Decision{InteractionTypes.State{E.Application{program, session}, services}, reply, runtime, interaction, service_effects, durable} = decision
  {==}

def receipt_after_navigation(dismiss: Bool, +decision: InteractionTypes.Decision) ->
  {Rule.receipt(Model.after_navigation(dismiss, decision)) == Rule.receipt(decision) : Rule.Receipt}:
  match dismiss:
    case False{}: {==}
    case True{}: receipt_navigation_closed(decision)

def receipt_perform_present(+capacity: V.Capacity, +state: InteractionTypes.State, +key: String,
  +input: Maybe<&2, InteractionTypes.Input>) ->
  {Rule.receipt(Model.perform_present(capacity, state, key, input)) == Rule.receipt(Model.apply_input(input, state)) : Rule.Receipt}:
  V.Capacity{navigation_beside, details_beside} = capacity
  Equal.trans(Rule.Receipt,
    Rule.receipt(Model.perform_present(capacity, state, key, input)),
    Rule.receipt(Model.record_source(state, key, Model.apply_input(input, state))),
    Rule.receipt(Model.apply_input(input, state)),
    receipt_after_navigation(Bool.not(navigation_beside) && Model.navigates(input),
      Model.record_source(state, key, Model.apply_input(input, state))),
    receipt_record_source(state, key, Model.apply_input(input, state)))

def receipt_perform_input(+input: Maybe<&2, InteractionTypes.Input>, +capacity: V.Capacity,
  +state: InteractionTypes.State, +key: String) ->
  {Rule.receipt(Model.perform_input(input, capacity, state, key)) == Rule.receipt(Model.apply_input(input, state)) : Rule.Receipt}:
  match input:
    case None{}: {==}
    case Some{value}: receipt_perform_present(capacity, state, key, Some{value})

def receipt_perform(+capacity: V.Capacity, +state: InteractionTypes.State, +key: String,
  +input: Maybe<&2, InteractionTypes.Input>) ->
  {Rule.receipt(Model.perform(capacity, state, key, input)) == Rule.receipt(Model.apply_input(input, state)) : Rule.Receipt}:
  receipt_perform_input(input, capacity, state, key)

def element_receipt(+capacity: V.Capacity, +state: InteractionTypes.State, +key: String,
  +gesture: SurfaceTypes.Gesture) ->
  {Rule.receipt(ProductUI.step(ProductUI.Element{capacity, key, gesture}, state)) ==
    Rule.receipt(Model.apply_input(Model.resolve(ProductUI.observe(capacity, state), key, gesture), state)) : Rule.Receipt}:
  receipt_perform(capacity, state, key, Model.resolve(ProductUI.observe(capacity, state), key, gesture))

def Rule.surface_evidence():
  Rule.SurfaceRequirements{
    +capacity => +state => +key => +gesture => absent =>
      element_without_resolution(capacity, state, key, gesture,
        resolve_absent(ProductUI.observe(capacity, state), key, gesture, absent))
    ,
    +capacity => +state => +key => +input => +reason => +node_key => +semantic => +label => +role => +children => found =>
      element_without_resolution(capacity, state, key, SurfaceTypes.Press{},
        resolve_unavailable(ProductUI.observe(capacity, state), key, input, reason, node_key, semantic, label, role, children, found))
    ,
    +capacity => +state => +editor => absent =>
      Equal.trans(InteractionTypes.Decision,
        ProductUI.step(ProductUI.SubmitComposer{capacity, editor}, state),
        Model.submit_found(None{}, capacity, state),
        Rule.quiet_decision(state),
        Equal.cong(Maybe<&2, SurfaceTypes.Node>, InteractionTypes.Decision,
          found => Model.submit_found(found, capacity, state),
          Model.submission(Model.active_nodes(ProductUI.observe(capacity, state)), editor), None{}, absent),
        absent_input_is_quiet(state))
    ,
    capacity => state => key => gesture => element_receipt(capacity, state, key, gesture),
    +capacity => +state => +key => +input => +node_key => +semantic => +label => +role => +children => found =>
      Equal.trans(Rule.Receipt,
        Rule.receipt(ProductUI.step(ProductUI.Element{capacity, key, SurfaceTypes.Press{}}, state)),
        Rule.receipt(Model.apply_input(Model.resolve(ProductUI.observe(capacity, state), key, SurfaceTypes.Press{}), state)),
        Rule.receipt(Core.step(input, state)),
        element_receipt(capacity, state, key, SurfaceTypes.Press{}),
        Equal.cong(Maybe<&2, InteractionTypes.Input>, Rule.Receipt,
          resolved => Rule.receipt(Model.apply_input(resolved, state)),
          Model.resolve(ProductUI.observe(capacity, state), key, SurfaceTypes.Press{}), Some{input},
          resolve_available(ProductUI.observe(capacity, state), key, input, node_key, semantic, label, role, children, found)))
    ,
    +previous => origin => +panel => trigger => initial_attention => query => +layer_occurrence => +rest => present =>
      Equal.cong(Bool, +List<E.Layer>,
        unchanged => E.Layer{panel, Model.layer_trigger(unchanged, trigger, origin), initial_attention, query, layer_occurrence} <> rest,
        Model.layer_present(previous, E.panel_target(panel)), True{}, present)
    ,
    +previous => origin => +panel => trigger => initial_attention => query => +layer_occurrence => +rest => absent =>
      Equal.cong(Bool, +List<E.Layer>,
        unchanged => E.Layer{panel, Model.layer_trigger(unchanged, trigger, origin), initial_attention, query, layer_occurrence} <> rest,
        Model.layer_present(previous, E.panel_target(panel)), False{}, absent)
    }

def conversation_recipe_evidence(composer: Bool, approvals: Bool, return_latest: Bool)
  -> Rule.conversation_recipe_law(composer, approvals, return_latest):
  match composer approvals return_latest:
    case False{} False{} False{}: {==}
    case False{} False{} True{}: {==}
    case False{} True{} False{}: {==}
    case False{} True{} True{}: {==}
    case True{} False{} False{}: {==}
    case True{} False{} True{}: {==}
    case True{} True{} False{}: {==}
    case True{} True{} True{}: {==}

def task_recipe_components_evidence(composer: Maybe<&2, V.ComposerScene>, approvals: +List<Conversation.DecisionRequest>, return_latest: Maybe<&2, U.Input>)
  -> {Composition.Recipe{Composition.ReadingMeasure{}, Composition.ConversationHeading{}, Composition.ChronologicalReading{},
        Composition.bottom_composer(View.has_composer(composer)), Composition.decisions(View.has_decisions(approvals)), Composition.latest(View.has_return_latest(return_latest))} ==
      Composition.Recipe{Composition.ReadingMeasure{}, Composition.ConversationHeading{}, Composition.ChronologicalReading{},
        Rule.expected_bottom_composer(Rule.has_composer(composer)), Rule.expected_decisions(View.has_decisions(approvals)), Rule.expected_latest(View.has_return_latest(return_latest))} : Composition.Recipe}:
  match composer approvals return_latest:
    case None{} Nil{} None{}: {==}
    case None{} Nil{} Some{input}: {==}
    case None{} Con{decision, rest} None{}: {==}
    case None{} Con{decision, rest} Some{input}: {==}
    case Some{scene} Nil{} None{}: {==}
    case Some{scene} Nil{} Some{input}: {==}
    case Some{scene} Con{decision, rest} None{}: {==}
    case Some{scene} Con{decision, rest} Some{input}: {==}

def task_recipe_evidence(task: V.TaskScene)
  -> {Composition.recipe(View.page_composition(V.TaskPage{task})) == Rule.expected_task_recipe(task) : Composition.Recipe}:
  V.TaskScene{task_id, title, status, context, timeline, previews, composer, details, actions} = task
  Conversation.Timeline{task_id, generation, groups, operations, approvals, reading, return_to_latest} = timeline
  task_recipe_components_evidence(composer, approvals, return_to_latest)

def action_evidence(parent: Identity.Key, control: InteractionTypes.Control)
  -> {Model.action(parent, control) == Rule.expected_action(parent, control) : SurfaceTypes.Node}:
  match control:
    case InteractionTypes.Control{+identity, label, V.Primary{}, input, availability}: {==}
    case InteractionTypes.Control{+identity, label, V.Destructive{}, input, availability}: {==}
    case InteractionTypes.Control{+identity, label, V.Secondary{}, input, availability}: {==}

def visible_speaker_evidence(+id: Nat, speaker: Conversation.Speaker, +text: String, +source: D.Message,
    +task: Nat, +parent: Identity.Key, +state: InteractionTypes.State)
  -> {Rule.first_speech_projection(Model.groups([Conversation.VisibleSpeech{id, speaker, text, source}], task, parent, state)) ==
      Some{Rule.SpeechProjection{Identity.Entity{parent, "message", Nat.show(id)}, "message/" ++ Nat.show(id), "Message",
        Rule.expected_speaker_role(speaker), SurfaceTypes.RichText{Code.Message{task, id}, text}}} : Maybe<&2, Rule.SpeechProjection>}:
  match speaker:
    case Conversation.UserSpeech{}: {==}
    case Conversation.AssistantSpeech{}: {==}

def structure_evidence(recipe: Composition.Recipe)
  -> {Composition.structure(recipe) == Rule.expected_structure(recipe) : Composition.Structure}:
  match recipe:
    case Composition.Recipe{measure, heading, Composition.CenteredCreation{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.ChronologicalReading{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.ProjectSections{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.ProjectRows{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.StageColumns{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.AgentRows{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.UnavailableNotice{}, composer, decisions, latest}: {==}

def current_composer_context(+identity: U.Editor, revision: Nat, message: U.Text,
  +footer: +List<V.ComposerControl>, +context: Maybe<&2, Context.Preview>, submit: V.ControlDeclaration,
  feedback: U.Feedback, pending: Bool, +world: M.World()) ->
  {Rule.introduction_context(View.creation_introduction(Some{V.ComposerScene{identity, revision, message, footer, View.preview_observation(context), submit, feedback, pending}}, world)) == context : Maybe<&2, Context.Preview>}:
  match context:
    case None{}: {==}
    case Some{preview}: {==}

def composer_has_context(+message: U.Text, +profile: String, reasoning: String, +context: Context.Configuration,
  scene: V.EditorScene, +world: M.World()) ->
  {Rule.composer_footer(View.composer_scene(U.NewTask{message, profile, reasoning, context}, scene, world)) ==
    [V.ComposerControl{V.ModelSubject{}, View.control("composer/model", View.profile_label(D.find_profile(Board.profiles(world), profile), profile), U.OpenPanel{U.ModelPicker{U.NewTaskEditor{}}, "composer/model"})},
     V.ComposerControl{V.WorkspaceSubject{}, View.context_control("composer/workspace/new-task", View.observation_workspace(Context.DraftExecution{Context.preview(context, world)}), U.WorkspaceConfiguration{U.NewTaskEditor{}})},
         V.ComposerControl{V.PermissionsSubject{}, View.context_control("composer/permissions/new-task", View.observation_permissions(Context.DraftExecution{Context.preview(context, world)}, Board.profiles(world)), U.PermissionsConfiguration{U.NewTaskEditor{}})}] : +List<V.ComposerControl>}:
  V.EditorScene{identity, revision, groups, sections, submit, feedback, pending} = scene
  {==}

def Rule.composition_evidence():
  Rule.CompositionRequirements{
    Rule.page_region_evidence(),
    navigation => main => layers => placement => attention => {==},
    task => task_recipe_evidence(task),
    composer => approvals => return_latest => conversation_recipe_evidence(composer, approvals, return_latest),
    message => {==},
    parent => control => action_evidence(parent, control),
    id => speaker => text => source => task => parent => state => visible_speaker_evidence(id, speaker, text, source, task, parent, state),
    +id => attention => +expanded => summary => audit => expand => collapse => +task => +parent => +state => {==},
    view => parent => state => Rule.composer_tree_agreement(view, parent, state),
    recipe => structure_evidence(recipe),
    +context => +world => {==},
    identity => revision => message => footer => context => submit => feedback => pending => world => current_composer_context(identity, revision, message, footer, context, submit, feedback, pending, world),
    +input => +parent => +world => +session => +services => {==},
    +declaration => +rest => +parent => +state => {==},
    message => profile => reasoning => context => scene => world => composer_has_context(message, profile, reasoning, context, scene, world),
    fallback => {==}}
