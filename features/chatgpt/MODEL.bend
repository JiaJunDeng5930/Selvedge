import Base
import ../../bendlib/categories.bend as Categories
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

def project_grant_allowed(project: Nat, grant: Grant) -> Bool:
  Grant{projects, sandbox} = grant
  member(project, projects)

def ProjectGrant(project: Nat) -> Grant -> Type:
  Categories.holds(Grant, grant => project_grant_allowed(project, grant))

def authorize(found: Maybe<&2, Grant>, +project: Nat) -> Maybe<&1, Categories.Membership<Grant, ProjectGrant(project)>>:
  match found:
    case None{}: None{}
    case Some{grant}: Categories.admit(Grant, grant => project_grant_allowed(project, grant), grant)

def authority(connection: Nat, +project: Nat, state: State) -> Maybe<&1, Categories.Membership<Grant, ProjectGrant(project)>>:
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

def retry_matches(connection: Nat, request: String, entry: Finite.Entry(Job)) -> Bool:
  (id, Job{owner, project, key, arguments, workspace, sandbox, outcome}) = entry
  Nat.is_eq(connection, owner) && String.eq(request, key)

def MatchingRetry(connection: Nat, request: String) -> Finite.Entry(Job) -> Type:
  Categories.holds(Finite.Entry(Job), entry => retry_matches(connection, request, entry))

def retained_retry(connection: Nat, request: String,
  admitted: Categories.Membership<Finite.Entry(Job), MatchingRetry(connection, request)>) -> Maybe<&2, Finite.Entry(Job)>:
  Categories.Membership{entry, evidence} = admitted
  Some{entry}

def retry_admission(+connection: Nat, +request: String, rest: Maybe<&2, Finite.Entry(Job)>,
  found: Maybe<&1, Categories.Membership<Finite.Entry(Job), MatchingRetry(connection, request)>>) -> Maybe<&2, Finite.Entry(Job)>:
  match found:
    case Some{admitted}: retained_retry(connection, request, admitted)
    case None{}: rest

def retry(entries: +List<Finite.Entry(Job)>, +connection: Nat, +request: String) -> Maybe<&2, Finite.Entry(Job)>:
  match entries:
    case Nil{}: None{}
    case Con{entry, rest}:
      retry_admission(connection, request, retry(rest, connection, request),
        Categories.admit(Finite.Entry(Job), entry => retry_matches(connection, request, entry), entry))

type JobCapacity is Data:
  JobCapacity{job: Job, state: State}

def capacity_available(candidate: JobCapacity) -> Bool:
  JobCapacity{job, +state} = candidate
  Nat.is_lt(List.length(&2, Finite.Entry(Job), jobs(state)), 128n) && Nat.is_lt(next(state), 4294967295n)

def AvailableCapacity() -> JobCapacity -> Type:
  Categories.holds(JobCapacity, capacity_available)

def start_admitted(admitted: Categories.Membership<JobCapacity, AvailableCapacity()>) -> Resolution:
  Categories.Membership{JobCapacity{job, state}, evidence} = admitted
  Accept{Start{next(state), job}}

def capacity_admission(found: Maybe<&1, Categories.Membership<JobCapacity, AvailableCapacity()>>) -> Resolution:
  match found:
    case Some{admitted}: start_admitted(admitted)
    case None{}: Refuse{"operation_capacity", "Forget a completed operation before starting more work"}

def new_job(job: Job, state: State) -> Resolution:
  capacity_admission(Categories.admit(JobCapacity, capacity_available, JobCapacity{job, state}))

def retry_compatible(connection: Nat, project: Nat, arguments: J.Json, +job: Job) -> Bool:
  owned(connection, project, job) && Same.json(128n, arguments, job_arguments(job))

def CompatibleRetry(connection: Nat, project: Nat, arguments: J.Json) -> Job -> Type:
  Categories.holds(Job, job => retry_compatible(connection, project, arguments, job))

def reuse_admitted(connection: Nat, project: Nat, arguments: J.Json, id: Nat,
  admitted: Categories.Membership<Job, CompatibleRetry(connection, project, arguments)>) -> Resolution:
  Categories.Membership{job, evidence} = admitted
  Accept{Reuse{id, job}}

def compatible_admission(connection: Nat, project: Nat, arguments: J.Json, id: Nat,
  found: Maybe<&1, Categories.Membership<Job, CompatibleRetry(connection, project, arguments)>>) -> Resolution:
  match found:
    case Some{admitted}: reuse_admitted(connection, project, arguments, id, admitted)
    case None{}: Refuse{"request_conflict", "This request_id already names a different command; do not retry with new arguments"}

def run_existing(found: Maybe<&2, Finite.Entry(Job)>, +connection: Nat, +project: Nat, request: String,
  +arguments: J.Json, workspace: D.Workspace, sandbox: D.Sandbox, state: State) -> Resolution:
  match found:
    case Some{(id, job)}:
      compatible_admission(connection, project, arguments, id,
        Categories.admit(Job, job => retry_compatible(connection, project, arguments, job), job))
    case None{}: new_job(Job{connection, project, request, arguments, workspace, sandbox, Running{}}, state)

def run_project(found: Maybe<&2, D.Project>, grant: Grant, +connection: Nat, project: Nat,
  +request: String, arguments: J.Json, +state: State) -> Resolution:
  match found grant:
    case None{} _: Refuse{"project_not_found", "The project is unavailable"}
    case Some{D.Project{name, D.Workspace{roots, None{}}, guidance}} _:
      Refuse{"empty_workspace", "The project needs a primary Workspace root"}
    case Some{D.Project{name, D.Workspace{roots, Some{root}}, guidance}} Grant{ids, sandbox}:
      run_existing(retry(jobs(state), connection, request), connection, project, request,
        arguments, D.Workspace{roots, Some{root}}, sandbox, state)

def run_project_grant_calculation(+connection: Nat, +project: Nat, request: String, arguments: J.Json,
  projects: D.Projects, state: State, admitted: Categories.Membership<Grant, ProjectGrant(project)>) -> Resolution:
  Categories.Membership{grant, evidence} = admitted
  run_project(Projects.find(projects, project), grant, connection, project, request, arguments, state)

def run_authorized(+connection: Nat, +project: Nat, found: Maybe<&1, Categories.Membership<Grant, ProjectGrant(project)>>, request: String,
  arguments: J.Json, projects: D.Projects, state: State) -> Resolution:
  match found:
    case None{}: Refuse{"project_forbidden", "This connection has no grant for that project"}
    case Some{admitted}: run_project_grant_calculation(connection, project, request, arguments, projects, state, admitted)

def cancel_pending(running: Bool, id: Nat, job: Job) -> Resolution:
  match running:
    case True{}: Accept{Interrupt{id, job}}
    case False{}: Accept{Reuse{id, job}}

type JobRemoval is Data:
  JobRemoval{operation: Nat, job: Job}

def finished_job(candidate: JobRemoval) -> Bool:
  JobRemoval{operation, job} = candidate
  Bool.not(pending(outcome(job)))

def ForgettableJob() -> JobRemoval -> Type:
  Categories.holds(JobRemoval, finished_job)

def forget_admitted(admitted: Categories.Membership<JobRemoval, ForgettableJob()>) -> Resolution:
  Categories.Membership{JobRemoval{id, job}, evidence} = admitted
  Accept{Remove{id}}

def forget_admission(found: Maybe<&1, Categories.Membership<JobRemoval, ForgettableJob()>>) -> Resolution:
  match found:
    case Some{admitted}: forget_admitted(admitted)
    case None{}: Refuse{"operation_running", "Cancel or finish the operation before forgetting it"}

def change_job(remove: Bool, id: Nat, +job: Job) -> Resolution:
  match remove:
    case True{}:
      forget_admission(Categories.admit(JobRemoval, finished_job, JobRemoval{id, job}))
    case False{}: cancel_pending(pending(outcome(job)), id, job)

def OwnedJob(connection: Nat, project: Nat) -> Job -> Type:
  Categories.holds(Job, job => owned(connection, project, job))

def owner_job(connection: Nat, project: Nat, id: Nat, remove: Bool,
  admitted: Categories.Membership<Job, OwnedJob(connection, project)>) -> Resolution:
  Categories.Membership{job, evidence} = admitted
  change_job(remove, id, job)

def owner_admission(connection: Nat, project: Nat, id: Nat, remove: Bool,
  found: Maybe<&1, Categories.Membership<Job, OwnedJob(connection, project)>>) -> Resolution:
  match found:
    case Some{admitted}: owner_job(connection, project, id, remove, admitted)
    case None{}: Refuse{"operation_not_found", "No retained operation belongs to that project and connection"}

def found_job(found: Maybe<&2, Job>, +connection: Nat, +project: Nat, id: Nat, remove: Bool) -> Resolution:
  match found:
    case None{}: Refuse{"operation_not_found", "No retained operation belongs to that project and connection"}
    case Some{job}:
      owner_admission(connection, project, id, remove, Categories.admit(Job, job => owned(connection, project, job), job))

def edit_project_grant_calculation(+connection: Nat, project: Nat, +id: Nat, remove: Bool, state: State,
  admitted: Categories.Membership<Grant, ProjectGrant(project)>) -> Resolution:
  Categories.Membership{grant, evidence} = admitted
  found_job(Finite.find(~Job, jobs(state), id), connection, project, id, remove)

def edit_authorized(+connection: Nat, +project: Nat, found: Maybe<&1, Categories.Membership<Grant, ProjectGrant(project)>>, +id: Nat, remove: Bool, state: State) -> Resolution:
  match found:
    case None{}: Refuse{"project_forbidden", "This connection has no grant for that project"}
    case Some{admitted}: edit_project_grant_calculation(connection, project, id, remove, state, admitted)

def run_command_valid(command: Command) -> Bool:
  match command:
    case Run{connection, project, request, arguments}: limited(request, 128n) && valid_args(arguments)
    case _: False{}

def ValidRun() -> Command -> Type:
  Categories.holds(Command, run_command_valid)

def run_valid(admitted: Categories.Membership<Command, ValidRun()>, projects: D.Projects, +state: State) -> Resolution:
  Categories.Membership{command, evidence} = admitted
  match command:
    case Run{+connection, +project, request, arguments}:
      run_authorized(connection, project, authority(connection, project, state), request, arguments, projects, state)
    case _: Refuse{"invalid_command", "A bounded request_id and valid Bash arguments are required"}

def configuration_valid(projects: D.Projects, command: Command) -> Bool:
  match command:
    case Configure{+entries}: Nat.is_le(List.length(&2, Finite.Entry(Grant), entries), 32n) && valid_grants(entries, projects)
    case _: False{}

def ValidConfiguration(projects: D.Projects) -> Command -> Type:
  Categories.holds(Command, command => configuration_valid(projects, command))

def configure_admitted(projects: D.Projects, admitted: Categories.Membership<Command, ValidConfiguration(projects)>) -> Resolution:
  Categories.Membership{command, evidence} = admitted
  match command:
    case Configure{entries}: Accept{SetGrants{entries}}
    case _: Refuse{"invalid_connections", "Connections need distinct identities and existing project grants"}

def configure_admission(+projects: D.Projects,
  found: Maybe<&1, Categories.Membership<Command, ValidConfiguration(projects)>>) -> Resolution:
  match found:
    case Some{admitted}: configure_admitted(projects, admitted)
    case None{}: Refuse{"invalid_connections", "Connections need distinct identities and existing project grants"}

def run_admission(projects: D.Projects, state: State,
  found: Maybe<&1, Categories.Membership<Command, ValidRun()>>) -> Resolution:
  match found:
    case Some{admitted}: run_valid(admitted, projects, state)
    case None{}: Refuse{"invalid_command", "A bounded request_id and valid Bash arguments are required"}

def resolve(command: Command, +state: State, +projects: D.Projects) -> Resolution:
  match command:
    case Configure{entries}:
      configure_admission(projects, Categories.admit(Command, command => configuration_valid(projects, command), Configure{entries}))
    case Run{connection, project, request, arguments}:
      run_admission(projects, state, Categories.admit(Command, run_command_valid, Run{connection, project, request, arguments}))
    case Cancel{+connection, +project, id}: edit_authorized(connection, project, authority(connection, project, state), id, False{}, state)
    case Forget{+connection, +project, id}: edit_authorized(connection, project, authority(connection, project, state), id, True{}, state)

def RunningJob() -> Job -> Type:
  Categories.holds(Job, job => pending(outcome(job)))

def settle_pending(id: Nat, admitted: Categories.Membership<Job, RunningJob()>, value: J.Json, error: Bool) -> Maybe<&2, Change>:
  Categories.Membership{job, evidence} = admitted
  Some{Complete{id, job, value, error}}

def settlement_admission(id: Nat, value: J.Json, error: Bool,
  found: Maybe<&1, Categories.Membership<Job, RunningJob()>>) -> Maybe<&2, Change>:
  match found:
    case Some{admitted}: settle_pending(id, admitted, value, error)
    case None{}: None{}

def settle(found: Maybe<&2, Job>, id: Nat, value: J.Json, error: Bool) -> Maybe<&2, Change>:
  match found:
    case None{}: None{}
    case Some{job}:
      settlement_admission(id, value, error, Categories.admit(Job, job => pending(outcome(job)), job))

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

type CommandRequest is Data:
  CommandRequest{command: Command, state: State, projects: D.Projects}

def request_resolution(request: CommandRequest) -> Resolution:
  CommandRequest{command, state, projects} = request
  resolve(command, state, projects)

def ConstructedCommand() -> Type:
  Categories.Membership<Categories.Construction<CommandRequest, Resolution>,
    Categories.constructed_by(CommandRequest, Resolution, request_resolution)>

def construct_command(command: Command, state: State, projects: D.Projects) -> ConstructedCommand():
  Categories.construct(CommandRequest, Resolution, request_resolution, CommandRequest{command, state, projects})

type CompletionRequest is Data:
  CompletionRequest{id: Nat, value: J.Json, error: Bool, state: State}

def completion_resolution(request: CompletionRequest) -> Maybe<&2, Change>:
  CompletionRequest{+id, value, error, +state} = request
  settle(Finite.find(~Job, jobs(state), id), id, value, error)

def ConstructedCompletion() -> Type:
  Categories.Membership<Categories.Construction<CompletionRequest, Maybe<&2, Change>>,
    Categories.constructed_by(CompletionRequest, Maybe<&2, Change>, completion_resolution)>

def construct_completion(id: Nat, value: J.Json, error: Bool, state: State) -> ConstructedCompletion():
  Categories.construct(CompletionRequest, Maybe<&2, Change>, completion_resolution, CompletionRequest{id, value, error, state})
