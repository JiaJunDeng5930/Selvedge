From Stdlib Require Import String List Bool NArith.
From Selvedge.Kernel Require Domain.
Inductive origin := EnvironmentDefaults | ProjectDefaults (project : N)
| ParentTask (task : N) | ProjectForParent (task project : N).
Inductive approval_choice := Ask | Unrestricted | AutomaticReview (profile : string).
Record configuration := Configuration {
  context_origin : origin;
  workspace_override : option Domain.workspace;
  sandbox_override : option Domain.sandbox;
  approval_override : option approval_choice
}.
Inductive workspace_value := InheritedWorkspace (value : Domain.workspace)
| EnteredWorkspace (value : Domain.workspace).
Inductive sandbox_value := InheritedSandbox (value : Domain.sandbox)
| ChosenSandbox (value : Domain.sandbox).
Inductive approval_value := InheritedApproval (value : Domain.approval_policy)
| ChosenApproval (value : approval_choice).
Inductive guidance_preview := InheritedGuidance (guidance : Selvedge.Foundation.Json.json)
| AwaitingDirectoryGuidance
| ObservedDirectoryGuidance (guidance : Selvedge.Foundation.Json.json).
Inductive preview := ContextUnavailable (reason : string)
| ProspectiveContext (source : origin) (project : option N)
    (workspace : workspace_value) (sandbox : sandbox_value)
    (approval : approval_value) (guidance : guidance_preview).
Definition initial := Configuration EnvironmentDefaults None None None.
