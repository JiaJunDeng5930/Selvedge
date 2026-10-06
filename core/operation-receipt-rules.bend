import Base
import ./ui-identity.bend as Identity
import ./operation-receipt.bend as Receipt
import ./interface.bend as UI
import ./SYSTEM.bend as Core
import ./user-conversation.bend as Conversation
import ../bendlib/domain.bend as D
import ../bendlib/json.bend as J

def notice_claim(+ticket: Nat, +origin: String, +code: String, +message: String, +content: Core.Scene,
  +key: Identity.Key, +semantic: String, +label: String, +role: UI.Role,
  +conversation: Maybe<&2, Conversation.Identity>, +children: +List<UI.Node>,
  +rest: +List<UI.Node>, +overlays: +List<UI.Node>, +scope: Maybe<&2, String>) -> Type:
  {UI.with_receipt(UI.Surface{content, UI.Node{key, semantic, label, role, UI.PageContext{conversation}, children} <> rest, overlays, scope},
    Some{Receipt.Receipt{ticket, origin, code, message}}) ==
    UI.Surface{content, UI.Node{key, semantic, label, role, UI.PageContext{conversation},
      UI.Node{Identity.Entity{Identity.Place{"@browser"}, "receipt", Nat.show(ticket)}, "operation-receipt", "Operation failed", UI.Alert{}, UI.ReadOnly{code ++ ": " ++ message}, Nil{}} <> children} <> rest,
      overlays, scope} : UI.Surface}

type Requirements is Type:
  Requirements{
    failure: @+ticket:Nat -> @+origin:String -> @+code:String -> @+message:String ->
      {Receipt.from_reply(ticket, origin, D.failure(code, message)) == Some{Receipt.Receipt{ticket, origin, code, message}} : Maybe<&2, Receipt.Receipt>},
    unknown: @ticket:Nat -> @origin:String -> {Receipt.from_reply(ticket, origin, J.Null{}) == None{} : Maybe<&2, Receipt.Receipt>},
    success: @ticket:Nat -> @origin:String -> {Receipt.from_reply(ticket, origin, J.Object{[J.Field{"ok", J.Boolean{True{}}}]}) == None{} : Maybe<&2, Receipt.Receipt>},
    absent: @+surface:UI.Surface -> {UI.with_receipt(surface, None{}) == surface : UI.Surface},
    notice: @+ticket:Nat -> @+origin:String -> @+code:String -> @+message:String -> @+content:Core.Scene ->
      @+key: Identity.Key -> @+semantic:String -> @+label:String -> @+role:UI.Role -> @+conversation:Maybe<&2, Conversation.Identity> ->
      @+children:+List<UI.Node> -> @+rest:+List<UI.Node> -> @+overlays:+List<UI.Node> -> @+scope:Maybe<&2, String> ->
      notice_claim(ticket, origin, code, message, content, key, semantic, label, role, conversation, children, rest, overlays, scope)}

law evidence:
  Requirements
