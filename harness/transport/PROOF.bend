import Base
import ../MODEL.bend as M
import ../PROGRAM.bend as P
import ../LAWS.bend as Laws
import ../../bendlib/json.bend as J
import ../protocol/COMMIT.bend as Commit
import ../execution/PROGRAM.bend as Execution
import ./MODEL.bend as Interface
import ./wire.bend as Wire
import ../protocol/commit-proof.bend as CommitProof
import ../../bendlib/logic-proof.bend as Logic
import ./CONTRACT.bend as Rule
import ../DOMAIN.bend as D
import ../reasoning/MODEL.bend as R
import ../reasoning/SPEC.bend as ReasoningRequirements
import ../reasoning/PROOF.bend as ReasoningProof

# Local proof obligations for the frontend boundary. No runtime policy lives here.
def Laws.frontend_input(input, world):
  match input:
    case Fail{reason}: {==}
    case Done{+input}:
      Equal.cong(M.Decision(), Interface.Output, (decision => Interface.Output{decision, M.durable(input)}),
        P.transition(input, world), Commit.input(~Execution.scheduled, input, world),
        Laws.interaction_transition(input, world))

def Laws.frontend_json(json, world):
  match json:
    case Fail{reason}: {==}
    case Done{json}: Laws.frontend_input(Wire.decode(json), world)

def Laws.frontend_packet(tokens, world):
  Laws.frontend_json(J.decode(tokens), world)

def escape_append_empty(+text: String) -> {text ++ "" == text : String}:
  match text:
    case SNil{}: {==}
    case SCon{+head, +rest}:
      Equal.cong(String, String, (tail => SCon{head, tail}), rest ++ "", rest,
        escape_append_empty(rest))

def escape_append_associative(+first: String, +second: String, +third: String) ->
  {(first ++ second) ++ third == first ++ (second ++ third) : String}:
  match first:
    case SNil{}: {==}
    case SCon{+head, +rest}:
      Equal.cong(String, String, (tail => SCon{head, tail}),
        (rest ++ second) ++ third, rest ++ (second ++ third),
        escape_append_associative(rest, second, third))

def escape_collected_refines(+text: String, +parts: +List<String>, +suffix: String) ->
  {J.escape_join(J.escape_collect(text, parts), suffix) ==
    J.escape_join(parts, Rule.required_escape(text) ++ suffix) : String}:
  match text:
    case SNil{}: {==}
    case SCon{Chr{+code}, +rest}:
      Equal.trans(String,
        J.escape_join(J.escape_collect(rest, Con{J.escaped_char(code), parts}), suffix),
        J.escape_join(parts, J.escaped_char(code) ++ (Rule.required_escape(rest) ++ suffix)),
        J.escape_join(parts, (J.escaped_char(code) ++ Rule.required_escape(rest)) ++ suffix),
        escape_collected_refines(rest, Con{J.escaped_char(code), parts}, suffix),
        Equal.cong(String, String, (tail => J.escape_join(parts, tail)),
          J.escaped_char(code) ++ (Rule.required_escape(rest) ++ suffix),
          (J.escaped_char(code) ++ Rule.required_escape(rest)) ++ suffix,
          Equal.sym(String,
            (J.escaped_char(code) ++ Rule.required_escape(rest)) ++ suffix,
            J.escaped_char(code) ++ (Rule.required_escape(rest) ++ suffix),
            escape_append_associative(J.escaped_char(code), Rule.required_escape(rest), suffix))))

def escape_refines(+text: String) -> {J.escape(text) == Rule.required_escape(text) : String}:
  Equal.trans(String, J.escape(text), Rule.required_escape(text) ++ "", Rule.required_escape(text),
    escape_collected_refines(text, Nil{}, ""), escape_append_empty(Rule.required_escape(text)))

def Rule.json_render_evidence():
  Rule.JsonRenderRequirements{J.sufficient, J.render_complete, J.show_complete, escape_refines}

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

def Rule.profile_evidence():
  Rule.ProfileRequirements{
    default_permitted, fixed_selection_member,
    profile => {==}, explicit_selection}

def Rule.model_request_mode(task, ticket, model, history, tools, callable, context, scope, reserve):
  Equal.cong(D.OutputMode, J.Json, mode => J.Text{D.output_mode_name(mode)},
    D.history_output_mode(history), ReasoningRequirements.request_mode(history), ReasoningProof.request_mode_meaning(history))
