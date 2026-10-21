From Stdlib Require Import String List Bool NArith.
From Selvedge.Kernel Require Domain.
From Selvedge.Features Require Domain.
From Selvedge.Interaction Require Context.
Import ListNotations.

(** Parameter identities and entry requirements are product declarations.  A
    browser chooses a native control only after receiving their semantic use. *)
Inductive field := WorkName | MessageText | ProjectName | CreateWorktree
| TaskEnvironment | WorkspaceDirectories | WorkspacePrimary | ContextOrigin
| SandboxMode | NetworkAccess | ApprovalPolicy | ApprovalReviewer | ModelProfile
| ReasoningEffort | DeliveryIntent | CardTitle | CardDescription | CardStage
| CardPriority | CardOwner | CardProject | CardLabels | CardAttachments
| ContinueCapture | AssistedCapture | AssistanceProfile | AgentName
| AgentInstructions | AgentConcurrency | ForkCount | ForkMessages
| CompactionSummary | TaskGraphDeclaration | TaskTitlePrompt | AgentTitlePrompt.
Inductive entry := DisplayOnly | SingleLine | Multiline | StructuredText
| Choice | MultipleChoices | PositiveInteger | DirectoryCollection | FileCollection.
Record choice_value := ChoiceValue { choice_value_of : string; choice_label : string }.
Inductive delivery := Send | Steer.
Inductive observed := ToggleValue (enabled : bool) | TextValue (text : string)
| CountValue (count : N) | TextsValue (values : list string)
| WorkspaceValue (workspace : Selvedge.Kernel.Domain.workspace)
| ContextValue (preview : Context.preview) (reviewers : list Selvedge.Kernel.Domain.profile)
| CommittedContextValue (task:N) (settings:Selvedge.Kernel.Domain.task_settings)
    (reviewers:list Selvedge.Kernel.Domain.profile)
| ModelValue (profile reasoning : string) | DeliveryValue (intent : delivery)
| StageValue (stage : Selvedge.Features.Domain.board_stage)
| PriorityValue (priority : Selvedge.Features.Domain.priority)
| OwnerValue (owner : Selvedge.Features.Domain.owner)
| ProjectValue (project : option N)
| AttachmentsValue (files : list Selvedge.Features.Domain.attachment)
| AssistanceValue (enabled : bool) (profile : string)
| OptionalTextValue (text : option string) | NotApplicable.
