From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema.
From Selvedge.Kernel Require Import Commands.
From Selvedge.Interaction Require Import Codec Identity.
From Selvedge.Interaction.Session Require State.
From Selvedge.Interaction.Experience Require Model Activity.
From Selvedge.Interaction.Submission Require Fields Parameters.
Import ListNotations.
Open Scope string_scope.

Definition encode_property kind:=JString(match kind with
 |Model.ProjectProperty=>"project"|Model.WorkspaceProperty=>"workspace"|Model.PermissionsProperty=>"permissions"|Model.ModelProperty=>"model"|Model.DeliveryProperty=>"delivery"end).
Definition decode_property value:=match value with
 |JString "project"=>Some Model.ProjectProperty|JString "workspace"=>Some Model.WorkspaceProperty
 |JString "permissions"=>Some Model.PermissionsProperty|JString "model"=>Some Model.ModelProperty
 |JString "delivery"=>Some Model.DeliveryProperty|_=>None end.
Definition encode_request request:=match request with
 |Activity.PropertyActivity kind=>JObject[("kind",JString "property");("property",encode_property kind)]
 |Activity.SubjectActivity name=>JObject[("kind",JString "subject");("field",JString name)]
 |Activity.WorkspaceActivity=>JObject[("kind",JString "workspace")]end.
Definition decode_request value:=match string_field "kind" value with
 |Some "property"=>option_map Activity.PropertyActivity(bind(field "property" value)decode_property)
 |Some "subject"=>option_map Activity.SubjectActivity(string_field "field" value)
 |Some "workspace"=>Some Activity.WorkspaceActivity|_=>None end.
Definition encode_information panel:=match panel with
 |State.TaskDetails task=>JObject[("kind",JString "task_details");("task",number task)]
 |State.CardDetails card=>JObject[("kind",JString "card_details");("card",number card)]
 |State.TaskContext task=>JObject[("kind",JString "task_context");("task",number task)]
 |State.PropertySource owner request=>JObject[("kind",JString "property_source");("owner",encode_editor owner);("request",encode_request request)]end.
Definition decode_information value:=match string_field "kind" value with
 |Some "task_details"=>option_map State.TaskDetails(natural_field "task" value)
 |Some "card_details"=>option_map State.CardDetails(natural_field "card" value)
 |Some "task_context"=>option_map State.TaskContext(natural_field "task" value)
 |Some "property_source"=>owner<-bind(field "owner" value)decode_editor;;request<-bind(field "request" value)decode_request;;Some(State.PropertySource owner request)
 |_=>None end.
Definition encode_panel panel:=match panel with
 |State.PropertyPanel owner request=>JObject[("kind",JString "property");("owner",encode_editor owner);("request",encode_request request)]
 |State.EditorPanel owner=>JObject[("kind",JString "editor");("owner",encode_editor owner)]
 |State.SideConversationPanel task=>JObject[("kind",JString "side_conversation");("task",number task)]
 |State.BoardSettingsPanel=>JObject[("kind",JString "board_settings")]
 |State.BoardFiltersPanel=>JObject[("kind",JString "board_filters")]
 |State.ArchivedCardsPanel=>JObject[("kind",JString "archived_cards")]
 |State.NavigationPanel kind=>JObject[("kind",JString "navigation");("navigation",JString(navigation_panel_name kind))]
 |State.ObjectActionsPanel subject=>JObject[("kind",JString "actions");("subject",encode_menu_subject subject)]
 |State.InformationPanel kind=>JObject[("kind",JString "information");("information",encode_information kind)]
 |State.Confirmation command caption destination=>JObject[("kind",JString "confirmation");("command",Schema.encode_command command);("caption",JString caption);("destination",encode_route destination)]end.
Definition decode_panel value:=match string_field "kind" value with
 |Some "property"=>owner<-bind(field "owner" value)decode_editor;;request<-bind(field "request" value)decode_request;;Some(State.PropertyPanel owner request)
 |Some "editor"=>option_map State.EditorPanel(bind(field "owner" value)decode_editor)
 |Some "side_conversation"=>option_map State.SideConversationPanel(natural_field "task" value)
 |Some "board_settings"=>Some State.BoardSettingsPanel|Some "board_filters"=>Some State.BoardFiltersPanel|Some "archived_cards"=>Some State.ArchivedCardsPanel
 |Some "navigation"=>option_map State.NavigationPanel(bind(string_field "navigation" value)decode_navigation_panel)
 |Some "actions"=>option_map State.ObjectActionsPanel(bind(field "subject" value)decode_menu_subject)
 |Some "information"=>option_map State.InformationPanel(bind(field "information" value)decode_information)
 |Some "confirmation"=>command<-bind(field "command" value)(Schema.decode_command command_specs);;caption<-string_field "caption" value;;destination<-bind(field "destination" value)decode_route;;Some(State.Confirmation command caption destination)
 |_=>None end.
Definition encode_optional {A}(encode:A->json)(value:option A):json:=match value with Some value=>encode value|None=>JNull end.
Definition decode_optional {A}(decode:json->option A)(value:json):option(option A):=match value with JNull=>Some None|value=>option_map (@Some A)(decode value)end.
Definition encode_decision field:=JString(Parameters.name field).
Definition decode_decision panel value:=match panel with
 |State.PropertyPanel owner _|State.EditorPanel owner=>name<-as_string value;;Parameters.find_subject_field owner name
 |_=>None end.
Definition encode_layer layer:=JObject[("panel",encode_panel(State.layer_panel layer));
 ("trigger",JString(State.layer_trigger layer));("initial_attention",JString(State.layer_initial_attention layer));
 ("query",JString(State.layer_query layer));("occurrence",number(State.layer_occurrence layer));
 ("source_expanded",JBool(State.layer_source_expanded layer));
 ("decision_field",encode_optional encode_decision(State.layer_decision_field layer));
 ("parameter_buffer",encode_optional JString(State.layer_parameter_buffer layer));
 ("feedback",encode_optional(fun feedback=>feedback)(State.layer_feedback layer));("pending",JBool(State.layer_pending layer))].
Definition decode_layer value:=panel<-bind(field "panel" value)decode_panel;;trigger<-string_field "trigger" value;;initial<-string_field "initial_attention" value;;query<-string_field "query" value;;occurrence<-natural_field "occurrence" value;;source<-bool_field "source_expanded" value;;decision<-bind(field "decision_field" value)(decode_optional(decode_decision panel));;buffer<-bind(field "parameter_buffer" value)(decode_optional as_string);;feedback<-bind(field "feedback" value)(decode_optional(fun feedback=>Some feedback));;pending<-bool_field "pending" value;;Some(State.Layer panel trigger initial query occurrence source decision buffer feedback pending).
Definition encode_visibility visibility:=JString(match visibility with State.AutomaticNavigation=>"automatic"|State.OpenNavigation=>"open"|State.ClosedNavigation=>"closed"end).
Definition decode_visibility value:=match value with JString "automatic"=>Some State.AutomaticNavigation|JString "open"=>Some State.OpenNavigation|JString "closed"=>Some State.ClosedNavigation|_=>None end.
Definition encode_visit value:=JObject[("work",optional_id(fst value));("route",encode_route(snd value))].
Definition decode_visit value:=work<-bind(field "work" value)decode_id;;route<-bind(field "route" value)decode_route;;Some(work,route).
Definition encode_navigation value:=JObject[("location",encode_route(State.location value));
 ("work",optional_id(State.active_work value));("visits",JArray(map encode_visit(State.visits value)));
 ("visibility",encode_visibility(State.navigation_intent value));
 ("desktop_task_list_visible",JBool(State.desktop_task_list_visible value));
 ("generation",number(State.generation value));
 ("layers",JArray(map encode_layer(State.layers value)))].
Definition decode_navigation value:=location<-bind(field "location" value)decode_route;;work<-bind(field "work" value)decode_id;;visits<-list_field decode_visit "visits" value;;visibility<-bind(field "visibility" value)decode_visibility;;desktop_visible<-bool_field "desktop_task_list_visible" value;;generation<-natural_field "generation" value;;layers<-list_field decode_layer "layers" value;;Some(State.Navigation location work visits visibility desktop_visible generation layers).
Definition encode_reading intent:=JString(match intent with State.FollowingLatest=>"follow"|State.ReadingHistory=>"history"end).
Definition decode_reading value:=match value with JString "follow"=>Some State.FollowingLatest|JString "history"=>Some State.ReadingHistory|_=>None end.
Definition encode_disclosure disclosure:=let '(group,occurrence,expanded):=disclosure in JObject[("group",number group);("occurrence",number occurrence);("expanded",JBool expanded)].
Definition decode_disclosure value:=group<-natural_field "group" value;;occurrence<-natural_field "occurrence" value;;expanded<-bool_field "expanded" value;;Some(group,occurrence,expanded).
Definition encode_reader value:=JObject[("task",number(State.reading_task value));("generation",number(State.reader_generation value));("position",encode_reading(State.reader_position value));("disclosures",JArray(map encode_disclosure(State.disclosures value)))].
Definition decode_reader value:=task<-natural_field "task" value;;generation<-natural_field "generation" value;;position<-bind(field "position" value)decode_reading;;disclosures<-list_field decode_disclosure "disclosures" value;;Some(State.Reader task generation position disclosures).
