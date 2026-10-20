import Base
import ../../bendlib/string-equality.bend as SafeText
import ../../bendlib/categories.bend as Categories
import ../../interaction/IDENTITY.bend as UIIdentity
import ../document/SOURCE.bend as Source
import ../controls/CONTROLS.bend as Controls
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/INPUT.bend as U
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes
import ../../interaction/interactive_markdown/TYPES.bend as Interactive
import ../../interaction/interactive_markdown/SCENE.bend as InteractiveScene
import ../../interaction/interactive_markdown/SYNTAX.bend as InteractiveSyntax

type Binding is Data:
  Binding{key: String, kind: Source.NativeFieldKind, semantic: String, meaning: SurfaceTypes.Meaning}

type Basis is Data:
  Basis{fields: +List<Binding>, controls: +List<String>}

type Identity is Data:
  Identity{key: String, semantic: String, meaning: SurfaceTypes.Meaning}

type Update is Data:
  SetIdentity{key: String, identity: Identity}
  SetValue{key: String, value: String}
  SetChecked{key: String, checked: Bool}
  SetEnabled{key: String, enabled: Bool}

type Session is Data:
  Idle{}
  Composing{}
  SupersededComposing{}
  SupersededTail{}

type Record is Data:
  Record{identity: Maybe<&2, Identity>, canonical: Maybe<&2, String>, session: Session}

type FieldEvent is Data:
  Rebind{identity: Identity}
  Synchronize{value: String}
  Reject{value: String}
  CompositionStarted{}
  CompositionEnded{}
  InputStarted{}
  InputObserved{}

type Decision is Data:
  Decision{record: Record, deliver: Bool, replace: Bool}

def initial() -> Record: Record{None{}, None{}, Idle{}}

def canonical_same(old: Maybe<&2, String>, value: String) -> Bool:
  match old:
    case None{}: False{}
    case Some{previous}: SafeText.string_equal(previous, value)

def supersede(session: Session) -> Session:
  match session:
    case Idle{}: Idle{}
    case Composing{}: SupersededComposing{}
    case SupersededComposing{}: SupersededComposing{}
    case SupersededTail{}: SupersededTail{}

def rebind_session(session: Session) -> Session:
  match session:
    case Composing{}: SupersededComposing{}
    case _: SupersededTail{}

def same_meaning(original: SurfaceTypes.Meaning, current: SurfaceTypes.Meaning) -> Bool:
  match original current:
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{identity, occurrence, tag, attrs, Interactive.FieldBinding{state_id, schema, raw, canonical, validation, enabled}, children}} SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{other_identity, other_occurrence, other_tag, other_attrs, Interactive.FieldBinding{other_state, other_schema, other_raw, other_canonical, other_validation, other_enabled}, other_children}}:
      UIIdentity.same(InteractiveScene.key(identity), InteractiveScene.key(other_identity)) && Nat.is_eq(occurrence, other_occurrence) && String.eq(state_id, other_state) && String.eq(tag, other_tag) && InteractiveSyntax.same_schema(schema, other_schema)
    case SurfaceTypes.Edit{editor, field, entry, value, choices} SurfaceTypes.Edit{other, new_field, new_entry, new_value, new_choices}: U.same_editor(editor, other)
    case SurfaceTypes.EnterDirectory{editor, text} SurfaceTypes.EnterDirectory{other, new_text}: U.same_editor(editor, other)
    case SurfaceTypes.ReceiveFile{editor, enabled} SurfaceTypes.ReceiveFile{other, new_enabled}: U.same_editor(editor, other)
    case SurfaceTypes.HistorySearchQuery{query} SurfaceTypes.HistorySearchQuery{new_query}: True{}
    case SurfaceTypes.HistorySearchScope{+project, value, choices} SurfaceTypes.HistorySearchScope{+new_project, new_value, new_choices}: (project && new_project) || (Bool.not(project) && Bool.not(new_project))
    case SurfaceTypes.SearchChoices{query} SurfaceTypes.SearchChoices{new_query}: True{}
    case SurfaceTypes.BoardSearch{filter} SurfaceTypes.BoardSearch{new_filter}: True{}
    case SurfaceTypes.DirectoryBrowserLocation{value} SurfaceTypes.DirectoryBrowserLocation{new_value}: True{}
    case SurfaceTypes.BoardProfile{automatic, selected, choices, enabled} SurfaceTypes.BoardProfile{new_automatic, new_selected, new_choices, new_enabled}: True{}
    case _ _: False{}

def same_identity(original: Identity, current: Identity) -> Bool:
  Identity{key, semantic, meaning} = original
  Identity{other_key, other_semantic, other_meaning} = current
  (SafeText.string_equal(key, other_key) && SafeText.string_equal(semantic, other_semantic)) && same_meaning(meaning, other_meaning)

def rebound(same: Bool, +identity: Identity, record: Record) -> Decision:
  match same:
    case True{}: Decision{record, False{}, False{}}
    case False{}:
      Record{old, canonical, session} = record
      Decision{Record{Some{identity}, canonical, rebind_session(session)}, False{}, True{}}

def rebind_existing(old: Maybe<&2, Identity>, +identity: Identity, +canonical: Maybe<&2, String>, +session: Session) -> Decision:
  match old:
    case None{}: Decision{Record{Some{identity}, canonical, session}, False{}, False{}}
    case Some{+previous}: rebound(same_identity(previous, identity), identity, Record{Some{previous}, canonical, session})

def rebind_record(record: Record, identity: Identity) -> Decision:
  Record{old, canonical, session} = record
  rebind_existing(old, identity, canonical, session)

def synchronized(same: Bool, value: String, record: Record) -> Decision:
  match same:
    case True{}: Decision{record, False{}, False{}}
    case False{}:
      Record{identity, old, session} = record
      Decision{Record{identity, Some{value}, supersede(session)}, False{}, True{}}

def synchronize_record(+record: Record, +value: String) -> Decision:
  Record{identity, +canonical, session} = record
  synchronized(canonical_same(canonical, value), value, record)

def ended(session: Session, +identity: Maybe<&2, Identity>, +canonical: Maybe<&2, String>) -> Decision:
  match session:
    case Idle{}: Decision{Record{identity, canonical, Idle{}}, True{}, False{}}
    case Composing{}: Decision{Record{identity, canonical, Idle{}}, True{}, False{}}
    # DEFENSE: A canonical update or field rebind can supersede the native composition before compositionend arrives.
    case SupersededComposing{}: Decision{Record{identity, canonical, SupersededTail{}}, False{}, True{}}
    # DEFENSE: Browsers can emit a trailing input/change event after a superseded composition; retain the current canonical value.
    case SupersededTail{}: Decision{Record{identity, canonical, SupersededTail{}}, False{}, True{}}

def observed(session: Session, +identity: Maybe<&2, Identity>, +canonical: Maybe<&2, String>) -> Decision:
  match session:
    case Idle{}: Decision{Record{identity, canonical, Idle{}}, True{}, False{}}
    case Composing{}: Decision{Record{identity, canonical, Composing{}}, False{}, False{}}
    case SupersededComposing{}: Decision{Record{identity, canonical, SupersededComposing{}}, False{}, True{}}
    # DEFENSE: Browsers can emit a trailing input/change event after a superseded composition; retain the current canonical value.
    case SupersededTail{}: Decision{Record{identity, canonical, SupersededTail{}}, False{}, True{}}

def step(event: FieldEvent, record: Record) -> Decision:
  match event:
    case Rebind{identity}: rebind_record(record, identity)
    case Synchronize{value}: synchronize_record(record, value)
    case Reject{value}:
      Record{identity, canonical, session} = record
      Decision{Record{identity, Some{value}, supersede(session)}, False{}, True{}}
    case CompositionStarted{}:
      Record{identity, canonical, session} = record
      Decision{Record{identity, canonical, Composing{}}, False{}, False{}}
    case CompositionEnded{}:
      Record{identity, canonical, session} = record
      ended(session, identity, canonical)
    case InputStarted{}:
      Record{identity, canonical, session} = record
      Decision{Record{identity, canonical, Idle{}}, False{}, False{}}
    case InputObserved{}:
      Record{identity, canonical, session} = record
      observed(session, identity, canonical)

def forest(surface: SurfaceTypes.Surface) -> +List<SurfaceTypes.Node>:
  SurfaceTypes.Surface{content, base, overlays, scope} = surface
  List.append(&2, SurfaceTypes.Node, base, overlays)

def editing(meaning: SurfaceTypes.Meaning) -> Bool:
  match meaning:
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{identity, occurrence, tag, attrs, Interactive.FieldBinding{state_id, schema, raw, canonical, validation, enabled}, children}}: True{}
    case SurfaceTypes.Edit{editor, field, entry, value, choices}: True{}
    case SurfaceTypes.HistorySearchQuery{query}: True{}
    case SurfaceTypes.HistorySearchScope{project, value, choices}: True{}
    case SurfaceTypes.SearchChoices{query}: True{}
    case SurfaceTypes.ReceiveFile{editor, enabled}: True{}
    case SurfaceTypes.EnterDirectory{editor, text}: True{}
    case SurfaceTypes.BoardSearch{filter}: True{}
    case SurfaceTypes.DirectoryBrowserLocation{value}: True{}
    case SurfaceTypes.BoardProfile{automatic, selected, choices, enabled}: True{}
    case _: False{}

def found_editing(editable: Bool, key: String, kind: Source.NativeFieldKind, semantic: String, meaning: SurfaceTypes.Meaning) -> +List<Binding>:
  match editable:
    case False{}: Nil{}
    case True{}: [Binding{key, kind, semantic, meaning}]

def found_binding(key: String, kind: Source.NativeFieldKind, found: Maybe<&2, SurfaceTypes.Node>) -> +List<Binding>:
  match found:
    case None{}: Nil{}
    case Some{SurfaceTypes.Node{current, semantic, label, role, +meaning, children}}:
      found_editing(editing(meaning), key, kind, semantic, meaning)

def merge(first: Basis, second: Basis) -> Basis:
  Basis{fields, controls} = first
  Basis{later_fields, later_controls} = second
  Basis{List.append(&2, Binding, fields, later_fields), List.append(&2, String, controls, later_controls)}

def collect(nodes: +List<Source.Node>, +semantic: +List<SurfaceTypes.Node>) -> Basis:
  match nodes:
    case Nil{}: Basis{Nil{}, Nil{}}
    case Con{Source.Box{key, tag, style, attrs, children}, rest}: merge(collect(children, semantic), collect(rest, semantic))
    case Con{Source.Control{key, tag, style, attrs, name, enabled, first, remaining, children}, rest}:
      merge(Basis{Nil{}, [UIIdentity.encode(key)]}, merge(collect(children, semantic), collect(rest, semantic)))
    case Con{Source.NativeAttachment{key, target, attrs, style, children}, rest}: merge(collect(children, semantic), collect(rest, semantic))
    case Con{Source.Field{+key, kind, style, attrs, value, placeholder, options, policy, name, enabled, first, remaining}, rest}:
      merge(Basis{found_binding(UIIdentity.encode(key), kind, InterfaceView.find_node(semantic, UIIdentity.encode(key))), [UIIdentity.encode(key)]}, collect(rest, semantic))
    case Con{Source.RichText{key, style, content, attachments, native_owner}, rest}: merge(collect(attachments, semantic), collect(rest, semantic))
    case Con{Source.Text{key, value, font, wrapping}, rest}: collect(rest, semantic)
    case Con{Source.Glyph{key, drawing, style}, rest}: collect(rest, semantic)

def basis(source: +List<Source.Node>, semantic: SurfaceTypes.Surface) -> Basis: collect(source, forest(semantic))

def owned_found(found: Maybe<&2, SurfaceTypes.Node>, binding: Binding) -> Bool:
  match found:
    case None{}: False{}
    case Some{SurfaceTypes.Node{current, identity, label, role, meaning, children}}:
      Binding{key, kind, semantic, original} = binding
      (SafeText.string_equal(key, UIIdentity.encode(current)) && SafeText.string_equal(semantic, identity)) && same_meaning(original, meaning)

def owned_node(binding: Binding, found: Maybe<&2, SurfaceTypes.Node>) -> Bool: owned_found(found, binding)

def projected_kind(kind: Source.NativeFieldKind, +key: String, +semantic: String, +meaning: SurfaceTypes.Meaning) -> +List<Update>:
  match kind:
    case Source.ToggleField{}: [SetIdentity{key, Identity{key, semantic, meaning}}, SetChecked{key, Controls.field_checked(meaning)}]
    case Source.FileField{multiple}: [SetIdentity{key, Identity{key, semantic, meaning}}]
    case _: [SetIdentity{key, Identity{key, semantic, meaning}}, SetValue{key, Controls.node_value(meaning)}]

def projected(key: String, kind: Source.NativeFieldKind, semantic: String, meaning: SurfaceTypes.Meaning) -> +List<Update>:
  projected_kind(kind, key, semantic, meaning)

def update_found(found: Maybe<&2, SurfaceTypes.Node>, binding: Binding) -> +List<Update>:
  match found:
    case None{}: Nil{}
    case Some{SurfaceTypes.Node{current, semantic, label, role, meaning, children}}:
      Binding{key, kind, identity, original} = binding
      projected(key, kind, semantic, meaning)

type UpdateCandidate is Data:
  UpdateCandidate{binding: Binding, found: Maybe<&2, SurfaceTypes.Node>}

def update_predicate(candidate: UpdateCandidate) -> Bool:
  UpdateCandidate{binding, found} = candidate
  owned_node(binding, found)

def update_category() -> UpdateCandidate -> Type: Categories.holds(UpdateCandidate, update_predicate)

def update_owned(member: Categories.Membership<UpdateCandidate, update_category()>) -> +List<Update>:
  Categories.Membership{candidate, evidence} = member
  UpdateCandidate{binding, found} = candidate
  update_found(found, binding)

def update_admitted(admission: Maybe<&1, Categories.Membership<UpdateCandidate, update_category()>>) -> +List<Update>:
  match admission:
    case None{}: Nil{}
    case Some{member}: update_owned(member)

def update(+binding: Binding, +nodes: +List<SurfaceTypes.Node>) -> +List<Update>:
  Binding{+key, kind, semantic, meaning} = binding
  +found = InterfaceView.find_node(nodes, key)
  update_admitted(Categories.admit(UpdateCandidate, update_predicate, UpdateCandidate{binding, found}))

def updates_fields(fields: +List<Binding>, +nodes: +List<SurfaceTypes.Node>) -> +List<Update>:
  match fields:
    case Nil{}: Nil{}
    case Con{binding, rest}: List.append(&2, Update, update(binding, nodes), updates_fields(rest, nodes))

def updates(basis: Basis, surface: SurfaceTypes.Surface) -> +List<Update>:
  Basis{fields, controls} = basis
  updates_fields(fields, forest(surface))

def fields_owned(fields: +List<Binding>, +key: String, +nodes: +List<SurfaceTypes.Node>) -> Bool:
  match fields:
    case Nil{}: False{}
    case Con{+binding, rest}:
      Binding{current, kind, semantic, meaning} = binding
      (SafeText.string_equal(current, key) && owned_node(binding, InterfaceView.find_node(nodes, key))) || fields_owned(rest, key, nodes)

def field_owned(basis: Basis, key: String, surface: SurfaceTypes.Surface) -> Bool:
  Basis{fields, controls} = basis
  fields_owned(fields, key, forest(surface))

def key_present(keys: +List<String>, +key: String) -> Bool:
  match keys:
    case Nil{}: False{}
    case Con{current, rest}: SafeText.string_equal(current, key) || key_present(rest, key)

def control_owned(basis: Basis, key: String) -> Bool:
  Basis{fields, controls} = basis
  key_present(controls, key)

def record_canonical(record: Record) -> Maybe<&2, String>:
  Record{identity, canonical, session} = record
  canonical

type NamedSemanticNode is Data:
  NamedSemanticNode{encoded: String, original: SurfaceTypes.Node, children: +List<NamedSemanticNode>}

def prepare_named(nodes: +List<SurfaceTypes.Node>) -> +List<NamedSemanticNode>:
  match nodes:
    case Nil{}: Nil{}
    case Con{+node, rest}:
      SurfaceTypes.Node{key, semantic, label, role, meaning, children} = node
      NamedSemanticNode{UIIdentity.encode(key), node, prepare_named(children)} <> prepare_named(rest)

def find_named_fallback(found: Maybe<&2, SurfaceTypes.Node>, fallback: Unit -> Maybe<&2, SurfaceTypes.Node>) -> Maybe<&2, SurfaceTypes.Node>:
  match found:
    case Some{node}: Some{node}
    case None{}: fallback(Unit{})

def find_named_match(same: Bool, node: SurfaceTypes.Node,
  descendants: Unit -> Maybe<&2, SurfaceTypes.Node>, siblings: Unit -> Maybe<&2, SurfaceTypes.Node>) -> Maybe<&2, SurfaceTypes.Node>:
  match same:
    case True{}: Some{node}
    case False{}: find_named_fallback(descendants(Unit{}), siblings)

def find_named(nodes: +List<NamedSemanticNode>, +key: String) -> Maybe<&2, SurfaceTypes.Node>:
  match nodes:
    case Nil{}: None{}
    case Con{NamedSemanticNode{encoded, node, children}, rest}:
      find_named_match(SafeText.string_equal(encoded, key), node,
        (_ => find_named(children, key)), (_ => find_named(rest, key)))

def update_named(+binding: Binding, +nodes: +List<NamedSemanticNode>) -> +List<Update>:
  Binding{+key, kind, semantic, meaning} = binding
  +found = find_named(nodes, key)
  update_admitted(Categories.admit(UpdateCandidate, update_predicate, UpdateCandidate{binding, found}))

def updates_fields_named(fields: +List<Binding>, +nodes: +List<NamedSemanticNode>) -> +List<Update>:
  match fields:
    case Nil{}: Nil{}
    case Con{binding, rest}:
      List.append(&2, Update, update_named(binding, nodes), updates_fields_named(rest, nodes))

def fields_many(fields: +List<Binding>) -> Bool:
  match fields:
    case Con{first, Con{second, rest}}: True{}
    case _: False{}
