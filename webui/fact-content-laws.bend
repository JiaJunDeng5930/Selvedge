import Base
import ./design.bend as D
import ./enclosure.bend as E
import ./renderer.bend as R
import ../core/field-options.bend as Options
import ./document.bend as Doc
import ../core/ui-world.bend as View
import ../core/user-context.bend as Context
import ../bendlib/domain.bend as Domain

def fact_document(+key: String, label: String, value: String) -> Doc.Node:
  Doc.Element{key, "div", Nil{},
    [R.property("display", "flex"), R.property("flex-direction", "column"), R.property("gap", R.px(E.frame_gap(D.fact_frame()))), R.property("min-width", "0")], Nil{},
    [Doc.Element{key ++ "/label", "strong", Nil{}, [R.property("min-width", "0"), R.property("overflow-wrap", "anywhere")], Nil{}, [Doc.Text{label}]},
     Doc.Element{key ++ "/value", "span", Nil{}, [R.property("min-width", "0"), R.property("overflow-wrap", "anywhere")], Nil{}, [Doc.Text{value}]}]}

def details_document(+owner: String, value: View.TaskDetails) -> +List<Doc.Node>:
  View.TaskDetails{Context.EffectiveContext{task, Domain.TaskContext{Domain.Workspace{roots, primary}, Domain.Sandbox{mode, network}, approval, project}, guidance, access}, Domain.Model{Domain.Profile{id, provider, name, policy}, reasoning, model_guidance}, tools, lineage, queued, status, phase} = value
  [Doc.Element{R.generated_identity(owner, "facts"), "div", Nil{},
    [R.property("display", "flex"), R.property("flex-direction", "column"), R.property("gap", R.px(E.frame_gap(D.facts_frame()))), R.property("min-width", "0")], Nil{},
    [fact_document(R.generated_identity(owner, "workspace"), "Working directories", Options.joined(roots)),
     fact_document(R.generated_identity(owner, "primary"), "Primary directory", Options.optional_text(primary)),
     fact_document(R.generated_identity(owner, "sandbox"), "Filesystem access", Domain.sandbox_mode_name(mode)),
     fact_document(R.generated_identity(owner, "network"), "Network access", Options.boolean(network)),
     fact_document(R.generated_identity(owner, "approval"), "Approval policy", Domain.approval_name(approval)),
     fact_document(R.generated_identity(owner, "model"), "Model", name),
     fact_document(R.generated_identity(owner, "reasoning"), "Reasoning", reasoning),
     fact_document(R.generated_identity(owner, "messages"), "Queued messages", Options.joined(queued))]}]



def details_refinement(+owner: String, +value: View.TaskDetails) ->
  {R.task_details(owner, value) == details_document(owner, value) : +List<Doc.Node>}:
  View.TaskDetails{Context.EffectiveContext{task, Domain.TaskContext{Domain.Workspace{roots, primary}, Domain.Sandbox{mode, network}, approval, project}, guidance, access}, Domain.Model{Domain.Profile{id, provider, name, policy}, reasoning, model_guidance}, tools, lineage, queued, status, phase} = value
  {==}



type Requirements is Type:
  Requirements{
    frames: {D.fact_content_layout() == D.FactContentLayout{E.Frame{E.ambient(0n, 0n), E.EmbeddedContent{4n}}, E.Frame{E.ambient(0n, 0n), E.SeparateFrames{E.Sections{}}}} : D.FactContentLayout},
    fact: @+key:String -> @+label:String -> @+value:String -> {R.fact(key, label, value) == fact_document(key, label, value) : Doc.Node},
    details: @+owner:String -> @+value:View.TaskDetails -> {R.task_details(owner, value) == details_document(owner, value) : +List<Doc.Node>}}

def evidence() -> Requirements:
  Requirements{{==}, +key => +label => +value => {==}, details_refinement}
