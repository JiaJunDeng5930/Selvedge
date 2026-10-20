From Stdlib Require Import String Ascii List Bool NArith.
From Selvedge.Foundation Require Import Json JsonObjects.
From Selvedge.Kernel Require Import Domain Codec Conversation Numbers.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Inductive portable_role := PortableUser | PortableAssistant.
Record portable_message := PortableMessage { portable_speaker : portable_role; portable_text : string }.
Inductive artifact :=
| PortableArtifact (first : portable_message) (rest : list portable_message) (usage : json)
| NativeArtifact (scope_head : ascii) (scope_tail : string) (first : json) (rest : list json) (usage : json).

Definition portable_message_json (message : portable_message) :=
 JObject [("role", JString (match portable_speaker message with PortableUser => "user" | PortableAssistant => "assistant" end));
          ("content", JString (portable_text message))].
Definition decode_portable_message (value : json) : option portable_message :=
 match string_field "role" value, string_field "content" value with
 | Some "user", Some text => Some (PortableMessage PortableUser text)
 | Some "assistant", Some text => Some (PortableMessage PortableAssistant text)
 | _, _ => None end.
Fixpoint decode_portable_messages (values : list json) : option (list portable_message) :=
 match values with
 | [] => Some []
 | value :: rest => match decode_portable_message value, decode_portable_messages rest with
   | Some message, Some messages => Some (message :: messages) | _, _ => None end
 end.
Definition decode_artifact (value : json) : option artifact :=
 match string_field "format" value, field "items" value with
 | Some "portable", Some (JArray (first :: rest)) =>
   match decode_portable_message first, decode_portable_messages rest with
   | Some message, Some messages => Some (PortableArtifact message messages (value_or_null "usage" value))
   | _, _ => None end
 | Some "native", Some (JArray (first :: rest)) =>
   match string_field "scope" value with
   | Some (String head tail) => Some (NativeArtifact head tail first rest (value_or_null "usage" value))
   | _ => None end
 | _, _ => None end.
Definition artifact_scope (value : artifact) :=
 match value with PortableArtifact _ _ _ => "" | NativeArtifact head tail _ _ _ => String head tail end.
Definition artifact_items (value : artifact) :=
 match value with PortableArtifact first rest _ => map portable_message_json (first :: rest)
 | NativeArtifact _ _ first rest _ => first :: rest end.
Definition artifact_usage (value : artifact) :=
 match value with PortableArtifact _ _ usage | NativeArtifact _ _ _ _ usage => usage end.
Definition artifact_format (value : artifact) :=
 match value with PortableArtifact _ _ _ => "portable" | NativeArtifact _ _ _ _ _ => "native" end.
Definition artifact_json (value : artifact) := JObject [
 ("format", JString (artifact_format value)); ("scope", JString (artifact_scope value));
 ("items", JArray (artifact_items value)); ("usage", artifact_usage value)].
Definition artifact_valid (value : json) := match decode_artifact value with Some _ => true | None => false end.
Definition consumes (value : artifact) (scope : string) :=
 match value with PortableArtifact _ _ _ => true | NativeArtifact head tail _ _ _ => String.eqb (String head tail) scope end.
Definition compatible (value : json) (scope : string) :=
 match decode_artifact value with Some result => consumes result scope | None => false end.

Inductive selection := Original | Replacement (source_length : N) (replacement : artifact).
Definition select_event (position : N) (scope : string) (message : json) (previous : selection) :=
 if String.eqb (text_default "role" message "") "context_replacement" then
 let content := value_or_null "content" message in
 match natural_field "source_length" content, decode_artifact content with
 | Some source, Some value => if (source <=? position) && consumes value scope then Replacement source value else previous
 | _, _ => previous end
 else previous.
Fixpoint latest (messages : list json) (scope : string) (position : N) (previous : selection) :=
 match messages with [] => previous | message :: rest => latest rest scope (N.succ position) (select_event position scope message previous) end.

Definition parts_text (parts : list json) :=
 fold_right (fun part rest => String.append (Conversation.provider_part_text part) rest) "" parts.
Definition readable_context (value : json) : list json :=
 let item := Conversation.provider_value value in
 match string_field "type" item with
 | Some "message" => [JObject [("role", value_or_null "role" item); ("content", JString (parts_text (array_default "content" item)))]]
 | Some "reasoning" => [JObject [("role", JString "assistant"); ("content", JString (parts_text (array_default "summary" item)))]]
 | _ => [] end.
Definition readable_message (message : json) :=
 match string_field "role" message with
 | Some "context_replacement" => []
 | Some "model_context" => readable_context (value_or_null "content" message)
 | _ => [message] end.
Definition raw_messages (messages : list json) := flat_map readable_message messages.
Definition scoped_message (scope : string) (message : json) :=
 match string_field "role" message with
 | Some "context_replacement" => []
 | Some "model_context" =>
   let value := value_or_null "content" message in
   if String.eqb (text_default "type" value "") "provider_receipt" &&
      negb (String.eqb scope "") && String.eqb (text_default "scope" value "") scope then
      [JObject [("role", JString "model_context"); ("content", Conversation.provider_value value)]]
   else readable_context value
 | _ => [message] end.
Definition scoped_messages (messages : list json) (scope : string) := flat_map (scoped_message scope) messages.
Definition image_parts (value : json) :=
 let parts := match value with JArray parts => parts | _ => array_default "content" value end in
 filter (fun part => String.eqb (text_default "type" part "") "image") parts.
Definition fixed_message (message : json) :=
 match string_field "role" message with
 | Some "task_context" => [message]
 | Some "user" | Some "function_output" | Some "operation_result" =>
   match image_parts (value_or_null "content" message) with
   | [] => []
   | parts => [JObject [("role", JString "user"); ("content", JArray parts)]] end
 | _ => [] end.
Definition fixed (messages : list json) := flat_map fixed_message messages.
Definition dialogue (messages : list json) :=
 filter (fun message => negb (String.eqb (text_default "role" message "") "task_context" ||
                             String.eqb (text_default "role" message "") "context_replacement")) messages.
Definition retained_messages (messages : list json) :=
 filter (fun message => negb (String.eqb (text_default "role" message "") "context_replacement")) messages.
Definition assemble (selected : selection) (messages : list json) (scope : string) :=
 match selected with
 | Original => scoped_messages messages scope
 | Replacement source value => (fixed (firstn (N.to_nat source) messages) ++
   dialogue (artifact_items value) ++ scoped_messages (skipn (N.to_nat source) messages) scope)%list end.
Definition target_messages (messages : list json) (scope : string) := assemble (latest messages scope 0 Original) messages scope.
Definition portable_messages (messages : list json) :=
 match latest messages "" 0 Original with
 | Original => messages
 | Replacement source value => (fixed (firstn (N.to_nat source) messages) ++
   dialogue (artifact_items value) ++ retained_messages (skipn (N.to_nat source) messages))%list end.
Definition history_json (owner : N) (history : list message) := map (Codec.message_json owner) history.
Definition has_output (history : list message) (id : string) :=
 existsb (fun message => match message with
 | FunctionOutput call_id _ _ | OperationResult _ (Call call_id _ _) _ _ | ForkReceipt _ (Call call_id _ _) _ => String.eqb call_id id
 | _ => false end) history.
Definition settled_calls (snapshot whole : list message) :=
 forallb (fun message => match message with FunctionCall invocation => has_output whole (call_id invocation) | _ => true end) snapshot.
Definition portable (summary : string) := PortableArtifact
 (PortableMessage PortableUser ("Task continuation summary (fallible; original records remain available through read_task):" ++ String (Ascii.ascii_of_nat 10) summary)) [] JNull.
Definition record (source_length : N) (value : artifact) := ContextReplacement
 (JObject (("source_length", number source_length) :: match artifact_json value with JObject fields => fields | _ => [] end)).
Definition history_extends (snapshot current : list message) :=
 (* Owner is a projection parameter, not part of an individual task's history.
    Both sides use the same owner when comparing that task's captured prefix. *)
 let source := history_json 0 snapshot in
 Nat.leb (List.length source) (List.length current) &&
 JsonObjects.equivalent (JArray source) (JArray (firstn (List.length source) (history_json 0 current))).
Definition adopt (snapshot : list message) (candidate : artifact) (current : list message) :=
 if history_extends snapshot current then (current ++ [record (N.of_nat (List.length snapshot)) candidate])%list else current.
