import Base
import ../DOMAIN.bend as D
import ../MODEL.bend as M
import ../workspace/WORKSPACE.bend as Workspace
import ../../bendlib/component.bend as C
import ./MODEL.bend as F
import ./work-state.bend as Work
import ./worktree-state.bend as Worktree
import ./worktree-spec.bend as RequiredWorktree
import ./worktree-proof.bend as WorktreeProof

def primary(selection: Workspace.Selection) -> String:
  Worktree.selection_primary(selection)

# Idle creation shares the ordinary Work association and managed-worktree birth
# transaction. It never manufactures an input to fit the started-task interface.
def membership(work: Maybe<&2, Nat>, id: Nat, original: M.World(), decision: M.Decision()) -> M.Decision():
  match work:
    case None{}: decision
    case Some{work}: Work.born(work, id, original, decision)

def initialized(create_worktree: Bool, id: Nat, workspace: D.Workspace, decision: M.Decision()) -> M.Decision():
  match create_worktree:
    case False{}: decision
    case True{}: Worktree.initialize(id, workspace, decision)

def required_initialized(create_worktree: Bool, id: Nat, workspace: D.Workspace, decision: M.Decision()) -> M.Decision():
  match create_worktree:
    case False{}: decision
    case True{}: RequiredWorktree.initialize(id, workspace, decision)

def actual(work: Maybe<&2, Nat>, create_worktree: Bool, +selection: Workspace.Selection, +original: M.World(), decision: M.Decision()) -> M.Decision():
  Workspace.Selection{context, guidance} = selection
  +id = D.state_next_task(C.local(D.State, F.State(), original))
  membership(work, id, original, initialized(create_worktree, id, Workspace.workspace(context), decision))

def required(work: Maybe<&2, Nat>, create_worktree: Bool, +selection: Workspace.Selection, +original: M.World(), decision: M.Decision()) -> M.Decision():
  Workspace.Selection{context, guidance} = selection
  +id = D.state_next_task(C.local(D.State, F.State(), original))
  membership(work, id, original, required_initialized(create_worktree, id, Workspace.workspace(context), decision))

def initialize_meaning(+create_worktree: Bool, +id: Nat, +workspace: D.Workspace, +decision: M.Decision()) ->
  {initialized(create_worktree, id, workspace, decision) == required_initialized(create_worktree, id, workspace, decision) : M.Decision()}:
  match create_worktree:
    case False{}: {==}
    case True{}: WorktreeProof.initialize(id, workspace, decision)

def meaning(+work: Maybe<&2, Nat>, +create_worktree: Bool, +selection: Workspace.Selection, +original: M.World(), +decision: M.Decision()) ->
  {actual(work, create_worktree, selection, original, decision) == required(work, create_worktree, selection, original, decision) : M.Decision()}:
  Workspace.Selection{+context, guidance} = selection
  +id = D.state_next_task(C.local(D.State, F.State(), original))
  Equal.cong(M.Decision(), M.Decision(), value => membership(work, id, original, value),
    initialized(create_worktree, id, Workspace.workspace(context), decision),
    required_initialized(create_worktree, id, Workspace.workspace(context), decision), initialize_meaning(create_worktree, id, Workspace.workspace(context), decision))
