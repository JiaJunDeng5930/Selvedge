import Base
import ../IDENTITY.bend as Identity
import ./MODEL.bend as Receipt
import ../presentation/PROGRAM.bend as InterfaceView
import ../STATE.bend as Core
import ../conversation/MODEL.bend as Conversation
import ../../harness/DOMAIN.bend as D
import ../../bendlib/json.bend as J

def notice_claim(+ticket: Nat, +origin: String, +code: String, +message: String, +content: Core.Scene,
  +key: Identity.Key, +semantic: String, +label: String, +role: InterfaceView.Role,
  +conversation: Maybe<&2, Conversation.Identity>, +children: +List<InterfaceView.Node>,
  +rest: +List<InterfaceView.Node>, +overlays: +List<InterfaceView.Node>, +scope: Maybe<&2, String>) -> Type:
  {InterfaceView.with_receipt(InterfaceView.Surface{content, InterfaceView.Node{key, semantic, label, role, InterfaceView.PageContext{conversation}, children} <> rest, overlays, scope},
    Some{Receipt.Receipt{ticket, origin, code, message}}) ==
    InterfaceView.Surface{content, InterfaceView.Node{key, semantic, label, role, InterfaceView.PageContext{conversation},
      InterfaceView.Node{Identity.Entity{Identity.Place{"@browser"}, "receipt", Nat.show(ticket)}, "operation-receipt", "Operation failed", InterfaceView.Alert{}, InterfaceView.ReadOnly{code ++ ": " ++ message}, Nil{}} <> children} <> rest,
      overlays, scope} : InterfaceView.Surface}

type Requirements is Type:
  Requirements{
    failure: @+ticket:Nat -> @+origin:String -> @+code:String -> @+message:String ->
      {Receipt.from_reply(ticket, origin, D.failure(code, message)) == Some{Receipt.Receipt{ticket, origin, code, message}} : Maybe<&2, Receipt.Receipt>},
    unknown: @ticket:Nat -> @origin:String -> {Receipt.from_reply(ticket, origin, J.Null{}) == None{} : Maybe<&2, Receipt.Receipt>},
    success: @ticket:Nat -> @origin:String -> {Receipt.from_reply(ticket, origin, J.Object{[J.Field{"ok", J.Boolean{True{}}}]}) == None{} : Maybe<&2, Receipt.Receipt>},
    absent: @+surface:InterfaceView.Surface -> {InterfaceView.with_receipt(surface, None{}) == surface : InterfaceView.Surface},
    notice: @+ticket:Nat -> @+origin:String -> @+code:String -> @+message:String -> @+content:Core.Scene ->
      @+key: Identity.Key -> @+semantic:String -> @+label:String -> @+role:InterfaceView.Role -> @+conversation:Maybe<&2, Conversation.Identity> ->
      @+children:+List<InterfaceView.Node> -> @+rest:+List<InterfaceView.Node> -> @+overlays:+List<InterfaceView.Node> -> @+scope:Maybe<&2, String> ->
      notice_claim(ticket, origin, code, message, content, key, semantic, label, role, conversation, children, rest, overlays, scope)}

law evidence:
  Requirements
