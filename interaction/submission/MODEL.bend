import Base
import ../../bendlib/json.bend as J

type Receipt is Data:
  Receipt{ticket: Nat, origin: String, code: String, message: String}

def from_reply_fields(ok: J.Json, code: J.Json, message: J.Json, ticket: Nat, origin: String) -> Maybe<&2, Receipt>:
  match ok code message:
    case J.Boolean{False{}} J.Text{code} J.Text{message}: Some{Receipt{ticket, origin, code, message}}
    case _ _ _: None{}

def from_reply(ticket: Nat, origin: String, +reply: J.Json) -> Maybe<&2, Receipt>:
  from_reply_fields(J.get(reply, "ok"), J.get(J.get(reply, "error"), "code"),
    J.get(J.get(reply, "error"), "message"), ticket, origin)
