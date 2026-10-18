import Base
import ../../bendlib/string-equality.bend as SafeText
import ../../bendlib/categories.bend as Categories
import ./CONTENT.bend as Content
import ../document/SOURCE.bend as Source
import ../../interaction/conversation/CODE.bend as Code

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
    case Source.RichText{key, style, Source.RichContent{source, value, policy}, attachments, native_owner}:
      content_height_valid(value, height)
    case Source.NativeAttachment{key, target, attributes, style, children}: False{}
    case Source.Box{key, tag, style, attributes, children}: False{}
    case Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: False{}
    case Source.Glyph{key, drawing, style}: False{}

# Natural Markdown probes omit the native interactive viewport. Only the actual
# prepared root owned by this request may account for a zero-height probe.
def interactive_target_belongs(target: Source.NativeTarget, source: Maybe<&2, Code.Source>) -> Bool:
  match target source:
    case Source.InteractiveTarget{identity} Some{owner}: Code.belongs(identity, owner)
    case Source.InteractiveTarget{identity} None{}: False{}
    case Source.ToolbarTarget{identity} _: False{}
    case Source.CodeBodyTarget{identity, wrap} _: False{}
    case Source.InteractiveSourceTarget{identity, exposed} _: False{}
    case Source.InteractiveFrameTarget{identity, active} _: False{}

def owned_interactive_root(roots: +List<Content.NativeRoot>, +key: String, +source: Maybe<&2, Code.Source>) -> Bool:
  match roots:
    case Nil{}: False{}
    case Con{Content.NativeRoot{owner_key, target, tree, attributes, style}, rest}:
      (String.eq(owner_key, key) && interactive_target_belongs(target, source)) || owned_interactive_root(rest, key, source)

def natural_ui_zero(node: Source.Node, +key: String, +roots: +List<Content.NativeRoot>, +height: Nat) -> Bool:
  match node:
    case Source.RichText{identity, style, Source.RichContent{source, value, policy}, attachments, native_owner}:
      owned_interactive_root(roots, key, source) && Nat.is_eq(height, 0n)
    case Source.NativeAttachment{identity, target, attributes, style, children}: False{}
    case Source.Box{identity, tag, style, attributes, children}: False{}
    case Source.Control{identity, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: False{}
    case Source.Text{identity, value, font, wrapping}: False{}
    case Source.Glyph{identity, drawing, style}: False{}
    case Source.Field{identity, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}: False{}

def zero_height_ui(purpose: Content.Purpose, +node: Source.Node, +key: String,
  +roots: +List<Content.NativeRoot>, +height: Nat) -> Bool:
  match purpose:
    case Content.Natural{}: natural_ui_zero(node, key, roots, height)
    case Content.AtWidth{width}: False{}

def request_observation_valid(request: Content.Request, +height: Nat, +advance: Nat) -> Bool:
  Content.Request{generation, key, Content.Value{+node, font}, purpose, native_roots, native_policies} = request
  primitive_observation_valid(node, height, advance) || zero_height_ui(purpose, node, key, native_roots, height)

type ReceiptPair is Data:
  ReceiptPair{request: Content.Request, observation: Content.Observation}

def receipt_guard(admitted: Bool, remainder: Unit -> Bool) -> Bool:
  match admitted:
    case False{}: False{}
    case True{}: remainder(Unit{})

def paired_receipt(pair: ReceiptPair) -> Bool:
  match pair:
    case ReceiptPair{Content.Request{+generation, +key, Content.Value{node, font}, +purpose, native_roots, native_policies},
      Content.Observation{observed_generation, observed_key, observed_purpose, minimum_width, preferred_width, content_height, reference_advance}}:
      receipt_guard(Nat.is_eq(generation, observed_generation), (_ =>
        receipt_guard(SafeText.string_equal(key, observed_key), (_ =>
          receipt_guard(same_purpose(purpose, observed_purpose), (_ =>
            receipt_guard(Nat.is_le(minimum_width, preferred_width), (_ =>
              request_observation_valid(Content.Request{generation, key, Content.Value{node, font}, purpose, native_roots, native_policies}, content_height, reference_advance)))))))))

def observation_matches(request: Content.Request, observation: Content.Observation) -> Bool:
  paired_receipt(ReceiptPair{request, observation})

def matching_receipt(-request: Content.Request) -> Content.Observation -> Type:
  Categories.holds(Content.Observation, observation => observation_matches(request, observation))

def choose_receipt(-request: Content.Request,
  member: Categories.Membership<Content.Observation, matching_receipt(request)>) -> Maybe<&2, Content.Observation>:
  Categories.Membership{observation, evidence} = member
  Some{observation}

def receipt_admission(-request: Content.Request,
  result: Maybe<&1, Categories.Membership<Content.Observation, matching_receipt(request)>>,
  fallback: Unit -> Maybe<&2, Content.Observation>) -> Maybe<&2, Content.Observation>:
  match result:
    case Some{member}: choose_receipt(request, member)
    case None{}: fallback(Unit{})

def scan(observations: +List<Content.Observation>, +request: Content.Request) -> Maybe<&2, Content.Observation>:
  match observations:
    case Nil{}: None{}
    case Con{+observation, rest}:
      receipt_admission(request, Categories.admit(Content.Observation, candidate => observation_matches(request, candidate), observation), (_ => scan(rest, request)))

def find(request: Content.Request, observations: +List<Content.Observation>) -> Maybe<&2, Content.Observation>:
  scan(observations, request)

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
