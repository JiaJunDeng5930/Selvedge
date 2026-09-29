import Base
import ../BOARD.bend as B
import ../MODEL.bend as M
import ../WORKSPACE.bend as W
import ../bendlib/association-map.bend as Finite
import ../bendlib/domain.bend as D
import ../bendlib/json.bend as J
import ./client-services.bend as Services
import ./code-block.bend as Code
import ./live-output.bend as Live
import ./user-context.bend as Context
import ./user-input.bend as U

# These fields expose only the settings that cross the directory-observation
# boundary and the existing policy fields preserved from the user's input.
type SettingsFields is Data:
  SettingsFields{workspace: J.Json, guidance: J.Json, project_id: J.Json,
    sandbox: J.Json, approval: J.Json}

def settings_fields(~value:J.Json) -> SettingsFields:
  SettingsFields{J.get(value, "workspace"), J.get(value, "guidance"),
    J.get(value, "project_id"), J.get(value, "sandbox"), J.get(value, "approval")}

def settings_fields_without_project(+previous:Maybe<&2, D.Workspace>, +sandbox:Maybe<&2, D.Sandbox>,
  +approval:Maybe<&2, Context.ApprovalChoice>, +workspace:D.Workspace, +guidance:D.ProjectContext) ->
  {settings_fields(Context.observed_settings(Context.Configuration{Context.EnvironmentDefaults{}, previous, sandbox, approval},
      Context.DirectoryObservation{workspace, guidance})) ==
    SettingsFields{D.workspace_json(workspace), D.project_json(guidance),
      J.get(Context.settings(Context.Configuration{Context.EnvironmentDefaults{}, previous, sandbox, approval}), "project_id"),
      J.get(Context.settings(Context.Configuration{Context.EnvironmentDefaults{}, previous, sandbox, approval}), "sandbox"),
      J.get(Context.settings(Context.Configuration{Context.EnvironmentDefaults{}, previous, sandbox, approval}), "approval")} : SettingsFields}:
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
  {settings_fields(Context.observed_settings(Context.Configuration{Context.ProjectDefaults{project}, previous, sandbox, approval},
      Context.DirectoryObservation{workspace, guidance})) ==
    SettingsFields{D.workspace_json(workspace), D.project_json(guidance),
      J.get(Context.settings(Context.Configuration{Context.ProjectDefaults{project}, previous, sandbox, approval}), "project_id"),
      J.get(Context.settings(Context.Configuration{Context.ProjectDefaults{project}, previous, sandbox, approval}), "sandbox"),
      J.get(Context.settings(Context.Configuration{Context.ProjectDefaults{project}, previous, sandbox, approval}), "approval")} : SettingsFields}:
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
  {settings_fields(Context.observed_settings(config, Context.DirectoryObservation{workspace, guidance})) ==
    SettingsFields{D.workspace_json(workspace), D.project_json(guidance),
      J.get(Context.settings(config), "project_id"),
      J.get(Context.settings(config), "sandbox"),
      J.get(Context.settings(config), "approval")} : SettingsFields}:
  match config:
    case Context.Configuration{Context.EnvironmentDefaults{}, previous, sandbox, approval}:
      settings_fields_without_project(previous, sandbox, approval, workspace, guidance)
    case Context.Configuration{Context.ParentTask{_}, previous, sandbox, approval}:
      settings_fields_without_project(previous, sandbox, approval, workspace, guidance)
    case Context.Configuration{Context.ProjectDefaults{project}, previous, sandbox, approval}:
      settings_fields_with_project(project, previous, sandbox, approval, workspace, guidance)
    case Context.Configuration{Context.ProjectForParent{task, project}, previous, sandbox, approval}:
      settings_fields_with_project(project, previous, sandbox, approval, workspace, guidance)

type Requirements is Type:
  Requirements{
    stale_auth: @+access:Services.Access -> @credential:String -> @settings_open:Bool ->
      @appearance:Services.Appearance -> @next:Nat -> @+transfers:+List<Finite.Entry(Services.Transfer)> ->
      @preview:Services.Preview -> @ticket:Nat -> @+result:Result<&2, &2, String, Unit> ->
      @stale:{Services.expected_access(access, ticket) == False{} : Bool} ->
      {Services.step(Services.Authenticated{ticket, result}, Services.State{access, credential,
        settings_open, appearance, next, transfers, preview}) ==
        Services.Decision{Services.State{access, credential, settings_open, appearance,
          next, transfers, preview}, Nil{}} : Services.Decision},
    missing_upload: @+access:Services.Access -> @credential:String -> @settings_open:Bool ->
      @appearance:Services.Appearance -> @next:Nat -> @+transfers:+List<Finite.Entry(Services.Transfer)> ->
      @preview:Services.Preview -> @ticket:Nat -> @+result:Result<&2, &2, String, B.Attachment> ->
      @missing:{Finite.find(~Services.Transfer, transfers, ticket) == None{} : Maybe<&2, Services.Transfer>} ->
      {Services.step(Services.Uploaded{ticket, result}, Services.State{access, credential,
        settings_open, appearance, next, transfers, preview}) ==
        Services.Decision{Services.State{access, credential, settings_open, appearance,
          next, transfers, preview}, Nil{}} : Services.Decision},
    upload_destination: @+access:Services.Access -> @credential:String -> @settings_open:Bool ->
      @appearance:Services.Appearance -> @next:Nat -> @+transfers:+List<Finite.Entry(Services.Transfer)> ->
      @preview:Services.Preview -> @ticket:Nat -> @+editor:U.Editor -> @+file:Services.File ->
      @+attachment:B.Attachment ->
      @found:{Finite.find(~Services.Transfer, transfers, ticket) ==
        Some{Services.Uploading{editor, file}} : Maybe<&2, Services.Transfer>} ->
      {Services.step(Services.Uploaded{ticket, Done{attachment}}, Services.State{access, credential,
        settings_open, appearance, next, transfers, preview}) ==
        Services.Decision{Services.State{access, credential, settings_open, appearance, next,
          Finite.remove(~Services.Transfer, transfers, ticket), preview},
          [Services.AttachToDraft{editor, attachment}]} : Services.Decision},
    closed_preview: @+access:Services.Access -> @credential:String -> @settings_open:Bool ->
      @appearance:Services.Appearance -> @next:Nat -> @+transfers:+List<Finite.Entry(Services.Transfer)> ->
      @ticket:Nat -> @+result:Result<&2, &2, String, String> ->
      {Services.step(Services.Previewed{ticket, result}, Services.State{access, credential,
        settings_open, appearance, next, transfers, Services.NoPreview{}}) ==
        Services.Decision{Services.State{access, credential, settings_open, appearance,
          next, transfers, Services.NoPreview{}}, Nil{}} : Services.Decision},
    stale_preview: @+access:Services.Access -> @credential:String -> @settings_open:Bool ->
      @appearance:Services.Appearance -> @next:Nat -> @+transfers:+List<Finite.Entry(Services.Transfer)> ->
      @current:Nat -> @+file:B.Attachment -> @trigger:String -> @ticket:Nat ->
      @+result:Result<&2, &2, String, String> ->
      @different:{Nat.is_eq(current, ticket) == False{} : Bool} ->
      {Services.step(Services.Previewed{ticket, result}, Services.State{access, credential,
        settings_open, appearance, next, transfers, Services.LoadingPreview{current, file, trigger}}) ==
        Services.Decision{Services.State{access, credential, settings_open, appearance, next,
          transfers, Services.LoadingPreview{current, file, trigger}}, Nil{}} : Services.Decision},
    stale_copy: @+identity:Code.Identity -> @source:String -> @+wrap:Bool -> @copy:Code.CopyState ->
      @next:Nat -> @pending:Maybe<&2, Nat> -> @ticket:Nat -> @success:Bool ->
      @stale:{Code.same_ticket(pending, ticket) == False{} : Bool} ->
      {Code.step(Code.Block{identity, source, Code.CodeView{wrap, copy}, next, pending},
        Code.Copied{ticket, success}) ==
        Code.Decision{Code.Block{identity, source, Code.CodeView{wrap, copy}, next, pending}, Nil{}} : Code.Decision},
    copy_snapshot: @+identity:Code.Identity -> @source:String -> @+wrap:Bool -> @copy:Code.CopyState ->
      @next:Nat -> @pending:Maybe<&2, Nat> ->
      @can_copy:{Code.code_can_copy(Code.CodeView{wrap, copy}) == True{} : Bool} ->
      {Code.step(Code.Block{identity, source, Code.CodeView{wrap, copy}, next, pending}, Code.Copy{}) ==
        Code.Decision{Code.Block{identity, source, Code.CodeView{wrap, Code.CopyPending{}},
          (next + 1n : Nat), Some{next}}, [Code.WriteClipboard{next, source}]} : Code.Decision},
    toggle_preserves_transfer: @+identity:Code.Identity -> @source:String -> @+wrap:Bool ->
      @copy:Code.CopyState -> @next:Nat -> @pending:Maybe<&2, Nat> ->
      {Code.step(Code.Block{identity, source, Code.CodeView{wrap, copy}, next, pending}, Code.ToggleWrap{}) ==
        Code.Decision{Code.Block{identity, source,
          Code.CodeView{Bool.not(wrap), copy}, next, pending}, Nil{}} : Code.Decision},
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
      {settings_fields(Context.observed_settings(config, Context.DirectoryObservation{workspace, guidance})) ==
        SettingsFields{D.workspace_json(workspace), D.project_json(guidance),
          J.get(Context.settings(config), "project_id"),
          J.get(Context.settings(config), "sandbox"),
          J.get(Context.settings(config), "approval")} : SettingsFields},
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

def evidence() -> Requirements:
  Requirements{
    access => credential => settings_open => appearance => next => transfers => preview => ticket => result => stale =>
      Equal.cong(Bool, Services.Decision,
        owned => Services.authentication(owned,
          Services.State{access, credential, settings_open, appearance, next, transfers, preview}, result),
        Services.expected_access(access, ticket), False{}, stale),
    access => credential => settings_open => appearance => next => transfers => preview => ticket => result => missing =>
      Equal.cong(Maybe<&2, Services.Transfer>, Services.Decision,
        found => Services.upload_finished(found,
          Services.State{access, credential, settings_open, appearance, next, transfers, preview}, ticket, result),
        Finite.find(~Services.Transfer, transfers, ticket), None{}, missing),
    access => credential => settings_open => appearance => next => transfers => preview => ticket => editor => file => attachment => found =>
      Equal.trans(Services.Decision,
        Services.step(Services.Uploaded{ticket, Done{attachment}},
          Services.State{access, credential, settings_open, appearance, next, transfers, preview}),
        Services.upload_finished(Some{Services.Uploading{editor, file}},
          Services.State{access, credential, settings_open, appearance, next, transfers, preview},
          ticket, Done{attachment}),
        Services.Decision{Services.State{access, credential, settings_open, appearance, next,
          Finite.remove(~Services.Transfer, transfers, ticket), preview},
          [Services.AttachToDraft{editor, attachment}]},
        Equal.cong(Maybe<&2, Services.Transfer>, Services.Decision,
          found => Services.upload_finished(found,
            Services.State{access, credential, settings_open, appearance, next, transfers, preview},
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
            Services.LoadingPreview{current, file, trigger}}, file, trigger, result),
        Nat.is_eq(current, ticket), False{}, different),
    identity => source => wrap => copy => next => pending => ticket => success => stale =>
      Equal.cong(Bool, Code.Decision,
        owned => Code.copy_result(owned, success, Code.Block{identity, source,
          Code.CodeView{wrap, copy}, next, pending}),
        Code.same_ticket(pending, ticket), False{}, stale),
    identity => source => wrap => copy => next => pending => can_copy =>
      Equal.cong(Bool, Code.Decision,
        allowed => Code.begin(allowed, Code.Block{identity, source,
          Code.CodeView{wrap, copy}, next, pending}),
        Code.code_can_copy(Code.CodeView{wrap, copy}), True{}, can_copy),
    identity => source => wrap => copy => next => pending => {==},
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
