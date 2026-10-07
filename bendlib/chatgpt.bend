import Base
import ../CHATGPT.bend as G
import ./component.bend as C
import ./domain.bend as D
import ./json.bend as J
import ./association-map.bend as Finite

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

def realize(change: G.Change, +state: G.State) -> C.Decision<G.State, G.Effect>:
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
