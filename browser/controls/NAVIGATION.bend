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
    case Surface.TaskChildren{task}: (depth + 1n : Nat)
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

def auxiliary_exposed(attention: Attention, owner: String, menu: Bool, selected: Bool) -> Bool:
  selected || revealed(attention, owner, menu)

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

# A visual rail and its independent command target share a center, not a width.
# The target's trailing clearance is paid from the visual-to-title gap once.
type LeadingGeometry is Data:
  LeadingGeometry{visual: Nat, target: Nat, allocation: Nat, before: Nat, after: Nat, following: Nat}

def leading_geometry(+visual: Nat, +target: Nat, gap: Nat) -> LeadingGeometry:
  +allocation: Nat = Nat.max(visual, target)
  +before: Nat = Nat.div(Nat.sub(allocation, visual), 2n)
  +after: Nat = Nat.sub(Nat.sub(allocation, visual), before)
  LeadingGeometry{visual, target, allocation, before, after, Nat.sub(gap, after)}

def leading_allocation(geometry: LeadingGeometry) -> Nat:
  LeadingGeometry{visual, target, allocation, before, after, following} = geometry
  allocation

def following_gap(geometry: LeadingGeometry) -> Nat:
  LeadingGeometry{visual, target, allocation, before, after, following} = geometry
  following


law auxiliary_exposure_uses_selection_and_owner_attention:
  @+hovered:Maybe<&2, String> -> @+focused:Maybe<&2, String> -> @+capable:Bool -> @+owner:String -> @+menu:Bool -> @+selected:Bool ->
    {auxiliary_exposed(Attention{hovered, focused, capable}, owner, menu, selected) == (selected || (Bool.not(capable) || owns(hovered, owner) || owns(focused, owner) || menu)) : Bool}

law selected_owner_exposes_auxiliary:
  @attention:Attention -> @owner:String -> @menu:Bool ->
    {auxiliary_exposed(attention, owner, menu, True{}) == True{} : Bool}

law unselected_owner_uses_existing_exposure:
  @+attention:Attention -> @+owner:String -> @+menu:Bool ->
    {auxiliary_exposed(attention, owner, menu, False{}) == revealed(attention, owner, menu) : Bool}
