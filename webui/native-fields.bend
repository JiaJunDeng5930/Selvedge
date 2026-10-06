import Base
import ../core/ui-identity.bend as UIIdentity
import ./source.bend as Source
import ./authored-controls.bend as Controls
import ../core/interface.bend as UI
import ../core/user-input.bend as U

type Binding is Data:
  Binding{key: String, kind: Source.NativeFieldKind, semantic: String, meaning: UI.Meaning}
type Basis is Data:
  Basis{fields: +List<Binding>, controls: +List<String>}
type Identity is Data:
  Identity{key: String, semantic: String, meaning: UI.Meaning}
type Update is Data:
  SetIdentity{key: String, identity: Identity}
  SetValue{key: String, value: String}
  SetChecked{key: String, checked: Bool}
type Session is Data:
  Idle{}
  Composing{}
  SupersededComposing{}
  SupersededTail{}
type Record is Data:
  Record{identity: Maybe<&2, Identity>, canonical: Maybe<&2, String>, session: Session}
type Event is Data:
  Rebind{identity: Identity}
  Synchronize{value: String}
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
    case Some{previous}: String.eq(previous, value)
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
def same_meaning(original: UI.Meaning, current: UI.Meaning) -> Bool:
  match original current:
    case UI.Edit{editor, field, entry, value, choices} UI.Edit{other, new_field, new_entry, new_value, new_choices}: U.same_editor(editor, other)
    case UI.EnterDirectory{editor, text} UI.EnterDirectory{other, new_text}: U.same_editor(editor, other)
    case UI.ReceiveFile{editor, enabled} UI.ReceiveFile{other, new_enabled}: U.same_editor(editor, other)
    case UI.SearchChoices{query} UI.SearchChoices{new_query}: True{}
    case UI.EnterCredential{entered} UI.EnterCredential{new_entered}: True{}
    case UI.BoardSearch{filter} UI.BoardSearch{new_filter}: True{}
    case UI.DirectoryBrowserLocation{value} UI.DirectoryBrowserLocation{new_value}: True{}
    case UI.BoardProfile{automatic, selected, choices, enabled} UI.BoardProfile{new_automatic, new_selected, new_choices, new_enabled}: True{}
    case _ _: False{}
def same_identity(original: Identity, current: Identity) -> Bool:
  Identity{key, semantic, meaning} = original
  Identity{other_key, other_semantic, other_meaning} = current
  (String.eq(key, other_key) && String.eq(semantic, other_semantic)) && same_meaning(meaning, other_meaning)
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
    case SupersededComposing{}: Decision{Record{identity, canonical, SupersededTail{}}, False{}, True{}}
    case SupersededTail{}: Decision{Record{identity, canonical, SupersededTail{}}, False{}, True{}}
def observed(session: Session, +identity: Maybe<&2, Identity>, +canonical: Maybe<&2, String>) -> Decision:
  match session:
    case Idle{}: Decision{Record{identity, canonical, Idle{}}, True{}, False{}}
    case Composing{}: Decision{Record{identity, canonical, Composing{}}, False{}, False{}}
    case SupersededComposing{}: Decision{Record{identity, canonical, SupersededComposing{}}, False{}, True{}}
    case SupersededTail{}: Decision{Record{identity, canonical, SupersededTail{}}, False{}, True{}}
def step(event: Event, record: Record) -> Decision:
  match event:
    case Rebind{identity}: rebind_record(record, identity)
    case Synchronize{value}: synchronize_record(record, value)
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

def forest(surface: UI.Surface) -> +List<UI.Node>:
  UI.Surface{content, base, overlays, scope} = surface
  List.append(&2, UI.Node, base, overlays)
def editing(meaning: UI.Meaning) -> Bool:
  match meaning:
    case UI.Edit{editor, field, entry, value, choices}: True{}
    case UI.SearchChoices{query}: True{}
    case UI.EnterCredential{entered}: True{}
    case UI.ReceiveFile{editor, enabled}: True{}
    case UI.EnterDirectory{editor, text}: True{}
    case UI.BoardSearch{filter}: True{}
    case UI.DirectoryBrowserLocation{value}: True{}
    case UI.BoardProfile{automatic, selected, choices, enabled}: True{}
    case _: False{}
def found_editing(editable: Bool, key: String, kind: Source.NativeFieldKind, semantic: String, meaning: UI.Meaning) -> +List<Binding>:
  match editable:
    case False{}: Nil{}
    case True{}: [Binding{key, kind, semantic, meaning}]
def found_binding(key: String, kind: Source.NativeFieldKind, found: Maybe<&2, UI.Node>) -> +List<Binding>:
  match found:
    case None{}: Nil{}
    case Some{UI.Node{current, semantic, label, role, +meaning, children}}:
      found_editing(editing(meaning), key, kind, semantic, meaning)
def merge(first: Basis, second: Basis) -> Basis:
  Basis{fields, controls} = first
  Basis{later_fields, later_controls} = second
  Basis{List.append(&2, Binding, fields, later_fields), List.append(&2, String, controls, later_controls)}
def collect(nodes: +List<Source.Node>, +semantic: +List<UI.Node>) -> Basis:
  match nodes:
    case Nil{}: Basis{Nil{}, Nil{}}
    case Con{Source.Box{key, tag, style, attrs, children}, rest}: merge(collect(children, semantic), collect(rest, semantic))
    case Con{Source.Control{key, tag, style, attrs, name, enabled, first, remaining, children}, rest}:
      merge(Basis{Nil{}, [UIIdentity.encode(key)]}, merge(collect(children, semantic), collect(rest, semantic)))
    case Con{Source.NativeAttachment{key, target, attrs, style, children}, rest}: merge(collect(children, semantic), collect(rest, semantic))
    case Con{Source.Field{+key, kind, style, attrs, value, placeholder, options, policy, name, enabled, first, remaining}, rest}:
      merge(Basis{found_binding(UIIdentity.encode(key), kind, UI.find_node(semantic, UIIdentity.encode(key))), [UIIdentity.encode(key)]}, collect(rest, semantic))
    case Con{Source.RichText{key, style, content, attachments, native_owner}, rest}: merge(collect(attachments, semantic), collect(rest, semantic))
    case Con{Source.Text{key, value, font, wrapping}, rest}: collect(rest, semantic)
    case Con{Source.Glyph{key, drawing, style}, rest}: collect(rest, semantic)
def basis(source: +List<Source.Node>, semantic: UI.Surface) -> Basis: collect(source, forest(semantic))
def owned_found(found: Maybe<&2, UI.Node>, binding: Binding) -> Bool:
  match found:
    case None{}: False{}
    case Some{UI.Node{current, identity, label, role, meaning, children}}:
      Binding{key, kind, semantic, original} = binding
      (String.eq(key, UIIdentity.encode(current)) && String.eq(semantic, identity)) && same_meaning(original, meaning)
def owned_node(binding: Binding, found: Maybe<&2, UI.Node>) -> Bool: owned_found(found, binding)
def projected_kind(kind: Source.NativeFieldKind, +key: String, +semantic: String, +meaning: UI.Meaning) -> +List<Update>:
  match kind:
    case Source.ToggleField{}: [SetIdentity{key, Identity{key, semantic, meaning}}, SetChecked{key, Controls.field_checked(meaning)}]
    case Source.FileField{multiple}: [SetIdentity{key, Identity{key, semantic, meaning}}]
    case _: [SetIdentity{key, Identity{key, semantic, meaning}}, SetValue{key, Controls.node_value(meaning)}]
def projected(key: String, kind: Source.NativeFieldKind, semantic: String, meaning: UI.Meaning) -> +List<Update>:
  projected_kind(kind, key, semantic, meaning)
def update_found(found: Maybe<&2, UI.Node>, binding: Binding) -> +List<Update>:
  match found:
    case None{}: Nil{}
    case Some{UI.Node{current, semantic, label, role, meaning, children}}:
      Binding{key, kind, identity, original} = binding
      projected(key, kind, semantic, meaning)
def update_owned(owned: Bool, binding: Binding, found: Maybe<&2, UI.Node>) -> +List<Update>:
  match owned:
    case False{}: Nil{}
    case True{}: update_found(found, binding)
def update(+binding: Binding, +nodes: +List<UI.Node>) -> +List<Update>:
  Binding{+key, kind, semantic, meaning} = binding
  +found = UI.find_node(nodes, key)
  update_owned(owned_node(binding, found), binding, found)
def updates_fields(fields: +List<Binding>, +nodes: +List<UI.Node>) -> +List<Update>:
  match fields:
    case Nil{}: Nil{}
    case Con{binding, rest}: List.append(&2, Update, update(binding, nodes), updates_fields(rest, nodes))
def updates(basis: Basis, surface: UI.Surface) -> +List<Update>:
  Basis{fields, controls} = basis
  updates_fields(fields, forest(surface))
def fields_owned(fields: +List<Binding>, +key: String, +nodes: +List<UI.Node>) -> Bool:
  match fields:
    case Nil{}: False{}
    case Con{+binding, rest}:
      Binding{current, kind, semantic, meaning} = binding
      (String.eq(current, key) && owned_node(binding, UI.find_node(nodes, key))) || fields_owned(rest, key, nodes)
def field_owned(basis: Basis, key: String, surface: UI.Surface) -> Bool:
  Basis{fields, controls} = basis
  fields_owned(fields, key, forest(surface))
def key_present(keys: +List<String>, +key: String) -> Bool:
  match keys:
    case Nil{}: False{}
    case Con{current, rest}: String.eq(current, key) || key_present(rest, key)
def control_owned(basis: Basis, key: String) -> Bool:
  Basis{fields, controls} = basis
  key_present(controls, key)

def record_canonical(record: Record) -> Maybe<&2, String>:
  Record{identity, canonical, session} = record
  canonical
