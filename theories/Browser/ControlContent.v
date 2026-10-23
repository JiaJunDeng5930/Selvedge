From Stdlib Require Import String List Bool Arith NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Interaction Require Identity.
From Selvedge.Features Require Domain BoardFilter.
From Selvedge.Interaction.Experience Require Model.
From Selvedge.Interaction.Presentation Require Surface Roles Information.
From Selvedge.Browser Require Import DOM Layout Typography Appearance ControlPurpose.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Module S := Selvedge.Interaction.Presentation.Surface.
Module PM := Selvedge.Interaction.Presentation.Model.
Module UX := Selvedge.Interaction.Experience.Model.
Module C := Selvedge.Browser.ControlPurpose.

Definition private_key key name :=
  Identity.key_part key (String.append "@native/" name).
Definition empty := JObject [].
Definition flag (value : bool) := if value then "true" else "false".
Definition box key tag attributes properties children :=
  DOM.Element key tag attributes properties [] empty children.
Definition span key attributes properties text :=
  box key "span" (("id",key)::attributes) properties [DOM.Text text].
Definition scaled env n := Typography.scaled (Layout.root_font_size_milli env) n.
Definition pixels env n := Typography.px (scaled env n).
Definition inline_properties : list (string * string) :=
  [("display","inline-flex");("flex-direction","row");("align-items","baseline");
   ("font","inherit");("line-height","inherit");("white-space","nowrap")].
Definition single_line_attributes text :=
  [("title",text);("data-native-minimum-inline","1ch")].
Definition single_line_properties : list (string * string) :=
  [("display","block");("min-inline-size","1ch");("overflow","hidden");
   ("text-overflow","ellipsis");("white-space","nowrap")].

Inductive supporting_form := FullSupporting | CompactSupporting.
Record supporting_layout := SupportingLayout {
  supporting_representation : supporting_form;
  supporting_direction : Layout.native_direction
}.
Definition form_name value := match value with
  FullSupporting => "full" | CompactSupporting => "compact" end.
Definition board_group_attributes grouping :=
  let '(name,label):=match grouping with
  |S.ViewChoices=>("view-choices","看板视图")|S.SearchArea=>("search","任务搜索")
  |S.WorkStatus=>("work-status","当前工作状态")
  |S.SecondaryActions=>("secondary-actions","看板筛选和设置")
  |S.PrimaryAction=>("primary-action","主要操作")end in
  [("data-board-group",name);("aria-label",label)].
Definition choose_supporting available full_preferred compact_minimum :=
  if Nat.leb full_preferred available
  then SupportingLayout FullSupporting Layout.Horizontal
  else SupportingLayout CompactSupporting (Layout.row_flow available compact_minimum).

Definition support_row {A} (children : list (S.node A)) :=
  existsb (fun child => match S.node_meaning child with
    S.SupportingControl _ _ _ _ => true | _ => false end) children.
Definition support_row_attributes key :=
  [("data-native-responsive-row",key);("data-native-supporting-row",key);
   ("data-allocated-region","supporting-controls");("data-supporting-form","full")].
(* The slot receives its parent's residual width independently of text demand.
   Measuring its full form must not resize the available-width denominator. *)
Definition support_row_properties : list (string * string) :=
  [("display","flex");("flex-direction","row");("flex-wrap","nowrap");("align-items","flex-start");
   ("flex","1 1 0%");("min-inline-size","0");("justify-content","flex-start")].

Definition property_icon {e} (property : UX.property e) :=
  match UX.property_kind_of property with
  | UX.ProjectProperty => Some "archive-box"
  | UX.WorkspaceProperty => Some "folder"
  | UX.PermissionsProperty => Some "shield"
  | UX.ModelProperty => None
  | UX.DeliveryProperty => Some "arrow-up"
  end.
Definition stage_filter_glyph (stage : Domain.board_stage) :=
  match stage with
  | Domain.Backlog => "status-backlog"
  | Domain.Todo => "status-todo"
  | Domain.InProgress => "status-in-progress"
  | Domain.InReview => "status-in-review"
  | Domain.Completed => "status-completed"
  | Domain.Blocked => "status-blocked"
  end.
Definition priority_filter_glyph (priority : Domain.priority) :=
  match priority with
  | Domain.NoPriority => "priority-no-priority"
  | Domain.Low => "priority-low"
  | Domain.Medium => "priority-medium"
  | Domain.High => "priority-high"
  | Domain.Urgent => "priority-urgent"
  end.
Definition board_filter_glyph (category : BoardFilter.category) (value : string)
    : option string :=
  match category with
  | BoardFilter.Status => option_map stage_filter_glyph
      (find (fun stage => String.eqb value (Domain.stage_name stage)) Domain.stages)
  | BoardFilter.Priority => option_map priority_filter_glyph
      (find (fun priority => String.eqb value (Domain.priority_name priority)) Domain.priorities)
  | BoardFilter.Date => Some "clock"
  | BoardFilter.Assignee => Some (if String.prefix "agent/" value then "bot" else "user")
  | BoardFilter.Creator => Some "user"
  | BoardFilter.Project => Some "folder"
  | BoardFilter.Label => Some "tag"
  end.
Definition summary_subject {e} (property : UX.property e) (secondary : bool) :=
  match UX.property_information property with
  | UX.PresentInformation principal supporting =>
      if secondary then match supporting with
        Some value => UX.subject_name (UX.summary_subject value)
        | None => UX.subject_name (UX.property_subject property) end
      else UX.subject_name (UX.summary_subject principal)
  | _ => UX.subject_name (UX.property_subject property)
  end.
Definition summary_member {A e} (property : UX.property e) (child : S.node A)
    : list DOM.node :=
  let key := S.node_key child in
  let text := S.node_label child in
  match S.node_meaning child with
  | S.InformationText Information.FieldValue =>
      [span key [("data-summary-role","principal");
        ("data-summary-subject",summary_subject property false);
        ("title",text)]
        inline_properties text]
  | S.InformationText Information.Description =>
      [span key [("data-summary-role","secondary");
        ("data-summary-subject",summary_subject property true);
        ("data-support-secondary","true")]
        (inline_properties ++ [("color",Appearance.secondary_text)])
        (String.append "· " text)]
  | _ => []
  end.
Definition setting_member {A e} (property : UX.property e) (child : S.node A)
    : list DOM.node :=
  let key := S.node_key child in
  let subject := UX.subject_name (UX.property_subject property) in
  match S.node_meaning child with
  | S.InformationText Information.FieldLabel =>
      [span key [("data-setting-role","label");("data-setting-subject",subject);
         ("title",S.node_label child);("data-native-minimum-inline","1ch")]
       (inline_properties ++ [("flex","1 1 0%");("min-inline-size","0");
         ("display","block");("min-inline-size","1ch");
         ("text-align","start");("overflow","hidden");("text-overflow","ellipsis")])
       (S.node_label child)]
  | S.InformationText Information.FieldValue =>
      [span key [("data-setting-role","value");("data-setting-subject",subject);
         ("title",S.node_label child);("data-native-minimum-inline","1ch")]
       (inline_properties ++ [("display","block");("flex","0 1 auto");("min-inline-size","1ch");
         ("overflow","hidden");("text-overflow","ellipsis");("color",Appearance.secondary_text);
         ("text-align","end")]) (S.node_label child)]
  | _ => []
  end.
Definition face_content {A} env key (artwork : string -> list DOM.node)
    (meaning : S.meaning A) (children : list (S.node A)) : option (list DOM.node) :=
  match meaning with
  | S.SettingEntry _ property _ =>
      Some (flat_map (setting_member property) children ++ artwork "chevron-right")
  | S.SupportingControl _ _ property _ =>
      Some ((match property_icon property with Some icon => artwork icon | None => [] end) ++
        [box (private_key key "property-value") "span" [("data-property-summary","true")]
         (inline_properties ++ [("gap",pixels env 3);("min-inline-size","max-content");("flex","1 1 auto")])
         (flat_map (summary_member property) children)] ++ artwork "chevron-down")
  | _ => None
  end.

Definition add_properties properties value :=
  match value with
  | DOM.Element key tag attributes existing events metadata children =>
      DOM.Element key tag attributes (existing ++ properties) events metadata children
  | _ => value
  end.
Definition replace_content attributes properties children value :=
  match value with
  | DOM.Element key tag existing style events metadata _ =>
      DOM.Element key tag (existing ++ attributes) (style ++ properties) events metadata children
  | _ => value
  end.
Fixpoint find_native key (value : DOM.node) : option DOM.node :=
  match value with
  | DOM.Element identity _ _ _ _ _ children =>
      if String.eqb key identity then Some value else
      (fix find_children (values : list DOM.node) : option DOM.node :=
        match values with
        | [] => None
        | child :: rest => match find_native key child with
          | Some found => Some found | None => find_children rest end
        end) children
  | DOM.Mount _ children =>
      (fix find_children (values : list DOM.node) : option DOM.node :=
        match values with
        | [] => None
        | child :: rest => match find_native key child with
          | Some found => Some found | None => find_children rest end
        end) children
  | _ => None
  end.
Definition native_for key values :=
  (fix find (values : list DOM.node) : list DOM.node :=
    match values with
    | [] => []
    | value :: rest => match find_native key value with
      | Some found => [found] | None => find rest end
    end) values.
Fixpoint selected_keys {A} (select : S.node A -> bool) (value : S.node A) : list string :=
  if select value then [S.node_key value]
  else flat_map (selected_keys select) (S.node_children value).
Definition native_selected {A} (select : S.node A -> bool)
    (children : list (S.node A)) native :=
  flat_map (fun key => native_for key native) (flat_map (selected_keys select) children).
Definition has_selected {A} (select : S.node A -> bool) (value : S.node A) :=
  negb (Nat.eqb (length (selected_keys select value)) 0).
Definition action_purpose {A} (describe : A -> C.purpose) (value : S.node A) :=
  match S.node_meaning value with
  | S.Activate action => Some (describe (PM.control_input action))
  | _ => None end.
Definition create_action {A} describe (value : S.node A) :=
  match action_purpose describe value with Some C.CreateItem => true | _ => false end.
Definition project_disclosure {A} describe project (value : S.node A) :=
  match action_purpose describe value with
  | Some (C.ProjectDisclosure actual) => N.eqb project actual | _ => false end.
Definition project_title {A} (value : S.node A) :=
  match S.node_role value with Roles.NavigationEntry _ => true | _ => false end.
Fixpoint project_titles {A} (value : S.node A) : list (string * string) :=
  if project_title value then [(S.node_key value,S.node_label value)]
  else flat_map project_titles (S.node_children value).
Definition project_auxiliary {A} describe (value : S.node A) :=
  match S.node_role value with
  | Roles.NavigationEntry _ => false
  | _ => match action_purpose describe value with
    | Some C.ProjectTaskCreation | Some (C.MoreActions _) => true | _ => false end
  end.
Definition open_menu {A} describe (value : S.node A) :=
  match action_purpose describe value with
  | Some (C.MoreActions expanded) => expanded | _ => false end.
Definition navigation_target env :=
  Nat.max (Layout.motor_minimum env)
    (Typography.line_height (Layout.root_font_size_milli env) Typography.ActivityPrimary).
Definition navigation_rail env := scaled env 20.
Definition navigation_following env :=
  let allocation := Nat.max (navigation_rail env) (navigation_target env) in
  let before := (allocation - navigation_rail env) / 2 in
  scaled env 8 - (allocation - navigation_rail env - before).
Definition project_header {A} describe env key project selected expanded
    (artwork : string -> list DOM.node) (children : list (S.node A)) native :=
  let target := navigation_target env in
  let target_style := [("inline-size",Typography.px target);
    ("min-block-size",Typography.px target);("max-inline-size","none");
    ("padding","0");("flex","none");("justify-content","center")] in
  let toggle := map (replace_content [("aria-expanded",flag expanded)]
    target_style (artwork (if expanded then "chevron-down" else "chevron-right")))
    (native_selected (project_disclosure describe project) children native) in
  let title := flat_map (fun entry =>
    map (replace_content [("data-navigation-slot","title")]
      [("flex","1 1 auto");("min-inline-size","0");("padding-inline","0");
       ("text-align","start");("white-space","nowrap")]
      [span (private_key (fst entry) "caption") [("title",snd entry)]
        [("flex","1 1 auto");("min-inline-size","0");("white-space","nowrap");
         ("overflow","hidden");("text-overflow","ellipsis")] (snd entry)]) (native_for (fst entry) native))
    (flat_map project_titles children) in
  let auxiliary := map (add_properties target_style)
    (native_selected (project_auxiliary describe) children native) in
  let menu_open := existsb (has_selected (open_menu describe)) children in
  box (private_key key "project-header") "div"
    [("data-navigation-owner",key);("data-navigation-active",flag (selected || menu_open));
     ("data-navigation-selected",flag selected);("data-navigation-feedback",flag menu_open)]
    (Appearance.navigation_feedback_properties selected ++
    Layout.row_properties Layout.Horizontal ++
    [
     ("min-block-size",Typography.px target);("min-inline-size","0");
     ("gap",Typography.px (navigation_following env))])
    ([box (private_key key "disclosure-slot") "div" [("data-navigation-slot","disclosure")]
      [("display","flex");("align-items","center");("justify-content","center");
       ("inline-size",Typography.px (Nat.max (navigation_rail env) target));("flex","none")]
      toggle] ++ title ++
    [box (private_key key "auxiliary-slot") "div" [("data-navigation-slot","auxiliary")]
      [("display","flex");("flex-direction","row");("align-items","center");
       ("inline-size",Typography.px (2 * target + scaled env 8));
       ("gap",pixels env 8);("flex","none")] auxiliary]).

Definition lane_content {A} describe env key label stage count
    (children : list (S.node A)) native :=
  let paired := combine children native in
  let header_actions := map snd (filter (fun pair => create_action describe (fst pair)) paired) in
  let cards := map snd (filter (fun pair =>
    match S.node_meaning (fst pair) with
    | S.InformationText Information.GroupTitle => false
    | _ => negb (create_action describe (fst pair)) end) paired) in
  let text_style strength := Typography.properties (Layout.root_font_size_milli env)
    Typography.Support strength in
  [box (private_key key "lane-heading") "header" [("data-board-lane-heading","true")]
    [("display","flex");("align-items","center");("gap",pixels env 12);("flex","none")]
    [box (private_key key "lane-heading-leading") "div" []
      [("display","flex");("align-items","center");("flex","1 1 0%");
       ("min-inline-size","0");("gap",pixels env 12)]
      [box (private_key key "stage-mark") "span"
        [("data-board-stage-mark",stage);("aria-hidden","true")] [] [];
       span (private_key key "lane-title") [] (text_style Typography.Medium) label;
       span (private_key key "lane-count") [("data-board-count",show_natural count)]
         (text_style Typography.Regular) (show_natural count)];
     box (private_key key "lane-heading-trailing") "div" []
      [("display","flex");("align-items","center");("flex","none")] header_actions];
   box (private_key key "lane-cards") "div" [("data-board-cards","true")]
    [("display","flex");("flex-direction","column");("gap",pixels env 12);
     ("flex","1 1 0%");("min-block-size","0");("overflow-y","auto")]
    ((if N.eqb count 0 then
      [box (private_key key "lane-empty") "p" [("data-board-empty","true")]
        (text_style Typography.Regular) [DOM.Text "暂无任务"]] else []) ++ cards)].

Definition collection_children (env : Layout.environment) key (children : list DOM.node) :=
  match children with
  | [] => []
  | header :: [] => [header]
  | header :: members => [header;
      box (private_key key "navigation-members") "div" [("data-navigation-members",key)]
      [("display","flex");("flex-direction","column");("min-inline-size","0");
       ("gap","0")] members]
  end.
Definition role_content env key (role : Roles.role) (native : list DOM.node)
    : option (list DOM.node) :=
  match role with
  | Roles.NavigationSection => Some (collection_children env key native)
  | Roles.WorkChoiceRow => Some (map (add_properties
      [("flex","1 1 0%");("min-inline-size","0")]) native)
  | _ => None
  end.
Definition board_filter_choice_content artwork label category value native :=
  match board_filter_glyph category value with
  | Some symbol => Some (artwork symbol ++
      match native with [] => [DOM.Text label] | _ => native end)
  | None => None
  end.
Definition node_properties {A} env (activity:bool) (role : Roles.role) (meaning : S.meaning A)
    : list (string * string) :=
  (match role with
  | Roles.WorkChoiceRow => [("display","flex");("flex-direction","row");
      ("flex-wrap","nowrap");("gap",pixels env 12);("inline-size","100%")]
  | Roles.NavigationCollection => [("display","flex");("flex-direction","column");
      ("gap",match meaning with S.TaskChildren _=>"0"|_=>Typography.px (Layout.heading_gap (Layout.hierarchy_for env true))end)]
  | Roles.NavigationSection => [("display","flex");("flex-direction","column");("gap","0")]
  | _ => [] end) ++
  match meaning with
  | S.BoardLane _ _ => let width := Typography.px (Layout.lane_minimum_width (Layout.parameters env)) in
      [("inline-size",width);("min-inline-size",width);("max-inline-size",width);
       ("block-size","100%");("min-block-size","0");("flex","none");("overflow","hidden")]
  | S.WorkChoice _ _ _ => [("flex","1 1 0%");("min-inline-size","0");
      ("min-block-size",pixels env 120);("white-space","nowrap")]
  | S.SettingEntry _ _ _ => [("inline-size","100%");("text-align","start")]
  | S.SupportingControl _ _ _ _ => [("flex","0 1 auto");("white-space","nowrap");
      ("justify-content","flex-start");("gap",pixels env (if activity then 8 else 6))]
  | _ => [] end.

Definition container_content {A} (describe : A -> C.purpose)
    (artwork : string -> list DOM.node) env key label (role : Roles.role)
    (meaning : S.meaning A) (children : list (S.node A)) native : option (list DOM.node) :=
  match meaning with
  | S.BoardLane stage count => Some (lane_content describe env key label stage count children native)
  | S.ProjectGroup project selected expanded =>
      let paired := combine children native in
      let members := map snd (filter (fun pair =>
        negb (has_selected (project_disclosure describe project) (fst pair))) paired) in
      Some ([project_header describe env key project selected expanded artwork children native] ++
        match members with
        | [] => []
        | _ => [add_properties [("gap","0")] (box (private_key key "project-members") "div"
          [("data-navigation-members",key)]
          (Layout.member_properties env true true) members)] end)
  | S.Choice _ _ _ action =>
      match describe (PM.control_input action) with
      | C.BoardFilterChoice category value =>
          match board_filter_choice_content artwork label category value native with
          | Some content => Some content
          | None => role_content env key role native
          end
      | _ => role_content env key role native
      end
  | _ => role_content env key role native
  end.
