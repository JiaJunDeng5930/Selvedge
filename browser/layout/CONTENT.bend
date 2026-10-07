import Base
import ../../bendlib/stdlib.bend as Std
import ../document/SOURCE.bend as Source
import ../appearance/TYPOGRAPHY.bend as T
import ./physical-space.bend as SpaceModel
import ./PROGRAM.bend as Allocation
import ./GEOMETRY.bend as Spatial
import ./enclosure.bend as Enclosure
import ../document/MODEL.bend as Doc

type Value is Data:
  Value{node: Source.Node, font: T.Presentation}

def local_value(node: Source.Node, +font: T.Presentation) -> Value:
  match node:
    case Source.Box{key, tag, style, attributes, children}:
      Value{Source.Box{key, tag, style, attributes, Nil{}}, font}
    case Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}:
      Value{Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, Nil{}}, font}
    case Source.RichText{key, style, content, attachments, native_owner}:
      Value{Source.RichText{key, style, content, Nil{}, native_owner}, font}
    case Source.NativeAttachment{key, target, attributes, style, children}:
      Value{Source.NativeAttachment{key, target, attributes, style, Nil{}}, font}
    case Source.Text{key, value, choice, wrapping}:
      Value{Source.Text{key, value, choice, wrapping}, font}
    case Source.Glyph{key, drawing, style}:
      Value{Source.Glyph{key, drawing, style}, font}
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}:
      Value{Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}, font}

type Purpose is Data:
  Natural{}
  AtWidth{width: Nat}

# Receipts belong to this immutable visit; authored content and environment changes
# require a new generation before any previous observation can be reused.
type Snapshot is Data:
  Snapshot{generation: Nat, source: Source.Node, default_font: T.Presentation}

type NativeRoot is Data:
  NativeRoot{owner_key: String, target: Source.NativeTarget, tree: SpaceModel.Tree<Value, Doc.DOMEvent>,
    attributes: +List<Source.Attribute>, style: Source.ResolvedStyle}

type NativePolicy is Data:
  NativePolicy{owner_key: String, target: Source.NativeTarget,
    attributes: +List<Source.Attribute>, style: Source.ResolvedStyle}

# The key names the positional physical path within the snapshot, independently
# of authored labels. RichText alone carries its native roots and policies.
type Request is Data:
  Request{generation: Nat, key: String, value: Value, purpose: Purpose,
    native_roots: +List<NativeRoot>, native_policies: +List<NativePolicy>}

type Observation is Data:
  Observation{generation: Nat, key: String, purpose: Purpose, minimum_width: Nat,
    preferred_width: Nat, content_height: Nat, reference_advance: Nat}

type NativeViewport is Data:
  NativeViewport{generation: Nat, owner_key: String, purpose: Purpose, target: Source.NativeTarget, bounds: Spatial.Box}

type Prepared is Data:
  Prepared{snapshot: Snapshot, tree: SpaceModel.Tree<Value, Doc.DOMEvent>,
    native_roots: +List<NativeRoot>, native_policies: +List<NativePolicy>}

type NativeSlot is Data:
  NativeSlot{owner_key: String, target_key: String}

def root_slot(root: NativeRoot) -> NativeSlot:
  NativeRoot{owner_key, target, tree, attributes, style} = root
  NativeSlot{owner_key, Source.target_key(target)}

def policy_slot(policy: NativePolicy) -> NativeSlot:
  NativePolicy{owner_key, target, attributes, style} = policy
  NativeSlot{owner_key, Source.target_key(target)}

def native_slots(prepared: Prepared) -> +List<NativeSlot>:
  Prepared{snapshot, tree, roots, policies} = prepared
  List.append(&2, NativeSlot, Std.map(~NativeRoot, ~NativeSlot, ~root_slot, roots),
    Std.map(~NativePolicy, ~NativeSlot, ~policy_slot, policies))

def slot_member(slots: +List<NativeSlot>, +owner: String, +target: String) -> Bool:
  match slots:
    case Nil{}: False{}
    case Con{NativeSlot{slot_owner, slot_target}, rest}:
      (String.eq(slot_owner, owner) && String.eq(slot_target, target)) || slot_member(rest, owner, target)

def duplicate_member(found: Bool, slot: NativeSlot, remaining: Maybe<&2, NativeSlot>) -> Maybe<&2, NativeSlot>:
  match found:
    case True{}: Some{slot}
    case False{}: remaining

def duplicate_native_slot(slots: +List<NativeSlot>) -> Maybe<&2, NativeSlot>:
  match slots:
    case Nil{}: None{}
    case Con{NativeSlot{+owner, +target}, +rest}:
      duplicate_member(slot_member(rest, owner, target), NativeSlot{owner, target}, duplicate_native_slot(rest))

type Error is Data:
  DuplicateNativeTarget{owner_key: String, target_key: String}
  InvalidDrawing{key: String}
  InvalidFieldPolicy{key: String}
  InvalidNativeOwner{key: String}
  InvalidNativeChild{key: String}
  InvalidNativeContentChildren{key: String}
  InvalidObservation{key: String}

type Preparation is Data:
  Ready{prepared: Prepared}
  NeedsMeasurements{snapshot: Snapshot, first: Request, remaining: +List<Request>}
  Invalid{snapshot: Snapshot, error: Error}

type AllocatedNative is Data:
  AllocatedNative{owner_key: String, target: Source.NativeTarget,
    tree: Allocation.AllocatedTree<Value, Doc.DOMEvent>}

type AllocatedWorld is Data:
  AllocatedWorld{snapshot: Snapshot, tree: Allocation.AllocatedTree<Value, Doc.DOMEvent>,
    native_roots: +List<AllocatedNative>, native_policies: +List<NativePolicy>}
