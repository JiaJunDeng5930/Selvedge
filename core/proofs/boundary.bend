import Base
import ../../bendlib/association-map.bend as Finite
import ../../bendlib/domain.bend as D
import ../../bendlib/json.bend as J
import ../client-services.bend as Services
import ../code-block.bend as Code
import ../live-output.bend as Live
import ../user-context.bend as Context
import ../boundary-laws.bend as Rule
import ../SYSTEM.bend as Core
import ../user-experience.bend as E

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

def Rule.evidence():
  Rule.Requirements{
    +access => credential => settings_open => appearance => next => +transfers => preview => picker => ticket => owned =>
      Equal.cong(Bool, Services.Decision, owned => Services.authentication(owned, Services.State{access, credential, settings_open, appearance, next, transfers, preview, picker}, Done{Unit{}}), Services.expected_access(access, ticket), True{}, owned),
    access => credential => settings_open => appearance => next => transfers => preview => picker => reason => {==},
    +state => result => {==},
    access => credential => settings_open => appearance => next => transfers => preview => picker => +application => {==},
    access => credential => settings_open => appearance => next => transfers => preview => picker => reason => application => {==},
    state => result => application => {==},
    {==},
    access => credential => settings_open => appearance => next => transfers => preview => ticket => result => stale =>
      Equal.cong(Bool, Services.Decision,
        owned => Services.authentication(owned,
          Services.State{access, credential, settings_open, appearance, next, transfers, preview, Services.NoDirectoryPicker{}}, result),
        Services.expected_access(access, ticket), False{}, stale),
    access => credential => settings_open => appearance => next => transfers => preview => ticket => result => missing =>
      Equal.cong(Maybe<&2, Services.Transfer>, Services.Decision,
        found => Services.upload_finished(found,
          Services.State{access, credential, settings_open, appearance, next, transfers, preview, Services.NoDirectoryPicker{}}, ticket, result),
        Finite.find(~Services.Transfer, transfers, ticket), None{}, missing),
    access => credential => settings_open => appearance => next => transfers => preview => ticket => editor => file => attachment => found =>
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
        {==}),
    access => credential => settings_open => appearance => next => transfers => ticket => result =>
      {==},
    access => credential => settings_open => appearance => next => transfers => current => file => trigger => ticket => result => different =>
      Equal.cong(Bool, Services.Decision,
        owned => Services.finish_preview(owned,
          Services.State{access, credential, settings_open, appearance, next, transfers,
            Services.LoadingPreview{current, file, trigger}, Services.NoDirectoryPicker{}}, file, trigger, result),
        Nat.is_eq(current, ticket), False{}, different),
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
