From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers TextJson.
From Selvedge.Interaction Require Import Codec.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Record diagnostic:=Diagnostic{diagnostic_path:string;diagnostic_message:string;diagnostic_fatal:bool}.
Record owner:=Owner{owner_key:string;epoch:N}.
Definition same_owner a b:=String.eqb a.(owner_key)b.(owner_key)&&N.eqb a.(epoch)b.(epoch).
Record event:=Event{event_owner:owner;path:string;occurrence:N}.
Inductive ending:=Open|Complete|Interrupted.
Definition ending_name e:=match e with Open=>"open"|Complete=>"complete"|Interrupted=>"interrupted"end.
Definition decode_ending s:=if String.eqb s "open"then Some Open else
 if String.eqb s "complete"then Some Complete else if String.eqb s "interrupted"then Some Interrupted else None.
Inductive view_command:=ZoomIn|ZoomOut|Pan(dx dy:string)|Fit|SelectNode(identity:string)|SortColumn(column:string)|Page(page:nat).
Inductive input:=
| SourceChanged(who:owner)(source:string)(closed:bool)(ending:ending)(external:bool)
| Continue(who:owner)
| EnvironmentChanged
| ExternalChanged(who:owner)(allowed:bool)
| ValueChanged(identity:event)(value:json)
| ActionClicked(identity:event)
| ViewChanged(identity:event)(command:view_command)
| Feedback(who:owner)(path:string)(ticket:N)(ok:bool)(message:string)
| Restore(who:owner)(definition:string)(revision:N)(payload:option string)
| StorageResult(who:owner)(revision:N)(ok:bool)(message:string)
| SourceDisclosure(who:owner)
| CopyDefinition(who:owner)
| Remove(who:owner).
Inductive effect:=
| ParseMore(who:owner)
| LoadSnapshot(who:owner)(storage_key definition:string)(revision:N)
| SaveSnapshot(who:owner)(storage_key:string)(revision:N)(payload:json)
| RemoveSnapshot(who:owner)(storage_key:string)
| FillDraft(who:owner)(path:string)(text:string)
| SendMessage(who:owner)(path:string)(ticket:N)(message:string)
| WriteClipboard(who:owner)(path:string)(ticket:N)(text:string)
| OpenUrl(who:owner)(path:string)(ticket:N)(url:string)
| RestoreFieldBuffer(identity:event)(text:string).
Definition encode_owner who:=JObject[("key",JString who.(owner_key));("epoch",number who.(epoch))].
Definition event_key e:=("interactive:"++render_json(JArray[encode_owner e.(event_owner);JString e.(path);number e.(occurrence)]))%string.
Definition decode_owner j:=key <- string_field "key"j;;ep <- natural_field "epoch"j;;Some(Owner key ep).
Definition event_fields e:=[("owner",encode_owner e.(event_owner));("path",JString e.(path));("occurrence",number e.(occurrence))].
Definition decode_event j:=whoj <- field "owner"j;;who <- decode_owner whoj;;path <- string_field "path"j;;occurrence <- natural_field "occurrence"j;;Some(Event who path occurrence).
Definition encode_view command:=match command with
 | ZoomIn=>JObject[("kind",JString "zoom_in")]|ZoomOut=>JObject[("kind",JString "zoom_out")]|Fit=>JObject[("kind",JString "fit")]
 | Pan dx dy=>JObject[("kind",JString "pan");("dx",JString dx);("dy",JString dy)]
 | SelectNode id=>JObject[("kind",JString "select");("identity",JString id)]
 | SortColumn id=>JObject[("kind",JString "sort");("column",JString id)]
 | Page page=>JObject[("kind",JString "page");("page",JNumber(show_nat page))]end.
Definition decode_view j:=kind <- string_field "kind"j;;
 if String.eqb kind "zoom_in"then Some ZoomIn else
 if String.eqb kind "zoom_out"then Some ZoomOut else
 if String.eqb kind "fit"then Some Fit else
 if String.eqb kind "pan"then dx <- string_field "dx"j;;dy <- string_field "dy"j;;Some(Pan dx dy)else
 if String.eqb kind "select"then id <- string_field "identity"j;;Some(SelectNode id)else
 if String.eqb kind "sort"then id <- string_field "column"j;;Some(SortColumn id)else
 if String.eqb kind "page"then s <- number_field "page"j;;n <- parse_nat s;;if Nat.leb n 4096 then Some(Page n)else None
 else None.
Definition encode_input value:=
 let pack name fields:=JObject(("type",JString name)::fields)in
 let owned who:=[("owner",encode_owner who)]in
 match value with
 | SourceChanged who source closed ending external=>pack "source"(owned who++[("source",JString source);("closed",JBool closed);("ending",JString(ending_name ending));("external",JBool external)])
 | Continue who=>pack "continue"(owned who)|EnvironmentChanged=>pack "environment"[]
 | ExternalChanged who allowed=>pack "external"(owned who++[("allowed",JBool allowed)])
 | ValueChanged e value=>pack "value"(event_fields e++[("value",value)])
 | ActionClicked e=>pack "action"(event_fields e)
 | ViewChanged e command=>pack "view"(event_fields e++[("command",encode_view command)])
 | Feedback who path ticket ok message=>pack "feedback"(owned who++[("path",JString path);("ticket",number ticket);("ok",JBool ok);("message",JString message)])
 | Restore who definition revision payload=>pack "restore"(owned who++[("definition",JString definition);("revision",number revision);("present",JBool(match payload with Some _=>true|None=>false end))]++match payload with Some value=>[("payload",JString value)]|None=>[]end)
 | StorageResult who revision ok message=>pack "storage"(owned who++[("revision",number revision);("ok",JBool ok);("message",JString message)])
 | SourceDisclosure who=>pack "source_disclosure"(owned who)
 | CopyDefinition who=>pack "copy_definition"(owned who)
 | Remove who=>pack "remove"(owned who)end.
Definition decode_input j:=kind <- string_field "type"j;;
 if String.eqb kind "environment"then Some EnvironmentChanged else
 if String.eqb kind "value"then e <- decode_event j;;v <- field "value"j;;Some(ValueChanged e v)else
 if String.eqb kind "action"then e <- decode_event j;;Some(ActionClicked e)else
 if String.eqb kind "view"then e <- decode_event j;;c <- field "command"j;;c <- decode_view c;;Some(ViewChanged e c)else
 whoj <- field "owner"j;;who <- decode_owner whoj;;
 if String.eqb kind "source"then source <- string_field "source"j;;closed <- bool_field "closed"j;;e <- string_field "ending"j;;e <- decode_ending e;;external <- bool_field "external"j;;Some(SourceChanged who source closed e external)else
 if String.eqb kind "continue"then Some(Continue who)else
 if String.eqb kind "external"then allowed <- bool_field "allowed"j;;Some(ExternalChanged who allowed)else
 if String.eqb kind "feedback"then path <- string_field "path"j;;ticket <- natural_field "ticket"j;;ok <- bool_field "ok"j;;message <- string_field "message"j;;Some(Feedback who path ticket ok message)else
 if String.eqb kind "restore"then definition <- string_field "definition"j;;revision <- natural_field "revision"j;;present <- bool_field "present"j;;
   if present then payload <- string_field "payload"j;;Some(Restore who definition revision(Some payload))else Some(Restore who definition revision None)else
 if String.eqb kind "storage"then revision <- natural_field "revision"j;;ok <- bool_field "ok"j;;message <- string_field "message"j;;Some(StorageResult who revision ok message)else
 if String.eqb kind "source_disclosure"then Some(SourceDisclosure who)else
 if String.eqb kind "copy_definition"then Some(CopyDefinition who)else
 if String.eqb kind "remove"then Some(Remove who)else None.
Definition encode_effect value:=
 let pack name fields:=JObject(("type",JString name)::fields)in
 let owned who:=[("owner",encode_owner who)]in
 match value with
 | ParseMore who=>pack "interactive_parse"(owned who)
 | LoadSnapshot who storage_key definition revision=>pack "interactive_load"(owned who++[("storage_key",JString storage_key);("definition",JString definition);("revision",number revision)])
 | SaveSnapshot who storage_key revision payload=>pack "interactive_save"(owned who++[("storage_key",JString storage_key);("revision",number revision);("payload",payload);("settled",JBool true)])
 | RemoveSnapshot who storage_key=>pack "interactive_remove"(owned who++[("storage_key",JString storage_key)])
 | FillDraft who path text=>pack "fill_draft"(owned who++[("path",JString path);("text",JString text)])
 | SendMessage who path ticket text=>pack "send_message"(owned who++[("path",JString path);("ticket",number ticket);("message",JString text)])
 | WriteClipboard who path ticket text=>pack "interactive_clipboard"(owned who++[("path",JString path);("ticket",number ticket);("text",JString text)])
 | OpenUrl who path ticket url=>pack "interactive_open_url"(owned who++[("path",JString path);("ticket",number ticket);("url",JString url)])
 | RestoreFieldBuffer e value=>pack "restore_field_buffer"(event_fields e++[("key",JString(event_key e));("value",JString value)])end.
