import Base
import ./physical-content.bend as Content
import ./physical-content-rules.bend as Rules
import ./physical-content-measurement.bend as Measurements
import ./physical-source.bend as PhysicalSource
import ./physical-space.bend as Model
import ./physical-allocation.bend as Allocation
import ./source.bend as Source
import ./space.bend as Space
import ./spatial.bend as Spatial
import ./enclosure.bend as Enclosure
import ./document.bend as Doc

type Query is Data:
  Query{generation: Nat, owner_key: String, purpose: Content.Purpose, target: Source.NativeTarget}

type Result is Data:
  Ready{roots: +List<Content.AllocatedNative>}
  NeedsTargets{first: Query, remaining: +List<Query>}
  NeedsMeasurements{first: Content.Request, remaining: +List<Content.Request>}
  Invalid{error: Content.Error}

def select_viewport(matches: Bool, +viewport: Content.NativeViewport, +rest: Maybe<&2, Content.NativeViewport>) -> Maybe<&2, Content.NativeViewport>:
  match matches:
    case True{}: Some{viewport}
    case False{}: rest

def viewport_matches(query: Query, value: Content.NativeViewport) -> Bool:
  Query{generation, owner, purpose, target} = query
  Content.NativeViewport{observed_generation, observed_owner, observed_purpose, observed_target, bounds} = value
  Nat.is_eq(generation, observed_generation) && String.eq(owner, observed_owner)
    && Rules.same_purpose(purpose, observed_purpose)
    && String.eq(Source.target_key(target), Source.target_key(observed_target))

def viewport(+query: Query, values: +List<Content.NativeViewport>) -> Maybe<&2, Content.NativeViewport>:
  match values:
    case Nil{}: None{}
    case Con{+value, rest}:
      select_viewport(viewport_matches(query, value), value, viewport(query, rest))

def absent(found: Maybe<&2, Content.NativeViewport>, +query: Query) -> +List<Query>:
  match found:
    case None{}: [query]
    case Some{value}: Nil{}

def root_queries(roots: +List<Content.NativeRoot>, +generation: Nat, +purpose: Content.Purpose, +viewports: +List<Content.NativeViewport>) -> +List<Query>:
  match roots:
    case Nil{}: Nil{}
    case Con{Content.NativeRoot{owner, target, tree, attrs, style}, rest}:
      +query: Query = Query{generation, owner, purpose, target}
      List.append(&2, Query, absent(viewport(query, viewports), query), root_queries(rest, generation, purpose, viewports))

def policy_queries(policies: +List<Content.NativePolicy>, +generation: Nat, +purpose: Content.Purpose, +viewports: +List<Content.NativeViewport>) -> +List<Query>:
  match policies:
    case Nil{}: Nil{}
    case Con{Content.NativePolicy{owner, target, attrs, style}, rest}:
      +query: Query = Query{generation, owner, purpose, target}
      List.append(&2, Query, absent(viewport(query, viewports), query), policy_queries(rest, generation, purpose, viewports))

def missing_receipt(found: Maybe<&2, Content.Observation>, +request: Content.Request) -> +List<Content.Request>:
  match found:
    case None{}: [request]
    case Some{observation}: Nil{}

def missing(requests: +List<Content.Request>, +observations: +List<Content.Observation>) -> +List<Content.Request>:
  match requests:
    case Nil{}: Nil{}
    case Con{+request, rest}:
      List.append(&2, Content.Request, missing_receipt(Measurements.find(request, observations), request), missing(rest, observations))

def pending_missing(requests: +List<Content.Request>, owner: String) -> Result:
  match requests:
    case Nil{}: Invalid{Content.InvalidNativeContentChildren{owner}}
    case Con{first, remaining}: NeedsMeasurements{first, remaining}

def pending(+prepared: Content.Prepared, requests: +List<Model.HeightRequest<Content.Value>>, observations: +List<Content.Observation>, owner: String) -> Result:
  pending_missing(missing(PhysicalSource.height_requests(prepared, requests), observations), owner)

def allocated(outcome: Allocation.Outcome<Content.Value, Doc.Event>, +prepared: Content.Prepared, +observations: +List<Content.Observation>, +owner: String, +target: Source.NativeTarget) -> Result:
  match outcome:
    case Allocation.Allocated{tree}: Ready{[Content.AllocatedNative{owner, target, tree}]}
    case Allocation.AwaitingHeights{first, remaining}: pending(prepared, first <> remaining, observations, owner)
    case Allocation.Infeasible{failure}: Invalid{Content.InvalidNativeContentChildren{owner}}

def demand_height(demand: Space.Demand) -> Nat:
  Space.Demand{Enclosure.Extent{minimum_width, minimum_height}, Enclosure.Extent{preferred_width, preferred_height}} = demand
  Nat.max(minimum_height, preferred_height)

def final_width(outcome: Allocation.WidthOutcome<Content.Value, Doc.Event>, +tree: Model.Tree<Content.Value, Doc.Event>, +width: Nat, +samples: +List<Model.HeightSample>, +prepared: Content.Prepared, +observations: +List<Content.Observation>, +owner: String, +target: Source.NativeTarget) -> Result:
  match outcome:
    case Allocation.WidthReady{measured}:
      allocated(Allocation.allocate(~Content.Value, ~Doc.Event, tree, Spatial.Box{0n, 0n, width, demand_height(Allocation.measured_demand(~Content.Value, ~Doc.Event, measured))}, samples), prepared, observations, owner, target)
    case Allocation.HeightPending{first, remaining}: pending(prepared, first <> remaining, observations, owner)
    case Allocation.WidthFailure{failure}: Invalid{Content.InvalidNativeContentChildren{owner}}

def sampled_width(requests: +List<Model.HeightRequest<Content.Value>>, +tree: Model.Tree<Content.Value, Doc.Event>, +width: Nat, +prepared: Content.Prepared, +observations: +List<Content.Observation>, +owner: String, +target: Source.NativeTarget) -> Result:
  +samples: +List<Model.HeightSample> = PhysicalSource.height_samples(PhysicalSource.height_requests(prepared, requests), observations)
  final_width(Allocation.fit_width(~Content.Value, ~Doc.Event, tree, width, samples), tree, width, samples, prepared, observations, owner, target)

def initial_width(outcome: Allocation.WidthOutcome<Content.Value, Doc.Event>, +tree: Model.Tree<Content.Value, Doc.Event>, +width: Nat, +prepared: Content.Prepared, +observations: +List<Content.Observation>, +owner: String, +target: Source.NativeTarget) -> Result:
  match outcome:
    case Allocation.WidthReady{measured}: sampled_width(Nil{}, tree, width, prepared, observations, owner, target)
    case Allocation.HeightPending{first, remaining}: sampled_width(first <> remaining, tree, width, prepared, observations, owner, target)
    case Allocation.WidthFailure{failure}: Invalid{Content.InvalidNativeContentChildren{owner}}

def root(found: Maybe<&2, Content.NativeViewport>, +native: Content.NativeRoot, +prepared: Content.Prepared, +observations: +List<Content.Observation>, +query: Query) -> Result:
  match found:
    case None{}: NeedsTargets{query, Nil{}}
    case Some{Content.NativeViewport{generation, viewport_owner, purpose, viewport_target, Spatial.Box{left, top, +width, observed_height}}}:
      Content.NativeRoot{owner, target, +tree, attrs, style} = native
      initial_width(Allocation.fit_width(~Content.Value, ~Doc.Event, tree, width, Nil{}), tree, width, prepared, observations, owner, target)

def merge(first: Result, +rest: Result) -> Result:
  match first:
    case Invalid{error}: Invalid{error}
    case NeedsTargets{first, remaining}: NeedsTargets{first, remaining}
    case Ready{roots}:
      match rest:
        case Ready{tail}: Ready{List.append(&2, Content.AllocatedNative, roots, tail)}
        case Invalid{error}: Invalid{error}
        case NeedsTargets{first, remaining}: NeedsTargets{first, remaining}
        case NeedsMeasurements{first, remaining}: NeedsMeasurements{first, remaining}
    case NeedsMeasurements{first, remaining}:
      match rest:
        case Invalid{error}: Invalid{error}
        case NeedsTargets{query, queries}: NeedsTargets{query, queries}
        case Ready{roots}: NeedsMeasurements{first, remaining}
        case NeedsMeasurements{next, tail}: NeedsMeasurements{first, List.append(&2, Content.Request, remaining, next <> tail)}

def roots(values: +List<Content.NativeRoot>, +prepared: Content.Prepared, +observations: +List<Content.Observation>, +viewports: +List<Content.NativeViewport>, +generation: Nat, +purpose: Content.Purpose) -> Result:
  match values:
    case Nil{}: Ready{Nil{}}
    case Con{+native, rest}:
      Content.NativeRoot{owner, target, tree, attrs, style} = native
      +query: Query = Query{generation, owner, purpose, target}
      merge(root(viewport(query, viewports), native, prepared, observations, query), roots(rest, prepared, observations, viewports, generation, purpose))

def targets(queries: +List<Query>, +native_roots: +List<Content.NativeRoot>, +prepared: Content.Prepared, +observations: +List<Content.Observation>, +viewports: +List<Content.NativeViewport>, +generation: Nat, +purpose: Content.Purpose) -> Result:
  match queries:
    case Con{first, remaining}: NeedsTargets{first, remaining}
    case Nil{}: roots(native_roots, prepared, observations, viewports, generation, purpose)

# Ownership comes from the immutable prepared physical tree, never request-carried roots.
def rich_owner(values: +List<Model.Tree<Content.Value, Doc.Event>>, +owner: String) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{Model.Leaf{key, Content.Value{Source.RichText{label, style, content, attachments}, font}, interaction, rule, demand, height}, rest}:
      String.eq(key, owner) || rich_owner(rest, owner)
    case Con{Model.Leaf{key, value, interaction, rule, demand, height}, rest}: rich_owner(rest, owner)
    case Con{Model.Container{key, value, interaction, rule, children}, rest}: rich_owner(children, owner) || rich_owner(rest, owner)

def prepared_snapshot(prepared: Content.Prepared) -> Content.Snapshot:
  Content.Prepared{snapshot, tree, roots, policies} = prepared
  snapshot

def prepared_tree(prepared: Content.Prepared) -> Model.Tree<Content.Value, Doc.Event>:
  Content.Prepared{snapshot, tree, roots, policies} = prepared
  tree

def request_key(request: Content.Request) -> String:
  Content.Request{generation, key, value, purpose, roots, policies} = request
  key

def rich_request(request: Content.Request) -> Bool:
  match request:
    case Content.Request{generation, key, Content.Value{Source.RichText{label, style, content, attachments}, font}, Content.AtWidth{width}, native_roots, native_policies}: True{}
    case Content.Request{generation, key, value, purpose, native_roots, native_policies}: False{}

def owned_resolution(+prepared: Content.Prepared, +generation: Nat, +owner: String, +purpose: Content.Purpose, +observations: +List<Content.Observation>, +viewports: +List<Content.NativeViewport>, all_roots: +List<Content.NativeRoot>, all_policies: +List<Content.NativePolicy>) -> Result:
  +native_roots: +List<Content.NativeRoot> = PhysicalSource.owned_root(all_roots, owner)
  +native_policies: +List<Content.NativePolicy> = PhysicalSource.owned_policy(all_policies, owner)
  targets(List.append(&2, Query, root_queries(native_roots, generation, purpose, viewports), policy_queries(native_policies, generation, purpose, viewports)), native_roots, prepared, observations, viewports, generation, purpose)

def request_resolution(+prepared: Content.Prepared, request: Content.Request, +observations: +List<Content.Observation>, +viewports: +List<Content.NativeViewport>, +all_roots: +List<Content.NativeRoot>, +all_policies: +List<Content.NativePolicy>) -> Result:
  Content.Request{generation, owner, value, purpose, supplied_roots, supplied_policies} = request
  owned_resolution(prepared, generation, owner, purpose, observations, viewports, all_roots, all_policies)

def prepared_resolution(prepared: Content.Prepared, +request: Content.Request, +observations: +List<Content.Observation>, +viewports: +List<Content.NativeViewport>) -> Result:
  Content.Prepared{+snapshot, +tree, +all_roots, +all_policies} = prepared
  request_resolution(Content.Prepared{snapshot, tree, all_roots, all_policies}, request, observations, viewports, all_roots, all_policies)

def resolve_valid(valid: Bool, +prepared: Content.Prepared, +request: Content.Request, +observations: +List<Content.Observation>, +viewports: +List<Content.NativeViewport>) -> Result:
  match valid:
    case False{}: Invalid{Content.InvalidNativeOwner{request_key(request)}}
    case True{}: prepared_resolution(prepared, request, observations, viewports)

def resolve(+prepared: Content.Prepared, +request: Content.Request, +observations: +List<Content.Observation>, +viewports: +List<Content.NativeViewport>) -> Result:
  resolve_valid(rich_request(request) && Rules.same_request_owner(prepared_snapshot(prepared), request)
    && rich_owner([prepared_tree(prepared)], request_key(request)), prepared, request, observations, viewports)
