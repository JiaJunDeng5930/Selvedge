import Base
import ./MODEL.bend as F
import ../../features/board/MODEL.bend as Board
import ../../bendlib/component.bend as C

def board_written(+value: Board.State, state: F.State()) ->
  {F.board(F.with_board(value, state)) == value : Board.State}:
  match state:
    case C.Frame{previous, rest}: {==}

def board_frame(value: Board.State, state: F.State()) ->
  {F.modules(F.with_board(value, state)) == F.modules(state) : F.Modules()}:
  C.replace_frame(Board.State, F.Modules(), value, state)
