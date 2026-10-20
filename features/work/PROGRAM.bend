import Base
import ./MODEL.bend as W
import ../../bendlib/association-map.bend as Finite
import ../../bendlib/component.bend as C
import ../../harness/DOMAIN.bend as D

def put_selected(hit: Bool, key: Nat, previous: W.Work, rest: +List<Finite.Entry(W.Work)>, work: W.Work, updated: +List<Finite.Entry(W.Work)>) -> +List<Finite.Entry(W.Work)>:
  match hit:
    case True{}: (key, work) <> rest
    case False{}: (key, previous) <> updated

def put_entries(entries: +List<Finite.Entry(W.Work)>, +id: Nat, +work: W.Work) -> +List<Finite.Entry(W.Work)>:
  match entries:
    case Nil{}: [(id, work)]
    case Con{(+key, previous), +rest}:
      put_selected(Nat.is_eq(id, key), key, previous, rest, work, put_entries(rest, id, work))

def put(+id: Nat, work: W.Work, state: W.State, next: Nat) -> W.State:
  W.State{works, roots, graphs, previous_next} = state
  W.State{put_entries(works, id, work), roots, graphs, next}

def result_state(decision: C.Decision<W.State, Unit>) -> W.State:
  C.Decision{state, reply, effects} = decision
  state

def realize_calculation(change: W.Change, +state: W.State) -> C.Decision<W.State, Unit>:
  match change:
    case W.Add{+id, +work, next}:
      C.Decision{put(id, work, state, next), D.success(W.work_json(id, work)), Nil{}}
    case W.Retitle{+id, +work}:
      C.Decision{put(id, work, state, W.next(state)), D.success(W.work_json(id, work)), Nil{}}
    case W.UpdateUI{+id, +work}:
      C.Decision{put(id, work, state, W.next(state)), D.success(W.ui_json(id, work)), Nil{}}
