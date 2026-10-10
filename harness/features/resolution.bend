import Base
import ../DOMAIN.bend as D
import ../../bendlib/json.bend as J
import ../MODEL.bend as M
import ./MODEL.bend as F
import ../../features/board/MODEL.bend as B
import ../workspace/WORKSPACE.bend as Workspace
import ./operations.bend as O
import ../../features/board/resolution.bend as Board
import ../../features/chatgpt/MODEL.bend as ChatGPT
import ../workspace/PROJECTS.bend as Projects
import ../../features/chatgpt/STATE.bend as ChatGPTState

type Start is Data:
  Start{profile: D.Profile, reasoning: String, message: String, selection: Workspace.Selection}
  StartRefused{code: String, reason: String}
  InvalidStart{}

type Resolution is Data:
  Refuse{code: String, reason: String}
  Accept{operation: O.Operation}

def card_start(start: Start, id: Nat, card: B.Card, now: U32) -> Resolution:
  match start:
    case Start{profile, reasoning, message, selection}: Accept{O.StartCard{id, card, now, profile, reasoning, message, selection}}
    case StartRefused{code, reason}: Refuse{code, reason}
    case InvalidStart{}: Refuse{"invalid_card_start", "A board launch must resolve through ordinary task creation"}

def without_project(fields: +List<J.Field>) -> +List<J.Field>:
  match fields:
    case Nil{}: Nil{}
    case Con{J.Field{"project_id", value}, rest}: without_project(rest)
    case Con{field, rest}: field <> without_project(rest)

def with_project(project: Maybe<&2, Nat>, fields: +List<J.Field>) -> J.Json:
  match project:
    case None{}: J.Object{fields}
    case Some{id}: J.Object{J.Field{"project_id", J.nat(id)} <> fields}

def card_options(project: Maybe<&2, Nat>, options: J.Json) -> J.Json:
  match options:
    case J.Object{fields}: with_project(project, without_project(fields))
    case _: with_project(project, Nil{})

def board(start: String -> String -> String -> J.Json -> @+world:M.World() -> Start, resolution: Board.Resolution, world: M.World()) -> Resolution:
  match resolution:
    case Board.Refuse{code, reason}: Refuse{code, reason}
    case Board.Mutate{change}: Accept{O.BoardChange{change}}
    case Board.Launch{+id, +card, now, +agent}:
      card_start(start(B.agent_profile(agent), B.agent_reasoning(agent), B.prompt(id, B.draft(card), B.agent_instructions(agent)),
        card_options(B.project(B.draft(card)), B.agent_settings(agent)), world), id, card, now)

def chatgpt(resolution: ChatGPT.Resolution) -> Resolution:
  match resolution:
    case ChatGPT.Refuse{code, reason}: Refuse{code, reason}
    case ChatGPT.Accept{change}: Accept{O.ChatGPTChange{change}}

def resolve(start: String -> String -> String -> J.Json -> @+world:M.World() -> Start, command: F.Command, +world: M.World()) -> Resolution:
  match command:
    case F.ChatGPTCommand{command}: chatgpt(ChatGPT.resolve(command, ChatGPTState.registry(world), Projects.registry(F.State(), world)))
    case F.BoardCommand{command}: board(start, Board.resolve(command, world), world)
