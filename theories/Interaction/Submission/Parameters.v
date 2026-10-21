From Stdlib Require Import String Ascii List Bool NArith.
From Selvedge.Foundation Require Import Json Schema.
From Selvedge.Kernel Require WorkspaceBackend Codec.
From Selvedge.Features Require Observation.
From Selvedge.Features Require Domain.
From Selvedge.Interaction Require Import Identity Codec.
From Selvedge.Interaction.Submission Require Import Fields.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition context_fields := [ContextOrigin; WorkspacePrimary; WorkspaceDirectories;
  SandboxMode; NetworkAccess; ApprovalPolicy; ApprovalReviewer].
Definition model_fields := [ModelProfile; ReasoningEffort].
Definition fields e := match e with
| Identity.NewTask _ => [MessageText; TaskEnvironment] ++ model_fields ++ context_fields
| Identity.Message _ => [MessageText; DeliveryIntent]
| Identity.Project _ => [ProjectName; WorkspaceDirectories; WorkspacePrimary; CreateWorktree]
| Identity.Card _ => [CardTitle; CardDescription; CardStage; CardPriority; CardOwner;
    CardProject; CardLabels; CardAttachments; ContinueCapture; AssistedCapture; AssistanceProfile]
| Identity.Agent _ => [AgentName; AgentInstructions; AgentConcurrency] ++ model_fields ++ context_fields
| Identity.Fork _ => [ForkCount; ForkMessages] ++ context_fields
| Identity.Compact _ => [CompactionSummary]
| Identity.TaskGraph _ _ => [TaskGraphDeclaration]
| Identity.WorkName _ => [WorkName]
| Identity.TitlePrompts => [TaskTitlePrompt; AgentTitlePrompt] end.
Definition field_eq_dec : forall a b : field, {a=b}+{a<>b}.
Proof. decide equality. Defined.
Definition live_fields := model_fields++[SandboxMode;NetworkAccess;ApprovalPolicy;ApprovalReviewer].
Definition committed_fields := [ContextOrigin;WorkspaceDirectories;WorkspacePrimary].
Definition subject_fields e:=match e with Identity.Message _=>fields e++live_fields++committed_fields|Identity.Project _=>ContextOrigin::fields e|_=>fields e end.
Definition live_configuration e field:=match e with Identity.Message _=>
 existsb(fun candidate=>if field_eq_dec candidate field then true else false)live_fields|_=>false end.
Definition editable e field:=match e with Identity.Message _=>
 negb(existsb(fun candidate=>if field_eq_dec candidate field then true else false)committed_fields)
|Identity.Project _=>if field_eq_dec field ContextOrigin then false else true|_=>true end.
Definition name field := match field with
| WorkName | ProjectName | AgentName => "name" | MessageText => "message"
| CreateWorktree => "create_worktree" | TaskEnvironment => "task_environment"
| WorkspaceDirectories => "roots" | WorkspacePrimary => "primary_root" | ContextOrigin => "project_id"
| SandboxMode => "sandbox" | NetworkAccess => "network_access" | ApprovalPolicy => "approval"
| ApprovalReviewer => "reviewer_profile" | ModelProfile => "profile" | ReasoningEffort => "reasoning"
| DeliveryIntent => "delivery" | CardTitle => "title" | CardDescription => "description"
| CardStage => "status" | CardPriority => "priority" | CardOwner => "assignee" | CardProject => "project"
| CardLabels => "labels" | CardAttachments => "attachments" | ContinueCapture => "keep_open"
| AssistedCapture => "assisted" | AssistanceProfile => "draft_profile" | AgentInstructions => "instructions"
| AgentConcurrency => "concurrency" | ForkCount => "child_count" | ForkMessages => "messages"
| CompactionSummary => "summary" | TaskGraphDeclaration => "declaration"
| TaskTitlePrompt => "task_prompt" | AgentTitlePrompt => "agent_prompt" end.
Definition label field := match field with
| WorkName | ProjectName | AgentName => "Name" | MessageText => "Message"
| CreateWorktree => "Create worktree for new tasks" | TaskEnvironment => "Task environment"
| WorkspaceDirectories => "Working directories" | WorkspacePrimary => "Primary directory"
| ContextOrigin => "Project" | SandboxMode => "Filesystem access" | NetworkAccess => "Network access"
| ApprovalPolicy => "Execution policy" | ApprovalReviewer => "Reviewing model" | ModelProfile => "Model"
| ReasoningEffort => "Reasoning effort" | DeliveryIntent => "Send as" | CardTitle => "Title"
| CardDescription => "Description" | CardStage => "Stage" | CardPriority => "Priority"
| CardOwner => "Assignee" | CardProject => "Project" | CardLabels => "Labels"
| CardAttachments => "Attachments" | ContinueCapture => "Create another after saving"
| AssistedCapture => "Assist with title and description" | AssistanceProfile => "Assistance model"
| AgentInstructions => "Instructions" | AgentConcurrency => "Concurrent tasks"
| ForkCount => "Number of tasks" | ForkMessages => "Initial messages" | CompactionSummary => "Summary override"
| TaskGraphDeclaration => "Declaration" | TaskTitlePrompt => "Task 看板标题提示词"
| AgentTitlePrompt => "Agent 会话标题提示词" end.
Definition entry_for field := match field with
| MessageText | CardDescription | AgentInstructions | ForkMessages | CompactionSummary
| TaskTitlePrompt | AgentTitlePrompt | CardLabels => Fields.Multiline
| WorkspaceDirectories => Fields.DirectoryCollection | CardAttachments => Fields.FileCollection
| TaskGraphDeclaration => Fields.StructuredText | ForkCount | AgentConcurrency => Fields.PositiveInteger
| WorkspacePrimary | ContextOrigin | TaskEnvironment | SandboxMode | NetworkAccess | ApprovalPolicy | ApprovalReviewer
| ModelProfile | ReasoningEffort | DeliveryIntent | CardStage | CardPriority | CardOwner | CardProject
| CreateWorktree | ContinueCapture | AssistedCapture | AssistanceProfile => Fields.Choice
| _ => Fields.SingleLine end.
Definition inheritable e := match e with
| Identity.NewTask _ | Identity.Agent _ | Identity.Fork _ => true | _ => false end.
Definition inherited_kind e kind := if inheritable e then KOptional kind else kind.
Definition managed_workspace_names := match WorkspaceBackend.declaration with
| KEnum first rest => first :: rest | _ => [] end.
Definition kind e field := match field with
| CreateWorktree | ContinueCapture | AssistedCapture => KBool
| TaskEnvironment => KEnum "current" managed_workspace_names
| WorkspaceDirectories => inherited_kind e (KArray KText)
| WorkspacePrimary | ContextOrigin => match field with
  | ContextOrigin => KOptional KNatural | _ => KOptional KText end
| SandboxMode => inherited_kind e (KEnum "workspace-write" ["read-only"])
| NetworkAccess => inherited_kind e KBool
| ApprovalPolicy => inherited_kind e (KEnum "ask-for-approval" ["full-access"; "approval-for-me"])
| ApprovalReviewer => KOptional KText
| DeliveryIntent => KEnum "send" ["steer"]
| CardStage => KEnum (Domain.stage_name Domain.Backlog) (map Domain.stage_name (tl Domain.stages))
| CardPriority => KEnum (Domain.priority_name Domain.NoPriority) (map Domain.priority_name (tl Domain.priorities))
| CardLabels | ForkMessages => KArray KText
| CardAttachments => KArray KJson
| ForkCount | AgentConcurrency => KNatural
| CompactionSummary => KOptional KText
| _ => KText end.
Definition specification e field := Schema.Field (name field) (kind e field).
Definition find_field e key := find (fun field => String.eqb key (name field)) (fields e).


Definition context_native (field:Fields.field) (source:Context.origin) (project:option N)
    (workspace:Context.workspace_value) (sandbox:Context.sandbox_value) (approval:Context.approval_value) :=
  match field with
  | ContextOrigin => Identity.optional_id project
  | WorkspaceDirectories => match workspace with
      | Context.InheritedWorkspace _ => JNull
      | Context.EnteredWorkspace value => JArray (map JString (Selvedge.Kernel.Domain.workspace_roots value)) end
  | WorkspacePrimary => match workspace with
      | Context.InheritedWorkspace _ => JNull
      | Context.EnteredWorkspace value => match Selvedge.Kernel.Domain.workspace_primary value with
        | None => JNull | Some path => JString path end end
  | SandboxMode | NetworkAccess => match sandbox with
      | Context.InheritedSandbox _ => JNull
      | Context.ChosenSandbox value => match field with
        | NetworkAccess => JBool (Selvedge.Kernel.Domain.sandbox_network value)
        | _ => JString (match Selvedge.Kernel.Domain.sandbox_access value with
          | Selvedge.Kernel.Domain.ReadOnly => "read-only"
          | Selvedge.Kernel.Domain.WorkspaceWrite => "workspace-write" end) end end
  | ApprovalPolicy | ApprovalReviewer => match approval with
      | Context.InheritedApproval _ => JNull
      | Context.ChosenApproval value => match field,value with
        | ApprovalReviewer,Context.AutomaticReview key => JString key
        | ApprovalReviewer,_ => JNull
        | _,Context.Ask => JString "ask-for-approval"
        | _,Context.Unrestricted => JString "full-access"
        | _,Context.AutomaticReview _ => JString "approval-for-me" end end
  | _ => JNull end.
Definition committed_native field (settings:Selvedge.Kernel.Domain.task_settings):json:=match field with
|ContextOrigin=>Identity.optional_id(Selvedge.Kernel.Domain.settings_project settings)
|WorkspaceDirectories=>JArray(map JString(Selvedge.Kernel.Domain.workspace_roots(Selvedge.Kernel.Domain.settings_workspace settings)))
|WorkspacePrimary=>match Selvedge.Kernel.Domain.workspace_primary(Selvedge.Kernel.Domain.settings_workspace settings)with None=>JNull|Some path=>JString path end
|SandboxMode=>JString(match Selvedge.Kernel.Domain.sandbox_access(Selvedge.Kernel.Domain.settings_sandbox settings)with Selvedge.Kernel.Domain.ReadOnly=>"read-only"|_=>"workspace-write"end)
|NetworkAccess=>JBool(Selvedge.Kernel.Domain.sandbox_network(Selvedge.Kernel.Domain.settings_sandbox settings))
|ApprovalPolicy=>JString(match Selvedge.Kernel.Domain.settings_approval settings with Selvedge.Kernel.Domain.FullAccess=>"full-access"|Selvedge.Kernel.Domain.AskForApproval=>"ask-for-approval"|_=>"approval-for-me"end)
|ApprovalReviewer=>match Selvedge.Kernel.Domain.settings_approval settings with Selvedge.Kernel.Domain.ReviewWith profile=>JString(Selvedge.Kernel.Domain.profile_key profile)|_=>JNull end
|_=>JNull end.
(** The native input value is a protocol value; readable identity labels are
    supplied by the experience observation, never by displaying this encoding. *)
Definition native_value (field:Fields.field) (value:Fields.observed) : json :=
 match value with
 | ToggleValue enabled => JBool enabled | TextValue text => JString text
 | CountValue count => number count | TextsValue values => match field with
   | CardLabels => JString(String.concat ", " values)
   | ForkMessages => JString(String.concat (String (ascii_of_nat 10) EmptyString) values)
   | _ => JArray(map JString values)end
 | WorkspaceValue workspace => match field with
   | WorkspacePrimary => match Selvedge.Kernel.Domain.workspace_primary workspace with Some path=>JString path|None=>JNull end
   | _ => JArray (map JString (Selvedge.Kernel.Domain.workspace_roots workspace)) end
 | ContextValue preview _ => match preview with
   | Context.ContextUnavailable _ => JNull
   | Context.ProspectiveContext source project workspace sandbox approval _ =>
     context_native field source project workspace sandbox approval end
 | CommittedContextValue _ settings _ => committed_native field settings
 | ModelValue profile reasoning => JString (match field with ReasoningEffort=>reasoning|_=>profile end)
 | DeliveryValue intent => JString (match intent with Send=>"send"|Steer=>"steer" end)
 | StageValue stage => JString (Domain.stage_name stage)
 | PriorityValue priority => JString (Domain.priority_name priority)
 | OwnerValue owner => JString (Domain.owner_name owner)
 | ProjectValue project => Identity.optional_id project
 | AttachmentsValue files => JArray (map Selvedge.Features.Observation.attachment_json files)
 | AssistanceValue enabled profile => match field with AssistedCapture=>JBool enabled|_=>JString profile end
 | OptionalTextValue text => match text with Some value=>JString value|None=>JNull end
 | NotApplicable => JNull end.

Definition space character := Nat.eqb(nat_of_ascii character)32 || Nat.eqb(nat_of_ascii character)9 || Nat.eqb(nat_of_ascii character)13.
Fixpoint trim_start text := match text with EmptyString=>text|String character rest=>if space character then trim_start rest else text end.
Fixpoint trim_end text := match text with EmptyString=>text|String character rest=>let tail:=trim_end rest in if space character && String.eqb tail "" then "" else String character tail end.
Definition trim text := trim_end(trim_start text).
Fixpoint split_text (comma:bool) text :list string := match text with
|EmptyString=>[""]
|String character rest=>let tail:=split_text comma rest in
 if Nat.eqb(nat_of_ascii character)10 || (comma && Nat.eqb(nat_of_ascii character)44)
 then ""::tail else match tail with []=>[String character ""]|head::tail=>String character head::tail end end.
Definition edit_value field incoming := match field,incoming with
|CardLabels,JString text=>JArray(map JString(filter(fun value=>negb(String.eqb value ""))(map trim(split_text true text))))
|ForkMessages,JString text=>JArray(map JString(split_text false text))
|_,value=>value end.
Definition native_input (description:Schema.kind)(incoming:json):json:=match description,incoming with
|KNatural,JString text=>JNumber text
|KOptional KNatural,JString text=>if String.eqb text ""then JNull else JNumber text
|KBool,JString "true"=>JBool true|KBool,JString "false"=>JBool false
|KOptional KBool,JString ""=>JNull
|KOptional KBool,JString "true"=>JBool true|KOptional KBool,JString "false"=>JBool false
|KOptional KText,JString ""=>JNull
|_,value=>value end.
Definition choice_input(e:Identity.editor)(field:Fields.field)(choice:Fields.choice_value):json:=
 native_input(kind e field)(JString(Fields.choice_value_of choice)).
Definition decode_input e field incoming := Schema.decode_value(kind e field)(native_input(kind e field)(edit_value field incoming)).
Definition native_checked (field:Fields.field)(value:Fields.observed):option bool:=match value with
|ToggleValue enabled=>Some enabled|AssistanceValue enabled _=>Some enabled
|ContextValue(Context.ProspectiveContext _ _ _ sandbox _ _)_=>match field with
 |NetworkAccess=>Some(Selvedge.Kernel.Domain.sandbox_network(match sandbox with Context.InheritedSandbox value|Context.ChosenSandbox value=>value end))|_=>None end
|CommittedContextValue _ settings _=>match field with
 |NetworkAccess=>Some(Selvedge.Kernel.Domain.sandbox_network(Selvedge.Kernel.Domain.settings_sandbox settings))|_=>None end
|_=>None end.

Definition find_subject_field e key:=find(fun field=>String.eqb key(name field))(subject_fields e).
