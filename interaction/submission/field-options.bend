import Base
import ../../harness/DOMAIN.bend as Domain
import ../../features/board/MODEL.bend as Board
import ../../harness/reasoning/MODEL.bend as Reasoning
import ../presentation/MODEL.bend as View
import ../INPUT.bend as User
import ../services/CONTEXT.bend as Context
import ./FIELDS.bend as Forms

# Selectable values are projected only from the owning editor's observations.
def option(value: String, label: String) -> Forms.ChoiceValue:
  Forms.ChoiceValue{value, label}

def boolean(value: Bool) -> String:
  match value:
    case True{}: "true"
    case False{}: "false"

def joined(values: +List<String>) -> String:
  match values:
    case Nil{}: ""
    case Con{value, Nil{}}: value
    case Con{value, rest}: value ++ "\n" ++ joined(rest)

def optional_text(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: ""
    case Some{text}: text

def optional_nat(value: Maybe<&2, Nat>) -> String:
  match value:
    case None{}: ""
    case Some{number}: Nat.show(number)

def delivery_name(value: User.Delivery) -> String:
  match value:
    case User.Send{}: "send"
    case User.Steer{}: "steer"

def prefer_options(first: +List<Forms.ChoiceValue>, second: +List<Forms.ChoiceValue>) -> +List<Forms.ChoiceValue>:
  match first:
    case Nil{}: second
    case Con{value, rest}: value <> rest

def workspace_roots(value: Context.WorkspaceValue) -> +List<String>:
  match value:
    case Context.InheritedWorkspace{Domain.Workspace{roots, primary}}: roots
    case Context.EnteredWorkspace{Domain.Workspace{roots, primary}}: roots

def primary_choices(value: Forms.Observed) -> +List<String>:
  match value:
    case Forms.WorkspaceValue{Domain.Workspace{roots, primary}}: roots
    case Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}: workspace_roots(workspace)
    case _: Nil{}

def sandbox_text(value: Context.SandboxValue) -> String:
  match value:
    case Context.InheritedSandbox{Domain.Sandbox{mode, network}}: Domain.sandbox_mode_name(mode)
    case Context.ChosenSandbox{Domain.Sandbox{mode, network}}: Domain.sandbox_mode_name(mode)

def workspace_text(value: Context.WorkspaceValue) -> String:
  match value:
    case Context.InheritedWorkspace{Domain.Workspace{roots, primary}}: joined(roots)
    case Context.EnteredWorkspace{Domain.Workspace{roots, primary}}: joined(roots)

def context_text(value: Context.Preview) -> String:
  match value:
    case Context.ContextUnavailable{reason}: reason
    case Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}: workspace_text(workspace) ++ "\n" ++ sandbox_text(sandbox)

def observed(value: Forms.Observed) -> String:
  match value:
    case Forms.TextValue{text}: text
    case Forms.CountValue{count}: Nat.show(count)
    case Forms.TextsValue{values}: joined(values)
    case Forms.ToggleValue{enabled}: boolean(enabled)
    case Forms.WorkspaceValue{Domain.Workspace{roots, primary}}: joined(roots)
    case Forms.ContextValue{preview}: context_text(preview)
    case Forms.ModelValue{profile, reasoning}: profile
    case Forms.DeliveryValue{delivery}: delivery_name(delivery)
    case Forms.StageValue{stage}: Board.stage_name(stage)
    case Forms.PriorityValue{priority}: Board.priority_name(priority)
    case Forms.OwnerValue{owner}: Board.owner_name(owner)
    case Forms.ProjectValue{project}: optional_nat(project)
    case Forms.AttachmentsValue{files}: ""
    case Forms.AssistanceValue{enabled, profile}: profile
    case Forms.OptionalTextValue{text}: optional_text(text)
    case Forms.NotApplicable{}: ""

def options(values: +List<String>) -> +List<Forms.ChoiceValue>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}: option(value, value) <> options(rest)

def profile_options(values: +List<Domain.Profile>) -> +List<Forms.ChoiceValue>:
  match values:
    case Nil{}: Nil{}
    case Con{Domain.Profile{id, provider, name, policy, options}, rest}: option(id, name) <> profile_options(rest)

def origin_option_values(origin: Context.Origin) -> +List<Forms.ChoiceValue>:
  match origin:
    case Context.EnvironmentDefaults{}: [option("environment", "Environment defaults")]
    case Context.ProjectDefaults{project}: [option("environment", "Environment defaults"), option("project/" ++ Nat.show(project), "Project defaults")]
    case Context.ParentTask{task}: [option("environment", "Environment defaults"), option("parent/" ++ Nat.show(task), "Parent task")]
    case Context.ProjectForParent{+task, project}: [option("environment", "Environment defaults"), option("parent/" ++ Nat.show(task), "Parent task"), option("project-for-parent/" ++ Nat.show(task) ++ "/" ++ Nat.show(project), "Project defaults")]

def project_origin_options(values: +List<View.ProjectChoice>) -> +List<Forms.ChoiceValue>:
  match values:
    case Nil{}: Nil{}
    case Con{View.ProjectChoice{id, name, workspace}, rest}: option("project/" ++ Nat.show(id), name) <> project_origin_options(rest)

def reviewer_options(values: +List<Domain.Profile>) -> +List<Forms.ChoiceValue>:
  match values:
    case Nil{}: Nil{}
    case Con{Domain.Profile{id, provider, name, policy, options}, rest}: option("automatic/" ++ id, "Automatic review: " ++ name) <> reviewer_options(rest)

def project_options(values: +List<View.ProjectChoice>) -> +List<Forms.ChoiceValue>:
  match values:
    case Nil{}: Nil{}
    case Con{View.ProjectChoice{id, name, workspace}, rest}: option(Nat.show(id), name) <> project_options(rest)

def origin_options(value: Forms.Observed) -> +List<Forms.ChoiceValue>:
  match value:
    case Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}: origin_option_values(origin)
    case _: [option("environment", "Environment defaults")]

def policy_options(policy: Reasoning.Policy) -> +List<Forms.ChoiceValue>:
  match policy:
    case Reasoning.Fixed{}: Nil{}
    case Reasoning.Adaptive{evaluator, efforts, baseline, transport, maximum}: [option("auto", "Automatic")]

def assistance_options(field: String, profiles: +List<Domain.Profile>) -> +List<Forms.ChoiceValue>:
  match field:
    case "assistance-profile": option("", "使用看板默认模型") <> profile_options(profiles)
    case _: Nil{}

def priority_options(values: +List<Board.Priority>) -> +List<Forms.ChoiceValue>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}: option(Board.priority_name(value), Board.priority_label(value)) <> priority_options(rest)

def card_options(field: String, projects: +List<View.ProjectChoice>, priorities: +List<Board.Priority>, owners: +List<Forms.ChoiceValue>) -> +List<Forms.ChoiceValue>:
  match field:
    case "card-project": option("", "No project") <> project_options(projects)
    case "card-owner": owners
    case "card-priority": priority_options(priorities)
    case _: Nil{}

def stage_options(values: +List<Board.Stage>) -> +List<Forms.ChoiceValue>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}: option(Board.stage_name(value), Board.stage_label(value)) <> stage_options(rest)

def field_options(field: Forms.Field, value: Forms.Observed) -> +List<Forms.ChoiceValue>:
  match field:
    case Forms.SandboxMode{}: [option("workspace-write", "Workspace write"), option("read-only", "Read only")]
    case Forms.ContextOrigin{}: origin_options(value)
    case Forms.ApprovalPolicy{}: [option("ask", "Ask for approval"), option("full-access", "Full access"), option("automatic", "Automatic review")]
    case Forms.WorkspacePrimary{}: options(primary_choices(value))
    case Forms.CardStage{}: stage_options(Board.stages())
    case Forms.CardPriority{}: priority_options(Board.priorities())
    case Forms.DeliveryIntent{}: [option("send", User.delivery_caption(User.Send{})), option("steer", User.delivery_caption(User.Steer{}))]
    case _: [option(observed(value), "Current value")]

def execution_options(field: String, configuration: Context.Configuration, preview: Context.Preview, projects: +List<View.ProjectChoice>, reviewers: +List<Domain.Profile>) -> +List<Forms.ChoiceValue>:
  match field:
    case "context-origin": List.append(&2, Forms.ChoiceValue, origin_options(Forms.ContextValue{preview}), project_origin_options(projects))
    case "approval-policy": List.append(&2, Forms.ChoiceValue, [option("ask", "Ask for approval"), option("full-access", "Full access")], reviewer_options(reviewers))
    case _: Nil{}

def permitted_option(permitted: Bool, value: Forms.ChoiceValue, rest: +List<Forms.ChoiceValue>) -> +List<Forms.ChoiceValue>:
  match permitted:
    case True{}: value <> rest
    case False{}: rest

def permitted_options(values: +List<Forms.ChoiceValue>, +profile: Domain.Profile) -> +List<Forms.ChoiceValue>:
  match values:
    case Nil{}: Nil{}
    case Con{Forms.ChoiceValue{+value, label}, rest}:
      permitted_option(Domain.profile_permitted(profile, value), Forms.ChoiceValue{value, label}, permitted_options(rest, profile))

def profile_reasoning_options(+profile: Domain.Profile) -> +List<Forms.ChoiceValue>:
  match profile:
    case Domain.Profile{id, provider, name, Reasoning.Fixed{}, Some{Domain.ReasoningOptions{default, values}}}: permitted_options(options(values), profile)
    case Domain.Profile{id, provider, name, policy, capability}: permitted_options(policy_options(policy), profile)

def selected_reasoning(found: Bool, profile: Domain.Profile, fallback: +List<Forms.ChoiceValue>) -> +List<Forms.ChoiceValue>:
  match found:
    case True{}: profile_reasoning_options(profile)
    case False{}: fallback

def reasoning_options(+profile: String, values: +List<Domain.Profile>) -> +List<Forms.ChoiceValue>:
  match values:
    case Nil{}: Nil{}
    case Con{Domain.Profile{+id, provider, name, policy, options}, rest}: selected_reasoning(String.eq(id, profile), Domain.Profile{id, provider, name, policy, options}, reasoning_options(profile, rest))

def model_group_options(field: String, profile: String, choices: +List<Domain.Profile>) -> +List<Forms.ChoiceValue>:
  match field:
    case "model-profile": profile_options(choices)
    case "reasoning-effort": reasoning_options(profile, choices)
    case _: Nil{}

def group_options(field: String, value: View.InputGroup) -> +List<Forms.ChoiceValue>:
  match value:
    case View.ModelInput{profile, reasoning, choices}: model_group_options(field, profile, choices)
    case View.CardAssistanceInput{enabled, profile, choices}: assistance_options(field, choices)
    case View.ExecutionInput{configuration, preview, workspace, projects, reviewers}: execution_options(field, configuration, preview, projects, reviewers)
    case View.CardContentInput{value, projects, stages, priorities, owners}: card_options(field, projects, priorities, owners)
    case _: Nil{}

def enriched_options(+field: String, values: +List<View.InputGroup>) -> +List<Forms.ChoiceValue>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: prefer_options(group_options(field, value), enriched_options(field, rest))

def choices(+field: Forms.Field, value: Forms.Observed, groups: +List<View.InputGroup>) -> +List<Forms.ChoiceValue>:
  match field:
    case Forms.ReasoningEffort{}: enriched_options("reasoning-effort", groups)
    case other: prefer_options(enriched_options(Forms.key(other), groups), field_options(other, value))
