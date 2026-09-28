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

def cursor_frame(value: Board.Cursor, cursor: F.Cursor()) ->
  {F.cursor_rest(F.with_board_cursor(value, cursor)) == F.cursor_rest(cursor) : F.CursorRest()}:
  match cursor:
    case C.Frame{previous, rest}: {==}

def cursor_written(+value: Board.Cursor, cursor: F.Cursor()) ->
  {F.board_cursor(F.with_board_cursor(value, cursor)) == value : Board.Cursor}:
  match cursor:
    case C.Frame{previous, rest}: {==}
