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
import ./SYSTEM.bend as Core
import ./user-experience.bend as E

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

type Requirements is Type:
  Requirements{
    accepted_auth: @+access:Services.Access -> @credential:String -> @settings_open:Bool -> @appearance:Services.Appearance -> @next:Nat -> @+transfers:+List<Finite.Entry(Services.Transfer)> -> @preview:Services.Preview -> @picker:Services.DirectoryPicker -> @ticket:Nat ->
      @owned:{Services.expected_access(access, ticket) == True{} : Bool} ->
      {Services.step(Services.Authenticated{ticket, Done{Unit{}}}, Services.State{access, credential, settings_open, appearance, next, transfers, preview, picker}) ==
        Services.Decision{Services.State{Services.Connected{}, "", False{}, appearance, next, transfers, preview, picker}, [Services.SessionReady{}]} : Services.Decision},
    failed_auth: @access:Services.Access -> @credential:String -> @settings_open:Bool -> @appearance:Services.Appearance -> @next:Nat -> @transfers:+List<Finite.Entry(Services.Transfer)> -> @preview:Services.Preview -> @picker:Services.DirectoryPicker -> @reason:String ->
      {Services.authentication(True{}, Services.State{access, credential, settings_open, appearance, next, transfers, preview, picker}, Fail{reason}) ==
        Services.Decision{Services.State{Services.CredentialRejected{reason}, "", True{}, appearance, next, transfers, preview, picker}, Nil{}} : Services.Decision},
    unowned_auth: @+state:Services.State -> @result:Result<&2, &2, String, Unit> ->
      {Services.authentication(False{}, state, result) == Services.Decision{state, Nil{}} : Services.Decision},
    readiness_attention: @access:Services.Access -> @credential:String -> @settings_open:Bool -> @appearance:Services.Appearance -> @next:Nat -> @transfers:+List<Finite.Entry(Services.Transfer)> -> @preview:Services.Preview -> @picker:Services.DirectoryPicker -> @+application:E.Application ->
      {Core.service_result(Services.authentication(True{}, Services.State{access, credential, settings_open, appearance, next, transfers, preview, picker}, Done{Unit{}}), application) ==
        Core.Decision{Core.State{application, Services.State{Services.Connected{}, "", False{}, appearance, next, transfers, preview, picker}}, D.success(J.Null{}), Nil{}, [E.Attend{Core.session_attention(application)}], Nil{}, False{}} : Core.Decision},
    failed_auth_no_attention: @access:Services.Access -> @credential:String -> @settings_open:Bool -> @appearance:Services.Appearance -> @next:Nat -> @transfers:+List<Finite.Entry(Services.Transfer)> -> @preview:Services.Preview -> @picker:Services.DirectoryPicker -> @reason:String -> @application:E.Application ->
      {Core.service_result(Services.authentication(True{}, Services.State{access, credential, settings_open, appearance, next, transfers, preview, picker}, Fail{reason}), application) ==
        Core.application_result_with_services(E.unchanged(application), Services.State{Services.CredentialRejected{reason}, "", True{}, appearance, next, transfers, preview, picker}, Nil{}) : Core.Decision},
    unowned_auth_no_attention: @state:Services.State -> @result:Result<&2, &2, String, Unit> -> @application:E.Application ->
      {Core.service_result(Services.authentication(False{}, state, result), application) == Core.application_result_with_services(E.unchanged(application), state, Nil{}) : Core.Decision},
    readiness_is_internal: {Core.external_effect(Services.SessionReady{}) == False{} : Bool},
    stale_auth: @+access:Services.Access -> @credential:String -> @settings_open:Bool ->
      @appearance:Services.Appearance -> @next:Nat -> @+transfers:+List<Finite.Entry(Services.Transfer)> ->
      @preview:Services.Preview -> @ticket:Nat -> @+result:Result<&2, &2, String, Unit> ->
      @stale:{Services.expected_access(access, ticket) == False{} : Bool} ->
      {Services.step(Services.Authenticated{ticket, result}, Services.State{access, credential,
        settings_open, appearance, next, transfers, preview, Services.NoDirectoryPicker{}}) ==
        Services.Decision{Services.State{access, credential, settings_open, appearance,
          next, transfers, preview, Services.NoDirectoryPicker{}}, Nil{}} : Services.Decision},
    missing_upload: @+access:Services.Access -> @credential:String -> @settings_open:Bool ->
      @appearance:Services.Appearance -> @next:Nat -> @+transfers:+List<Finite.Entry(Services.Transfer)> ->
      @preview:Services.Preview -> @ticket:Nat -> @+result:Result<&2, &2, String, B.Attachment> ->
      @missing:{Finite.find(~Services.Transfer, transfers, ticket) == None{} : Maybe<&2, Services.Transfer>} ->
      {Services.step(Services.Uploaded{ticket, result}, Services.State{access, credential,
        settings_open, appearance, next, transfers, preview, Services.NoDirectoryPicker{}}) ==
        Services.Decision{Services.State{access, credential, settings_open, appearance,
          next, transfers, preview, Services.NoDirectoryPicker{}}, Nil{}} : Services.Decision},
    upload_destination: @+access:Services.Access -> @credential:String -> @settings_open:Bool ->
      @appearance:Services.Appearance -> @next:Nat -> @+transfers:+List<Finite.Entry(Services.Transfer)> ->
      @preview:Services.Preview -> @ticket:Nat -> @+editor:U.Editor -> @+file:Services.File ->
      @+attachment:B.Attachment ->
      @found:{Finite.find(~Services.Transfer, transfers, ticket) ==
        Some{Services.Uploading{editor, file}} : Maybe<&2, Services.Transfer>} ->
      {Services.step(Services.Uploaded{ticket, Done{attachment}}, Services.State{access, credential,
        settings_open, appearance, next, transfers, preview, Services.NoDirectoryPicker{}}) ==
        Services.Decision{Services.State{access, credential, settings_open, appearance, next,
          Finite.remove(~Services.Transfer, transfers, ticket), preview, Services.NoDirectoryPicker{}},
          [Services.AttachToDraft{editor, attachment}]} : Services.Decision},
    closed_preview: @+access:Services.Access -> @credential:String -> @settings_open:Bool ->
      @appearance:Services.Appearance -> @next:Nat -> @+transfers:+List<Finite.Entry(Services.Transfer)> ->
      @ticket:Nat -> @+result:Result<&2, &2, String, String> ->
      {Services.step(Services.Previewed{ticket, result}, Services.State{access, credential,
        settings_open, appearance, next, transfers, Services.NoPreview{}, Services.NoDirectoryPicker{}}) ==
        Services.Decision{Services.State{access, credential, settings_open, appearance,
          next, transfers, Services.NoPreview{}, Services.NoDirectoryPicker{}}, Nil{}} : Services.Decision},
    stale_preview: @+access:Services.Access -> @credential:String -> @settings_open:Bool ->
      @appearance:Services.Appearance -> @next:Nat -> @+transfers:+List<Finite.Entry(Services.Transfer)> ->
      @current:Nat -> @+file:B.Attachment -> @trigger:String -> @ticket:Nat ->
      @+result:Result<&2, &2, String, String> ->
      @different:{Nat.is_eq(current, ticket) == False{} : Bool} ->
      {Services.step(Services.Previewed{ticket, result}, Services.State{access, credential,
        settings_open, appearance, next, transfers, Services.LoadingPreview{current, file, trigger}, Services.NoDirectoryPicker{}}) ==
        Services.Decision{Services.State{access, credential, settings_open, appearance, next,
          transfers, Services.LoadingPreview{current, file, trigger}, Services.NoDirectoryPicker{}}, Nil{}} : Services.Decision},
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

law evidence:
  Requirements
