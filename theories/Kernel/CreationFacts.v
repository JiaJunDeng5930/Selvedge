From Stdlib Require Import String List.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Schema.
From Selvedge.Kernel Require Import Domain State Configuration ContextTypes Guidance.
Import ListNotations.
Open Scope string_scope.

(** These observations belong to one request to create roots. The admitted
    environment still owns the model and tool catalog and configured text. *)
Record t := Facts {
 observed_project : Guidance.t;
 observed_global_instructions : option ContextTypes.snapshot
}.
Definition fields := [Field "project" KJson; Field "global" (KOptional KJson)].
Definition of_fields (value : Schema.fields fields) : option t :=
 match Guidance.parse (head value) with
 | None => None
 | Some project => match head (tail value) with
   | None => Some (Facts project None)
   | Some raw => option_map (fun global => Facts project (Some global))
       (Configuration.parse_global_instructions raw)
   end
 end.
Definition parse raw := match Schema.decode fields raw with
 | Some value => of_fields value | None => None end.

Definition environment_for (facts : t) (configured : environment) :=
 Environment (environment_profiles configured) (environment_tools configured)
  (environment_max_fork configured) (environment_max_descendants configured)
  (observed_project facts) (environment_plugins configured)
  (environment_instructions configured) (observed_global_instructions facts).
Definition observation_world facts before :=
 with_environment (environment_for facts (world_environment before)) before.

(** The existing birth planners resolve defaults from an immutable world.
    The view changes exactly the observations they use to start a root.
    Publication and scheduling receive the committed environment from before. *)
Definition select (facts : t) (plan : world -> decision) (before : world) : decision :=
 let configured := world_environment before in
 let candidate := plan (observation_world facts before) in
 Decision (with_environment configured (decision_world candidate))
   (decision_reply candidate) (decision_effects candidate).

Theorem select_preserves_committed_environment facts plan before :
 world_environment (decision_world (select facts plan before)) = world_environment before.
Proof.
 unfold select, with_environment.
 destruct (plan _) as [candidate reply effects]. destruct candidate. reflexivity.
Qed.

Theorem a_refused_plan_retains_no_observations facts plan before code reason :
 plan (observation_world facts before) = State.reject code reason (observation_world facts before) ->
 select facts plan before = State.reject code reason before.
Proof.
 intro Refused. unfold select. rewrite Refused.
 destruct before. reflexivity.
Qed.
