From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Foundation Require TextJson.
From Selvedge.Kernel Require Import Conversation Streams.
From Selvedge.Browser Require Import NavigationIdentity.
From Selvedge.Interaction Require Import Codec Identity Origin CodeSource Audit.
From Selvedge.Interaction Require TaskHistory.
From Selvedge.Browser Require Import DocumentPublication DocumentState Documents ToolAppearance.
From Selvedge.Programming Require Import Graphics.
From Selvedge.Interaction.Interactive Require Import Types State.
From Selvedge.Browser.Interactive Require Render.
From Selvedge.Browser.Scene Require Import Surface.
From Selvedge.Browser.Presentation Require Import Roles.
From Selvedge.Browser.Scene Require Import Model.
From Selvedge.Browser.Presentation Require Import Information.
Import ListNotations.
Open Scope string_scope.
Module S := Selvedge.Browser.Scene.Surface.
Module R := Selvedge.Browser.Presentation.Roles.
Module M := Selvedge.Browser.Scene.Model.
Record actions (Action:Type) := ReadingActions {
 reading_disclosure:N->N->N->bool->Action;
 reading_interactive:Types.input->Action;
 reading_retained:string->bool->Action
}.
Arguments ReadingActions {Action}.
Arguments reading_disclosure {Action}.
Arguments reading_interactive {Action}.
Arguments reading_retained {Action}.
Definition control {A} key label (input:A) :=
 S.Node key "conversation/control" label R.Button
  (S.Activate (M.Control key label M.Secondary input M.Available)) [].
Definition fact {A} key value : S.node A := S.Node key "conversation/fact" "" R.Content (S.Fact value) [].
Definition source_for namespace task occurrence message :=
 match bind (field "origin" message) Origin.decode_origin with
 |Some origin=>CodeSource.Generated namespace task origin true
 |None=>CodeSource.Message task occurrence end.
Definition history_target namespace task occurrence message:=
 NavigationIdentity.task_view_key(NavigationIdentity.PrimaryTask task)
  (CodeSource.source_key(source_for namespace task occurrence message)).
Definition scope_meaning {A} view (meaning:S.meaning A) :=
 match meaning with S.Graphic drawing=>S.Graphic (Graphics.map_keys (NavigationIdentity.task_view_key view) drawing)
 |_=>meaning end.
Fixpoint in_view {A} view (node:S.node A) : S.node A :=
 let 'S.Node key semantic label role meaning children:=node in
 S.Node (NavigationIdentity.task_view_key view key) semantic label role (scope_meaning view meaning)
  (map (in_view view) children).
Definition attachments {A} (on_interactive:Types.input->A) context retained interactive source :=
 match source with
 |CodeSource.Generated namespace viewer origin closed=>
   let document:=Documents.Document viewer origin "" closed in
   fold_right (fun block rest=>
     match Documents.code_identity_for_document namespace document block.(block_owner) retained with
     |Some identity=>S.map_node on_interactive (Render.fence_for identity block (Documents.environment context false))::rest
     |None=>rest end) [] interactive.(blocks)
 |_=>[] end.
Definition reading {A} source value retained : S.meaning A :=
 match source with
 |CodeSource.Generated namespace viewer origin closed=>
   match Documents.document_stamp namespace (Documents.Document viewer origin value closed) retained with
   |Some stamp=>S.PublishedText (DocumentPublication.PublishedDocument
      (document_namespace stamp) (document_viewer stamp) (document_origin stamp)
      (document_epoch stamp) (document_source stamp) (document_ending stamp))
   |None=>S.RichText source value end
 |_=>S.RichText source value end.
Definition speech {A} action context retained interactive task occurrence message : S.node A :=
 let source:=source_for (context_namespace context) task occurrence message in
 let key:=CodeSource.source_key source in
 S.Node key ("message/"++show_natural occurrence) "Message"
  (if Conversation.json_message_assistant message ||
    String.eqb (value_or "" (Conversation.json_message_role message)) "assistant"
   then R.AssistantMessage else R.UserMessage)
  (reading source (value_or "" (Conversation.json_message_text message)) retained)
  (attachments action context retained interactive source).
Definition group {A} (action:actions A) context retained interactive task disclosures history (entry:Audit.group) : S.node A :=
 match entry with
 |Audit.Spoken (occurrence,message)=>speech action.(reading_interactive) context retained interactive task (N.of_nat occurrence) message
 |Audit.Activity first rest=>let entries:=first::rest in
   let identity:=N.of_nat (fst first) in let attention:=Audit.attention entries in
   let disclosure:=(4 * identity + 3)%N in
   let expanded:=Audit.disclosed disclosure disclosures attention in
   let key:="task/"++show_natural task++"/activity/"++show_natural identity in
   let summary:=Audit.summary history entries in
   S.Node key ("activity/"++show_natural identity) summary R.Activity
    (S.ActivityContent expanded (Audit.faces history entries))
    [S.Node (key++"/disclosure") "activity-disclosure" summary R.Button
      (S.Activate (M.Control "disclosure" summary M.Secondary
        (action.(reading_disclosure) task disclosure attention (negb expanded)) M.Available)) []]
 end.
Definition preview_source context output part :=
 let task:=Streams.output_task output in
 match DocumentState.find_task task (context_world context) with
 |Some record=>match bind (field "model_pending" record) (fun pending=>bind (string_field "mode" pending) Origin.decode_mode) with
   |Some mode=>CodeSource.Generated (context_namespace context) task
      (Origin.OutputOrigin task (Streams.output_operation output) part mode) false
   |None=>CodeSource.StreamingPart task (Streams.output_operation output) part end
 |None=>CodeSource.StreamingPart task (Streams.output_operation output) part end.
Definition preview_node {A} retained source value (children : list (S.node A)) : S.node A :=
 S.Node (CodeSource.source_key source) "generated-output" "Agent output" R.AssistantMessage
  (reading source value retained) children.
Definition preview {A} action context retained interactive output part : S.node A :=
 let '(ordinal,value):=part in let source:=preview_source context output ordinal in
 preview_node retained source value (attachments action context retained interactive source).
Definition retained_part {A} (action:actions A) context retained interactive stamp : list (S.node A) :=
 let identity:=DocumentState.document_identity stamp in
 let source:=CodeSource.Generated (document_namespace stamp) (document_viewer stamp) (document_origin stamp) false in
 let visible:=negb (document_archived stamp) || document_revealed stamp in
 let notice:=if document_archived stamp then "未完成显示已收起" else
   match document_ending stamp with Interrupted=>"生成未完成（仅在本次会话保留）"|_=>"输出同步中（仅在本次会话保留）" end in
 List.app [S.Node (identity++"/unfinished-notice") "unfinished-notice" notice R.Content S.Region
   (List.app [fact (identity++"/unfinished-label") notice]
    (List.app (if document_archived stamp then
      [control (identity++"/archived-source") (if visible then "收起源码" else "展开源码")
        (action.(reading_retained) identity true)] else [])
     [control (identity++"/dismiss-unfinished") "关闭未完成回复" (action.(reading_retained) identity false)]))]
 (if visible then [S.Node identity "generated-output" "Interrupted output" R.AssistantMessage (reading source (document_source stamp) retained)
   (attachments action.(reading_interactive) context retained interactive source)] else []).
Definition task_messages context task :=
 value_or [] (option_map (items "history") (DocumentState.find_task task (context_world context))).
Definition has_history context task :=
 Audit.has_reading (task_messages context task).
Definition history_card_address index level := (4 * N.of_nat index + level)%N.
Definition history_card_control {A} (action:actions A) task key label index level (default:bool) disclosures :=
 let address:=history_card_address index level in
 let open_card:=Audit.disclosed address disclosures (if default then 1%N else 0%N) in
 (open_card,M.Control key label M.Secondary (action.(reading_disclosure) task address 0%N (negb open_card)) M.Available).

Definition tool_definition context task (name:string) :=
 let named:=fun tool=>String.eqb name (text "name" tool) in
 match find named (items "tools" (context_world context)) with
 |Some tool=>Some tool
 |None=>bind (DocumentState.find_task task (context_world context))
    (fun task_record=>find named (items "tools" task_record)) end.
Definition invocation_face context task (invocation:TaskHistory.invocation) :=
 let source:=snd (TaskHistory.invocation_entry invocation) in
 let name:=Audit.call_name source in
 let '(label,argument,symbol,icon):=
   if String.eqb name "bash" then
     let command:=text "command" (value_or JNull (field "arguments" (value_or JNull (field "content" source)))) in
     (name,command,ToolAppearance.shell_symbol command,None)
   else match ToolAppearance.native_symbol name with
   |Some symbol=>(name,"",symbol,None)
   |None=>match tool_definition context task name with
     |Some tool=>match bind (field "source" tool) (string_field "name"),
                       bind (field "source" tool) (string_field "server") with
       |Some remote,Some _=>(remote,"","plug",string_field "icon" tool)
       |_,_=>(name,"","task-tool",None) end
     |None=>(name,"","task-tool",None) end end in
 S.TaskToolFace task (TaskHistory.invocation_id invocation)
   label argument symbol icon
   (TaskHistory.invocation_running invocation)
   (match TaskHistory.invocation_result invocation with Some result=>Audit.failed(snd result)|None=>false end).

Definition result_text (entry:TaskHistory.entry) :=
 let source:=snd entry in
 let contents:=value_or JNull (field "content" source) in
 match string_field "stdout" contents,string_field "stderr" contents with
 |Some stdout,Some stderr=>
   let failure:=text "message" (value_or JNull (field "error" contents)) in
   String.concat "
" (filter (fun line=>negb(String.eqb line "")) [stdout;stderr;failure])
 |_,_=>match contents with JString output=>output | value=>TextJson.render_json value end end.
Definition invocation_details (invocation:TaskHistory.invocation) :=
 match TaskHistory.invocation_result invocation with
 |Some result=>match TaskHistory.invocation_receipt invocation with
   |Some receipt=>result_text result++"

执行回执
"++result_text receipt
   |None=>result_text result end
 |None=>"" end.

Definition tool_card {A} (action:actions A) context task disclosures invocation : S.node A :=
 let index:=fst(TaskHistory.invocation_entry invocation) in
 let face:=invocation_face context task invocation in
 let key:="tool-call/"++show_nat index in
 let '(expanded,toggle):=history_card_control action task key (S.task_tool_label face) index 2%N false disclosures in
 S.Node key "tool-call" (S.task_tool_label face) R.Content
   (S.TaskHistoryCard (S.TaskToolCallCard face (if expanded then invocation_details invocation else "")) expanded toggle) [].

Definition latest_tool (calls:list TaskHistory.invocation) := hd_error (rev calls).

Definition process_step {A} (action:actions A) context retained interactive task disclosures history step : S.node A :=
 match step with
 |TaskHistory.Commentary entry=>
   let spoken:=speech action.(reading_interactive) context retained interactive task (N.of_nat(fst entry)) (snd entry) in
   S.Node (S.node_key spoken) "task-commentary" (S.node_label spoken) (S.node_role spoken)
     (S.node_meaning spoken) (S.node_children spoken)
 |TaskHistory.Tools first []=>tool_card action context task disclosures first
 |TaskHistory.Tools first (next::rest)=>
   let calls:=first::next::rest in
   let index:=fst(TaskHistory.invocation_entry first) in
   let key:="tool-group/"++show_nat index in
   let face:=invocation_face context task (value_or first (latest_tool calls)) in
   let label:=S.task_tool_label face in
   let '(expanded,toggle):=history_card_control action task key label index 1%N false disclosures in
   S.Node key "tool-group" label R.Content (S.TaskHistoryCard (S.TaskToolGroupCard face) expanded toggle)
    (map (tool_card action context task disclosures) calls)
 |TaskHistory.Supporting first rest=>group action context retained interactive task disclosures history (Audit.Activity first rest)
 end.
Definition step_invocations step :=
 match step with TaskHistory.Tools first rest=>first::rest | _=>[] end.
Definition task_history_node {A} (action:actions A) context retained interactive task disclosures history entry : S.node A :=
 match entry with
 |TaskHistory.Speech (index,message)=>speech action.(reading_interactive) context retained interactive task (N.of_nat index) message
 |TaskHistory.Process index steps ended=>
   let running:=negb ended && value_or false
     (option_map (flag "working") (DocumentState.find_task task (context_world context))) in
   let title:=if running then "处理中…" else "处理完成" in
   let key:="task-process/"++show_nat index in
   let '(expanded,toggle):=history_card_control action task key title index 0%N (negb ended) disclosures in
   let latest:=if running then option_map (invocation_face context task) (latest_tool (flat_map step_invocations steps)) else None in
   S.Node key key title R.Activity (S.TaskHistoryCard (S.TaskProcessCard running latest) expanded toggle)
    (map (process_step action context retained interactive task disclosures history) steps)
 end.
Definition task_operations context task :=
 value_or [] (option_map (items "operations") (DocumentState.find_task task (context_world context))).
Definition history {A} (action:actions A) context retained interactive view disclosures : list (S.node A) :=
 let task:=NavigationIdentity.task_view_task view in
 let messages:=task_messages context task in
 map (fun entry=>in_view view (task_history_node action context retained interactive task disclosures messages entry))
   (TaskHistory.project messages (task_operations context task)).

Definition commentary_process index history operations :=
 bind (find (fun section=>match section with
  |TaskHistory.Process _ steps _=>existsb (fun step=>match step with
    |TaskHistory.Commentary entry=>Nat.eqb index(fst entry) |_=>false end) steps
  |_=>false end) (TaskHistory.project history operations))
  (fun section=>match section with
   |TaskHistory.Process occurrence _ _=>Some (history_card_address occurrence 0%N) |_=>None end).

Inductive reply :=
 | AwaitingReply
 | LiveReply (output:Streams.live_output) (first:N*string) (rest:list(N*string)).
Definition task_reply context task :=
 match current_task_preview context task with
 |Some output=>match Streams.output_parts output with
   |first::rest=>LiveReply output first rest
   |[]=>AwaitingReply
   end
 |None=>AwaitingReply
 end.
Definition reply_nodes {A} (action:actions A) context retained interactive task : list (S.node A) :=
 match task_reply context task with
 |AwaitingReply=>[]
 |LiveReply output first rest=>
   map (preview action.(reading_interactive) context retained interactive output) (first::rest)
 end.
Definition unfinished_nodes {A} (action:actions A) context retained interactive task : list (S.node A) :=
 match flat_map (retained_part action context retained interactive)
   (Documents.task_retained_stamps context retained task) with
 |[]=>[]
 |parts=>[S.Node "unfinished-replies" "unfinished-replies" "未完成回复" R.Content S.Region
   (S.Node "unfinished-replies/heading" "heading" "未完成回复" R.Content
     (S.InformationText Information.GroupTitle) []::parts)]
 end.
Definition task_reading_tail {A} (action:actions A) context retained interactive view : list (S.node A) :=
 let task:=NavigationIdentity.task_view_task view in
 map (in_view view) (List.app (unfinished_nodes action context retained interactive task)
   (reply_nodes action context retained interactive task)).

Fixpoint same_items {A} (equal:A->A->bool) (left right:list A) :=
 match left,right with
 |[],[]=>true
 |item::rest,value::tail=>equal item value && same_items equal rest tail
 |_,_=>false end.
Definition same_reply before after task :=
 match task_reply before task,task_reply after task with
 |AwaitingReply,AwaitingReply=>true
 |LiveReply previous first rest,LiveReply next next_first next_rest=>
   let same_part '(index,source) '(other,following):=
     N.eqb index other && String.eqb source following &&
     String.eqb (CodeSource.source_key (preview_source before previous index))
       (CodeSource.source_key (preview_source after next other)) in
   same_part first next_first && same_items same_part rest next_rest
 |_,_=>false end.
Definition same_retained_reply before after :=
 String.eqb (document_identity before) (document_identity after) &&
 N.eqb (document_epoch before) (document_epoch after) &&
 Documents.same_ending (document_ending before) (document_ending after) &&
 Bool.eqb (document_archived before) (document_archived after) &&
 Bool.eqb (document_revealed before) (document_revealed after) &&
 String.eqb (document_source before) (document_source after).
Definition task_reply_changed before before_retention after after_retention task :=
 negb (same_reply before after task &&
   same_items same_retained_reply (Documents.task_retained_stamps before before_retention task)
     (Documents.task_retained_stamps after after_retention task)).
Definition shared_ui {A} (on_interactive:Types.input->A) context retained interactive : list (S.node A) :=
 fold_right (fun block rest=>match Documents.shared_work context block.(block_owner),
   Documents.publication_identity context block.(block_owner) retained with
 |Some _,Some identity=>S.map_node on_interactive
   (Render.shared_for identity block (Documents.environment context false))::rest
 |_,_=>rest end) [] interactive.(blocks).
