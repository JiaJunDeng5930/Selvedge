import Base
import ./MODEL.bend as G
import ../../bendlib/component.bend as C
import ../../harness/DOMAIN.bend as D
import ../../bendlib/json.bend as J
import ../../bendlib/association-map.bend as Finite

# Independent complete-decision equations over the accepted operation algebra.
# This module never imports the production interpreter or the feature assembly.
def meaning(change: G.Change, +state: G.State) -> C.Decision<G.State, G.Effect>:
  match change state:
    case G.SetGrants{entries} G.State{grants, jobs, next}:
      C.Decision{G.State{entries, jobs, next}, D.success(J.Object{[]}), Nil{}}
    case G.Start{+id, +job} G.State{grants, jobs, next}:
      C.Decision{G.State{grants, (id, job) <> Finite.remove(~G.Job, jobs, id), 1n+id},
        D.success(G.receipt(id, job)), [G.Execute{id, job}]}
    case G.Reuse{id, job} G.State{grants, jobs, next}: C.Decision{G.State{grants, jobs, next}, D.success(G.receipt(id, job)), Nil{}}
    case G.Interrupt{+id, job} G.State{grants, jobs, next}:
      +changed = G.with_outcome(G.Interrupted{"Cancellation requested; physical changes are not undone"}, job)
      C.Decision{G.State{grants, (id, changed) <> Finite.remove(~G.Job, jobs, id), next},
        D.success(G.receipt(id, changed)), [G.Stop{id}]}
    case G.Remove{+id} G.State{grants, jobs, next}:
      C.Decision{G.State{grants, Finite.remove(~G.Job, jobs, id), next},
        D.success(J.Object{[J.Field{"operation_id", J.nat(id)}]}), Nil{}}
    case G.Complete{+id, job, value, error} G.State{grants, jobs, next}:
      C.Decision{G.State{grants, (id, G.with_outcome(G.Finished{value, error}, job)) <> Finite.remove(~G.Job, jobs, id), next},
        D.success(J.Object{[J.Field{"accepted", J.Boolean{True{}}}]}), Nil{}}
