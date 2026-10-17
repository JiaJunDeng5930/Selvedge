import Base

# Shared text equality keeps comparison stack use bounded by a tail-recursive
# traversal. The public equality module retains forwarding entry points.
def char_equal(compared: (Char & Char) & Cmp) -> Bool:
  ((left, right), order) = compared
  Cmp.is_eq(order)

def string_equal_acc(left: String, right: String, same: Bool) -> Bool:
  match left right:
    case SNil{} SNil{}: same
    case SNil{} SCon{head, tail}: False{}
    case SCon{head, tail} SNil{}: False{}
    case SCon{a, rest_a} SCon{b, rest_b}:
      string_equal_acc(rest_a, rest_b, same && char_equal(Char.cmp(a, b)))

def string_equal(left: String, right: String) -> Bool:
  string_equal_acc(left, right, True{})

