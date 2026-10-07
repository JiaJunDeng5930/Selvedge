import Base
import ../../features/board/MODEL.bend as B
import ../../harness/MODEL.bend as M
import ../../harness/workspace/WORKSPACE.bend as W
import ../INPUT.bend as U
import ../../bendlib/association-map.bend as Finite
import ../../harness/DOMAIN.bend as D
import ../../bendlib/json.bend as J
import ../services/MODEL.bend as Services
import ../conversation/CODE.bend as Code
import ../conversation/OUTPUT.bend as Live
import ../services/CONTEXT.bend as Context
import ./boundary-laws.bend as Rule
import ../STATE.bend as Core
import ../session/MODEL.bend as E

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
        Core.application_result_with_services(E.unchanged(application), Services.with_settings_open(True{}, Services.with_credential("", Services.with_access(Services.CredentialRejected{reason}, state))), Nil{}) : Core.Decision}:
  Services.State{+access, +credential, +settings_open, +appearance, +next, +transfers, +preview, +picker} = state
  {==}

def encapsulated_readiness_attention(+state: Services.State, +application: E.Application) ->
  {Core.service_result(Services.authentication(True{}, state, Done{Unit{}}), application) ==
        Core.Decision{Core.from_application(application, Services.with_settings_open(False{}, Services.with_credential("", Services.with_access(Services.Connected{}, state)))), D.success(J.Null{}), Nil{}, [E.Attend{Core.session_attention(application)}], Nil{}, False{}} : Core.Decision}:
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

def Rule.evidence():
  Rule.Requirements{
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
