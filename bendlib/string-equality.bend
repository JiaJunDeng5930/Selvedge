import Base

# Shared text equality keeps comparison stack use bounded by a tail-recursive
# traversal. The public equality module retains forwarding entry points.
def char_equal(compared: (Char & Char) & Cmp) -> Bool:
  ((left, right), order) = compared
  Cmp.is_eq(order)

def string_equal_acc(left: String, right: String, same: Bool) -> Bool:
  match left right same:
    case SNil{} SNil{} False{}: False{}
    case SNil{} SNil{} True{}: True{}
    case SNil{} SCon{head, tail} False{}: False{}
    case SNil{} SCon{head, tail} True{}: False{}
    case SCon{head, tail} SNil{} False{}: False{}
    case SCon{head, tail} SNil{} True{}: False{}
    case SCon{a, rest_a} SCon{b, rest_b} False{}: False{}
    case SCon{a, rest_a} SCon{b, rest_b} True{}:
      string_equal_acc(rest_a, rest_b, char_equal(Char.cmp(a, b)))

def string_equal(left: String, right: String) -> Bool:
  string_equal_acc(left, right, True{})

