import Base
import ./paint-rules.bend as Rule
import ./TYPOGRAPHY.bend as T
import ./PROGRAM.bend as Paint

def code_family(+capacity: Nat, +parent: T.Presentation) ->
  {Rule.property_value(Paint.rich_properties_at(capacity, parent), "--rich-code-font") == "var(--font-mono, monospace)" : String}:
  match parent:
    case T.Presentation{tier, emphasis, scale}: {==}

def emphasis_preserves_context(+parent: T.Presentation, emphasis: T.Emphasis) ->
  {Rule.presentation_context(T.with_emphasis(parent, emphasis)) == Rule.presentation_context(parent) : (T.Tier & T.Scale)}:
  match parent:
    case T.Presentation{tier, original, scale}: {==}

def emphasis_preserves_resolved_context(+capacity: Nat, +parent: T.Presentation, emphasis: T.Emphasis) ->
  {Rule.resolved_context(T.resolve_presentation(capacity, T.with_emphasis(parent, emphasis))) ==
    Rule.resolved_context(T.resolve_presentation(capacity, parent)) : (T.Font & (Nat & Nat))}:
  match parent:
    case T.Presentation{tier, original, scale}: {==}

def Rule.evidence():
  Rule.Requirements{+paint => +width => +inset => {==}, paint => width => inset => {==}, paint => +width => +inset => {==}, +capacity => +parent => {==}, +capacity => +parent => {==}, +capacity => +parent => {==}, +capacity => +parent => {==}, emphasis_preserves_context, emphasis_preserves_resolved_context, code_family}
