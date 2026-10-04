import Base
import ./algebra.bend as Alg
import ../json.bend as J

def accumulator_refines(+text: String, +total: Nat) ->
  {J.utf8_length_acc(text, total) == Nat.add(total, J.utf8_length_spec(text)) : Nat}:
  match text:
    case SNil{}: Equal.sym(Nat, Nat.add(total, 0n), total, Alg.nat_add_zero(total))
    case SCon{Chr{+code}, +rest}:
      +width = J.char_width(U32.is_lt(code, 128), U32.is_lt(code, 2048), U32.is_lt(code, 65536))
      Equal.trans(Nat,
        J.utf8_length_acc(rest, Nat.add(total, width)),
        Nat.add(Nat.add(total, width), J.utf8_length_spec(rest)),
        Nat.add(total, Nat.add(width, J.utf8_length_spec(rest))),
        accumulator_refines(rest, Nat.add(total, width)),
        Alg.nat_add_assoc(total, width, J.utf8_length_spec(rest)))

def public_refines(+text: String) ->
  {J.utf8_length(text) == J.utf8_length_spec(text) : Nat}:
  accumulator_refines(text, 0n)
