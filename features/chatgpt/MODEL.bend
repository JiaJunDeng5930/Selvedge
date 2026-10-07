import Base
import ../../harness/DOMAIN.bend as D
import ../../bendlib/json.bend as J
import ../../harness/transport/schema.bend as Schema
import ../../bendlib/association-map.bend as Finite
import ../../bendlib/equality.bend as Same
import ../../harness/workspace/WORKSPACE.bend as Workspace
import ../../harness/workspace/PROJECTS.bend as Projects

# A connection is a capability over projects, not over conversations. Secrets
# and tunnel identities are transport data; only the authenticated connection
# identity and its explicit project grants enter the executable model.
type Grant is Data:
  Grant{projects: +List<Nat>, sandbox: D.Sandbox}

type Outcome is Data:
  Running{}
  Finished{value: J.Json, error: Bool}
  Interrupted{reason: String}

type Job is Data:
  Job{connection: Nat, project: Nat, request: String, arguments: J.Json,
    workspace: D.Workspace, sandbox: D.Sandbox, outcome: Outcome}

type State is Data:
  State{grants: +List<Finite.Entry(Grant)>, jobs: +List<Finite.Entry(Job)>, next: Nat}

type Effect is Data:
  Execute{operation: Nat, job: Job}
  Stop{operation: Nat}

type Command is Data:
  Configure{grants: +List<Finite.Entry(Grant)>}
  Run{connection: Nat, project: Nat, request: String, arguments: J.Json}
  Cancel{connection: Nat, project: Nat, operation: Nat}
  Forget{connection: Nat, project: Nat, operation: Nat}

type Query is Data:
  ListProjects{connection: Nat}
  ReadProject{connection: Nat, project: Nat}
  ReadJob{connection: Nat, project: Nat, operation: Nat}
  ListJobs{connection: Nat, project: Nat}

# Only resolution constructs these accepted operations. A retry returns the
# retained receipt without another effect. Forgetting explicitly ends retention.
type Change is Data:
  SetGrants{grants: +List<Finite.Entry(Grant)>}
  Start{operation: Nat, job: Job}
  Reuse{operation: Nat, job: Job}
  Interrupt{operation: Nat, job: Job}
  Remove{operation: Nat}
  Complete{operation: Nat, job: Job, value: J.Json, error: Bool}

type Resolution is Data:
  Refuse{code: String, reason: String}
  Accept{change: Change}

# Model observations.
def grants(state: State) -> +List<Finite.Entry(Grant)>:
  State{grants, jobs, next} = state
  grants

def jobs(state: State) -> +List<Finite.Entry(Job)>:
  State{grants, jobs, next} = state
  jobs

def next(state: State) -> Nat:
  State{grants, jobs, next} = state
  next

def outcome(job: Job) -> Outcome:
  Job{connection, project, request, arguments, workspace, sandbox, outcome} = job
  outcome

def owned(connection: Nat, project: Nat, job: Job) -> Bool:
  Job{owner, target, request, arguments, workspace, sandbox, outcome} = job
  Nat.is_eq(connection, owner) && Nat.is_eq(project, target)

def job_connection(job: Job) -> Nat:
  Job{connection, project, request, arguments, workspace, sandbox, outcome} = job
  connection

def job_project(job: Job) -> Nat:
  Job{connection, project, request, arguments, workspace, sandbox, outcome} = job
  project

def job_request(job: Job) -> String:
  Job{connection, project, request, arguments, workspace, sandbox, outcome} = job
  request

def job_arguments(job: Job) -> J.Json:
  Job{connection, project, request, arguments, workspace, sandbox, outcome} = job
  arguments

def job_workspace(job: Job) -> D.Workspace:
  Job{connection, project, request, arguments, workspace, sandbox, outcome} = job
  workspace

def job_sandbox(job: Job) -> D.Sandbox:
  Job{connection, project, request, arguments, workspace, sandbox, outcome} = job
  sandbox

def job_outcome(job: Job) -> Outcome:
  Job{connection, project, request, arguments, workspace, sandbox, outcome} = job
  outcome

# Model intended updates.
def with_outcome(value: Outcome, job: Job) -> Job:
  Job{connection, project, request, arguments, workspace, sandbox, previous} = job
  Job{connection, project, request, arguments, workspace, sandbox, value}

# Model birth.
def initial() -> State:
  State{Nil{}, Nil{}, 0n}

def member(+id: Nat, values: +List<Nat>) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{value, rest}: Nat.is_eq(id, value) || member(id, rest)

def selected(allowed: Bool, grant: Grant) -> Maybe<&2, Grant>:
  match allowed:
    case True{}: Some{grant}
    case False{}: None{}

def authorize(found: Maybe<&2, Grant>, project: Nat) -> Maybe<&2, Grant>:
  match found:
    case None{}: None{}
    case Some{Grant{+projects, +sandbox}}:
      selected(member(project, projects), Grant{projects, sandbox})

def authority(connection: Nat, project: Nat, state: State) -> Maybe<&2, Grant>:
  authorize(Finite.find(~Grant, grants(state), connection), project)

def pending(outcome: Outcome) -> Bool:
  match outcome:
    case Running{}: True{}
    case _: False{}

def status(outcome: Outcome) -> String:
  match outcome:
    case Running{}: "running"
    case Finished{value, error}: "completed"
    case Interrupted{reason}: "interrupted"

def result(outcome: Outcome) -> J.Json:
  match outcome:
    case Running{}: J.Null{}
    case Finished{value, error}: value
    case Interrupted{reason}: J.Object{[J.Field{"error", J.Object{[
      J.Field{"code", J.Text{"outcome_unknown"}}, J.Field{"message", J.Text{reason}}]}}]}

def failed(outcome: Outcome) -> Bool:
  match outcome:
    case Running{}: False{}
    case Finished{value, error}: error
    case Interrupted{reason}: True{}

def receipt(id: Nat, job: Job) -> J.Json:
  Job{connection, project, request, arguments, workspace, sandbox, +outcome} = job
  J.Object{[J.Field{"operation_id", J.nat(id)}, J.Field{"project_id", J.nat(project)},
    J.Field{"request_id", J.Text{request}}, J.Field{"status", J.Text{status(outcome)}},
    J.Field{"error", J.Boolean{failed(outcome)}}, J.Field{"value", result(outcome)}]}

def execution(job: Job) -> J.Json:
  Job{connection, project, request, arguments, workspace, sandbox, outcome} = job
  J.Object{[J.Field{"workspace", D.workspace_json(workspace)}, J.Field{"sandbox", D.sandbox_json(sandbox)},
    J.Field{"access", J.Text{"sandboxed"}}, J.Field{"scope", J.Text{"project"}}]}

def job_json(+id: Nat, +job: Job) -> J.Json:
  Job{connection, project, request, arguments, workspace, sandbox, outcome} = job
  J.Object{[J.Field{"receipt", receipt(id, job)}, J.Field{"connection_id", J.nat(connection)},
    J.Field{"arguments", arguments}, J.Field{"execution", execution(job)}]}

def effect_json(effect: Effect) -> J.Json:
  match effect:
    case Execute{id, +job}:
      Job{connection, project, request, arguments, workspace, sandbox, outcome} = job
      J.Object{[J.Field{"kind", J.Text{"chatgpt_exec"}}, J.Field{"operation_id", J.nat(id)},
        J.Field{"arguments", arguments}, J.Field{"execution", execution(job)}]}
    case Stop{id}: J.Object{[J.Field{"kind", J.Text{"chatgpt_cancel"}}, J.Field{"operation_id", J.nat(id)}]}

def missing(~V: Data, found: Maybe<&2, V>) -> Bool:
  match found:
    case None{}: True{}
    case Some{value}: False{}

def project_ids(ids: +List<Nat>, +projects: D.Projects) -> Bool:
  match ids:
    case Nil{}: True{}
    case Con{+id, +rest}: Bool.not(member(id, rest)) &&
      Bool.not(missing(~D.Project, Projects.find(projects, id))) && project_ids(rest, projects)

def valid_grants(entries: +List<Finite.Entry(Grant)>, +projects: D.Projects) -> Bool:
  match entries:
    case Nil{}: True{}
    case Con{(+id, Grant{+ids, sandbox}), +rest}:
      Nat.is_le(id, 4294967295n) && Nat.is_le(List.length(&2, Nat, ids), 32n) && project_ids(ids, projects) &&
      missing(~Grant, Finite.find(~Grant, rest, id)) && valid_grants(rest, projects)

def text_schema() -> J.Json:
  J.Object{[J.Field{"type", J.Text{"string"}}]}

def integer_schema(minimum: Nat, maximum: Nat) -> J.Json:
  J.Object{[J.Field{"type", J.Text{"integer"}}, J.Field{"minimum", J.nat(minimum)}, J.Field{"maximum", J.nat(maximum)}]}

def args_schema() -> J.Json:
  Schema.object([J.Field{"command", text_schema()}, J.Field{"timeout_ms", integer_schema(100n, 1800000n)},
    J.Field{"max_output_length", integer_schema(1n, 8192n)}], [J.Text{"command"}, J.Text{"timeout_ms"}, J.Text{"max_output_length"}])

def limited(+text: String, maximum: Nat) -> Bool:
  Bool.not(String.eq(text, "")) && Nat.is_le(J.utf8_length(text), maximum)

def valid_args(+arguments: J.Json) -> Bool:
  Schema.valid(args_schema(), arguments) && limited(J.text(J.get(arguments, "command")), 32768n)

def valid_jobs(entries: +List<Finite.Entry(Job)>, +next: Nat) -> Bool:
  match entries:
    case Nil{}: True{}
    case Con{(+id, Job{connection, project, request, arguments, workspace, sandbox, outcome}), +rest}:
      Nat.is_lt(id, next) && limited(request, 128n) && valid_args(arguments) && Workspace.valid(workspace) &&
      missing(~Job, Finite.find(~Job, rest, id)) && valid_jobs(rest, next)

def valid(+state: State, projects: D.Projects) -> Bool:
  Nat.is_le(List.length(&2, Finite.Entry(Grant), grants(state)), 32n) && valid_grants(grants(state), projects) &&
    Nat.is_le(List.length(&2, Finite.Entry(Job), jobs(state)), 128n) && valid_jobs(jobs(state), next(state)) &&
    Nat.is_le(next(state), 4294967295n)

def grant_uses(entries: +List<Finite.Entry(Grant)>, +project: Nat) -> Bool:
  match entries:
    case Nil{}: False{}
    case Con{(id, Grant{ids, sandbox}), rest}: member(project, ids) || grant_uses(rest, project)

def job_uses(entries: +List<Finite.Entry(Job)>, +project: Nat) -> Bool:
  match entries:
    case Nil{}: False{}
    case Con{(id, Job{connection, target, request, arguments, workspace, sandbox, outcome}), rest}:
      Nat.is_eq(project, target) || job_uses(rest, project)

def project_used(+state: State, +project: Nat) -> Bool:
  grant_uses(grants(state), project) || job_uses(jobs(state), project)

def retry_choose(hit: Bool, id: Nat, job: Job, rest: Maybe<&2, Finite.Entry(Job)>) -> Maybe<&2, Finite.Entry(Job)>:
  match hit:
    case True{}: Some{(id, job)}
    case False{}: rest

def retry(entries: +List<Finite.Entry(Job)>, +connection: Nat, +request: String) -> Maybe<&2, Finite.Entry(Job)>:
  match entries:
    case Nil{}: None{}
    case Con{(id, +job), rest}:
      Job{owner, project, key, arguments, workspace, sandbox, outcome} = job
      retry_choose(Nat.is_eq(connection, owner) && String.eq(request, key), id, job, retry(rest, connection, request))

def gate(allowed: Bool, change: Change, code: String, reason: String) -> Resolution:
  match allowed:
    case True{}: Accept{change}
    case False{}: Refuse{code, reason}

def new_job(capacity: Bool, id: Nat, job: Job) -> Resolution:
  gate(capacity, Start{id, job}, "operation_capacity", "Forget a completed operation before starting more work")

def run_existing(found: Maybe<&2, Finite.Entry(Job)>, +connection: Nat, +project: Nat, request: String,
  +arguments: J.Json, workspace: D.Workspace, sandbox: D.Sandbox, +state: State) -> Resolution:
  match found:
    case Some{(id, +job)}:
      Job{owner, target, key, previous, old_workspace, old_sandbox, outcome} = job
      gate(owned(connection, project, job) && Same.json(128n, arguments, previous), Reuse{id, job},
        "request_conflict", "This request_id already names a different command; do not retry with new arguments")
    case None{}:
      new_job(Nat.is_lt(List.length(&2, Finite.Entry(Job), jobs(state)), 128n) && Nat.is_lt(next(state), 4294967295n),
        next(state), Job{connection, project, request, arguments, workspace, sandbox, Running{}})

def run_project(found: Maybe<&2, D.Project>, grant: Grant, +connection: Nat, project: Nat,
  +request: String, arguments: J.Json, +state: State) -> Resolution:
  match found grant:
    case None{} _: Refuse{"project_not_found", "The project is unavailable"}
    case Some{D.Project{name, D.Workspace{roots, None{}}, guidance}} _:
      Refuse{"empty_workspace", "The project needs a primary Workspace root"}
    case Some{D.Project{name, D.Workspace{roots, Some{root}}, guidance}} Grant{ids, sandbox}:
      run_existing(retry(jobs(state), connection, request), connection, project, request,
        arguments, D.Workspace{roots, Some{root}}, sandbox, state)

def run_authorized(found: Maybe<&2, Grant>, +connection: Nat, +project: Nat, request: String,
  arguments: J.Json, projects: D.Projects, state: State) -> Resolution:
  match found:
    case None{}: Refuse{"project_forbidden", "This connection has no grant for that project"}
    case Some{grant}: run_project(Projects.find(projects, project), grant, connection, project, request, arguments, state)

def cancel_pending(running: Bool, id: Nat, job: Job) -> Resolution:
  match running:
    case True{}: Accept{Interrupt{id, job}}
    case False{}: Accept{Reuse{id, job}}

def change_job(remove: Bool, +id: Nat, +job: Job) -> Resolution:
  match remove:
    case True{}: gate(Bool.not(pending(outcome(job))), Remove{id}, "operation_running", "Cancel or finish the operation before forgetting it")
    case False{}: cancel_pending(pending(outcome(job)), id, job)

def owner_job(allowed: Bool, id: Nat, job: Job, remove: Bool) -> Resolution:
  match allowed:
    case False{}: Refuse{"operation_not_found", "No retained operation belongs to that project and connection"}
    case True{}: change_job(remove, id, job)

def found_job(found: Maybe<&2, Job>, connection: Nat, project: Nat, id: Nat, remove: Bool) -> Resolution:
  match found:
    case None{}: Refuse{"operation_not_found", "No retained operation belongs to that project and connection"}
    case Some{+job}: owner_job(owned(connection, project, job), id, job, remove)

def edit_authorized(found: Maybe<&2, Grant>, +connection: Nat, +project: Nat, +id: Nat, remove: Bool, state: State) -> Resolution:
  match found:
    case None{}: Refuse{"project_forbidden", "This connection has no grant for that project"}
    case Some{grant}: found_job(Finite.find(~Job, jobs(state), id), connection, project, id, remove)

def run_valid(valid: Bool, +connection: Nat, +project: Nat, request: String, arguments: J.Json,
  projects: D.Projects, +state: State) -> Resolution:
  match valid:
    case False{}: Refuse{"invalid_command", "A bounded request_id and valid Bash arguments are required"}
    case True{}: run_authorized(authority(connection, project, state), connection, project, request, arguments, projects, state)

def resolve(command: Command, +state: State, projects: D.Projects) -> Resolution:
  match command:
    case Configure{+entries}: gate(Nat.is_le(List.length(&2, Finite.Entry(Grant), entries), 32n) && valid_grants(entries, projects),
      SetGrants{entries}, "invalid_connections", "Connections need distinct identities and existing project grants")
    case Run{+connection, +project, +request, +arguments}:
      run_valid(limited(request, 128n) && valid_args(arguments), connection, project, request, arguments, projects, state)
    case Cancel{+connection, +project, id}: edit_authorized(authority(connection, project, state), connection, project, id, False{}, state)
    case Forget{+connection, +project, id}: edit_authorized(authority(connection, project, state), connection, project, id, True{}, state)

def settle_pending(running: Bool, id: Nat, job: Job, value: J.Json, error: Bool) -> Maybe<&2, Change>:
  match running:
    case False{}: None{}
    case True{}: Some{Complete{id, job, value, error}}

def settle(found: Maybe<&2, Job>, id: Nat, value: J.Json, error: Bool) -> Maybe<&2, Change>:
  match found:
    case None{}: None{}
    case Some{+job}: settle_pending(pending(outcome(job)), id, job, value, error)

def recovered(running: Bool, job: Job) -> Job:
  match running:
    case False{}: job
    case True{}: with_outcome(Interrupted{"Service restarted; execution may have happened and will not be replayed"}, job)

def recover_job(+job: Job) -> Job:
  recovered(pending(outcome(job)), job)

def recover_jobs(entries: +List<Finite.Entry(Job)>) -> +List<Finite.Entry(Job)>:
  match entries:
    case Nil{}: Nil{}
    case Con{(id, job), rest}: (id, recover_job(job)) <> recover_jobs(rest)

def recover(state: State) -> State:
  State{grants, jobs, next} = state
  State{grants, recover_jobs(jobs), next}

def same_live(found: Maybe<&2, Job>, +id: Nat, job: Job) -> Bool:
  match found:
    case None{}: False{}
    case Some{+current}: pending(outcome(current)) && Same.json(128n, job_json(id, current), job_json(id, job))

def stopped(found: Maybe<&2, Job>) -> Bool:
  match found:
    case Some{Job{connection, project, request, arguments, workspace, sandbox, Interrupted{reason}}}: True{}
    case _: False{}

def effect_valid(effect: Effect, state: State) -> Bool:
  match effect:
    case Execute{+id, job}: same_live(Finite.find(~Job, jobs(state), id), id, job)
    case Stop{id}: stopped(Finite.find(~Job, jobs(state), id))
