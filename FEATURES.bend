import Base
import ./bendlib/domain.bend as D
import ./BOARD.bend as Board
import ./bendlib/board-codec.bend as BoardCodec
import ./bendlib/json.bend as J
import ./bendlib/component.bend as C
import ./CHATGPT.bend as ChatGPT
import ./bendlib/chatgpt-codec.bend as ChatGPTCodec

# The empty product is the identity for adding further independent components.
# Only this assembly module selects their concrete state types and initializers.
def Rest() -> Data:
  Unit

def initial_rest() -> Rest():
  Unit{}

def State() -> Data:
  C.Frame<Board.State, Modules()>

def Modules() -> Data:
  C.Frame<ChatGPT.State, Rest()>

def initial() -> State():
  C.Frame{Board.initial(), C.Frame{ChatGPT.initial(), initial_rest()}}

def board(state: State()) -> Board.State:
  C.local(Board.State, Modules(), state)

def rest(state: State()) -> Rest():
  C.rest(ChatGPT.State, Rest(), C.rest(Board.State, Modules(), state))

def with_board(value: Board.State, state: State()) -> State():
  C.replace(Board.State, Modules(), value, state)

def chatgpt(state: State()) -> ChatGPT.State:
  C.local(ChatGPT.State, Rest(), C.rest(Board.State, Modules(), state))

def with_chatgpt(value: ChatGPT.State, state: State()) -> State():
  C.map_rest(Board.State, Modules(), rest => C.replace(ChatGPT.State, Rest(), value, rest), state)

def with_rest(value: Rest(), state: State()) -> State():
  C.map_rest(Board.State, Modules(), modules => C.map_rest(ChatGPT.State, Rest(), previous => value, modules), state)

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
  ChatGPTEffect{effect: ChatGPT.Effect}
  RequestBoardText{card_id: Nat, ticket: Nat, profile: D.Profile, prompt: String, retitle: Bool}

type Command is Data:
  ChatGPTCommand{command: ChatGPT.Command}
  BoardCommand{command: Board.Command}

type Query is Data:
  ChatGPTQuery{query: ChatGPT.Query}
  BoardQuery{query: Board.Query}

type CommandKind is Data:
  ChatGPTKind{kind: ChatGPTCodec.EntryKind}
  BoardKind{kind: BoardCodec.EntryKind}

type Navigation is Data:
  BoardEvent{event: Board.Navigation}

type Completion is Data:
  ChatGPTCompleted{operation: Nat, value: J.Json, error: Bool}
  BoardTextCompleted{card_id: Nat, ticket: Nat, outcome: Board.Outcome}

type CommandSpec is Data:
  CommandSpec{name: String, description: String, kind: CommandKind, schema: J.Json}

def board_specs(specs: +List<BoardCodec.Spec>) -> +List<CommandSpec>:
  match specs:
    case Nil{}: Nil{}
    case Con{BoardCodec.Spec{name, description, kind, schema}, rest}:
      CommandSpec{name, description, BoardKind{kind}, schema} <> board_specs(rest)

def chatgpt_specs(specs: +List<ChatGPTCodec.Spec>) -> +List<CommandSpec>:
  match specs:
    case Nil{}: Nil{}
    case Con{ChatGPTCodec.Spec{name, description, kind, schema}, rest}:
      CommandSpec{name, description, ChatGPTKind{kind}, schema} <> chatgpt_specs(rest)

def specs(settings_schema: J.Json) -> +List<CommandSpec>:
  List.append(&2, CommandSpec, board_specs(BoardCodec.specs(settings_schema)), chatgpt_specs(ChatGPTCodec.specs()))
