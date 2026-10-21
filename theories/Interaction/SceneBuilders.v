From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema.
From Selvedge.Kernel Require Import Commands.
From Selvedge.Interaction Require Import Codec Identity Forms Input Scene.
Import ListNotations.
Open Scope string_scope.

Record ui_action := UiAction { action_input:option Input.input }.
Definition invoke i:=UiAction(Some i).
Inductive presentation_property := JsonProperty(value:json)|InputProperty(value:ui_action)|FieldProperty(value:field_spec)|KeyProperty(values:list(string*Input.input)).
Coercion JsonProperty : json >-> presentation_property.
Coercion InputProperty : ui_action >-> presentation_property.
Definition scene_data_key name:=match name with
|"label"=>Some Scene.Label|"value"=>Some Scene.Value|"attrs"=>Some Scene.Attributes|"disabled"=>Some Scene.Disabled|"checked"=>Some Scene.Checked|"multiline"=>Some Scene.Multiline|"options"=>Some Scene.Options|"help"=>Some Scene.Help|"invalid"=>Some Scene.Invalid|"role"=>Some Scene.Role|"value_kind"=>Some Scene.ValueKind|"url"=>Some Scene.Url|"complete"=>Some Scene.Complete|"origin"=>Some Scene.Origin|"document_key"=>Some Scene.DocumentKey|"epoch"=>Some Scene.Epoch|"revision"=>Some Scene.Revision|"ending"=>Some Scene.Ending|"appearance"=>Some Scene.Appearance|"layout"=>Some Scene.Layout|"target"=>Some Scene.Target|_=>None end.
Definition scene_property role '(name,value):list(Scene.property Input.input):=
 match value with
 |FieldProperty spec=>[Scene.Specification spec]
 |KeyProperty keys=>[Scene.KeyActions keys]
 |JsonProperty value=>match scene_data_key name with Some key=>[Scene.Data key value]|None=>[]end
 |InputProperty value=>match action_input value with None=>[]|Some input=>
   if String.eqb name "dismiss_action"then [Scene.Dismiss input]else
   if String.eqb name "file_action"then [Scene.Files input]else
   [Scene.Bind(match role with Scene.Field|Scene.Select|Scene.Checkbox=>Scene.Supply
      (match input with ServiceInput(Services.AddFile _ _)=>Scene.FileInjection|Input.Interactive _=>Scene.InteractiveValueInjection|_=>Scene.ValueInjection end)input
      |_=>Scene.Activate input end)]end end.
Definition node role key (props:list(string*presentation_property))(children:list(Scene.scene Input.input)):=
 Scene.make role key(flat_map(scene_property(proj1_sig role))props)children.
Definition text_node key text := node Scene.Text_role key[("value",JsonProperty(JString text))] [].
Definition heading key text := node Scene.Heading_role key[("label",JsonProperty(JString text))] [].
Definition group key children := node Scene.Group_role key [] children.
Definition command_action op props := UiAction(option_map Input.Command(decode_command command_specs(JObject(("op",JString op)::props)))).
Definition history_action task index:=UiAction(match natural task,natural index with Some task,Some index=>Some(Input.OpenHistoryMessage task index)|_,_=>None end).
Definition button key caption input disabled := Scene.ActionButton key[("label",JString caption)](action_input input)disabled[].
Definition icon_button key caption icon input disabled :=
 Scene.ActionButton key[("label",JString caption);("icon",JString icon)](action_input input)disabled[].
Definition navigation_action r := invoke(Input.Navigate r).
Definition editor_button key caption e := button key caption(invoke(Input.OpenEditor e key))false.
Definition edit_action e name := invoke(Input.Edit e name JNull None).

Definition feedback_scene d :=match status d with Editing=>[]|Accepted _=>[text_node(editor_key(owner d)++"/feedback")"Saved"]
|WorkspaceRejected reason=>[text_node(editor_key(owner d)++"/feedback")reason;button(editor_key(owner d)++"/workspace-retry")"重试工作区准备"(invoke(Input.RetryWorkspace(owner d)(editor_key(owner d)++"/workspace-retry")))false]
|Rejected reason=>[node Scene.Text_role(editor_key(owner d)++"/feedback")[("value",JsonProperty(JString reason));("attrs",JsonProperty(JObject[("role",JString "alert")]))][]]end.
