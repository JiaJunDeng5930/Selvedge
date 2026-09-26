import Base

# Generated from ExtLib FMapAList definitions and remove_eq_alist's proof body.
# Nat keys use the Boolean-relation instance in scripts/ExportMaps.v.
# Source copyright ExtLib contributors; BSD-2-Clause (theory/EXTLIB-LICENSE).

def Entry(-V: Data) -> Data:
  Sigma<&2, &2, Nat, (_ => V)>

def choose(~V: Data, hit: Bool, value: V, tail: Maybe<&2, V>) -> Maybe<&2, V>:
  match hit:
    case True{}: Some{value}
    case False{}: tail

def find(~V: Data, entries: +List<Entry(V)>, +query: Nat) -> Maybe<&2, V>:
  match entries:
    case Nil{}: None{}
    case Con{(+key, value), rest}: choose(~V, Nat.is_eq(query, key), value, find(~V, rest, query))

def keep(~V: Data, retained: Bool, key: Nat, value: V, tail: +List<Entry(V)>) -> +List<Entry(V)>:
  match retained:
    case True{}: (key, value) <> tail
    case False{}: tail

def remove(~V: Data, entries: +List<Entry(V)>, +query: Nat) -> +List<Entry(V)>:
  match entries:
    case Nil{}: Nil{}
    case Con{(+key, value), rest}: keep(~V, Bool.not(Nat.is_eq(query, key)), key, value, remove(~V, rest, query))

# A reflected source case becomes a Boolean case plus equality transport.
# Both leaf proofs below are translated source leaves, not a target proof search.
def absence_case(~V: Data, +hit: Bool, +key: Nat, +value: V, +rest: +List<Entry(V)>, +query: Nat,
  observed: {Nat.is_eq(query, key) == hit : Bool},
  induction: {find(~V, remove(~V, rest, query), query) == None{} : Maybe<&2, V>}) ->
  {find(~V, keep(~V, Bool.not(hit), key, value, remove(~V, rest, query)), query) == None{} : Maybe<&2, V>}:
  match hit:
    case True{}: induction
    case False{}:
      backwards = Equal.sym(Bool, Nat.is_eq(query, key), False{}, observed)
      %backwards : {choose(~V, _, value, find(~V, remove(~V, rest, query), query)) == None{} : Maybe<&2, V>}
      induction

def removal_absence(~V: Data, entries: +List<Entry(V)>, +query: Nat) ->
  {find(~V, remove(~V, entries, query), query) == None{} : Maybe<&2, V>}:
  match entries:
    case Nil{}: {==}
    case Con{(+key, value), +rest}:
      absence_case(~V, Nat.is_eq(query, key), key, value, rest, query, {==}, removal_absence(~V, rest, query))
