From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Kernel Require Import Conversation Streams.
From Selvedge.Interaction Require Import Codec Identity Origin CodeSource DocumentPublication DocumentState Documents Audit.
From Selvedge.Programming Require Import Graphics.
From Selvedge.Interaction.Interactive Require Import Types State Language.
From Selvedge.Programming.Presentation Require Import Surface.
From Selvedge.Interaction.Presentation Require Import Roles.
From Selvedge.Programming.Presentation Require Import Model.
From Selvedge.Interaction.Presentation Require Import Information.
Import ListNotations.
Open Scope string_scope.
Module S := Selvedge.Programming.Presentation.Surface.
Module R := Selvedge.Interaction.Presentation.Roles.
Module M := Selvedge.Programming.Presentation.Model.
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
 Identity.task_view_key(Identity.PrimaryTask task)
  (CodeSource.source_key(source_for namespace task occurrence message)).
Definition scope_meaning {A} view (meaning:S.meaning A) :=
 match meaning with S.Graphic drawing=>S.Graphic (Graphics.map_keys (Identity.task_view_key view) drawing)
 |_=>meaning end.
Fixpoint in_view {A} view (node:S.node A) : S.node A :=
 let 'S.Node key semantic label role meaning children:=node in
 S.Node (Identity.task_view_key view key) semantic label role (scope_meaning view meaning)
  (map (in_view view) children).
Definition attachments {A} (on_interactive:Types.input->A) context retained interactive source :=
 fold_right (fun block rest=>match Documents.publication_identity context block.(block_owner) retained with
 |Some identity=>if String.eqb (CodeSource.source_key source) (CodeSource.source_key identity.(CodeSource.document_source))
   then S.map_node on_interactive (Language.fence_for identity block (Documents.environment context false))::rest
   else rest
 |None=>rest end) [] interactive.(blocks).
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
   let expanded:=Audit.disclosed identity disclosures attention in
   let key:="task/"++show_natural task++"/activity/"++show_natural identity in
   S.Node key ("activity/"++show_natural identity) (Audit.summary history entries) R.Activity
    (S.ActivityContent expanded (Audit.faces history entries))
    [control (key++"/disclosure") (if expanded then "Collapse activity" else "Expand activity")
      (action.(reading_disclosure) task identity attention (negb expanded))]
 end.
Definition preview_source context output part :=
 let task:=Streams.output_task output in
 match DocumentState.find_task task (context_world context) with
 |Some record=>match bind (field "model_pending" record) (fun pending=>bind (string_field "mode" pending) Origin.decode_mode) with
   |Some mode=>CodeSource.Generated (context_namespace context) task
      (Origin.OutputOrigin task (Streams.output_operation output) part mode) false
   |None=>CodeSource.StreamingPart task (Streams.output_operation output) part end
 |None=>CodeSource.StreamingPart task (Streams.output_operation output) part end.
Definition preview {A} action context retained interactive output part : S.node A :=
 let '(ordinal,value):=part in let source:=preview_source context output ordinal in
 S.Node (CodeSource.source_key source) "generated-output" "Agent output" R.AssistantMessage
  (reading source value retained) (attachments action context retained interactive source).
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
Definition timeline {A} (action:actions A) context retained interactive view disclosures : list (S.node A) :=
 let task:=Identity.task_view_task view in
 let messages:=match DocumentState.find_task task (context_world context) with Some value=>items "history" value|None=>[] end in
 let history:=map (group action context retained interactive task disclosures messages) (Audit.groups 0 messages) in
 let live:=flat_map (fun output=>if N.eqb task (Streams.output_task output)
   then map (preview action.(reading_interactive) context retained interactive output) (Streams.output_parts output) else []) (current_previews context) in
 let unfinished:=flat_map (retained_part action context retained interactive)
   (filter (fun stamp=>N.eqb task (document_viewer stamp)) (Documents.retained_stamps context retained)) in
 let unfinished_section:=match unfinished with
 |[]=>[]
 |parts=>[S.Node "unfinished-replies" "unfinished-replies" "未完成回复" R.Content S.Region
   (S.Node "unfinished-replies/heading" "heading" "未完成回复" R.Content
     (S.InformationText Information.GroupTitle) []::parts)]
 end in
 map (in_view view) (List.app history (List.app unfinished_section live)).
Definition shared_ui {A} (on_interactive:Types.input->A) context retained interactive : list (S.node A) :=
 fold_right (fun block rest=>match Documents.shared_work context block.(block_owner),
   Documents.publication_identity context block.(block_owner) retained with
 |Some _,Some identity=>S.map_node on_interactive
   (Language.shared_for identity block (Documents.environment context false))::rest
 |_,_=>rest end) [] interactive.(blocks).
