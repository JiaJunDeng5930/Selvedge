From Stdlib Require Import String List.
From Selvedge.Foundation Require Import Json.
From Selvedge.Adapters Require Import Common EvaluatorPolicy.
Import ListNotations.
Open Scope string_scope.
Definition handlers : list (string * (json -> json)) := [
  ("evaluator.contract",fun _ => success contract);
  ("evaluator.request",request);("evaluator.request_admission",request_admission);
  ("evaluator.decision",decision);("evaluator.retry",retry)].
Definition call operation source := match find (fun entry => String.eqb operation (fst entry)) handlers with
  | Some (_,handler) => handler source | None => err "Unknown evaluator operation" end.
