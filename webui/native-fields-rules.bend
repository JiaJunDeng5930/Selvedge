import Base
import ./native-fields.bend as Native
import ./source.bend as Source
import ./authored-controls.bend as Controls
import ../core/interface.bend as InterfaceView
import ../core/user-input.bend as U
import ../core/form-fields.bend as Forms
import ./physical-browser.bend as Browser
import ./browser.bend as Legacy
import ../core/client-services.bend as Services

def unchanged_claim(+value: String, +record: Native.Record) -> Type:
  {Native.step(Native.Synchronize{value}, record) == Native.Decision{record, False{}, False{}} : Native.Decision}
def unmatched_claim(+binding: Native.Binding, +found: Maybe<&2, InterfaceView.Node>) -> Type:
  {Native.update_owned(Native.owned_node(binding, found), binding, found) == Nil{} : +List<Native.Update>}
def matching_claim(+binding: Native.Binding, +node: InterfaceView.Node) -> Type:
  Native.Binding{key, kind, identity, original} = binding
  InterfaceView.Node{current, semantic, label, role, meaning, children} = node
  {Native.update_owned(Native.owned_node(binding, Some{node}), binding, Some{node}) == Native.projected(key, kind, semantic, meaning) : +List<Native.Update>}
def changed_composing_claim(+identity: Maybe<&2, Native.Identity>, +old: Maybe<&2, String>, +value: String) -> Type:
  {Native.step(Native.Synchronize{value}, Native.Record{identity, old, Native.Composing{}}) ==
    Native.Decision{Native.Record{identity, Some{value}, Native.SupersededComposing{}}, False{}, True{}} : Native.Decision}
def superseded_end_claim(+identity: Maybe<&2, Native.Identity>, +canonical: Maybe<&2, String>) -> Type:
  {Native.step(Native.CompositionEnded{}, Native.Record{identity, canonical, Native.SupersededComposing{}}) ==
    Native.Decision{Native.Record{identity, canonical, Native.SupersededTail{}}, False{}, True{}} : Native.Decision}
def superseded_tail_claim(+identity: Maybe<&2, Native.Identity>, +canonical: Maybe<&2, String>) -> Type:
  {Native.step(Native.InputObserved{}, Native.Record{identity, canonical, Native.SupersededTail{}}) ==
    Native.Decision{Native.Record{identity, canonical, Native.SupersededTail{}}, False{}, True{}} : Native.Decision}
def superseded_input_claim(+identity: Maybe<&2, Native.Identity>, +canonical: Maybe<&2, String>) -> Type:
  {Native.step(Native.InputObserved{}, Native.Record{identity, canonical, Native.SupersededComposing{}}) ==
    Native.Decision{Native.Record{identity, canonical, Native.SupersededComposing{}}, False{}, True{}} : Native.Decision}
def superseded_tail_end_claim(+identity: Maybe<&2, Native.Identity>, +canonical: Maybe<&2, String>) -> Type:
  {Native.step(Native.CompositionEnded{}, Native.Record{identity, canonical, Native.SupersededTail{}}) ==
    Native.Decision{Native.Record{identity, canonical, Native.SupersededTail{}}, False{}, True{}} : Native.Decision}
def transaction_claim(+record: Native.Record) -> Type:
  Native.Record{identity, canonical, session} = record
  {Native.step(Native.InputStarted{}, record) == Native.Decision{Native.Record{identity, canonical, Native.Idle{}}, False{}, False{}} : Native.Decision}
def checkbox_claim(+key: String, +semantic: String, +meaning: InterfaceView.Meaning) -> Type:
  {Native.projected(key, Source.ToggleField{}, semantic, meaning) == [Native.SetIdentity{key, Native.Identity{key, semantic, meaning}}, Native.SetChecked{key, Controls.field_checked(meaning)}] : +List<Native.Update>}
def text_claim(+key: String, +semantic: String, +meaning: InterfaceView.Meaning) -> Type:
  {Native.projected(key, Source.TextField{}, semantic, meaning) == [Native.SetIdentity{key, Native.Identity{key, semantic, meaning}}, Native.SetValue{key, Controls.node_value(meaning)}] : +List<Native.Update>}

def editor_owner_claim(+editor: U.Editor, +other: U.Editor, +field: Forms.Field, +entry: Forms.Entry, +value: Forms.Observed, +choices: +List<Forms.ChoiceValue>, +new_field: Forms.Field, +new_entry: Forms.Entry, +new_value: Forms.Observed, +new_choices: +List<Forms.ChoiceValue>) -> Type:
  {Native.same_meaning(InterfaceView.Edit{editor, field, entry, value, choices}, InterfaceView.Edit{other, new_field, new_entry, new_value, new_choices}) == U.same_editor(editor, other) : Bool}

def unbound_claim(+identity: Native.Identity, +canonical: Maybe<&2, String>, +session: Native.Session) -> Type:
  {Native.step(Native.Rebind{identity}, Native.Record{None{}, canonical, session}) == Native.Decision{Native.Record{Some{identity}, canonical, session}, False{}, False{}} : Native.Decision}
def equal_rebind_claim(+old: Native.Identity, +identity: Native.Identity, +canonical: Maybe<&2, String>, +session: Native.Session) -> Type:
  {Native.step(Native.Rebind{identity}, Native.Record{Some{old}, canonical, session}) == Native.Decision{Native.Record{Some{old}, canonical, session}, False{}, False{}} : Native.Decision}
def changed_rebind_claim(+old: Native.Identity, +identity: Native.Identity, +canonical: Maybe<&2, String>, +session: Native.Session) -> Type:
  {Native.step(Native.Rebind{identity}, Native.Record{Some{old}, canonical, session}) == Native.Decision{Native.Record{Some{identity}, canonical, Native.rebind_session(session)}, False{}, True{}} : Native.Decision}
def rebind_composing_claim() -> Type:
  {Native.rebind_session(Native.Composing{}) == Native.SupersededComposing{} : Native.Session}
def rebind_idle_claim() -> Type:
  {Native.rebind_session(Native.Idle{}) == Native.SupersededTail{} : Native.Session}

type Requirements is Type:
  Requirements{
    unbound: @+identity:Native.Identity -> @+canonical:Maybe<&2, String> -> @+session:Native.Session -> unbound_claim(identity, canonical, session),
    equal_rebind: @+old:Native.Identity -> @+identity:Native.Identity -> @+canonical:Maybe<&2, String> -> @+session:Native.Session -> {Native.same_identity(old, identity) == True{} : Bool} -> equal_rebind_claim(old, identity, canonical, session),
    changed_rebind: @+old:Native.Identity -> @+identity:Native.Identity -> @+canonical:Maybe<&2, String> -> @+session:Native.Session -> {Native.same_identity(old, identity) == False{} : Bool} -> changed_rebind_claim(old, identity, canonical, session),
    rebind_composing: rebind_composing_claim(),
    rebind_idle: rebind_idle_claim(),
    editor_owner: @+editor:U.Editor -> @+other:U.Editor -> @+field:Forms.Field -> @+entry:Forms.Entry -> @+value:Forms.Observed -> @+choices:+List<Forms.ChoiceValue> -> @+new_field:Forms.Field -> @+new_entry:Forms.Entry -> @+new_value:Forms.Observed -> @+new_choices:+List<Forms.ChoiceValue> -> editor_owner_claim(editor, other, field, entry, value, choices, new_field, new_entry, new_value, new_choices),
    unchanged: @+value:String -> @+record:Native.Record ->
      {Native.canonical_same(Native.record_canonical(record), value) == True{} : Bool} -> unchanged_claim(value, record),
    unmatched: @+binding:Native.Binding -> @+found:Maybe<&2, InterfaceView.Node> ->
      {Native.owned_node(binding, found) == False{} : Bool} -> unmatched_claim(binding, found),
    matching: @+binding:Native.Binding -> @+node:InterfaceView.Node ->
      {Native.owned_node(binding, Some{node}) == True{} : Bool} -> matching_claim(binding, node),
    changed_composing: @+identity:Maybe<&2, Native.Identity> -> @+old:Maybe<&2, String> -> @+value:String ->
      {Native.canonical_same(old, value) == False{} : Bool} -> changed_composing_claim(identity, old, value),
    superseded_end: @+identity:Maybe<&2, Native.Identity> -> @+canonical:Maybe<&2, String> -> superseded_end_claim(identity, canonical),
    superseded_tail: @+identity:Maybe<&2, Native.Identity> -> @+canonical:Maybe<&2, String> -> superseded_tail_claim(identity, canonical),
    superseded_input: @+identity:Maybe<&2, Native.Identity> -> @+canonical:Maybe<&2, String> -> superseded_input_claim(identity, canonical),
    superseded_tail_end: @+identity:Maybe<&2, Native.Identity> -> @+canonical:Maybe<&2, String> -> superseded_tail_end_claim(identity, canonical),
    transaction: @+record:Native.Record -> transaction_claim(record),
    checkbox: @+key:String -> @+semantic:String -> @+meaning:InterfaceView.Meaning -> checkbox_claim(key, semantic, meaning),
    text: @+key:String -> @+semantic:String -> @+meaning:InterfaceView.Meaning -> text_claim(key, semantic, meaning)}

law evidence:
  Requirements


law updates_empty:
  for nodes: +List<InterfaceView.Node>
  {Native.updates_fields(Nil{}, nodes) == Nil{} : +List<Native.Update>}

law updates_complete:
  for +binding: Native.Binding
  for +rest: +List<Native.Binding>
  for +nodes: +List<InterfaceView.Node>
  {Native.updates_fields(binding <> rest, nodes) == List.append(&2, Native.Update, Native.update(binding, nodes), Native.updates_fields(rest, nodes)) : +List<Native.Update>}

law updates_basis:
  for fields: +List<Native.Binding>
  for controls: +List<String>
  for surface: InterfaceView.Surface
  {Native.updates(Native.Basis{fields, controls}, surface) == Native.updates_fields(fields, Native.forest(surface)) : +List<Native.Update>}

law update_owner:
  for +key: String
  for +kind: Source.NativeFieldKind
  for +semantic: String
  for +meaning: InterfaceView.Meaning
  for +nodes: +List<InterfaceView.Node>
  {Native.update(Native.Binding{key, kind, semantic, meaning}, nodes) ==
    Native.update_owned(Native.owned_node(Native.Binding{key, kind, semantic, meaning}, InterfaceView.find_node(nodes, key)), Native.Binding{key, kind, semantic, meaning}, InterfaceView.find_node(nodes, key)) : +List<Native.Update>}

def field_projection(kind: Source.NativeFieldKind, key: String, semantic: String, meaning: InterfaceView.Meaning, actual: +List<Native.Update>) -> Type:
  match kind:
    case Source.ToggleField{}: {actual == [Native.SetIdentity{key, Native.Identity{key, semantic, meaning}}, Native.SetChecked{key, Controls.field_checked(meaning)}] : +List<Native.Update>}
    case Source.FileField{multiple}: {actual == [Native.SetIdentity{key, Native.Identity{key, semantic, meaning}}] : +List<Native.Update>}
    case _: {actual == [Native.SetIdentity{key, Native.Identity{key, semantic, meaning}}, Native.SetValue{key, Controls.node_value(meaning)}] : +List<Native.Update>}

law all_field_projections:
  for +kind: Source.NativeFieldKind
  for +key: String
  for +semantic: String
  for +meaning: InterfaceView.Meaning
  field_projection(kind, key, semantic, meaning, Native.projected(key, kind, semantic, meaning))

law edit_text_rejected:
  for +key: String
  for +text: String
  for +state: Browser.State
  for owned: {Browser.field_owned(key, state) == False{} : Bool}
  {Browser.edit_text(key, text, state) == Browser.Decision{state, Nil{}} : Browser.Decision}

law edit_text_accepted:
  for +key: String
  for +text: String
  for +state: Browser.State
  for owned: {Browser.field_owned(key, state) == True{} : Bool}
  {Browser.edit_text(key, text, state) == Browser.accept(True{}, Legacy.edit_text(key, text, Browser.legacy(state)), state) : Browser.Decision}

law confirm_text_rejected:
  for +key: String
  for +keyboard: String
  for +composing: Bool
  for +control: Bool
  for +alt: Bool
  for +shift: Bool
  for +meta: Bool
  for +state: Browser.State
  for owned: {Browser.field_owned(key, state) == False{} : Bool}
  {Browser.confirm_text(key, keyboard, composing, control, alt, shift, meta, state) == Browser.Decision{state, Nil{}} : Browser.Decision}

law confirm_text_accepted:
  for +key: String
  for +keyboard: String
  for +composing: Bool
  for +control: Bool
  for +alt: Bool
  for +shift: Bool
  for +meta: Bool
  for +state: Browser.State
  for owned: {Browser.field_owned(key, state) == True{} : Bool}
  {Browser.confirm_text(key, keyboard, composing, control, alt, shift, meta, state) == Browser.accept(True{}, Legacy.confirm_text(key, keyboard, composing, control, alt, shift, meta, Browser.legacy(state)), state) : Browser.Decision}

law edit_toggle_rejected:
  for +key: String
  for +enabled: Bool
  for +state: Browser.State
  for owned: {Browser.field_owned(key, state) == False{} : Bool}
  {Browser.edit_toggle(key, enabled, state) == Browser.Decision{state, Nil{}} : Browser.Decision}

law edit_toggle_accepted:
  for +key: String
  for +enabled: Bool
  for +state: Browser.State
  for owned: {Browser.field_owned(key, state) == True{} : Bool}
  {Browser.edit_toggle(key, enabled, state) == Browser.accept(True{}, Legacy.edit_toggle(key, enabled, Browser.legacy(state)), state) : Browser.Decision}

law attach_rejected:
  for +key: String
  for +file: Services.SelectedFile
  for +state: Browser.State
  for owned: {Browser.field_owned(key, state) == False{} : Bool}
  {Browser.attach(key, file, state) == Browser.Decision{state, Nil{}} : Browser.Decision}

law attach_accepted:
  for +key: String
  for +file: Services.SelectedFile
  for +state: Browser.State
  for owned: {Browser.field_owned(key, state) == True{} : Bool}
  {Browser.attach(key, file, state) == Browser.accept(True{}, Legacy.attach(key, file, Browser.legacy(state)), state) : Browser.Decision}
