import Base
import ../BOARD.bend as B
import ./user-input.bend as U
import ./user-context.bend as Context

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
  AssistedCapture{}
  AssistanceProfile{}
  AgentName{}
  AgentInstructions{}
  AgentConcurrency{}
  ForkCount{}
  ForkMessages{}
  CompactionSummary{}

type Entry is Data:
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

def execution() -> Section:
  Section{"Execution context", [FieldScene{ContextOrigin{}, "Defaults from", Choice{}},
    FieldScene{WorkspaceDirectories{}, "Working directories", DirectoryCollection{}},
    FieldScene{WorkspacePrimary{}, "Primary directory", Choice{}},
    FieldScene{SandboxMode{}, "Filesystem access", Choice{}},
    FieldScene{NetworkAccess{}, "Network access", Choice{}},
    FieldScene{ApprovalPolicy{}, "Approval policy", Choice{}}]}

def model() -> Section:
  Section{"Model", [FieldScene{ModelProfile{}, "Model", Choice{}}, FieldScene{ReasoningEffort{}, "Reasoning effort", Choice{}}]}

def structure(body: U.Body) -> +List<Section>:
  match body:
    case U.NewTask{message, profile, reasoning, context}:
      [Section{"Message", [FieldScene{MessageText{}, "Task", Multiline{}}]}, model(), execution()]
    case U.Message{task, message, delivery}:
      [Section{"Message", [FieldScene{MessageText{}, "Message", Multiline{}}, FieldScene{DeliveryIntent{}, "Send as", Choice{}}]}]
    case U.Project{id, name, workspace}:
      [Section{"Project", [FieldScene{ProjectName{}, "Name", SingleLine{}}]},
       Section{"Default workspace", [FieldScene{WorkspaceDirectories{}, "Working directories", DirectoryCollection{}}, FieldScene{WorkspacePrimary{}, "Primary directory", Choice{}}]}]
    case U.Card{id, revision, draft, assist, profile}:
      [Section{"Work", [FieldScene{CardTitle{}, "Title", SingleLine{}}, FieldScene{CardDescription{}, "Description", Multiline{}}]},
       Section{"Organization", [FieldScene{CardStage{}, "Stage", Choice{}}, FieldScene{CardPriority{}, "Priority", Choice{}},
         FieldScene{CardOwner{}, "Assignee", Choice{}}, FieldScene{CardProject{}, "Project", Choice{}}, FieldScene{CardLabels{}, "Labels", MultipleChoices{}}]},
       Section{"Attachments", [FieldScene{CardAttachments{}, "Files", FileCollection{}}]},
       Section{"Capture assistance", [FieldScene{AssistedCapture{}, "Assist with title and description", Choice{}}, FieldScene{AssistanceProfile{}, "Assistance model", Choice{}}]}]
    case U.Agent{id, revision, name, profile, reasoning, instructions, context, concurrency}:
      [Section{"Agent", [FieldScene{AgentName{}, "Name", SingleLine{}}, FieldScene{AgentInstructions{}, "Instructions", Multiline{}}, FieldScene{AgentConcurrency{}, "Concurrent tasks", PositiveInteger{}}]}, model(), execution()]
    case U.Fork{task, count, messages, context}:
      [Section{"Fork", [FieldScene{ForkCount{}, "Number of tasks", PositiveInteger{}}, FieldScene{ForkMessages{}, "Initial messages", Multiline{}}]}, execution()]
    case U.Compact{task, summary}:
      [Section{"Compaction", [FieldScene{CompactionSummary{}, "Summary override", Multiline{}}]}]

def edit(field: Field, value: Value) -> Maybe<&2, U.Edit>:
  match field value:
    case MessageText{} Text{text}: Some{U.WriteMessage{U.Text{text}}}
    case ProjectName{} Text{text}: Some{U.NameProject{text}}
    case WorkspaceDirectories{} WorkspaceChange{change}: Some{U.EditWorkspace{change}}
    case WorkspacePrimary{} WorkspaceChange{change}: Some{U.EditWorkspace{change}}
    case ContextOrigin{} ContextChange{change}: Some{U.ConfigureContext{change}}
    case SandboxMode{} ContextChange{change}: Some{U.ConfigureContext{change}}
    case NetworkAccess{} ContextChange{change}: Some{U.ConfigureContext{change}}
    case ApprovalPolicy{} ContextChange{change}: Some{U.ConfigureContext{change}}
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
