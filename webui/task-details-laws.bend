import Base
import ../core/ui-identity.bend as UIIdentity
import ../REASONING.bend as Reasoning
import ../core/ui-world.bend as View
import ../core/user-context.bend as Context
import ../core/field-options.bend as FieldOptions
import ../bendlib/domain.bend as Domain
import ../bendlib/tasks.bend as Tasks
import ../bendlib/json.bend as J
import ./authored.bend as Authored
import ./source.bend as Source
import ./design.bend as Design
import ./physical-space.bend as Model
import ./typography.bend as T

def instructions_text_when(empty: Bool, value: String) -> String:
  match empty:
    case True{}: "No project instructions"
    case False{}: value

def instructions_text(+value: String) -> String:
  instructions_text_when(String.eq(value, ""), value)

def project_law(+owner: UIIdentity.Key, +label: String, +directory: String, +revision: String, +instructions: String, +visual: Design.Style) -> Type:
  {Authored.project_context_facts(owner, label, Domain.ProjectContext{directory, revision, instructions}, visual) ==
    [Authored.group(owner, visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, [Authored.text(UIIdentity.part(owner, "title"), label, visual, T.Body{}, T.Strong{}), Authored.fact(UIIdentity.part(owner, "directory"), "Directory", directory, visual), Authored.fact(UIIdentity.part(owner, "revision"), "Revision", revision, visual), Authored.fact(UIIdentity.part(owner, "instructions"), "Instructions", instructions_text(instructions), visual)])] : +List<Source.Node>}

def projection_law(+owner: UIIdentity.Key, +task: Nat, +roots: +List<String>, +primary: Maybe<&2, String>, +mode: Domain.SandboxMode, +network: Bool, +approval: Domain.ApprovalPolicy, +project: Maybe<&2, Nat>, +guidance: Domain.ProjectContext, +access: Domain.ExecutionAccess, +id: String, +provider: String, +name: String, +policy: Reasoning.Policy, +options: Maybe<&2, Domain.ReasoningOptions>, +reasoning: String, +model_guidance: Domain.ProjectContext, +tools: +List<Domain.Tool>, +lineage: +List<Nat>, +queued: +List<String>, +status: Domain.Status, +phase: Domain.Phase, +visual: Design.Style) -> Type:
  {Authored.task_details(owner, View.TaskDetails{Context.EffectiveContext{task, Domain.TaskContext{Domain.Workspace{roots, primary}, Domain.Sandbox{mode, network}, approval, project}, guidance, access}, Domain.Model{Domain.Profile{id, provider, name, policy, options}, reasoning, model_guidance}, tools, lineage, queued, status, phase}, visual) ==
    [Authored.group(UIIdentity.part(owner, "@facts"), visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, Authored.append([Authored.fact(UIIdentity.part(owner, "@workspace"), "Working directories", FieldOptions.joined(roots), visual), Authored.fact(UIIdentity.part(owner, "@primary"), "Primary directory", FieldOptions.optional_text(primary), visual), Authored.fact(UIIdentity.part(owner, "@sandbox"), "Filesystem access", Context.filesystem_summary(access, mode), visual), Authored.fact(UIIdentity.part(owner, "@network"), "Network access", Context.network_summary(access, network), visual), Authored.fact(UIIdentity.part(owner, "@approval"), "Approval policy", Domain.approval_name(approval), visual), Authored.fact(UIIdentity.part(owner, "@model"), "Model", name, visual), Authored.fact(UIIdentity.part(owner, "@reasoning"), "Reasoning", reasoning, visual), Authored.fact(UIIdentity.part(owner, "@status"), "Status", Domain.status_name(status), visual), Authored.fact(UIIdentity.part(owner, "@phase"), "Phase", Tasks.phase_name(phase), visual), Authored.fact(UIIdentity.part(owner, "@messages"), "Queued messages", FieldOptions.joined(queued), visual), Authored.group(UIIdentity.part(owner, "@tools"), visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, Authored.text(UIIdentity.part(UIIdentity.part(owner, "@tools"), "title"), "Tools", visual, T.Body{}, T.Strong{}) <> Authored.tool_detail_nodes(UIIdentity.part(owner, "@tools"), tools, visual)), Authored.fact(UIIdentity.part(owner, "@lineage"), "Ancestor tasks", FieldOptions.joined(Authored.ancestor_names(lineage)), visual)], Authored.append(Authored.project_context_facts(UIIdentity.part(owner, "@task-project"), "Task project context", guidance, visual), Authored.project_context_facts(UIIdentity.part(owner, "@model-project"), "Model project context", model_guidance, visual))))] : +List<Source.Node>}

type Requirements is Type:
  Requirements{
    missing_project: @+owner:UIIdentity.Key -> @+label:String -> @+visual:Design.Style -> {Authored.project_context_facts(owner, label, Domain.NoProject{}, visual) == Nil{} : +List<Source.Node>},
    frozen_project: @+owner:UIIdentity.Key -> @+label:String -> @+directory:String -> @+revision:String -> @+instructions:String -> @+visual:Design.Style -> project_law(owner, label, directory, revision, instructions, visual),
    no_tools: @+owner:UIIdentity.Key -> @+visual:Design.Style -> {Authored.tool_detail_nodes(owner, Nil{}, visual) == Nil{} : +List<Source.Node>},
    every_tool: @+owner:UIIdentity.Key -> @+name:String -> @+description:String -> @+schema:J.Json -> @+source:Domain.Source -> @+rest:+List<Domain.Tool> -> @+visual:Design.Style ->
      {Authored.tool_detail_nodes(owner, Con{Domain.Tool{name, description, schema, source}, rest}, visual) == Authored.fact(UIIdentity.entity(owner, "tool", name), name, description, visual) <> Authored.tool_detail_nodes(owner, rest, visual) : +List<Source.Node>},
    no_ancestors: {Authored.ancestor_names(Nil{}) == Nil{} : +List<String>},
    ancestor_order: @+ancestor:Nat -> @+rest:+List<Nat> -> {Authored.ancestor_names(Con{ancestor, rest}) == Nat.show(ancestor) <> Authored.ancestor_names(rest) : +List<String>},
    complete_projection: @+owner:UIIdentity.Key -> @+task:Nat -> @+roots:+List<String> -> @+primary:Maybe<&2,String> -> @+mode:Domain.SandboxMode -> @+network:Bool -> @+approval:Domain.ApprovalPolicy -> @+project:Maybe<&2,Nat> -> @+guidance:Domain.ProjectContext -> @+access:Domain.ExecutionAccess -> @+id:String -> @+provider:String -> @+name:String -> @+policy:Reasoning.Policy -> @+options:Maybe<&2,Domain.ReasoningOptions> -> @+reasoning:String -> @+model_guidance:Domain.ProjectContext -> @+tools:+List<Domain.Tool> -> @+lineage:+List<Nat> -> @+queued:+List<String> -> @+status:Domain.Status -> @+phase:Domain.Phase -> @+visual:Design.Style -> projection_law(owner, task, roots, primary, mode, network, approval, project, guidance, access, id, provider, name, policy, options, reasoning, model_guidance, tools, lineage, queued, status, phase, visual)}

law evidence:
  Requirements
