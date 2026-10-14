import Base
import ../../interaction/IDENTITY.bend as Identity
import ../../interaction/presentation/SURFACE.bend as Surface
import ../../interaction/presentation/MODEL.bend as View

# Physical interest belongs to presentation, independently of domain selection.
type Attention is Data:
  Attention{hovered: Maybe<&2, String>, focused: Maybe<&2, String>, hover_capable: Bool}

def initial() -> Attention:
  Attention{None{}, None{}, False{}}

def owns(interest: Maybe<&2, String>, owner: String) -> Bool:
  match interest:
    case None{}: False{}
    case Some{actual}: String.eq(actual, owner)

def same_owner(first: Maybe<&2, String>, second: Maybe<&2, String>) -> Bool:
  match first second:
    case None{} None{}: True{}
    case Some{left} Some{right}: String.eq(left, right)
    case _ _: False{}

def same(first: Attention, second: Attention) -> Bool:
  Attention{hovered, focused, +capable} = first
  Attention{next_hovered, next_focused, +next_capable} = second
  same_owner(hovered, next_hovered) && same_owner(focused, next_focused) && ((capable && next_capable) || (Bool.not(capable) && Bool.not(next_capable)))

def row(meaning: Surface.Meaning) -> Bool:
  match meaning:
    case Surface.ProjectGroup{project, selected, expanded}: True{}
    case Surface.TaskRow{task, status, selected}: True{}
    case _: False{}

def declares(nodes: +List<Surface.Node>, +owner: String) -> Bool:
  match nodes:
    case Nil{}: False{}
    case Con{Surface.Node{+key, semantic, label, role, +meaning, children}, rest}:
      (row(meaning) && String.eq(Identity.encode(key), owner)) || declares(children, owner) || declares(rest, owner)

def admitted(owner: Maybe<&2, String>, nodes: +List<Surface.Node>) -> Bool:
  match owner:
    case None{}: True{}
    case Some{value}: declares(nodes, value)

def descend(meaning: Surface.Meaning, depth: Nat) -> Nat:
  match meaning:
    case Surface.ProjectGroup{project, selected, expanded}: (depth + 1n : Nat)
    case _: depth

def menu_owned(layers: +List<View.Layer>, +create: String, +more: String) -> Bool:
  match layers:
    case Nil{}: False{}
    case Con{View.Layer{kind, content, initial, +trigger, dismissal}, rest}:
      String.eq(trigger, create) || String.eq(trigger, more) || menu_owned(rest, create, more)

def feedback_active(attention: Attention, +owner: String, menu: Bool) -> Bool:
  Attention{hovered, focused, capable} = attention
  owns(hovered, owner) || owns(focused, owner) || menu

def revealed(attention: Attention, +owner: String, menu: Bool) -> Bool:
  Attention{hovered, focused, capable} = attention
  Bool.not(capable) || owns(hovered, owner) || owns(focused, owner) || menu

type ContentRole is Data:
  DisclosureSlot{}
  IdentitySlot{}
  TitleSlot{}
  StatusSlot{}
  AuxiliarySlot{}

def role_name(value: ContentRole) -> String:
  match value:
    case DisclosureSlot{}: "disclosure"
    case IdentitySlot{}: "identity"
    case TitleSlot{}: "title"
    case StatusSlot{}: "status"
    case AuxiliarySlot{}: "auxiliary"
