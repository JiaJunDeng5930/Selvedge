From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json TextJson Utf8 Numbers.
From Selvedge.Kernel Require Import Domain Codec Conversation.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Definition omission := "
[Evaluator history preview: material omitted; omissions are unknown.]
".
Definition marker := JObject [("role",JString "error");("content",JString omission)].
Definition excerpt (text : string) := match Utf8.chunks text with
 | Some parts => if Nat.leb (List.length parts) 1024 then text else
   String.append (Utf8.render_chunks (firstn 768 parts))
    (String.append omission (Utf8.render_chunks (skipn (List.length parts - 256) parts)))
 | None => omission end.
Definition public_parts (parts : list json) := fold_right (fun part rest =>
 match text_default "type" part "" with
 | "output_text" | "summary_text" => JObject [("text",JString (text_default "text" part ""))] :: rest
 | "refusal" => JObject [("text",JString (text_default "refusal" part ""))] :: rest
 | _ => rest end) [] parts.
(* Tool results can contain another task's provider checkpoint. Project JSON
   before rendering it, so encrypted continuations never become preview text. *)
Fixpoint public_value (fuel : nat) (value : json) : json := match fuel with
 | O => JString "[Evaluator JSON preview: nesting or field limit reached]"
 | S fuel => match value with
   | JArray (item :: rest) => match public_value fuel (JArray rest) with
     | JArray rest => JArray (public_value fuel item :: rest)
     | limit => JArray [public_value fuel item; limit] end
   | JObject ((name,item) :: rest) =>
     match text_default "type" value "" with
     | "reasoning" => JObject [("type",JString "reasoning");("summary",JArray (public_parts (array_default "summary" value)))]
     | "compaction" => JObject [("type",JString "compaction");("omitted",JString "Opaque provider checkpoint")]
     | _ =>
       let item := if String.eqb name "encrypted_content" then JString "[Private provider continuation omitted]" else public_value fuel item in
       match public_value fuel (JObject rest) with
       | JObject rest => JObject ((name,item) :: rest)
       | limit => JObject [(name,item);("__selvedge_preview__",limit)] end end
   | _ => value end end.
Definition text_message role text := JObject [("role",JString role);("content",JString text)].
Definition public_context value := let value := provider_value value in
 match text_default "type" value "" with
 | "message" => Some (text_message "assistant" (String.concat "" (map Conversation.provider_part_text (array_default "content" value))))
 | "reasoning" => Some (text_message "reasoning_summary"
    (String.concat "" (map (fun part => text_default "text" part "") (public_parts (array_default "summary" value)))))
 | _ => None end.
Definition public_message (message : message) := match message with
 | SpeechTranscript _ _ _ who _ text => Some (text_message (match who with UserSpeaker => "user" | AssistantSpeaker => "assistant" end) text)
 | UserMessage content => Some (text_message "user" (Domain.content_text content))
 | AssistantMessage _ text => Some (text_message "assistant" text)
 | FailureMessage text => Some (text_message "error" text)
 | ModelContext _ value => public_context value
 | FunctionCall call => Some (JObject [("role",JString "function_call");("call_id",JString (call_id call));
    ("name",JString (call_name call));("arguments",public_value 512 (call_arguments call))])
 | FunctionOutput id value error => Some (JObject [("role",JString "function_output");("call_id",JString id);("content",public_value 512 value);("is_error",JBool error)])
 | OperationResult _ call value error => Some (JObject [("role",JString "function_output");("call_id",JString (call_id call));
    ("name",JString (call_name call));("content",public_value 512 value);("is_error",JBool error)])
 | ForkReceipt _ call branch => Some (JObject [("role",JString "function_output");("call_id",JString (call_id call));
    ("content",JNumber (Selvedge.Foundation.Numbers.show_natural branch));("is_error",JBool false)])
 | _ => None end.
Definition preview_value value := let rendered := TextJson.render_json value in
 match Utf8.scalar_count rendered with Some count => if Nat.leb count 1024 then value else JString (excerpt rendered)
 | None => JString omission end.
Definition preview_message message := match text_default "role" message "" with
 | "function_call" => JObject [("role",JString "function_call");("call_id",value_or_null "call_id" message);
    ("name",value_or_null "name" message);("arguments",preview_value (value_or_null "arguments" message))]
 | "function_output" => JObject [("role",JString "function_output");("call_id",value_or_null "call_id" message);
    ("is_error",value_or_null "is_error" message);("content",preview_value (value_or_null "content" message))]
 | role => text_message role (excerpt (text_default "content" message "")) end.
Definition call_names (messages : list json) := fold_left (fun names message =>
 if String.eqb (text_default "role" message "") "function_call" then
 text_default "call_id" message "" :: firstn 5 names else names) messages [].
Record selection := Selection { selected_users:nat;selected_notes:nat;selected_outputs:nat;selected_items:list json }.
Fixpoint select_messages (essential seen : bool) (names : list string) (messages : list json) : selection :=
 match messages with [] => Selection 0 0 0 [] | message :: rest =>
 let role := text_default "role" message "" in
 let selected := select_messages essential (seen || String.eqb role "user") names rest in
 let users := selected_users selected in let notes := selected_notes selected in let outputs := selected_outputs selected in
 let '(keep,users,notes,outputs) := match role with
 | "user" => (negb seen || Nat.ltb users (if essential then 1 else 7), S users,notes,outputs)
 | "assistant" | "reasoning_summary" | "error" => (negb essential && Nat.ltb notes 8,users,S notes,outputs)
 | "function_call" => (negb essential && existsb (String.eqb (text_default "call_id" message "")) names,users,notes,outputs)
 | "function_output" => let matches := existsb (String.eqb (text_default "call_id" message "")) names in
    (negb essential && matches && Nat.ltb outputs 12,users,notes,if matches then S outputs else outputs)
 | _ => (false,users,notes,outputs) end in
 Selection users notes outputs (if keep then preview_message message :: selected_items selected else selected_items selected) end.
Definition maximum_bytes : nat := 16384.
Definition fits messages := Nat.leb (String.length (TextJson.render_json (JArray messages))) maximum_bytes.
Definition history (messages : list message) :=
 let public := fold_right (fun message rest => match public_message message with Some value => value :: rest | None => rest end) [] messages in
 let candidate := marker :: selected_items (select_messages false false (call_names public) public) in
 if fits candidate then candidate else
 let essential := marker :: selected_items (select_messages true false [] public) in
 if fits essential then essential else [marker].
