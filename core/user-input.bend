import Base
import ../MODEL.bend as M
import ../BOARD.bend as B
import ../FEATURES.bend as F
import ../bendlib/domain.bend as D
import ../bendlib/json.bend as J
import ./user-context.bend as Context

# Editor identities denote the user's work, independently of its current page,
# popover, delivery intent or platform widget lifetime.
type Editor is Data:
  NewTaskEditor{}
  MessageEditor{task: Nat}
  ProjectEditor{project: Maybe<&2, Nat>}
  CardEditor{card: Maybe<&2, Nat>}
  AgentEditor{agent: Maybe<&2, Nat>}
  ForkEditor{task: Nat}
  CompactEditor{task: Nat}

type Text is Data:
  Text{value: String}

type ReadingIntent is Data:
  FollowLatest{}
  ReadHistory{}

type Delivery is Data:
  Send{}
  Steer{}

type Body is Data:
  NewTask{message: Text, profile: String, reasoning: String, context: Context.Configuration}
  Message{task: Nat, message: Text, delivery: Delivery}
  Project{project: Maybe<&2, Nat>, name: String, workspace: D.Workspace}
  Card{card: Maybe<&2, Nat>, revision: Nat, value: B.Draft, assist: Bool, profile: String, keep_open: Bool}
  Agent{agent: Maybe<&2, Nat>, revision: Nat, name: String, profile: String, reasoning: String,
    instructions: String, context: Context.Configuration, concurrency: Nat}
  Fork{task: Nat, count: Nat, messages: +List<String>, context: Context.Configuration}
  Compact{task: Nat, summary: Maybe<&2, String>}

type Feedback is Data:
  Editing{}
  Accepted{revision: Nat, reply: J.Json}
  Rejected{revision: Nat, reason: String}

type Draft is Data:
  Draft{revision: Nat, body: Body, feedback: Feedback, directory_entry: String}

type Edit is Data:
  WriteDirectory{path: String}
  ConfirmDirectory{}
  EditWorkspace{change: Context.WorkspaceEdit}
  WriteMessage{message: Text}
  ChooseDelivery{delivery: Delivery}
  ChooseModel{profile: String, reasoning: String}
  ConfigureContext{change: Context.Change}
  NameProject{name: String}
  ConfigureProjectWorkspace{workspace: D.Workspace}
  WriteCard{patch: B.Patch}
  KeepCaptureOpen{enabled: Bool}
  ConfigureCardAssistance{assist: Bool, profile: String}
  NameAgent{name: String}
  WriteInstructions{instructions: String}
  SetConcurrency{concurrency: Nat}
  SetFork{count: Nat, messages: +List<String>}
  WriteSummary{summary: Maybe<&2, String>}

type Route is Data:
  Start{}
  Conversation{task: Nat}
  ProjectHome{project: Nat}
  ProjectCollection{}
  TaskBoard{}
  AgentCollection{}

type Subject is Data:
  TaskSubject{id: Nat}
  ProjectSubject{id: Nat}
  CardSubject{id: Nat}
  AgentSubject{id: Nat}

type Panel is Data:
  ProjectPicker{}
  ObjectActions{subject: Subject}
  ArchivedCards{}
  BoardSettings{}
  BoardFilters{}
  CardDetails{card: Nat}
  EditObject{editor: Editor}
  TaskDetails{task: Nat}
  WorkspaceConfiguration{editor: Editor}
  PermissionsConfiguration{editor: Editor}
  TaskContext{task: Nat}
  ModelPicker{editor: Editor}
  DeliveryPicker{task: Nat}
  Confirm{command: M.Command, title: String, destination: Route}

type Action is Data:
  Navigate{route: Route}
  SelectProject{project: Maybe<&2, Nat>}
  ToggleProjectGroup{project: Nat}
  BeginTask{project: Maybe<&2, Nat>}
  EditProject{project: Maybe<&2, Nat>}
  NewCard{stage: B.Stage}
  EditCard{card: Nat}
  EditAgent{agent: Maybe<&2, Nat>}
  ForkTask{task: Nat}
  CompactTask{task: Nat}
  Submit{editor: Editor}
  ControlTask{task: Nat, control: D.Control}
  CancelOperation{task: Nat, operation: Nat}
  ReviewApproval{task: Nat, operation: Nat, allow: Bool, reason: String}
  DeleteProject{project: Nat}
  BoardCommand{command: B.Command}
  OpenPanel{panel: Panel, trigger: String}
  ClosePanel{}
  ConfirmAction{}

type Input is Data:
  Activate{action: Action}
  EditDraft{editor: Editor, edit: Edit}
  ReadTimeline{task: Nat, generation: Nat, intent: ReadingIntent}
  SetDisclosure{task: Nat, group: Nat, occurrence: Nat, expanded: Bool}
  SetNavigation{expanded: Bool}
  SearchChoices{query: String}
  FilterBoard{filter: B.Filter}

def approval_outcome(allow: Bool, reason: String) -> D.ApprovalOutcome:
  match allow:
    case True{}: D.ApprovalAllowed{reason}
    case False{}: D.ApprovalDenied{reason}

# Both observation and activation use this meaning. A renderer cannot choose a
# different command while retaining the enabled state of another command.
def direct_command(action: Action) -> Maybe<&2, M.Command>:
  match action:
    case ControlTask{task, control}: Some{M.ChangeStatus{task, control}}
    case CancelOperation{task, operation}: Some{M.Cancel{task, operation}}
    case ReviewApproval{task, operation, allow, reason}: Some{M.ReviewApproval{task, operation, approval_outcome(allow, reason)}}
    case DeleteProject{project}: Some{M.DeleteProject{project}}
    case BoardCommand{command}: Some{M.FeatureCommand{F.BoardCommand{command}}}
    case _: None{}

def optional_key(value: Maybe<&2, Nat>) -> String:
  match value:
    case None{}: "new"
    case Some{id}: Nat.show(id)

def editor_key(editor: Editor) -> String:
  match editor:
    case NewTaskEditor{}: "new-task"
    case MessageEditor{id}: "message/" ++ Nat.show(id)
    case ProjectEditor{id}: "project/" ++ optional_key(id)
    case CardEditor{id}: "card/" ++ optional_key(id)
    case AgentEditor{id}: "agent/" ++ optional_key(id)
    case ForkEditor{id}: "fork/" ++ Nat.show(id)
    case CompactEditor{id}: "compact/" ++ Nat.show(id)

def same_editor(left: Editor, right: Editor) -> Bool:
  String.eq(editor_key(left), editor_key(right))

def text(value: Text) -> String:
  Text{value} = value
  value

def initial_text(value: String) -> Text:
  Text{value}

def owner(body: Body) -> Editor:
  match body:
    case NewTask{message, profile, reasoning, context}: NewTaskEditor{}
    case Message{task, message, delivery}: MessageEditor{task}
    case Project{id, name, workspace}: ProjectEditor{id}
    case Card{id, revision, value, assist, profile, keep_open}: CardEditor{id}
    case Agent{id, revision, name, profile, reasoning, instructions, context, concurrency}: AgentEditor{id}
    case Fork{task, count, messages, context}: ForkEditor{task}
    case Compact{task, summary}: CompactEditor{task}

def chosen(~A: Data, value: Maybe<&2, A>, fallback: A) -> A:
  match value:
    case None{}: fallback
    case Some{value}: value

def patch_card(patch: B.Patch, value: B.Draft) -> B.Draft:
  B.Patch{title, description, stage, priority, owner, project, labels, attachments} = patch
  B.Draft{old_title, old_description, old_stage, old_priority, old_owner, old_project, old_labels, old_attachments} = value
  B.Draft{chosen(~String, title, old_title), chosen(~String, description, old_description),
    chosen(~B.Stage, stage, old_stage), chosen(~B.Priority, priority, old_priority),
    chosen(~B.Owner, owner, old_owner), chosen(~(Maybe<&2, Nat>), project, old_project),
    chosen(~(+List<String>), labels, old_labels), chosen(~(+List<B.Attachment>), attachments, old_attachments)}

def replace_context(result: Result<&2, &2, String, Context.Configuration>, body: Body) -> Result<&2, &2, String, Body>:
  match result body:
    case Fail{reason} _: Fail{reason}
    case Done{context} NewTask{message, profile, reasoning, previous}: Done{NewTask{message, profile, reasoning, context}}
    case Done{context} Agent{id, revision, name, profile, reasoning, instructions, previous, concurrency}:
      Done{Agent{id, revision, name, profile, reasoning, instructions, context, concurrency}}
    case Done{context} Fork{task, count, messages, previous}: Done{Fork{task, count, messages, context}}
    case _ _: Fail{"This editor does not configure an execution context"}

def apply_workspace(change: Context.WorkspaceEdit, body: Body, world: M.World()) -> Result<&2, &2, String, Body>:
  match body:
    case Project{id, name, workspace}: Done{Project{id, name, Context.edit_workspace(change, workspace)}}
    case NewTask{message, profile, reasoning, +context}:
      replace_context(Context.modify_workspace(context, change, world), NewTask{message, profile, reasoning, context})
    case Agent{id, revision, name, profile, reasoning, instructions, +context, concurrency}:
      replace_context(Context.modify_workspace(context, change, world), Agent{id, revision, name, profile, reasoning, instructions, context, concurrency})
    case Fork{task, count, messages, +context}: replace_context(Context.modify_workspace(context, change, world), Fork{task, count, messages, context})
    case _: Fail{"This editor does not configure a workspace"}

def fork_change(task: Nat, change: Context.Change) -> Context.Change:
  match change:
    case Context.ChooseOrigin{Context.ProjectDefaults{project}}: Context.ChooseOrigin{Context.ProjectForParent{task, project}}
    case Context.ChooseOrigin{Context.EnvironmentDefaults{}}: Context.ChooseOrigin{Context.ParentTask{task}}
    case other: other

def apply_edit(change: Edit, body: Body, world: M.World()) -> Result<&2, &2, String, Body>:
  match change body:
    case EditWorkspace{change} body: apply_workspace(change, body, world)
    case WriteMessage{value} NewTask{old, profile, reasoning, context}: Done{NewTask{value, profile, reasoning, context}}
    case WriteMessage{value} Message{task, old, delivery}: Done{Message{task, value, delivery}}
    case ChooseDelivery{value} Message{task, message, old}: Done{Message{task, message, value}}
    case ChooseModel{profile, reasoning} NewTask{message, old_profile, old_reasoning, context}:
      Done{NewTask{message, profile, reasoning, context}}
    case ChooseModel{profile, reasoning} Agent{id, revision, name, old_profile, old_reasoning, instructions, context, concurrency}:
      Done{Agent{id, revision, name, profile, reasoning, instructions, context, concurrency}}
    case ConfigureContext{change} NewTask{message, profile, reasoning, context}:
      Done{NewTask{message, profile, reasoning, Context.edit(context, change)}}
    case ConfigureContext{change} Fork{+task, count, messages, context}: Done{Fork{task, count, messages, Context.edit(context, fork_change(task, change))}}
    case ConfigureContext{change} Agent{id, revision, name, profile, reasoning, instructions, context, concurrency}:
      Done{Agent{id, revision, name, profile, reasoning, instructions, Context.edit(context, change), concurrency}}
    case NameProject{name} Project{id, old, workspace}: Done{Project{id, name, workspace}}
    case ConfigureProjectWorkspace{workspace} Project{id, name, old}: Done{Project{id, name, workspace}}
    case WriteCard{patch} Card{id, revision, value, assist, profile, keep_open}: Done{Card{id, revision, patch_card(patch, value), assist, profile, keep_open}}
    case KeepCaptureOpen{enabled} Card{None{}, revision, value, assist, profile, previous}: Done{Card{None{}, revision, value, assist, profile, enabled}}
    case ConfigureCardAssistance{assist, profile} Card{None{}, revision, value, old_assist, old_profile, keep_open}: Done{Card{None{}, revision, value, assist, profile, keep_open}}
    case NameAgent{name} Agent{id, revision, old, profile, reasoning, instructions, context, concurrency}:
      Done{Agent{id, revision, name, profile, reasoning, instructions, context, concurrency}}
    case WriteInstructions{instructions} Agent{id, revision, name, profile, reasoning, old, context, concurrency}:
      Done{Agent{id, revision, name, profile, reasoning, instructions, context, concurrency}}
    case SetConcurrency{concurrency} Agent{id, revision, name, profile, reasoning, instructions, context, old}:
      Done{Agent{id, revision, name, profile, reasoning, instructions, context, concurrency}}
    case SetFork{count, messages} Fork{task, old_count, old_messages, context}: Done{Fork{task, count, messages, context}}
    case WriteSummary{summary} Compact{task, old}: Done{Compact{task, summary}}
    case _ _: Fail{"This input does not belong to this editor"}

def editor_trigger(editor: Editor) -> String:
  match editor:
    case ProjectEditor{None{}}: "project/new"
    case ProjectEditor{Some{id}}: "project/edit/" ++ Nat.show(id)
    case CardEditor{None{}}: "card/new"
    case CardEditor{Some{id}}: "card/" ++ Nat.show(id)
    case AgentEditor{None{}}: "agent/new"
    case AgentEditor{Some{id}}: "agent/edit/" ++ Nat.show(id)
    case ForkEditor{id}: "fork/" ++ Nat.show(id)
    case CompactEditor{id}: "compact/" ++ Nat.show(id)
    case other: "composer/" ++ editor_key(other)

def card_command(id: Maybe<&2, Nat>, revision: Nat, value: B.Draft, assist: Bool, profile: String, now: U32) -> B.Command:
  match id:
    case None{}: B.Create{value, now, assist, profile}
    case Some{id}:
      B.Draft{title, description, stage, priority, owner, project, labels, attachments} = value
      B.Update{id, revision, B.Patch{Some{title}, Some{description}, Some{stage}, Some{priority}, Some{owner},
        Some{project}, Some{labels}, Some{attachments}}, now}

def project_command(id: Maybe<&2, Nat>, name: String, workspace: J.Json, guidance: J.Json) -> M.Command:
  match id:
    case None{}: M.CreateProject{name, workspace, guidance}
    case Some{id}: M.UpdateProject{id, Some{name}, workspace, guidance}

def message_command(delivery: Delivery, task: Nat, message: String) -> M.Command:
  match delivery:
    case Send{}: M.Send{task, message}
    case Steer{}: M.Steer{task, message}

def command(body: Body, now: U32) -> M.Command:
  match body:
    case NewTask{message, profile, reasoning, context}: M.Create{profile, reasoning, text(message), Context.settings(context)}
    case Message{task, message, delivery}: message_command(delivery, task, text(message))
    case Project{id, name, workspace}: project_command(id, name, D.workspace_json(workspace), J.Null{})
    case Card{id, revision, value, assist, profile, keep_open}: M.FeatureCommand{F.BoardCommand{card_command(id, revision, value, assist, profile, now)}}
    case Agent{id, +revision, name, profile, reasoning, instructions, context, concurrency}:
      M.FeatureCommand{F.BoardCommand{B.SaveAgent{id, revision, B.AgentProfile{revision, name, profile, reasoning, instructions, Context.settings(context), concurrency}}}}
    case Fork{task, count, messages, context}: M.Fork{task, count, messages, Context.settings(context)}
    case Compact{task, summary}: M.Compact{task, summary}

def required_workspace(body: Body) -> Maybe<&2, D.Workspace>:
  match body:
    case NewTask{message, profile, reasoning, context}: Context.required_workspace(context)
    case Project{id, name, workspace}: Some{workspace}
    case Agent{id, revision, name, profile, reasoning, instructions, context, concurrency}: Context.required_workspace(context)
    case Fork{task, count, messages, context}: Context.required_workspace(context)
    case _: None{}

def prepared_command(body: Body, observation: Context.DirectoryObservation, now: U32) -> M.Command:
  match body:
    case NewTask{message, profile, reasoning, context}: M.Create{profile, reasoning, text(message), Context.observed_settings(context, observation)}
    case Project{id, name, previous}:
      Context.DirectoryObservation{workspace, guidance} = observation
      project_command(id, name, D.workspace_json(workspace), D.project_json(guidance))
    case Agent{id, +revision, name, profile, reasoning, instructions, context, concurrency}:
      M.FeatureCommand{F.BoardCommand{B.SaveAgent{id, revision, B.AgentProfile{revision, name, profile, reasoning, instructions, Context.observed_settings(context, observation), concurrency}}}}
    case Fork{task, count, messages, context}: M.Fork{task, count, messages, Context.observed_settings(context, observation)}
    case other: command(other, now)

def creation_origin(origin: Context.Origin) -> Bool:
  match origin:
    case Context.ParentTask{id}: False{}
    case Context.ProjectForParent{task, project}: False{}
    case _: True{}

def fork_origin(origin: Context.Origin, task: Nat) -> Bool:
  match origin:
    case Context.ParentTask{id}: Nat.is_eq(id, task)
    case Context.ProjectForParent{parent, id}: Nat.is_eq(parent, task)
    case _: False{}

def valid_origin(body: Body) -> Bool:
  match body:
    case NewTask{message, profile, reasoning, Context.Configuration{origin, workspace, sandbox, approval}}: creation_origin(origin)
    case Agent{id, revision, name, profile, reasoning, instructions, Context.Configuration{origin, workspace, sandbox, approval}, concurrency}: creation_origin(origin)
    case Fork{task, count, messages, Context.Configuration{origin, workspace, sandbox, approval}}: fork_origin(origin, task)
    case _: True{}


def contents(draft: Draft) -> Body:
  Draft{revision, body, feedback, directory_entry} = draft
  body

def next_capture(draft: B.Draft) -> B.Draft:
  B.Draft{title, description, stage, priority, owner, project, labels, attachments} = draft
  B.Draft{"", "", stage, priority, owner, project, labels, Nil{}}
def after_accept(body: Body) -> Body:
  match body:
    case NewTask{message, profile, reasoning, context}: NewTask{initial_text(""), profile, reasoning, context}
    case Message{task, message, delivery}: Message{task, initial_text(""), delivery}
    case Card{None{}, revision, value, assist, profile, keep_open}: Card{None{}, revision, next_capture(value), assist, profile, keep_open}
    case other: other

def subject_key(subject: Subject) -> String:
  match subject:
    case TaskSubject{id}: "task/" ++ Nat.show(id)
    case ProjectSubject{id}: "project/" ++ Nat.show(id)
    case CardSubject{id}: "card/" ++ Nat.show(id)
    case AgentSubject{id}: "agent/" ++ Nat.show(id)


def workspace_capable(body: Body) -> Bool:
  match body:
    case NewTask{message, profile, reasoning, context}: True{}
    case Project{id, name, workspace}: True{}
    case Agent{id, revision, name, profile, reasoning, instructions, context, concurrency}: True{}
    case Fork{task, count, messages, context}: True{}
    case _: False{}

def directory_entry(draft: Draft) -> String:
  Draft{revision, body, feedback, entry} = draft
  entry

def edited_body(result: Result<&2, &2, String, Body>, revision: Nat, entry: String) -> Result<&2, &2, String, Draft>:
  match result:
    case Fail{reason}: Fail{reason}
    case Done{body}: Done{Draft{(revision + 1n : Nat), body, Editing{}, entry}}

def confirm_directory(admitted: Bool, +draft: Draft, world: M.World()) -> Result<&2, &2, String, Draft>:
  match admitted:
    case False{}: Done{draft}
    case True{}:
      Draft{revision, body, feedback, entry} = draft
      edited_body(apply_edit(EditWorkspace{Context.AddRoot{entry}}, body, world), revision, "")

def can_confirm_directory(draft: Draft) -> Bool:
  Draft{revision, body, feedback, entry} = draft
  Bool.not(String.eq(entry, "")) && workspace_capable(body)

def edit_draft(change: Edit, +draft: Draft, world: M.World()) -> Result<&2, &2, String, Draft>:
  match change:
    case WriteDirectory{path}:
      Draft{revision, body, feedback, old} = draft
      Done{Draft{(revision + 1n : Nat), body, Editing{}, path}}
    case ConfirmDirectory{}: confirm_directory(can_confirm_directory(draft), draft, world)
    case other:
      Draft{revision, body, feedback, entry} = draft
      edited_body(apply_edit(other, body, world), revision, entry)
