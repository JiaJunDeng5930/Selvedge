import Base
import ./MODEL.bend as W
import ../../bendlib/association-map.bend as Finite
import ../../bendlib/component.bend as C
import ../../harness/DOMAIN.bend as D

def replacement(hit: Bool, key: Nat, previous: W.Work, tail: +List<Finite.Entry(W.Work)>, work: W.Work, updated: +List<Finite.Entry(W.Work)>) -> +List<Finite.Entry(W.Work)>:
  match hit:
    case True{}: (key, work) <> tail
    case False{}: (key, previous) <> updated

# Creation appends, while renaming retains the existing Work's position.
def store(entries: +List<Finite.Entry(W.Work)>, +id: Nat, +work: W.Work) -> +List<Finite.Entry(W.Work)>:
  match entries:
    case Nil{}: [(id, work)]
    case Con{(+key, previous), +tail}:
      replacement(Nat.is_eq(id, key), key, previous, tail, work, store(tail, id, work))

def meaning(change: W.Change, +state: W.State) -> C.Decision<W.State, Unit>:
  match change:
    case W.Add{+id, +work, next}:
      W.State{works, roots, graphs, previous_next} = state
      C.Decision{W.State{store(works, id, work), roots, graphs, next}, D.success(W.work_json(id, work)), Nil{}}
    case W.Retitle{+id, +work}:
      W.State{works, roots, graphs, previous_next} = state
      C.Decision{W.State{store(works, id, work), roots, graphs, previous_next}, D.success(W.work_json(id, work)), Nil{}}
    case W.UpdateUI{+id, +work}:
      W.State{works, roots, graphs, previous_next} = state
      C.Decision{W.State{store(works, id, work), roots, graphs, previous_next}, D.success(W.ui_json(id, work)), Nil{}}
