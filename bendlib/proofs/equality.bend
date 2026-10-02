import Base
import ../equality.bend as Same

def reconstructed_order(+a: Char, +b: Char, compared: (String & String) & Cmp) ->
  {String.eq.fin(String.cmp.rec(a, b, compared)) == String.eq.fin(compared) : Bool}:
  ((left, right), order) = compared
  {==}

def compared_heads(+left: String, +right: String, heads: (Char & Char) & Cmp) ->
  {String.eq.fin(String.cmp.fin(left, right, heads)) == (Same.char_equal(heads) && String.eq(left, right)) : Bool}:
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
