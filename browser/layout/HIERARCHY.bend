import ./natural-size.bend as NaturalSize
import Base
import ./enclosure.bend as E
import ./ACTIVITY.bend as Activity
import ../appearance/TYPOGRAPHY.bend as T

# Positive increments retain the owner/member relations for every calibration.
type Grammar is Data:
  Grammar{member_gap: Nat, heading_extra: Nat, group_extra: Nat, nesting_extra: Nat}

def initial() -> Grammar:
  Grammar{4n, 3n, 7n, 11n}

def for_activity(+capacity: Nat, enabled: Bool, +text: T.Presentation) -> Grammar:
  match enabled:
    case False{}: initial()
    case True{}:
      +member = Activity.length(capacity, text, 4n)
      +heading = Activity.length(capacity, text, 8n)
      Grammar{member, Nat.sub(Nat.sub(heading, member), 1n),
        Nat.sub(Nat.sub(Activity.length(capacity, text, 16n), heading), 1n),
        Nat.sub(Activity.length(capacity, text, 12n), 1n)}

def for_text(capacity: Nat, +text: T.Presentation) -> Grammar:
  for_activity(capacity, T.is_activity(text), text)

def member_gap(grammar: Grammar) -> Nat:
  Grammar{gap, heading_extra, group_extra, nesting_extra} = grammar
  gap

def heading_gap(grammar: Grammar) -> Nat:
  Grammar{gap, heading_extra, group_extra, nesting_extra} = grammar
  Nat.add(Nat.add(gap, heading_extra), 1n)

def group_gap(+grammar: Grammar) -> Nat:
  Grammar{gap, heading_extra, group_extra, nesting_extra} = grammar
  Nat.add(Nat.add(heading_gap(grammar), group_extra), 1n)

def member_inset(grammar: Grammar) -> Nat:
  Grammar{gap, heading_extra, group_extra, nesting_extra} = grammar
  Nat.add(nesting_extra, 1n)

def member_frame(+grammar: Grammar) -> E.Frame:
  E.Frame{E.ambient(member_inset(grammar), 0n), E.EmbeddedContent{member_gap(grammar)}}

def flat_member_frame(grammar: Grammar) -> E.Frame:
  E.Frame{E.ambient(0n, 0n), E.EmbeddedContent{member_gap(grammar)}}

def heading_frame(grammar: Grammar) -> E.Frame:
  E.Frame{E.ambient(0n, 0n), E.EmbeddedContent{heading_gap(grammar)}}

def grouped_frame(grammar: Grammar, area: E.ContentArea) -> E.Frame:
  E.Frame{area, E.EmbeddedContent{group_gap(grammar)}}
