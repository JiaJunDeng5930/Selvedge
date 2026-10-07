import Base
import ../paint-rules.bend as Rule
import ../typography.bend as T
import ../paint.bend as Paint

def code_family(+capacity: Nat, +parent: T.Presentation) ->
  {Rule.property_value(Paint.rich_properties_at(capacity, parent), "--rich-code-font") == "var(--font-mono, monospace)" : String}:
  match parent:
    case T.Presentation{tier, emphasis, scale}: {==}

def Rule.evidence():
  Rule.Requirements{+paint => +width => +inset => {==}, paint => width => inset => {==}, paint => +width => +inset => {==}, +capacity => +parent => {==}, +capacity => +parent => {==}, code_family}
