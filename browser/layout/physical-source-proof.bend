import Base
import ../../interaction/IDENTITY.bend as UIIdentity
import ../../bendlib/stdlib.bend as Std
import ./SOURCE.bend as Source
import ./CONTENT.bend as Content
import ./physical-content-rules.bend as ContentRules
import ./physical-source-rules.bend as Rule
import ./physical-space.bend as Model
import ../document/MODEL.bend as Doc
import ../document/SOURCE.bend as Authored
import ./SPACE.bend as Space
import ./enclosure.bend as Enclosure
import ../appearance/TYPOGRAPHY.bend as T

def field_native_footprint(+kind: Authored.NativeFieldKind, +node: Authored.Node, +key: String,
  +style: Authored.ResolvedStyle, +generation: Nat, +observations: +List<Content.Observation>) ->
  Rule.field_native_footprint(kind, node, key, style, generation, observations): {==}

def admitted(+duplicate: Maybe<&2, Content.NativeSlot>, +prepared: Content.Prepared,
  proof: {Content.duplicate_native_slot(Content.native_slots(prepared)) == duplicate : Maybe<&2, Content.NativeSlot>}) ->
  {ContentRules.ready_native_targets_valid(Source.admit_duplicate(duplicate, prepared)) == True{} : Bool}:
  match duplicate:
    case None{}:
      Std.transport(Maybe<&2, Content.NativeSlot>, None{},
        (result => {ContentRules.no_duplicate(result) == True{} : Bool}), {==},
        Content.duplicate_native_slot(Content.native_slots(prepared)), proof)
    case Some{Content.NativeSlot{owner_key, target_key}}:
      match prepared:
        case Content.Prepared{snapshot, tree, roots, policies}: {==}

def admission(+prepared: Content.Prepared) ->
  {ContentRules.ready_native_targets_valid(Source.admit_native_targets(prepared)) == True{} : Bool}:
  admitted(Content.duplicate_native_slot(Content.native_slots(prepared)), prepared, {==})

def single_root(trees: +List<Model.Tree<Content.Value, Doc.DOMEvent>>, +snapshot: Content.Snapshot,
  +roots: +List<Content.NativeRoot>, +policies: +List<Content.NativePolicy>) ->
  {ContentRules.ready_native_targets_valid(Source.single_root(trees, snapshot, roots, policies)) == True{} : Bool}:
  match trees:
    case Nil{}: {==}
    case Con{tree, Nil{}}: admission(Content.Prepared{snapshot, tree, roots, policies})
    case Con{tree, Con{next, rest}}: {==}

def preparation(result: Source.Forest, +snapshot: Content.Snapshot) ->
  {ContentRules.ready_native_targets_valid(Source.preparation(result, snapshot)) == True{} : Bool}:
  match result:
    case Source.ReadyForest{trees, roots, policies}: single_root(trees, snapshot, roots, policies)
    case Source.MissingForest{first, remaining}: {==}
    case Source.InvalidForest{error}: {==}

def native_targets(+snapshot: Content.Snapshot, +observations: +List<Content.Observation>) ->
  Rule.native_targets_claim(snapshot, observations):
  match snapshot:
    case Content.Snapshot{generation, source, default_font}:
      preparation(Source.prepare_forest(source <> Nil{}, default_font, generation, "", 0n, Source.Ordinary{}, observations), snapshot)

def field_width_formula(+capacity: Nat, +kind: Authored.NativeFieldKind, +policy: Authored.FieldPolicy, +font: T.Presentation, +observation: Content.Observation) ->
  {Rule.minimum_width(Source.field_natural_demand_at(capacity, kind, policy, font, observation)) == Nat.max(Rule.column_floor(policy, observation), Rule.observed_minimum(observation)) : Nat}:
  match policy:
    case Authored.FieldPolicy{+columns, +minimum_lines, +maximum_lines}:
      match observation:
        case Content.Observation{generation, key, purpose, +minimum, preferred, height, +advance}:
          {==}

def field_column_floor(+capacity: Nat, +kind: Authored.NativeFieldKind, +policy: Authored.FieldPolicy, +font: T.Presentation, +observation: Content.Observation) ->
  {Nat.is_ge(Rule.minimum_width(Source.field_natural_demand_at(capacity, kind, policy, font, observation)), Rule.column_floor(policy, observation)) == True{} : Bool}:
  match policy:
    case Authored.FieldPolicy{+columns, +minimum_lines, +maximum_lines}:
      match observation:
        case Content.Observation{generation, key, purpose, +minimum, preferred, height, +advance}:
          Nat.max_ge_l(Nat.mul(columns, advance), minimum)

def field_observed_minimum(+capacity: Nat, +kind: Authored.NativeFieldKind, +policy: Authored.FieldPolicy, +font: T.Presentation, +observation: Content.Observation) ->
  {Nat.is_ge(Rule.minimum_width(Source.field_natural_demand_at(capacity, kind, policy, font, observation)), Rule.observed_minimum(observation)) == True{} : Bool}:
  match policy:
    case Authored.FieldPolicy{+columns, +minimum_lines, +maximum_lines}:
      match observation:
        case Content.Observation{generation, key, purpose, +minimum, preferred, height, +advance}:
          Nat.max_ge_r(Nat.mul(columns, advance), minimum)

def field_preferred_width(+capacity: Nat, +kind: Authored.NativeFieldKind, +policy: Authored.FieldPolicy, +font: T.Presentation, +observation: Content.Observation) ->
  {Rule.preferred_width(Source.field_natural_demand_at(capacity, kind, policy, font, observation)) == Nat.max(Rule.minimum_width(Source.field_natural_demand_at(capacity, kind, policy, font, observation)), Rule.observed_preferred(observation)) : Nat}:
  match policy:
    case Authored.FieldPolicy{+columns, +minimum_lines, +maximum_lines}:
      match observation:
        case Content.Observation{generation, key, purpose, +minimum, preferred, height, +advance}:
          {==}

def field_minimum_height_fields(+capacity: Nat, +kind: Authored.NativeFieldKind, +font: T.Presentation, +columns: Nat, +minimum_lines: Nat, +maximum_lines: Nat, +generation: Nat, +key: String, +purpose: Content.Purpose, +minimum: Nat, +preferred: Nat, +height: Nat, +advance: Nat) ->
  {Rule.minimum_height(Source.field_natural_demand_at(capacity, kind, Authored.FieldPolicy{columns, minimum_lines, maximum_lines}, font, Content.Observation{generation, key, purpose, minimum, preferred, height, advance})) == Rule.expected_height(capacity, kind, Authored.FieldPolicy{columns, minimum_lines, maximum_lines}, font, Content.Observation{generation, key, purpose, minimum, preferred, height, advance}) : Nat}:
  match kind:
    case Authored.TextField{}: {==}
    case Authored.MessageField{}: {==}
    case Authored.TextAreaField{}: {==}
    case Authored.SelectField{}: {==}
    case Authored.MultiSelectField{}: {==}
    case Authored.ToggleField{}: {==}
    case Authored.NumberField{minimum}: {==}
    case Authored.FileField{multiple}: {==}
    case Authored.DirectoryField{}: {==}
    case Authored.SearchField{}: {==}
    case Authored.SecretField{}: {==}

def field_minimum_height(+capacity: Nat, +kind: Authored.NativeFieldKind, +policy: Authored.FieldPolicy, +font: T.Presentation, +observation: Content.Observation) ->
  {Rule.minimum_height(Source.field_natural_demand_at(capacity, kind, policy, font, observation)) == Rule.expected_height(capacity, kind, policy, font, observation) : Nat}:
  match policy:
    case Authored.FieldPolicy{+columns, +minimum_lines, +maximum_lines}:
      match observation:
        case Content.Observation{generation, key, purpose, +minimum, preferred, height, +advance}:
          field_minimum_height_fields(capacity, kind, font, columns, minimum_lines, maximum_lines, generation, key, purpose, minimum, preferred, height, advance)

def field_preferred_height_fields(+capacity: Nat, +kind: Authored.NativeFieldKind, +font: T.Presentation, +columns: Nat, +minimum_lines: Nat, +maximum_lines: Nat, +generation: Nat, +key: String, +purpose: Content.Purpose, +minimum: Nat, +preferred: Nat, +height: Nat, +advance: Nat) ->
  {Rule.preferred_height(Source.field_natural_demand_at(capacity, kind, Authored.FieldPolicy{columns, minimum_lines, maximum_lines}, font, Content.Observation{generation, key, purpose, minimum, preferred, height, advance})) == Rule.expected_height(capacity, kind, Authored.FieldPolicy{columns, minimum_lines, maximum_lines}, font, Content.Observation{generation, key, purpose, minimum, preferred, height, advance}) : Nat}:
  match kind:
    case Authored.TextField{}: {==}
    case Authored.MessageField{}: {==}
    case Authored.TextAreaField{}: {==}
    case Authored.SelectField{}: {==}
    case Authored.MultiSelectField{}: {==}
    case Authored.ToggleField{}: {==}
    case Authored.NumberField{minimum}: {==}
    case Authored.FileField{multiple}: {==}
    case Authored.DirectoryField{}: {==}
    case Authored.SearchField{}: {==}
    case Authored.SecretField{}: {==}

def field_preferred_height(+capacity: Nat, +kind: Authored.NativeFieldKind, +policy: Authored.FieldPolicy, +font: T.Presentation, +observation: Content.Observation) ->
  {Rule.preferred_height(Source.field_natural_demand_at(capacity, kind, policy, font, observation)) == Rule.expected_height(capacity, kind, policy, font, observation) : Nat}:
  match policy:
    case Authored.FieldPolicy{+columns, +minimum_lines, +maximum_lines}:
      match observation:
        case Content.Observation{generation, key, purpose, +minimum, preferred, height, +advance}:
          field_preferred_height_fields(capacity, kind, font, columns, minimum_lines, maximum_lines, generation, key, purpose, minimum, preferred, height, advance)

def field_production_demand(+capacity: Nat, +label: UIIdentity.Key, +kind: Authored.NativeFieldKind, +style: Authored.Style,
  +attributes: +List<Authored.Attribute>, +value: String, +placeholder: String, +options: +List<Authored.Choice>,
  +policy: Authored.FieldPolicy, +name: String, +enabled: Bool, +first_event: Doc.DOMEvent,
  +remaining_events: +List<Doc.DOMEvent>, +key: String, +font: T.Presentation, +rule: Model.Rule,
  +observation: Content.Observation, +roots: +List<Content.NativeRoot>, +policies: +List<Content.NativePolicy>) ->
  {Rule.first_leaf_demand(Source.observed_leaf_at(capacity, Authored.Field{label, kind, style, attributes, value, placeholder,
    options, policy, name, enabled, first_event, remaining_events}, key, font, rule, observation, roots, policies)) ==
    Some{Source.field_natural_demand_at(capacity, kind, policy, font, observation)} : Maybe<&2, Space.Demand>}:
  match policy:
    case Authored.FieldPolicy{columns, minimum_lines, maximum_lines}: {==}

def Rule.evidence():
  Rule.Requirements{field_native_footprint, +snapshot => +observations => native_targets(snapshot, observations),
    field_width_formula, field_column_floor, field_observed_minimum, field_preferred_width,
    field_minimum_height, field_preferred_height, field_production_demand}
