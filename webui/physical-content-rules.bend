import Base
import ./physical-content.bend as Content
import ./source.bend as Source

type PurposePair is Data:
  PurposePair{first: Content.Purpose, second: Content.Purpose}

def paired_purpose(pair: PurposePair) -> Bool:
  match pair:
    case PurposePair{Content.Natural{}, Content.Natural{}}: True{}
    case PurposePair{Content.AtWidth{first}, Content.AtWidth{second}}: Nat.is_eq(first, second)
    case PurposePair{Content.Natural{}, Content.AtWidth{width}}: False{}
    case PurposePair{Content.AtWidth{width}, Content.Natural{}}: False{}

def same_purpose(first: Content.Purpose, second: Content.Purpose) -> Bool:
  paired_purpose(PurposePair{first, second})

type OwnerPair is Data:
  OwnerPair{snapshot: Content.Snapshot, request: Content.Request}

def paired_owner(pair: OwnerPair) -> Bool:
  match pair:
    case OwnerPair{Content.Snapshot{generation, source, default_font},
      Content.Request{request_generation, key, value, purpose, native_roots, native_policies}}:
      Nat.is_eq(generation, request_generation)

def same_request_owner(snapshot: Content.Snapshot, request: Content.Request) -> Bool:
  paired_owner(OwnerPair{snapshot, request})

def content_height_valid(value: String, height: Nat) -> Bool:
  String.eq(value, "") || Nat.is_le(1n, height)

def primitive_observation_valid(node: Source.Node, +height: Nat, +advance: Nat) -> Bool:
  match node:
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}:
      Nat.is_le(1n, advance) && Nat.is_le(1n, height)
    case Source.Text{key, value, font, wrapping}: content_height_valid(value, height)
    case Source.RichText{key, style, Source.RichContent{source, value, policy}, attachments}:
      content_height_valid(value, height)
    case Source.NativeAttachment{key, target, attributes, style, children}: False{}
    case Source.Box{key, tag, style, attributes, children}: False{}
    case Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: False{}
    case Source.Glyph{key, drawing, style}: False{}

type ReceiptPair is Data:
  ReceiptPair{request: Content.Request, observation: Content.Observation}

def paired_receipt(pair: ReceiptPair) -> Bool:
  match pair:
    case ReceiptPair{Content.Request{generation, key, Content.Value{node, font}, purpose, native_roots, native_policies},
      Content.Observation{observed_generation, observed_key, observed_purpose, minimum_width, preferred_width, content_height, reference_advance}}:
      Nat.is_eq(generation, observed_generation) && String.eq(key, observed_key)
        && same_purpose(purpose, observed_purpose) && Nat.is_le(minimum_width, preferred_width)
        && primitive_observation_valid(node, content_height, reference_advance)

def observation_matches(request: Content.Request, observation: Content.Observation) -> Bool:
  paired_receipt(ReceiptPair{request, observation})


def no_duplicate(result: Maybe<&2, Content.NativeSlot>) -> Bool:
  match result:
    case None{}: True{}
    case Some{slot}: False{}

def native_targets_valid(prepared: Content.Prepared) -> Bool:
  no_duplicate(Content.duplicate_native_slot(Content.native_slots(prepared)))

def ready_native_targets_valid(result: Content.Preparation) -> Bool:
  match result:
    case Content.Ready{prepared}: native_targets_valid(prepared)
    case Content.NeedsMeasurements{snapshot, first, remaining}: True{}
    case Content.Invalid{snapshot, error}: True{}
