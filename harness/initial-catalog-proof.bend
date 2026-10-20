import Base
import ./tools/MODEL.bend as Tools
import ./DOMAIN.bend as D
import ./INVARIANTS.bend as I
import ./tasks/PROGRAM.bend as Tasks
import ./approval/HOOKS.bend as Hooks
import ../bendlib/categories.bend as Categories

# Schema admission can remove declarations. Keep its decision abstract while
# proving properties that depend only on their native source and names.
def checked_result(+request: Tools.Request, accepted: Bool,
  observed: {Tools.valid_tool(Tools.source(request)) == accepted : Bool}) -> +List<D.Tool>:
  Tools.catalog_constructed(Tools.construct_checked(Tools.Observation{request, Tools.source(request)},
    Tools.correspondence_evidence(request), accepted, observed))

def request_name(request: Tools.Request) -> String:
  Tools.Request{name, description, program} = request
  name

def absent(+name: String, requests: +List<Tools.Request>) -> Bool:
  match requests:
    case Nil{}: True{}
    case Con{+request, rest}:
      Bool.not(String.eq(request_name(request), name)) && absent(name, rest)

def named(requests: +List<Tools.Request>) -> Bool:
  match requests:
    case Nil{}: True{}
    case Con{+request, +rest}:
      D.nonempty(request_name(request)) && (absent(request_name(request), rest) && named(rest))

def left_true(+left: Bool, +right: Bool, evidence: {left && right == True{} : Bool}) -> {left == True{} : Bool}:
  match left:
    case True{}: {==}
    case False{}: evidence

def right_true(+left: Bool, +right: Bool, evidence: {left && right == True{} : Bool}) -> {right == True{} : Bool}:
  match left:
    case True{}: evidence
    case False{}: Categories.impossible({right == True{} : Bool}, evidence)

def not_false(+value: Bool, evidence: {Bool.not(value) == True{} : Bool}) -> {value == False{} : Bool}:
  match value:
    case False{}: {==}
    case True{}: Categories.impossible({True{} == False{} : Bool}, evidence)

def three_true(+first: Bool, +second: Bool, +third: Bool,
  first_true: {first == True{} : Bool}, second_true: {second == True{} : Bool}, third_true: {third == True{} : Bool}) ->
  {first && second && third == True{} : Bool}:
  Equal.trans(Bool, first && second && third, second && third, True{},
    Equal.cong(Bool, Bool, value => value && second && third, first, True{}, first_true),
    Equal.trans(Bool, second && third, third, True{},
      Equal.cong(Bool, Bool, value => value && third, second, True{}, second_true), third_true))

def checked_routes(+request: Tools.Request, +accepted: Bool,
  observed: {Tools.valid_tool(Tools.source(request)) == accepted : Bool}, +rest: +List<D.Tool>,
  rest_routed: {Hooks.routes(rest, Nil{}) == True{} : Bool}) ->
  {Hooks.routes(List.append(&2, D.Tool, checked_result(request, accepted, observed), rest), Nil{}) == True{} : Bool}:
  Tools.Request{name, description, program} = request
  match accepted:
    case False{}: rest_routed
    case True{}: rest_routed

def routes(+requests: +List<Tools.Request>) -> {Hooks.routes(Tools.catalog_requests(requests), Nil{}) == True{} : Bool}:
  match requests:
    case Nil{}: {==}
    case Con{+request, +rest}:
      checked_routes(request, Tools.valid_tool(Tools.source(request)), {==}, Tools.catalog_requests(rest), routes(rest))

def checked_absent(+request: Tools.Request, +accepted: Bool,
  observed: {Tools.valid_tool(Tools.source(request)) == accepted : Bool}, +name: String, +rest: +List<D.Tool>,
  different: {String.eq(request_name(request), name) == False{} : Bool},
  rest_absent: {I.missing_tool(Tasks.find_tool(rest, name)) == True{} : Bool}) ->
  {I.missing_tool(Tasks.find_tool(List.append(&2, D.Tool, checked_result(request, accepted, observed), rest), name)) == True{} : Bool}:
  Tools.Request{+declared_name, +description, +program} = request
  match accepted:
    case False{}: rest_absent
    case True{}:
      Equal.trans(Bool,
        I.missing_tool(Tasks.find_tool(List.append(&2, D.Tool, checked_result(Tools.Request{declared_name, description, program}, True{}, observed), rest), name)),
        I.missing_tool(Tasks.find_tool(rest, name)), True{},
        Equal.cong(Bool, Bool, same => I.missing_tool(Tasks.choose_tool(same,
          Tools.source(Tools.Request{declared_name, description, program}), Tasks.find_tool(rest, name))),
          String.eq(declared_name, name), False{}, different), rest_absent)

def catalog_absent(+requests: +List<Tools.Request>, +name: String,
  +evidence: {absent(name, requests) == True{} : Bool}) ->
  {I.missing_tool(Tasks.find_tool(Tools.catalog_requests(requests), name)) == True{} : Bool}:
  match requests:
    case Nil{}: {==}
    case Con{+request, +rest}:
      checked_absent(request, Tools.valid_tool(Tools.source(request)), {==}, name, Tools.catalog_requests(rest),
        not_false(String.eq(request_name(request), name),
          left_true(Bool.not(String.eq(request_name(request), name)), absent(name, rest), evidence)),
        catalog_absent(rest, name,
          right_true(Bool.not(String.eq(request_name(request), name)), absent(name, rest), evidence)))

def checked_unique(+request: Tools.Request, +accepted: Bool,
  observed: {Tools.valid_tool(Tools.source(request)) == accepted : Bool}, +rest: +List<D.Tool>,
  nonempty: {D.nonempty(request_name(request)) == True{} : Bool},
  fresh: {I.missing_tool(Tasks.find_tool(rest, request_name(request))) == True{} : Bool},
  rest_unique: {I.unique_tools(rest) == True{} : Bool}) ->
  {I.unique_tools(List.append(&2, D.Tool, checked_result(request, accepted, observed), rest)) == True{} : Bool}:
  Tools.Request{+name, description, program} = request
  match accepted:
    case False{}: rest_unique
    case True{}:
      three_true(D.nonempty(name), I.missing_tool(Tasks.find_tool(rest, name)), I.unique_tools(rest), nonempty, fresh, rest_unique)

def unique(+requests: +List<Tools.Request>, +evidence: {named(requests) == True{} : Bool}) ->
  {I.unique_tools(Tools.catalog_requests(requests)) == True{} : Bool}:
  match requests:
    case Nil{}: {==}
    case Con{+request, +rest}:
      checked_unique(request, Tools.valid_tool(Tools.source(request)), {==}, Tools.catalog_requests(rest),
        left_true(D.nonempty(request_name(request)), absent(request_name(request), rest) && named(rest), evidence),
        catalog_absent(rest, request_name(request),
          left_true(absent(request_name(request), rest), named(rest),
            right_true(D.nonempty(request_name(request)), absent(request_name(request), rest) && named(rest), evidence))),
        unique(rest,
          right_true(absent(request_name(request), rest), named(rest),
            right_true(D.nonempty(request_name(request)), absent(request_name(request), rest) && named(rest), evidence))))
