import Base
import ../native-fields.bend as Native
import ../native-fields-rules.bend as Rule
import ../../core/interface.bend as UI
import ../../bendlib/stdlib.bend as Std

def unchanged(+record: Native.Record, +value: String,
  proof: {Native.canonical_same(Native.record_canonical(record), value) == True{} : Bool}) -> Rule.unchanged_claim(value, record):
  match record:
    case Native.Record{identity, +canonical, +session}:
      Std.transport(Bool, True{},
        (same => {Native.synchronized(same, value, Native.Record{identity, canonical, session}) == Native.Decision{Native.Record{identity, canonical, session}, False{}, False{}} : Native.Decision}),
        {==}, Native.canonical_same(canonical, value), proof)
def unmatched(+binding: Native.Binding, +found: Maybe<&2, UI.Node>,
  proof: {Native.owned_node(binding, found) == False{} : Bool}) -> Rule.unmatched_claim(binding, found):
  Std.transport(Bool, False{},
    (owned => {Native.update_owned(owned, binding, found) == Nil{} : +List<Native.Update>}),
    {==}, Native.owned_node(binding, found), proof)
def matching(+binding: Native.Binding, +node: UI.Node,
  proof: {Native.owned_node(binding, Some{node}) == True{} : Bool}) -> Rule.matching_claim(binding, node):
  match binding node:
    case Native.Binding{+key, +kind, identity, original} UI.Node{current, semantic, label, role, +meaning, children}:
      Std.transport(Bool, True{},
        (owned => {Native.update_owned(owned, Native.Binding{key, kind, identity, original}, Some{UI.Node{current, semantic, label, role, meaning, children}}) == Native.projected(key, kind, semantic, meaning) : +List<Native.Update>}),
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
