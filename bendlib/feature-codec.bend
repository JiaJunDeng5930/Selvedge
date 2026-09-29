import Base
import ../FEATURES.bend as F
import ../MODEL.bend as M
import ../BOARD.bend as B
import ./domain.bend as D
import ./json.bend as J
import ./schema.bend as Schema
import ./wire-shape.bend as Shape
import ./board-codec.bend as Board

def command_json(command: F.Command) -> J.Json:
  match command:
    case F.BoardCommand{command}: Board.command_json(command)

def query_json(query: F.Query) -> J.Json:
  match query:
    case F.BoardQuery{query}: Board.query_json(query)

def board_command(kind: Board.EntryKind, body: J.Json) -> M.Command:
  match kind:
    case Board.Write{kind}: M.FeatureCommand{F.BoardCommand{Board.construct(kind, body)}}
    case Board.Read{kind}: M.Observe{M.FeatureQuery{F.BoardQuery{Board.query(kind, body)}}}

def construct(kind: F.CommandKind, body: J.Json) -> M.Command:
  match kind:
    case F.BoardKind{kind}: board_command(kind, body)

def valid(kind: F.CommandKind, body: J.Json) -> Bool:
  match kind:
    case F.BoardKind{kind}: Board.valid(kind, body)

def effect_json(model_json: D.Model -> J.Json, effect: F.Effect) -> J.Json:
  match effect:
    case F.RequestBoardText{card_id, ticket, profile, prompt, retitle}:
      J.Object{[J.Field{"kind", J.Text{"board_text"}}, J.Field{"card_id", J.nat(card_id)}, J.Field{"ticket", J.nat(ticket)},
        J.Field{"model", model_json(D.Model{profile, "default", D.NoProject{}})}, J.Field{"prompt", J.Text{prompt}}, J.Field{"retitle", J.Boolean{retitle}}]}

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

def completion(kind: String, +body: J.Json) -> Result<&2, &2, String, F.Completion>:
  match kind:
    case "board_text":
      board_text_valid(Schema.valid(Board.integer_schema(), J.get(body, "card_id")) && Shape.is_natural(J.get(body, "ticket")) &&
        Shape.is_bool(J.get(body, "ok")) && board_text_payload(J.boolean(J.get(body, "ok")), body), body)
    case _: Fail{"Unknown input envelope"}
