import Base
import ../json.bend as J

# These arithmetic helpers close only the UTF-8 accumulator refinement.
def length_add_zero(+total: Nat) -> {Nat.add(total, 0n) == total : Nat}:
  match total:
    case 0n: {==}
    case 1n+rest:
      Equal.cong(Nat, Nat, (value => 1n+value), Nat.add(rest, 0n), rest, length_add_zero(rest))

def length_add_assoc(+a: Nat, +b: Nat, +c: Nat) ->
  {Nat.add(a, Nat.add(b, c)) == Nat.add(Nat.add(a, b), c) : Nat}:
  match a:
    case 0n: {==}
    case 1n+rest:
      Equal.cong(Nat, Nat, (value => 1n+value),
        Nat.add(rest, Nat.add(b, c)), Nat.add(Nat.add(rest, b), c), length_add_assoc(rest, b, c))

def accumulator_refines(+text: String, +total: Nat) ->
  {J.utf8_length_acc(text, total) == Nat.add(total, J.utf8_length_spec(text)) : Nat}:
  match text:
    case SNil{}: Equal.sym(Nat, Nat.add(total, 0n), total, length_add_zero(total))
    case SCon{Chr{+code}, +rest}:
      +width = J.char_width(U32.is_lt(code, 128), U32.is_lt(code, 2048), U32.is_lt(code, 65536))
      Equal.trans(Nat,
        J.utf8_length_acc(rest, Nat.add(total, width)),
        Nat.add(Nat.add(total, width), J.utf8_length_spec(rest)),
        Nat.add(total, Nat.add(width, J.utf8_length_spec(rest))),
        accumulator_refines(rest, Nat.add(total, width)),
        Equal.sym(Nat, Nat.add(total, Nat.add(width, J.utf8_length_spec(rest))),
          Nat.add(Nat.add(total, width), J.utf8_length_spec(rest)),
          length_add_assoc(total, width, J.utf8_length_spec(rest))))

def public_refines(+text: String) ->
  {J.utf8_length(text) == J.utf8_length_spec(text) : Nat}:
  accumulator_refines(text, 0n)
