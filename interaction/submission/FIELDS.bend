import Base
import ../../harness/COMMANDS.bend as Commands
import ../../harness/MODEL.bend as M
import ../../harness/DOMAIN.bend as D
import ../../features/board/MODEL.bend as B
import ../INPUT.bend as U
import ../services/CONTEXT.bend as Context

type ChoiceValue is Data:
  ChoiceValue{value: String, label: String}

type Field is Data:
  MessageText{}
  ProjectName{}
  WorkspaceDirectories{}
  WorkspacePrimary{}
  ContextOrigin{}
  SandboxMode{}
  NetworkAccess{}
  ApprovalPolicy{}
  ModelProfile{}
  ReasoningEffort{}
  DeliveryIntent{}
  CardTitle{}
  CardDescription{}
  CardStage{}
  CardPriority{}
  CardOwner{}
  CardProject{}
  CardLabels{}
  CardAttachments{}
  ContinueCapture{}
  AssistedCapture{}
  AssistanceProfile{}
  AgentName{}
  AgentInstructions{}
  AgentConcurrency{}
  ForkCount{}
  ForkMessages{}
  CompactionSummary{}

type Entry is Data:
  DisplayOnly{}
  SingleLine{}
  Multiline{}
  Choice{}
  MultipleChoices{}
  PositiveInteger{}
  DirectoryCollection{}
  FileCollection{}

type FieldScene is Data:
  FieldScene{field: Field, label: String, entry: Entry}

type Section is Data:
  Section{title: String, fields: +List<FieldScene>}

# The value and allowed choices remain in the typed InputGroup observation.
# This defines their product-level grouping, order and editing affordance.
type Value is Data:
  Toggle{enabled: Bool}
  Text{value: String}
  Count{value: Nat}
  Strings{values: +List<String>}
  Stage{value: B.Stage}
  Priority{value: B.Priority}
  Owner{value: B.Owner}
  Project{value: Maybe<&2, Nat>}
  ContextChange{value: Context.Change}
  WorkspaceChange{value: Context.WorkspaceEdit}
  Model{profile: String, reasoning: String}
  Delivery{value: U.Delivery}
  Assistance{enabled: Bool, profile: String}
  Fork{count: Nat, messages: +List<String>}
  Summary{value: Maybe<&2, String>}

type Observed is Data:
  ToggleValue{enabled: Bool}
  TextValue{text: String}
  CountValue{count: Nat}
  TextsValue{values: +List<String>}
  WorkspaceValue{workspace: D.Workspace}
  ContextValue{preview: Context.Preview}
  ModelValue{profile: String, reasoning: String}
  DeliveryValue{delivery: U.Delivery}
  StageValue{stage: B.Stage}
  PriorityValue{priority: B.Priority}
  OwnerValue{owner: B.Owner}
  ProjectValue{project: Maybe<&2, Nat>}
  AttachmentsValue{files: +List<B.Attachment>}
  AssistanceValue{enabled: Bool, profile: String}
  OptionalTextValue{text: Maybe<&2, String>}
  NotApplicable{}

def execution() -> Section:
  Section{"Execution context", [FieldScene{ContextOrigin{}, "Defaults from", Choice{}},
    FieldScene{WorkspaceDirectories{}, "Working directories", DirectoryCollection{}},
    FieldScene{WorkspacePrimary{}, "Primary directory", Choice{}},
    FieldScene{SandboxMode{}, "Filesystem access", Choice{}},
    FieldScene{NetworkAccess{}, "Network access", Choice{}},
    FieldScene{ApprovalPolicy{}, "Approval policy", Choice{}}]}

def model() -> Section:
  Section{"Model", [FieldScene{ModelProfile{}, "Model", Choice{}}, FieldScene{ReasoningEffort{}, "Reasoning effort", Choice{}}]}

def capture_structure(id: Maybe<&2, Nat>) -> +List<Section>:
  match id:
    case None{}: [Section{"Creation options", [FieldScene{ContinueCapture{}, "Create another after saving", Choice{}}, FieldScene{AssistedCapture{}, "Assist with title and description", Choice{}}, FieldScene{AssistanceProfile{}, "Assistance model", Choice{}}]}]
    case Some{id}: Nil{}

def structure(body: U.Body) -> +List<Section>:
  match body:
    case U.NewTask{message, profile, reasoning, context}:
      [Section{"Message", [FieldScene{MessageText{}, "Task", Multiline{}}]}, model(), execution()]
    case U.Message{task, message, delivery}:
      [Section{"Message", [FieldScene{MessageText{}, "Message", Multiline{}}, FieldScene{DeliveryIntent{}, "Send as", Choice{}}]}]
    case U.Project{id, name, workspace}:
      [Section{"Project", [FieldScene{ProjectName{}, "Name", SingleLine{}}]},
       Section{"Default workspace", [FieldScene{WorkspaceDirectories{}, "Working directories", DirectoryCollection{}}, FieldScene{WorkspacePrimary{}, "Primary directory", Choice{}}]}]
    case U.Card{id, revision, draft, assist, profile, keep_open}:
      List.append(&2, Section, [Section{"Work", [FieldScene{CardTitle{}, "Title", SingleLine{}}, FieldScene{CardDescription{}, "Description", Multiline{}}]},
       Section{"Organization", [FieldScene{CardStage{}, "Stage", Choice{}}, FieldScene{CardPriority{}, "Priority", Choice{}},
         FieldScene{CardOwner{}, "Assignee", Choice{}}, FieldScene{CardProject{}, "Project", Choice{}}, FieldScene{CardLabels{}, "Labels", Multiline{}}]},
       Section{"Attachments", [FieldScene{CardAttachments{}, "Files", FileCollection{}}]}], capture_structure(id))
    case U.Agent{id, revision, name, profile, reasoning, instructions, context, concurrency}:
      [Section{"Agent", [FieldScene{AgentName{}, "Name", SingleLine{}}, FieldScene{AgentInstructions{}, "Instructions", Multiline{}}, FieldScene{AgentConcurrency{}, "Concurrent tasks", PositiveInteger{}}]}, model(), execution()]
    case U.Fork{task, count, messages, context}:
      [Section{"Fork", [FieldScene{ForkCount{}, "Number of tasks", PositiveInteger{}}, FieldScene{ForkMessages{}, "Initial messages", Multiline{}}]}, execution()]
    case U.Compact{task, summary}:
      [Section{"Compaction", [FieldScene{CompactionSummary{}, "Summary override", Multiline{}}]}]

def edit(field: Field, value: Value) -> Maybe<&2, U.Edit>:
  match field value:
    case ContinueCapture{} Toggle{enabled}: Some{U.KeepCaptureOpen{enabled}}
    case MessageText{} Text{text}: Some{U.WriteMessage{U.Text{text}}}
    case ProjectName{} Text{text}: Some{U.NameProject{text}}
    case WorkspaceDirectories{} WorkspaceChange{Context.AddRoot{path}}: Some{U.EditWorkspace{Context.AddRoot{path}}}
    case WorkspaceDirectories{} WorkspaceChange{Context.RemoveRoot{path}}: Some{U.EditWorkspace{Context.RemoveRoot{path}}}
    case WorkspacePrimary{} WorkspaceChange{Context.ChoosePrimary{path}}: Some{U.EditWorkspace{Context.ChoosePrimary{path}}}
    case ContextOrigin{} ContextChange{Context.ChooseOrigin{origin}}: Some{U.ConfigureContext{Context.ChooseOrigin{origin}}}
    case SandboxMode{} ContextChange{Context.SetSandbox{sandbox}}: Some{U.ConfigureContext{Context.SetSandbox{sandbox}}}
    case NetworkAccess{} ContextChange{Context.SetSandbox{sandbox}}: Some{U.ConfigureContext{Context.SetSandbox{sandbox}}}
    case ApprovalPolicy{} ContextChange{Context.SetApproval{approval}}: Some{U.ConfigureContext{Context.SetApproval{approval}}}
    case ModelProfile{} Model{profile, reasoning}: Some{U.ChooseModel{profile, reasoning}}
    case ReasoningEffort{} Model{profile, reasoning}: Some{U.ChooseModel{profile, reasoning}}
    case DeliveryIntent{} Delivery{delivery}: Some{U.ChooseDelivery{delivery}}
    case CardTitle{} Text{text}: Some{U.WriteCard{B.Patch{Some{text}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}}}
    case CardDescription{} Text{text}: Some{U.WriteCard{B.Patch{None{}, Some{text}, None{}, None{}, None{}, None{}, None{}, None{}}}}
    case CardStage{} Stage{stage}: Some{U.WriteCard{B.Patch{None{}, None{}, Some{stage}, None{}, None{}, None{}, None{}, None{}}}}
    case CardPriority{} Priority{priority}: Some{U.WriteCard{B.Patch{None{}, None{}, None{}, Some{priority}, None{}, None{}, None{}, None{}}}}
    case CardOwner{} Owner{owner}: Some{U.WriteCard{B.Patch{None{}, None{}, None{}, None{}, Some{owner}, None{}, None{}, None{}}}}
    case CardProject{} Project{project}: Some{U.WriteCard{B.Patch{None{}, None{}, None{}, None{}, None{}, Some{project}, None{}, None{}}}}
    case CardLabels{} Strings{labels}: Some{U.WriteCard{B.Patch{None{}, None{}, None{}, None{}, None{}, None{}, Some{labels}, None{}}}}
    case AssistedCapture{} Assistance{enabled, profile}: Some{U.ConfigureCardAssistance{enabled, profile}}
    case AssistanceProfile{} Assistance{enabled, profile}: Some{U.ConfigureCardAssistance{enabled, profile}}
    case AgentName{} Text{text}: Some{U.NameAgent{text}}
    case AgentInstructions{} Text{text}: Some{U.WriteInstructions{text}}
    case AgentConcurrency{} Count{count}: Some{U.SetConcurrency{count}}
    case ForkCount{} Fork{count, messages}: Some{U.SetFork{count, messages}}
    case ForkMessages{} Fork{count, messages}: Some{U.SetFork{count, messages}}
    case CompactionSummary{} Summary{summary}: Some{U.WriteSummary{summary}}
    case _ _: None{}

def key(field: Field) -> String:
  match field:
    case MessageText{}: "message-text"
    case ProjectName{}: "project-name"
    case WorkspaceDirectories{}: "workspace-directories"
    case WorkspacePrimary{}: "workspace-primary"
    case ContextOrigin{}: "context-origin"
    case SandboxMode{}: "sandbox-mode"
    case NetworkAccess{}: "network-access"
    case ApprovalPolicy{}: "approval-policy"
    case ModelProfile{}: "model-profile"
    case ReasoningEffort{}: "reasoning-effort"
    case DeliveryIntent{}: "delivery-intent"
    case CardTitle{}: "card-title"
    case CardDescription{}: "card-description"
    case CardStage{}: "card-stage"
    case CardPriority{}: "card-priority"
    case CardOwner{}: "card-owner"
    case CardProject{}: "card-project"
    case CardLabels{}: "card-labels"
    case CardAttachments{}: "card-attachments"
    case ContinueCapture{}: "continue-capture"
    case AssistedCapture{}: "assisted-capture"
    case AssistanceProfile{}: "assistance-profile"
    case AgentName{}: "agent-name"
    case AgentInstructions{}: "agent-instructions"
    case AgentConcurrency{}: "agent-concurrency"
    case ForkCount{}: "fork-count"
    case ForkMessages{}: "fork-messages"
    case CompactionSummary{}: "compaction-summary"

def field_present(fields: +List<FieldScene>, +wanted: Field) -> Bool:
  match fields:
    case Nil{}: False{}
    case Con{FieldScene{field, label, entry}, rest}: String.eq(key(field), key(wanted)) || field_present(rest, wanted)

def section_present(sections: +List<Section>, +wanted: Field) -> Bool:
  match sections:
    case Nil{}: False{}
    case Con{Section{title, fields}, rest}: field_present(fields, wanted) || section_present(rest, wanted)

def exposed(body: U.Body, field: Field) -> Bool:
  section_present(structure(body), field)

def context_value(field: Field, config: Context.Configuration, world: M.World()) -> Observed:
  match field:
    case ContextOrigin{}: ContextValue{Context.preview(config, world)}
    case WorkspaceDirectories{}: ContextValue{Context.preview(config, world)}
    case WorkspacePrimary{}: ContextValue{Context.preview(config, world)}
    case SandboxMode{}: ContextValue{Context.preview(config, world)}
    case NetworkAccess{}: ContextValue{Context.preview(config, world)}
    case ApprovalPolicy{}: ContextValue{Context.preview(config, world)}
    case _: NotApplicable{}

def new_task_value(field: Field, message: U.Text, profile: String, reasoning: String, config: Context.Configuration, world: M.World()) -> Observed:
  match field:
    case MessageText{}: TextValue{U.text(message)}
    case ModelProfile{}: ModelValue{profile, reasoning}
    case ReasoningEffort{}: ModelValue{profile, reasoning}
    case other: context_value(other, config, world)

def message_value(field: Field, message: U.Text, delivery: U.Delivery) -> Observed:
  match field:
    case MessageText{}: TextValue{U.text(message)}
    case DeliveryIntent{}: DeliveryValue{delivery}
    case _: NotApplicable{}

def project_value(field: Field, name: String, workspace: D.Workspace) -> Observed:
  match field:
    case ProjectName{}: TextValue{name}
    case WorkspaceDirectories{}: WorkspaceValue{workspace}
    case WorkspacePrimary{}: WorkspaceValue{workspace}
    case _: NotApplicable{}

def card_value(draft: B.Draft, field: Field, assist: Bool, profile: String, keep_open: Bool) -> Observed:
  B.Draft{title, description, stage, priority, owner, project, labels, attachments} = draft
  match field:
    case ContinueCapture{}: ToggleValue{keep_open}
    case CardTitle{}: TextValue{title}
    case CardDescription{}: TextValue{description}
    case CardStage{}: StageValue{stage}
    case CardPriority{}: PriorityValue{priority}
    case CardOwner{}: OwnerValue{owner}
    case CardProject{}: ProjectValue{project}
    case CardLabels{}: TextsValue{labels}
    case CardAttachments{}: AttachmentsValue{attachments}
    case AssistedCapture{}: AssistanceValue{assist, profile}
    case AssistanceProfile{}: AssistanceValue{assist, profile}
    case _: NotApplicable{}

def agent_value(field: Field, name: String, profile: String, reasoning: String, instructions: String, config: Context.Configuration, concurrency: Nat, world: M.World()) -> Observed:
  match field:
    case AgentName{}: TextValue{name}
    case AgentInstructions{}: TextValue{instructions}
    case AgentConcurrency{}: CountValue{concurrency}
    case ModelProfile{}: ModelValue{profile, reasoning}
    case ReasoningEffort{}: ModelValue{profile, reasoning}
    case other: context_value(other, config, world)

def fork_value(field: Field, count: Nat, messages: +List<String>, config: Context.Configuration, world: M.World()) -> Observed:
  match field:
    case ForkCount{}: CountValue{count}
    case ForkMessages{}: TextsValue{messages}
    case other: context_value(other, config, world)

def observed(body: U.Body, field: Field, world: M.World()) -> Observed:
  match body:
    case U.NewTask{message, profile, reasoning, config}: new_task_value(field, message, profile, reasoning, config, world)
    case U.Message{task, message, delivery}: message_value(field, message, delivery)
    case U.Project{id, name, workspace}: project_value(field, name, workspace)
    case U.Card{id, revision, draft, assist, profile, keep_open}: card_value(draft, field, assist, profile, keep_open)
    case U.Agent{id, revision, name, profile, reasoning, instructions, config, concurrency}: agent_value(field, name, profile, reasoning, instructions, config, concurrency, world)
    case U.Fork{task, count, messages, config}: fork_value(field, count, messages, config, world)
    case U.Compact{task, summary}: OptionalTextValue{summary}

def permitted_model_edit(permitted: Bool, profile: String, reasoning: String) -> Maybe<&2, U.Edit>:
  match permitted:
    case True{}: Some{U.ChooseModel{profile, reasoning}}
    case False{}: None{}

def selected_profile_effort(permitted: Bool, previous: String, profile: D.Profile) -> String:
  match permitted:
    case True{}: previous
    case False{}: D.profile_default(profile)

def profile_change(found: Maybe<&2, D.Profile>, +previous: String) -> Maybe<&2, U.Edit>:
  match found:
    case None{}: None{}
    case Some{D.Profile{+key, provider, name, policy, options}}:
      +profile: D.Profile = D.Profile{key, provider, name, policy, options}
      +selected: String = selected_profile_effort(D.profile_permitted(profile, previous), previous, profile)
      permitted_model_edit(D.profile_permitted(profile, selected), key, selected)

def reasoning_change(found: Maybe<&2, D.Profile>, requested: String) -> Maybe<&2, U.Edit>:
  match found:
    case None{}: None{}
    case Some{D.Profile{+key, provider, name, policy, options}}:
      +profile: D.Profile = D.Profile{key, provider, name, policy, options}
      +selected = D.profile_selection(requested, profile)
      permitted_model_edit(D.profile_permitted(profile, selected), key, selected)

def sandbox_field(field: Field, new_mode: D.SandboxMode, new_network: Bool, mode: D.SandboxMode, network: Bool) -> Maybe<&2, U.Edit>:
  match field:
    case SandboxMode{}: Some{U.ConfigureContext{Context.SetSandbox{D.Sandbox{new_mode, network}}}}
    case NetworkAccess{}: Some{U.ConfigureContext{Context.SetSandbox{D.Sandbox{mode, new_network}}}}
    case _: None{}

def update_sandbox(field: Field, requested: D.Sandbox, current: D.Sandbox) -> Maybe<&2, U.Edit>:
  D.Sandbox{new_mode, new_network} = requested
  D.Sandbox{mode, network} = current
  sandbox_field(field, new_mode, new_network, mode, network)

def context_sandbox(preview: Context.Preview, field: Field, requested: D.Sandbox) -> Maybe<&2, U.Edit>:
  match preview:
    case Context.ContextUnavailable{reason}: None{}
    case Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}: update_sandbox(field, requested, Context.unwrap_sandbox(sandbox))

def configured_edit(field: Field, value: Value, profile: String, reasoning: String, config: Context.Configuration, world: M.World()) -> Maybe<&2, U.Edit>:
  match field value:
    case ModelProfile{} Model{+selected, effort}: profile_change(D.find_profile(Commands.configured(Commands.settings(world)), selected), reasoning)
    case ReasoningEffort{} Model{selected, effort}: reasoning_change(D.find_profile(Commands.configured(Commands.settings(world)), profile), effort)
    case SandboxMode{} ContextChange{Context.SetSandbox{sandbox}}: context_sandbox(Context.preview(config, world), SandboxMode{}, sandbox)
    case NetworkAccess{} ContextChange{Context.SetSandbox{sandbox}}: context_sandbox(Context.preview(config, world), NetworkAccess{}, sandbox)
    case other next: edit(other, next)

def card_edit(field: Field, value: Value, assist: Bool, profile: String) -> Maybe<&2, U.Edit>:
  match field value:
    case AssistedCapture{} Assistance{enabled, selected}: Some{U.ConfigureCardAssistance{enabled, profile}}
    case AssistanceProfile{} Assistance{enabled, selected}: Some{U.ConfigureCardAssistance{assist, selected}}
    case other next: edit(other, next)

def fork_edit(field: Field, value: Value, count: Nat, messages: +List<String>, config: Context.Configuration, world: M.World()) -> Maybe<&2, U.Edit>:
  match field value:
    case ForkCount{} Fork{next, text}: Some{U.SetFork{next, messages}}
    case ForkMessages{} Fork{next, text}: Some{U.SetFork{count, text}}
    case other next: configured_edit(other, next, "", "", config, world)

def edit_for(body: U.Body, field: Field, value: Value, world: M.World()) -> Maybe<&2, U.Edit>:
  match body:
    case U.NewTask{message, profile, reasoning, context}: configured_edit(field, value, profile, reasoning, context, world)
    case U.Agent{id, revision, name, profile, reasoning, instructions, context, concurrency}: configured_edit(field, value, profile, reasoning, context, world)
    case U.Card{id, revision, draft, assist, profile, keep_open}: card_edit(field, value, assist, profile)
    case U.Fork{task, count, messages, context}: fork_edit(field, value, count, messages, context, world)
    case _: edit(field, value)

def label(name: String) -> String:
  match name:
    case "command": "Command"
    case "justification": "Reason"
    case other: other
