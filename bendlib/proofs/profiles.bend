import Base
import ../domain.bend as D
import ../profile-rules.bend as Rule
import ./logic.bend as Logic
import ../../REASONING.bend as R

# These local eliminators project the actual validity predicates' conjuncts.
def left_true(+left: Bool, +right: Bool, evidence: {(left && right) == True{} : Bool}) ->
  {left == True{} : Bool}:
  match left:
    case True{}: {==}
    case False{}: evidence

def right_true(+left: Bool, +right: Bool, evidence: {(left && right) == True{} : Bool}) ->
  {right == True{} : Bool}:
  match left:
    case True{}: evidence
    case False{}: Logic.impossible({right == True{} : Bool}, evidence)

def both_true(+left: Bool, +right: Bool,
  first: {left == True{} : Bool}, second: {right == True{} : Bool}) ->
  {(left && right) == True{} : Bool}:
  Equal.trans(Bool, left && right, True{} && right, True{},
    Equal.cong(Bool, Bool, (value => value && right), left, True{}, first), second)

def fixed_default(+default: String, +values: +List<String>,
  +valid: {D.policy_options_valid(R.Fixed{}, Some{D.ReasoningOptions{default, values}}) == True{} : Bool}) ->
  {(R.permitted(R.Fixed{}, default) && R.member(values, default)) == True{} : Bool}:
  +options_valid = D.reasoning_options_valid(D.ReasoningOptions{default, values})
  +permitted = R.permitted(R.Fixed{}, default)
  +options_evidence = left_true(options_valid && True{}, permitted, valid)
  +valid_options = left_true(options_valid, True{}, options_evidence)
  both_true(permitted, R.member(values, default),
    right_true(options_valid && True{}, permitted, valid),
    right_true(R.distinct(values), R.member(values, default), valid_options))

def policy_default(+policy: R.Policy, +options: Maybe<&2, D.ReasoningOptions>,
  valid: {D.policy_options_valid(policy, options) == True{} : Bool},
  key: String, provider: String, name: String) ->
  {D.profile_permitted(D.Profile{key, provider, name, policy, options},
    D.profile_default(D.Profile{key, provider, name, policy, options})) == True{} : Bool}:
  match policy options:
    case R.Fixed{} None{}: {==}
    case R.Fixed{} Some{D.ReasoningOptions{+default, +values}}:
      fixed_default(default, values, valid)
    case R.Adaptive{evaluator, efforts, baseline, transport, maximum} None{}: {==}
    case R.Adaptive{evaluator, efforts, baseline, transport, maximum} Some{D.ReasoningOptions{default, values}}:
      valid

def default_permitted(+profile: D.Profile, valid: {D.profile_valid(profile) == True{} : Bool}) ->
  {D.profile_permitted(profile, D.profile_default(profile)) == True{} : Bool}:
  D.Profile{+key, +provider, +name, +policy, +options} = profile
  policy_default(policy, options,
    right_true((D.nonempty(key) && D.nonempty(provider)) && D.nonempty(name),
      D.policy_options_valid(policy, options), valid), key, provider, name)

def fixed_selection_member(key: String, provider: String, name: String,
  default: String, +values: +List<String>, +selection: String,
  accepted: {D.profile_permitted(D.Profile{key, provider, name, R.Fixed{}, Some{D.ReasoningOptions{default, values}}}, selection) == True{} : Bool}) ->
  {R.member(values, selection) == True{} : Bool}:
  right_true(R.permitted(R.Fixed{}, selection), R.member(values, selection), accepted)

def explicit_selection(+profile: D.Profile, +selection: String,
  explicit: {String.eq(selection, "default") == False{} : Bool}) ->
  {D.profile_selection(selection, profile) == selection : String}:
  Equal.cong(Bool, String, (defaulted => D.profile_selection_default(defaulted, selection, profile)),
    String.eq(selection, "default"), False{}, explicit)

def Rule.evidence():
  Rule.Requirements{
    default_permitted, fixed_selection_member,
    profile => {==}, explicit_selection}
