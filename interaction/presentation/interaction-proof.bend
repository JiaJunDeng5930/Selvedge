import ../experience/MODEL.bend as Experience
import ../experience/PROGRAM.bend as UX
import ../submission/FIELDS.bend as Forms
import Base
import ../../harness/tasks/PROGRAM.bend as T
import ../../harness/COMMANDS.bend as Commands
import ../../bendlib/string-equality.bend as SafeText
import ../../bendlib/equality-proof.bend as TextProof
import ../../bendlib/categories.bend as Categories
import ../../harness/DOMAIN.bend as D
import ../services/CONTEXT.bend as Context
import ./CONTRACT.bend as Rule
import ../../bendlib/json.bend as J
import ../conversation/CODE.bend as Code
import ../interactive_markdown/TYPES.bend as IM
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
import ../interactive_markdown/DOCUMENTS.bend as InteractiveDocuments
import ../../bendlib/stdlib.bend as Std
import ../../bendlib/logic-proof.bend as Logic
import ../../bendlib/algebra-proof.bend as Alg

def preview_outcome(accepted: Bool, +current: Nat, +ticket: Nat, +state: Services.State, +file: B.Attachment, +trigger: String, +result: Result<&2, &2, String, String>) -> Services.Decision:
  match accepted:
    case False{}: Services.Decision{state, Nil{}}
    case True{}: Services.preview_calculation(state, file, trigger, result)

def preview_checked(+current: Nat, +ticket: Nat, +state: Services.State, +file: B.Attachment, +trigger: String, +result: Result<&2, &2, String, String>, accepted: Bool, observed: {Services.preview_result_owned(Services.PreviewResult{current, ticket, state, file, trigger, result}) == accepted : Bool}) ->
  {Services.preview_admitted(Categories.admit_checked(Services.PreviewResult, Services.preview_result_owned, Services.PreviewResult{current, ticket, state, file, trigger, result}, accepted, observed), state) == preview_outcome(accepted, current, ticket, state, file, trigger, result) : Services.Decision}:
  match accepted:
    case False{}: {==}
    case True{}: {==}


def authentication_outcome(accepted: Bool, +ticket: Nat, +state: Services.State, +result: Result<&2, &2, String, Unit>) -> Services.Decision:
  match accepted:
    case False{}: Services.Decision{state, Nil{}}
    case True{}: Services.authentication_calculation(state, result)

def authentication_checked(+ticket: Nat, +state: Services.State, +result: Result<&2, &2, String, Unit>, accepted: Bool, observed: {Services.authentication_owned(Services.AuthenticationRequest{ticket, state, result}) == accepted : Bool}) ->
  {Services.authentication_admitted(Categories.admit_checked(Services.AuthenticationRequest, Services.authentication_owned, Services.AuthenticationRequest{ticket, state, result}, accepted, observed), state) == authentication_outcome(accepted, ticket, state, result) : Services.Decision}:
  match accepted:
    case False{}: {==}
    case True{}: {==}


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
  Services.State{access, settings_open, appearance, next, transfers, preview, directory_picker, +speech} = state
  Services.State{access, settings_open, appearance, next, transfers, value, directory_picker, speech}

def restore_directory_picker(value: Services.DirectoryPicker, state: Services.State) -> Services.State:
  Services.State{access, settings_open, appearance, next, transfers, preview, directory_picker, +speech} = state
  Services.State{access, settings_open, appearance, next, transfers, preview, value, speech}

def encapsulated_stale_preview_reusable(+state: Services.State, +current: Nat, +file: B.Attachment, +trigger: String, +ticket: Nat, +result: Result<&2, &2, String, String>, observed_preview: {Services.preview(state) == Services.LoadingPreview{current, file, trigger} : Services.Preview}, observed_directory_picker: {Services.directory_picker(state) == Services.NoDirectoryPicker{} : Services.DirectoryPicker}, different: {Nat.is_eq(current, ticket) == False{} : Bool}) ->
  {Services.step(Services.Previewed{ticket, result}, state) ==
        Services.Decision{state, Nil{}} : Services.Decision}:
  Services.State{+access, +settings_open, +appearance, +next, +transfers, +stored_preview, +stored_directory_picker, +speech} = state
  backwards_preview = Equal.sym(Services.State, state, restore_preview(Services.LoadingPreview{current, file, trigger}, state),
    Equal.cong(Services.Preview, Services.State, value => restore_preview(value, state), Services.preview(state), Services.LoadingPreview{current, file, trigger}, observed_preview))
  %backwards_preview : {Services.step(Services.Previewed{ticket, result}, _) ==
        Services.Decision{_, Nil{}} : Services.Decision}
  backwards_directory_picker = Equal.sym(Services.State, restore_preview(Services.LoadingPreview{current, file, trigger}, state), restore_directory_picker(Services.NoDirectoryPicker{}, restore_preview(Services.LoadingPreview{current, file, trigger}, state)),
    Equal.cong(Services.DirectoryPicker, Services.State, value => restore_directory_picker(value, restore_preview(Services.LoadingPreview{current, file, trigger}, state)), Services.directory_picker(restore_preview(Services.LoadingPreview{current, file, trigger}, state)), Services.NoDirectoryPicker{}, observed_directory_picker))
  %backwards_directory_picker : {Services.step(Services.Previewed{ticket, result}, _) ==
        Services.Decision{_, Nil{}} : Services.Decision}
  Equal.trans(Services.Decision,
    Services.preview_result(Services.LoadingPreview{current, file, trigger}, ticket, result, Services.State{access, settings_open, appearance, next, transfers, Services.LoadingPreview{current, file, trigger}, Services.NoDirectoryPicker{}, speech}),
    preview_outcome(Nat.is_eq(current, ticket), current, ticket, Services.State{access, settings_open, appearance, next, transfers, Services.LoadingPreview{current, file, trigger}, Services.NoDirectoryPicker{}, speech}, file, trigger, result), Services.Decision{Services.State{access, settings_open, appearance, next, transfers, Services.LoadingPreview{current, file, trigger}, Services.NoDirectoryPicker{}, speech}, Nil{}},
    preview_checked(current, ticket, Services.State{access, settings_open, appearance, next, transfers, Services.LoadingPreview{current, file, trigger}, Services.NoDirectoryPicker{}, speech}, file, trigger, result, Nat.is_eq(current, ticket), {==}),
    Equal.cong(Bool, Services.Decision, owned => preview_outcome(owned, current, ticket, Services.State{access, settings_open, appearance, next, transfers, Services.LoadingPreview{current, file, trigger}, Services.NoDirectoryPicker{}, speech}, file, trigger, result), Nat.is_eq(current, ticket), False{}, different))

def encapsulated_stale_preview(+state: Services.State, current: Nat, +file: B.Attachment, trigger: String, ticket: Nat, +result: Result<&2, &2, String, String>, observed_preview: {Services.preview(state) == Services.LoadingPreview{current, file, trigger} : Services.Preview}, observed_directory_picker: {Services.directory_picker(state) == Services.NoDirectoryPicker{} : Services.DirectoryPicker}, different: {Nat.is_eq(current, ticket) == False{} : Bool}) ->
  {Services.step(Services.Previewed{ticket, result}, state) ==
        Services.Decision{state, Nil{}} : Services.Decision}:
  encapsulated_stale_preview_reusable(state, current, file, trigger, ticket, result, observed_preview, observed_directory_picker, different)


def encapsulated_closed_preview(+state: Services.State, ticket: Nat, +result: Result<&2, &2, String, String>, observed_preview: {Services.preview(state) == Services.NoPreview{} : Services.Preview}, observed_directory_picker: {Services.directory_picker(state) == Services.NoDirectoryPicker{} : Services.DirectoryPicker}) ->
  {Services.step(Services.Previewed{ticket, result}, state) ==
        Services.Decision{state, Nil{}} : Services.Decision}:
  Services.State{+access, +settings_open, +appearance, +next, +transfers, +stored_preview, +stored_directory_picker, +speech} = state
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
  Services.State{+access, +settings_open, +appearance, +next, +transfers, +preview, +stored_directory_picker, +speech} = state
  backwards_directory_picker = Equal.sym(Services.State, state, restore_directory_picker(Services.NoDirectoryPicker{}, state),
    Equal.cong(Services.DirectoryPicker, Services.State, value => restore_directory_picker(value, state), Services.directory_picker(state), Services.NoDirectoryPicker{}, observed_directory_picker))
  %backwards_directory_picker : {Services.step(Services.Uploaded{ticket, Done{attachment}}, _) ==
        Services.Decision{Services.with_transfers(Finite.remove(~Services.Transfer, Services.transfers(_), ticket), _),
          [Services.AttachToDraft{editor, attachment}]} : Services.Decision}
  Equal.trans(Services.Decision,
          Services.step(Services.Uploaded{ticket, Done{attachment}},
            Services.State{access, settings_open, appearance, next, transfers, preview, Services.NoDirectoryPicker{}, speech}),
          Services.upload_finished(Some{Services.Uploading{editor, file}},
            Services.State{access, settings_open, appearance, next, transfers, preview, Services.NoDirectoryPicker{}, speech},
            ticket, Done{attachment}),
          Services.Decision{Services.State{access, settings_open, appearance, next,
            Finite.remove(~Services.Transfer, transfers, ticket), preview, Services.NoDirectoryPicker{}, speech},
            [Services.AttachToDraft{editor, attachment}]},
          Equal.cong(Maybe<&2, Services.Transfer>, Services.Decision,
            found => Services.upload_finished(found,
              Services.State{access, settings_open, appearance, next, transfers, preview, Services.NoDirectoryPicker{}, speech},
              ticket, Done{attachment}),
            Finite.find(~Services.Transfer, transfers, ticket),
            Some{Services.Uploading{editor, file}}, found),
          {==})

def encapsulated_missing_upload(+state: Services.State, ticket: Nat, +result: Result<&2, &2, String, B.Attachment>, observed_directory_picker: {Services.directory_picker(state) == Services.NoDirectoryPicker{} : Services.DirectoryPicker}, missing: {Finite.find(~Services.Transfer, Services.transfers(state), ticket) == None{} : Maybe<&2, Services.Transfer>}) ->
  {Services.step(Services.Uploaded{ticket, result}, state) ==
        Services.Decision{state, Nil{}} : Services.Decision}:
  Services.State{+access, +settings_open, +appearance, +next, +transfers, +preview, +stored_directory_picker, +speech} = state
  backwards_directory_picker = Equal.sym(Services.State, state, restore_directory_picker(Services.NoDirectoryPicker{}, state),
    Equal.cong(Services.DirectoryPicker, Services.State, value => restore_directory_picker(value, state), Services.directory_picker(state), Services.NoDirectoryPicker{}, observed_directory_picker))
  %backwards_directory_picker : {Services.step(Services.Uploaded{ticket, result}, _) ==
        Services.Decision{_, Nil{}} : Services.Decision}
  Equal.cong(Maybe<&2, Services.Transfer>, Services.Decision,
          found => Services.upload_finished(found,
            Services.State{access, settings_open, appearance, next, transfers, preview, Services.NoDirectoryPicker{}, speech}, ticket, result),
          Finite.find(~Services.Transfer, transfers, ticket), None{}, missing)

def encapsulated_stale_auth_reusable(+state: Services.State, +ticket: Nat, +result: Result<&2, &2, String, Unit>, observed_directory_picker: {Services.directory_picker(state) == Services.NoDirectoryPicker{} : Services.DirectoryPicker}, stale: {Services.expected_access(Services.access(state), ticket) == False{} : Bool}) ->
  {Services.step(Services.Authenticated{ticket, result}, state) ==
        Services.Decision{state, Nil{}} : Services.Decision}:
  Services.State{+access, +settings_open, +appearance, +next, +transfers, +preview, +stored_directory_picker, +speech} = state
  backwards_directory_picker = Equal.sym(Services.State, state, restore_directory_picker(Services.NoDirectoryPicker{}, state),
    Equal.cong(Services.DirectoryPicker, Services.State, value => restore_directory_picker(value, state), Services.directory_picker(state), Services.NoDirectoryPicker{}, observed_directory_picker))
  %backwards_directory_picker : {Services.step(Services.Authenticated{ticket, result}, _) ==
        Services.Decision{_, Nil{}} : Services.Decision}
  Equal.trans(Services.Decision,
    Services.step(Services.Authenticated{ticket, result}, Services.State{access, settings_open, appearance, next, transfers, preview, Services.NoDirectoryPicker{}, speech}),
    authentication_outcome(Services.expected_access(access, ticket), ticket, Services.State{access, settings_open, appearance, next, transfers, preview, Services.NoDirectoryPicker{}, speech}, result), Services.Decision{Services.State{access, settings_open, appearance, next, transfers, preview, Services.NoDirectoryPicker{}, speech}, Nil{}},
    authentication_checked(ticket, Services.State{access, settings_open, appearance, next, transfers, preview, Services.NoDirectoryPicker{}, speech}, result, Services.expected_access(access, ticket), {==}),
    Equal.cong(Bool, Services.Decision, owned => authentication_outcome(owned, ticket, Services.State{access, settings_open, appearance, next, transfers, preview, Services.NoDirectoryPicker{}, speech}, result), Services.expected_access(access, ticket), False{}, stale))

def encapsulated_stale_auth(+state: Services.State, ticket: Nat, +result: Result<&2, &2, String, Unit>, observed_directory_picker: {Services.directory_picker(state) == Services.NoDirectoryPicker{} : Services.DirectoryPicker}, stale: {Services.expected_access(Services.access(state), ticket) == False{} : Bool}) ->
  {Services.step(Services.Authenticated{ticket, result}, state) ==
        Services.Decision{state, Nil{}} : Services.Decision}:
  encapsulated_stale_auth_reusable(state, ticket, result, observed_directory_picker, stale)


def encapsulated_failed_auth_no_attention(+state: Services.State, reason: String, application: E.Application) ->
  {Core.service_result(Services.authentication_calculation(state, Fail{reason}), application) ==
        Core.application_result_with_services(E.unchanged(application), Services.with_settings_open(True{}, Services.with_access(Services.ConnectionLost{Services.connection_ticket(Services.access(state)), reason}, state)), [Services.ScheduleReconnect{Services.connection_ticket(Services.access(state)), 1000n}]) : InteractionTypes.Decision}:
  Services.State{+access, +settings_open, +appearance, +next, +transfers, +preview, +picker, +speech} = state
  {==}

def encapsulated_readiness_attention(+state: Services.State, +application: E.Application) ->
  {Core.service_result(Services.authentication_calculation(state, Done{Unit{}}), application) ==
        InteractionTypes.Decision{Core.from_application(application, Services.with_settings_open(False{}, Services.with_access(Services.Connected{Services.connection_ticket(Services.access(state))}, state))), D.success(J.Null{}), Nil{}, [E.Attend{Core.session_attention(application)}], Nil{}, False{}} : InteractionTypes.Decision}:
  Services.State{+access, +settings_open, +appearance, +next, +transfers, +preview, +picker, +speech} = state
  {==}

def encapsulated_failed_auth(+state: Services.State, reason: String) ->
  {Services.authentication_calculation(state, Fail{reason}) ==
        Services.Decision{Services.with_settings_open(True{}, Services.with_access(Services.ConnectionLost{Services.connection_ticket(Services.access(state)), reason}, state)), [Services.ScheduleReconnect{Services.connection_ticket(Services.access(state)), 1000n}]} : Services.Decision}:
  Services.State{+access, +settings_open, +appearance, +next, +transfers, +preview, +picker, +speech} = state
  {==}

def encapsulated_accepted_auth_reusable(+state: Services.State, +ticket: Nat, owned: {Services.expected_access(Services.access(state), ticket) == True{} : Bool}) ->
  {Services.step(Services.Authenticated{ticket, Done{Unit{}}}, state) ==
        Services.Decision{Services.with_settings_open(False{}, Services.with_access(Services.Connected{Services.connection_ticket(Services.access(state))}, state)), [Services.SessionReady{}]} : Services.Decision}:
  Services.State{+access, +settings_open, +appearance, +next, +transfers, +preview, +picker, +speech} = state
  Equal.trans(Services.Decision,
    Services.step(Services.Authenticated{ticket, Done{Unit{}}}, Services.State{access, settings_open, appearance, next, transfers, preview, picker, speech}),
    authentication_outcome(Services.expected_access(access, ticket), ticket, Services.State{access, settings_open, appearance, next, transfers, preview, picker, speech}, Done{Unit{}}),
    Services.authentication_calculation(Services.State{access, settings_open, appearance, next, transfers, preview, picker, speech}, Done{Unit{}}),
    authentication_checked(ticket, Services.State{access, settings_open, appearance, next, transfers, preview, picker, speech}, Done{Unit{}}, Services.expected_access(access, ticket), {==}),
    Equal.cong(Bool, Services.Decision, owned => authentication_outcome(owned, ticket, Services.State{access, settings_open, appearance, next, transfers, preview, picker, speech}, Done{Unit{}}), Services.expected_access(access, ticket), True{}, owned))

def encapsulated_accepted_auth(+state: Services.State, ticket: Nat, owned: {Services.expected_access(Services.access(state), ticket) == True{} : Bool}) ->
  {Services.step(Services.Authenticated{ticket, Done{Unit{}}}, state) ==
        Services.Decision{Services.with_settings_open(False{}, Services.with_access(Services.Connected{Services.connection_ticket(Services.access(state))}, state)), [Services.SessionReady{}]} : Services.Decision}:
  encapsulated_accepted_auth_reusable(state, ticket, owned)


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
    model => tools => max_fork => max_descendants => plugins => context => task => guidance => {==},
    origin => workspace => sandbox => approval => project => guidance => entered_workspace => entered_sandbox => entered_approval => {==},
    project => name => old_workspace => workspace => guidance => now => {==},
    name => workspace => guidance => {==},
    project => name => workspace => guidance => {==},
    text => profile => reasoning => config => observation => now => work => create_worktree => {==},
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
    case V.SharedUIPage{work, name, source}: {==}
    case V.TaskGraphsPage{graphs, create}: {==}
    case V.HistorySearchPage{search, projects, works}: {==}
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
    case V.SharedUIPage{work, name, source}: {==}
    case V.TaskGraphsPage{graphs, create}: {==}
    case V.HistorySearchPage{search, projects, works}: {==}
    case V.MissingObject{message}: {==}

def task_reading(+value: V.TaskScene, +parent: Identity.Key, +state: InteractionTypes.State) -> Rule.task_reading(value, parent, state):
  V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, live, decisions, reading, return_latest}, previews, input, details, V.TaskActions{detail, overflow}} = value
  {==}

def task_title(+value: V.TaskScene, +parent: Identity.Key, +state: InteractionTypes.State) ->
  {Rule.find_region(Model.page_contents(V.TaskPage{value}, parent, state), Composition.ConversationTitle{}) ==
    Some{Model.region(Rule.task_title_key(value, parent), "heading", Rule.task_title_text(value), SurfaceTypes.Heading{}, Nil{}) <>
      Rule.task_worktree_feedback(value, parent, state)} : Maybe<&2, +List<SurfaceTypes.Node>>}:
  match value:
    case V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, approvals, reading, latest}, previews, composer, details, V.TaskActions{detail, overflow}}: {==}

def project_title(+value: V.ProjectScene, +parent: Identity.Key, +state: InteractionTypes.State) ->
  {Rule.find_region(Model.page_contents(V.ProjectPage{value}, parent, state), Composition.ProjectTitle{}) ==
    Some{[Model.region(parent, "heading", Rule.project_title_text(value), SurfaceTypes.Heading{}, Nil{})]} : Maybe<&2, +List<SurfaceTypes.Node>>}:
  match value:
    case V.ProjectScene{id, name, D.Workspace{roots, primary}, guidance, tasks, actions}: {==}

def layer_title_evidence() -> Rule.LayerTitleRequirements:
  Rule.LayerTitleRequirements{
    work => {==},
    task => {==},
    {==},
    id => {==},
    {==},
    id => {==},
    {==},
    id => {==},
    {==},
    work => {==},
    id => {==},
    task => {==},
    task => {==},
    actions => {==},
    cards => {==},
    automatic => selected => profiles => automation => {==},
    filter => {==},
    {==},
    identity => revision => groups => sections => assessment => submit => feedback => pending => {==},
    editor => fields => {==},
    editor => fields => {==},
    context => {==},
    editor => query => fields => {==},
    editor => fields => {==},
    task => {==},
    title => confirm => cancel => {==},
    selected => works => {==},
    route => destinations => {==}}

def collapsed_assembly(+full: Bool, +content: InteractionTypes.Scene, +state: InteractionTypes.State,
  collapsed: {Rule.content_navigation_placement(content) == V.CollapsedNavigation{} : V.NavigationPlacement}) ->
  {Rule.collapsed_restore_node(full, Rule.surface_base(Model.assemble(full, content, state))) ==
    Rule.required_collapsed_restore(full, Rule.content_navigation(content), state) : SurfaceTypes.Node}:
  match full content:
    case True{} InteractionTypes.Scene{V.Scene{V.Navigation{+expanded, +create, +destinations, +projects, +tasks, +toggle}, +main, +layers, V.Arrangement{+placement}, +attention}, +settings, +transfers, +preview, +code, directory_picker}:
      +nav: V.Navigation = V.Navigation{expanded, create, destinations, projects, tasks, toggle}
      Equal.cong(V.NavigationPlacement, SurfaceTypes.Node,
        (position => Rule.collapsed_restore_node(True{}, Rule.surface_base(Model.assemble(True{}, InteractionTypes.Scene{V.Scene{nav, main, layers,
          V.Arrangement{position}, attention}, settings, transfers, preview, code, directory_picker}, state)))),
        placement, V.CollapsedNavigation{}, collapsed)
    case False{} InteractionTypes.Scene{V.Scene{V.Navigation{+expanded, +create, +destinations, +projects, +tasks, +toggle}, +main, +layers, V.Arrangement{+placement}, +attention}, +settings, +transfers, +preview, +code, directory_picker}:
      +nav: V.Navigation = V.Navigation{expanded, create, destinations, projects, tasks, toggle}
      Equal.cong(V.NavigationPlacement, SurfaceTypes.Node,
        (position => Rule.collapsed_restore_node(False{}, Rule.surface_base(Model.assemble(False{}, InteractionTypes.Scene{V.Scene{nav, main, layers,
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
    case V.SharedUIPage{work, name, source}: {==}
    case V.TaskGraphsPage{graphs, create}: {==}
    case V.HistorySearchPage{search, projects, works}: {==}
    case V.MissingObject{message}: {==}

def task_graphs_route_selects_nav(+world: M.World(), +session: E.Session) ->
  {Rule.task_graphs_navigation_selected(U.TaskGraphs{}, world, session) == True{} : Bool}:
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code, next_layer, model_preference, draft_model_manual, workspace_git, interactive} = session
  {==}

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
    +graphs => +create => +parent => +state => {==},
    task_graphs_route_selects_nav,
    +id => +value => route => +world => {==},
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
    navigation, filter, now, next, pending, previews, code, next_layer, model_preference, draft_model_manual, workspace_git, interactive}}, services} = before
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
        Rule.receipt(Core.step(Model.activity_requested_input(input, state), state)),
        element_receipt(capacity, state, key, SurfaceTypes.Press{}),
        Equal.cong(Maybe<&2, InteractionTypes.Input>, Rule.Receipt,
          resolved => Rule.receipt(Model.apply_input(resolved, state)),
          Model.resolve(ProductUI.observe(capacity, state), key, SurfaceTypes.Press{}), Some{input},
          resolve_available(ProductUI.observe(capacity, state), key, input, node_key, semantic, label, role, children, found)))
    ,
    +previous => origin => +panel => trigger => initial_attention => query => +layer_occurrence => +source_expanded => +decision_field => +parameter_buffer => +rest => present =>
      Equal.cong(Bool, +List<E.Layer>,
        unchanged => E.Layer{panel, Model.layer_trigger(unchanged, trigger, origin), initial_attention, query, layer_occurrence, source_expanded, decision_field, parameter_buffer} <> rest,
        Model.layer_present(previous, E.panel_target(panel)), True{}, present)
    ,
    +previous => origin => +panel => trigger => initial_attention => query => +layer_occurrence => +source_expanded => +decision_field => +parameter_buffer => +rest => absent =>
      Equal.cong(Bool, +List<E.Layer>,
        unchanged => E.Layer{panel, Model.layer_trigger(unchanged, trigger, origin), initial_attention, query, layer_occurrence, source_expanded, decision_field, parameter_buffer} <> rest,
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
      Some{Rule.SpeechProjection{Rule.expected_output_key(Rule.expected_message_source(task, id, source, state), Identity.Entity{parent, "message", Nat.show(id)}), "message/" ++ Nat.show(id), "Message",
        Rule.expected_speaker_role(speaker), SurfaceTypes.RichText{Rule.expected_message_source(task, id, source, state), text}}} : Maybe<&2, Rule.SpeechProjection>}:
  match speaker source:
    case Conversation.UserSpeech{} D.UserMessage{body}: {==}
    case Conversation.UserSpeech{} D.AssistantMessage{origin, body}: {==}
    case Conversation.UserSpeech{} D.FunctionCall{call}: {==}
    case Conversation.UserSpeech{} D.FunctionOutput{call_id, value, error}: {==}
    case Conversation.UserSpeech{} D.OperationResult{ticket, call_id, tool, value, error}: {==}
    case Conversation.UserSpeech{} D.FailureMessage{body}: {==}
    case Conversation.UserSpeech{} D.ModelContext{origin, value}: {==}
    case Conversation.UserSpeech{} D.ContextReplacement{value}: {==}
    case Conversation.UserSpeech{} D.ReasoningRecord{owner, effort, remaining, sampling}: {==}
    case Conversation.UserSpeech{} D.ContextMessage{context}: {==}
    case Conversation.UserSpeech{} D.HookRecord{task_id, call_id, plugin, outcome}: {==}
    case Conversation.UserSpeech{} D.ToolReceipt{task_id, operation_id, call, value, error}: {==}
    case Conversation.UserSpeech{} D.AfterRecord{task_id, operation_id, plugin, outcome}: {==}
    case Conversation.UserSpeech{} D.ApprovalRecord{task_id, operation_id, call, reviewer, outcome}: {==}
    case Conversation.UserSpeech{} D.ForkResult{task_id, call_id, branch}: {==}
    case Conversation.UserSpeech{} D.SpeechTranscript{owner, session_id, item_id, speaker, completion, text}: {==}
    case Conversation.UserSpeech{} D.SpeechDelegationReceipt{owner, session_id, delegation_id, mode, message}: {==}
    case Conversation.AssistantSpeech{} D.UserMessage{body}: {==}
    case Conversation.AssistantSpeech{} D.AssistantMessage{origin, body}: {==}
    case Conversation.AssistantSpeech{} D.FunctionCall{call}: {==}
    case Conversation.AssistantSpeech{} D.FunctionOutput{call_id, value, error}: {==}
    case Conversation.AssistantSpeech{} D.OperationResult{ticket, call_id, tool, value, error}: {==}
    case Conversation.AssistantSpeech{} D.FailureMessage{body}: {==}
    case Conversation.AssistantSpeech{} D.ModelContext{origin, value}: {==}
    case Conversation.AssistantSpeech{} D.ContextReplacement{value}: {==}
    case Conversation.AssistantSpeech{} D.ReasoningRecord{owner, effort, remaining, sampling}: {==}
    case Conversation.AssistantSpeech{} D.ContextMessage{context}: {==}
    case Conversation.AssistantSpeech{} D.HookRecord{task_id, call_id, plugin, outcome}: {==}
    case Conversation.AssistantSpeech{} D.ToolReceipt{task_id, operation_id, call, value, error}: {==}
    case Conversation.AssistantSpeech{} D.AfterRecord{task_id, operation_id, plugin, outcome}: {==}
    case Conversation.AssistantSpeech{} D.ApprovalRecord{task_id, operation_id, call, reviewer, outcome}: {==}
    case Conversation.AssistantSpeech{} D.ForkResult{task_id, call_id, branch}: {==}
    case Conversation.AssistantSpeech{} D.SpeechTranscript{owner, session_id, item_id, speaker, completion, text}: {==}
    case Conversation.AssistantSpeech{} D.SpeechDelegationReceipt{owner, session_id, delegation_id, mode, message}: {==}


def structure_evidence(recipe: Composition.Recipe)
  -> {Composition.structure(recipe) == Rule.expected_structure(recipe) : Composition.Structure}:
  match recipe:
    case Composition.Recipe{measure, heading, Composition.CenteredCreation{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.ChronologicalReading{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.ProjectSections{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.ProjectRows{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.StageColumns{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.AgentRows{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.SharedInterfaceBody{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.TaskGraphRows{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.UnavailableNotice{}, composer, decisions, latest}: {==}

def current_composer_context(+identity: U.Editor, revision: Nat, message: U.Text,
  +footer: +List<V.ComposerControl>, +context: Maybe<&2, Context.Preview>, assessment: Experience.Assessment, submit: V.ControlDeclaration,
  feedback: U.Feedback, pending: Bool, +world: M.World()) ->
  {Rule.introduction_context(View.creation_introduction(Some{V.ComposerScene{identity, revision, message, V.Creation{}, Nil{}, footer, View.preview_observation(context), assessment, submit, feedback, pending}}, world)) == context : Maybe<&2, Context.Preview>}:
  match context:
    case None{}: {==}
    case Some{preview}: {==}

def composer_has_context(+message: U.Text, +profile: String, reasoning: String, +context: Context.Configuration,
  scene: V.EditorScene, +world: M.World(), +work: Maybe<&2, Nat>, +create_worktree: U.TaskWorkspace) ->
  {Rule.composer_footer(View.composer_scene(U.NewTask{message, profile, reasoning, context, create_worktree, work}, scene, world)) ==
    [View.scoped_model_control(profile, reasoning, world, work),
         V.ComposerControl{UX.permissions_property(U.NewTaskEditor{work}, Context.DraftExecution{Context.preview(context, world)}), View.context_control("composer/permissions/" ++ U.editor_key(U.NewTaskEditor{work}), View.observation_permissions(Context.DraftExecution{Context.preview(context, world)}, Board.profiles(world)), U.PermissionsConfiguration{U.NewTaskEditor{work}})}] : +List<V.ComposerControl>}:
  V.EditorScene{identity, revision, groups, sections, assessment, submit, feedback, pending} = scene
  {==}

def creation_phase(scene: V.EditorScene, message: U.Text, profile: String, reasoning: String, context: Context.Configuration, world: M.World(), +work: Maybe<&2, Nat>, +create_worktree: U.TaskWorkspace) ->
  {Rule.composer_phase(View.composer_scene(U.NewTask{message, profile, reasoning, context, create_worktree, work}, scene, world)) == Some{V.Creation{}} : Maybe<&2, V.ComposerPhase>}:
  V.EditorScene{identity, revision, groups, sections, assessment, submit, feedback, pending} = scene
  {==}

def conversation_phase(scene: V.EditorScene, +task: Nat, message: U.Text, delivery: U.Delivery, world: M.World()) ->
  {Rule.composer_phase(View.composer_scene(U.Message{task, message, delivery}, scene, world)) == Some{V.Conversation{task}} : Maybe<&2, V.ComposerPhase>}:
  V.EditorScene{identity, revision, groups, sections, assessment, submit, feedback, pending} = scene
  {==}

def conversation_context_empty(scene: V.EditorScene, task: Nat, message: U.Text, delivery: U.Delivery, world: M.World()) ->
  {Rule.composer_creation_controls(View.composer_scene(U.Message{task, message, delivery}, scene, world)) == Nil{} : +List<V.ComposerControl>}:
  V.EditorScene{identity, revision, groups, sections, assessment, submit, feedback, pending} = scene
  {==}

def creation_controls(scene: V.EditorScene, message: U.Text, profile: String, reasoning: String, +context: Context.Configuration, +world: M.World(), +work: Maybe<&2, Nat>, +create_worktree: U.TaskWorkspace) ->
  {Rule.composer_creation_controls(View.composer_scene(U.NewTask{message, profile, reasoning, context, create_worktree, work}, scene, world)) ==
    [V.ComposerControl{UX.project_property(U.NewTaskEditor{work}, View.observation_project(Context.DraftExecution{Context.preview(context, world)}), world), View.context_control("composer/project", View.project_choice_label(View.creation_selected_project(Some{Context.preview(context, world)}, world)), U.ProjectPicker{})},
         V.ComposerControl{UX.workspace_property(U.NewTaskEditor{work}, Context.DraftExecution{Context.preview(context, world)}, world), View.context_control("composer/workspace/" ++ U.editor_key(U.NewTaskEditor{work}), View.observation_workspace(Context.DraftExecution{Context.preview(context, world)}), U.WorkspaceConfiguration{U.NewTaskEditor{work}})}] : +List<V.ComposerControl>}:
  V.EditorScene{identity, revision, groups, sections, assessment, submit, feedback, pending} = scene
  {==}

def workspace_description_agreement(+found: Maybe<&2, D.Workspace>, editor: U.Editor, parent: Identity.Key, state: InteractionTypes.State) ->
  {Rule.collection_instruction(Model.workspace_collection_menu(found, editor, None{}, parent, state)) == Rule.expected_collection_instruction(found) : Maybe<&2, SurfaceTypes.Meaning>}:
  match found:
    case None{}: {==}
    case Some{workspace}: {==}

def expanded_navigation_agreement(beside: Bool) ->
  {View.navigation_placement(beside, True{}) == Rule.expanded_navigation_placement(beside) : V.NavigationPlacement}:
  match beside:
    case True{}: {==}
    case False{}: {==}

def collapsed_navigation_agreement(beside: Bool) ->
  {View.navigation_placement(beside, False{}) == V.CollapsedNavigation{} : V.NavigationPlacement}:
  match beside:
    case True{}: {==}
    case False{}: {==}

def Rule.composer_tree_present_agreement(identity, revision, message, phase, creation_context, execution_controls, context, assessment, submit, feedback, pending, parent, state):
  {==}

def Rule.composer_tree_agreement(view, parent, state):
  match view:
    case None{}: {==}
    case Some{V.ComposerScene{+identity, revision, message, phase, creation_context, execution_controls, context, assessment, submit, feedback, pending}}:
      Rule.composer_tree_present_agreement(identity, revision, message, phase, creation_context, execution_controls, context, assessment, submit, feedback, pending, parent, state)

def Rule.task_environment_control_belongs_to_new_task(editor, parent, state):
  match editor:
    case U.NewWorkGraphEditor{work}: {==}
    case U.WorkEditor{work}: {==}
    case U.NewTaskEditor{work}: {==}
    case U.MessageEditor{task}: {==}
    case U.ProjectEditor{project}: {==}
    case U.CardEditor{card}: {==}
    case U.AgentEditor{agent}: {==}
    case U.ForkEditor{task}: {==}
    case U.CompactEditor{task}: {==}
    case U.TaskGraphEditor{graph}: {==}
    case U.TitlePromptEditor{}: {==}

def Rule.cloud_task_voice_waits_for_creation(editor, revision, parent, speech): {==}

def Rule.composer_enclosure_present_agreement(identity, revision, message, phase, creation_context, execution_controls, context, assessment, submit, feedback, pending, parent, state):
  match creation_context:
    case Nil{}: {==}
    case Con{first, rest}: {==}

def Rule.composer_enclosure_agreement(view, parent, state):
  match view:
    case None{}: {==}
    case Some{V.ComposerScene{+identity, revision, message, phase, creation_context, execution_controls, context, assessment, submit, feedback, pending}}:
      Rule.composer_enclosure_present_agreement(identity, revision, message, phase, creation_context, execution_controls, context, assessment, submit, feedback, pending, parent, state)

def committed_permission_summary_agreement(+found: Maybe<&2, Context.EffectiveContext>, +parent: Identity.Key, +state: InteractionTypes.State) ->
  {Model.committed_permission_summary(found, parent, state) == Rule.expected_committed_permission_summary(found, parent, state) : +List<SurfaceTypes.Node>}:
  match found:
    case Some{context}: {==}
    case None{}: {==}

def Rule.committed_permission_summary_agreement(task, preview, parent, state):
  committed_permission_summary_agreement(View.committed_context(T.find(Commands.entries(E.program(Core.application(state))), task)), parent, state)

def Rule.task_permission_resets_absent(task, config, parent, state):
  {==}

def Rule.permission_menu_agreement(editor, group, parent, state):
  match group:
    case V.ExecutionInput{config, Context.ContextUnavailable{reason}, controls, projects, reviewers}: {==}
    case V.ExecutionInput{config, Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, controls, projects, reviewers}: {==}
    case V.MessageInput{value}: {==}
    case V.ModelInput{profile, reasoning, choices}: {==}
    case V.DeliveryInput{selected, send, steer}: {==}
    case V.ProjectNameInput{name}: {==}
    case V.ProjectWorkspaceInput{workspace, controls}: {==}
    case V.CardContentInput{value, projects, stages, priorities, owners}: {==}
    case V.CardAssistanceInput{enabled, profile, choices}: {==}
    case V.AgentIdentityInput{name, instructions, concurrency}: {==}
    case V.ForkInput{count, messages}: {==}
    case V.SummaryInput{summary}: {==}
    case V.TaskGraphInput{declaration}: {==}

def Rule.composition_evidence():
  Rule.CompositionRequirements{
    Rule.page_region_evidence(),
    beside => expanded_navigation_agreement(beside),
    beside => collapsed_navigation_agreement(beside),
    task => preview => parent => state => Rule.committed_permission_summary_agreement(task, preview, parent, state),
    task => config => parent => state => Rule.task_permission_resets_absent(task, config, parent, state),
    editor => group => parent => state => Rule.permission_menu_agreement(editor, group, parent, state),
    navigation => main => layers => placement => attention => {==},
    task => task_recipe_evidence(task),
    composer => approvals => return_latest => conversation_recipe_evidence(composer, approvals, return_latest),
    message => {==},
    parent => control => action_evidence(parent, control),
    id => speaker => text => source => task => parent => state => visible_speaker_evidence(id, speaker, text, source, task, parent, state),
    +id => attention => +expanded => summary => audit => expand => collapse => +task => +parent => +state => {==},
    view => parent => state => Rule.composer_tree_agreement(view, parent, state),
    editor => parent => state => workspace_description_agreement(Model.workspace_observed(Model.field_value(state, editor, Forms.WorkspaceDirectories{})), editor, parent, state),
    editor => parent => state => Rule.task_environment_control_belongs_to_new_task(editor, parent, state),
    view => parent => state => Rule.composer_enclosure_agreement(view, parent, state),
    recipe => structure_evidence(recipe),
    +context => +world => {==},
    identity => revision => message => footer => context => assessment => submit => feedback => pending => world => current_composer_context(identity, revision, message, footer, context, assessment, submit, feedback, pending, world),
    +input => +parent => +world => +session => +services => {==},
    +declaration => +rest => +parent => +state => {==},
    message => profile => reasoning => context => scene => world => work => create_worktree => composer_has_context(message, profile, reasoning, context, scene, world, work, create_worktree),
    fallback => {==},
    message => profile => reasoning => context => scene => world => work => create_worktree => creation_phase(scene, message, profile, reasoning, context, world, work, create_worktree),
    task => message => delivery => scene => world => conversation_phase(scene, task, message, delivery, world),
    task => message => delivery => scene => world => conversation_context_empty(scene, task, message, delivery, world),
    message => profile => reasoning => context => scene => world => work => create_worktree => creation_controls(scene, message, profile, reasoning, context, world, work, create_worktree)}

def Rule.passive_obstruction_has_no_paragraph(obstruction, assessment, parent, passive):
  Equal.cong(Bool, +List<SurfaceTypes.Node>, (hidden => Model.visible_action_obstruction_selected(hidden, obstruction, assessment, parent)), UX.passive_obstruction(obstruction), True{}, passive)
def Rule.workspace_failure_is_not_global_feedback(editor, revision, reason, parent): {==}
def Rule.property_source_hidden_until_requested(property, parent): {==}
def Rule.requested_property_source_is_owner_observation(property, parent): {==}
def Rule.property_source_uses_actual_top_layer(property, parent, state): {==}

def Rule.property_source_toggle_uses_actual_control(editor, parent, state): {==}
def Rule.property_source_toggle_exposes_expansion(identity, label, prominence, input, availability, expanded, parent): {==}

def Rule.property_source_controls_use_actual_top_layer(property, parent, state): {==}
def Rule.workspace_current_retains_context_observation(preview, parent): {==}
def Rule.permission_scope_retains_context_observation(editor, observation, parent, state): {==}


def Rule.interactive_text_retains_exact_component_owner(node, raw):
  IM.ExpandedNode{identity, occurrence, tag, attributes, binding, children} = node
  {==}

def Rule.interactive_checked_retains_exact_component_owner(node):
  IM.ExpandedNode{identity, occurrence, tag, attributes, binding, children} = node
  {==}

def Rule.interactive_unchecked_retains_exact_component_owner(node):
  IM.ExpandedNode{identity, occurrence, tag, attributes, binding, children} = node
  {==}

def Rule.interactive_press_retains_exact_component_owner(node):
  IM.ExpandedNode{identity, occurrence, tag, attributes, binding, children} = node
  {==}

def Rule.interactive_enabled_view_retains_command_and_owner(event, command, label): {==}

def Rule.interactive_disabled_view_has_no_input(event, command, label): {==}

def Rule.interactive_region_has_no_control_input(identity, visible, gesture): {==}

def Rule.interactive_field_focus_follows_enabled(identity, occurrence, tag, attributes, state_id, schema, raw, canonical, validation, enabled, children): {==}

def Rule.interactive_action_focus_requires_enabled_and_settled(identity, occurrence, tag, attributes, kind, enabled, pending, children): {==}

def Rule.interactive_view_focus_follows_enabled(event, command, label, enabled): {==}

def Rule.interactive_passive_node_has_no_focus(identity, occurrence, tag, attributes, children): {==}


def Rule.discarded_unfinished_zero_has_no_notice(task, parent): {==}

def Rule.discarded_unfinished_positive_discloses_count_and_clear_action(count, task, parent): {==}

def deferred_node_fallback(+found: Maybe<&2, SurfaceTypes.Node>, fallback: Unit -> Maybe<&2, SurfaceTypes.Node>) ->
  {Model.find_node_fallback(found, fallback) == Model.prefer_node(found, fallback(Unit{})) : Maybe<&2, SurfaceTypes.Node>}:
  match found:
    case None{}: {==}
    case Some{node}: {==}

def deferred_node_match(+same: Bool, +node: SurfaceTypes.Node,
  descendants: Unit -> Maybe<&2, SurfaceTypes.Node>, siblings: Unit -> Maybe<&2, SurfaceTypes.Node>) ->
  {Model.find_node_match(same, node, descendants, siblings) ==
    Bool.pick((Maybe<&2, SurfaceTypes.Node>), same, Some{node},
      Model.prefer_node(descendants(Unit{}), siblings(Unit{}))) : Maybe<&2, SurfaceTypes.Node>}:
  match same:
    case True{}: {==}
    case False{}: deferred_node_fallback(descendants(Unit{}), siblings)

def prefer_node_step(+same: Bool, +node: SurfaceTypes.Node,
  +tail: Maybe<&2, SurfaceTypes.Node>, +fallback: Maybe<&2, SurfaceTypes.Node>) ->
  {Model.prefer_node(Bool.pick((Maybe<&2, SurfaceTypes.Node>), same, Some{node}, tail), fallback) ==
    Bool.pick((Maybe<&2, SurfaceTypes.Node>), same, Some{node}, Model.prefer_node(tail, fallback)) : Maybe<&2, SurfaceTypes.Node>}:
  match same:
    case False{}: {==}
    case True{}: {==}

def first_named_append(+left: +List<SurfaceTypes.Node>, +right: +List<SurfaceTypes.Node>, +key: String) ->
  {Rule.first_named_flat(List.append(&2, SurfaceTypes.Node, left, right), key) ==
    Model.prefer_node(Rule.first_named_flat(left, key), Rule.first_named_flat(right, key)) : Maybe<&2, SurfaceTypes.Node>}:
  match left:
    case Nil{}: {==}
    case Con{+node, +rest}:
      +tail: Maybe<&2, SurfaceTypes.Node> = Rule.first_named_flat(rest, key)
      +fallback: Maybe<&2, SurfaceTypes.Node> = Rule.first_named_flat(right, key)
      +appended: Maybe<&2, SurfaceTypes.Node> = Rule.first_named_flat(List.append(&2, SurfaceTypes.Node, rest, right), key)
      +same: Bool = String.eq(Rule.lookup_node_key(node), key)
      +middle: Maybe<&2, SurfaceTypes.Node> = Rule.first_named_node_step(key, node, Model.prefer_node(tail, fallback))
      Equal.trans((Maybe<&2, SurfaceTypes.Node>), Rule.first_named_node_step(key, node, appended), middle,
        Model.prefer_node(Rule.first_named_node_step(key, node, tail), fallback),
        Equal.cong((Maybe<&2, SurfaceTypes.Node>), (Maybe<&2, SurfaceTypes.Node>),
          (found => Rule.first_named_node_step(key, node, found)), appended, Model.prefer_node(tail, fallback), first_named_append(rest, right, key)),
        Equal.sym((Maybe<&2, SurfaceTypes.Node>),
          Model.prefer_node(Rule.first_named_node_step(key, node, tail), fallback), middle,
          prefer_node_step(same, node, tail, fallback)))

def complete_node_lookup(+nodes: +List<SurfaceTypes.Node>, +key: String) ->
  {Model.find_node(nodes, key) == Rule.first_named_node(nodes, key) : Maybe<&2, SurfaceTypes.Node>}:
  match nodes:
    case Nil{}: {==}
    case Con{SurfaceTypes.Node{+current, +semantic, +label, +role, +meaning, +children}, +rest}:
      +node: SurfaceTypes.Node = SurfaceTypes.Node{current, semantic, label, role, meaning, children}
      +encoded: String = Identity.encode(current)
      +safe: Bool = SafeText.string_equal(encoded, key)
      +plain: Bool = String.eq(encoded, key)
      +child: Maybe<&2, SurfaceTypes.Node> = Model.find_node(children, key)
      +sibling: Maybe<&2, SurfaceTypes.Node> = Model.find_node(rest, key)
      +expected_child: Maybe<&2, SurfaceTypes.Node> = Rule.first_named_node(children, key)
      +expected_sibling: Maybe<&2, SurfaceTypes.Node> = Rule.first_named_node(rest, key)
      +actual: Maybe<&2, SurfaceTypes.Node> = Model.find_node_match(safe, node, (_ => child), (_ => sibling))
      +deferred: Maybe<&2, SurfaceTypes.Node> = Bool.pick((Maybe<&2, SurfaceTypes.Node>), safe, Some{node}, Model.prefer_node(child, sibling))
      +compared: Maybe<&2, SurfaceTypes.Node> = Bool.pick((Maybe<&2, SurfaceTypes.Node>), plain, Some{node}, Model.prefer_node(child, sibling))
      +children_replaced: Maybe<&2, SurfaceTypes.Node> = Bool.pick((Maybe<&2, SurfaceTypes.Node>), plain, Some{node}, Model.prefer_node(expected_child, sibling))
      +siblings_replaced: Maybe<&2, SurfaceTypes.Node> = Bool.pick((Maybe<&2, SurfaceTypes.Node>), plain, Some{node}, Model.prefer_node(expected_child, expected_sibling))
      +target: Maybe<&2, SurfaceTypes.Node> = Rule.first_named_node(node <> rest, key)
      Equal.trans((Maybe<&2, SurfaceTypes.Node>), actual, deferred, target,
        deferred_node_match(safe, node, (_ => child), (_ => sibling)),
        Equal.trans((Maybe<&2, SurfaceTypes.Node>), deferred, compared, target,
          Equal.cong(Bool, (Maybe<&2, SurfaceTypes.Node>),
            (same => Bool.pick((Maybe<&2, SurfaceTypes.Node>), same, Some{node}, Model.prefer_node(child, sibling))),
            safe, plain, TextProof.public_refines(encoded, key)),
          Equal.trans((Maybe<&2, SurfaceTypes.Node>), compared, children_replaced, target,
            Equal.cong((Maybe<&2, SurfaceTypes.Node>), (Maybe<&2, SurfaceTypes.Node>),
              (found => Bool.pick((Maybe<&2, SurfaceTypes.Node>), plain, Some{node}, Model.prefer_node(found, sibling))),
              child, expected_child, complete_node_lookup(children, key)),
            Equal.trans((Maybe<&2, SurfaceTypes.Node>), children_replaced, siblings_replaced, target,
              Equal.cong((Maybe<&2, SurfaceTypes.Node>), (Maybe<&2, SurfaceTypes.Node>),
                (found => Bool.pick((Maybe<&2, SurfaceTypes.Node>), plain, Some{node}, Model.prefer_node(expected_child, found))),
                sibling, expected_sibling, complete_node_lookup(rest, key)),
              Equal.cong((Maybe<&2, SurfaceTypes.Node>), (Maybe<&2, SurfaceTypes.Node>),
                (found => Rule.first_named_node_step(key, node, found)),
                Model.prefer_node(expected_child, expected_sibling),
                Rule.first_named_flat(List.append(&2, SurfaceTypes.Node, Rule.preorder_nodes(children), Rule.preorder_nodes(rest)), key),
                Equal.sym((Maybe<&2, SurfaceTypes.Node>),
                  Rule.first_named_flat(List.append(&2, SurfaceTypes.Node, Rule.preorder_nodes(children), Rule.preorder_nodes(rest)), key),
                  Model.prefer_node(expected_child, expected_sibling),
                  first_named_append(Rule.preorder_nodes(children), Rule.preorder_nodes(rest), key)))))))

def Rule.complete_node_lookup(nodes, key):
  complete_node_lookup(nodes, key)


def fence_before_complete(+left: Model.FenceAttachment, +right: Model.FenceAttachment) ->
  {Model.fence_attachment_before(left, right) == Rule.required_fence_before(left, right) : Bool}:
  match left right:
    case Model.FenceAttachment{left_ordinal, left_interactive, left_node} Model.FenceAttachment{right_ordinal, right_interactive, right_node}: {==}

def fence_runs_ordered(runs: +List<+List<Model.FenceAttachment>>) -> Bool:
  match runs:
    case Nil{}: True{}
    case Con{run, rest}: Rule.fence_values_ordered(run) && fence_runs_ordered(rest)

def fence_values_nonempty(values: +List<Model.FenceAttachment>) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{first, rest}: True{}

def fence_runs_nonempty(runs: +List<+List<Model.FenceAttachment>>) -> Bool:
  match runs:
    case Nil{}: True{}
    case Con{run, rest}: fence_values_nonempty(run) && fence_runs_nonempty(rest)

def fence_run_weight(runs: +List<+List<Model.FenceAttachment>>) -> Nat:
  match runs:
    case Nil{}: 0n
    case Con{run, rest}: (List.length(&2, Model.FenceAttachment, run) + fence_run_weight(rest) : Nat)

def fence_true_left(+first: Bool, +second: Bool, +evidence: {(first && second) == True{} : Bool}) -> {first == True{} : Bool}:
  match first:
    case False{}: Logic.impossible({False{} == True{} : Bool}, evidence)
    case True{}: {==}

def fence_true_right(+first: Bool, +second: Bool, +evidence: {(first && second) == True{} : Bool}) -> {second == True{} : Bool}:
  match first:
    case False{}: Logic.impossible({second == True{} : Bool}, evidence)
    case True{}: evidence

def fence_true_and(+first: Bool, +second: Bool, +left: {first == True{} : Bool}, +right: {second == True{} : Bool}) ->
  {(first && second) == True{} : Bool}:
  Equal.trans(Bool, (first && second), (True{} && second), True{},
    Equal.cong(Bool, Bool, (value => value && second), first, True{}, left), right)

def code_region_complete(+scene: Code.Scene, +parent: Identity.Key) ->
  {Model.code_region(scene, parent) == Rule.required_code_region(scene) : SurfaceTypes.Node}:
  match scene:
    case Code.Scene{Code.Identity{source, ordinal}, literal, wrap, copy, True{}, controls}: {==}
    case Code.Scene{Code.Identity{source, ordinal}, literal, wrap, copy, False{}, controls}: {==}

def interactive_region_complete(+identity: Code.Identity, +visible: Bool, +scene: IM.Scene) ->
  {Model.interactive_region(identity, visible, scene) == Rule.required_interactive_region(identity, visible, scene) : SurfaceTypes.Node}:
  match visible:
    case False{}: {==}
    case True{}: {==}

def code_attachment_complete(+owned: Bool, +scene: Code.Scene, +parent: Identity.Key) ->
  {Model.code_attachment(owned, scene, parent) == Rule.required_code_attachment(owned, scene, parent) : +List<Model.FenceAttachment>}:
  match owned:
    case False{}: {==}
    case True{}:
      Code.Scene{Code.Identity{+source, +ordinal}, +literal, +wrap, +copy, +enabled, +controls} = scene
      Equal.cong(SurfaceTypes.Node, (+List<Model.FenceAttachment>), (node => [Model.FenceAttachment{ordinal, False{}, node}]),
        Model.code_region(scene, parent), Rule.required_code_region(scene), code_region_complete(scene, parent))

def code_attachments_complete(+values: +List<Code.Scene>, +source: Code.Source, +parent: Identity.Key) ->
  {Model.code_attachments(values, source, parent) == Rule.required_code_attachments(values, source, parent) : +List<Model.FenceAttachment>}:
  match values:
    case Nil{}: {==}
    case Con{Code.Scene{+identity, +literal, +wrap, +copy, +enabled, +controls}, +rest}:
      +scene: Code.Scene = Code.Scene{identity, literal, wrap, copy, enabled, controls}
      +owned: Bool = Code.belongs(identity, source)
      +actual_head: +List<Model.FenceAttachment> = Model.code_attachment(owned, scene, parent)
      +expected_head: +List<Model.FenceAttachment> = Rule.required_code_attachment(owned, scene, parent)
      +actual_rest: +List<Model.FenceAttachment> = Model.code_attachments(rest, source, parent)
      +expected_rest: +List<Model.FenceAttachment> = Rule.required_code_attachments(rest, source, parent)
      Equal.trans((+List<Model.FenceAttachment>),
        List.append(&2, Model.FenceAttachment, actual_head, actual_rest),
        List.append(&2, Model.FenceAttachment, expected_head, actual_rest),
        List.append(&2, Model.FenceAttachment, expected_head, expected_rest),
        Equal.cong((+List<Model.FenceAttachment>), (+List<Model.FenceAttachment>),
          (head => List.append(&2, Model.FenceAttachment, head, actual_rest)),
          actual_head, expected_head, code_attachment_complete(owned, scene, parent)),
        Equal.cong((+List<Model.FenceAttachment>), (+List<Model.FenceAttachment>),
          (tail => List.append(&2, Model.FenceAttachment, expected_head, tail)),
          actual_rest, expected_rest, code_attachments_complete(rest, source, parent)))

def interactive_attachments_complete(+values: +List<InteractiveDocuments.BlockScene>, +session: E.Session) ->
  {Model.interactive_attachments(values, session) == Rule.required_interactive_attachments(values, session) : +List<Model.FenceAttachment>}:
  match values:
    case Nil{}: {==}
    case Con{InteractiveDocuments.BlockScene{Code.Identity{+source, +ordinal}, +scene}, +rest}:
      +identity: Code.Identity = Code.Identity{source, ordinal}
      +visible = E.interactive_source_visible(identity, session)
      +actual: SurfaceTypes.Node = Model.interactive_region(identity, visible, scene)
      +required: SurfaceTypes.Node = Rule.required_interactive_region(identity, visible, scene)
      Equal.trans((+List<Model.FenceAttachment>),
        Model.FenceAttachment{ordinal, True{}, actual} <> Model.interactive_attachments(rest, session),
        Model.FenceAttachment{ordinal, True{}, required} <> Model.interactive_attachments(rest, session),
        Model.FenceAttachment{ordinal, True{}, required} <> Rule.required_interactive_attachments(rest, session),
        Equal.cong(SurfaceTypes.Node, (+List<Model.FenceAttachment>),
          (node => Model.FenceAttachment{ordinal, True{}, node} <> Model.interactive_attachments(rest, session)),
          actual, required, interactive_region_complete(identity, visible, scene)),
        Equal.cong((+List<Model.FenceAttachment>), (+List<Model.FenceAttachment>),
          (tail => Model.FenceAttachment{ordinal, True{}, required} <> tail),
          Model.interactive_attachments(rest, session), Rule.required_interactive_attachments(rest, session),
          interactive_attachments_complete(rest, session)))

def fence_collection_complete(+source: Code.Source, +parent: Identity.Key, +codes: +List<Code.Scene>,
  +scenes: +List<InteractiveDocuments.BlockScene>, +session: E.Session) ->
  {List.append(&2, Model.FenceAttachment, Model.code_attachments(codes, source, parent), Model.interactive_attachments(scenes, session)) ==
    List.append(&2, Model.FenceAttachment, Rule.required_code_attachments(codes, source, parent), Rule.required_interactive_attachments(scenes, session)) : +List<Model.FenceAttachment>}:
  +actual_codes: +List<Model.FenceAttachment> = Model.code_attachments(codes, source, parent)
  +expected_codes: +List<Model.FenceAttachment> = Rule.required_code_attachments(codes, source, parent)
  +actual_scenes: +List<Model.FenceAttachment> = Model.interactive_attachments(scenes, session)
  +expected_scenes: +List<Model.FenceAttachment> = Rule.required_interactive_attachments(scenes, session)
  Equal.trans((+List<Model.FenceAttachment>),
    List.append(&2, Model.FenceAttachment, actual_codes, actual_scenes),
    List.append(&2, Model.FenceAttachment, expected_codes, actual_scenes),
    List.append(&2, Model.FenceAttachment, expected_codes, expected_scenes),
    Equal.cong((+List<Model.FenceAttachment>), (+List<Model.FenceAttachment>),
      (values => List.append(&2, Model.FenceAttachment, values, actual_scenes)),
      actual_codes, expected_codes, code_attachments_complete(codes, source, parent)),
    Equal.cong((+List<Model.FenceAttachment>), (+List<Model.FenceAttachment>),
      (values => List.append(&2, Model.FenceAttachment, expected_codes, values)),
      actual_scenes, expected_scenes, interactive_attachments_complete(scenes, session)))

def fence_nodes_complete(+values: +List<Model.FenceAttachment>) ->
  {Model.fence_attachment_nodes(values) == Rule.required_fence_nodes(values) : +List<SurfaceTypes.Node>}:
  match values:
    case Nil{}: {==}
    case Con{Model.FenceAttachment{ordinal, interactive, +node}, +rest}:
      Equal.cong((+List<SurfaceTypes.Node>), (+List<SurfaceTypes.Node>),
        (tail => node <> tail), Model.fence_attachment_nodes(rest), Rule.required_fence_nodes(rest), fence_nodes_complete(rest))

def fence_origin_source_complete(+origin: Maybe<&2, D.OutputOrigin>, +viewer: Nat, +message: Nat, +session: E.Session) ->
  {Model.generated_source(origin, viewer, Code.Message{viewer, message}, True{}, session) ==
    Rule.expected_origin_source(origin, E.namespace(session), viewer, message) : Code.Source}:
  match origin:
    case None{}: {==}
    case Some{value}: {==}

def fence_message_source_complete(+viewer: Nat, +id: Nat, +message: D.Message, +state: InteractionTypes.State) ->
  {Model.message_source(viewer, id, message, state) == Rule.expected_message_source(viewer, id, message, state) : Code.Source}:
  fence_origin_source_complete(D.message_origin(message), viewer, id, E.session(Core.application(state)))

def fence_output_key_complete(+source: Code.Source, +fallback: Identity.Key) ->
  {Model.output_key(source, fallback) == Rule.expected_output_key(source, fallback) : Identity.Key}:
  match source:
    case Code.SharedDocument{namespace, owner}: {==}
    case Code.Message{task, message}: {==}
    case Code.StreamingPart{task, operation, part}: {==}
    case Code.Generated{namespace, viewer, origin, complete}: {==}

def fence_speaker_role_complete(+speaker: Conversation.Speaker) ->
  {Model.speaker_role(speaker) == Rule.expected_speaker_role(speaker) : SurfaceTypes.Role}:
  match speaker:
    case Conversation.UserSpeech{}: {==}
    case Conversation.AssistantSpeech{}: {==}

def fence_key_before(+ao: Nat, ai: Bool, +bo: Nat, bi: Bool) -> Bool:
  Nat.is_lt(ao, bo) || (Nat.is_eq(ao, bo) && (Bool.not(ai) || bi))

def fence_nat_equal_reflect(+a: Nat, +b: Nat, +observed: {Nat.is_eq(a, b) == True{} : Bool}) ->
  {a == b : Nat}:
  match a b:
    case 0n 0n: {==}
    case 0n 1n+bp: Logic.impossible({0n == 1n+bp : Nat}, observed)
    case 1n+ap 0n: Logic.impossible({1n+ap == 0n : Nat}, observed)
    case 1n+ap 1n+bp:
      Equal.cong(Nat, Nat, (value => 1n+value), ap, bp, fence_nat_equal_reflect(ap, bp, observed))

def fence_key_reverse_false(+ao: Nat, +ai: Bool, +bo: Nat, +bi: Bool,
  +observed: {fence_key_before(ao, ai, bo, bi) == False{} : Bool}) ->
  {fence_key_before(bo, bi, ao, ai) == True{} : Bool}:
  match ao ai bo bi:
    case 0n False{} 0n False{}: {==}
    case 0n False{} 0n True{}:
      Logic.impossible({False{} == True{} : Bool}, Equal.sym(Bool, True{}, False{}, observed))
    case 0n True{} 0n False{}: {==}
    case 0n True{} 0n True{}: {==}
    case 0n a 1n+bp b:
      Logic.impossible({fence_key_before(1n+bp, b, 0n, a) == True{} : Bool},
        Equal.sym(Bool, True{}, False{}, observed))
    case 1n+ap _ 0n +_: {==}
    case 1n+ap a 1n+bp b: fence_key_reverse_false(ap, a, bp, b, observed)

def fence_key_trans(+ao: Nat, +ai: Bool, +bo: Nat, +bi: Bool, +co: Nat, +ci: Bool,
  +ab: {fence_key_before(ao, ai, bo, bi) == True{} : Bool},
  +bc: {fence_key_before(bo, bi, co, ci) == True{} : Bool}) ->
  {fence_key_before(ao, ai, co, ci) == True{} : Bool}:
  match ao ai bo bi co ci:
    case 0n False{} 0n False{} 0n False{}: {==}
    case 0n False{} 0n False{} 0n True{}: {==}
    case 0n False{} 0n True{} 0n False{}: {==}
    case 0n False{} 0n True{} 0n True{}: {==}
    case 0n True{} 0n False{} 0n False{}: Logic.impossible({False{} == True{} : Bool}, ab)
    case 0n True{} 0n False{} 0n True{}: {==}
    case 0n True{} 0n True{} 0n False{}: Logic.impossible({False{} == True{} : Bool}, bc)
    case 0n True{} 0n True{} 0n True{}: {==}
    case 0n _ 0n _ 1n+cp +_: {==}
    case 0n a 1n+bp _ 0n c:
      Logic.impossible({fence_key_before(0n, a, 0n, c) == True{} : Bool}, bc)
    case 0n _ 1n+bp _ 1n+cp +_: {==}
    case 1n+ap a 0n _ 0n c:
      Logic.impossible({fence_key_before(1n+ap, a, 0n, c) == True{} : Bool}, ab)
    case 1n+ap a 0n _ 1n+cp c:
      Logic.impossible({fence_key_before(1n+ap, a, 1n+cp, c) == True{} : Bool}, ab)
    case 1n+ap a 1n+bp _ 0n c:
      Logic.impossible({fence_key_before(1n+ap, a, 0n, c) == True{} : Bool}, bc)
    case 1n+ap a 1n+bp b 1n+cp c:
      fence_key_trans(ap, a, bp, b, cp, c, ab, bc)

def fence_before_reverse_false(+left: Model.FenceAttachment, +right: Model.FenceAttachment,
  +observed: {Rule.required_fence_before(left, right) == False{} : Bool}) ->
  {Rule.required_fence_before(right, left) == True{} : Bool}:
  Model.FenceAttachment{+ao, +ai, an} = left
  Model.FenceAttachment{+bo, +bi, bn} = right
  fence_key_reverse_false(ao, ai, bo, bi, observed)

def fence_before_trans(+left: Model.FenceAttachment, +middle: Model.FenceAttachment, +right: Model.FenceAttachment,
  +ab: {Rule.required_fence_before(left, middle) == True{} : Bool},
  +bc: {Rule.required_fence_before(middle, right) == True{} : Bool}) ->
  {Rule.required_fence_before(left, right) == True{} : Bool}:
  Model.FenceAttachment{+ao, +ai, an} = left
  Model.FenceAttachment{+bo, +bi, bn} = middle
  Model.FenceAttachment{+co, +ci, cn} = right
  fence_key_trans(ao, ai, bo, bi, co, ci, ab, bc)

def fence_bound_append(+minimum: Model.FenceAttachment, +left: +List<Model.FenceAttachment>, +right: +List<Model.FenceAttachment>,
  +left_bound: {Rule.fence_all_after(minimum, left) == True{} : Bool}, +right_bound: {Rule.fence_all_after(minimum, right) == True{} : Bool}) ->
  {Rule.fence_all_after(minimum, List.append(&2, Model.FenceAttachment, left, right)) == True{} : Bool}:
  match left:
    case Nil{}: right_bound
    case Con{+first, +rest}:
      fence_true_and(Rule.required_fence_before(minimum, first), Rule.fence_all_after(minimum, List.append(&2, Model.FenceAttachment, rest, right)),
        fence_true_left(Rule.required_fence_before(minimum, first), Rule.fence_all_after(minimum, rest), left_bound),
        fence_bound_append(minimum, rest, right,
          fence_true_right(Rule.required_fence_before(minimum, first), Rule.fence_all_after(minimum, rest), left_bound), right_bound))

def fence_bound_trans(+minimum: Model.FenceAttachment, +middle: Model.FenceAttachment, +values: +List<Model.FenceAttachment>,
  +first_bound: {Rule.required_fence_before(minimum, middle) == True{} : Bool},
  +bounds: {Rule.fence_all_after(middle, values) == True{} : Bool}) ->
  {Rule.fence_all_after(minimum, values) == True{} : Bool}:
  match values:
    case Nil{}: {==}
    case Con{+first, +rest}:
      fence_true_and(Rule.required_fence_before(minimum, first), Rule.fence_all_after(minimum, rest),
        fence_before_trans(minimum, middle, first, first_bound,
          fence_true_left(Rule.required_fence_before(middle, first), Rule.fence_all_after(middle, rest), bounds)),
        fence_bound_trans(minimum, middle, rest, first_bound,
          fence_true_right(Rule.required_fence_before(middle, first), Rule.fence_all_after(middle, rest), bounds)))

def fence_all_strict_after(+minimum: Model.FenceAttachment, values: +List<Model.FenceAttachment>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{first, rest}: Bool.not(Rule.required_fence_before(first, minimum)) && fence_all_strict_after(minimum, rest)

def fence_not_true(+value: Bool, +evidence: {Bool.not(value) == True{} : Bool}) -> {value == False{} : Bool}:
  match value:
    case False{}: {==}
    case True{}: Logic.impossible({True{} == False{} : Bool}, evidence)

def fence_false_bound_case(+left: Model.FenceAttachment, +middle: Model.FenceAttachment, +right: Model.FenceAttachment,
  result: Bool, +observed: {Rule.required_fence_before(middle, right) == result : Bool},
  +lm: {Rule.required_fence_before(left, middle) == True{} : Bool},
  +lr: {Rule.required_fence_before(left, right) == False{} : Bool}) ->
  {Rule.required_fence_before(middle, right) == False{} : Bool}:
  match result:
    case False{}: observed
    case True{}:
      Logic.impossible({Rule.required_fence_before(middle, right) == False{} : Bool},
        Equal.trans(Bool, False{}, Rule.required_fence_before(left, right), True{},
          Equal.sym(Bool, Rule.required_fence_before(left, right), False{}, lr), fence_before_trans(left, middle, right, lm, observed)))

def fence_strict_bound(+head: Model.FenceAttachment, +minimum: Model.FenceAttachment, +values: +List<Model.FenceAttachment>,
  +strict: {Rule.required_fence_before(head, minimum) == False{} : Bool},
  +bounded: {Rule.fence_all_after(head, values) == True{} : Bool}) ->
  {fence_all_strict_after(minimum, values) == True{} : Bool}:
  match values:
    case Nil{}: {==}
    case Con{+first, +rest}:
      fence_true_and(Bool.not(Rule.required_fence_before(first, minimum)), fence_all_strict_after(minimum, rest),
        Equal.cong(Bool, Bool, Bool.not, Rule.required_fence_before(first, minimum), False{},
          fence_false_bound_case(head, first, minimum, Rule.required_fence_before(first, minimum), {==},
            fence_true_left(Rule.required_fence_before(head, first), Rule.fence_all_after(head, rest), bounded), strict)),
        fence_strict_bound(head, minimum, rest, strict,
          fence_true_right(Rule.required_fence_before(head, first), Rule.fence_all_after(head, rest), bounded)))

def fence_run_count(runs: +List<+List<Model.FenceAttachment>>) -> Nat:
  List.length(&2, +List<Model.FenceAttachment>, runs)

def fence_count_spare_step(+count: Nat, +limit: Nat,
  +fits: {Nat.is_le(count, limit) == True{} : Bool}) ->
  {Nat.is_le(count, 1n+limit) == True{} : Bool}:
  match count limit:
    case 0n +_: {==}
    case 1n+rest 0n:
      Logic.impossible({Nat.is_le(1n+rest, 1n) == True{} : Bool}, fits)
    case 1n+rest 1n+available:
      fence_count_spare_step(rest, available, fits)

def fence_count_budget_chain(+count: Nat, +upper: Nat, +budget: Nat,
  +bounded: {Nat.is_le(count, upper) == True{} : Bool},
  +fits: {Nat.is_le(upper, budget) == True{} : Bool}) ->
  {Nat.is_le(count, budget) == True{} : Bool}:
  match count upper budget:
    case 0n _ 0n: {==}
    case 0n _ 1n+available: {==}
    case 1n+rest 0n _:
      Logic.impossible({Nat.is_le(1n+rest, budget) == True{} : Bool}, bounded)
    case 1n+rest 1n+middle 0n:
      Logic.impossible({Nat.is_le(1n+rest, 0n) == True{} : Bool}, fits)
    case 1n+rest 1n+middle 1n+available:
      fence_count_budget_chain(rest, middle, available, bounded, fits)

def fence_mass_prefix_budget(+prefix: Nat, +remaining: Nat, +budget: Nat,
  +fits: {Nat.is_le(Nat.add(prefix, remaining), budget) == True{} : Bool}) ->
  {Nat.is_le(prefix, budget) == True{} : Bool}:
  match prefix budget:
    case 0n 0n: {==}
    case 0n 1n+available: {==}
    case 1n+rest 0n:
      Logic.impossible({Nat.is_le(1n+rest, 0n) == True{} : Bool}, fits)
    case 1n+rest 1n+available:
      fence_mass_prefix_budget(rest, remaining, available, fits)

def fence_mass_suffix_budget(+prefix: Nat, +remaining: Nat, +budget: Nat,
  +fits: {Nat.is_le(Nat.add(prefix, remaining), budget) == True{} : Bool}) ->
  {Nat.is_le(remaining, budget) == True{} : Bool}:
  match prefix budget:
    case 0n _: fits
    case 1n+rest 0n:
      Logic.impossible({Nat.is_le(remaining, 0n) == True{} : Bool}, fits)
    case 1n+rest 1n+available:
      fence_count_spare_step(remaining, available,
        fence_mass_suffix_budget(rest, remaining, available, fits))

def fence_append_length(+xs: +List<Model.FenceAttachment>, +ys: +List<Model.FenceAttachment>) ->
  {List.length(&2, Model.FenceAttachment, List.append(&2, Model.FenceAttachment, xs, ys)) ==
    Nat.add(List.length(&2, Model.FenceAttachment, xs), List.length(&2, Model.FenceAttachment, ys)) : Nat}:
  match xs:
    case Nil{}: {==}
    case Con{first, rest}:
      Equal.cong(Nat, Nat, (count => 1n+count),
        List.length(&2, Model.FenceAttachment, List.append(&2, Model.FenceAttachment, rest, ys)),
        Nat.add(List.length(&2, Model.FenceAttachment, rest), List.length(&2, Model.FenceAttachment, ys)),
        fence_append_length(rest, ys))

def fence_reverse_go_length(+xs: +List<Model.FenceAttachment>, +acc: +List<Model.FenceAttachment>) ->
  {List.length(&2, Model.FenceAttachment, List.reverse.go(&2, Model.FenceAttachment, xs, acc)) ==
    Nat.add(List.length(&2, Model.FenceAttachment, xs), List.length(&2, Model.FenceAttachment, acc)) : Nat}:
  match xs:
    case Nil{}: {==}
    case Con{+first, +rest}:
      Equal.trans(Nat,
        List.length(&2, Model.FenceAttachment, List.reverse.go(&2, Model.FenceAttachment, rest, first <> acc)),
        Nat.add(List.length(&2, Model.FenceAttachment, rest), 1n+List.length(&2, Model.FenceAttachment, acc)),
        1n+Nat.add(List.length(&2, Model.FenceAttachment, rest), List.length(&2, Model.FenceAttachment, acc)),
        fence_reverse_go_length(rest, first <> acc),
        Alg.nat_add_succ(List.length(&2, Model.FenceAttachment, rest), List.length(&2, Model.FenceAttachment, acc)))

def fence_concat_length(+runs: +List<+List<Model.FenceAttachment>>) ->
  {List.length(&2, Model.FenceAttachment, List.concat(&2, Model.FenceAttachment, runs)) ==
    fence_run_weight(runs) : Nat}:
  match runs:
    case Nil{}: {==}
    case Con{+first, +rest}:
      Equal.trans(Nat,
        List.length(&2, Model.FenceAttachment, List.append(&2, Model.FenceAttachment, first,
          List.concat(&2, Model.FenceAttachment, rest))),
        Nat.add(List.length(&2, Model.FenceAttachment, first),
          List.length(&2, Model.FenceAttachment, List.concat(&2, Model.FenceAttachment, rest))),
        Nat.add(List.length(&2, Model.FenceAttachment, first), fence_run_weight(rest)),
        fence_append_length(first, List.concat(&2, Model.FenceAttachment, rest)),
        Equal.cong(Nat, Nat, (count => Nat.add(List.length(&2, Model.FenceAttachment, first), count)),
          List.length(&2, Model.FenceAttachment, List.concat(&2, Model.FenceAttachment, rest)),
          fence_run_weight(rest), fence_concat_length(rest)))

def fence_reverse_append_length(+acc: +List<Model.FenceAttachment>,
  +xs: +List<Model.FenceAttachment>, +ys: +List<Model.FenceAttachment>) ->
  {List.length(&2, Model.FenceAttachment,
      List.reverse.go(&2, Model.FenceAttachment, acc, List.append(&2, Model.FenceAttachment, xs, ys))) ==
    Nat.add(List.length(&2, Model.FenceAttachment, acc),
      Nat.add(List.length(&2, Model.FenceAttachment, xs), List.length(&2, Model.FenceAttachment, ys))) : Nat}:
  Equal.trans(Nat,
    List.length(&2, Model.FenceAttachment,
      List.reverse.go(&2, Model.FenceAttachment, acc, List.append(&2, Model.FenceAttachment, xs, ys))),
    Nat.add(List.length(&2, Model.FenceAttachment, acc),
      List.length(&2, Model.FenceAttachment, List.append(&2, Model.FenceAttachment, xs, ys))),
    Nat.add(List.length(&2, Model.FenceAttachment, acc),
      Nat.add(List.length(&2, Model.FenceAttachment, xs), List.length(&2, Model.FenceAttachment, ys))),
    fence_reverse_go_length(acc, List.append(&2, Model.FenceAttachment, xs, ys)),
    Equal.cong(Nat, Nat, (count => Nat.add(List.length(&2, Model.FenceAttachment, acc), count)),
      List.length(&2, Model.FenceAttachment, List.append(&2, Model.FenceAttachment, xs, ys)),
      Nat.add(List.length(&2, Model.FenceAttachment, xs), List.length(&2, Model.FenceAttachment, ys)),
      fence_append_length(xs, ys)))

def fence_selected_left_mass(+acc: Nat, +left: Nat, +right: Nat) ->
  {Nat.add(1n+acc, Nat.add(left, right)) == Nat.add(acc, Nat.add(1n+left, right)) : Nat}:
  Equal.sym(Nat, Nat.add(acc, 1n+Nat.add(left, right)),
    1n+Nat.add(acc, Nat.add(left, right)), Alg.nat_add_succ(acc, Nat.add(left, right)))

def fence_selected_right_mass(+acc: Nat, +left: Nat, +right: Nat) ->
  {Nat.add(1n+acc, Nat.add(left, right)) == Nat.add(acc, Nat.add(left, 1n+right)) : Nat}:
  Equal.trans(Nat, Nat.add(1n+acc, Nat.add(left, right)),
    Nat.add(acc, 1n+Nat.add(left, right)), Nat.add(acc, Nat.add(left, 1n+right)),
    Equal.sym(Nat, Nat.add(acc, 1n+Nat.add(left, right)),
      1n+Nat.add(acc, Nat.add(left, right)), Alg.nat_add_succ(acc, Nat.add(left, right))),
    Equal.cong(Nat, Nat, (count => Nat.add(acc, count)), 1n+Nat.add(left, right), Nat.add(left, 1n+right),
      Equal.sym(Nat, Nat.add(left, 1n+right), 1n+Nat.add(left, right), Alg.nat_add_succ(left, right))))

# The caller supplies both direct fuel-predecessor induction hypotheses.
# This case helper is nonrecursive.

def fence_merge_mass_selected(+fuel: Nat, +acc: +List<Model.FenceAttachment>,
  +x: Model.FenceAttachment, +xt: +List<Model.FenceAttachment>,
  +y: Model.FenceAttachment, +yt: +List<Model.FenceAttachment>, choice: Bool,
  +left_mass: {List.length(&2, Model.FenceAttachment,
      List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (x <> acc, xt, y <> yt))) ==
    Nat.add(1n+List.length(&2, Model.FenceAttachment, acc),
      Nat.add(List.length(&2, Model.FenceAttachment, xt), 1n+List.length(&2, Model.FenceAttachment, yt))) : Nat},
  +right_mass: {List.length(&2, Model.FenceAttachment,
      List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (y <> acc, x <> xt, yt))) ==
    Nat.add(1n+List.length(&2, Model.FenceAttachment, acc),
      Nat.add(1n+List.length(&2, Model.FenceAttachment, xt), List.length(&2, Model.FenceAttachment, yt))) : Nat}) ->
  {List.length(&2, Model.FenceAttachment,
      List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel,
        List.merge.step(Model.FenceAttachment, acc, x, xt, y, yt, choice))) ==
    Nat.add(List.length(&2, Model.FenceAttachment, acc),
      Nat.add(1n+List.length(&2, Model.FenceAttachment, xt), 1n+List.length(&2, Model.FenceAttachment, yt))) : Nat}:
  match choice:
    case True{}:
      Equal.trans(Nat,
        List.length(&2, Model.FenceAttachment, List.merge.go(~Model.FenceAttachment,
          ~Model.fence_attachment_before, fuel, (x <> acc, xt, y <> yt))),
        Nat.add(1n+List.length(&2, Model.FenceAttachment, acc),
          Nat.add(List.length(&2, Model.FenceAttachment, xt), 1n+List.length(&2, Model.FenceAttachment, yt))),
        Nat.add(List.length(&2, Model.FenceAttachment, acc),
          Nat.add(1n+List.length(&2, Model.FenceAttachment, xt), 1n+List.length(&2, Model.FenceAttachment, yt))),
        left_mass,
        fence_selected_left_mass(List.length(&2, Model.FenceAttachment, acc),
          List.length(&2, Model.FenceAttachment, xt), 1n+List.length(&2, Model.FenceAttachment, yt)))
    case False{}:
      Equal.trans(Nat,
        List.length(&2, Model.FenceAttachment, List.merge.go(~Model.FenceAttachment,
          ~Model.fence_attachment_before, fuel, (y <> acc, x <> xt, yt))),
        Nat.add(1n+List.length(&2, Model.FenceAttachment, acc),
          Nat.add(1n+List.length(&2, Model.FenceAttachment, xt), List.length(&2, Model.FenceAttachment, yt))),
        Nat.add(List.length(&2, Model.FenceAttachment, acc),
          Nat.add(1n+List.length(&2, Model.FenceAttachment, xt), 1n+List.length(&2, Model.FenceAttachment, yt))),
        right_mass,
        fence_selected_right_mass(List.length(&2, Model.FenceAttachment, acc),
          1n+List.length(&2, Model.FenceAttachment, xt), List.length(&2, Model.FenceAttachment, yt)))

def fence_merge_mass(+fuel: Nat, +acc: +List<Model.FenceAttachment>,
  +xs: +List<Model.FenceAttachment>, +ys: +List<Model.FenceAttachment>) ->
  {List.length(&2, Model.FenceAttachment,
      List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (acc, xs, ys))) ==
    Nat.add(List.length(&2, Model.FenceAttachment, acc),
      Nat.add(List.length(&2, Model.FenceAttachment, xs), List.length(&2, Model.FenceAttachment, ys))) : Nat}:
  match fuel:
    case 0n: fence_reverse_append_length(acc, xs, ys)
    case 1n+remaining:
      match xs ys:
        case Nil{} Nil{}: fence_reverse_go_length(acc, Nil{})
        case Nil{} Con{+y, +yt}: fence_reverse_go_length(acc, y <> yt)
        case Con{+x, +xt} Nil{}:
          Equal.trans(Nat,
            List.length(&2, Model.FenceAttachment, List.reverse.go(&2, Model.FenceAttachment, acc, x <> xt)),
            Nat.add(List.length(&2, Model.FenceAttachment, acc), 1n+List.length(&2, Model.FenceAttachment, xt)),
            Nat.add(List.length(&2, Model.FenceAttachment, acc),
              Nat.add(1n+List.length(&2, Model.FenceAttachment, xt), 0n)),
            fence_reverse_go_length(acc, x <> xt),
            Equal.cong(Nat, Nat, (count => Nat.add(List.length(&2, Model.FenceAttachment, acc), count)),
              1n+List.length(&2, Model.FenceAttachment, xt), Nat.add(1n+List.length(&2, Model.FenceAttachment, xt), 0n),
              Equal.sym(Nat, Nat.add(1n+List.length(&2, Model.FenceAttachment, xt), 0n),
                1n+List.length(&2, Model.FenceAttachment, xt), Alg.nat_add_zero(1n+List.length(&2, Model.FenceAttachment, xt)))))
        case Con{+x, +xt} Con{+y, +yt}:
          fence_merge_mass_selected(remaining, acc, x, xt, y, yt, Model.fence_attachment_before(x, y),
            fence_merge_mass(remaining, x <> acc, xt, y <> yt),
            fence_merge_mass(remaining, y <> acc, x <> xt, yt))

def fence_pass_weight(+n: Nat, +runs: +List<+List<Model.FenceAttachment>>) ->
  {fence_run_weight(List.sort.pass(~Model.FenceAttachment, ~Model.fence_attachment_before, n, runs)) ==
    fence_run_weight(runs) : Nat}:
  match runs:
    case Nil{}: {==}
    case Con{run, Nil{}}: {==}
    case Con{+first, Con{+second, +rest}}:
      +merged = List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, n, (Nil{}, first, second))
      +tail = List.sort.pass(~Model.FenceAttachment, ~Model.fence_attachment_before, n, rest)
      Equal.trans(Nat, Nat.add(List.length(&2, Model.FenceAttachment, merged), fence_run_weight(tail)),
        Nat.add(Nat.add(List.length(&2, Model.FenceAttachment, first), List.length(&2, Model.FenceAttachment, second)), fence_run_weight(tail)),
        Nat.add(List.length(&2, Model.FenceAttachment, first), Nat.add(List.length(&2, Model.FenceAttachment, second), fence_run_weight(rest))),
        Equal.cong(Nat, Nat, (count => Nat.add(count, fence_run_weight(tail))),
          List.length(&2, Model.FenceAttachment, merged),
          Nat.add(List.length(&2, Model.FenceAttachment, first), List.length(&2, Model.FenceAttachment, second)),
          fence_merge_mass(n, Nil{}, first, second)),
        Equal.trans(Nat,
          Nat.add(Nat.add(List.length(&2, Model.FenceAttachment, first), List.length(&2, Model.FenceAttachment, second)), fence_run_weight(tail)),
          Nat.add(Nat.add(List.length(&2, Model.FenceAttachment, first), List.length(&2, Model.FenceAttachment, second)), fence_run_weight(rest)),
          Nat.add(List.length(&2, Model.FenceAttachment, first), Nat.add(List.length(&2, Model.FenceAttachment, second), fence_run_weight(rest))),
          Equal.cong(Nat, Nat,
            (count => Nat.add(Nat.add(List.length(&2, Model.FenceAttachment, first), List.length(&2, Model.FenceAttachment, second)), count)),
            fence_run_weight(tail), fence_run_weight(rest), fence_pass_weight(n, rest)),
          Alg.nat_add_assoc(List.length(&2, Model.FenceAttachment, first), List.length(&2, Model.FenceAttachment, second), fence_run_weight(rest))))

def fence_pass_weight_budget(+n: Nat, +runs: +List<+List<Model.FenceAttachment>>,
  +fits: {Nat.is_le(fence_run_weight(runs), n) == True{} : Bool}) ->
  {Nat.is_le(fence_run_weight(List.sort.pass(~Model.FenceAttachment,
      ~Model.fence_attachment_before, n, runs)), n) == True{} : Bool}:
  Equal.trans(Bool,
    Nat.is_le(fence_run_weight(List.sort.pass(~Model.FenceAttachment, ~Model.fence_attachment_before, n, runs)), n),
    Nat.is_le(fence_run_weight(runs), n), True{},
    Equal.cong(Nat, Bool, (weight => Nat.is_le(weight, n)),
      fence_run_weight(List.sort.pass(~Model.FenceAttachment, ~Model.fence_attachment_before, n, runs)),
      fence_run_weight(runs), fence_pass_weight(n, runs)), fits)

def fence_pass_count_nonincreasing(+n: Nat, +runs: +List<+List<Model.FenceAttachment>>) ->
  {Nat.is_le(fence_run_count(List.sort.pass(~Model.FenceAttachment,
      ~Model.fence_attachment_before, n, runs)), fence_run_count(runs)) == True{} : Bool}:
  match runs:
    case Nil{}: {==}
    case Con{run, Nil{}}: {==}
    case Con{first, Con{second, +rest}}:
      fence_count_spare_step(fence_run_count(List.sort.pass(~Model.FenceAttachment,
        ~Model.fence_attachment_before, n, rest)), fence_run_count(rest), fence_pass_count_nonincreasing(n, rest))

def fence_pass_count_step(+n: Nat, +first: +List<Model.FenceAttachment>,
  +second: +List<Model.FenceAttachment>, +rest: +List<+List<Model.FenceAttachment>>) ->
  {Nat.is_le(fence_run_count(List.sort.pass(~Model.FenceAttachment,
      ~Model.fence_attachment_before, n, first <> second <> rest)), 1n+fence_run_count(rest)) == True{} : Bool}:
  fence_pass_count_nonincreasing(n, rest)

def fence_pass_budget(+n: Nat, +first: +List<Model.FenceAttachment>,
  +second: +List<Model.FenceAttachment>, +rest: +List<+List<Model.FenceAttachment>>, +predecessor: Nat,
  +fits: {Nat.is_le(2n+fence_run_count(rest), 1n+predecessor) == True{} : Bool}) ->
  {Nat.is_le(fence_run_count(List.sort.pass(~Model.FenceAttachment,
      ~Model.fence_attachment_before, n, first <> second <> rest)), predecessor) == True{} : Bool}:
  fence_count_budget_chain(fence_run_count(List.sort.pass(~Model.FenceAttachment,
    ~Model.fence_attachment_before, n, first <> second <> rest)), 1n+fence_run_count(rest), predecessor,
    fence_pass_count_step(n, first, second, rest), fits)

def fence_first_pair_budget(+first: +List<Model.FenceAttachment>, +second: +List<Model.FenceAttachment>,
  +rest: +List<+List<Model.FenceAttachment>>, +n: Nat,
  +fits: {Nat.is_le(fence_run_weight(first <> second <> rest), n) == True{} : Bool}) ->
  {Nat.is_le(Nat.add(List.length(&2, Model.FenceAttachment, first), List.length(&2, Model.FenceAttachment, second)), n) == True{} : Bool}:
  fence_mass_prefix_budget(
    Nat.add(List.length(&2, Model.FenceAttachment, first), List.length(&2, Model.FenceAttachment, second)),
    fence_run_weight(rest), n,
    Equal.trans(Bool,
      Nat.is_le(Nat.add(Nat.add(List.length(&2, Model.FenceAttachment, first), List.length(&2, Model.FenceAttachment, second)), fence_run_weight(rest)), n),
      Nat.is_le(fence_run_weight(first <> second <> rest), n), True{},
      Equal.cong(Nat, Bool, (weight => Nat.is_le(weight, n)),
        Nat.add(Nat.add(List.length(&2, Model.FenceAttachment, first), List.length(&2, Model.FenceAttachment, second)), fence_run_weight(rest)),
        fence_run_weight(first <> second <> rest),
        Alg.nat_add_assoc(List.length(&2, Model.FenceAttachment, first), List.length(&2, Model.FenceAttachment, second), fence_run_weight(rest))), fits))

def fence_remaining_weight_budget(+first: +List<Model.FenceAttachment>, +second: +List<Model.FenceAttachment>,
  +rest: +List<+List<Model.FenceAttachment>>, +n: Nat,
  +fits: {Nat.is_le(fence_run_weight(first <> second <> rest), n) == True{} : Bool}) ->
  {Nat.is_le(fence_run_weight(rest), n) == True{} : Bool}:
  fence_mass_suffix_budget(List.length(&2, Model.FenceAttachment, second), fence_run_weight(rest), n,
    fence_mass_suffix_budget(List.length(&2, Model.FenceAttachment, first),
      Nat.add(List.length(&2, Model.FenceAttachment, second), fence_run_weight(rest)), n, fits))

def fence_merge_left_budget(+xs: +List<Model.FenceAttachment>, +ys: +List<Model.FenceAttachment>, +fuel: Nat,
  +fits: {Nat.is_le(Nat.add(1n+List.length(&2, Model.FenceAttachment, xs),
      List.length(&2, Model.FenceAttachment, ys)), 1n+fuel) == True{} : Bool}) ->
  {Nat.is_le(Nat.add(List.length(&2, Model.FenceAttachment, xs),
      List.length(&2, Model.FenceAttachment, ys)), fuel) == True{} : Bool}:
  fits

def fence_merge_right_budget(+xs: +List<Model.FenceAttachment>, +ys: +List<Model.FenceAttachment>, +fuel: Nat,
  +fits: {Nat.is_le(Nat.add(List.length(&2, Model.FenceAttachment, xs),
      1n+List.length(&2, Model.FenceAttachment, ys)), 1n+fuel) == True{} : Bool}) ->
  {Nat.is_le(Nat.add(List.length(&2, Model.FenceAttachment, xs),
      List.length(&2, Model.FenceAttachment, ys)), fuel) == True{} : Bool}:
  match xs fuel:
    case Nil{} _: fits
    case Con{first, Nil{}} 0n:
      Logic.impossible({Nat.is_le(1n+List.length(&2, Model.FenceAttachment, ys), 0n) == True{} : Bool}, fits)
    case Con{first, Con{next, rest}} 0n:
      Logic.impossible({Nat.is_le(Nat.add(1n+List.length(&2, Model.FenceAttachment, rest),
        List.length(&2, Model.FenceAttachment, ys)), 0n) == True{} : Bool}, fits)
    case Con{first, rest} 1n+available:
      fence_merge_right_budget(rest, ys, available, fits)

# This selected-case helper and fence_merge_go_spare decrease the remaining
# fuel before following the selected actual Base.merge.step branch.

def fence_count_refl(+count: Nat) -> {Nat.is_le(count, count) == True{} : Bool}:
  match count:
    case 0n: {==}
    case 1n+rest: fence_count_refl(rest)

# Padding the weight by this run's remaining elements preserves a tail bound.

def fence_weight_prefix_padding(+prefix: Nat, +count: Nat, +weight: Nat,
  +fits: {Nat.is_le(count, weight) == True{} : Bool}) ->
  {Nat.is_le(count, Nat.add(prefix, weight)) == True{} : Bool}:
  match prefix:
    case 0n: fits
    case 1n+rest:
      fence_count_spare_step(count, Nat.add(rest, weight),
        fence_weight_prefix_padding(rest, count, weight, fits))

def fence_nonempty_count_weight(+runs: +List<+List<Model.FenceAttachment>>,
  +nonempty: {fence_runs_nonempty(runs) == True{} : Bool}) ->
  {Nat.is_le(fence_run_count(runs), fence_run_weight(runs)) == True{} : Bool}:
  match runs:
    case Nil{}: {==}
    case Con{+run, +rest}:
      match run:
        case Nil{}:
          Logic.impossible({Nat.is_le(1n+fence_run_count(rest), fence_run_weight(rest)) == True{} : Bool}, nonempty)
        case Con{first, +tail}:
          fence_weight_prefix_padding(List.length(&2, Model.FenceAttachment, tail),
            fence_run_count(rest), fence_run_weight(rest), fence_nonempty_count_weight(rest, nonempty))

def fence_weight_from_flatten(+values: +List<Model.FenceAttachment>,
  +runs: +List<+List<Model.FenceAttachment>>,
  +flattened: {List.concat(&2, Model.FenceAttachment, runs) == values : +List<Model.FenceAttachment>}) ->
  {fence_run_weight(runs) == List.length(&2, Model.FenceAttachment, values) : Nat}:
  Equal.trans(Nat, fence_run_weight(runs),
    List.length(&2, Model.FenceAttachment, List.concat(&2, Model.FenceAttachment, runs)),
    List.length(&2, Model.FenceAttachment, values),
    Equal.sym(Nat,
      List.length(&2, Model.FenceAttachment, List.concat(&2, Model.FenceAttachment, runs)),
      fence_run_weight(runs), fence_concat_length(runs)),
    Equal.cong(+List<Model.FenceAttachment>, Nat,
      (items => List.length(&2, Model.FenceAttachment, items)),
      List.concat(&2, Model.FenceAttachment, runs), values, flattened))

# A single equality transport initializes both bounds at N = original length.
# flattened is consumed once; no duplicability premise on proof evidence.

def fence_reverse_acc_append(+values: +List<Model.FenceAttachment>, +left: +List<Model.FenceAttachment>, +right: +List<Model.FenceAttachment>) ->
  {List.reverse.go(&2, Model.FenceAttachment, values, List.append(&2, Model.FenceAttachment, left, right)) ==
    List.append(&2, Model.FenceAttachment, List.reverse.go(&2, Model.FenceAttachment, values, left), right) : +List<Model.FenceAttachment>}:
  match values:
    case Nil{}: {==}
    case Con{first, rest}: fence_reverse_acc_append(rest, first <> left, right)

def fence_reverse_cons(+first: Model.FenceAttachment, +rest: +List<Model.FenceAttachment>) ->
  {List.reverse(&2, Model.FenceAttachment, first <> rest) ==
    List.append(&2, Model.FenceAttachment, List.reverse(&2, Model.FenceAttachment, rest), [first]) : +List<Model.FenceAttachment>}:
  fence_reverse_acc_append(rest, Nil{}, [first])

def fence_concat_append(+left: +List<+List<Model.FenceAttachment>>, +right: +List<+List<Model.FenceAttachment>>) ->
  {List.concat(&2, Model.FenceAttachment, List.append(&2, +List<Model.FenceAttachment>, left, right)) ==
    List.append(&2, Model.FenceAttachment, List.concat(&2, Model.FenceAttachment, left), List.concat(&2, Model.FenceAttachment, right)) : +List<Model.FenceAttachment>}:
  match left:
    case Nil{}: {==}
    case Con{+first, +rest}:
      Equal.trans((+List<Model.FenceAttachment>),
        List.concat(&2, Model.FenceAttachment, List.append(&2, +List<Model.FenceAttachment>, first <> rest, right)),
        List.append(&2, Model.FenceAttachment, first,
          List.append(&2, Model.FenceAttachment, List.concat(&2, Model.FenceAttachment, rest), List.concat(&2, Model.FenceAttachment, right))),
        List.append(&2, Model.FenceAttachment, List.concat(&2, Model.FenceAttachment, first <> rest), List.concat(&2, Model.FenceAttachment, right)),
        Equal.cong((+List<Model.FenceAttachment>), (+List<Model.FenceAttachment>),
          (xs => List.append(&2, Model.FenceAttachment, first, xs)),
          List.concat(&2, Model.FenceAttachment, List.append(&2, +List<Model.FenceAttachment>, rest, right)),
          List.append(&2, Model.FenceAttachment, List.concat(&2, Model.FenceAttachment, rest), List.concat(&2, Model.FenceAttachment, right)), fence_concat_append(rest, right)),
        Std.app_assoc(Model.FenceAttachment, first, List.concat(&2, Model.FenceAttachment, rest), List.concat(&2, Model.FenceAttachment, right)))

def fence_runs_reverse_acc_append(+values: +List<+List<Model.FenceAttachment>>, +left: +List<+List<Model.FenceAttachment>>, +right: +List<+List<Model.FenceAttachment>>) ->
  {List.reverse.go(&2, +List<Model.FenceAttachment>, values, List.append(&2, +List<Model.FenceAttachment>, left, right)) ==
    List.append(&2, +List<Model.FenceAttachment>, List.reverse.go(&2, +List<Model.FenceAttachment>, values, left), right) : +List<+List<Model.FenceAttachment>>}:
  match values:
    case Nil{}: {==}
    case Con{first, rest}: fence_runs_reverse_acc_append(rest, first <> left, right)

def fence_runs_reverse_cons(+first: +List<Model.FenceAttachment>, +rest: +List<+List<Model.FenceAttachment>>) ->
  {List.reverse(&2, +List<Model.FenceAttachment>, first <> rest) ==
    List.append(&2, +List<Model.FenceAttachment>, List.reverse(&2, +List<Model.FenceAttachment>, rest), [first]) : +List<+List<Model.FenceAttachment>>}:
  fence_runs_reverse_acc_append(rest, Nil{}, [first])

def fence_run_prefix(+current: +List<Model.FenceAttachment>, +completed: +List<+List<Model.FenceAttachment>>) -> +List<Model.FenceAttachment>:
  List.append(&2, Model.FenceAttachment, List.concat(&2, Model.FenceAttachment, List.reverse(&2, +List<Model.FenceAttachment>, completed)),
    List.reverse(&2, Model.FenceAttachment, current))

def fence_run_prefix_step(+ordered: Bool, +first: Model.FenceAttachment, +current: +List<Model.FenceAttachment>, +completed: +List<+List<Model.FenceAttachment>>) ->
  {fence_run_prefix(Model.fence_run_current(Model.fence_run_step(ordered, first, current, completed)),
    Model.fence_run_completed(Model.fence_run_step(ordered, first, current, completed))) ==
    List.append(&2, Model.FenceAttachment, fence_run_prefix(current, completed), [first]) : +List<Model.FenceAttachment>}:
  match ordered:
    case True{}:
      +prefix: +List<Model.FenceAttachment> = List.concat(&2, Model.FenceAttachment, List.reverse(&2, +List<Model.FenceAttachment>, completed))
      +reversed: +List<Model.FenceAttachment> = List.reverse(&2, Model.FenceAttachment, current)
      Equal.trans((+List<Model.FenceAttachment>),
        fence_run_prefix(first <> current, completed),
        List.append(&2, Model.FenceAttachment, prefix, List.append(&2, Model.FenceAttachment, reversed, [first])),
        List.append(&2, Model.FenceAttachment, fence_run_prefix(current, completed), [first]),
        Equal.cong((+List<Model.FenceAttachment>), (+List<Model.FenceAttachment>),
          (xs => List.append(&2, Model.FenceAttachment, prefix, xs)),
          List.reverse(&2, Model.FenceAttachment, first <> current),
          List.append(&2, Model.FenceAttachment, reversed, [first]), fence_reverse_cons(first, current)),
        Std.app_assoc(Model.FenceAttachment, prefix, reversed, [first]))
    case False{}:
      +reversed: +List<Model.FenceAttachment> = List.reverse(&2, Model.FenceAttachment, current)
      +runs: +List<+List<Model.FenceAttachment>> = List.reverse(&2, +List<Model.FenceAttachment>, completed)
      +prefix: +List<Model.FenceAttachment> = List.concat(&2, Model.FenceAttachment, runs)
      +actual: +List<Model.FenceAttachment> = fence_run_prefix([first], reversed <> completed)
      +middle0: +List<Model.FenceAttachment> = List.append(&2, Model.FenceAttachment,
        List.concat(&2, Model.FenceAttachment, List.append(&2, +List<Model.FenceAttachment>, runs, [reversed])), [first])
      +middle1: +List<Model.FenceAttachment> = List.append(&2, Model.FenceAttachment,
        List.append(&2, Model.FenceAttachment, prefix, List.concat(&2, Model.FenceAttachment, [reversed])), [first])
      +target: +List<Model.FenceAttachment> = List.append(&2, Model.FenceAttachment, fence_run_prefix(current, completed), [first])
      Equal.trans((+List<Model.FenceAttachment>), actual, middle0, target,
        Equal.cong((+List<+List<Model.FenceAttachment>>), (+List<Model.FenceAttachment>),
          (xs => List.append(&2, Model.FenceAttachment, List.concat(&2, Model.FenceAttachment, xs), [first])),
          List.reverse(&2, +List<Model.FenceAttachment>, reversed <> completed),
          List.append(&2, +List<Model.FenceAttachment>, runs, [reversed]), fence_runs_reverse_cons(reversed, completed)),
        Equal.trans((+List<Model.FenceAttachment>), middle0, middle1, target,
          Equal.cong((+List<Model.FenceAttachment>), (+List<Model.FenceAttachment>),
            (xs => List.append(&2, Model.FenceAttachment, xs, [first])),
            List.concat(&2, Model.FenceAttachment, List.append(&2, +List<Model.FenceAttachment>, runs, [reversed])),
            List.append(&2, Model.FenceAttachment, prefix, List.concat(&2, Model.FenceAttachment, [reversed])), fence_concat_append(runs, [reversed])),
          Equal.cong((+List<Model.FenceAttachment>), (+List<Model.FenceAttachment>),
            (xs => List.append(&2, Model.FenceAttachment, List.append(&2, Model.FenceAttachment, prefix, xs), [first])),
            List.concat(&2, Model.FenceAttachment, [reversed]), reversed, Std.app_nil_r(Model.FenceAttachment, reversed))))

def fence_concat_reverse_cons(+first: +List<Model.FenceAttachment>, +rest: +List<+List<Model.FenceAttachment>>) ->
  {List.concat(&2, Model.FenceAttachment, List.reverse(&2, +List<Model.FenceAttachment>, first <> rest)) ==
    List.append(&2, Model.FenceAttachment, List.concat(&2, Model.FenceAttachment, List.reverse(&2, +List<Model.FenceAttachment>, rest)), first) : +List<Model.FenceAttachment>}:
  +runs: +List<+List<Model.FenceAttachment>> = List.reverse(&2, +List<Model.FenceAttachment>, rest)
  +prefix: +List<Model.FenceAttachment> = List.concat(&2, Model.FenceAttachment, runs)
  Equal.trans((+List<Model.FenceAttachment>),
    List.concat(&2, Model.FenceAttachment, List.reverse(&2, +List<Model.FenceAttachment>, first <> rest)),
    List.concat(&2, Model.FenceAttachment, List.append(&2, +List<Model.FenceAttachment>, runs, [first])),
    List.append(&2, Model.FenceAttachment, prefix, first),
    Equal.cong((+List<+List<Model.FenceAttachment>>), (+List<Model.FenceAttachment>),
      (xs => List.concat(&2, Model.FenceAttachment, xs)),
      List.reverse(&2, +List<Model.FenceAttachment>, first <> rest),
      List.append(&2, +List<Model.FenceAttachment>, runs, [first]), fence_runs_reverse_cons(first, rest)),
    Equal.trans((+List<Model.FenceAttachment>),
      List.concat(&2, Model.FenceAttachment, List.append(&2, +List<Model.FenceAttachment>, runs, [first])),
      List.append(&2, Model.FenceAttachment, prefix, List.concat(&2, Model.FenceAttachment, [first])),
      List.append(&2, Model.FenceAttachment, prefix, first),
      fence_concat_append(runs, [first]),
      Equal.cong((+List<Model.FenceAttachment>), (+List<Model.FenceAttachment>),
        (xs => List.append(&2, Model.FenceAttachment, prefix, xs)),
        List.concat(&2, Model.FenceAttachment, [first]), first, Std.app_nil_r(Model.FenceAttachment, first))))

def fence_runs_complete_flatten(+current: +List<Model.FenceAttachment>, +completed: +List<+List<Model.FenceAttachment>>) ->
  {List.concat(&2, Model.FenceAttachment, Model.fence_runs_complete(current, completed)) == fence_run_prefix(current, completed) : +List<Model.FenceAttachment>}:
  match current:
    case Nil{}:
      Equal.sym((+List<Model.FenceAttachment>),
        fence_run_prefix(Nil{}, completed),
        List.concat(&2, Model.FenceAttachment, List.reverse(&2, +List<Model.FenceAttachment>, completed)),
        Std.app_nil_r(Model.FenceAttachment, List.concat(&2, Model.FenceAttachment, List.reverse(&2, +List<Model.FenceAttachment>, completed))))
    case Con{first, rest}: fence_concat_reverse_cons(List.reverse(&2, Model.FenceAttachment, first <> rest), completed)

def fence_natural_runs_flatten(+values: +List<Model.FenceAttachment>, +current: +List<Model.FenceAttachment>, +completed: +List<+List<Model.FenceAttachment>>) ->
  {List.concat(&2, Model.FenceAttachment, Model.fence_natural_runs(values, current, completed)) ==
    List.append(&2, Model.FenceAttachment, fence_run_prefix(current, completed), values) : +List<Model.FenceAttachment>}:
  match values:
    case Nil{}:
      Equal.trans((+List<Model.FenceAttachment>),
        List.concat(&2, Model.FenceAttachment, Model.fence_runs_complete(current, completed)),
        fence_run_prefix(current, completed), List.append(&2, Model.FenceAttachment, fence_run_prefix(current, completed), Nil{}),
        fence_runs_complete_flatten(current, completed),
        Equal.sym((+List<Model.FenceAttachment>), List.append(&2, Model.FenceAttachment, fence_run_prefix(current, completed), Nil{}),
          fence_run_prefix(current, completed), Std.app_nil_r(Model.FenceAttachment, fence_run_prefix(current, completed))))
    case Con{+first, +rest}:
      +ordered: Bool = Model.fence_run_ordered(first, current)
      +next: Model.FenceRunState = Model.fence_run_step(ordered, first, current, completed)
      +left: +List<Model.FenceAttachment> = List.concat(&2, Model.FenceAttachment,
        Model.fence_natural_runs(rest, Model.fence_run_current(next), Model.fence_run_completed(next)))
      +middle0: +List<Model.FenceAttachment> = List.append(&2, Model.FenceAttachment,
        fence_run_prefix(Model.fence_run_current(next), Model.fence_run_completed(next)), rest)
      +middle1: +List<Model.FenceAttachment> = List.append(&2, Model.FenceAttachment,
        List.append(&2, Model.FenceAttachment, fence_run_prefix(current, completed), [first]), rest)
      +target: +List<Model.FenceAttachment> = List.append(&2, Model.FenceAttachment, fence_run_prefix(current, completed), first <> rest)
      Equal.trans((+List<Model.FenceAttachment>), left, middle0, target,
        fence_natural_runs_flatten(rest, Model.fence_run_current(next), Model.fence_run_completed(next)),
        Equal.trans((+List<Model.FenceAttachment>), middle0, middle1, target,
          Equal.cong((+List<Model.FenceAttachment>), (+List<Model.FenceAttachment>),
            (xs => List.append(&2, Model.FenceAttachment, xs, rest)),
            fence_run_prefix(Model.fence_run_current(next), Model.fence_run_completed(next)),
            List.append(&2, Model.FenceAttachment, fence_run_prefix(current, completed), [first]),
            fence_run_prefix_step(ordered, first, current, completed)),
          Equal.sym((+List<Model.FenceAttachment>), target, middle1,
            Std.app_assoc(Model.FenceAttachment, fence_run_prefix(current, completed), [first], rest))))

def fence_natural_runs_preserve_all(+values: +List<Model.FenceAttachment>) ->
  {List.concat(&2, Model.FenceAttachment, Model.fence_natural_runs(values, Nil{}, Nil{})) == values : +List<Model.FenceAttachment>}:
  fence_natural_runs_flatten(values, Nil{}, Nil{})

def fence_current_reverse_tail(rest: +List<Model.FenceAttachment>, +top: Model.FenceAttachment) -> Bool:
  match rest:
    case Nil{}: True{}
    case Con{+previous, +tail}:
      Rule.required_fence_before(previous, top) && fence_current_reverse_tail(tail, previous)

def fence_current_reverse_ordered(current: +List<Model.FenceAttachment>) -> Bool:
  match current:
    case Nil{}: True{}
    case Con{top, rest}: fence_current_reverse_tail(rest, top)

def fence_natural_order_invariant(+current: +List<Model.FenceAttachment>, +completed: +List<+List<Model.FenceAttachment>>) -> Bool:
  fence_current_reverse_ordered(current) && (fence_runs_ordered(completed) && fence_runs_nonempty(completed))

def fence_reverse_acc_ordered(+rest: +List<Model.FenceAttachment>, +top: Model.FenceAttachment,
  +acc: +List<Model.FenceAttachment>,
  +chain: {fence_current_reverse_tail(rest, top) == True{} : Bool},
  +bound: {Rule.fence_all_after(top, acc) == True{} : Bool},
  +acc_ordered: {Rule.fence_values_ordered(acc) == True{} : Bool}) ->
  {Rule.fence_values_ordered(List.reverse.go(&2, Model.FenceAttachment, top <> rest, acc)) == True{} : Bool}:
  match rest:
    case Nil{}:
      fence_true_and(Rule.fence_all_after(top, acc), Rule.fence_values_ordered(acc), bound, acc_ordered)
    case Con{+previous, +tail}:
      fence_reverse_acc_ordered(tail, previous, top <> acc,
        fence_true_right(Rule.required_fence_before(previous, top), fence_current_reverse_tail(tail, previous), chain),
        fence_true_and(Rule.required_fence_before(previous, top), Rule.fence_all_after(previous, acc),
          fence_true_left(Rule.required_fence_before(previous, top), fence_current_reverse_tail(tail, previous), chain),
          fence_bound_trans(previous, top, acc,
            fence_true_left(Rule.required_fence_before(previous, top), fence_current_reverse_tail(tail, previous), chain), bound)),
        fence_true_and(Rule.fence_all_after(top, acc), Rule.fence_values_ordered(acc), bound, acc_ordered))

def fence_reversed_current_ordered(+current: +List<Model.FenceAttachment>,
  +ordered: {fence_current_reverse_ordered(current) == True{} : Bool}) ->
  {Rule.fence_values_ordered(List.reverse(&2, Model.FenceAttachment, current)) == True{} : Bool}:
  match current:
    case Nil{}: {==}
    case Con{+top, +rest}: fence_reverse_acc_ordered(rest, top, Nil{}, ordered, {==}, {==})

def fence_current_push_ordered(+value: Model.FenceAttachment, +current: +List<Model.FenceAttachment>,
  +ordered: {fence_current_reverse_ordered(current) == True{} : Bool},
  +observed: {Model.fence_run_ordered(value, current) == True{} : Bool}) ->
  {fence_current_reverse_ordered(value <> current) == True{} : Bool}:
  match current:
    case Nil{}: {==}
    case Con{+previous, +rest}:
      fence_true_and(Rule.required_fence_before(previous, value), fence_current_reverse_tail(rest, previous),
        Equal.trans(Bool, Rule.required_fence_before(previous, value), Model.fence_attachment_before(previous, value), True{},
          Equal.sym(Bool, Model.fence_attachment_before(previous, value), Rule.required_fence_before(previous, value),
            fence_before_complete(previous, value)), observed), ordered)

def fence_reverse_acc_nonempty(+values: +List<Model.FenceAttachment>, +first: Model.FenceAttachment,
  +rest: +List<Model.FenceAttachment>) ->
  {fence_values_nonempty(List.reverse.go(&2, Model.FenceAttachment, values, first <> rest)) == True{} : Bool}:
  match values:
    case Nil{}: {==}
    case Con{value, tail}: fence_reverse_acc_nonempty(tail, value, first <> rest)

def fence_reversed_current_nonempty(+current: +List<Model.FenceAttachment>,
  +nonempty: {fence_values_nonempty(current) == True{} : Bool}) ->
  {fence_values_nonempty(List.reverse(&2, Model.FenceAttachment, current)) == True{} : Bool}:
  match current:
    case Nil{}: nonempty
    case Con{+first, +rest}: fence_reverse_acc_nonempty(rest, first, Nil{})

def fence_failed_current_nonempty(+value: Model.FenceAttachment, +current: +List<Model.FenceAttachment>,
  +observed: {Model.fence_run_ordered(value, current) == False{} : Bool}) ->
  {fence_values_nonempty(current) == True{} : Bool}:
  match current:
    case Nil{}:
      Logic.impossible({False{} == True{} : Bool}, Equal.sym(Bool, True{}, False{}, observed))
    case Con{first, rest}: {==}

def fence_runs_reverse_ordered_acc(+runs: +List<+List<Model.FenceAttachment>>, +acc: +List<+List<Model.FenceAttachment>>,
  +ordered: {fence_runs_ordered(runs) == True{} : Bool},
  +acc_ordered: {fence_runs_ordered(acc) == True{} : Bool}) ->
  {fence_runs_ordered(List.reverse.go(&2, +List<Model.FenceAttachment>, runs, acc)) == True{} : Bool}:
  match runs:
    case Nil{}: acc_ordered
    case Con{+first, +rest}:
      fence_runs_reverse_ordered_acc(rest, first <> acc,
        fence_true_right(Rule.fence_values_ordered(first), fence_runs_ordered(rest), ordered),
        fence_true_and(Rule.fence_values_ordered(first), fence_runs_ordered(acc),
          fence_true_left(Rule.fence_values_ordered(first), fence_runs_ordered(rest), ordered), acc_ordered))

def fence_runs_reverse_nonempty_acc(+runs: +List<+List<Model.FenceAttachment>>, +acc: +List<+List<Model.FenceAttachment>>,
  +nonempty: {fence_runs_nonempty(runs) == True{} : Bool},
  +acc_nonempty: {fence_runs_nonempty(acc) == True{} : Bool}) ->
  {fence_runs_nonempty(List.reverse.go(&2, +List<Model.FenceAttachment>, runs, acc)) == True{} : Bool}:
  match runs:
    case Nil{}: acc_nonempty
    case Con{+first, +rest}:
      fence_runs_reverse_nonempty_acc(rest, first <> acc,
        fence_true_right(fence_values_nonempty(first), fence_runs_nonempty(rest), nonempty),
        fence_true_and(fence_values_nonempty(first), fence_runs_nonempty(acc),
          fence_true_left(fence_values_nonempty(first), fence_runs_nonempty(rest), nonempty), acc_nonempty))

def fence_natural_step_ordered(+ordered: Bool, +value: Model.FenceAttachment,
  +current: +List<Model.FenceAttachment>, +completed: +List<+List<Model.FenceAttachment>>,
  +observed: {Model.fence_run_ordered(value, current) == ordered : Bool},
  +current_ordered: {fence_current_reverse_ordered(current) == True{} : Bool},
  +completed_ordered: {fence_runs_ordered(completed) == True{} : Bool},
  +completed_nonempty: {fence_runs_nonempty(completed) == True{} : Bool}) ->
  {fence_natural_order_invariant(Model.fence_run_current(Model.fence_run_step(ordered, value, current, completed)),
    Model.fence_run_completed(Model.fence_run_step(ordered, value, current, completed))) == True{} : Bool}:
  match ordered:
    case True{}:
      fence_true_and(fence_current_reverse_ordered(value <> current),
        (fence_runs_ordered(completed) && fence_runs_nonempty(completed)),
        fence_current_push_ordered(value, current, current_ordered, observed),
        fence_true_and(fence_runs_ordered(completed), fence_runs_nonempty(completed), completed_ordered, completed_nonempty))
    case False{}:
      +closed: +List<Model.FenceAttachment> = List.reverse(&2, Model.FenceAttachment, current)
      fence_true_and(fence_current_reverse_ordered([value]),
        (fence_runs_ordered(closed <> completed) && fence_runs_nonempty(closed <> completed)), {==},
        fence_true_and(fence_runs_ordered(closed <> completed), fence_runs_nonempty(closed <> completed),
          fence_true_and(Rule.fence_values_ordered(closed), fence_runs_ordered(completed),
            fence_reversed_current_ordered(current, current_ordered), completed_ordered),
          fence_true_and(fence_values_nonempty(closed), fence_runs_nonempty(completed),
            fence_reversed_current_nonempty(current, fence_failed_current_nonempty(value, current, observed)), completed_nonempty)))

def fence_natural_step_valid(+ordered: Bool, +value: Model.FenceAttachment,
  +current: +List<Model.FenceAttachment>, +completed: +List<+List<Model.FenceAttachment>>,
  +observed: {Model.fence_run_ordered(value, current) == ordered : Bool},
  +invariant: {fence_natural_order_invariant(current, completed) == True{} : Bool}) ->
  {fence_natural_order_invariant(Model.fence_run_current(Model.fence_run_step(ordered, value, current, completed)),
    Model.fence_run_completed(Model.fence_run_step(ordered, value, current, completed))) == True{} : Bool}:
  fence_natural_step_ordered(ordered, value, current, completed, observed,
    fence_true_left(fence_current_reverse_ordered(current), (fence_runs_ordered(completed) && fence_runs_nonempty(completed)), invariant),
    fence_true_left(fence_runs_ordered(completed), fence_runs_nonempty(completed),
      fence_true_right(fence_current_reverse_ordered(current), (fence_runs_ordered(completed) && fence_runs_nonempty(completed)), invariant)),
    fence_true_right(fence_runs_ordered(completed), fence_runs_nonempty(completed),
      fence_true_right(fence_current_reverse_ordered(current), (fence_runs_ordered(completed) && fence_runs_nonempty(completed)), invariant)))

def fence_runs_complete_ordered(+current: +List<Model.FenceAttachment>, +completed: +List<+List<Model.FenceAttachment>>,
  +current_ordered: {fence_current_reverse_ordered(current) == True{} : Bool},
  +completed_ordered: {fence_runs_ordered(completed) == True{} : Bool}) ->
  {fence_runs_ordered(Model.fence_runs_complete(current, completed)) == True{} : Bool}:
  match current:
    case Nil{}: fence_runs_reverse_ordered_acc(completed, Nil{}, completed_ordered, {==})
    case Con{+top, +rest}:
      +closed: +List<Model.FenceAttachment> = List.reverse(&2, Model.FenceAttachment, top <> rest)
      fence_runs_reverse_ordered_acc(closed <> completed, Nil{},
        fence_true_and(Rule.fence_values_ordered(closed), fence_runs_ordered(completed),
          fence_reversed_current_ordered(top <> rest, current_ordered), completed_ordered), {==})

def fence_runs_complete_nonempty(+current: +List<Model.FenceAttachment>, +completed: +List<+List<Model.FenceAttachment>>,
  +completed_nonempty: {fence_runs_nonempty(completed) == True{} : Bool}) ->
  {fence_runs_nonempty(Model.fence_runs_complete(current, completed)) == True{} : Bool}:
  match current:
    case Nil{}: fence_runs_reverse_nonempty_acc(completed, Nil{}, completed_nonempty, {==})
    case Con{+first, +rest}:
      +closed: +List<Model.FenceAttachment> = List.reverse(&2, Model.FenceAttachment, first <> rest)
      fence_runs_reverse_nonempty_acc(closed <> completed, Nil{},
        fence_true_and(fence_values_nonempty(closed), fence_runs_nonempty(completed),
          fence_reverse_acc_nonempty(rest, first, Nil{}), completed_nonempty), {==})

def fence_natural_runs_valid(+values: +List<Model.FenceAttachment>, +current: +List<Model.FenceAttachment>,
  +completed: +List<+List<Model.FenceAttachment>>,
  +invariant: {fence_natural_order_invariant(current, completed) == True{} : Bool}) ->
  {(fence_runs_ordered(Model.fence_natural_runs(values, current, completed)) &&
    fence_runs_nonempty(Model.fence_natural_runs(values, current, completed))) == True{} : Bool}:
  match values:
    case Nil{}:
      fence_true_and(fence_runs_ordered(Model.fence_runs_complete(current, completed)),
        fence_runs_nonempty(Model.fence_runs_complete(current, completed)),
        fence_runs_complete_ordered(current, completed,
          fence_true_left(fence_current_reverse_ordered(current), (fence_runs_ordered(completed) && fence_runs_nonempty(completed)), invariant),
          fence_true_left(fence_runs_ordered(completed), fence_runs_nonempty(completed),
            fence_true_right(fence_current_reverse_ordered(current), (fence_runs_ordered(completed) && fence_runs_nonempty(completed)), invariant))),
        fence_runs_complete_nonempty(current, completed,
          fence_true_right(fence_runs_ordered(completed), fence_runs_nonempty(completed),
            fence_true_right(fence_current_reverse_ordered(current), (fence_runs_ordered(completed) && fence_runs_nonempty(completed)), invariant))))
    case Con{+first, +rest}:
      +ordered: Bool = Model.fence_run_ordered(first, current)
      +next: Model.FenceRunState = Model.fence_run_step(ordered, first, current, completed)
      fence_natural_runs_valid(rest, Model.fence_run_current(next), Model.fence_run_completed(next),
        fence_natural_step_valid(ordered, first, current, completed, {==}, invariant))

def fence_natural_runs_ordered_nonempty(+values: +List<Model.FenceAttachment>) ->
  {(fence_runs_ordered(Model.fence_natural_runs(values, Nil{}, Nil{})) &&
    fence_runs_nonempty(Model.fence_natural_runs(values, Nil{}, Nil{}))) == True{} : Bool}:
  fence_natural_runs_valid(values, Nil{}, Nil{}, {==})

def fence_natural_runs_ordered(+values: +List<Model.FenceAttachment>) ->
  {fence_runs_ordered(Model.fence_natural_runs(values, Nil{}, Nil{})) == True{} : Bool}:
  fence_true_left(fence_runs_ordered(Model.fence_natural_runs(values, Nil{}, Nil{})),
    fence_runs_nonempty(Model.fence_natural_runs(values, Nil{}, Nil{})), fence_natural_runs_ordered_nonempty(values))

def fence_natural_runs_nonempty(+values: +List<Model.FenceAttachment>) ->
  {fence_runs_nonempty(Model.fence_natural_runs(values, Nil{}, Nil{})) == True{} : Bool}:
  fence_true_right(fence_runs_ordered(Model.fence_natural_runs(values, Nil{}, Nil{})),
    fence_runs_nonempty(Model.fence_natural_runs(values, Nil{}, Nil{})), fence_natural_runs_ordered_nonempty(values))

def fence_weight_budget_flatten(+values: +List<Model.FenceAttachment>, +runs: +List<+List<Model.FenceAttachment>>,
  +flattened: {List.concat(&2, Model.FenceAttachment, runs) == values : +List<Model.FenceAttachment>}) ->
  {Nat.is_le(fence_run_weight(runs), List.length(&2, Model.FenceAttachment, values)) == True{} : Bool}:
  +count: Nat = List.length(&2, Model.FenceAttachment, values)
  Equal.trans(Bool, Nat.is_le(fence_run_weight(runs), count), Nat.is_le(count, count), True{},
    Equal.cong(Nat, Bool, (weight => Nat.is_le(weight, count)), fence_run_weight(runs), count,
      fence_weight_from_flatten(values, runs, flattened)), fence_count_refl(count))

# Merge accumulation only changes where the already selected prefix is stored.

def fence_merge_acc_selected(+fuel: Nat, +acc: +List<Model.FenceAttachment>,
  +x: Model.FenceAttachment, +xt: +List<Model.FenceAttachment>,
  +y: Model.FenceAttachment, +yt: +List<Model.FenceAttachment>, choice: Bool,
  +left_acc: {List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (x <> acc, xt, y <> yt)) ==
    List.reverse.go(&2, Model.FenceAttachment, x <> acc, List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (Nil{}, xt, y <> yt))) : +List<Model.FenceAttachment>},
  +left_head: {List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, ([x], xt, y <> yt)) ==
    x <> List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (Nil{}, xt, y <> yt)) : +List<Model.FenceAttachment>},
  +right_acc: {List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (y <> acc, x <> xt, yt)) ==
    List.reverse.go(&2, Model.FenceAttachment, y <> acc, List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (Nil{}, x <> xt, yt))) : +List<Model.FenceAttachment>},
  +right_head: {List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, ([y], x <> xt, yt)) ==
    y <> List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (Nil{}, x <> xt, yt)) : +List<Model.FenceAttachment>}) ->
  {List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel,
      List.merge.step(Model.FenceAttachment, acc, x, xt, y, yt, choice)) ==
    List.reverse.go(&2, Model.FenceAttachment, acc,
      List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel,
        List.merge.step(Model.FenceAttachment, Nil{}, x, xt, y, yt, choice))) : +List<Model.FenceAttachment>}:
  match choice:
    case True{}:
      Equal.trans((+List<Model.FenceAttachment>),
        List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (x <> acc, xt, y <> yt)),
        List.reverse.go(&2, Model.FenceAttachment, acc, x <> List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (Nil{}, xt, y <> yt))),
        List.reverse.go(&2, Model.FenceAttachment, acc, List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, ([x], xt, y <> yt))),
        left_acc, Equal.cong((+List<Model.FenceAttachment>), (+List<Model.FenceAttachment>),
          (tail => List.reverse.go(&2, Model.FenceAttachment, acc, tail)),
          x <> List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (Nil{}, xt, y <> yt)),
          List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, ([x], xt, y <> yt)),
          Equal.sym((+List<Model.FenceAttachment>),
            List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, ([x], xt, y <> yt)),
            x <> List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (Nil{}, xt, y <> yt)), left_head)))
    case False{}:
      Equal.trans((+List<Model.FenceAttachment>),
        List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (y <> acc, x <> xt, yt)),
        List.reverse.go(&2, Model.FenceAttachment, acc, y <> List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (Nil{}, x <> xt, yt))),
        List.reverse.go(&2, Model.FenceAttachment, acc, List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, ([y], x <> xt, yt))),
        right_acc, Equal.cong((+List<Model.FenceAttachment>), (+List<Model.FenceAttachment>),
          (tail => List.reverse.go(&2, Model.FenceAttachment, acc, tail)),
          y <> List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (Nil{}, x <> xt, yt)),
          List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, ([y], x <> xt, yt)),
          Equal.sym((+List<Model.FenceAttachment>),
            List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, ([y], x <> xt, yt)),
            y <> List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (Nil{}, x <> xt, yt)), right_head)))

# Every chosen element remains after any lower bound shared by both input runs.

def fence_merge_acc(+fuel: Nat, +acc: +List<Model.FenceAttachment>,
  +left: +List<Model.FenceAttachment>, +right: +List<Model.FenceAttachment>) ->
  {List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (acc, left, right)) ==
    List.reverse.go(&2, Model.FenceAttachment, acc,
      List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (Nil{}, left, right))) : +List<Model.FenceAttachment>}:
  match fuel:
    case 0n: {==}
    case 1n+remaining:
      match left right:
        case Nil{} Nil{}: {==}
        case Nil{} Con{first, rest}: {==}
        case Con{first, rest} Nil{}: {==}
        case Con{+x, +xt} Con{+y, +yt}:
          fence_merge_acc_selected(remaining, acc, x, xt, y, yt, Model.fence_attachment_before(x, y),
            fence_merge_acc(remaining, x <> acc, xt, y <> yt),
            fence_merge_acc(remaining, [x], xt, y <> yt),
            fence_merge_acc(remaining, y <> acc, x <> xt, yt),
            fence_merge_acc(remaining, [y], x <> xt, yt))

def fence_merge_bound_selected(+fuel: Nat, +minimum: Model.FenceAttachment,
  +x: Model.FenceAttachment, +xt: +List<Model.FenceAttachment>,
  +y: Model.FenceAttachment, +yt: +List<Model.FenceAttachment>, choice: Bool,
  +xb: {Rule.required_fence_before(minimum, x) == True{} : Bool},
  +yb: {Rule.required_fence_before(minimum, y) == True{} : Bool},
  +lb: {Rule.fence_all_after(minimum, List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (Nil{}, xt, y <> yt))) == True{} : Bool},
  +rb: {Rule.fence_all_after(minimum, List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (Nil{}, x <> xt, yt))) == True{} : Bool}) ->
  {Rule.fence_all_after(minimum, List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel,
      List.merge.step(Model.FenceAttachment, Nil{}, x, xt, y, yt, choice))) == True{} : Bool}:
  match choice:
    case True{}:
      Std.transport((+List<Model.FenceAttachment>),
        x <> List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (Nil{}, xt, y <> yt)),
        (values => {Rule.fence_all_after(minimum, values) == True{} : Bool}),
        fence_true_and(Rule.required_fence_before(minimum, x),
          Rule.fence_all_after(minimum, List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (Nil{}, xt, y <> yt))), xb, lb),
        List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, ([x], xt, y <> yt)),
        fence_merge_acc(fuel, [x], xt, y <> yt))
    case False{}:
      Std.transport((+List<Model.FenceAttachment>),
        y <> List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (Nil{}, x <> xt, yt)),
        (values => {Rule.fence_all_after(minimum, values) == True{} : Bool}),
        fence_true_and(Rule.required_fence_before(minimum, y),
          Rule.fence_all_after(minimum, List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (Nil{}, x <> xt, yt))), yb, rb),
        List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, ([y], x <> xt, yt)),
        fence_merge_acc(fuel, [y], x <> xt, yt))

# Finite fuel is sufficient because each actual merge step removes one input element.

def fence_merge_bound(+fuel: Nat, +minimum: Model.FenceAttachment,
  +left: +List<Model.FenceAttachment>, +right: +List<Model.FenceAttachment>,
  +lb: {Rule.fence_all_after(minimum, left) == True{} : Bool},
  +rb: {Rule.fence_all_after(minimum, right) == True{} : Bool}) ->
  {Rule.fence_all_after(minimum, List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (Nil{}, left, right))) == True{} : Bool}:
  match fuel:
    case 0n: fence_bound_append(minimum, left, right, lb, rb)
    case 1n+remaining:
      match left right:
        case Nil{} Nil{}: {==}
        case Nil{} Con{first, rest}: rb
        case Con{first, rest} Nil{}: lb
        case Con{+x, +xt} Con{+y, +yt}:
          fence_merge_bound_selected(remaining, minimum, x, xt, y, yt, Model.fence_attachment_before(x, y),
            fence_true_left(Rule.required_fence_before(minimum, x), Rule.fence_all_after(minimum, xt), lb),
            fence_true_left(Rule.required_fence_before(minimum, y), Rule.fence_all_after(minimum, yt), rb),
            fence_merge_bound(remaining, minimum, xt, y <> yt,
              fence_true_right(Rule.required_fence_before(minimum, x), Rule.fence_all_after(minimum, xt), lb), rb),
            fence_merge_bound(remaining, minimum, x <> xt, yt, lb,
              fence_true_right(Rule.required_fence_before(minimum, y), Rule.fence_all_after(minimum, yt), rb)))

def fence_merge_ordered_selected(+fuel: Nat, +x: Model.FenceAttachment, +xt: +List<Model.FenceAttachment>,
  +y: Model.FenceAttachment, +yt: +List<Model.FenceAttachment>, choice: Bool,
  +seen: {Rule.required_fence_before(x, y) == choice : Bool},
  +lo: {Rule.fence_values_ordered(x <> xt) == True{} : Bool}, +ro: {Rule.fence_values_ordered(y <> yt) == True{} : Bool},
  +left_sorted: {Rule.fence_values_ordered(List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (Nil{}, xt, y <> yt))) == True{} : Bool},
  +right_sorted: {Rule.fence_values_ordered(List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (Nil{}, x <> xt, yt))) == True{} : Bool}) ->
  {Rule.fence_values_ordered(List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel,
      List.merge.step(Model.FenceAttachment, Nil{}, x, xt, y, yt, choice))) == True{} : Bool}:
  match choice:
    case True{}:
      +tail = List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (Nil{}, xt, y <> yt))
      +xt_bound = fence_true_left(Rule.fence_all_after(x, xt), Rule.fence_values_ordered(xt), lo)
      +yt_bound = fence_bound_trans(x, y, yt, seen, fence_true_left(Rule.fence_all_after(y, yt), Rule.fence_values_ordered(yt), ro))
      Std.transport((+List<Model.FenceAttachment>), x <> tail,
        (values => {Rule.fence_values_ordered(values) == True{} : Bool}),
        fence_true_and(Rule.fence_all_after(x, tail), Rule.fence_values_ordered(tail),
          fence_merge_bound(fuel, x, xt, y <> yt, xt_bound,
            fence_true_and(Rule.required_fence_before(x, y), Rule.fence_all_after(x, yt), seen, yt_bound)), left_sorted),
        List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, ([x], xt, y <> yt)),
        fence_merge_acc(fuel, [x], xt, y <> yt))
    case False{}:
      +tail = List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (Nil{}, x <> xt, yt))
      +yx = fence_before_reverse_false(x, y, seen)
      +xt_bound = fence_bound_trans(y, x, xt, yx, fence_true_left(Rule.fence_all_after(x, xt), Rule.fence_values_ordered(xt), lo))
      +yt_bound = fence_true_left(Rule.fence_all_after(y, yt), Rule.fence_values_ordered(yt), ro)
      Std.transport((+List<Model.FenceAttachment>), y <> tail,
        (values => {Rule.fence_values_ordered(values) == True{} : Bool}),
        fence_true_and(Rule.fence_all_after(y, tail), Rule.fence_values_ordered(tail),
          fence_merge_bound(fuel, y, x <> xt, yt,
            fence_true_and(Rule.required_fence_before(y, x), Rule.fence_all_after(y, xt), yx, xt_bound), yt_bound), right_sorted),
        List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, ([y], x <> xt, yt)),
        fence_merge_acc(fuel, [y], x <> xt, yt))

def fence_merge_ordered(+fuel: Nat, +left: +List<Model.FenceAttachment>, +right: +List<Model.FenceAttachment>,
  +lo: {Rule.fence_values_ordered(left) == True{} : Bool}, +ro: {Rule.fence_values_ordered(right) == True{} : Bool},
  +fits: {Nat.is_le(Nat.add(List.length(&2, Model.FenceAttachment, left), List.length(&2, Model.FenceAttachment, right)), fuel) == True{} : Bool}) ->
  {Rule.fence_values_ordered(List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (Nil{}, left, right))) == True{} : Bool}:
  match fuel:
    case 0n:
      match left right:
        case Nil{} Nil{}: {==}
        case Nil{} Con{first, rest}:
          Logic.impossible({Rule.fence_values_ordered(first <> rest) == True{} : Bool}, fits)
        case Con{first, rest} _:
          Logic.impossible({Rule.fence_values_ordered(List.append(&2, Model.FenceAttachment, first <> rest, right)) == True{} : Bool}, fits)
    case 1n+remaining:
      match left right:
        case Nil{} Nil{}: {==}
        case Nil{} Con{first, rest}: ro
        case Con{first, rest} Nil{}: lo
        case Con{+x, +xt} Con{+y, +yt}:
          fence_merge_ordered_selected(remaining, x, xt, y, yt, Model.fence_attachment_before(x, y),
            Equal.sym(Bool, Model.fence_attachment_before(x, y), Rule.required_fence_before(x, y), fence_before_complete(x, y)), lo, ro,
            fence_merge_ordered(remaining, xt, y <> yt,
              fence_true_right(Rule.fence_all_after(x, xt), Rule.fence_values_ordered(xt), lo), ro,
              fence_merge_left_budget(xt, y <> yt, remaining, fits)),
            fence_merge_ordered(remaining, x <> xt, yt, lo,
              fence_true_right(Rule.fence_all_after(y, yt), Rule.fence_values_ordered(yt), ro),
              fence_merge_right_budget(x <> xt, yt, remaining, fits)))

def fence_category_reflect(+left: Bool, +right: Bool,
  +same: {Rule.same_fence_category(left, right) == True{} : Bool}) -> {left == right : Bool}:
  match left right:
    case False{} False{}: {==}
    case False{} True{}: Logic.impossible({False{} == True{} : Bool}, same)
    case True{} False{}: Logic.impossible({True{} == False{} : Bool}, same)
    case True{} True{}: {==}

def fence_group_member_key(+value: Model.FenceAttachment, +ordinal: Nat, +interactive: Bool,
  +member: {Rule.fence_in_group(value, ordinal, interactive) == True{} : Bool}) ->
  {value == Model.FenceAttachment{ordinal, interactive,
    Rule.fence_attachment_node(value)} : Model.FenceAttachment}:
  Model.FenceAttachment{+vo, +vi, +node} = value
  +ord = fence_nat_equal_reflect(vo, ordinal,
    fence_true_left(Nat.is_eq(vo, ordinal), Rule.same_fence_category(vi, interactive), member))
  +cat = fence_category_reflect(vi, interactive,
    fence_true_right(Nat.is_eq(vo, ordinal), Rule.same_fence_category(vi, interactive), member))
  Equal.trans(Model.FenceAttachment, Model.FenceAttachment{vo, vi, node},
    Model.FenceAttachment{ordinal, vi, node}, Model.FenceAttachment{ordinal, interactive, node},
    Equal.cong(Nat, Model.FenceAttachment, (n => Model.FenceAttachment{n, vi, node}), vo, ordinal, ord),
    Equal.cong(Bool, Model.FenceAttachment, (c => Model.FenceAttachment{ordinal, c, node}), vi, interactive, cat))

def fence_equal_key_before(+ordinal: Nat, +interactive: Bool, +x: SurfaceTypes.Node, +y: SurfaceTypes.Node) ->
  {Rule.required_fence_before(Model.FenceAttachment{ordinal, interactive, x}, Model.FenceAttachment{ordinal, interactive, y}) == True{} : Bool}:
  match ordinal interactive:
    case 0n False{}: {==}
    case 0n True{}: {==}
    case 1n+rest value: fence_equal_key_before(rest, value, x, y)

def fence_group_same_before(+x: Model.FenceAttachment, +y: Model.FenceAttachment, +ordinal: Nat, +interactive: Bool,
  +xm: {Rule.fence_in_group(x, ordinal, interactive) == True{} : Bool},
  +ym: {Rule.fence_in_group(y, ordinal, interactive) == True{} : Bool}) ->
  {Rule.required_fence_before(x, y) == True{} : Bool}:
  Model.FenceAttachment{xo, xi, +xn} = x
  Model.FenceAttachment{yo, yi, +yn} = y
  +xkey: Model.FenceAttachment = Model.FenceAttachment{ordinal, interactive, xn}
  +ykey: Model.FenceAttachment = Model.FenceAttachment{ordinal, interactive, yn}
  Equal.trans(Bool, Rule.required_fence_before(x, y), Rule.required_fence_before(xkey, y), True{},
    Equal.cong(Model.FenceAttachment, Bool, (left => Rule.required_fence_before(left, y)), x, xkey,
      fence_group_member_key(x, ordinal, interactive, xm)),
    Equal.trans(Bool, Rule.required_fence_before(xkey, y), Rule.required_fence_before(xkey, ykey), True{},
      Equal.cong(Model.FenceAttachment, Bool, (right => Rule.required_fence_before(xkey, right)), y, ykey,
        fence_group_member_key(y, ordinal, interactive, ym)),
      fence_equal_key_before(ordinal, interactive, xn, yn)))

def fence_group_append_step(included: Bool, +node: SurfaceTypes.Node,
  +left: +List<SurfaceTypes.Node>, +right: +List<SurfaceTypes.Node>) ->
  {Rule.fence_group_step(included, node, List.append(&2, SurfaceTypes.Node, left, right)) ==
    List.append(&2, SurfaceTypes.Node, Rule.fence_group_step(included, node, left), right) : +List<SurfaceTypes.Node>}:
  match included:
    case False{}: {==}
    case True{}: {==}

def fence_group_append(+left: +List<Model.FenceAttachment>, +right: +List<Model.FenceAttachment>, +ordinal: Nat, +interactive: Bool) ->
  {Rule.fence_group(List.append(&2, Model.FenceAttachment, left, right), ordinal, interactive) ==
    List.append(&2, SurfaceTypes.Node, Rule.fence_group(left, ordinal, interactive), Rule.fence_group(right, ordinal, interactive)) : +List<SurfaceTypes.Node>}:
  match left:
    case Nil{}: {==}
    case Con{Model.FenceAttachment{+vo, +vi, +node}, +rest}:
      +included = Nat.is_eq(vo, ordinal) && Rule.same_fence_category(vi, interactive)
      Equal.trans((+List<SurfaceTypes.Node>),
        Rule.fence_group_step(included, node, Rule.fence_group(List.append(&2, Model.FenceAttachment, rest, right), ordinal, interactive)),
        Rule.fence_group_step(included, node, List.append(&2, SurfaceTypes.Node, Rule.fence_group(rest, ordinal, interactive), Rule.fence_group(right, ordinal, interactive))),
        List.append(&2, SurfaceTypes.Node, Rule.fence_group_step(included, node, Rule.fence_group(rest, ordinal, interactive)), Rule.fence_group(right, ordinal, interactive)),
        Equal.cong((+List<SurfaceTypes.Node>), (+List<SurfaceTypes.Node>), (tail => Rule.fence_group_step(included, node, tail)),
          Rule.fence_group(List.append(&2, Model.FenceAttachment, rest, right), ordinal, interactive),
          List.append(&2, SurfaceTypes.Node, Rule.fence_group(rest, ordinal, interactive), Rule.fence_group(right, ordinal, interactive)),
          fence_group_append(rest, right, ordinal, interactive)),
        fence_group_append_step(included, node, Rule.fence_group(rest, ordinal, interactive), Rule.fence_group(right, ordinal, interactive)))

# A right-hand element can pass a left run only when that run has no equal group.

def fence_strict_group_step(included: Bool, +minimum: Model.FenceAttachment, +value: Model.FenceAttachment,
  +rest: +List<Model.FenceAttachment>, +ordinal: Nat, +interactive: Bool,
  +seen: {Rule.fence_in_group(value, ordinal, interactive) == included : Bool},
  +member: {Rule.fence_in_group(minimum, ordinal, interactive) == True{} : Bool},
  +strict: {Rule.required_fence_before(value, minimum) == False{} : Bool},
  +tail: {Rule.fence_group(rest, ordinal, interactive) == Nil{} : +List<SurfaceTypes.Node>}) ->
  {Rule.fence_group(value <> rest, ordinal, interactive) == Nil{} : +List<SurfaceTypes.Node>}:
  match included:
    case True{}:
      Logic.impossible({Rule.fence_group(value <> rest, ordinal, interactive) == Nil{} : +List<SurfaceTypes.Node>},
        Equal.trans(Bool, False{}, Rule.required_fence_before(value, minimum), True{},
          Equal.sym(Bool, Rule.required_fence_before(value, minimum), False{}, strict),
          fence_group_same_before(value, minimum, ordinal, interactive, seen, member)))
    case False{}:
      Model.FenceAttachment{vo, vi, +node} = value
      Equal.trans((+List<SurfaceTypes.Node>), Rule.fence_group(value <> rest, ordinal, interactive),
        Rule.fence_group(rest, ordinal, interactive), Nil{},
        Equal.cong(Bool, (+List<SurfaceTypes.Node>),
          (keep => Rule.fence_group_step(keep, node, Rule.fence_group(rest, ordinal, interactive))),
          Rule.fence_in_group(value, ordinal, interactive), False{}, seen), tail)

def fence_strict_group_empty(+minimum: Model.FenceAttachment, +values: +List<Model.FenceAttachment>, +ordinal: Nat, +interactive: Bool,
  +member: {Rule.fence_in_group(minimum, ordinal, interactive) == True{} : Bool},
  +strict: {fence_all_strict_after(minimum, values) == True{} : Bool}) ->
  {Rule.fence_group(values, ordinal, interactive) == Nil{} : +List<SurfaceTypes.Node>}:
  match values:
    case Nil{}: {==}
    case Con{Model.FenceAttachment{+vo, +vi, +node}, +rest}:
      +value: Model.FenceAttachment = Model.FenceAttachment{vo, vi, node}
      fence_strict_group_step(Rule.fence_in_group(value, ordinal, interactive), minimum, value, rest, ordinal, interactive,
        {==}, member,
        fence_not_true(Rule.required_fence_before(value, minimum),
          fence_true_left(Bool.not(Rule.required_fence_before(value, minimum)), fence_all_strict_after(minimum, rest), strict)),
        fence_strict_group_empty(minimum, rest, ordinal, interactive, member,
          fence_true_right(Bool.not(Rule.required_fence_before(value, minimum)), fence_all_strict_after(minimum, rest), strict)))

def fence_group_right_prefix(+value: Model.FenceAttachment, +left: +List<Model.FenceAttachment>, +tail: +List<Model.FenceAttachment>,
  +ordinal: Nat, +interactive: Bool, included: Bool,
  +seen: {Rule.fence_in_group(value, ordinal, interactive) == included : Bool},
  +strict: {fence_all_strict_after(value, left) == True{} : Bool}) ->
  {Rule.fence_group_step(included,
      Rule.fence_attachment_node(value),
      List.append(&2, SurfaceTypes.Node, Rule.fence_group(left, ordinal, interactive), Rule.fence_group(tail, ordinal, interactive))) ==
    List.append(&2, SurfaceTypes.Node, Rule.fence_group(left, ordinal, interactive), Rule.fence_group(value <> tail, ordinal, interactive)) : +List<SurfaceTypes.Node>}:
  Model.FenceAttachment{vo, vi, +node} = value
  match included:
    case False{}:
      Equal.cong((+List<SurfaceTypes.Node>), (+List<SurfaceTypes.Node>),
        (suffix => List.append(&2, SurfaceTypes.Node, Rule.fence_group(left, ordinal, interactive), suffix)),
        Rule.fence_group(tail, ordinal, interactive), Rule.fence_group(value <> tail, ordinal, interactive),
        Equal.sym((+List<SurfaceTypes.Node>), Rule.fence_group(value <> tail, ordinal, interactive), Rule.fence_group(tail, ordinal, interactive),
          Equal.cong(Bool, (+List<SurfaceTypes.Node>), (keep => Rule.fence_group_step(keep, node, Rule.fence_group(tail, ordinal, interactive))),
            Rule.fence_in_group(value, ordinal, interactive), False{}, seen)))
    case True{}:
      +empty = fence_strict_group_empty(value, left, ordinal, interactive, seen, strict)
      Std.transport((+List<SurfaceTypes.Node>), Nil{},
        (prefix => {node <> List.append(&2, SurfaceTypes.Node, prefix, Rule.fence_group(tail, ordinal, interactive)) ==
          List.append(&2, SurfaceTypes.Node, prefix, Rule.fence_group(value <> tail, ordinal, interactive)) : +List<SurfaceTypes.Node>}),
        Equal.cong(Bool, (+List<SurfaceTypes.Node>), (keep => Rule.fence_group_step(keep, node, Rule.fence_group(tail, ordinal, interactive))),
          True{}, Rule.fence_in_group(value, ordinal, interactive), Equal.sym(Bool, Rule.fence_in_group(value, ordinal, interactive), True{}, seen)),
        Rule.fence_group(left, ordinal, interactive), empty)

# Only equal ordinal/category entries share a group; left priority retains their order.

def fence_merge_groups_selected(choice: Bool, +fuel: Nat, +x: Model.FenceAttachment, +xt: +List<Model.FenceAttachment>,
  +y: Model.FenceAttachment, +yt: +List<Model.FenceAttachment>, +ordinal: Nat, +interactive: Bool,
  +seen: {Rule.required_fence_before(x, y) == choice : Bool},
  +lo: {Rule.fence_values_ordered(x <> xt) == True{} : Bool},
  +left_result: {Rule.fence_group(List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (Nil{}, xt, y <> yt)), ordinal, interactive) ==
    List.append(&2, SurfaceTypes.Node, Rule.fence_group(xt, ordinal, interactive), Rule.fence_group(y <> yt, ordinal, interactive)) : +List<SurfaceTypes.Node>},
  +right_result: {Rule.fence_group(List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (Nil{}, x <> xt, yt)), ordinal, interactive) ==
    List.append(&2, SurfaceTypes.Node, Rule.fence_group(x <> xt, ordinal, interactive), Rule.fence_group(yt, ordinal, interactive)) : +List<SurfaceTypes.Node>}) ->
  {Rule.fence_group(List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel,
      List.merge.step(Model.FenceAttachment, Nil{}, x, xt, y, yt, choice)), ordinal, interactive) ==
    List.append(&2, SurfaceTypes.Node, Rule.fence_group(x <> xt, ordinal, interactive), Rule.fence_group(y <> yt, ordinal, interactive)) : +List<SurfaceTypes.Node>}:
  match choice:
    case True{}:
      Model.FenceAttachment{xo, xi, +node} = x
      +tail = List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (Nil{}, xt, y <> yt))
      +keep = Rule.fence_in_group(x, ordinal, interactive)
      +expected = List.append(&2, SurfaceTypes.Node, Rule.fence_group(x <> xt, ordinal, interactive), Rule.fence_group(y <> yt, ordinal, interactive))
      Equal.trans((+List<SurfaceTypes.Node>),
        Rule.fence_group(List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, ([x], xt, y <> yt)), ordinal, interactive),
        Rule.fence_group(x <> tail, ordinal, interactive), expected,
        Equal.cong((+List<Model.FenceAttachment>), (+List<SurfaceTypes.Node>), (values => Rule.fence_group(values, ordinal, interactive)),
          List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, ([x], xt, y <> yt)), x <> tail,
          fence_merge_acc(fuel, [x], xt, y <> yt)),
        Equal.trans((+List<SurfaceTypes.Node>), Rule.fence_group(x <> tail, ordinal, interactive),
          Rule.fence_group_step(keep, node, List.append(&2, SurfaceTypes.Node, Rule.fence_group(xt, ordinal, interactive), Rule.fence_group(y <> yt, ordinal, interactive))), expected,
          Equal.cong((+List<SurfaceTypes.Node>), (+List<SurfaceTypes.Node>), (suffix => Rule.fence_group_step(keep, node, suffix)),
            Rule.fence_group(tail, ordinal, interactive),
            List.append(&2, SurfaceTypes.Node, Rule.fence_group(xt, ordinal, interactive), Rule.fence_group(y <> yt, ordinal, interactive)), left_result),
          fence_group_append_step(keep, node, Rule.fence_group(xt, ordinal, interactive), Rule.fence_group(y <> yt, ordinal, interactive))))
    case False{}:
      Model.FenceAttachment{yo, yi, +node} = y
      +tail = List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (Nil{}, x <> xt, yt))
      +keep = Rule.fence_in_group(y, ordinal, interactive)
      +expected = List.append(&2, SurfaceTypes.Node, Rule.fence_group(x <> xt, ordinal, interactive), Rule.fence_group(y <> yt, ordinal, interactive))
      +strict = fence_true_and(Bool.not(Rule.required_fence_before(x, y)), fence_all_strict_after(y, xt),
        Equal.cong(Bool, Bool, Bool.not, Rule.required_fence_before(x, y), False{}, seen),
        fence_strict_bound(x, y, xt, seen, fence_true_left(Rule.fence_all_after(x, xt), Rule.fence_values_ordered(xt), lo)))
      Equal.trans((+List<SurfaceTypes.Node>),
        Rule.fence_group(List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, ([y], x <> xt, yt)), ordinal, interactive),
        Rule.fence_group(y <> tail, ordinal, interactive), expected,
        Equal.cong((+List<Model.FenceAttachment>), (+List<SurfaceTypes.Node>), (values => Rule.fence_group(values, ordinal, interactive)),
          List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, ([y], x <> xt, yt)), y <> tail,
          fence_merge_acc(fuel, [y], x <> xt, yt)),
        Equal.trans((+List<SurfaceTypes.Node>), Rule.fence_group(y <> tail, ordinal, interactive),
          Rule.fence_group_step(keep, node, List.append(&2, SurfaceTypes.Node, Rule.fence_group(x <> xt, ordinal, interactive), Rule.fence_group(yt, ordinal, interactive))), expected,
          Equal.cong((+List<SurfaceTypes.Node>), (+List<SurfaceTypes.Node>), (suffix => Rule.fence_group_step(keep, node, suffix)),
            Rule.fence_group(tail, ordinal, interactive),
            List.append(&2, SurfaceTypes.Node, Rule.fence_group(x <> xt, ordinal, interactive), Rule.fence_group(yt, ordinal, interactive)), right_result),
          fence_group_right_prefix(y, x <> xt, yt, ordinal, interactive, keep, {==}, strict)))

def fence_merge_groups(+fuel: Nat, +left: +List<Model.FenceAttachment>, +right: +List<Model.FenceAttachment>,
  +ordinal: Nat, +interactive: Bool,
  +lo: {Rule.fence_values_ordered(left) == True{} : Bool}, +ro: {Rule.fence_values_ordered(right) == True{} : Bool}) ->
  {Rule.fence_group(List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, (Nil{}, left, right)), ordinal, interactive) ==
    List.append(&2, SurfaceTypes.Node, Rule.fence_group(left, ordinal, interactive), Rule.fence_group(right, ordinal, interactive)) : +List<SurfaceTypes.Node>}:
  match fuel:
    case 0n: fence_group_append(left, right, ordinal, interactive)
    case 1n+remaining:
      match left right:
        case Nil{} Nil{}: {==}
        case Nil{} Con{first, rest}: {==}
        case Con{first, rest} Nil{}:
          Equal.sym((+List<SurfaceTypes.Node>),
            List.append(&2, SurfaceTypes.Node, Rule.fence_group(first <> rest, ordinal, interactive), Nil{}),
            Rule.fence_group(first <> rest, ordinal, interactive),
            Std.app_nil_r(SurfaceTypes.Node, Rule.fence_group(first <> rest, ordinal, interactive)))
        case Con{+x, +xt} Con{+y, +yt}:
          fence_merge_groups_selected(Model.fence_attachment_before(x, y), remaining, x, xt, y, yt, ordinal, interactive,
            Equal.sym(Bool, Model.fence_attachment_before(x, y), Rule.required_fence_before(x, y), fence_before_complete(x, y)), lo,
            fence_merge_groups(remaining, xt, y <> yt, ordinal, interactive,
              fence_true_right(Rule.fence_all_after(x, xt), Rule.fence_values_ordered(xt), lo), ro),
            fence_merge_groups(remaining, x <> xt, yt, ordinal, interactive, lo,
              fence_true_right(Rule.fence_all_after(y, yt), Rule.fence_values_ordered(yt), ro)))

def fence_pass_ordered(+n: Nat, +runs: +List<+List<Model.FenceAttachment>>,
  +ordered: {fence_runs_ordered(runs) == True{} : Bool},
  +fits: {Nat.is_le(fence_run_weight(runs), n) == True{} : Bool}) ->
  {fence_runs_ordered(List.sort.pass(~Model.FenceAttachment, ~Model.fence_attachment_before, n, runs)) == True{} : Bool}:
  match runs:
    case Nil{}: {==}
    case Con{run, Nil{}}: ordered
    case Con{+first, Con{+second, +rest}}:
      +merged: +List<Model.FenceAttachment> = List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, n, (Nil{}, first, second))
      +tail: +List<+List<Model.FenceAttachment>> = List.sort.pass(~Model.FenceAttachment, ~Model.fence_attachment_before, n, rest)
      fence_true_and(Rule.fence_values_ordered(merged), fence_runs_ordered(tail),
        fence_merge_ordered(n, first, second,
          fence_true_left(Rule.fence_values_ordered(first), fence_runs_ordered(second <> rest), ordered),
          fence_true_left(Rule.fence_values_ordered(second), fence_runs_ordered(rest),
            fence_true_right(Rule.fence_values_ordered(first), fence_runs_ordered(second <> rest), ordered)),
          fence_first_pair_budget(first, second, rest, n, fits)),
        fence_pass_ordered(n, rest,
          fence_true_right(Rule.fence_values_ordered(second), fence_runs_ordered(rest),
            fence_true_right(Rule.fence_values_ordered(first), fence_runs_ordered(second <> rest), ordered)),
          fence_remaining_weight_budget(first, second, rest, n, fits)))

def fence_group_join(+left: +List<Model.FenceAttachment>, +right: +List<Model.FenceAttachment>,
  +out_left: +List<Model.FenceAttachment>, +out_right: +List<Model.FenceAttachment>, +ordinal: Nat, +interactive: Bool,
  +lp: {Rule.fence_group(out_left, ordinal, interactive) == Rule.fence_group(left, ordinal, interactive) : +List<SurfaceTypes.Node>},
  +rp: {Rule.fence_group(out_right, ordinal, interactive) == Rule.fence_group(right, ordinal, interactive) : +List<SurfaceTypes.Node>}) ->
  {Rule.fence_group(List.append(&2, Model.FenceAttachment, out_left, out_right), ordinal, interactive) ==
    Rule.fence_group(List.append(&2, Model.FenceAttachment, left, right), ordinal, interactive) : +List<SurfaceTypes.Node>}:
  Equal.trans((+List<SurfaceTypes.Node>),
    Rule.fence_group(List.append(&2, Model.FenceAttachment, out_left, out_right), ordinal, interactive),
    List.append(&2, SurfaceTypes.Node, Rule.fence_group(out_left, ordinal, interactive), Rule.fence_group(out_right, ordinal, interactive)),
    Rule.fence_group(List.append(&2, Model.FenceAttachment, left, right), ordinal, interactive),
    fence_group_append(out_left, out_right, ordinal, interactive),
    Equal.trans((+List<SurfaceTypes.Node>),
      List.append(&2, SurfaceTypes.Node, Rule.fence_group(out_left, ordinal, interactive), Rule.fence_group(out_right, ordinal, interactive)),
      List.append(&2, SurfaceTypes.Node, Rule.fence_group(left, ordinal, interactive), Rule.fence_group(out_right, ordinal, interactive)),
      Rule.fence_group(List.append(&2, Model.FenceAttachment, left, right), ordinal, interactive),
      Equal.cong((+List<SurfaceTypes.Node>), (+List<SurfaceTypes.Node>),
        (prefix => List.append(&2, SurfaceTypes.Node, prefix, Rule.fence_group(out_right, ordinal, interactive))),
        Rule.fence_group(out_left, ordinal, interactive), Rule.fence_group(left, ordinal, interactive), lp),
      Equal.trans((+List<SurfaceTypes.Node>),
        List.append(&2, SurfaceTypes.Node, Rule.fence_group(left, ordinal, interactive), Rule.fence_group(out_right, ordinal, interactive)),
        List.append(&2, SurfaceTypes.Node, Rule.fence_group(left, ordinal, interactive), Rule.fence_group(right, ordinal, interactive)),
        Rule.fence_group(List.append(&2, Model.FenceAttachment, left, right), ordinal, interactive),
        Equal.cong((+List<SurfaceTypes.Node>), (+List<SurfaceTypes.Node>),
          (suffix => List.append(&2, SurfaceTypes.Node, Rule.fence_group(left, ordinal, interactive), suffix)),
          Rule.fence_group(out_right, ordinal, interactive), Rule.fence_group(right, ordinal, interactive), rp),
        Equal.sym((+List<SurfaceTypes.Node>),
          Rule.fence_group(List.append(&2, Model.FenceAttachment, left, right), ordinal, interactive),
          List.append(&2, SurfaceTypes.Node, Rule.fence_group(left, ordinal, interactive), Rule.fence_group(right, ordinal, interactive)),
          fence_group_append(left, right, ordinal, interactive)))))

def fence_pass_groups(+n: Nat, +runs: +List<+List<Model.FenceAttachment>>, +ordinal: Nat, +interactive: Bool,
  +ordered: {fence_runs_ordered(runs) == True{} : Bool}) ->
  {Rule.fence_group(List.concat(&2, Model.FenceAttachment, List.sort.pass(~Model.FenceAttachment, ~Model.fence_attachment_before, n, runs)), ordinal, interactive) ==
    Rule.fence_group(List.concat(&2, Model.FenceAttachment, runs), ordinal, interactive) : +List<SurfaceTypes.Node>}:
  match runs:
    case Nil{}: {==}
    case Con{run, Nil{}}: {==}
    case Con{+first, Con{+second, +rest}}:
      +merged = List.merge.go(~Model.FenceAttachment, ~Model.fence_attachment_before, n, (Nil{}, first, second))
      +prefix = List.append(&2, Model.FenceAttachment, first, second)
      +actual_tail = List.concat(&2, Model.FenceAttachment, List.sort.pass(~Model.FenceAttachment, ~Model.fence_attachment_before, n, rest))
      +original_tail = List.concat(&2, Model.FenceAttachment, rest)
      +first_ordered = fence_true_left(Rule.fence_values_ordered(first), fence_runs_ordered(second <> rest), ordered)
      +tail_ordered = fence_true_right(Rule.fence_values_ordered(first), fence_runs_ordered(second <> rest), ordered)
      +second_ordered = fence_true_left(Rule.fence_values_ordered(second), fence_runs_ordered(rest), tail_ordered)
      +rest_ordered = fence_true_right(Rule.fence_values_ordered(second), fence_runs_ordered(rest), tail_ordered)
      +merged_group = Equal.trans((+List<SurfaceTypes.Node>), Rule.fence_group(merged, ordinal, interactive),
        List.append(&2, SurfaceTypes.Node, Rule.fence_group(first, ordinal, interactive), Rule.fence_group(second, ordinal, interactive)),
        Rule.fence_group(prefix, ordinal, interactive),
        fence_merge_groups(n, first, second, ordinal, interactive, first_ordered, second_ordered),
        Equal.sym((+List<SurfaceTypes.Node>), Rule.fence_group(prefix, ordinal, interactive),
          List.append(&2, SurfaceTypes.Node, Rule.fence_group(first, ordinal, interactive), Rule.fence_group(second, ordinal, interactive)),
          fence_group_append(first, second, ordinal, interactive)))
      Equal.trans((+List<SurfaceTypes.Node>),
        Rule.fence_group(List.append(&2, Model.FenceAttachment, merged, actual_tail), ordinal, interactive),
        Rule.fence_group(List.append(&2, Model.FenceAttachment, prefix, original_tail), ordinal, interactive),
        Rule.fence_group(List.concat(&2, Model.FenceAttachment, first <> second <> rest), ordinal, interactive),
        fence_group_join(prefix, original_tail, merged, actual_tail, ordinal, interactive, merged_group,
          fence_pass_groups(n, rest, ordinal, interactive, rest_ordered)),
        Equal.cong((+List<Model.FenceAttachment>), (+List<SurfaceTypes.Node>), (values => Rule.fence_group(values, ordinal, interactive)),
          List.append(&2, Model.FenceAttachment, prefix, original_tail),
          List.append(&2, Model.FenceAttachment, first, List.append(&2, Model.FenceAttachment, second, original_tail)),
          Equal.sym((+List<Model.FenceAttachment>),
            List.append(&2, Model.FenceAttachment, first, List.append(&2, Model.FenceAttachment, second, original_tail)),
            List.append(&2, Model.FenceAttachment, prefix, original_tail),
            Std.app_assoc(Model.FenceAttachment, first, second, original_tail))))

def fence_pass_order_result(+n: Nat, +runs: +List<+List<Model.FenceAttachment>>,
  +output: +List<Model.FenceAttachment>, +ordered: {fence_runs_ordered(runs) == True{} : Bool},
  result: Rule.FenceOrder<List.concat(&2, Model.FenceAttachment,
    List.sort.pass(~Model.FenceAttachment, ~Model.fence_attachment_before, n, runs)), output>) ->
  Rule.FenceOrder<List.concat(&2, Model.FenceAttachment, runs), output>:
  match result:
    case Rule.FenceOrder{sorted, groups}:
      Rule.FenceOrder{sorted, (+ordinal => +interactive =>
        Equal.trans((+List<SurfaceTypes.Node>), Rule.fence_group(output, ordinal, interactive),
          Rule.fence_group(List.concat(&2, Model.FenceAttachment,
            List.sort.pass(~Model.FenceAttachment, ~Model.fence_attachment_before, n, runs)), ordinal, interactive),
          Rule.fence_group(List.concat(&2, Model.FenceAttachment, runs), ordinal, interactive),
          groups(ordinal, interactive), fence_pass_groups(n, runs, ordinal, interactive, ordered)))}

def fence_sort_requirements(+fuel: Nat, +n: Nat, +runs: +List<+List<Model.FenceAttachment>>,
  +ordered: {fence_runs_ordered(runs) == True{} : Bool},
  +weight_fits: {Nat.is_le(fence_run_weight(runs), n) == True{} : Bool},
  +count_fits: {Nat.is_le(fence_run_count(runs), fuel) == True{} : Bool}) ->
  Rule.FenceOrder<List.concat(&2, Model.FenceAttachment, runs), List.sort.go(~Model.FenceAttachment, ~Model.fence_attachment_before, fuel, n, runs)>:
  match fuel:
    case 0n:
      match runs:
        case Nil{}: Rule.FenceOrder{{==}, (ordinal => interactive => {==})}
        case Con{first, rest}:
          Logic.impossible(Rule.FenceOrder<List.concat(&2, Model.FenceAttachment, first <> rest),
            List.sort.go(~Model.FenceAttachment, ~Model.fence_attachment_before, 0n, n, first <> rest)>, count_fits)
    case 1n+remaining:
      match runs:
        case Nil{}: Rule.FenceOrder{{==}, (ordinal => interactive => {==})}
        case Con{+first, Nil{}}:
          Rule.FenceOrder{
            fence_true_left(Rule.fence_values_ordered(first), True{}, ordered),
            (+ordinal => +interactive =>
              Equal.cong((+List<Model.FenceAttachment>), (+List<SurfaceTypes.Node>), (values => Rule.fence_group(values, ordinal, interactive)),
                first, List.append(&2, Model.FenceAttachment, first, Nil{}),
                Equal.sym((+List<Model.FenceAttachment>), List.append(&2, Model.FenceAttachment, first, Nil{}), first,
                  Std.app_nil_r(Model.FenceAttachment, first))))}
        case Con{+first, Con{+second, +rest}}:
          +next = List.sort.pass(~Model.FenceAttachment, ~Model.fence_attachment_before, n, first <> second <> rest)
          +output = List.sort.go(~Model.FenceAttachment, ~Model.fence_attachment_before, remaining, n, next)
          fence_pass_order_result(n, first <> second <> rest, output, ordered,
            fence_sort_requirements(remaining, n, next,
              fence_pass_ordered(n, first <> second <> rest, ordered, weight_fits),
              fence_pass_weight_budget(n, first <> second <> rest, weight_fits),
              fence_pass_budget(n, first, second, rest, remaining, count_fits)))

def complete_fence_order(+values: +List<Model.FenceAttachment>) ->
  Rule.FenceOrder<values, Model.ordered_fence_attachments(values)>:
  +count = List.length(&2, Model.FenceAttachment, values)
  +runs = Model.fence_natural_runs(values, Nil{}, Nil{})
  Std.transport((+List<Model.FenceAttachment>), List.concat(&2, Model.FenceAttachment, runs),
    (input => Rule.FenceOrder<input, Model.ordered_fence_attachments(values)>),
    fence_sort_requirements(count, count, runs, fence_natural_runs_ordered(values),
      fence_weight_budget_flatten(values, runs, fence_natural_runs_preserve_all(values)),
      fence_count_budget_chain(fence_run_count(runs), fence_run_weight(runs), count,
        fence_nonempty_count_weight(runs, fence_natural_runs_nonempty(values)),
        fence_weight_budget_flatten(values, runs, fence_natural_runs_preserve_all(values)))),
    values, Equal.sym((+List<Model.FenceAttachment>),
      List.concat(&2, Model.FenceAttachment, runs), values, fence_natural_runs_preserve_all(values)))

def Rule.fence_order_complete(values):
  complete_fence_order(values)

def complete_fence_attachments(+source: Code.Source, +parent: Identity.Key, +codes: +List<Code.Scene>,
  +scenes: +List<InteractiveDocuments.BlockScene>, +session: E.Session) ->
  Rule.FenceAttachments<Rule.admitted_fence_attachments(source, parent, codes, scenes, session),
    Model.fence_attachments(source, parent, codes, scenes, session)>:
  +input = List.append(&2, Model.FenceAttachment, Model.code_attachments(codes, source, parent), Model.interactive_attachments(scenes, session))
  +expected = Rule.admitted_fence_attachments(source, parent, codes, scenes, session)
  +positions = Model.ordered_fence_attachments(input)
  Rule.FenceAttachments{positions,
    Equal.sym((+List<SurfaceTypes.Node>), Model.fence_attachment_nodes(positions), Rule.required_fence_nodes(positions), fence_nodes_complete(positions)),
    Std.transport((+List<Model.FenceAttachment>), input,
      (values => Rule.FenceOrder<values, positions>), complete_fence_order(input), expected,
      Equal.sym((+List<Model.FenceAttachment>), input, expected, fence_collection_complete(source, parent, codes, scenes, session)))}

def Rule.fence_attachments_complete(source, parent, codes, scenes, session):
  complete_fence_attachments(source, parent, codes, scenes, session)

def complete_output_attachments(+source: Code.Source, +parent: Identity.Key, +state: InteractionTypes.State) ->
  Rule.OutputAttachments(source, parent, state, Model.output_attachments(source, parent, state)):
  +session = E.session(Core.application(state))
  complete_fence_attachments(source, parent, Core.code_scenes(Core.application(state)), E.interactive_scenes(source, session), session)

def Rule.output_attachments_complete(source, parent, state):
  complete_output_attachments(source, parent, state)

def complete_speech_frame(+id: Nat, +speaker: Conversation.Speaker, +text: String, +message: D.Message,
  +task: Nat, +parent: Identity.Key, +state: InteractionTypes.State) ->
  {Model.speech_node(id, speaker, text, message, task, parent, state) ==
    Rule.message_frame(id, speaker, text, message, task, parent, state,
      Model.output_attachments(Rule.expected_message_source(task, id, message, state),
        Rule.expected_output_key(Rule.expected_message_source(task, id, message, state), Identity.Entity{parent, "message", Nat.show(id)}), state)) : SurfaceTypes.Node}:
  +source = Model.message_source(task, id, message, state)
  +expected_source = Rule.expected_message_source(task, id, message, state)
  +fallback: Identity.Key = Identity.Entity{parent, "message", Nat.show(id)}
  +key = Model.output_key(expected_source, fallback)
  +expected_key = Rule.expected_output_key(expected_source, fallback)
  +role = Model.speaker_role(speaker)
  +expected_role = Rule.expected_speaker_role(speaker)
  +actual = Model.speech_node(id, speaker, text, message, task, parent, state)
  +source_replaced: SurfaceTypes.Node = SurfaceTypes.Node{key, "message/" ++ Nat.show(id), "Message", role,
    SurfaceTypes.RichText{expected_source, text}, Model.output_attachments(expected_source, key, state)}
  +key_replaced: SurfaceTypes.Node = SurfaceTypes.Node{expected_key, "message/" ++ Nat.show(id), "Message", role,
    SurfaceTypes.RichText{expected_source, text}, Model.output_attachments(expected_source, expected_key, state)}
  +target = Rule.message_frame(id, speaker, text, message, task, parent, state, Model.output_attachments(expected_source, expected_key, state))
  Equal.trans(SurfaceTypes.Node, actual, source_replaced, target,
    Equal.cong(Code.Source, SurfaceTypes.Node,
      (+value => SurfaceTypes.Node{Model.output_key(value, fallback), "message/" ++ Nat.show(id), "Message", role,
        SurfaceTypes.RichText{value, text}, Model.output_attachments(value, Model.output_key(value, fallback), state)}),
      source, expected_source, fence_message_source_complete(task, id, message, state)),
    Equal.trans(SurfaceTypes.Node, source_replaced, key_replaced, target,
      Equal.cong(Identity.Key, SurfaceTypes.Node,
        (+value => SurfaceTypes.Node{value, "message/" ++ Nat.show(id), "Message", role,
          SurfaceTypes.RichText{expected_source, text}, Model.output_attachments(expected_source, value, state)}),
        key, expected_key, fence_output_key_complete(expected_source, fallback)),
      Equal.cong(SurfaceTypes.Role, SurfaceTypes.Node,
        (value => SurfaceTypes.Node{expected_key, "message/" ++ Nat.show(id), "Message", value,
          SurfaceTypes.RichText{expected_source, text}, Model.output_attachments(expected_source, expected_key, state)}),
        role, expected_role, fence_speaker_role_complete(speaker))))

def complete_speech_attachments(+id: Nat, +speaker: Conversation.Speaker, +text: String, +message: D.Message,
  +task: Nat, +parent: Identity.Key, +state: InteractionTypes.State) ->
  Rule.SpeechAttachments(id, speaker, text, message, task, parent, state, Model.speech_node(id, speaker, text, message, task, parent, state)):
  +source = Rule.expected_message_source(task, id, message, state)
  +key = Rule.expected_output_key(source, Identity.Entity{parent, "message", Nat.show(id)})
  Rule.MessageAttachments{Model.output_attachments(source, key, state),
    complete_speech_frame(id, speaker, text, message, task, parent, state), complete_output_attachments(source, key, state)}

def Rule.speech_attachments_complete(id, speaker, text, message, task, parent, state):
  complete_speech_attachments(id, speaker, text, message, task, parent, state)

def fence_preview_origin_complete(+origin: Maybe<&2, D.OutputOrigin>, +viewer: Nat, +operation: Nat, +part: Nat, +session: E.Session) ->
  {Model.generated_source(origin, viewer, Code.StreamingPart{viewer, operation, part}, False{}, session) ==
    Rule.expected_preview_origin(origin, E.namespace(session), viewer, operation, part) : Code.Source}:
  match origin:
    case None{}: {==}
    case Some{value}: {==}

def fence_preview_source_complete(+viewer: Nat, +operation: Nat, +part: Nat, +state: InteractionTypes.State) ->
  {Model.preview_source(viewer, operation, part, state) == Rule.expected_preview_source(viewer, operation, part, state) : Code.Source}:
  fence_preview_origin_complete(Live.origin(Live.Output{viewer, operation, Nil{}}, part, E.program(Core.application(state))),
    viewer, operation, part, E.session(Core.application(state)))

def complete_live_part_attachments(+part: Nat, +text: String, +task: Nat, +operation: Nat,
  +parent: Identity.Key, +state: InteractionTypes.State) ->
  Rule.LivePartAttachments(part, text, task, operation, parent, state, Model.live_part_node(part, text, task, operation, parent, state)):
  +source = Model.preview_source(task, operation, part, state)
  +expected_source = Rule.expected_preview_source(task, operation, part, state)
  +fallback: Identity.Key = Identity.Entity{parent, "part", Nat.show(part)}
  +key = Model.output_key(expected_source, fallback)
  +expected_key = Rule.expected_output_key(expected_source, fallback)
  +children = Model.output_attachments(expected_source, expected_key, state)
  +middle: SurfaceTypes.Node = SurfaceTypes.Node{key, "generated-output", "Agent output", SurfaceTypes.AssistantMessage{},
    SurfaceTypes.RichText{expected_source, text}, Model.output_attachments(expected_source, key, state)}
  +target: SurfaceTypes.Node = SurfaceTypes.Node{expected_key, "generated-output", "Agent output", SurfaceTypes.AssistantMessage{},
    SurfaceTypes.RichText{expected_source, text}, children}
  Rule.MessageAttachments{children,
    Equal.trans(SurfaceTypes.Node, Model.live_part_node(part, text, task, operation, parent, state), middle, target,
      Equal.cong(Code.Source, SurfaceTypes.Node,
        (+value => SurfaceTypes.Node{Model.output_key(value, fallback), "generated-output", "Agent output", SurfaceTypes.AssistantMessage{},
          SurfaceTypes.RichText{value, text}, Model.output_attachments(value, Model.output_key(value, fallback), state)}),
        source, expected_source, fence_preview_source_complete(task, operation, part, state)),
      Equal.cong(Identity.Key, SurfaceTypes.Node,
        (+value => SurfaceTypes.Node{value, "generated-output", "Agent output", SurfaceTypes.AssistantMessage{},
          SurfaceTypes.RichText{expected_source, text}, Model.output_attachments(expected_source, value, state)}),
        key, expected_key, fence_output_key_complete(expected_source, fallback))),
    complete_output_attachments(expected_source, expected_key, state)}

def Rule.live_part_attachments_complete(part, text, task, operation, parent, state):
  complete_live_part_attachments(part, text, task, operation, parent, state)

def complete_retained_attachments(+source: Code.Source, +text: String, +parent: Identity.Key,
  +state: InteractionTypes.State, +visible: Bool) ->
  Rule.RetainedAttachments(source, text, parent, state, visible, Model.retained_output(source, text, parent, state, visible)):
  match visible:
    case False{}: {==}
    case True{}:
      +key = Model.output_key(source, parent)
      +expected_key = Rule.expected_output_key(source, parent)
      +children = Model.output_attachments(source, parent, state)
      Rule.RetainedMessage{children,
        Equal.cong(Identity.Key, (+List<SurfaceTypes.Node>),
          (value => [SurfaceTypes.Node{value, "generated-output", "Interrupted output", SurfaceTypes.AssistantMessage{}, SurfaceTypes.RichText{source, text}, children}]),
          key, expected_key, fence_output_key_complete(source, parent)),
        complete_output_attachments(source, parent, state)}

def Rule.retained_attachments_complete(source, text, parent, state, visible):
  complete_retained_attachments(source, text, parent, state, visible)

def Rule.creating_worktree_has_visible_feedback(message, parent): {==}
def Rule.failed_worktree_has_visible_diagnostic(message, parent): {==}
def Rule.failed_worktree_archive_has_visible_diagnostic(message, parent): {==}

def Rule.workspace_worktree_choice_retains_its_creation_scope(work, parent, state): {==}

def Rule.available_worktree_choice_edits_the_requested_creation_scope(work, parent, state): {==}

def Rule.unavailable_worktree_choice_has_no_control(editor, parent, state): {==}
