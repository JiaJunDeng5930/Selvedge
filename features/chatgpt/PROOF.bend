import Base
import ../../bendlib/categories.bend as Categories
import ../../bendlib/json.bend as J
import ./MODEL.bend as G
import ../../harness/features/MODEL.bend as F
import ../../harness/MODEL.bend as M
import ../../bendlib/component.bend as C
import ../../harness/DOMAIN.bend as D
import ./PROGRAM.bend as Actual
import ./SPEC.bend as Spec
import ./STATE.bend as State
import ./CONTRACT.bend as Boundary
import ../../bendlib/association-map.bend as Finite
import ../board/MODEL.bend as Board

def refinement(+change: G.Change, +state: G.State) ->
  {Actual.realize_calculation(change, state) == Spec.meaning(change, state) : C.Decision<G.State, G.Effect>}:
  match change state:
    case G.SetGrants{entries} G.State{grants, jobs, next}: {==}
    case G.Start{id, job} G.State{grants, jobs, next}: {==}
    case G.Reuse{id, job} G.State{grants, jobs, next}: {==}
    case G.Interrupt{id, job} G.State{grants, jobs, next}: {==}
    case G.Remove{id} G.State{grants, jobs, next}: {==}
    case G.Complete{id, job, value, error} G.State{grants, jobs, next}: {==}

def assembled(+change: G.Change, +world: M.World()) ->
  {State.embed(Actual.realize_calculation(change, State.registry(world)), world) ==
   State.embed(Spec.meaning(change, State.registry(world)), world) : M.Decision()}:
  Equal.cong(C.Decision<G.State, G.Effect>, M.Decision(), decision => State.embed(decision, world),
    Actual.realize_calculation(change, State.registry(world)), Spec.meaning(change, State.registry(world)), refinement(change, State.registry(world)))

def written(+value: G.State, +world: M.World()) ->
  {State.registry(State.store(value, world)) == value : G.State}:
  match world:
    case C.Frame{core, C.Frame{board, C.Frame{previous, rest}}}: {==}

def core_frame(+value: G.State, +world: M.World()) ->
  {C.local(D.State, F.State(), State.store(value, world)) == C.local(D.State, F.State(), world) : D.State}:
  match world:
    case C.Frame{core, C.Frame{board, C.Frame{previous, rest}}}: {==}

def board_frame(+value: G.State, +world: M.World()) ->
  {F.board(C.rest(D.State, F.State(), State.store(value, world))) == F.board(C.rest(D.State, F.State(), world)) : Board.State}:
  match world:
    case C.Frame{core, C.Frame{board, C.Frame{previous, rest}}}: {==}

def removed(+id: Nat, +state: G.State) ->
  {Finite.find(~G.Job, G.jobs(Actual.result_state(Actual.realize_calculation(G.Remove{id}, state))), id) == None{} : Maybe<&2, G.Job>}:
  match state:
    case G.State{grants, jobs, next}: Finite.removal_absence(~G.Job, jobs, id)

def rest_frame(+value: G.State, +world: M.World()) ->
  {F.rest(C.rest(D.State, F.State(), State.store(value, world))) == F.rest(C.rest(D.State, F.State(), world)) : F.Rest()}:
  match world:
    case C.Frame{core, C.Frame{board, C.Frame{previous, rest}}}: {==}

def board_preserves(+value: Board.State, +features: F.State()) ->
  {F.chatgpt(F.with_board(value, features)) == F.chatgpt(features) : G.State}:
  match features:
    case C.Frame{board, modules}: {==}

def ownership(+connection: Nat, +project: Nat, +job: G.Job) ->
  {G.owned(connection, project, job) ==
   (Nat.is_eq(connection, G.job_connection(job)) && Nat.is_eq(project, G.job_project(job))) : Bool}:
  match job:
    case G.Job{owner, target, request, arguments, workspace, sandbox, outcome}: {==}

def restarted(+job: G.Job, running: {G.outcome(job) == G.Running{} : G.Outcome}) ->
  {G.outcome(G.recover_job(job)) ==
   G.Interrupted{"Service restarted; execution may have happened and will not be replayed"} : G.Outcome}:
  G.Job{connection, project, request, arguments, workspace, sandbox, outcome} = job
  Equal.cong(G.Outcome, G.Outcome,
    value => G.outcome(G.recovered(G.pending(value), G.Job{connection, project, request, arguments, workspace, sandbox, outcome})),
    outcome, G.Running{}, running)

def command_calculation(construction: Categories.Construction<G.CommandRequest, G.Resolution>) -> C.Decision<G.State, G.Effect>:
  Categories.Construction{G.CommandRequest{command, +state, projects}, resolution} = construction
  Actual.resolution_calculation(G.resolve(command, state, projects), state)

def command_equation(member: G.ConstructedCommand()) ->
  {Actual.realize(member) ==
   command_calculation(Categories.value(Categories.Construction<G.CommandRequest, G.Resolution>,
     Categories.constructed_by(G.CommandRequest, G.Resolution, G.request_resolution), member)) : C.Decision<G.State, G.Effect>}:
  Categories.Membership{Categories.Construction{G.CommandRequest{command, +state, projects}, +resolution}, evidence} = member
  Equal.cong(G.Resolution, C.Decision<G.State, G.Effect>, value => Actual.resolution_calculation(value, state),
    resolution, G.resolve(command, state, projects), evidence)

def constructed_command_equation(+command: G.Command, +state: G.State, +projects: D.Projects) ->
  {Actual.realize(G.construct_command(command, state, projects)) ==
   Actual.resolution_calculation(G.resolve(command, state, projects), state) : C.Decision<G.State, G.Effect>}:
  command_equation(G.construct_command(command, state, projects))

def completion_calculation(construction: Categories.Construction<G.CompletionRequest, Maybe<&2, G.Change>>) -> Maybe<&2, C.Decision<G.State, G.Effect>>:
  Categories.Construction{G.CompletionRequest{+id, value, error, +state}, change} = construction
  Actual.completion_calculation(G.settle(Finite.find(~G.Job, G.jobs(state), id), id, value, error), state)

def completion_equation(member: G.ConstructedCompletion()) ->
  {Actual.realize_completion(member) ==
   completion_calculation(Categories.value(Categories.Construction<G.CompletionRequest, Maybe<&2, G.Change>>,
     Categories.constructed_by(G.CompletionRequest, Maybe<&2, G.Change>, G.completion_resolution), member)) : Maybe<&2, C.Decision<G.State, G.Effect>>}:
  Categories.Membership{Categories.Construction{G.CompletionRequest{+id, value, error, +state}, +change}, evidence} = member
  Equal.cong(Maybe<&2, G.Change>, Maybe<&2, C.Decision<G.State, G.Effect>>,
    value => Actual.completion_calculation(value, state), change,
    G.settle(Finite.find(~G.Job, G.jobs(state), id), id, value, error), evidence)

def constructed_completion_equation(+id: Nat, +value: J.Json, +error: Bool, +state: G.State) ->
  {Actual.realize_completion(G.construct_completion(id, value, error, state)) ==
   Actual.completion_calculation(G.settle(Finite.find(~G.Job, G.jobs(state), id), id, value, error), state) : Maybe<&2, C.Decision<G.State, G.Effect>>}:
  completion_equation(G.construct_completion(id, value, error, state))


# NOTE: The quoted map closure exports removal absence, but no inserted-head lookup.
# This bridge is tied to the actual ChatGPT update and read operations.
def cancel_key_same(+id: Nat) -> {Nat.is_eq(id, id) == True{} : Bool}:
  match id:
    case 0n: {==}
    case 1n+previous: cancel_key_same(previous)

def cancel_put_lookup(+id: Nat, +job: G.Job, +state: G.State, next: Nat) ->
  {Finite.find(~G.Job, G.jobs(Actual.put(id, job, state, next)), id) == Some{job} : Maybe<&2, G.Job>}:
  G.State{grants, jobs, previous} = state
  backwards = Equal.sym(Bool, Nat.is_eq(id, id), True{}, cancel_key_same(id))
  %backwards : {Finite.choose(~G.Job, _, job, Finite.find(~G.Job, Finite.remove(~G.Job, jobs, id), id)) == Some{job} : Maybe<&2, G.Job>}
  {==}

# NOTE: These two calculations eliminate checked admission without capturing
# its dependent evidence in a congruence function.
def owner_bool_calculation(accepted: Bool, connection: Nat, project: Nat, id: Nat, job: G.Job) -> G.Resolution:
  match accepted:
    case True{}: G.change_job(False{}, id, job)
    case False{}: G.Refuse{"operation_not_found", "No retained operation belongs to that project and connection"}

def owner_bool_checked(+accepted: Bool, +connection: Nat, +project: Nat, +id: Nat, +job: G.Job,
  observed: {G.owned(connection, project, job) == accepted : Bool}) ->
  {G.owner_admission(connection, project, id, False{},
     Categories.admit_checked(G.Job, candidate => G.owned(connection, project, candidate), job, accepted, observed)) ==
   owner_bool_calculation(accepted, connection, project, id, job) : G.Resolution}:
  match accepted:
    case True{}: {==}
    case False{}: {==}

def authority_bool_calculation(accepted: Bool, +connection: Nat, +project: Nat, +id: Nat, state: G.State) -> G.Resolution:
  match accepted:
    case True{}: G.found_job(Finite.find(~G.Job, G.jobs(state), id), connection, project, id, False{})
    case False{}: G.Refuse{"project_forbidden", "This connection has no grant for that project"}

def authority_bool_checked(+accepted: Bool, +connection: Nat, +project: Nat, +id: Nat, +state: G.State, +grant: G.Grant,
  observed: {G.project_grant_allowed(project, grant) == accepted : Bool}) ->
  {G.edit_authorized(connection, project,
     Categories.admit_checked(G.Grant, candidate => G.project_grant_allowed(project, candidate), grant, accepted, observed),
     id, False{}, state) == authority_bool_calculation(accepted, connection, project, id, state) : G.Resolution}:
  match accepted:
    case True{}: {==}
    case False{}: {==}

def owner_bool_actual(+connection: Nat, +project: Nat, +id: Nat, +job: G.Job) ->
  {G.owner_admission(connection, project, id, False{},
     Categories.admit(G.Job, candidate => G.owned(connection, project, candidate), job)) ==
   owner_bool_calculation(G.owned(connection, project, job), connection, project, id, job) : G.Resolution}:
  owner_bool_checked(G.owned(connection, project, job), connection, project, id, job, {==})

def authority_bool_actual(+connection: Nat, +project: Nat, +id: Nat, +state: G.State, +grant: G.Grant) ->
  {G.edit_authorized(connection, project,
     Categories.admit(G.Grant, candidate => G.project_grant_allowed(project, candidate), grant), id, False{}, state) ==
   authority_bool_calculation(G.project_grant_allowed(project, grant), connection, project, id, state) : G.Resolution}:
  authority_bool_checked(G.project_grant_allowed(project, grant), connection, project, id, state, grant, {==})

def authority_raw_calculation(found: Maybe<&2, G.Grant>, +connection: Nat, +project: Nat, +id: Nat, +state: G.State) -> G.Resolution:
  match found:
    case None{}: G.Refuse{"project_forbidden", "This connection has no grant for that project"}
    case Some{grant}: authority_bool_calculation(G.project_grant_allowed(project, grant), connection, project, id, state)

def authority_raw_actual(+found: Maybe<&2, G.Grant>, +connection: Nat, +project: Nat, +id: Nat, +state: G.State) ->
  {G.edit_authorized(connection, project, G.authorize(found, project), id, False{}, state) ==
   authority_raw_calculation(found, connection, project, id, state) : G.Resolution}:
  match found:
    case None{}: {==}
    case Some{grant}: authority_bool_actual(connection, project, id, state, grant)

# NOTE: Cancel only refuses, reuses, or interrupts; none of these decisions writes grants.
def cancel_owner_grants_frame(+accepted: Bool, +connection: Nat, +project: Nat, +id: Nat, +job: G.Job, +state: G.State) ->
  {G.grants(Actual.result_state(Actual.resolution_calculation(
     owner_bool_calculation(accepted, connection, project, id, job), state))) == G.grants(state) : +List<Finite.Entry(G.Grant)>}:
  match accepted job state:
    case False{} job G.State{grants, jobs, next}: {==}
    case True{} G.Job{owner, target, request, arguments, workspace, sandbox, G.Running{}} G.State{grants, jobs, next}: {==}
    case True{} G.Job{owner, target, request, arguments, workspace, sandbox, G.Finished{value, error}} G.State{grants, jobs, next}: {==}
    case True{} G.Job{owner, target, request, arguments, workspace, sandbox, G.Interrupted{reason}} G.State{grants, jobs, next}: {==}

def cancel_found_grants_frame(+found: Maybe<&2, G.Job>, +connection: Nat, +project: Nat, +id: Nat, +state: G.State) ->
  {G.grants(Actual.result_state(Actual.resolution_calculation(
     G.found_job(found, connection, project, id, False{}), state))) == G.grants(state) : +List<Finite.Entry(G.Grant)>}:
  match found:
    case None{}: {==}
    case Some{+job}:
      Equal.trans(+List<Finite.Entry(G.Grant)>,
        G.grants(Actual.result_state(Actual.resolution_calculation(G.found_job(Some{job}, connection, project, id, False{}), state))),
        G.grants(Actual.result_state(Actual.resolution_calculation(owner_bool_calculation(G.owned(connection, project, job), connection, project, id, job), state))),
        G.grants(state),
        Equal.cong(G.Resolution, +List<Finite.Entry(G.Grant)>,
          resolution => G.grants(Actual.result_state(Actual.resolution_calculation(resolution, state))),
          G.found_job(Some{job}, connection, project, id, False{}),
          owner_bool_calculation(G.owned(connection, project, job), connection, project, id, job),
          owner_bool_actual(connection, project, id, job)),
        cancel_owner_grants_frame(G.owned(connection, project, job), connection, project, id, job, state))

def cancel_authority_grants_frame(+accepted: Bool, +connection: Nat, +project: Nat, +id: Nat, +state: G.State) ->
  {G.grants(Actual.result_state(Actual.resolution_calculation(
     authority_bool_calculation(accepted, connection, project, id, state), state))) == G.grants(state) : +List<Finite.Entry(G.Grant)>}:
  match accepted:
    case False{}: {==}
    case True{}: cancel_found_grants_frame(Finite.find(~G.Job, G.jobs(state), id), connection, project, id, state)

def cancel_raw_grants_frame(+found: Maybe<&2, G.Grant>, +connection: Nat, +project: Nat, +id: Nat, +state: G.State) ->
  {G.grants(Actual.result_state(Actual.resolution_calculation(
     authority_raw_calculation(found, connection, project, id, state), state))) == G.grants(state) : +List<Finite.Entry(G.Grant)>}:
  match found:
    case None{}: {==}
    case Some{grant}: cancel_authority_grants_frame(G.project_grant_allowed(project, grant), connection, project, id, state)

def cancel_raw_grant_lookup_frame(+found: Maybe<&2, G.Grant>, +connection: Nat, +project: Nat, +id: Nat, +state: G.State) ->
  {Finite.find(~G.Grant, G.grants(Actual.result_state(Actual.resolution_calculation(
     authority_raw_calculation(found, connection, project, id, state), state))), connection) ==
   Finite.find(~G.Grant, G.grants(state), connection) : Maybe<&2, G.Grant>}:
  Equal.cong(+List<Finite.Entry(G.Grant)>, Maybe<&2, G.Grant>,
    grants => Finite.find(~G.Grant, grants, connection),
    G.grants(Actual.result_state(Actual.resolution_calculation(authority_raw_calculation(found, connection, project, id, state), state))),
    G.grants(state), cancel_raw_grants_frame(found, connection, project, id, state))


# NOTE: Rewriting the equality proposition moves both its result and retained
# first-state observation with one affine lookup witness.
def cancel_joint_observation(decision: C.Decision<G.State, G.Effect>) -> (G.State & +List<G.Effect>):
  C.Decision{state, reply, effects} = decision
  (state, effects)

def cancel_raw_first(+found: Maybe<&2, G.Grant>, connection: Nat, project: Nat, id: Nat, +state: G.State) -> C.Decision<G.State, G.Effect>:
  Actual.resolution_calculation(authority_raw_calculation(found, connection, project, id, state), state)

def cancel_joint_goal(+found: Maybe<&2, G.Grant>, +connection: Nat, +project: Nat, +id: Nat, +state: G.State) -> Type:
  {cancel_joint_observation(Actual.resolution_calculation(
     authority_raw_calculation(found, connection, project, id,
       Actual.result_state(cancel_raw_first(found, connection, project, id, state))),
     Actual.result_state(cancel_raw_first(found, connection, project, id, state)))) ==
   (Actual.result_state(cancel_raw_first(found, connection, project, id, state)), Nil{}) : (G.State & +List<G.Effect>)}

def cancel_joint_transport(+found: Maybe<&2, G.Grant>, +connection: Nat, +project: Nat, +id: Nat, +state: G.State,
  observed: {Finite.find(~G.Grant, G.grants(state), connection) == found : Maybe<&2, G.Grant>},
  selected: cancel_joint_goal(found, connection, project, id, state)) ->
  cancel_joint_goal(Finite.find(~G.Grant, G.grants(state), connection), connection, project, id, state):
  %Equal.sym(Maybe<&2, G.Grant>, Finite.find(~G.Grant, G.grants(state), connection), found, observed) :
    cancel_joint_goal(_, connection, project, id, state)
  selected

# NOTE: The untouched branches retain the original lookup. The observed job is
# independent of that lookup until the diagonal observation is transported.
def cancel_next_outcome(outcome: G.Outcome, original_lookup: Maybe<&2, G.Job>, job: G.Job) -> Maybe<&2, G.Job>:
  match outcome:
    case G.Running{}: Some{G.with_outcome(G.Interrupted{"Cancellation requested; physical changes are not undone"}, job)}
    case G.Finished{value, error}: original_lookup
    case G.Interrupted{reason}: original_lookup

def cancel_next_owner(accepted: Bool, original_lookup: Maybe<&2, G.Job>, +job: G.Job) -> Maybe<&2, G.Job>:
  match accepted:
    case False{}: original_lookup
    case True{}: cancel_next_outcome(G.outcome(job), original_lookup, job)

def cancel_next_lookup(found: Maybe<&2, G.Job>, original_lookup: Maybe<&2, G.Job>, +connection: Nat, +project: Nat, id: Nat) -> Maybe<&2, G.Job>:
  match found:
    case None{}: original_lookup
    case Some{+job}: cancel_next_owner(G.owned(connection, project, job), original_lookup, job)

def cancel_owner_lookup(+accepted: Bool, +connection: Nat, +project: Nat, +id: Nat, +job: G.Job, +state: G.State) ->
  {Finite.find(~G.Job, G.jobs(Actual.result_state(Actual.resolution_calculation(
     owner_bool_calculation(accepted, connection, project, id, job), state))), id) ==
   cancel_next_owner(accepted, Finite.find(~G.Job, G.jobs(state), id), job) : Maybe<&2, G.Job>}:
  match accepted:
    case False{}: {==}
    case True{}:
      G.Job{owner, target, request, arguments, workspace, sandbox, outcome} = job
      match outcome:
        case G.Running{}:
          cancel_put_lookup(id,
            G.with_outcome(G.Interrupted{"Cancellation requested; physical changes are not undone"},
              G.Job{owner, target, request, arguments, workspace, sandbox, G.Running{}}), state, G.next(state))
        case G.Finished{value, error}: {==}
        case G.Interrupted{reason}: {==}

def cancel_next_lookup_actual(+found: Maybe<&2, G.Job>, +connection: Nat, +project: Nat, +id: Nat, +state: G.State) ->
  {Finite.find(~G.Job, G.jobs(Actual.result_state(Actual.resolution_calculation(
     G.found_job(found, connection, project, id, False{}), state))), id) ==
   cancel_next_lookup(found, Finite.find(~G.Job, G.jobs(state), id), connection, project, id) : Maybe<&2, G.Job>}:
  match found:
    case None{}: {==}
    case Some{+job}:
      Equal.trans(Maybe<&2, G.Job>,
        Finite.find(~G.Job, G.jobs(Actual.result_state(Actual.resolution_calculation(
          G.found_job(Some{job}, connection, project, id, False{}), state))), id),
        Finite.find(~G.Job, G.jobs(Actual.result_state(Actual.resolution_calculation(
          owner_bool_calculation(G.owned(connection, project, job), connection, project, id, job), state))), id),
        cancel_next_owner(G.owned(connection, project, job), Finite.find(~G.Job, G.jobs(state), id), job),
        Equal.cong(G.Resolution, Maybe<&2, G.Job>,
          resolution => Finite.find(~G.Job, G.jobs(Actual.result_state(Actual.resolution_calculation(resolution, state))), id),
          G.found_job(Some{job}, connection, project, id, False{}),
          owner_bool_calculation(G.owned(connection, project, job), connection, project, id, job),
          owner_bool_actual(connection, project, id, job)),
        cancel_owner_lookup(G.owned(connection, project, job), connection, project, id, job, state))

def cancel_job_first(+found: Maybe<&2, G.Job>, +connection: Nat, +project: Nat, +id: Nat, +state: G.State) -> C.Decision<G.State, G.Effect>:
  Actual.resolution_calculation(G.found_job(found, connection, project, id, False{}), state)

def cancel_job_joint_goal(+found: Maybe<&2, G.Job>, +original_lookup: Maybe<&2, G.Job>, +connection: Nat, +project: Nat, +id: Nat, +state: G.State) -> Type:
  {cancel_joint_observation(Actual.resolution_calculation(
     G.found_job(cancel_next_lookup(found, original_lookup, connection, project, id), connection, project, id, False{}),
     Actual.result_state(cancel_job_first(found, connection, project, id, state)))) ==
   (Actual.result_state(cancel_job_first(found, connection, project, id, state)), Nil{}) : (G.State & +List<G.Effect>)}

def cancel_job_diagonal_goal(+found: Maybe<&2, G.Job>, +connection: Nat, +project: Nat, +id: Nat, +state: G.State) -> Type:
  cancel_job_joint_goal(found, found, connection, project, id, state)

def cancel_job_joint_transport(+found: Maybe<&2, G.Job>, +connection: Nat, +project: Nat, +id: Nat, +state: G.State,
  observed: {Finite.find(~G.Job, G.jobs(state), id) == found : Maybe<&2, G.Job>},
  selected: cancel_job_joint_goal(found, found, connection, project, id, state)) ->
  cancel_job_joint_goal(Finite.find(~G.Job, G.jobs(state), id), Finite.find(~G.Job, G.jobs(state), id), connection, project, id, state):
  %Equal.sym(Maybe<&2, G.Job>, Finite.find(~G.Job, G.jobs(state), id), found, observed) :
    cancel_job_diagonal_goal(_, connection, project, id, state)
  selected

def cancel_next_job_outcome(outcome: G.Outcome, +job: G.Job) -> G.Job:
  match outcome:
    case G.Running{}: G.with_outcome(G.Interrupted{"Cancellation requested; physical changes are not undone"}, job)
    case G.Finished{value, error}: job
    case G.Interrupted{reason}: job

def cancel_next_job(accepted: Bool, +job: G.Job) -> G.Job:
  match accepted:
    case False{}: job
    case True{}: cancel_next_job_outcome(G.outcome(job), job)

def cancel_next_diagonal(+accepted: Bool, +job: G.Job) ->
  {cancel_next_owner(accepted, Some{job}, job) == Some{cancel_next_job(accepted, job)} : Maybe<&2, G.Job>}:
  match accepted:
    case False{}: {==}
    case True{}:
      G.Job{owner, target, request, arguments, workspace, sandbox, outcome} = job
      match outcome:
        case G.Running{}: {==}
        case G.Finished{value, error}: {==}
        case G.Interrupted{reason}: {==}

def cancel_next_ownership(+accepted: Bool, +connection: Nat, +project: Nat, +job: G.Job) ->
  {G.owned(connection, project, cancel_next_job(accepted, job)) == G.owned(connection, project, job) : Bool}:
  match accepted:
    case False{}: {==}
    case True{}:
      G.Job{owner, target, request, arguments, workspace, sandbox, outcome} = job
      match outcome:
        case G.Running{}: {==}
        case G.Finished{value, error}: {==}
        case G.Interrupted{reason}: {==}

def cancel_diagonal_second_actual(+connection: Nat, +project: Nat, +id: Nat, +job: G.Job) ->
  {G.found_job(cancel_next_lookup(Some{job}, Some{job}, connection, project, id), connection, project, id, False{}) ==
   owner_bool_calculation(G.owned(connection, project, job), connection, project, id,
     cancel_next_job(G.owned(connection, project, job), job)) : G.Resolution}:
  +accepted = G.owned(connection, project, job)
  +updated = cancel_next_job(accepted, job)
  Equal.trans(G.Resolution,
    G.found_job(cancel_next_lookup(Some{job}, Some{job}, connection, project, id), connection, project, id, False{}),
    G.found_job(Some{updated}, connection, project, id, False{}),
    owner_bool_calculation(accepted, connection, project, id, updated),
    Equal.cong(Maybe<&2, G.Job>, G.Resolution,
      found => G.found_job(found, connection, project, id, False{}),
      cancel_next_owner(accepted, Some{job}, job), Some{updated}, cancel_next_diagonal(accepted, job)),
    Equal.trans(G.Resolution,
      G.found_job(Some{updated}, connection, project, id, False{}),
      owner_bool_calculation(G.owned(connection, project, updated), connection, project, id, updated),
      owner_bool_calculation(accepted, connection, project, id, updated),
      owner_bool_actual(connection, project, id, updated),
      Equal.cong(Bool, G.Resolution,
        owned => owner_bool_calculation(owned, connection, project, id, updated),
        G.owned(connection, project, updated), accepted, cancel_next_ownership(accepted, connection, project, job))))

def cancel_owner_joint(+accepted: Bool, +connection: Nat, +project: Nat, +id: Nat, +job: G.Job, +state: G.State) ->
  {cancel_joint_observation(Actual.resolution_calculation(
     owner_bool_calculation(accepted, connection, project, id, cancel_next_job(accepted, job)),
     Actual.result_state(Actual.resolution_calculation(owner_bool_calculation(accepted, connection, project, id, job), state)))) ==
   (Actual.result_state(Actual.resolution_calculation(owner_bool_calculation(accepted, connection, project, id, job), state)), Nil{}) : (G.State & +List<G.Effect>)}:
  match accepted:
    case False{}: {==}
    case True{}:
      G.Job{owner, target, request, arguments, workspace, sandbox, outcome} = job
      match outcome:
        case G.Running{}: {==}
        case G.Finished{value, error}: {==}
        case G.Interrupted{reason}: {==}

def cancel_first_resolution_goal(+resolution: G.Resolution, +found: Maybe<&2, G.Job>, +connection: Nat, +project: Nat, +id: Nat, +state: G.State) -> Type:
  {cancel_joint_observation(Actual.resolution_calculation(
     G.found_job(cancel_next_lookup(found, found, connection, project, id), connection, project, id, False{}),
     Actual.result_state(Actual.resolution_calculation(resolution, state)))) ==
   (Actual.result_state(Actual.resolution_calculation(resolution, state)), Nil{}) : (G.State & +List<G.Effect>)}

def cancel_some_joint(+connection: Nat, +project: Nat, +id: Nat, +job: G.Job, +state: G.State) ->
  cancel_job_diagonal_goal(Some{job}, connection, project, id, state):
  %Equal.sym(G.Resolution,
    G.found_job(Some{job}, connection, project, id, False{}),
    owner_bool_calculation(G.owned(connection, project, job), connection, project, id, job),
    owner_bool_actual(connection, project, id, job)) :
    cancel_first_resolution_goal(_, Some{job}, connection, project, id, state)
  +first_state = Actual.result_state(Actual.resolution_calculation(
    owner_bool_calculation(G.owned(connection, project, job), connection, project, id, job), state))
  Equal.trans((G.State & +List<G.Effect>),
    cancel_joint_observation(Actual.resolution_calculation(
      G.found_job(cancel_next_lookup(Some{job}, Some{job}, connection, project, id), connection, project, id, False{}), first_state)),
    cancel_joint_observation(Actual.resolution_calculation(
      owner_bool_calculation(G.owned(connection, project, job), connection, project, id,
        cancel_next_job(G.owned(connection, project, job), job)), first_state)),
    (first_state, Nil{}),
    Equal.cong(G.Resolution, (G.State & +List<G.Effect>),
      resolution => cancel_joint_observation(Actual.resolution_calculation(resolution, first_state)),
      G.found_job(cancel_next_lookup(Some{job}, Some{job}, connection, project, id), connection, project, id, False{}),
      owner_bool_calculation(G.owned(connection, project, job), connection, project, id,
        cancel_next_job(G.owned(connection, project, job), job)),
      cancel_diagonal_second_actual(connection, project, id, job)),
    cancel_owner_joint(G.owned(connection, project, job), connection, project, id, job, state))

def cancel_job_diagonal(+found: Maybe<&2, G.Job>, +connection: Nat, +project: Nat, +id: Nat, +state: G.State) ->
  cancel_job_diagonal_goal(found, connection, project, id, state):
  match found:
    case None{}: {==}
    case Some{job}: cancel_some_joint(connection, project, id, job, state)

def cancel_actual_job_joint(+connection: Nat, +project: Nat, +id: Nat, +state: G.State) ->
  {cancel_joint_observation(Actual.resolution_calculation(
     G.found_job(Finite.find(~G.Job, G.jobs(Actual.result_state(cancel_job_first(
       Finite.find(~G.Job, G.jobs(state), id), connection, project, id, state))), id), connection, project, id, False{}),
     Actual.result_state(cancel_job_first(Finite.find(~G.Job, G.jobs(state), id), connection, project, id, state)))) ==
   (Actual.result_state(cancel_job_first(Finite.find(~G.Job, G.jobs(state), id), connection, project, id, state)), Nil{}) : (G.State & +List<G.Effect>)}:
  +found = Finite.find(~G.Job, G.jobs(state), id)
  +first_state = Actual.result_state(cancel_job_first(found, connection, project, id, state))
  Equal.trans((G.State & +List<G.Effect>),
    cancel_joint_observation(Actual.resolution_calculation(
      G.found_job(Finite.find(~G.Job, G.jobs(first_state), id), connection, project, id, False{}), first_state)),
    cancel_joint_observation(Actual.resolution_calculation(
      G.found_job(cancel_next_lookup(found, found, connection, project, id), connection, project, id, False{}), first_state)),
    (first_state, Nil{}),
    Equal.cong(Maybe<&2, G.Job>, (G.State & +List<G.Effect>),
      lookup => cancel_joint_observation(Actual.resolution_calculation(
        G.found_job(lookup, connection, project, id, False{}), first_state)),
      Finite.find(~G.Job, G.jobs(first_state), id), cancel_next_lookup(found, found, connection, project, id),
      cancel_next_lookup_actual(found, connection, project, id, state)),
    cancel_job_joint_transport(found, connection, project, id, state, {==},
      cancel_job_diagonal(found, connection, project, id, state)))

def cancel_authority_joint(+accepted: Bool, +connection: Nat, +project: Nat, +id: Nat, +state: G.State) ->
  {cancel_joint_observation(Actual.resolution_calculation(
     authority_bool_calculation(accepted, connection, project, id,
       Actual.result_state(Actual.resolution_calculation(authority_bool_calculation(accepted, connection, project, id, state), state))),
     Actual.result_state(Actual.resolution_calculation(authority_bool_calculation(accepted, connection, project, id, state), state)))) ==
   (Actual.result_state(Actual.resolution_calculation(authority_bool_calculation(accepted, connection, project, id, state), state)), Nil{}) : (G.State & +List<G.Effect>)}:
  match accepted:
    case False{}: {==}
    case True{}: cancel_actual_job_joint(connection, project, id, state)

def cancel_raw_joint(+found: Maybe<&2, G.Grant>, +connection: Nat, +project: Nat, +id: Nat, +state: G.State) ->
  cancel_joint_goal(found, connection, project, id, state):
  match found:
    case None{}: {==}
    case Some{grant}: cancel_authority_joint(G.project_grant_allowed(project, grant), connection, project, id, state)

# NOTE: This family retains the exact first decision while independently
# reconnecting the second authorization to the preserved grant lookup.
def cancel_resolution_joint_goal(+resolution: G.Resolution, +connection: Nat, +project: Nat, +id: Nat, +state: G.State, +projects: D.Projects) -> Type:
  {cancel_joint_observation(Actual.realize(G.construct_command(G.Cancel{connection, project, id},
     Actual.result_state(Actual.resolution_calculation(resolution, state)), projects))) ==
   (Actual.result_state(Actual.resolution_calculation(resolution, state)), Nil{}) : (G.State & +List<G.Effect>)}

def cancel_public_resolution(+connection: Nat, +project: Nat, +id: Nat, +state: G.State, +projects: D.Projects) ->
  {Actual.realize(G.construct_command(G.Cancel{connection, project, id}, state, projects)) ==
   Actual.resolution_calculation(authority_raw_calculation(Finite.find(~G.Grant, G.grants(state), connection), connection, project, id, state), state) : C.Decision<G.State, G.Effect>}:
  Equal.trans(C.Decision<G.State, G.Effect>,
    Actual.realize(G.construct_command(G.Cancel{connection, project, id}, state, projects)),
    Actual.resolution_calculation(G.resolve(G.Cancel{connection, project, id}, state, projects), state),
    Actual.resolution_calculation(authority_raw_calculation(Finite.find(~G.Grant, G.grants(state), connection), connection, project, id, state), state),
    constructed_command_equation(G.Cancel{connection, project, id}, state, projects),
    Equal.cong(G.Resolution, C.Decision<G.State, G.Effect>, resolution => Actual.resolution_calculation(resolution, state),
      G.resolve(G.Cancel{connection, project, id}, state, projects),
      authority_raw_calculation(Finite.find(~G.Grant, G.grants(state), connection), connection, project, id, state),
      authority_raw_actual(Finite.find(~G.Grant, G.grants(state), connection), connection, project, id, state)))

def cancel_raw_public_joint(+connection: Nat, +project: Nat, +id: Nat, +state: G.State, +projects: D.Projects) ->
  cancel_resolution_joint_goal(authority_raw_calculation(Finite.find(~G.Grant, G.grants(state), connection), connection, project, id, state),
    connection, project, id, state, projects):
  +found = Finite.find(~G.Grant, G.grants(state), connection)
  +first_state = Actual.result_state(cancel_raw_first(found, connection, project, id, state))
  Equal.trans((G.State & +List<G.Effect>),
    cancel_joint_observation(Actual.realize(G.construct_command(G.Cancel{connection, project, id}, first_state, projects))),
    cancel_joint_observation(Actual.resolution_calculation(
      authority_raw_calculation(Finite.find(~G.Grant, G.grants(first_state), connection), connection, project, id, first_state), first_state)),
    (first_state, Nil{}),
    Equal.cong(C.Decision<G.State, G.Effect>, (G.State & +List<G.Effect>), cancel_joint_observation,
      Actual.realize(G.construct_command(G.Cancel{connection, project, id}, first_state, projects)),
      Actual.resolution_calculation(authority_raw_calculation(Finite.find(~G.Grant, G.grants(first_state), connection), connection, project, id, first_state), first_state),
      cancel_public_resolution(connection, project, id, first_state, projects)),
    Equal.trans((G.State & +List<G.Effect>),
      cancel_joint_observation(Actual.resolution_calculation(
        authority_raw_calculation(Finite.find(~G.Grant, G.grants(first_state), connection), connection, project, id, first_state), first_state)),
      cancel_joint_observation(Actual.resolution_calculation(authority_raw_calculation(found, connection, project, id, first_state), first_state)),
      (first_state, Nil{}),
      Equal.cong(Maybe<&2, G.Grant>, (G.State & +List<G.Effect>),
        lookup => cancel_joint_observation(Actual.resolution_calculation(authority_raw_calculation(lookup, connection, project, id, first_state), first_state)),
        Finite.find(~G.Grant, G.grants(first_state), connection), found,
        cancel_raw_grant_lookup_frame(found, connection, project, id, state)),
      cancel_joint_transport(found, connection, project, id, state, {==}, cancel_raw_joint(found, connection, project, id, state))))

def cancel_first(+connection: Nat, +project: Nat, +id: Nat, +state: G.State, +projects: D.Projects) -> C.Decision<G.State, G.Effect>:
  Boundary.cancel_first(connection, project, id, state, projects)

def cancel_second(+connection: Nat, +project: Nat, +id: Nat, +state: G.State, +projects: D.Projects) -> C.Decision<G.State, G.Effect>:
  Boundary.cancel_second(connection, project, id, state, projects)

def cancel_decision_joint_goal(+first: C.Decision<G.State, G.Effect>, +connection: Nat, +project: Nat, +id: Nat, +projects: D.Projects) -> Type:
  {cancel_joint_observation(Actual.realize(G.construct_command(G.Cancel{connection, project, id}, Actual.result_state(first), projects))) ==
   (Actual.result_state(first), Nil{}) : (G.State & +List<G.Effect>)}

def cancel_joint(+connection: Nat, +project: Nat, +id: Nat, +state: G.State, +projects: D.Projects) ->
  {cancel_joint_observation(cancel_second(connection, project, id, state, projects)) ==
   (Actual.result_state(cancel_first(connection, project, id, state, projects)), Nil{}) : (G.State & +List<G.Effect>)}:
  %Equal.sym(C.Decision<G.State, G.Effect>,
    cancel_first(connection, project, id, state, projects),
    cancel_raw_first(Finite.find(~G.Grant, G.grants(state), connection), connection, project, id, state),
    cancel_public_resolution(connection, project, id, state, projects)) :
    cancel_decision_joint_goal(_, connection, project, id, projects)
  cancel_raw_public_joint(connection, project, id, state, projects)

def cancel_state_observation(pair: (G.State & +List<G.Effect>)) -> G.State:
  (state, effects) = pair
  state

def cancel_effect_observation(pair: (G.State & +List<G.Effect>)) -> +List<G.Effect>:
  (state, effects) = pair
  effects

def cancel_effects(decision: C.Decision<G.State, G.Effect>) -> +List<G.Effect>:
  Boundary.cancel_effects(decision)

def cancel_state_projection(+decision: C.Decision<G.State, G.Effect>) ->
  {cancel_state_observation(cancel_joint_observation(decision)) == Actual.result_state(decision) : G.State}:
  match decision:
    case C.Decision{state, reply, effects}: {==}

def cancel_effect_projection(+decision: C.Decision<G.State, G.Effect>) ->
  {cancel_effect_observation(cancel_joint_observation(decision)) == cancel_effects(decision) : +List<G.Effect>}:
  match decision:
    case C.Decision{state, reply, effects}: {==}

def cancel_repeated_state(+connection: Nat, +project: Nat, +id: Nat, +state: G.State, +projects: D.Projects) ->
  {Actual.result_state(cancel_second(connection, project, id, state, projects)) ==
   Actual.result_state(cancel_first(connection, project, id, state, projects)) : G.State}:
  +second = cancel_second(connection, project, id, state, projects)
  +first_state = Actual.result_state(cancel_first(connection, project, id, state, projects))
  Equal.trans(G.State, Actual.result_state(second), cancel_state_observation(cancel_joint_observation(second)), first_state,
    Equal.sym(G.State, cancel_state_observation(cancel_joint_observation(second)), Actual.result_state(second), cancel_state_projection(second)),
    Equal.cong((G.State & +List<G.Effect>), G.State, cancel_state_observation,
      cancel_joint_observation(second), (first_state, Nil{}), cancel_joint(connection, project, id, state, projects)))

def cancel_repeated_effects(+connection: Nat, +project: Nat, +id: Nat, +state: G.State, +projects: D.Projects) ->
  {cancel_effects(cancel_second(connection, project, id, state, projects)) == Nil{} : +List<G.Effect>}:
  +second = cancel_second(connection, project, id, state, projects)
  Equal.trans(+List<G.Effect>, cancel_effects(second), cancel_effect_observation(cancel_joint_observation(second)), Nil{},
    Equal.sym(+List<G.Effect>, cancel_effect_observation(cancel_joint_observation(second)), cancel_effects(second), cancel_effect_projection(second)),
    Equal.cong((G.State & +List<G.Effect>), +List<G.Effect>, cancel_effect_observation,
      cancel_joint_observation(second),
      (Actual.result_state(cancel_first(connection, project, id, state, projects)), Nil{}),
      cancel_joint(connection, project, id, state, projects)))

def cancellation_capability() -> Boundary.CancellationCapability:
  Boundary.CancellationCapability{cancel_repeated_state, cancel_repeated_effects}

def Boundary.boundary():
  Boundary.Boundary{refinement, assembled, written, core_frame, board_frame, rest_frame, board_preserves,
    ownership,
    connection => project => request => arguments => projects => state => {==},
    connection => project => id => state => {==},
    removed,
    restarted,
    cancellation_capability()}
