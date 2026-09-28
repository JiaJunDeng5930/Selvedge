import Base
import ./bendlib/domain.bend as D
import ./BOARD.bend as Board
import ./bendlib/board-codec.bend as BoardCodec
import ./bendlib/json.bend as J
import ./bendlib/component.bend as C

# The empty product is the identity for adding further independent components.
# Only this assembly module selects their concrete state types and initializers.
def Rest() -> Data:
  Unit

def initial_rest() -> Rest():
  Unit{}

def State() -> Data:
  C.Frame<Board.State, Rest()>

def initial() -> State():
  C.Frame{Board.initial(), initial_rest()}

def board(state: State()) -> Board.State:
  C.local(Board.State, Rest(), state)

def rest(state: State()) -> Rest():
  C.rest(Board.State, Rest(), state)

def with_board(value: Board.State, state: State()) -> State():
  C.replace(Board.State, Rest(), value, state)

def CursorRest() -> Data:
  Unit

def initial_cursor_rest() -> CursorRest():
  Unit{}

def Cursor() -> Data:
  C.Frame<Board.Cursor, CursorRest()>

def from_board_cursor(cursor: Board.Cursor) -> Cursor():
  C.Frame{cursor, initial_cursor_rest()}

def initial_cursor() -> Cursor():
  from_board_cursor(Board.cursor())

def board_cursor(cursor: Cursor()) -> Board.Cursor:
  C.local(Board.Cursor, CursorRest(), cursor)

def cursor_rest(cursor: Cursor()) -> CursorRest():
  C.rest(Board.Cursor, CursorRest(), cursor)

def with_board_cursor(value: Board.Cursor, cursor: Cursor()) -> Cursor():
  C.replace(Board.Cursor, CursorRest(), value, cursor)

type Effect is Data:
  RequestBoardText{card_id: Nat, ticket: Nat, profile: D.Profile, prompt: String, retitle: Bool}

type Command is Data:
  BoardCommand{command: Board.Command}

type Query is Data:
  BoardQuery{query: Board.Query}

type CommandKind is Data:
  BoardKind{kind: BoardCodec.EntryKind}

type Navigation is Data:
  BoardEvent{event: Board.Navigation}

type Completion is Data:
  BoardTextCompleted{card_id: Nat, ticket: Nat, outcome: Board.Outcome}

type CommandSpec is Data:
  CommandSpec{name: String, description: String, kind: CommandKind, schema: J.Json}

def board_specs(specs: +List<BoardCodec.Spec>) -> +List<CommandSpec>:
  match specs:
    case Nil{}: Nil{}
    case Con{BoardCodec.Spec{name, description, kind, schema}, rest}:
      CommandSpec{name, description, BoardKind{kind}, schema} <> board_specs(rest)

def specs(settings_schema: J.Json) -> +List<CommandSpec>:
  board_specs(BoardCodec.specs(settings_schema))
