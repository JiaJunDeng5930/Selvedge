From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Programming Require Import Schema.
From Selvedge.Foundation Require Import Utf8.
From Selvedge.Kernel Require Domain WorkspaceBackend.
From Selvedge.Features Require Domain.
From Selvedge.Interaction Require Import Identity Context.
From Selvedge.Interaction.Submission Require Fields.
Import ListNotations.
Open Scope string_scope.

Record text := Text { text_value : string; text_images : list Selvedge.Features.Domain.attachment }.
Inductive task_workspace := CurrentWorkspace | ManagedWorkspace (backend : WorkspaceBackend.backend).
Inductive body :=
| WorkNameBody (work : N) (name : string)
| NewTaskBody (message : text) (profile reasoning : string)
    (context : Context.configuration) (workspace_mode : task_workspace) (work : option N)
| MessageBody (task : N) (message : text) (delivery : Fields.delivery)
| ProjectBody (project : option N) (name : string)
    (workspace : Selvedge.Kernel.Domain.workspace) (create_worktree : bool)
| CardBody (card : option N) (revision : N) (value : Selvedge.Features.Domain.card_draft)
    (assist : bool) (profile : string) (keep_open : bool)
| AgentBody (agent : option N) (revision : N) (name profile reasoning instructions : string)
    (context : Context.configuration) (concurrency : N)
| ForkBody (task count : N) (messages : list string) (context : Context.configuration)
| CompactBody (task : N) (summary : option string)
| TaskGraphBody (graph : option N) (declaration : string) (parsed : option json) (work : option N)
| TitlePromptsBody (revision : N) (task_prompt agent_prompt : string).
Inductive feedback := Editing | Accepted (revision : N) (reply : json)
| Rejected (revision : N) (diagnostic : json) | WorkspaceRejected (revision : N) (reason : string).
Inductive selection_direction := DirectionNone | DirectionForward | DirectionBackward.
Record selection := Selection { selection_start : N; selection_end : N;
  selection_orientation : selection_direction }.
Definition direction_name value := match value with
 |DirectionNone=>"none"|DirectionForward=>"forward"|DirectionBackward=>"backward"end.
Definition decode_direction value := match value with
 |"none"=>Some DirectionNone|"forward"=>Some DirectionForward|"backward"=>Some DirectionBackward|_=>None end.
Definition selection_from_bytes text start finish direction :=
 if N.leb start finish && N.leb finish (N.of_nat(String.length text))then
 match Utf8.scalar_count(String.substring 0 (N.to_nat start)text),
       Utf8.scalar_count(String.substring 0 (N.to_nat finish)text)with
 |Some start_count,Some end_count=>Some(Selection(N.of_nat start_count)(N.of_nat end_count)direction)
 |_,_=>None end else None.
Record draft := Draft {
  revision : N;
  contents : body;
  draft_feedback : feedback;
  directory_entry : string;
  message_selection : option selection
}.
Definition owner value := match contents value with
| WorkNameBody work _ => Identity.WorkName work
| NewTaskBody _ _ _ _ _ work => Identity.NewTask work
| MessageBody task _ _ => Identity.Message task
| ProjectBody project _ _ _ => Identity.Project project
| CardBody card _ _ _ _ _ => Identity.Card card
| AgentBody agent _ _ _ _ _ _ _ => Identity.Agent agent
| ForkBody task _ _ _ => Identity.Fork task
| CompactBody task _ => Identity.Compact task
| TaskGraphBody graph _ _ work => Identity.graph_editor graph work
| TitlePromptsBody _ _ _ => Identity.TitlePrompts end.
Definition empty_text := Text "" [].
Definition empty_workspace := Selvedge.Kernel.Domain.Workspace [] None.
Definition new_body e := match e with
| Identity.NewTask work => NewTaskBody empty_text "" "" Context.initial CurrentWorkspace work
| Identity.Message task => MessageBody task empty_text Fields.Send
| Identity.Project id => ProjectBody id "" empty_workspace false
| Identity.Card id => CardBody id 0
    (Selvedge.Features.Domain.CardDraft "" "" Selvedge.Features.Domain.Backlog
      Selvedge.Features.Domain.NoPriority Selvedge.Features.Domain.Unassigned None [] []) false "" false
| Identity.Agent id => AgentBody id 0 "" "" "" "" Context.initial 1
| Identity.Fork task => ForkBody task 1 [] (Context.Configuration (Context.ParentTask task) None None None)
| Identity.Compact task => CompactBody task None
| Identity.TaskGraph id work => TaskGraphBody id "" None work
| Identity.WorkName work => WorkNameBody work ""
| Identity.TitlePrompts => TitlePromptsBody 0 "" "" end.
Definition new_draft e := Draft 0 (new_body e) Editing "" None.
Definition with_body value d := Draft (N.succ (revision d)) value Editing (directory_entry d) (message_selection d).
Definition with_directory_entry value d := Draft (revision d) (contents d) (draft_feedback d) value (message_selection d).
Definition with_feedback value d := Draft (revision d) (contents d) value (directory_entry d) (message_selection d).
Definition with_selection value d := Draft (revision d) (contents d) (draft_feedback d) (directory_entry d) value.
Definition find_draft e values := find (fun value => same_editor e (owner value)) values.
Definition store_draft value values := value :: filter (fun own => negb (same_editor (owner value) (owner own))) values.

Definition explicit_workspace value:=match contents value with
|ProjectBody _ _ workspace _=>Some workspace
|NewTaskBody _ _ _ configuration _ _|AgentBody _ _ _ _ _ _ configuration _|ForkBody _ _ _ configuration=>Context.workspace_override configuration
|_=>None end.
