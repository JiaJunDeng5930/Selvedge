import Base
import ../../bendlib/categories.bend as Categories
import ./MODEL.bend as G
import ../../harness/workspace/PROJECTS.bend as Projects
import ../../harness/DOMAIN.bend as D
import ../../bendlib/json.bend as J
import ../../bendlib/association-map.bend as Finite

def forbidden() -> J.Json:
  D.failure("project_forbidden", "This connection has no grant for that project")

def project(+id: Nat, found: Maybe<&2, D.Project>, sandbox: D.Sandbox) -> J.Json:
  match found:
    case None{}: J.Null{}
    case Some{D.Project{name, D.Workspace{roots, primary}, guidance}}:
      J.Object{[J.Field{"project_id", J.nat(id)}, J.Field{"name", J.Text{name}},
        J.Field{"root_count", J.nat(List.length(&2, String, roots))}, J.Field{"primary_root", D.optional_string(primary)},
        J.Field{"sandbox", D.sandbox_json(sandbox)}]}

def projects(ids: +List<Nat>, +registry: D.Projects, +sandbox: D.Sandbox) -> +List<J.Json>:
  match ids:
    case Nil{}: Nil{}
    case Con{+id, rest}: project(id, Projects.find(registry, id), sandbox) <> projects(rest, registry, sandbox)

def list(found: Maybe<&2, G.Grant>, registry: D.Projects) -> J.Json:
  match found:
    case None{}: forbidden()
    case Some{G.Grant{ids, sandbox}}: D.success(J.Array{projects(ids, registry, sandbox)})

def granted_project(+id: Nat, registry: D.Projects,
  admitted: Categories.Membership<G.Grant, G.ProjectGrant(id)>) -> J.Json:
  Categories.Membership{G.Grant{ids, sandbox}, evidence} = admitted
  Projects.detail(id, Projects.find(registry, id))

def read_project(+id: Nat, found: Maybe<&1, Categories.Membership<G.Grant, G.ProjectGrant(id)>>, registry: D.Projects) -> J.Json:
  match found:
    case None{}: forbidden()
    case Some{admitted}: granted_project(id, registry, admitted)

def job_result(connection: Nat, project: Nat, id: Nat,
  admitted: Categories.Membership<G.Job, G.OwnedJob(connection, project)>) -> J.Json:
  Categories.Membership{job, evidence} = admitted
  D.success(G.receipt(id, job))

def job_admission(connection: Nat, project: Nat, id: Nat,
  found: Maybe<&1, Categories.Membership<G.Job, G.OwnedJob(connection, project)>>) -> J.Json:
  match found:
    case None{}: D.failure("operation_not_found", "No retained operation belongs to that project and connection")
    case Some{admitted}: job_result(connection, project, id, admitted)

def job(found: Maybe<&2, G.Job>, +connection: Nat, +project: Nat, id: Nat) -> J.Json:
  match found:
    case None{}: D.failure("operation_not_found", "No retained operation belongs to that project and connection")
    case Some{value}: job_admission(connection, project, id,
      Categories.admit(G.Job, job => G.owned(connection, project, job), value))

def granted_job(+connection: Nat, project: Nat, +id: Nat, state: G.State,
  admitted: Categories.Membership<G.Grant, G.ProjectGrant(project)>) -> J.Json:
  Categories.Membership{grant, evidence} = admitted
  job(Finite.find(~G.Job, G.jobs(state), id), connection, project, id)

def read_job(+connection: Nat, +project: Nat, found: Maybe<&1, Categories.Membership<G.Grant, G.ProjectGrant(project)>>,
  +id: Nat, state: G.State) -> J.Json:
  match found:
    case None{}: forbidden()
    case Some{admitted}: granted_job(connection, project, id, state, admitted)

def summary(id: Nat, +job: G.Job) -> J.Json:
  J.Object{[J.Field{"operation_id", J.nat(id)}, J.Field{"project_id", J.nat(G.job_project(job))},
    J.Field{"request_id", J.Text{G.job_request(job)}}, J.Field{"status", J.Text{G.status(G.outcome(job))}},
    J.Field{"error", J.Boolean{G.failed(G.outcome(job))}}]}

def keep(connection: Nat, project: Nat, id: Nat, rest: +List<J.Json>,
  admitted: Categories.Membership<G.Job, G.OwnedJob(connection, project)>) -> +List<J.Json>:
  Categories.Membership{job, evidence} = admitted
  summary(id, job) <> rest

def summary_admission(connection: Nat, project: Nat, id: Nat, rest: +List<J.Json>,
  found: Maybe<&1, Categories.Membership<G.Job, G.OwnedJob(connection, project)>>) -> +List<J.Json>:
  match found:
    case None{}: rest
    case Some{admitted}: keep(connection, project, id, rest, admitted)

def summaries(entries: +List<Finite.Entry(G.Job)>, +connection: Nat, +project: Nat) -> +List<J.Json>:
  match entries:
    case Nil{}: Nil{}
    case Con{(id, value), rest}: summary_admission(connection, project, id, summaries(rest, connection, project),
      Categories.admit(G.Job, job => G.owned(connection, project, job), value))

def granted_jobs(connection: Nat, project: Nat, state: G.State,
  admitted: Categories.Membership<G.Grant, G.ProjectGrant(project)>) -> J.Json:
  Categories.Membership{grant, evidence} = admitted
  D.success(J.Array{summaries(G.jobs(state), connection, project)})

def list_jobs(+connection: Nat, +project: Nat, found: Maybe<&1, Categories.Membership<G.Grant, G.ProjectGrant(project)>>, state: G.State) -> J.Json:
  match found:
    case None{}: forbidden()
    case Some{admitted}: granted_jobs(connection, project, state, admitted)

def query(query: G.Query, +state: G.State, registry: D.Projects) -> J.Json:
  match query:
    case G.ListProjects{connection}: list(Finite.find(~G.Grant, G.grants(state), connection), registry)
    case G.ReadProject{+connection, +project}: read_project(project, G.authority(connection, project, state), registry)
    case G.ReadJob{+connection, +project, operation}: read_job(connection, project, G.authority(connection, project, state), operation, state)
    case G.ListJobs{+connection, +project}: list_jobs(connection, project, G.authority(connection, project, state), state)
