From Stdlib Require Import String List Bool Arith NArith.
From Selvedge.Browser Require Import Appearance Typography Layout ControlPurpose.
From Selvedge.Programming.Presentation Require Import Model.
From Selvedge.Interaction.Presentation Require Import Roles Information Composition.
From Selvedge.Programming.Presentation Require Import Surface.
From Selvedge.Interaction.Submission Require Fields.
From Selvedge.Interaction.Interactive Require Expand Vocabulary Presentation.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Module UX := Selvedge.Interaction.Experience.Model.
Definition scaled env := Typography.scaled (Layout.root_font_size_milli env).
Definition pixels env value := Typography.px (scaled env value).
Definition row env := [("display","flex"); ("flex-direction","row"); ("align-items","center"); ("justify-content","flex-start");
  ("padding-inline",pixels env 8); ("padding-block","0"); ("gap",pixels env 8);
  ("min-block-size",Typography.px (Layout.motor_minimum env))].
Definition embedded (env : Layout.environment) : list (string * string) := [("background","transparent"); ("border-width","0");
  ("--control-rest-background","transparent"); ("--control-hover-background","transparent");
  ("--control-pressed-background","transparent")].
Definition compact_control env := embedded env ++ row env ++
  [("border-radius",pixels env 6); ("white-space","nowrap")].
Definition single_line env := embedded env ++ [("display","block"); ("padding","0");
  ("overflow","hidden"); ("text-overflow","ellipsis"); ("white-space","nowrap")].
Definition member_properties env (activity : bool) : list (string * string) :=
  if activity then row env else [("display","flex"); ("flex-direction","column"); ("gap","8px")].

(** Responsive rows are product relationships, including rows whose container
    style comes from its source family. A button's internal icon/text arrangement
    stays horizontal; it is the enclosing row that changes direction. *)
Definition responsive_role role := match role with
  | Roles.CompactHeader => false
  | _ => match Appearance.style_flow (Appearance.role_style role) with
      | Appearance.RowFlow | Appearance.SplitRowFlow => true | _ => false end
  end.
Definition responsive_row {Action} activity (source : Surface.meaning Action)
    (role : Roles.role) (meaning : Surface.meaning Action) :=
  match meaning with
  | Surface.Activate _ | Surface.ActionCommit _ _ _ | Surface.Choice _ _ _ _
  | Surface.WorkChoice _ _ _ | Surface.SettingEntry _ _ _
  | Surface.SupportingControl _ _ _ _ | Surface.PanelToggle _ _
  | Surface.SkillSuggestion _ _ | Surface.ProjectChooser _
  | Surface.InformationText _ | Surface.Fact _ | Surface.ReadOnly _
  | Surface.Edit _ _ _ | Surface.RichText _ _ | Surface.PublishedText _
  | Surface.EmbeddedMarkdown _ => false
  | Surface.TaskRow _ _ _ _ _ => false
  | Surface.ActivityRow _ => false
  | Surface.DirectoryRow _ _ | Surface.WorkspaceMember _ _ _ => activity
  | Surface.BoardGroup _ => false
  | Surface.PageRegion Composition.ConversationHeader _
  | Surface.PageRegion Composition.BoardControls _ => true
  | Surface.PageRegion Composition.CreationContext _ => false
  | Surface.InteractiveNode component =>
      String.eqb (Vocabulary.component_tag (Expand.description (Presentation.component_properties component))) "row-layout"
  | Surface.PageRegion Composition.TaskActions _ => false
  | Surface.Region =>
      match source,role with Surface.ProjectGroup _ _ _,Roles.Section => false | _,_ =>
        responsive_role role end
  | _ => responsive_role role
  end.
Definition action_properties env (activity : bool) : list (string * string) :=
  (if activity then Layout.heading_properties env true else
    [("display","flex"); ("flex-direction","column"); ("padding","12px"); ("gap","12px")]).
Definition surface_maximum_width env := Nat.max (scaled env 200)
  (Layout.activity_primary_advance (Layout.parameters env) * 56 + scaled env 16).
Definition surface_properties env : list (string * string) :=
  let width := surface_maximum_width env in
  [("min-inline-size",pixels env 200);
   ("inline-size","fit-content");
   ("max-inline-size",String.append "min(100%," (String.append (Typography.px width) ")"))].
Definition description_properties env : list (string * string) :=
  [("max-inline-size",Typography.px (Layout.activity_support_advance (Layout.parameters env) * 38))].
Definition member_width_properties env : list (string * string) :=
  [("max-inline-size",Typography.px (Layout.activity_primary_advance (Layout.parameters env) * 44))].
Definition field_width_properties env : list (string * string) :=
  let advance := Layout.activity_primary_advance (Layout.parameters env) in
  [("inline-size","auto");
   ("min-inline-size",Typography.px (advance * 32));
   ("max-inline-size",String.append "min(100%,"
     (String.append (Typography.px (advance * 64)) ")"));
   ("field-sizing","content");("align-self","flex-start")].
Definition supporting_properties env :=
  Typography.properties (Layout.root_font_size_milli env) Typography.ActivitySupport Typography.Regular ++
  [("color","inherit")].
Definition toggle_properties (env : Layout.environment) :=
  [("inline-size","16px"); ("block-size","16px"); ("min-block-size","16px");
   ("padding","0"); ("align-self","center"); ("border-radius","3px")].
Definition editor_properties {Action} env (activity : bool) (value : Surface.meaning Action) : list (string * string) :=
  match value with
  | Surface.Edit _ subject control =>
      if ControlPurpose.toggle_widget (UX.subject_declaration subject)(Model.editing_observation control)
      then toggle_properties env else
      if match Model.editing_entry control with Fields.DisplayOnly => true | _ => false end
      then embedded env else
      match UX.subject_declaration subject, Model.editing_observation control with
      | Fields.MessageText, _ => embedded env ++
          [("padding","0"); ("border-radius",pixels env 8); ("resize","none"); ("inline-size","100%");
           ("max-block-size",Typography.px (Layout.input_maximum_height (Layout.parameters env)))]
      | Fields.CardTitle, _ => [("border-width","0")]
      | Fields.CardDescription, _ => [("border-width","0"); ("min-block-size","110px")]
      | _, _ => [] end
  | Surface.HistorySearchQuery _ _ _ | Surface.BoardSearch _ _ =>
      [("background",Appearance.background Appearance.InsetPaint Appearance.Rest);
       ("padding-inline","8px"); ("padding-block","4px"); ("border-radius","6px")]
  | _ => [] end.

(** The meaning selects product relationships before native element construction. *)
Definition meaning_properties {Action} env activity (value : Surface.meaning Action)
    : list (string * string) :=
  (match value with
  | Surface.InformationText role => Appearance.information_properties env activity role ++
      match role with
      | Information.NavigationCaption => [("padding-inline",pixels env 8);("display","block");
          ("overflow","hidden");("text-overflow","ellipsis");("white-space","nowrap")]
      | Information.Description => if activity then description_properties env else []
      | _ => [] end
  | Surface.PageRegion region position => Layout.region_properties env region position
  | Surface.PageContext _ =>
      [("flex","1 1 auto");("min-block-size","0");("overflow","hidden")]
  | Surface.ReadingTimeline _ _ =>
      [("flex","1 1 auto");("min-block-size","0");("overflow-y","auto");("overflow-x","hidden")]
  | Surface.ProjectGroup _ _ _ => [("display","flex"); ("flex-direction","column"); ("gap","0")]
  | Surface.TaskRow _ _ _ _ selected =>
      Appearance.style_properties env (Appearance.navigation_style selected 6 0)
  | Surface.TaskChildren _ => Layout.member_properties env false true
  | Surface.ProjectChooser _ => [("display","flex"); ("flex-direction","row"); ("align-items","center"); ("gap","0"); ("padding","0")]
  | Surface.ActivityGroup _ _ _ _ => surface_properties env ++
      [("padding",pixels env 8); ("gap",pixels env 4)]
  | Surface.LayerRegion behavior =>
      match Model.layer_presentation behavior with Model.AnchoredMenu => surface_properties env | _ => [] end
  | Surface.ContextSummary _ => [("display","flex"); ("flex-direction","column"); ("gap","4px"); ("padding-inline","8px")]
  | Surface.DirectoryRow _ _ | Surface.WorkspaceMember _ _ _ => member_properties env activity
  | Surface.ChoiceGroup | Surface.DecisionGroup _ _ | Surface.WorkspaceCollection _ _ =>
      Layout.heading_properties env activity
  | Surface.Choice _ selected description _ =>
      Appearance.style_properties env (Appearance.navigation_style selected 8 6) ++
      [("align-items","flex-start"); ("justify-content","flex-start"); ("white-space","normal"); ("padding-block",pixels env 8)]
  | Surface.WorkChoice _ selected _ =>
      Appearance.style_properties env (Appearance.fields (Appearance.ChoicePaint selected)
        (Appearance.token (if selected then "--color-token-focus-border" else "--color-token-border-default"))
        1 10 false Appearance.Leading Appearance.RowFlow Appearance.ContentFlow 12 12 8 120 100 true false) ++ [("justify-content","flex-start")]
  | Surface.ActionUnit _ _ => action_properties env activity
  | Surface.ObjectGroup _ => Layout.heading_properties env activity
  | Surface.ActivityRow row =>
      Layout.row_properties (match row with
        | Surface.MemberRow | Surface.ObjectHeading | Surface.NavigationRow | Surface.TerminalRow => Layout.Horizontal
        | _ => Layout.Vertical end) ++
      [("padding","0");("gap",pixels env 8);("overflow","hidden");
       ("min-block-size",Typography.px (Layout.motor_minimum env));("align-items","center");
       ("justify-content",match row with Surface.TerminalRow => "flex-end" | _ => "flex-start" end)] ++
      (match row with Surface.SupportingRow => description_properties env ++ supporting_properties env | _ => [] end)
  | Surface.SettingEntry _ _ _ | Surface.SupportingControl _ _ _ _ => compact_control env
  | Surface.BoardLane _ _ => [("background",Appearance.token "--color-surface-secondary");
      ("padding","8px"); ("min-inline-size",Typography.px (Layout.lane_minimum_width (Layout.parameters env)))]
  | Surface.BoardGroup _ => [("display","flex");("flex-direction","row");
      ("flex-wrap","nowrap");("flex","1 1 0%");("min-inline-size","min-content")]
  | Surface.ActionFeedback _ _ _ | Surface.ActionExplanation _ _ =>
      Appearance.information_properties env activity Information.Description
  | Surface.ReadOnly _ | Surface.Fact _ => [("overflow-wrap","anywhere");("color","inherit")]
  | _ => [] end) ++ editor_properties env activity value ++
  if activity then match value with
  | Surface.SearchChoices _ _ => field_width_properties env ++
      [("padding-inline",pixels env 8);("padding-block","0");("gap",pixels env 8);
       ("min-block-size",Typography.px (Layout.motor_minimum env));("border-radius",pixels env 6)]
  | Surface.Edit _ subject control =>
      if ControlPurpose.toggle_widget (UX.subject_declaration subject) (Model.editing_observation control)
      then [] else (match UX.subject_declaration subject with Fields.MessageText=>[]|_=>field_width_properties env end) ++
        [("padding-inline",pixels env 8);("padding-block","0");("gap",pixels env 8);
         ("min-block-size",Typography.px (Layout.motor_minimum env)); ("border-radius",pixels env 6)]
  | _ => [] end else [].

(** A source context is propagated as a typed meaning, never recovered from a DOM key. *)
Definition source_properties {Action} env (source current : Surface.meaning Action)
    : list (string * string) :=
  match source,current with
  | Surface.ActivityRow Surface.NavigationRow,Surface.InformationText _ =>
      [("white-space","nowrap");("flex","0 1 auto");("min-inline-size","0")]
  | Surface.PageRegion Composition.CreationIntroduction _,Surface.InformationText _ =>
      [("text-align","center");("inline-size","100%");("align-self","center")]
  | Surface.PageRegion Composition.ConversationTitle _,Surface.InformationText _ =>
      Typography.properties (Layout.root_font_size_milli env) Typography.Section Typography.Medium ++
      [("display","block");("min-inline-size","1ch");("overflow","hidden");
       ("text-overflow","ellipsis");("white-space","nowrap")]
  | Surface.Choice _ _ _ _,Surface.InformationText Information.Description => description_properties env
  | Surface.WorkChoice _ _ _,Surface.InformationText _ =>
      [("display","block");("min-inline-size","1ch");("overflow","hidden");
       ("text-overflow","ellipsis");("white-space","nowrap")]
  | Surface.TaskRow _ _ _ _ selected, Surface.Activate _ =>
      Appearance.style_properties env (Appearance.navigation_style selected 6 0) ++
      [("flex","1");("text-align","left");("white-space","nowrap");
       ("min-inline-size",Typography.px (Layout.motor_minimum env))]
  | Surface.SkillSuggestion _ _, Surface.InformationText Information.OptionLabel =>
      [("font-size","14px");("font-weight","700")]
  | Surface.SkillSuggestion _ _, Surface.InformationText Information.Description =>
      [("font-size","12px");("overflow","hidden");("text-overflow","ellipsis");
       ("white-space","nowrap");("max-inline-size","100%")]
  | Surface.SkillSuggestion _ _, Surface.InformationText Information.FieldValue =>
      [("font-size","11px");("color",Appearance.secondary_text);("overflow-wrap","anywhere")]
  | Surface.SkillSuggestions _ _ _, Surface.InformationText Information.Status =>
      [("padding","10px 12px");("font-size","13px")]
  | Surface.DirectoryRow _ _, Surface.InformationText Information.FieldValue
  | Surface.WorkspaceMember _ _ _, Surface.Region
  | Surface.WorkspaceMember _ _ _, Surface.Fact _ =>
      member_width_properties env ++ [("inline-size","fit-content")]
  | Surface.ProjectGroup _ selected _, Surface.Region =>
      Appearance.style_properties env (Appearance.navigation_style selected 0 0)
  | Surface.ProjectGroup _ _ _, Surface.Activate _ => single_line env
  | Surface.ProjectChooser _, Surface.Activate _ => compact_control env ++
      [("padding-inline","0"); ("padding-block",pixels env 4); ("gap",pixels env 4)]
  | Surface.ProjectGroup _ _ _, Surface.InformationText Information.GroupTitle =>
      Typography.properties (Layout.root_font_size_milli env) Typography.ActivityPrimary Typography.Strong
  | Surface.LayerRegion behavior, Surface.ActionUnit _ _
  | Surface.NavigationRegion _ behavior, Surface.ActionUnit _ _
  | Surface.ActivityGroup _ _ _ behavior, Surface.ActionUnit _ _ =>
      if Model.modal_layer behavior then
        [("display","flex"); ("flex-direction","column"); ("overflow","hidden");
         ("flex","1 1 auto"); ("min-inline-size","0"); ("min-block-size","0");
         ("padding","0"); ("gap","0")]
      else []
  | Surface.ActivityRow Surface.SupportingRow, Surface.InformationText role =>
      Typography.properties (Layout.root_font_size_milli env) Typography.ActivitySupport (Typography.information_emphasis role) ++
      [("color",Appearance.information_foreground role)] ++ description_properties env
  | Surface.ActivityRow Surface.SupportingRow, _ => supporting_properties env ++ description_properties env
  | _,_ => [] end.
