import Base
import ../bendlib/json.bend as J
import ./physical-content.bend as Content
import ./physical-content-rules.bend as ContentRules
import ./physical-content-measurement.bend as Measurements
import ./physical-source.bend as PhysicalSource
import ./physical-native.bend as Native
import ./physical-plan.bend as PhysicalPlan
import ./physical-allocation.bend as Allocation
import ./physical-space.bend as SpaceModel
import ./spatial.bend as Spatial
import ./source.bend as Source
import ./document.bend as Doc
type ReceiptStatus is Data:
  Unchanged{}
  Accepted{}
  Rejected{reason: String}
type Engine is Data:
  Engine{snapshot: Content.Snapshot, viewport: Spatial.Box,
    observations: +List<Content.Observation>, viewports: +List<Content.NativeViewport>, receipt_status: ReceiptStatus}
def observations(state: Engine) -> +List<Content.Observation>:
  Engine{value_snapshot, value_viewport, value_observations, value_viewports, value_receipt_status} = state
  value_observations

def viewports(state: Engine) -> +List<Content.NativeViewport>:
  Engine{value_snapshot, value_viewport, value_observations, value_viewports, value_receipt_status} = state
  value_viewports

def initial(snapshot: Content.Snapshot, viewport: Spatial.Box) -> Engine:
  Engine{snapshot, viewport, Nil{}, Nil{}, Unchanged{}}

def snapshot(engine: Engine) -> Content.Snapshot:
  Engine{snapshot, viewport, observations, viewports, status} = engine
  snapshot

def viewport(engine: Engine) -> Spatial.Box:
  Engine{snapshot, viewport, observations, viewports, status} = engine
  viewport

def snapshot_generation(snapshot: Content.Snapshot) -> Nat:
  Content.Snapshot{generation, source, font} = snapshot
  generation

def receipt_status(engine: Engine) -> ReceiptStatus:
  Engine{snapshot, viewport, observations, viewports, status} = engine
  status

def measure_jobs(requests: +List<Content.Request>) -> +List<PhysicalPlan.Job>:
  match requests:
    case Nil{}: Nil{}
    case Con{request, rest}: PhysicalPlan.Job{request, Nil{}, PhysicalPlan.Measure{}} <> measure_jobs(rest)

type Discovery is Data:
  Discovered{jobs: +List<PhysicalPlan.Job>, roots: +List<Content.AllocatedNative>}
  InvalidDiscovery{error: Content.Error}
def merge(first: Discovery, +second: Discovery) -> Discovery:
  match first:
    case InvalidDiscovery{error}: InvalidDiscovery{error}
    case Discovered{jobs, roots}:
      match second:
        case InvalidDiscovery{error}: InvalidDiscovery{error}
        case Discovered{next_jobs, next_roots}:
          Discovered{List.append(&2, PhysicalPlan.Job, jobs, next_jobs), List.append(&2, Content.AllocatedNative, roots, next_roots)}

def absent(found: Maybe<&2, Content.Observation>, request: Content.Request, +roots: +List<Content.AllocatedNative>) -> Discovery:
  match found:
    case None{}: Discovered{[PhysicalPlan.Job{request, roots, PhysicalPlan.Measure{}}], roots}
    case Some{value}: Discovered{Nil{}, roots}

def native_result(result: Native.NativeAllocation, +request: Content.Request, +observations: +List<Content.Observation>) -> Discovery:
  match result:
    case Native.Invalid{error}: InvalidDiscovery{error}
    case Native.NeedsTargets{first, remaining}: Discovered{[PhysicalPlan.Job{request, Nil{}, PhysicalPlan.TargetsOnly{}}], Nil{}}
    case Native.NeedsMeasurements{first, remaining}: Discovered{measure_jobs(first <> remaining), Nil{}}
    case Native.Ready{+roots}: absent(Measurements.find(request, observations), request, roots)

def discover_one(rich: Bool, +prepared: Content.Prepared, +request: Content.Request,
  +observations: +List<Content.Observation>, +viewports: +List<Content.NativeViewport>) -> Discovery:
  match rich:
    case True{}: native_result(Native.resolve(prepared, request, observations, viewports), request, observations)
    case False{}: absent(Measurements.find(request, observations), request, Nil{})

def discover(requests: +List<Content.Request>, +prepared: Content.Prepared,
  +observations: +List<Content.Observation>, +viewports: +List<Content.NativeViewport>) -> Discovery:
  match requests:
    case Nil{}: Discovered{Nil{}, Nil{}}
    case Con{+request, rest}:
      merge(discover_one(Native.rich_request(request), prepared, request, observations, viewports), discover(rest, prepared, observations, viewports))

def pending(jobs: +List<PhysicalPlan.Job>, generation: Nat) -> PhysicalPlan.Plan:
  match jobs:
    case Con{first, remaining}: PhysicalPlan.Awaiting{generation, first, remaining}
    case Nil{}: PhysicalPlan.Invalid{Content.InvalidObservation{"missing height request"}}

def allocated_result(result: Allocation.Outcome<Content.Value, Doc.DOMEvent>, +prepared: Content.Prepared,
  +snapshot: Content.Snapshot, roots: +List<Content.AllocatedNative>, policies: +List<Content.NativePolicy>) -> PhysicalPlan.Plan:
  match result:
    case Allocation.Allocated{tree}: PhysicalPlan.Ready{Content.AllocatedWorld{snapshot, tree, roots, policies}}
    case Allocation.Infeasible{failure}: PhysicalPlan.Infeasible{failure}
    case Allocation.AwaitingHeights{first, remaining}:
      pending(measure_jobs(PhysicalSource.height_requests(prepared, first <> remaining)), snapshot_generation(snapshot))

def allocated(result: Allocation.Outcome<Content.Value, Doc.DOMEvent>, +prepared: Content.Prepared,
  roots: +List<Content.AllocatedNative>) -> PhysicalPlan.Plan:
  Content.Prepared{snapshot, tree, native_roots, policies} = prepared
  allocated_result(result, prepared, snapshot, roots, policies)

def discovered_result(result: Discovery, +prepared: Content.Prepared, viewport: Spatial.Box,
  requests: +List<Content.Request>, observations: +List<Content.Observation>, +snapshot: Content.Snapshot,
  tree: SpaceModel.Tree<Content.Value, Doc.DOMEvent>) -> PhysicalPlan.Plan:
  match result:
    case InvalidDiscovery{error}: PhysicalPlan.Invalid{error}
    case Discovered{Con{first, remaining}, roots}: PhysicalPlan.Awaiting{snapshot_generation(snapshot), first, remaining}
    case Discovered{Nil{}, roots}:
      allocated(Allocation.allocate(~Content.Value, ~Doc.DOMEvent, tree, viewport, PhysicalSource.height_samples(requests, observations)), prepared, roots)

def discovered(result: Discovery, +prepared: Content.Prepared, viewport: Spatial.Box,
  requests: +List<Content.Request>, observations: +List<Content.Observation>) -> PhysicalPlan.Plan:
  Content.Prepared{snapshot, tree, native_roots, policies} = prepared
  discovered_result(result, prepared, viewport, requests, observations, snapshot, tree)

def width_result(result: Allocation.WidthOutcome<Content.Value, Doc.DOMEvent>, +prepared: Content.Prepared,
  +viewport: Spatial.Box, +observations: +List<Content.Observation>, viewports: +List<Content.NativeViewport>) -> PhysicalPlan.Plan:
  match result:
    case Allocation.WidthFailure{failure}: PhysicalPlan.Infeasible{failure}
    case Allocation.WidthReady{tree}: discovered(Discovered{Nil{}, Nil{}}, prepared, viewport, Nil{}, observations)
    case Allocation.HeightPending{first, remaining}:
      +requests = PhysicalSource.height_requests(prepared, first <> remaining)
      discovered(discover(requests, prepared, observations, viewports), prepared, viewport, requests, observations)

def preparation(result: Content.Preparation, +viewport: Spatial.Box,
  observations: +List<Content.Observation>, viewports: +List<Content.NativeViewport>) -> PhysicalPlan.Plan:
  match result:
    case Content.Invalid{snapshot, error}: PhysicalPlan.Invalid{error}
    case Content.NeedsMeasurements{snapshot, first, remaining}: pending(measure_jobs(first <> remaining), snapshot_generation(snapshot))
    case Content.Ready{+prepared}:
      Content.Prepared{snapshot, tree, native_roots, policies} = prepared
      Spatial.Box{left, top, width, height} = viewport
      # Width discovery stays independent of receipts so native roots remain present.
      width_result(Allocation.fit_width(~Content.Value, ~Doc.DOMEvent, tree, width, Nil{}), prepared, viewport, observations, viewports)

def plan(engine: Engine) -> PhysicalPlan.Plan:
  Engine{+snapshot, viewport, +observations, viewports, status} = engine
  preparation(PhysicalSource.prepare(snapshot, observations), viewport, observations, viewports)

def plan_jobs(plan: PhysicalPlan.Plan) -> +List<PhysicalPlan.Job>:
  match plan:
    case PhysicalPlan.Awaiting{generation, first, remaining}: first <> remaining
    case _: Nil{}

def request_matches(request: Content.Request, key: String, purpose: Content.Purpose) -> Bool:
  Content.Request{generation, request_key, value, request_purpose, roots, policies} = request
  String.eq(request_key, key) && ContentRules.same_purpose(request_purpose, purpose)

def pick_job(matches: Bool, +request: Content.Request, rest: Maybe<&2, Content.Request>) -> Maybe<&2, Content.Request>:
  match matches:
    case True{}: Some{request}
    case False{}: rest

def same_mode(first: PhysicalPlan.ProbeMode, second: PhysicalPlan.ProbeMode) -> Bool:
  match first second:
    case PhysicalPlan.Measure{} PhysicalPlan.Measure{}: True{}
    case PhysicalPlan.TargetsOnly{} PhysicalPlan.TargetsOnly{}: True{}
    case _ _: False{}

def find_job(jobs: +List<PhysicalPlan.Job>, +key: String, +purpose: Content.Purpose, +mode: PhysicalPlan.ProbeMode) -> Maybe<&2, Content.Request>:
  match jobs:
    case Nil{}: None{}
    case Con{PhysicalPlan.Job{+request, roots, job_mode}, rest}:
      pick_job(same_mode(mode, job_mode) && request_matches(request, key, purpose), request, find_job(rest, key, purpose, mode))

def purpose_result(result: Maybe<&2, Nat>) -> Maybe<&2, Content.Purpose>:
  match result:
    case Some{width}: Some{Content.AtWidth{width}}
    case None{}: None{}

def purpose(value: J.Json) -> Maybe<&2, Content.Purpose>:
  match value:
    case J.Null{}: Some{Content.Natural{}}
    case J.Number{lexeme}:
      purpose_result(J.natural(J.Number{lexeme}))
    case _: None{}

def contains(values: +List<String>, +value: String) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{first, rest}: String.eq(first, value) || contains(rest, value)

def unique_fields(fields: +List<J.Field>, +seen: +List<String>) -> Bool:
  match fields:
    case Nil{}: True{}
    case Con{J.Field{+name, value}, rest}: Bool.not(contains(seen, name)) && unique_fields(rest, name <> seen)

def fields_allowed(fields: +List<J.Field>, +allowed: +List<String>) -> Bool:
  match fields:
    case Nil{}: True{}
    case Con{J.Field{name, value}, rest}: contains(allowed, name) && fields_allowed(rest, allowed)

def object_fields(value: J.Json, allowed: +List<String>) -> Bool:
  match value:
    case J.Object{+fields}: unique_fields(fields, Nil{}) && fields_allowed(fields, allowed)
    case _: False{}

def has_named_field(fields: +List<J.Field>, +name: String) -> Bool:
  match fields:
    case Nil{}: False{}
    case Con{J.Field{key, value}, rest}: String.eq(key, name) || has_named_field(rest, name)

type Batch is Data:
  Batch{observations: +List<Content.Observation>, viewports: +List<Content.NativeViewport>}
def has_field(value: J.Json, name: String) -> Bool:
  match value:
    case J.Object{fields}: has_named_field(fields, name)
    case _: False{}

def observation_present_result(result: Maybe<&2, Content.Observation>) -> Bool:
  match result:
    case None{}: False{}
    case Some{value}: True{}

def observation_present(request: Content.Request, values: +List<Content.Observation>) -> Bool:
  observation_present_result(Measurements.find(request, values))

def measurement_guard(member: Bool, valid: Bool, +request: Content.Request, batch: Batch) -> Bool:
  Batch{observations, viewports} = batch
  member && valid && Bool.not(observation_present(request, observations))

def measurement_valid_result(result: Bool, observation: Content.Observation, observations: +List<Content.Observation>, viewports: +List<Content.NativeViewport>) -> Result<&2, &2, String, Batch>:
  match result:
    case True{}: Done{Batch{observation <> observations, viewports}}
    case False{}: Fail{"invalid or duplicate physical measurement"}

def measurement_valid_member(member: Bool, valid: Bool, +request: Content.Request, +observation: Content.Observation, +batch: Batch) -> Result<&2, &2, String, Batch>:
  Batch{observations, viewports} = batch
  measurement_valid_result(measurement_guard(member, valid, request, batch), observation, observations, viewports)

def measurement_valid(valid: Bool, +request: Content.Request, +observation: Content.Observation, batch: Batch) -> Result<&2, &2, String, Batch>:
  measurement_valid_member(ContentRules.observation_matches(request, observation), valid, request, observation, batch)

def is_natural_result(result: Maybe<&2, Nat>) -> Bool:
  match result:
    case Some{number}: True{}
    case None{}: False{}

def is_natural(value: J.Json) -> Bool:
  is_natural_result(J.natural(value))

def number(value: J.Json) -> Nat:
  J.natural_or(J.natural(value), 0n)

def measurement_request(found: Maybe<&2, Content.Request>, +value: J.Json, batch: Batch) -> Result<&2, &2, String, Batch>:
  match found:
    case None{}: Fail{"unexpected physical measurement"}
    case Some{+request}:
      Content.Request{generation, key, content, purpose, roots, policies} = request
      measurement_valid(object_fields(value, ["key", "width", "minimum_width", "preferred_width", "content_height", "reference_advance"]) && is_natural(J.get(value, "minimum_width"))
        && is_natural(J.get(value, "preferred_width")) && is_natural(J.get(value, "content_height"))
        && is_natural(J.get(value, "reference_advance")), request,
        Content.Observation{generation, key, purpose, number(J.get(value, "minimum_width")),
          number(J.get(value, "preferred_width")), number(J.get(value, "content_height")), number(J.get(value, "reference_advance"))}, batch)

def measurement_purpose(parsed: Maybe<&2, Content.Purpose>, +value: J.Json, jobs: +List<PhysicalPlan.Job>, batch: Batch) -> Result<&2, &2, String, Batch>:
  match parsed:
    case None{}: Fail{"invalid physical measurement width"}
    case Some{purpose}:
      measurement_request(find_job(jobs, J.text(J.get(value, "key")), purpose, PhysicalPlan.Measure{}), value, batch)

def measurement_result(result: Bool, +value: J.Json, jobs: +List<PhysicalPlan.Job>, batch: Batch) -> Result<&2, &2, String, Batch>:
  match result:
    case True{}: measurement_purpose(purpose(J.get(value, "width")), value, jobs, batch)
    case False{}: Fail{"invalid physical measurement identity"}

def measurement(value: J.Json, jobs: +List<PhysicalPlan.Job>, batch: Batch) -> Result<&2, &2, String, Batch>:
  +value = value
  measurement_result(has_field(value, "width") && J.is_text(J.get(value, "key")), value, jobs, batch)

def pick_target(matches: Bool, +target: Source.NativeTarget, rest: Maybe<&2, Source.NativeTarget>) -> Maybe<&2, Source.NativeTarget>:
  match matches:
    case True{}: Some{target}
    case False{}: rest

def policy_target(policies: +List<Content.NativePolicy>, +key: String) -> Maybe<&2, Source.NativeTarget>:
  match policies:
    case Nil{}: None{}
    case Con{Content.NativePolicy{owner, +target, attributes, style}, rest}:
      pick_target(String.eq(Source.target_key(target), key), target, policy_target(rest, key))

def root_target(roots: +List<Content.NativeRoot>, +policies: +List<Content.NativePolicy>, +key: String) -> Maybe<&2, Source.NativeTarget>:
  match roots:
    case Nil{}: policy_target(policies, key)
    case Con{Content.NativeRoot{owner, +target, tree, attributes, style}, rest}:
      pick_target(String.eq(Source.target_key(target), key), target, root_target(rest, policies, key))

def target_present_result(result: Maybe<&2, Content.NativeViewport>) -> Bool:
  match result:
    case None{}: False{}
    case Some{value}: True{}

def target_present(query: Native.Query, values: +List<Content.NativeViewport>) -> Bool:
  target_present_result(Native.viewport(query, values))

def target_found_result(result: Bool, +value: J.Json, generation: Nat, owner: String, purpose: Content.Purpose, target: Source.NativeTarget, observations: +List<Content.Observation>, viewports: +List<Content.NativeViewport>) -> Result<&2, &2, String, Batch>:
  match result:
    case False{}: Fail{"invalid or duplicate native target"}
    case True{}: Done{Batch{observations, Content.NativeViewport{generation, owner, purpose, target,
      Spatial.Box{number(J.get(value, "left")), number(J.get(value, "top")),
        number(J.get(value, "target_width")), number(J.get(value, "target_height"))}} <> viewports}}

def target_found(found: Maybe<&2, Source.NativeTarget>, +request: Content.Request, +value: J.Json, batch: Batch) -> Result<&2, &2, String, Batch>:
  match found:
    case None{}: Fail{"unexpected native target identity"}
    case Some{+target}:
      Content.Request{+generation, +owner, content, +purpose, roots, policies} = request
      Batch{observations, +viewports} = batch
      target_found_result(object_fields(value, ["owner_key", "width", "target", "left", "top", "target_width", "target_height"]) && is_natural(J.get(value, "left")) && is_natural(J.get(value, "top")) && is_natural(J.get(value, "target_width")) && is_natural(J.get(value, "target_height")) && Bool.not(target_present(Native.Query{generation, owner, purpose, target}, viewports)), value, generation, owner, purpose, target, observations, viewports)

def target_request(found: Maybe<&2, Content.Request>, +value: J.Json, batch: Batch) -> Result<&2, &2, String, Batch>:
  match found:
    case None{}: Fail{"unexpected native target request"}
    case Some{+request}:
      Content.Request{generation, key, content, purpose, roots, policies} = request
      target_found(root_target(roots, policies, J.text(J.get(value, "target"))), request, value, batch)

def target_result(result: Bool, +value: J.Json, jobs: +List<PhysicalPlan.Job>, batch: Batch) -> Result<&2, &2, String, Batch>:
  match result:
    case False{}: Fail{"invalid native target request identity"}
    case True{}: target_request(find_job(jobs, J.text(J.get(value, "owner_key")),
      Content.AtWidth{number(J.get(value, "width"))}, PhysicalPlan.TargetsOnly{}), value, batch)

def target(value: J.Json, jobs: +List<PhysicalPlan.Job>, batch: Batch) -> Result<&2, &2, String, Batch>:
  +value = value
  target_result(J.is_text(J.get(value, "owner_key")) && J.is_text(J.get(value, "target")) && is_natural(J.get(value, "width")), value, jobs, batch)

def measurements(values: +List<J.Json>, +jobs: +List<PhysicalPlan.Job>, result: Result<&2, &2, String, Batch>) -> Result<&2, &2, String, Batch>:
  match values result:
    case Nil{} Done{batch}: Done{batch}
    case Nil{} Fail{error}: Fail{error}
    case Con{value, rest} Done{batch}: measurements(rest, jobs, measurement(value, jobs, batch))
    case Con{value, rest} Fail{error}: Fail{error}

def targets(values: +List<J.Json>, +jobs: +List<PhysicalPlan.Job>, result: Result<&2, &2, String, Batch>) -> Result<&2, &2, String, Batch>:
  match values result:
    case Nil{} Done{batch}: Done{batch}
    case Nil{} Fail{error}: Fail{error}
    case Con{value, rest} Done{batch}: targets(rest, jobs, target(value, jobs, batch))
    case Con{value, rest} Fail{error}: Fail{error}

def decode_arrays(measurements_value: J.Json, targets_value: J.Json, +jobs: +List<PhysicalPlan.Job>) -> Result<&2, &2, String, Batch>:
  match measurements_value targets_value:
    case J.Array{measurement_values} J.Array{target_values}:
      targets(target_values, jobs, measurements(measurement_values, jobs, Done{Batch{Nil{}, Nil{}}}))
    case _ _: Fail{"physical receipts require measurements and targets arrays"}

def decode_receipts_result(result: Bool, +value: J.Json, jobs: +List<PhysicalPlan.Job>) -> Result<&2, &2, String, Batch>:
  match result:
    case False{}: Fail{"invalid physical receipt object"}
    case True{}: decode_arrays(J.get(value, "measurements"), J.get(value, "targets"), jobs)

def decode_receipts(result: Result<&2, &2, String, J.Json>, jobs: +List<PhysicalPlan.Job>) -> Result<&2, &2, String, Batch>:
  match result:
    case Fail{error}: Fail{error}
    case Done{+value}:
      decode_receipts_result(object_fields(value, ["measurements", "targets"]), value, jobs)

def observation_identity(observation: Content.Observation, candidate: Content.Observation) -> Bool:
  Content.Observation{generation, key, purpose, minimum, preferred, height, advance} = observation
  Content.Observation{other_generation, other_key, other_purpose, other_minimum, other_preferred, other_height, other_advance} = candidate
  Nat.is_eq(generation, other_generation) && String.eq(key, other_key) && ContentRules.same_purpose(purpose, other_purpose)

def remove_observation_result(result: Bool, value: Content.Observation, filtered_tail: +List<Content.Observation>) -> +List<Content.Observation>:
  match result:
    case True{}: filtered_tail
    case False{}: value <> filtered_tail

def remove_observation(values: +List<Content.Observation>, +replacement: Content.Observation) -> +List<Content.Observation>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}:
      remove_observation_result(observation_identity(value, replacement), value, remove_observation(rest, replacement))

def put_observations(values: +List<Content.Observation>, old: +List<Content.Observation>) -> +List<Content.Observation>:
  match values:
    case Nil{}: old
    case Con{+value, rest}: put_observations(rest, value <> remove_observation(old, value))

def viewport_identity(viewport: Content.NativeViewport, candidate: Content.NativeViewport) -> Bool:
  Content.NativeViewport{generation, owner, purpose, target, bounds} = viewport
  Native.viewport_matches(Native.Query{generation, owner, purpose, target}, candidate)

def remove_viewport_result(result: Bool, value: Content.NativeViewport, filtered_tail: +List<Content.NativeViewport>) -> +List<Content.NativeViewport>:
  match result:
    case True{}: filtered_tail
    case False{}: value <> filtered_tail

def remove_viewport(values: +List<Content.NativeViewport>, +replacement: Content.NativeViewport) -> +List<Content.NativeViewport>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}:
      remove_viewport_result(viewport_identity(value, replacement), value, remove_viewport(rest, replacement))

def put_viewports(values: +List<Content.NativeViewport>, old: +List<Content.NativeViewport>) -> +List<Content.NativeViewport>:
  match values:
    case Nil{}: old
    case Con{+value, rest}: put_viewports(rest, value <> remove_viewport(old, value))

def received_result(result: Result<&2, &2, String, Batch>, snapshot: Content.Snapshot, viewport: Spatial.Box, observations: +List<Content.Observation>, viewports: +List<Content.NativeViewport>) -> Engine:
  match result:
    case Fail{reason}: Engine{snapshot, viewport, observations, viewports, Rejected{reason}}
    case Done{Batch{new_observations, new_viewports}}:
      Engine{snapshot, viewport, put_observations(new_observations, observations), put_viewports(new_viewports, viewports), Accepted{}}

def received(result: Result<&2, &2, String, Batch>, engine: Engine) -> Engine:
  Engine{snapshot, viewport, observations, viewports, status} = engine
  received_result(result, snapshot, viewport, observations, viewports)

def receive_current(current: Bool, receipts: +List<String>, +engine: Engine) -> Engine:
  match current:
    case False{}: engine
    case True{}: received(decode_receipts(J.decode(receipts), plan_jobs(plan(engine))), engine)

def receive(generation: Nat, receipts: +List<String>, +engine: Engine) -> Engine:
  receive_current(Nat.is_eq(generation, snapshot_generation(snapshot(engine))), receipts, engine)
