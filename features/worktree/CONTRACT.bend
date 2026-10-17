import Base
import ./MODEL.bend as W
import ../../bendlib/association-map.bend as Finite

type Boundary is Type:
  Boundary{
    written: @+task_id:Nat -> @+value:W.Worktree -> @+state:W.State ->
      {W.lookup(task_id, W.put(task_id, value, state)) == Some{value} : Maybe<&2, W.Worktree>},
    replaced_absence: @+task_id:Nat -> @value:W.Worktree -> @state:W.State ->
      {Finite.find(~W.Worktree, List.tail(&2, Finite.Entry(W.Worktree), W.entries(W.put(task_id, value, state))), task_id) == None{} : Maybe<&2, W.Worktree>},
    creating_pending: {W.pending(W.Creating{}) == True{} : Bool},
    creating_archived_pending: {W.pending(W.CreatingArchived{}) == True{} : Bool},
    archiving_pending: {W.pending(W.Archiving{}) == True{} : Bool},
    ready_settled: {W.pending(W.Ready{}) == False{} : Bool},
    create_failed_settled: {W.pending(W.CreateFailed{}) == False{} : Bool},
    archived_settled: {W.pending(W.Archived{}) == False{} : Bool},
    archive_failed_settled: {W.pending(W.ArchiveFailed{}) == False{} : Bool}
  }
