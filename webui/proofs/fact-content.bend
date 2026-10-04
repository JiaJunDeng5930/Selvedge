import Base
import ../fact-content-laws.bend as Rule
import ../renderer.bend as R
import ../document.bend as Doc
import ../../core/ui-world.bend as View
import ../../core/user-context.bend as Context
import ../../bendlib/domain.bend as Domain

def details_refinement(+owner: String, +value: View.TaskDetails) ->
  {R.task_details(owner, value) == Rule.details_document(owner, value) : +List<Doc.Node>}:
  View.TaskDetails{Context.EffectiveContext{task, Domain.TaskContext{Domain.Workspace{roots, primary}, Domain.Sandbox{mode, network}, approval, project}, guidance, access}, Domain.Model{Domain.Profile{id, provider, name, policy}, reasoning, model_guidance}, tools, lineage, queued, status, phase} = value
  {==}

def Rule.evidence():
  Rule.Requirements{{==}, +key => +label => +value => {==}, details_refinement}
