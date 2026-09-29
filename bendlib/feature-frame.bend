import Base
import ../FEATURES.bend as F
import ../BOARD.bend as Board
import ./component.bend as C

def board_written(+value: Board.State, state: F.State()) ->
  {F.board(F.with_board(value, state)) == value : Board.State}:
  match state:
    case C.Frame{previous, rest}: {==}

def board_frame(value: Board.State, state: F.State()) ->
  {F.rest(F.with_board(value, state)) == F.rest(state) : F.Rest()}:
  match state:
    case C.Frame{previous, rest}: {==}
