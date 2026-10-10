import Base
import ../../bendlib/categories.bend as Categories
import ./MODEL.bend as G
import ../../bendlib/component.bend as C
import ../../harness/DOMAIN.bend as D
import ../../bendlib/json.bend as J
import ../../bendlib/association-map.bend as Finite

def result_state(decision: C.Decision<G.State, G.Effect>) -> G.State:
  C.Decision{state, reply, effects} = decision
  state

def put(+id: Nat, job: G.Job, state: G.State, next: Nat) -> G.State:
  G.State{grants, jobs, previous} = state
  G.State{grants, (id, job) <> Finite.remove(~G.Job, jobs, id), next}

def respond(state: G.State, reply: J.Json) -> C.Decision<G.State, G.Effect>:
  C.Decision{state, D.success(reply), Nil{}}

def interrupted(+id: Nat, +job: G.Job, +state: G.State) -> C.Decision<G.State, G.Effect>:
  C.Decision{put(id, job, state, G.next(state)), D.success(G.receipt(id, job)), [G.Stop{id}]}

def change_calculation(change: G.Change, +state: G.State) -> C.Decision<G.State, G.Effect>:
  match change:
    case G.SetGrants{entries}:
      G.State{previous, jobs, next} = state
      respond(G.State{entries, jobs, next}, J.Object{[]})
    case G.Start{+id, +job}:
      C.Decision{put(id, job, state, 1n+id), D.success(G.receipt(id, job)), [G.Execute{id, job}]}
    case G.Reuse{id, job}: respond(state, G.receipt(id, job))
    case G.Interrupt{id, job}:
      interrupted(id, G.with_outcome(G.Interrupted{"Cancellation requested; physical changes are not undone"}, job), state)
    case G.Remove{+id}:
      G.State{grants, jobs, next} = state
      respond(G.State{grants, Finite.remove(~G.Job, jobs, id), next}, J.Object{[J.Field{"operation_id", J.nat(id)}]})
    case G.Complete{id, job, value, error}:
      respond(put(id, G.with_outcome(G.Finished{value, error}, job), state, G.next(state)),
        J.Object{[J.Field{"accepted", J.Boolean{True{}}}]})

type ChangeRequest is Data:
  ChangeRequest{change: G.Change, state: G.State}

def change_result(request: ChangeRequest) -> C.Decision<G.State, G.Effect>:
  ChangeRequest{change, state} = request
  change_calculation(change, state)

def ConstructedChange() -> Type:
  Categories.Membership<Categories.Construction<ChangeRequest, C.Decision<G.State, G.Effect>>,
    Categories.constructed_by(ChangeRequest, C.Decision<G.State, G.Effect>, change_result)>

def construct_change(change: G.Change, state: G.State) -> ConstructedChange():
  Categories.construct(ChangeRequest, C.Decision<G.State, G.Effect>, change_result, ChangeRequest{change, state})

def change_value(member: ConstructedChange()) -> C.Decision<G.State, G.Effect>:
  Categories.Membership{Categories.Construction{request, result}, evidence} = member
  result

def realize_calculation(change: G.Change, +state: G.State) -> C.Decision<G.State, G.Effect>:
  change_value(construct_change(change, state))

# Calculation helpers interpret the canonical result; public consumers capture
# their state exclusively from the construction request.
def resolution_calculation(resolution: G.Resolution, state: G.State) -> C.Decision<G.State, G.Effect>:
  match resolution:
    case G.Refuse{code, reason}: C.Decision{state, D.failure(code, reason), Nil{}}
    case G.Accept{change}: realize_calculation(change, state)

def realize(member: G.ConstructedCommand()) -> C.Decision<G.State, G.Effect>:
  Categories.Membership{Categories.Construction{G.CommandRequest{command, state, projects}, resolution}, evidence} = member
  resolution_calculation(resolution, state)

def completion_calculation(change: Maybe<&2, G.Change>, state: G.State) -> Maybe<&2, C.Decision<G.State, G.Effect>>:
  match change:
    case None{}: None{}
    case Some{change}: Some{realize_calculation(change, state)}

def realize_completion(member: G.ConstructedCompletion()) -> Maybe<&2, C.Decision<G.State, G.Effect>>:
  Categories.Membership{Categories.Construction{G.CompletionRequest{id, value, error, state}, change}, evidence} = member
  completion_calculation(change, state)
