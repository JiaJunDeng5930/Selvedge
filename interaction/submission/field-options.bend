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
    case Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, reviewers}: workspace_roots(workspace)
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
    case Forms.ContextValue{preview, reviewers}: context_text(preview)
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

def task_profile_option_hidden(hidden: Bool, profile: Domain.Profile, rest: +List<Forms.ChoiceValue>) -> +List<Forms.ChoiceValue>:
  match hidden:
    case True{}: rest
    case False{}:
      Domain.Profile{id, provider, name, policy, options} = profile
      option(id, name) <> rest

def task_profile_option(+profile: Domain.Profile, rest: +List<Forms.ChoiceValue>) -> +List<Forms.ChoiceValue>:
  task_profile_option_hidden(Domain.is_codex_auto_review(profile), profile, rest)

def profile_options(values: +List<Domain.Profile>) -> +List<Forms.ChoiceValue>:
  match values:
    case Nil{}: Nil{}
    case Con{profile, rest}: task_profile_option(profile, profile_options(rest))

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
    case Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, reviewers}: origin_option_values(origin)
    case _: [option("environment", "Environment defaults")]

def policy_options(policy: Reasoning.Policy) -> +List<Forms.ChoiceValue>:
  match policy:
    case Reasoning.Fixed{}: Nil{}
    case Reasoning.Adaptive{evaluator, efforts, baseline, transport, maximum}: [option("auto", "Automatic")]

type AssistanceOptionsName is Data:
  AssistanceOptionsNameAssistanceProfile{}
  AssistanceOptionsNameOther{}

def assistance_options_discriminant(+value: String) -> AssistanceOptionsName:
  Bool.pick(AssistanceOptionsName, String.eq(value, "assistance-profile"), AssistanceOptionsNameAssistanceProfile{},
    AssistanceOptionsNameOther{})

def assistance_options_classified(field: AssistanceOptionsName, profiles: +List<Domain.Profile>) -> +List<Forms.ChoiceValue>:
  match field:
    case AssistanceOptionsNameAssistanceProfile{}: option("", "使用看板默认模型") <> profile_options(profiles)
    case AssistanceOptionsNameOther{}: Nil{}

def assistance_options(field: String, profiles: +List<Domain.Profile>) -> +List<Forms.ChoiceValue>:
  assistance_options_classified(assistance_options_discriminant(field), profiles)

def priority_options(values: +List<Board.Priority>) -> +List<Forms.ChoiceValue>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}: option(Board.priority_name(value), Board.priority_label(value)) <> priority_options(rest)

type CardOptionsName is Data:
  CardOptionsNameCardProject{}
  CardOptionsNameCardOwner{}
  CardOptionsNameCardPriority{}
  CardOptionsNameOther{}

def card_options_discriminant(+value: String) -> CardOptionsName:
  Bool.pick(CardOptionsName, String.eq(value, "card-project"), CardOptionsNameCardProject{},
    Bool.pick(CardOptionsName, String.eq(value, "card-owner"), CardOptionsNameCardOwner{},
    Bool.pick(CardOptionsName, String.eq(value, "card-priority"), CardOptionsNameCardPriority{},
    CardOptionsNameOther{})))

def card_options_classified(field: CardOptionsName, projects: +List<View.ProjectChoice>, priorities: +List<Board.Priority>, owners: +List<Forms.ChoiceValue>) -> +List<Forms.ChoiceValue>:
  match field:
    case CardOptionsNameCardProject{}: option("", "No project") <> project_options(projects)
    case CardOptionsNameCardOwner{}: owners
    case CardOptionsNameCardPriority{}: priority_options(priorities)
    case CardOptionsNameOther{}: Nil{}

def card_options(field: String, projects: +List<View.ProjectChoice>, priorities: +List<Board.Priority>, owners: +List<Forms.ChoiceValue>) -> +List<Forms.ChoiceValue>:
  card_options_classified(card_options_discriminant(field), projects, priorities, owners)

def stage_options(values: +List<Board.Stage>) -> +List<Forms.ChoiceValue>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}: option(Board.stage_name(value), Board.stage_label(value)) <> stage_options(rest)

def field_options(field: Forms.Field, value: Forms.Observed) -> +List<Forms.ChoiceValue>:
  match field:
    case Forms.TaskEnvironment{}: [option("current", "Current workspace"), option("local", "Local worktree"), option("tencent_cvm", "Tencent Cloud CVM")]
    case Forms.SandboxMode{}: [option("workspace-write", "Workspace write"), option("read-only", "Read only")]
    case Forms.ContextOrigin{}: origin_options(value)
    case Forms.ApprovalReviewer{}: Nil{}
    case Forms.ApprovalPolicy{}: [option("ask", "Ask for approval"), option("full-access", "Full access"), option("automatic", "Automatic review")]
    case Forms.WorkspacePrimary{}: options(primary_choices(value))
    case Forms.CardStage{}: stage_options(Board.stages())
    case Forms.CardPriority{}: priority_options(Board.priorities())
    case Forms.DeliveryIntent{}: [option("send", User.delivery_caption(User.Send{})), option("steer", User.delivery_caption(User.Steer{}))]
    case _: [option(observed(value), "Current value")]

def approval_choice_reviewer_options(choice: Context.ApprovalChoice, reviewers: +List<Domain.Profile>) -> +List<Forms.ChoiceValue>:
  match choice:
    case Context.AutomaticReview{profile}: reviewer_options(reviewers)
    case _: Nil{}

def approval_reviewer_options(preview: Context.Preview, reviewers: +List<Domain.Profile>) -> +List<Forms.ChoiceValue>:
  match preview:
    case Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}: approval_choice_reviewer_options(Context.observed_approval(approval), reviewers)
    case _: Nil{}

type ExecutionOptionsName is Data:
  ExecutionOptionsNameContextOrigin{}
  ExecutionOptionsNameApprovalReviewer{}
  ExecutionOptionsNameApprovalPolicy{}
  ExecutionOptionsNameOther{}

def execution_options_discriminant(+value: String) -> ExecutionOptionsName:
  Bool.pick(ExecutionOptionsName, String.eq(value, "context-origin"), ExecutionOptionsNameContextOrigin{},
    Bool.pick(ExecutionOptionsName, String.eq(value, "approval-reviewer"), ExecutionOptionsNameApprovalReviewer{},
    Bool.pick(ExecutionOptionsName, String.eq(value, "approval-policy"), ExecutionOptionsNameApprovalPolicy{},
    ExecutionOptionsNameOther{})))

def execution_options_classified(field: ExecutionOptionsName, configuration: Context.Configuration, preview: Context.Preview, projects: +List<View.ProjectChoice>, reviewers: +List<Domain.Profile>) -> +List<Forms.ChoiceValue>:
  match field:
    case ExecutionOptionsNameContextOrigin{}: List.append(&2, Forms.ChoiceValue, origin_options(Forms.ContextValue{preview, reviewers}), project_origin_options(projects))
    case ExecutionOptionsNameApprovalReviewer{}: approval_reviewer_options(preview, reviewers)
    case ExecutionOptionsNameApprovalPolicy{}: List.append(&2, Forms.ChoiceValue, [option("ask", "Ask for approval"), option("full-access", "Full access")], reviewer_options(reviewers))
    case ExecutionOptionsNameOther{}: Nil{}

def execution_options(field: String, configuration: Context.Configuration, preview: Context.Preview, projects: +List<View.ProjectChoice>, reviewers: +List<Domain.Profile>) -> +List<Forms.ChoiceValue>:
  execution_options_classified(execution_options_discriminant(field), configuration, preview, projects, reviewers)

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

type ModelGroupOptionsName is Data:
  ModelGroupOptionsNameModelProfile{}
  ModelGroupOptionsNameReasoningEffort{}
  ModelGroupOptionsNameOther{}

def model_group_options_discriminant(+value: String) -> ModelGroupOptionsName:
  Bool.pick(ModelGroupOptionsName, String.eq(value, "model-profile"), ModelGroupOptionsNameModelProfile{},
    Bool.pick(ModelGroupOptionsName, String.eq(value, "reasoning-effort"), ModelGroupOptionsNameReasoningEffort{},
    ModelGroupOptionsNameOther{}))

def model_group_options_classified(field: ModelGroupOptionsName, profile: String, choices: +List<Domain.Profile>) -> +List<Forms.ChoiceValue>:
  match field:
    case ModelGroupOptionsNameModelProfile{}: profile_options(choices)
    case ModelGroupOptionsNameReasoningEffort{}: reasoning_options(profile, choices)
    case ModelGroupOptionsNameOther{}: Nil{}

def model_group_options(field: String, profile: String, choices: +List<Domain.Profile>) -> +List<Forms.ChoiceValue>:
  model_group_options_classified(model_group_options_discriminant(field), profile, choices)

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
