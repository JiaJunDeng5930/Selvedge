import Base
import ../../bendlib/json.bend as J
import ../../bendlib/stdlib.bend as Std

# An evaluator is an external observation, not an authority to change a model,
# call a tool or choose a value outside the task's frozen endpoint policy.
type Transport is Data:
  ConfigurationUpdates{}
  RequestEffort{}

type Policy is Data:
  Fixed{}
  Adaptive{evaluator: String, efforts: +List<String>, baseline: String,
    transport: Transport, max_lease: Nat}

# A lease counts future model generations, including the next generation.
# Tool calls, retries of one HTTP request and compaction do not spend steps.

type Lease is Data:
  NoLease{}
  Lease{effort: String, remaining: Nat}

type Plan is Data:
  FixedPlan{}
  Evaluate{}
  Reuse{effort: String, remaining: Nat}

type Outcome is Data:
  Chosen{effort: String, generations: Nat}
  EvaluationFailed{reason: String}

def Membership() -> Data:
  Sigma<&2, &2, String, (_ => Bool)>

def member_step(state: Membership(), item: String) -> Membership():
  (+query, found) = state
  (query, found || String.eq(item, query))

def member_result(state: Membership()) -> Bool:
  (query, found) = state
  found

def member(values: +List<String>, value: String) -> Bool:
  member_result(List.foldl(~&2, ~String, ~Membership(), ~member_step, values, (value, False{})))

def distinct(values: +List<String>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{+head, +tail}:
      Bool.not(String.eq(head, "")) && Bool.not(String.eq(head, "auto")) &&
        Bool.not(member(tail, head)) && distinct(tail)

def valid(policy: Policy) -> Bool:
  match policy:
    case Fixed{}: True{}
    case Adaptive{evaluator, +efforts, baseline, transport, +maximum}:
      Bool.not(String.eq(evaluator, "")) && member(efforts, baseline) && distinct(efforts) &&
        Nat.is_le(1n, maximum) && Nat.is_le(maximum, 10n)

def automatic(policy: Policy) -> Bool:
  match policy:
    case Fixed{}: False{}
    case Adaptive{evaluator, efforts, baseline, transport, maximum}: True{}

def default_selection(policy: Policy) -> String:
  match policy:
    case Fixed{}: "medium"
    case Adaptive{evaluator, efforts, baseline, transport, maximum}: "auto"

def select_default(defaulted: Bool, value: String, policy: Policy) -> String:
  match defaulted:
    case True{}: default_selection(policy)
    case False{}: value

def selection(+value: String, policy: Policy) -> String:
  select_default(String.eq(value, "default"), value, policy)

def permitted(policy: Policy, +value: String) -> Bool:
  match policy:
    case Fixed{}: Bool.not(String.eq(value, "")) && Bool.not(String.eq(value, "auto"))
    case Adaptive{evaluator, efforts, baseline, transport, maximum}: String.eq(value, "auto")

def allowed(policy: Policy, effort: String) -> Bool:
  match policy:
    case Fixed{}: False{}
    case Adaptive{evaluator, efforts, baseline, transport, maximum}: member(efforts, effort)

def duration(+steps: Nat, maximum: Nat) -> Bool:
  (Nat.is_eq(steps, 1n) || Nat.is_eq(steps, 2n) || Nat.is_eq(steps, 5n) || Nat.is_eq(steps, 10n)) &&
    Nat.is_le(steps, maximum)

def accepts(policy: Policy, effort: String, steps: Nat) -> Bool:
  match policy:
    case Fixed{}: False{}
    case Adaptive{evaluator, efforts, baseline, transport, maximum}:
      member(efforts, effort) && duration(steps, maximum)

def remaining_valid(policy: Policy, remaining: Nat) -> Bool:
  match policy:
    case Fixed{}: False{}
    case Adaptive{evaluator, efforts, baseline, transport, maximum}: Nat.is_lt(remaining, maximum)

def supported(yes: Bool, effort: String, remaining: Nat) -> Plan:
  match yes:
    case True{}: Reuse{effort, remaining}
    case False{}: Evaluate{}

# Independent executable requirement: a positive, supported lease authorizes
# exactly one generation and leaves its predecessor. No lease asks the evaluator.
# The production router is in bendlib/reasoning.bend, not a callback supplied here.

def requirement(policy: Policy, lease: Lease) -> Plan:
  match policy lease:
    case Fixed{} _: FixedPlan{}
    case Adaptive{evaluator, efforts, baseline, transport, maximum} Lease{+effort, 1n+remaining}:
      supported(member(efforts, effort), effort, remaining)
    case _ _: Evaluate{}

def request_effort(policy: Policy, effective: String) -> String:
  match policy:
    case Adaptive{evaluator, efforts, baseline, ConfigurationUpdates{}, maximum}: baseline
    case _: effective

def baseline(policy: Policy, fixed: String) -> String:
  match policy:
    case Fixed{}: fixed
    case Adaptive{evaluator, efforts, baseline, transport, maximum}: baseline

def uses_updates(policy: Policy) -> Bool:
  match policy:
    case Adaptive{evaluator, efforts, baseline, ConfigurationUpdates{}, maximum}: True{}
    case _: False{}

def transport_name(transport: Transport) -> String:
  match transport:
    case ConfigurationUpdates{}: "configuration_update"
    case RequestEffort{}: "request_effort"

def strings(values: +List<String>) -> +List<J.Json>:
  Std.map(~String, ~J.Json, ~(value => J.Text{value}), values)

def json(policy: Policy) -> J.Json:
  match policy:
    case Fixed{}: J.Null{}
    case Adaptive{evaluator, efforts, baseline, transport, maximum}:
      J.Object{[J.Field{"evaluator", J.Text{evaluator}}, J.Field{"efforts", J.Array{strings(efforts)}},
        J.Field{"baseline", J.Text{baseline}}, J.Field{"transport", J.Text{transport_name(transport)}},
        J.Field{"max_lease", J.nat(maximum)}]}

def equal_strings(a: +List<String>, b: +List<String>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case Con{x, xs} Con{y, ys}: String.eq(x, y) && equal_strings(xs, ys)
    case _ _: False{}

def same(a: Policy, b: Policy) -> Bool:
  match a b:
    case Fixed{} Fixed{}: True{}
    case Adaptive{ea, sa, ba, ta, ma} Adaptive{eb, sb, bb, tb, mb}:
      String.eq(ea, eb) && equal_strings(sa, sb) && String.eq(ba, bb) &&
        String.eq(transport_name(ta), transport_name(tb)) && Nat.is_eq(ma, mb)
    case _ _: False{}
