From Stdlib Require Import String List NArith ZArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Browser Require Import Appearance Typography Layout.
From Selvedge.Interaction.Interactive Require Import Presentation Expand Vocabulary.
From Selvedge.Browser.Presentation Require Roles.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition gap name := match name with "none" => 0 | "sm" => 6 | "lg" => 18 | _ => 12 end.
Definition tone name := match name with
 | "accent" => Some (Appearance.token "--selvedge-accent")
 | "success" => Some (Appearance.token "--selvedge-success")
 | "warning" => Some (Appearance.token "--selvedge-warning")
 | "danger" => Some (Appearance.token "--selvedge-danger")
 | "muted" => Some Appearance.secondary_text | _ => None end.
Definition badge_properties env : list (string * string) :=
 Typography.properties (Layout.root_font_size_milli env) Typography.Support Typography.Medium ++
 [("background",Appearance.background Appearance.InsetPaint Appearance.Rest);
  ("align-self","flex-start");("border-radius","4px");("padding","2px 6px")].
Definition component_properties env (value : Presentation.component) : list (string * string) :=
 let props := Presentation.component_properties value in
 let tag := Vocabulary.component_tag (Expand.description props) in
 [("display","flex"); ("flex-direction","column"); ("min-inline-size","0");
  ("max-inline-size","100%"); ("gap",Typography.px (gap (Expand.property_text "gap" props)))] ++
 (match tag with
 | "row-layout" => Layout.row_properties Layout.Vertical ++ [("align-items","stretch");("overflow","hidden")]
 | "card" => Appearance.role_properties env Roles.Card
 | "badge" => badge_properties env
 | "table" => [("min-block-size","40px"); ("max-block-size","560px"); ("overflow","auto")]
 | "text-input" | "number-input" | "select" | "textarea" | "slider" =>
     [("min-block-size",Typography.px (Layout.motor_minimum env))]
 | "button" => Appearance.role_properties env Roles.Button
 | _ => [] end) ++
 (match tone (Expand.property_text "tone" props) with Some color => [("color",color)] | None => [] end) ++
 (match Presentation.component_binding value with
 | Expand.FieldLink _ _ | Expand.ActionLink _ _ =>
     [("padding","0"); ("border-width","0"); ("background","transparent"); ("min-block-size","0")]
 | _ => [] end).
Definition npx value := String.append (Numbers.show_natural value) "px".
Definition zpx value := String.append (Numbers.show_integer value) "px".
Definition placement_properties (env : Layout.environment) (value : Presentation.placement) : list (string * string) :=
 match value with
 | Presentation.ChartViewport => [("position","relative");("inline-size","100%");("block-size","240px");("overflow-x","auto");("overflow-y","hidden")]
 | Presentation.GraphViewport => [("position","relative"); ("inline-size","100%"); ("block-size","420px"); ("overflow","auto")]
 | Presentation.GraphCanvas width height => [("position","relative"); ("inline-size",npx width); ("block-size",npx height); ("flex","none")]
 | Presentation.GraphEdges => [("position","absolute"); ("inset","0"); ("pointer-events","none")]
 | Presentation.GraphNode x y width height selected => Appearance.role_properties env Roles.Card ++
     [("position","absolute"); ("inset-inline-start",zpx x); ("inset-block-start",zpx y);
      ("inline-size",npx width); ("block-size",npx height); ("overflow-y","auto"); ("overflow-x","hidden");
      ("border-color",if selected then Appearance.focus_color else Appearance.border_color)]
 end.
