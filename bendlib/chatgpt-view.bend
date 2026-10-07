import Base
import ../CHATGPT.bend as G
import ../PROJECTS.bend as Projects
import ./domain.bend as D
import ./json.bend as J
import ./association-map.bend as Finite

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

def read_project(found: Maybe<&2, G.Grant>, +id: Nat, registry: D.Projects) -> J.Json:
  match found:
    case None{}: forbidden()
    case Some{G.Grant{ids, sandbox}}: Projects.detail(id, Projects.find(registry, id))

def job_result(owned: Bool, id: Nat, job: G.Job) -> J.Json:
  match owned:
    case False{}: D.failure("operation_not_found", "No retained operation belongs to that project and connection")
    case True{}: D.success(G.receipt(id, job))

def job(found: Maybe<&2, G.Job>, connection: Nat, project: Nat, id: Nat) -> J.Json:
  match found:
    case None{}: D.failure("operation_not_found", "No retained operation belongs to that project and connection")
    case Some{+value}: job_result(G.owned(connection, project, value), id, value)

def read_job(found: Maybe<&2, G.Grant>, +connection: Nat, +project: Nat, +id: Nat, state: G.State) -> J.Json:
  match found:
    case None{}: forbidden()
    case Some{grant}: job(Finite.find(~G.Job, G.jobs(state), id), connection, project, id)

def summary(id: Nat, +job: G.Job) -> J.Json:
  J.Object{[J.Field{"operation_id", J.nat(id)}, J.Field{"project_id", J.nat(G.job_project(job))},
    J.Field{"request_id", J.Text{G.job_request(job)}}, J.Field{"status", J.Text{G.status(G.outcome(job))}},
    J.Field{"error", J.Boolean{G.failed(G.outcome(job))}}]}

def keep(allowed: Bool, id: Nat, job: G.Job, rest: +List<J.Json>) -> +List<J.Json>:
  match allowed:
    case False{}: rest
    case True{}: summary(id, job) <> rest

def summaries(entries: +List<Finite.Entry(G.Job)>, +connection: Nat, +project: Nat) -> +List<J.Json>:
  match entries:
    case Nil{}: Nil{}
    case Con{(id, +job), rest}: keep(G.owned(connection, project, job), id, job, summaries(rest, connection, project))

def list_jobs(found: Maybe<&2, G.Grant>, connection: Nat, project: Nat, state: G.State) -> J.Json:
  match found:
    case None{}: forbidden()
    case Some{grant}: D.success(J.Array{summaries(G.jobs(state), connection, project)})

def query(query: G.Query, +state: G.State, registry: D.Projects) -> J.Json:
  match query:
    case G.ListProjects{connection}: list(Finite.find(~G.Grant, G.grants(state), connection), registry)
    case G.ReadProject{+connection, +project}: read_project(G.authority(connection, project, state), project, registry)
    case G.ReadJob{+connection, +project, operation}: read_job(G.authority(connection, project, state), connection, project, operation, state)
    case G.ListJobs{+connection, +project}: list_jobs(G.authority(connection, project, state), connection, project, state)
