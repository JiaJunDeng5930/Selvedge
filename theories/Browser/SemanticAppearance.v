From Stdlib Require Import String List Bool Arith NArith.
From Selvedge.Browser Require Import Appearance Typography Layout ControlPurpose.
From Selvedge.Interaction.Presentation Require Import Roles Information Composition Surface.
From Selvedge.Interaction.Submission Require Fields.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Module UX := Selvedge.Interaction.Experience.Model.
Definition scaled env := Typography.scaled (Layout.root_font_size_milli env).
Definition pixels env value := Typography.px (scaled env value).
Definition row env := [("display","flex"); ("flex-direction","row"); ("align-items","center");
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
  if activity then row env else [("display","flex"); ("flex-direction","column"); ("gap",pixels env 8)].
Definition action_properties env (activity : bool) : list (string * string) :=
  (if activity then Layout.heading_properties env true else
    [("display","flex"); ("flex-direction","column"); ("padding",pixels env 12); ("gap",pixels env 12)]) ++
  [("--control-focus-width","1px"); ("--control-focus-offset","-1px");
   ("--control-focus-ring",Appearance.token "--color-token-border-default")].
Definition surface_properties env : list (string * string) :=
  let width := Nat.max (scaled env 200)
    (Layout.activity_primary_advance (Layout.parameters env) * 56 + scaled env 16) in
  [("min-inline-size",String.append "min(100%," (String.append (pixels env 200) ")"));
   ("inline-size","fit-content");
   ("max-inline-size",String.append "min(100%," (String.append (Typography.px width) ")"))].
Definition description_properties env : list (string * string) :=
  [("max-inline-size",Typography.px (Layout.activity_support_advance (Layout.parameters env) * 38))].
Definition member_width_properties env : list (string * string) :=
  [("max-inline-size",Typography.px (Layout.activity_primary_advance (Layout.parameters env) * 44))].
Definition toggle_properties env :=
  [("inline-size",pixels env 16); ("block-size",pixels env 16); ("min-block-size",pixels env 16);
   ("padding","0"); ("align-self","center"); ("border-radius",pixels env 3)].
Definition editor_properties {Action} env (value : Surface.meaning Action) : list (string * string) :=
  match value with
  | Surface.Edit _ subject control =>
      if ControlPurpose.toggle_widget (UX.subject_declaration subject)(Model.editing_observation control)
      then toggle_properties env else
      match UX.subject_declaration subject, Model.editing_observation control with
      | Fields.MessageText, _ => embedded env ++
          [("padding","0"); ("border-radius","0"); ("resize","none"); ("inline-size","100%");
           ("min-block-size",Typography.px (Layout.input_minimum_height (Layout.parameters env)));
           ("max-block-size",Typography.px (Layout.input_maximum_height (Layout.parameters env)))]
      | Fields.WorkName, _ | Fields.CardTitle, _ => embedded env
      | Fields.CardDescription, _ => [("border-width","0"); ("min-block-size",pixels env 110)]
      | _, _ => [] end
  | Surface.SearchChoices _ _ => [("background",Appearance.background Appearance.InsetPaint Appearance.Rest);
      ("padding-inline",pixels env 8); ("padding-block",pixels env 4); ("border-radius",pixels env 6)]
  | _ => [] end.

(** The meaning selects product relationships before native element construction. *)
Definition meaning_properties {Action} env activity (value : Surface.meaning Action)
    : list (string * string) :=
  (match value with
  | Surface.InformationText role => Appearance.information_properties env activity role ++
      match role with
      | Information.NavigationCaption => [("padding-inline",pixels env 8)]
      | Information.Description => if activity then description_properties env else []
      | _ => [] end
  | Surface.PageRegion region position => Layout.region_properties env region position
  | Surface.ProjectGroup _ _ _ => [("display","flex"); ("flex-direction","column"); ("gap",pixels env 4)]
  | Surface.TaskRow _ _ _ _ _ => Layout.member_properties env false false
  | Surface.TaskChildren _ => Layout.member_properties env false true
  | Surface.ProjectChooser _ => [("display","flex"); ("flex-direction","row"); ("align-items","center"); ("gap","0"); ("padding","0")]
  | Surface.ActivityGroup _ _ _ behavior | Surface.LayerRegion behavior =>
      match Model.layer_presentation behavior with Model.AnchoredMenu => surface_properties env | _ => [] end
  | Surface.ContextSummary _ => [("display","flex"); ("flex-direction","column"); ("gap",pixels env 4); ("padding-inline",pixels env 8)]
  | Surface.DirectoryRow _ _ | Surface.WorkspaceMember _ _ _ => member_properties env activity ++
      if activity then member_width_properties env else []
  | Surface.ChoiceGroup | Surface.DecisionGroup _ _ => [("display","flex"); ("flex-direction","column"); ("gap",pixels env 4)]
  | Surface.Choice _ selected description _ =>
      Appearance.style_properties env (Appearance.navigation_style selected 8 6) ++
      [("align-items","flex-start"); ("white-space","normal"); ("padding-block",pixels env 8)]
  | Surface.WorkChoice _ selected _ =>
      Appearance.style_properties env (Appearance.fields (Appearance.ChoicePaint selected)
        (Appearance.token (if selected then "--color-token-focus-border" else "--color-token-border-default"))
        1 10 false Appearance.Leading Appearance.RowFlow Appearance.ContentFlow 12 12 8 120 100 true false)
  | Surface.ActionUnit _ _ => action_properties env activity
  | Surface.ObjectGroup _ => Layout.group_properties env activity
  | Surface.ActivityRow Surface.ObjectHeading => Layout.heading_properties env activity
  | Surface.ActivityRow _ => Layout.member_properties env activity false
  | Surface.SettingEntry _ _ _ | Surface.SupportingControl _ _ _ _ => compact_control env
  | Surface.BoardLane _ _ => [("background",Appearance.token "--color-surface-secondary");
      ("padding",pixels env 8); ("min-inline-size",Typography.px (Layout.lane_minimum_width (Layout.parameters env)))]
  | Surface.BoardGroup Surface.SearchArea => row env
  | Surface.BoardGroup Surface.PrimaryAction => [("margin-inline-start","auto")]
  | Surface.ActionFeedback _ _ _ | Surface.ActionExplanation _ _ =>
      Appearance.information_properties env activity Information.Description
  | Surface.ReadOnly _ => [("overflow-wrap","anywhere")]
  | _ => [] end) ++ editor_properties env value.

(** A source context is propagated as a typed meaning, never recovered from a DOM key. *)
Definition source_properties {Action} env (source current : Surface.meaning Action)
    : list (string * string) :=
  match source,current with
  | Surface.TaskRow _ _ _ _ _, Surface.Activate _ => single_line env ++ [("flex","1");("text-align","left")]
  | Surface.SkillSuggestion _ _, Surface.InformationText Information.OptionLabel =>
      [("font-size","14px");("font-weight","700")]
  | Surface.SkillSuggestion _ _, Surface.InformationText Information.Description =>
      [("font-size","12px");("overflow","hidden");("text-overflow","ellipsis");
       ("white-space","nowrap");("max-inline-size","100%")]
  | Surface.SkillSuggestion _ _, Surface.InformationText Information.FieldValue =>
      [("font-size","11px");("color",Appearance.secondary_text);("overflow-wrap","anywhere")]
  | Surface.SkillSuggestions _ _, Surface.InformationText Information.Status =>
      [("padding","10px 12px");("font-size","13px")]
  | Surface.ProjectGroup _ selected _, Surface.Region =>
      Appearance.style_properties env (Appearance.navigation_style selected 2 0)
  | Surface.ProjectGroup _ _ _, Surface.Activate _ => single_line env
  | Surface.ProjectChooser _, Surface.Activate _ => compact_control env ++
      [("padding-inline","0"); ("padding-block",pixels env 4); ("gap",pixels env 4)]
  | Surface.ProjectGroup _ _ _, Surface.InformationText Information.GroupTitle =>
      Typography.properties (Layout.root_font_size_milli env) Typography.ActivityPrimary Typography.Strong
  | _,_ => [] end.
