From Stdlib Require Import String.
From Selvedge.Adapters Require Import Common.
From Selvedge.Host Require Import Resources LocalResources CloudResources WorkspaceRecovery.
Open Scope string_scope.
Definition call (operation : string) (source : json) : json :=
  if String.eqb operation "control.resource.start" then success (CloudResources.start source)
  else if String.eqb operation "control.resource.recover" then success (CloudResources.recover source)
  else if String.eqb operation "control.resource.step" then if is_null (get (get source "state") "local_mode") then match CloudResources.call_step (get source "state") (get source "observation") with
      Some plan=>success plan | None=>type_error "Invalid cloud resource controller observation" end
    else match LocalResources.apply (get source "state") (get source "observation") with
      Some plan=>success plan | None=>type_error "Invalid local resource controller observation" end
  else if String.eqb operation "control.resource.recovery" then success (WorkspaceRecovery.plan (get source "entry") (get source "receipt"))
  else if String.eqb operation "control.resource.receipt" then
    match CloudResources.receipt_state (get source "state") with
    | Some receipt=>success receipt | None=>type_error "Invalid cloud resource receipt state" end
  else if String.eqb operation "control.resource.ssh" then
    match CloudResources.ssh_call source with Some plan=>success plan | None=>type_error "Invalid cloud SSH readiness observation" end
  else if String.eqb operation "control.resource.git_admit" then
    if LocalResources.git_admitted source then success JNull else type_error "Managed worktree canonical root or Git registration does not match"
  else if String.eqb operation "control.resource.classify" then success (LocalResources.local_classification source)
  else if String.eqb operation "control.resource.local" then success (LocalResources.begin source)
  else if String.eqb operation "control.resource.request" then success (Resources.provider_request source)
  else if String.eqb operation "control.resource.provider" then success (Resources.provider source)
  else type_error "Unknown resource control operation".
