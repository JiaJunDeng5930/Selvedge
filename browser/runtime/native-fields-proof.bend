import Base
import ./native-fields.bend as Native
import ./native-fields-rules.bend as Rule
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../bendlib/stdlib.bend as Std
import ../document/SOURCE.bend as Source
import ./MODEL.bend as Browser
import ./SEMANTICS.bend as Legacy

def unchanged(+record: Native.Record, +value: String,
  proof: {Native.canonical_same(Native.record_canonical(record), value) == True{} : Bool}) -> Rule.unchanged_claim(value, record):
  match record:
    case Native.Record{identity, +canonical, +session}:
      Std.transport(Bool, True{},
        (same => {Native.synchronized(same, value, Native.Record{identity, canonical, session}) == Native.Decision{Native.Record{identity, canonical, session}, False{}, False{}} : Native.Decision}),
        {==}, Native.canonical_same(canonical, value), proof)
def unmatched(+binding: Native.Binding, +found: Maybe<&2, InterfaceView.Node>,
  proof: {Native.owned_node(binding, found) == False{} : Bool}) -> Rule.unmatched_claim(binding, found):
  Std.transport(Bool, False{},
    (owned => {Native.update_owned(owned, binding, found) == Nil{} : +List<Native.Update>}),
    {==}, Native.owned_node(binding, found), proof)
def matching(+binding: Native.Binding, +node: InterfaceView.Node,
  proof: {Native.owned_node(binding, Some{node}) == True{} : Bool}) -> Rule.matching_claim(binding, node):
  match binding node:
    case Native.Binding{+key, +kind, identity, original} InterfaceView.Node{current, semantic, label, role, +meaning, children}:
      Std.transport(Bool, True{},
        (owned => {Native.update_owned(owned, Native.Binding{key, kind, identity, original}, Some{InterfaceView.Node{current, semantic, label, role, meaning, children}}) == Native.projected(key, kind, semantic, meaning) : +List<Native.Update>}),
        {==}, Native.owned_node(binding, Some{node}), proof)
def changed_composing(+identity: Maybe<&2, Native.Identity>, +old: Maybe<&2, String>, +value: String,
  proof: {Native.canonical_same(old, value) == False{} : Bool}) -> Rule.changed_composing_claim(identity, old, value):
  Std.transport(Bool, False{},
    (same => {Native.synchronized(same, value, Native.Record{identity, old, Native.Composing{}}) == Native.Decision{Native.Record{identity, Some{value}, Native.SupersededComposing{}}, False{}, True{}} : Native.Decision}),
    {==}, Native.canonical_same(old, value), proof)
def transaction(+record: Native.Record) -> Rule.transaction_claim(record):
  match record:
    case Native.Record{identity, canonical, session}: {==}

def equal_rebind(+old: Native.Identity, +identity: Native.Identity, +canonical: Maybe<&2, String>, +session: Native.Session,
  proof: {Native.same_identity(old, identity) == True{} : Bool}) -> Rule.equal_rebind_claim(old, identity, canonical, session):
  Std.transport(Bool, True{},
    (same => {Native.rebound(same, identity, Native.Record{Some{old}, canonical, session}) == Native.Decision{Native.Record{Some{old}, canonical, session}, False{}, False{}} : Native.Decision}),
    {==}, Native.same_identity(old, identity), proof)
def changed_rebind(+old: Native.Identity, +identity: Native.Identity, +canonical: Maybe<&2, String>, +session: Native.Session,
  proof: {Native.same_identity(old, identity) == False{} : Bool}) -> Rule.changed_rebind_claim(old, identity, canonical, session):
  Std.transport(Bool, False{},
    (same => {Native.rebound(same, identity, Native.Record{Some{old}, canonical, session}) == Native.Decision{Native.Record{Some{identity}, canonical, Native.rebind_session(session)}, False{}, True{}} : Native.Decision}),
    {==}, Native.same_identity(old, identity), proof)

def Rule.evidence():
  Rule.Requirements{
    +identity => +canonical => +session => {==},
    +old => +identity => +canonical => +session => proof => equal_rebind(old, identity, canonical, session, proof),
    +old => +identity => +canonical => +session => proof => changed_rebind(old, identity, canonical, session, proof),
    {==},
    {==},
    +editor => +other => +field => +entry => +value => +choices => +new_field => +new_entry => +new_value => +new_choices => {==},
    +value => +record => proof => unchanged(record, value, proof),
    +binding => +found => proof => unmatched(binding, found, proof),
    +binding => +node => proof => matching(binding, node, proof),
    +identity => +old => +value => proof => changed_composing(identity, old, value, proof),
    +identity => +canonical => {==},
    +identity => +canonical => {==},
    +identity => +canonical => {==},
    +identity => +canonical => {==},
    +record => transaction(record),
    +key => +semantic => +meaning => {==},
    +key => +semantic => +meaning => {==}}



def Rule.updates_empty(nodes): {==}
def Rule.updates_complete(binding, rest, nodes): {==}
def Rule.updates_basis(fields, controls, surface): {==}
def Rule.update_owner(key, kind, semantic, meaning, nodes): {==}
def Rule.all_field_projections(kind, key, semantic, meaning):
  match kind:
    case Source.TextField{}: {==}
    case Source.MessageField{}: {==}
    case Source.TextAreaField{}: {==}
    case Source.SelectField{}: {==}
    case Source.MultiSelectField{}: {==}
    case Source.ToggleField{}: {==}
    case Source.NumberField{minimum}: {==}
    case Source.FileField{multiple}: {==}
    case Source.DirectoryField{}: {==}
    case Source.SearchField{}: {==}
    case Source.SecretField{}: {==}

def Rule.edit_text_rejected(key, text, state, owned):
  Equal.cong(Bool, Browser.Decision,
    (allowed => Browser.edit_text_owned(allowed, key, text, state)),
    Browser.field_owned(key, state), False{}, owned)

def Rule.edit_text_accepted(key, text, state, owned):
  Equal.cong(Bool, Browser.Decision,
    (allowed => Browser.edit_text_owned(allowed, key, text, state)),
    Browser.field_owned(key, state), True{}, owned)

def Rule.confirm_text_rejected(key, keyboard, composing, control, alt, shift, meta, state, owned):
  Equal.cong(Bool, Browser.Decision,
    (allowed => Browser.confirm_text_owned(allowed, key, keyboard, composing, control, alt, shift, meta, state)),
    Browser.field_owned(key, state), False{}, owned)

def Rule.confirm_text_accepted(key, keyboard, composing, control, alt, shift, meta, state, owned):
  Equal.cong(Bool, Browser.Decision,
    (allowed => Browser.confirm_text_owned(allowed, key, keyboard, composing, control, alt, shift, meta, state)),
    Browser.field_owned(key, state), True{}, owned)

def Rule.edit_toggle_rejected(key, enabled, state, owned):
  Equal.cong(Bool, Browser.Decision,
    (allowed => Browser.edit_toggle_owned(allowed, key, enabled, state)),
    Browser.field_owned(key, state), False{}, owned)

def Rule.edit_toggle_accepted(key, enabled, state, owned):
  Equal.cong(Bool, Browser.Decision,
    (allowed => Browser.edit_toggle_owned(allowed, key, enabled, state)),
    Browser.field_owned(key, state), True{}, owned)

def Rule.attach_rejected(key, file, state, owned):
  Equal.cong(Bool, Browser.Decision,
    (allowed => Browser.attach_owned(allowed, key, file, state)),
    Browser.field_owned(key, state), False{}, owned)

def Rule.attach_accepted(key, file, state, owned):
  Equal.cong(Bool, Browser.Decision,
    (allowed => Browser.attach_owned(allowed, key, file, state)),
    Browser.field_owned(key, state), True{}, owned)
