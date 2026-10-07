import Base
import ../../bendlib/logic-proof.bend as Logic
import ../../bendlib/json.bend as J
import ./json-render-rules.bend as Rule

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

# Equality elimination closes the impossible exhausted-budget branches.
def exhausted(+job: J.Render,
  enough: {Nat.is_ge(0n, J.required(job)) == True{} : Bool}) ->
  Rule.Completed(J.render(0n, job)):
  match job:
    case J.One{J.Null{}}: Logic.impossible(Rule.Completed(J.render(0n, J.One{J.Null{}})), enough)
    case J.One{J.Boolean{value}}: Logic.impossible(Rule.Completed(J.render(0n, J.One{J.Boolean{value}})), enough)
    case J.One{J.Number{lexeme}}: Logic.impossible(Rule.Completed(J.render(0n, J.One{J.Number{lexeme}})), enough)
    case J.One{J.Text{value}}: Logic.impossible(Rule.Completed(J.render(0n, J.One{J.Text{value}})), enough)
    case J.One{J.Array{items}}: Logic.impossible(Rule.Completed(J.render(0n, J.One{J.Array{items}})), enough)
    case J.One{J.Object{fields}}: Logic.impossible(Rule.Completed(J.render(0n, J.One{J.Object{fields}})), enough)
    case J.Elements{Nil{}, first}: Logic.impossible(Rule.Completed(J.render(0n, J.Elements{Nil{}, first})), enough)
    case J.Elements{Con{head, tail}, first}:
      Logic.impossible(Rule.Completed(J.render(0n, J.Elements{Con{head, tail}, first})), enough)
    case J.Fields{Nil{}, first}: Logic.impossible(Rule.Completed(J.render(0n, J.Fields{Nil{}, first})), enough)
    case J.Fields{Con{J.Field{key, value}, tail}, first}:
      Logic.impossible(Rule.Completed(J.render(0n, J.Fields{Con{J.Field{key, value}, tail}, first})), enough)

# Base supplies both maximum bounds. This local bridge passes an enclosing
# render budget through such a bound without re-proving the maximum theorems.
def budget_lower_bound(+budget: Nat, +ceiling: Nat, +lower: Nat,
  fits: {Nat.is_ge(budget, ceiling) == True{} : Bool},
  bound: {Nat.is_ge(ceiling, lower) == True{} : Bool}) ->
  {Nat.is_ge(budget, lower) == True{} : Bool}:
  match budget ceiling lower:
    case 0n _ 0n: {==}
    case 1n+rest _ 0n: {==}
    case _ 0n 1n+rest:
      Logic.impossible({Nat.is_ge(budget, 1n+rest) == True{} : Bool}, bound)
    case 0n 1n+rest 1n+lower_rest:
      Logic.impossible({Nat.is_ge(0n, 1n+lower_rest) == True{} : Bool}, fits)
    case 1n+budget_rest 1n+ceiling_rest 1n+lower_rest:
      budget_lower_bound(budget_rest, ceiling_rest, lower_rest, fits, bound)

def joined(+left: Result<&2, &2, String, String>, +right: Result<&2, &2, String, String>,
  left_done: Rule.Completed(left), right_done: Rule.Completed(right)) ->
  Rule.Completed(J.join(left, right)):
  (+a, left_equal) = left_done
  (+b, right_equal) = right_done
  (a ++ b, Equal.trans(Result<&2, &2, String, String>,
    J.join(left, right), J.join(Done{a}, right), Done{a ++ b},
    Equal.cong(Result<&2, &2, String, String>, Result<&2, &2, String, String>,
      (result => J.join(result, right)), left, Done{a}, left_equal),
    Equal.cong(Result<&2, &2, String, String>, Result<&2, &2, String, String>,
      (result => J.join(Done{a}, result)), right, Done{b}, right_equal)))

def surrounded(+left: String, +middle: Result<&2, &2, String, String>, +right: String,
  middle_done: Rule.Completed(middle)) -> Rule.Completed(J.surround(left, middle, right)):
  joined(Done{left}, J.join(middle, Done{right}), (left, {==}),
    joined(middle, Done{right}, middle_done, (right, {==})))

def sufficient(+fuel: Nat, +job: J.Render,
  enough: {Nat.is_ge(fuel, J.required(job)) == True{} : Bool}) ->
  Rule.Completed(J.render(fuel, job)):
  match fuel:
    case 0n: exhausted(job, enough)
    case 1n+remaining:
      match job:
        case J.One{J.Null{}}: ("null", {==})
        case J.One{J.Boolean{value}}: (J.show_bool(value), {==})
        case J.One{J.Number{lexeme}}: (lexeme, {==})
        case J.One{J.Text{value}}: (J.quote(value), {==})
        case J.One{J.Array{items}}:
          surrounded("[", J.render(remaining, J.Elements{items, True{}}), "]",
            sufficient(remaining, J.Elements{items, True{}}, enough))
        case J.One{J.Object{fields}}:
          surrounded("{", J.render(remaining, J.Fields{fields, True{}}), "}",
            sufficient(remaining, J.Fields{fields, True{}}, enough))
        case J.Elements{Nil{}, first}: ("", {==})
        case J.Elements{Con{head, tail}, first}:
          +fits = enough
          +head_job: J.Render = J.One{head}
          +tail_job: J.Render = J.Elements{tail, False{}}
          +head_budget = J.required(head_job)
          +tail_budget = J.required(tail_job)
          surrounded(J.comma(first), J.join(J.render(remaining, head_job), J.render(remaining, tail_job)), "",
            joined(J.render(remaining, head_job), J.render(remaining, tail_job),
              sufficient(remaining, head_job, budget_lower_bound(remaining, Nat.max(head_budget, tail_budget), head_budget,
                fits, Nat.max_ge_l(head_budget, tail_budget))),
              sufficient(remaining, tail_job, budget_lower_bound(remaining, Nat.max(head_budget, tail_budget), tail_budget,
                fits, Nat.max_ge_r(head_budget, tail_budget)))))
        case J.Fields{Nil{}, first}: ("", {==})
        case J.Fields{Con{J.Field{key, value}, tail}, first}:
          +fits = enough
          +head_job: J.Render = J.One{value}
          +tail_job: J.Render = J.Fields{tail, False{}}
          +head_budget = J.required(head_job)
          +tail_budget = J.required(tail_job)
          surrounded(J.comma(first) ++ J.quote(key) ++ ":",
            J.join(J.render(remaining, head_job), J.render(remaining, tail_job)), "",
            joined(J.render(remaining, head_job), J.render(remaining, tail_job),
              sufficient(remaining, head_job, budget_lower_bound(remaining, Nat.max(head_budget, tail_budget), head_budget,
                fits, Nat.max_ge_l(head_budget, tail_budget))),
              sufficient(remaining, tail_job, budget_lower_bound(remaining, Nat.max(head_budget, tail_budget), tail_budget,
                fits, Nat.max_ge_r(head_budget, tail_budget)))))

def render_complete(+job: J.Render) -> Rule.Completed(J.render(J.required(job), job)):
  sufficient(J.required(job), job, Nat.ge_refl(J.required(job)))

def show_complete(+value: J.Json) -> Rule.Completed(J.show(value)):
  render_complete(J.One{value})

def Rule.evidence():
  Rule.Requirements{sufficient, render_complete, show_complete, escape_refines}
