import Base
import ../../features/remote/MODEL.bend as Remote
import ../../features/remote/CODEC.bend as RemoteCodec
import ../../features/worktree/CODEC.bend as Worktree
import ../../features/worktree/MODEL.bend as WorktreeModel
import ../../features/compaction/MODEL.bend as CompactionResult
import ../../features/compaction/CODEC.bend as Compaction
import ./MODEL.bend as F
import ../MODEL.bend as M
import ../../features/board/MODEL.bend as B
import ../DOMAIN.bend as D
import ../../bendlib/json.bend as J
import ../transport/schema.bend as Schema
import ../transport/wire-shape.bend as Shape
import ../../features/board/CODEC.bend as Board
import ../../features/chatgpt/MODEL.bend as ChatGPT
import ../../features/chatgpt/CODEC.bend as ChatGPTCodec
import ../../features/task_graph/CODEC.bend as TaskGraphCodec

def command_json(command: F.Command) -> J.Json:
  match command:
    case F.RemoteCommand{command}: RemoteCodec.command_json(command)
    case F.WorktreeCommand{command}: Worktree.command_json(command)
    case F.ChatGPTCommand{command}: ChatGPTCodec.command_json(command)
    case F.BoardCommand{command}: Board.command_json(command)
    case F.TaskGraphCommand{command}: TaskGraphCodec.command_json(command)

def query_json(query: F.Query) -> J.Json:
  match query:
    case F.RemoteStatus{}: RemoteCodec.command_json(Remote.Status{})
    case F.WorktreeQuery{query}: Worktree.query_json(query)
    case F.ChatGPTQuery{query}: ChatGPTCodec.query_json(query)
    case F.BoardQuery{query}: Board.query_json(query)
    case F.TaskGraphQuery{query}: TaskGraphCodec.query_json(query)

def task_graph_command(kind: TaskGraphCodec.EntryKind, body: J.Json) -> M.Command:
  match kind:
    case TaskGraphCodec.Write{kind}: M.FeatureCommand{F.TaskGraphCommand{TaskGraphCodec.construct(kind, body)}}
    case TaskGraphCodec.Read{kind}: M.Observe{M.FeatureQuery{F.TaskGraphQuery{TaskGraphCodec.query(kind, body)}}}

def board_command(kind: Board.EntryKind, body: J.Json) -> M.Command:
  match kind:
    case Board.Write{kind}: M.FeatureCommand{F.BoardCommand{Board.construct(kind, body)}}
    case Board.Read{kind}: M.Observe{M.FeatureQuery{F.BoardQuery{Board.query(kind, body)}}}

def chatgpt_command(kind: ChatGPTCodec.EntryKind, body: J.Json) -> M.Command:
  match kind:
    case ChatGPTCodec.Write{kind}: M.FeatureCommand{F.ChatGPTCommand{ChatGPTCodec.construct(kind, body)}}
    case ChatGPTCodec.Read{kind}: M.Observe{M.FeatureQuery{F.ChatGPTQuery{ChatGPTCodec.query(kind, body)}}}

def remote_command(kind: RemoteCodec.AdminKind, body: J.Json) -> M.Command:
  match kind:
    case RemoteCodec.StatusKind{}: M.Observe{M.FeatureQuery{F.RemoteStatus{}}}
    case other: M.FeatureCommand{F.RemoteCommand{RemoteCodec.construct(other, body)}}

def worktree_command(kind: Worktree.EntryKind, body: J.Json) -> M.Command:
  match kind:
    case Worktree.ListKind{}: M.Observe{M.FeatureQuery{F.WorktreeQuery{Worktree.query(kind, body)}}}
    case Worktree.ReadKind{}: M.Observe{M.FeatureQuery{F.WorktreeQuery{Worktree.query(kind, body)}}}
    case other: M.FeatureCommand{F.WorktreeCommand{Worktree.construct(other, body)}}

def construct(kind: F.CommandKind, body: J.Json) -> M.Command:
  match kind:
    case F.RemoteKind{kind}: remote_command(kind, body)
    case F.WorktreeKind{kind}: worktree_command(kind, body)
    case F.ChatGPTKind{kind}: chatgpt_command(kind, body)
    case F.BoardKind{kind}: board_command(kind, body)
    case F.TaskGraphKind{kind}: task_graph_command(kind, body)

def valid(kind: F.CommandKind, body: J.Json) -> Bool:
  match kind:
    case F.RemoteKind{kind}: RemoteCodec.valid(kind, body)
    case F.WorktreeKind{kind}: Worktree.valid(kind, body)
    case F.ChatGPTKind{kind}: ChatGPTCodec.valid(kind, body)
    case F.BoardKind{kind}: Board.valid(kind, body)
    case F.TaskGraphKind{kind}: TaskGraphCodec.entry_valid(kind, body)

def effect_json(model_json: D.Model -> J.Json, effect: F.Effect) -> J.Json:
  match effect:
    case F.WorktreeEffect{effect}: Worktree.effect_json(effect)
    case F.CompactionEffect{effect}: Compaction.effect_json(model_json, effect)
    case F.ChatGPTEffect{effect}: ChatGPT.effect_json(effect)
    case F.RequestBoardText{card_id, ticket, profile, prompt, retitle}:
      J.Object{[J.Field{"kind", J.Text{"board_text"}}, J.Field{"card_id", J.nat(card_id)}, J.Field{"ticket", J.nat(ticket)},
        J.Field{"model", model_json(D.Model{profile, "default"})}, J.Field{"prompt", J.Text{prompt}}, J.Field{"retitle", J.Boolean{retitle}}]}

def board_text_outcome(ok: Bool, +body: J.Json) -> B.Outcome:
  match ok:
    case True{}: B.Suggested{J.text(J.get(body, "title")), J.text(J.get(body, "description"))}
    case False{}: B.SuggestionFailed{J.text(J.get(body, "message"))}

def board_text_payload(ok: Bool, +body: J.Json) -> Bool:
  match ok:
    case True{}: Shape.object_keys(body, ["kind", "card_id", "ticket", "ok", "title", "description"]) &&
      J.is_text(J.get(body, "title")) && J.is_text(J.get(body, "description"))
    case False{}: Shape.object_keys(body, ["kind", "card_id", "ticket", "ok", "message"]) &&
      J.is_text(J.get(body, "message")) && B.limited(J.text(J.get(body, "message")), 4096n)

def board_text_valid(valid: Bool, +body: J.Json) -> Result<&2, &2, String, F.Completion>:
  match valid:
    case False{}: Fail{"Malformed board drafting completion"}
    case True{}: Done{F.BoardTextCompleted{J.natural_or(J.natural(J.get(body, "card_id")), 0n), J.natural_or(J.natural(J.get(body, "ticket")), 0n),
      board_text_outcome(J.boolean(J.get(body, "ok")), body)}}

def chatgpt_completed(valid: Bool, +body: J.Json) -> Result<&2, &2, String, F.Completion>:
  match valid:
    case False{}: Fail{"Malformed ChatGPT operation completion"}
    case True{}: Done{F.ChatGPTCompleted{ChatGPTCodec.number(J.get(body, "operation_id")), J.get(body, "value"), J.boolean(J.get(body, "error"))}}

def compaction_completion(value: Result<&2, &2, String, CompactionResult.Completion>) -> Result<&2, &2, String, F.Completion>:
  match value:
    case Fail{message}: Fail{message}
    case Done{completion}: Done{F.CompactionCompleted{completion}}

def worktree_completion(value: Result<&2, &2, String, WorktreeModel.Completion>) -> Result<&2, &2, String, F.Completion>:
  match value:
    case Fail{message}: Fail{message}
    case Done{completion}: Done{F.WorktreeCompleted{completion}}

def completion(kind: String, +body: J.Json) -> Result<&2, &2, String, F.Completion>:
  match kind:
    case "worktree_created": worktree_completion(Worktree.completion(kind, body))
    case "worktree_archived": worktree_completion(Worktree.completion(kind, body))
    case "chatgpt_result": chatgpt_completed(Shape.object_keys(body, ["kind", "operation_id", "value", "error"]) &&
      Schema.valid(ChatGPTCodec.id_schema(), J.get(body, "operation_id")) && Shape.is_bool(J.get(body, "error")) && J.is_object(J.get(body, "value")), body)
    case "board_text":
      board_text_valid(Schema.valid(Board.integer_schema(), J.get(body, "card_id")) && Shape.is_natural(J.get(body, "ticket")) &&
        Shape.is_bool(J.get(body, "ok")) && board_text_payload(J.boolean(J.get(body, "ok")), body), body)
    case other: compaction_completion(Compaction.completion(other, body))

def compaction_json(state: F.State()) -> J.Json:
  Compaction.state_json(F.compaction(state))
