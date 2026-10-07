import Base
import ./MODEL.bend as F
import ../../features/board/MODEL.bend as Board
import ../../bendlib/component.bend as C

def board_written(+value: Board.State, state: F.State()) ->
  {F.board(F.with_board(value, state)) == value : Board.State}:
  match state:
    case C.Frame{previous, rest}: {==}

def board_frame(value: Board.State, state: F.State()) ->
  {F.rest(F.with_board(value, state)) == F.rest(state) : F.Rest()}:
  match state:
    case C.Frame{previous, rest}: {==}
