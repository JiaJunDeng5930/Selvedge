import Base
import ./task-storage.bend as TaskProof
import ./feature-frame.bend as FrameProof
import ../component.bend as C
import ../domain.bend as D
import ./reasoning-locality.bend as ReasoningProof
import ../../FEATURES.bend as F
import ../../BOARD.bend as Board
import ../../MODEL.bend as M
import ../board-state.bend as BoardState
import ../locality.bend as Rule

def board_frame(value: Board.State, world: M.World()) ->
  {F.rest(C.rest(D.State, F.State(), BoardState.store(value, world))) == F.rest(C.rest(D.State, F.State(), world)) : F.Rest()}:
  match world:
    case C.Frame{core, state}: FrameProof.board_frame(value, state)

def board_core_frame(value: Board.State, world: M.World()) ->
  {C.local(D.State, F.State(), BoardState.store(value, world)) == C.local(D.State, F.State(), world) : D.State}:
  match world:
    case C.Frame{core, state}: {==}

def locality() -> Rule.Locality:
  Rule.Locality{
    R => +task => +state => +rest => TaskProof.update_meaning(R, task, state, rest),
    R => task => world => TaskProof.update_frame(R, task, world),
    R => X => +task => +world => ReasoningProof.start_meaning(R, X, task, world),
    R => X => task => world => ReasoningProof.start_frame(R, X, task, world),
    task => world => {==},
    task => world => ReasoningProof.start_frame(F.State(), F.Effect, task, world),
    +value => state => FrameProof.board_written(value, state),
    value => world => board_frame(value, world),
    value => world => board_core_frame(value, world)}
