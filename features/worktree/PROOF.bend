import Base
import ./MODEL.bend as W
import ./CONTRACT.bend as Contract
import ../../bendlib/association-map.bend as Finite

def same_key(+task_id: Nat) -> {Nat.is_eq(task_id, task_id) == True{} : Bool}:
  match task_id:
    case 0n: {==}
    case 1n+previous: same_key(previous)

def written(+task_id: Nat, +value: W.Worktree, +state: W.State) ->
  {W.lookup(task_id, W.put(task_id, value, state)) == Some{value} : Maybe<&2, W.Worktree>}:
  W.State{+entries} = state
  backwards = Equal.sym(Bool, Nat.is_eq(task_id, task_id), True{}, same_key(task_id))
  %backwards : {Finite.choose(~W.Worktree, _, value,
    Finite.find(~W.Worktree, Finite.remove(~W.Worktree, entries, task_id), task_id)) == Some{value} : Maybe<&2, W.Worktree>}
  {==}

def replaced_absence(+task_id: Nat, value: W.Worktree, state: W.State) ->
  {Finite.find(~W.Worktree, List.tail(&2, Finite.Entry(W.Worktree), W.entries(W.put(task_id, value, state))), task_id) == None{} : Maybe<&2, W.Worktree>}:
  Finite.removal_absence(~W.Worktree, W.entries(state), task_id)

def boundary() -> Contract.Boundary:
  Contract.Boundary{written, replaced_absence, {==}, {==}, {==}, {==}, {==}, {==}, {==}}
