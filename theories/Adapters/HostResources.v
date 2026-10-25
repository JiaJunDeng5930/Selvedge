From Stdlib Require Import String.
From Selvedge.Adapters Require Import Common.
From Selvedge.Host Require Import Resources.
Open Scope string_scope.
Definition call (operation : string) (source : json) : json :=
  if String.eqb operation "control.resource.start" then success (Resources.start source)
  else if String.eqb operation "control.resource.recover" then success (Resources.recover source)
  else if String.eqb operation "control.resource.step" then success (Resources.step (get source "state") (get source "observation"))
  else if String.eqb operation "control.resource.local" then success (Resources.local source)
  else if String.eqb operation "control.resource.request" then success (Resources.provider_request source)
  else if String.eqb operation "control.resource.provider" then success (Resources.provider source)
  else type_error "Unknown resource control operation".
