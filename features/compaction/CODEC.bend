import Base
import ../../harness/context/PROGRAM.bend as Context
import ./MODEL.bend as A
import ../../harness/DOMAIN.bend as D
import ../../harness/tasks/PROGRAM.bend as T
import ../../harness/compaction/PROGRAM.bend as Rebuild
import ../../harness/compaction/MODEL.bend as Bounded
import ../../bendlib/json.bend as J
import ../../harness/transport/wire-shape.bend as Shape
import ../../harness/transport/model-json.bend as ModelJSON

def compact_metadata_json(+id: Nat, +ticket: Nat, +model: D.Model, +scope: String, +target: A.Target) -> J.Json:
  A.Target{profile, window, reserve, ttl, method} = target
  J.Object{[J.Field{"kind", J.Text{"context_compaction"}}, J.Field{"task_id", J.nat(id)},
    J.Field{"ticket", J.nat(ticket)}, J.Field{"model", ModelJSON.encode(model)},
    J.Field{"context_selected", J.Boolean{True{}}}, J.Field{"context_scope", J.Text{scope}},
    J.Field{"method", J.Text{method}}, J.Field{"window_tokens", J.nat(window)},
    J.Field{"output_reserve_tokens", J.nat(reserve)}]}

def rendered_bytes(result: Result<&2, &2, String, String>, limit: Nat) -> Nat:
  match result:
    case Fail{message}: 1n+limit
    case Done{text}: J.utf8_length(text)

def compact_metadata_bytes(+id: Nat, +ticket: Nat, +model: D.Model, +scope: String, +target: A.Target, limit: Nat) -> Nat:
  # Adding the nonempty object's final `,"plan":` field costs eight bytes.
  Nat.add(8n, rendered_bytes(J.show(compact_metadata_json(id, ticket, model, scope, target)), limit))

def compact_with_metadata(metadata: J.Json, plan: J.Json) -> J.Json:
  match metadata:
    case J.Object{fields}: J.Object{List.append(&2, J.Field, fields, [J.Field{"plan", plan}])}
    case _: J.Object{Nil{}}

# Snapshot identity is retained in Bend; wire histories are the complete input
# observations used by the external encoder and meter.

def compact_json(+id: Nat, +ticket: Nat, +model: D.Model, +scope: String, +target: A.Target, progress: Bounded.State) -> J.Json:
  compact_with_metadata(compact_metadata_json(id, ticket, model, scope, target), Rebuild.plan_json(progress))

def effect_json(model_json: D.Model -> J.Json, +effect: A.Effect) -> J.Json:
  match effect:
    case A.Scope{+id, +ticket, +model}:
      J.Object{[J.Field{"kind", J.Text{"context_scope"}}, J.Field{"task_id", J.nat(id)}, J.Field{"ticket", J.nat(ticket)}, J.Field{"model", model_json(model)}]}
    case A.Measure{+id, +ticket, +model, +history, +tools, +context, +callable, +scope, +validating}:
      J.Object{[J.Field{"kind", J.Text{"context_measure"}}, J.Field{"task_id", J.nat(id)}, J.Field{"ticket", J.nat(ticket)}, J.Field{"model", model_json(model)},
        J.Field{"history", J.Array{Context.target_messages(Context.history_json(history), scope)}}, J.Field{"context_selected", J.Boolean{True{}}}, J.Field{"context_scope", J.Text{scope}},
        J.Field{"tools", J.Array{D.tools_json(tools)}}, J.Field{"settings", D.task_context_json(context)}, J.Field{"callable", J.Array{J.text_items(callable)}}, J.Field{"validating", J.Boolean{validating}}]}
    case A.Compact{+id, +ticket, +model, +history, +tools, +context, +target, +progress, +scope}:
      compact_json(id, ticket, model, scope, target, progress)
    case A.ArmClock{+deadline}: J.Object{[J.Field{"kind", J.Text{"compaction_clock"}}, J.Field{"deadline", J.nat(deadline)}]}
    case A.Cancel{+id, +ticket}: J.Object{[J.Field{"kind", J.Text{"compaction_cancel"}}, J.Field{"task_id", J.nat(id)}, J.Field{"ticket", J.nat(ticket)}]}

def target_json(+target: A.Target) -> J.Json:
  A.Target{+profile, +window, +reserve, +ttl, +method} = target
  J.Object{[J.Field{"profile", J.Text{profile}}, J.Field{"window_tokens", J.nat(window)}, J.Field{"output_reserve_tokens", J.nat(reserve)},
    J.Field{"cache_ttl_ms", J.nat(ttl)}, J.Field{"method", J.Text{method}}]}

def targets_json(+values: +List<A.Target>) -> +List<J.Json>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, +rest}: target_json(value) <> targets_json(rest)

def policy_json(+policy: A.Policy) -> J.Json:
  A.Policy{+enabled, +background, +blocking, +lead, +targets} = policy
  J.Object{[J.Field{"enabled", J.Boolean{enabled}}, J.Field{"background_percent", J.nat(background)}, J.Field{"blocking_percent", J.nat(blocking)},
    J.Field{"idle_lead_ms", J.nat(lead)}, J.Field{"targets", J.Array{targets_json(targets)}}]}

def envelope(+body: J.Json) -> Bool:
  Shape.is_natural(J.get(body, "task_id")) && Shape.is_natural(J.get(body, "ticket")) && Shape.is_bool(J.get(body, "error")) && J.is_object(J.get(body, "result"))

def has_field(fields: +List<J.Field>, +name: String) -> Bool:
  match fields:
    case Nil{}: False{}
    case Con{J.Field{key, value}, rest}: String.eq(key, name) || has_field(rest, name)

def counted_budget(valid: Bool, scope: String, tokens: Nat, window: Nat, +reserve: Nat) -> Result<&2, &2, String, A.Inspection>:
  match valid:
    case False{}: Fail{"Malformed compaction measurement budget"}
    case True{}:
      Done{A.InputMeasured{A.InputCount{scope, tokens, A.TokenBudget{
        Nat.sub(reserve, Bounded.minimum_reserve()),
        Nat.sub(window, Nat.max(Bounded.minimum_window(), Nat.mul(4n, reserve)))}}}}

def counted(scope: String, tokens: Maybe<&2, Nat>, window: Maybe<&2, Nat>, reserve: Maybe<&2, Nat>) -> Result<&2, &2, String, A.Inspection>:
  match tokens window reserve:
    case Some{tokens} Some{+window} Some{+reserve}: counted_budget(Bounded.legal_budget(window, reserve), scope, tokens, window, reserve)
    case _ _ _: Fail{"A compaction measurement requires input_tokens, window_tokens and output_reserve_tokens"}

def inspected_scope(has_count: Bool, scope: String, +value: J.Json) -> Result<&2, &2, String, A.Inspection>:
  match has_count:
    case False{}: Done{A.ScopeObserved{scope}}
    case True{}: counted(scope, J.natural(J.get(value, "input_tokens")), J.natural(J.get(value, "window_tokens")), J.natural(J.get(value, "output_reserve_tokens")))

def inspection_failure(message: J.Json) -> Result<&2, &2, String, A.Inspection>:
  match message:
    case J.Text{message}: Done{A.InspectionFailed{message}}
    case _: Fail{"A failed compaction observation requires a message"}

def inspection_scope(scope: J.Json, +fields: +List<J.Field>) -> Result<&2, &2, String, A.Inspection>:
  match scope:
    case J.Text{scope}: inspected_scope(has_field(fields, "input_tokens") || has_field(fields, "window_tokens") || has_field(fields, "output_reserve_tokens"), scope, J.Object{fields})
    case _: Fail{"A compaction observation requires its actual scope"}

def inspection(error: Bool, +value: J.Json) -> Result<&2, &2, String, A.Inspection>:
  match error value:
    case True{} J.Object{fields}: inspection_failure(J.get(J.Object{fields}, "message"))
    case False{} J.Object{+fields}: inspection_scope(J.get(J.Object{fields}, "scope"), fields)
    case _ _: Fail{"Malformed compaction observation"}

def measured_completion(id: Nat, ticket: Nat, parsed: Result<&2, &2, String, A.Inspection>) -> Result<&2, &2, String, A.Completion>:
  match parsed:
    case Fail{message}: Fail{message}
    case Done{outcome}: Done{A.MeasuredInput{id, ticket, outcome}}

def measured_envelope(valid: Bool, +body: J.Json) -> Result<&2, &2, String, A.Completion>:
  match valid:
    case False{}: Fail{"Malformed compaction observation"}
    case True{}: measured_completion(A.number(J.get(body, "task_id")), A.number(J.get(body, "ticket")), inspection(J.boolean(J.get(body, "error")), J.get(body, "result")))

def checked(+valid: Bool, +completion: A.Completion) -> Result<&2, &2, String, A.Completion>:
  match valid:
    case False{}: Fail{"Malformed compaction observation"}
    case True{}: Done{completion}

def completion(+kind: String, +body: J.Json) -> Result<&2, &2, String, A.Completion>:
  match kind:
    case "compaction_configure": checked(J.is_object(J.get(body, "policy")) && A.valid_policy(A.policy_json(J.get(body, "policy"))) && Shape.is_natural(J.get(body, "now")),
      A.Configure{A.policy_json(J.get(body, "policy")), A.number(J.get(body, "now"))})
    case "compaction_clock": checked(Shape.is_natural(J.get(body, "now")), A.Clock{A.number(J.get(body, "now"))})
    case "compaction_activity": checked(Shape.is_natural(J.get(body, "task_id")) && Shape.is_natural(J.get(body, "source_length")) &&
      Shape.is_natural(J.get(body, "now")) && J.is_text(J.get(body, "scope")),
      A.Activity{A.number(J.get(body, "task_id")), A.number(J.get(body, "source_length")), A.number(J.get(body, "now")), J.text(J.get(body, "scope"))})
    case "compaction_measured": measured_envelope(envelope(body), body)
    case "compaction_completed": checked(envelope(body), A.Completed{A.number(J.get(body, "task_id")), A.number(J.get(body, "ticket")), J.get(body, "result"), J.boolean(J.get(body, "error"))})
    case _: Fail{"Unknown compaction input"}

def job_name(job: A.Job) -> String:
  match job:
    case A.NoJob{}: "idle"
    case A.Resuming{snapshot, model, reason}: "waiting"
    case A.Preparing{ticket, snapshot, model, reason, scope}: "preparing"
    case A.Compacting{ticket, snapshot, model, reason, progress, scope}: "compacting"
    case A.Validating{ticket, snapshot, model, reason, candidate, preview, scope}: "validating"

def entry_json(id: Nat, entry: A.Entry) -> J.Json:
  A.Entry{measurement, job, useful, maintained, attempted, activity, deadline, cache, scope} = entry
  J.Object{[J.Field{"task_id", J.nat(id)}, J.Field{"state", J.Text{job_name(job)}}, J.Field{"useful_revision", J.nat(useful)},
    J.Field{"maintained_revision", J.nat(maintained)}, J.Field{"cache_deadline", J.nat(deadline)}]}

def entry_items(entries: +List<Sigma<&2, &2, Nat, (_ => A.Entry)>>) -> +List<J.Json>:
  match entries:
    case Nil{}: Nil{}
    case Con{(id, entry), rest}: entry_json(id, entry) <> entry_items(rest)

def state_json(state: A.State) -> J.Json:
  A.State{policy, entries, now, timer} = state
  J.Object{[J.Field{"policy", policy_json(policy)}, J.Field{"tasks", J.Array{entry_items(entries)}}]}
