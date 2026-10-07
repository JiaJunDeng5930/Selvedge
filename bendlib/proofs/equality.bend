import Base
import ../equality.bend as Same

def reconstructed_order(+a: Char, +b: Char, compared: (String & String) & Cmp) ->
  {Cmp.is_eq(Pair.snd(String & String, Cmp, String.cmp.rec(a, b, compared))) == Cmp.is_eq(Pair.snd(String & String, Cmp, compared)) : Bool}:
  ((left, right), order) = compared
  {==}

def compared_heads(+left: String, +right: String, heads: (Char & Char) & Cmp) ->
  {Cmp.is_eq(Pair.snd(String & String, Cmp, String.cmp.fin(left, right, heads))) == (Same.char_equal(heads) && String.eq(left, right)) : Bool}:
  ((a, b), order) = heads
  match order:
    case LT{}: {==}
    case EQ{}: reconstructed_order(a, b, String.cmp(left, right))
    case GT{}: {==}

def conjunction_assoc(+a: Bool, +b: Bool, +c: Bool) ->
  {((a && b) && c) == (a && (b && c)) : Bool}:
  match a:
    case False{}: {==}
    case True{}: {==}

def accumulator_refines(+left: String, +right: String, +same: Bool) ->
  {Same.string_equal_acc(left, right, same) == (same && String.eq(left, right)) : Bool}:
  match left right:
    case SNil{} SNil{}:
      match same:
        case False{}: {==}
        case True{}: {==}
    case SNil{} SCon{head, tail}:
      match same:
        case False{}: {==}
        case True{}: {==}
    case SCon{head, tail} SNil{}:
      match same:
        case False{}: {==}
        case True{}: {==}
    case SCon{+a, +rest_a} SCon{+b, +rest_b}:
      +equal_heads = Same.char_equal(Char.cmp(a, b))
      Equal.trans(Bool,
        Same.string_equal_acc(rest_a, rest_b, same && equal_heads),
        ((same && equal_heads) && String.eq(rest_a, rest_b)),
        (same && String.eq(SCon{a, rest_a}, SCon{b, rest_b})),
        accumulator_refines(rest_a, rest_b, same && equal_heads),
        Equal.trans(Bool,
          ((same && equal_heads) && String.eq(rest_a, rest_b)),
          (same && (equal_heads && String.eq(rest_a, rest_b))),
          (same && String.eq(SCon{a, rest_a}, SCon{b, rest_b})),
          conjunction_assoc(same, equal_heads, String.eq(rest_a, rest_b)),
          Equal.cong(Bool, Bool, (value => same && value),
            (equal_heads && String.eq(rest_a, rest_b)),
            String.eq(SCon{a, rest_a}, SCon{b, rest_b}),
            Equal.sym(Bool,
              String.eq(SCon{a, rest_a}, SCon{b, rest_b}),
              (equal_heads && String.eq(rest_a, rest_b)),
              compared_heads(rest_a, rest_b, Char.cmp(a, b))))))

def public_refines(+left: String, +right: String) ->
  {Same.string_equal(left, right) == String.eq(left, right) : Bool}:
  accumulator_refines(left, right, True{})

def same_bit(+value: Bool) -> {Bool.cmp(value, value) == EQ{} : Cmp}:
  match value:
    case False{}: {==}
    case True{}: {==}

def same_word(+size: Nat, +value: Word(size)) -> {Word.cmp(size, value, value) == EQ{} : Cmp}:
  match size:
    case 0n: {==}
    case 1n+rest:
      match value:
        case WCon{+head, +tail}:
          Equal.trans(Cmp, Word.cmp.fin(head, head, Word.cmp(rest, tail, tail)), Word.cmp.fin(head, head, EQ{}), EQ{},
            Equal.cong(Cmp, Cmp, (order => Word.cmp.fin(head, head, order)), Word.cmp(rest, tail, tail), EQ{}, same_word(rest, tail)), same_bit(head))

def same_character(+code: U32) -> {Char.cmp(Chr{code}, Chr{code}) == ((Chr{code}, Chr{code}), EQ{}) : (Char & Char) & Cmp}:
  match code:
    case U32{+value}:
      Equal.cong(Cmp, (Char & Char) & Cmp, (order => ((Chr{U32{value}}, Chr{U32{value}}), order)), Word.cmp(32n, value, value), EQ{}, same_word(32n, value))

def same_comparison(+text: String) -> {String.cmp(text, text) == ((text, text), EQ{}) : (String & String) & Cmp}:
  match text:
    case SNil{}: {==}
    case SCon{Chr{+code}, +rest}:
      Equal.trans((String & String) & Cmp,
        String.cmp(SCon{Chr{code}, rest}, SCon{Chr{code}, rest}),
        String.cmp.rec(Chr{code}, Chr{code}, String.cmp(rest, rest)),
        ((SCon{Chr{code}, rest}, SCon{Chr{code}, rest}), EQ{}),
        Equal.cong((Char & Char) & Cmp, (String & String) & Cmp,
          (heads => String.cmp.fin(rest, rest, heads)), Char.cmp(Chr{code}, Chr{code}), ((Chr{code}, Chr{code}), EQ{}), same_character(code)),
        Equal.cong((String & String) & Cmp, (String & String) & Cmp,
          (compared => String.cmp.rec(Chr{code}, Chr{code}, compared)), String.cmp(rest, rest), ((rest, rest), EQ{}), same_comparison(rest)))

def same_string(+text: String) -> {String.eq(text, text) == True{} : Bool}:
  Equal.cong((String & String) & Cmp, Bool, (compared => Cmp.is_eq(Pair.snd(String & String, Cmp, compared))), String.cmp(text, text), ((text, text), EQ{}), same_comparison(text))
