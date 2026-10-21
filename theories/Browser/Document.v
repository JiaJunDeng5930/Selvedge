From Stdlib Require Import String List Bool Arith NArith ZArith.
From Selvedge.Foundation Require Import Json TextJson Numbers.
From Selvedge.Browser Require Import Native Appearance.
From Selvedge.Interaction Require Export Scene.
From Selvedge.Interaction Require Import Graphics.
Import ListNotations.
Open Scope string_scope.

Definition tag (value : kind) (multiline : bool) : string :=
  match value with
  | Group => "div" | Header => "header" | Heading => "h2" | Navigation => "nav" | Main => "main"
  | Aside => "aside" | Section => "section" | Dialog => "dialog" | ListView => "ul"
  | Item => "li" | Button => "button" | Field => if multiline then "textarea" else "input"
  | Select => "select" | OptionView => "option" | Checkbox => "input" | Form => "form"
  | Link => "a" | Image => "img" | Progress => "progress" | Table => "table"
  | Row => "tr" | Cell => "td" | Code => "code" | Icon => "span"
  | Text => "span" | Markdown => "div" | Portal => "div" | Graphic => "svg"
  end.

Definition optional_text (name : string) (value : json) : string :=
  match string_field name value with Some text => text | None => "" end.
Definition optional_bool (name : string) (value : json) : bool :=
  match bool_field name value with Some flag => flag | None => false end.
Definition optional_json (name : string) (value : json) : json :=
  match field name value with Some item => item | None => JNull end.

Definition value_text (source : json) : string :=
  match field "value" source with
  | Some (JString text) => text | Some JNull | None => ""
  | Some value => render_json value end.
Definition checked_value (source : json) : bool :=
  match bool_field "checked" source with
  | Some value => value | None => optional_bool "value" source end.
Definition option_scene (key : string) (source : json) :=
  (optional_text "label" source, value_text source).

Inductive scene : Type :=
| Scene (role : kind) (key label value : string) (disabled checked multiline : bool)
    (action attributes : json) (source : json) (children : list scene)
| GraphicScene (key label : string) (plot : Graphics.plot json).

(** Fuel is the input's structural size, rather than a product-visible depth limit. *)
Fixpoint json_size (value : json) : nat :=
  S (match value with
  | JArray xs => (fix sizes (rest : list json) :=
      match rest with [] => O | x :: tail => json_size x + sizes tail end) xs
  | JObject fields => (fix sizes (rest : list (string * json)) :=
      match rest with [] => O | (_, x) :: tail => json_size x + sizes tail end) fields
  | _ => O
  end).

Fixpoint decode_scene_at (fuel : nat) (value : json) : option scene :=
  match fuel with
  | O => None
  | S remaining =>
    match string_field "kind" value with
    | None => None
    | Some name =>
      match decode_kind name with
      | None => None
      | Some Graphic => match field "plot" value with
          | Some plot => option_map (GraphicScene (optional_text "key" value) (optional_text "label" value)) (Graphics.decode plot)
          | None => None end
      | Some role =>
        let children := match array_field "children" value with Some xs => xs | None => [] end in
        let fix decode_children (xs : list json) : option (list scene) :=
          match xs with
          | [] => Some []
          | x :: tail => match decode_scene_at remaining x, decode_children tail with
            | Some child, Some rest => Some (child :: rest) | _, _ => None end
          end in
        match decode_children children with
        | None => None
        | Some content =>
            let options := match role, array_field "options" value with
              | Select, Some options => map (fun option =>
                  Scene OptionView (optional_text "key" value ++ "/option/" ++ value_text option)
                    (optional_text "label" option) (value_text option) false false false
                    JNull JNull option []) options
              | _, _ => [] end in
            Some (Scene role (optional_text "key" value)
            (optional_text "label" value) (value_text value)
            (optional_bool "disabled" value) (checked_value value)
            (optional_bool "multiline" value) (optional_json "action" value)
            (optional_json "attrs" value) value (content ++ options))
        end
      end
    end
  end.
Definition decode_scene (value : json) := decode_scene_at (json_size value) value.

Inductive event_kind := Activate | Edit | Toggle | ChooseFiles | Submit | Dismiss.
Definition event_name (event : event_kind) :=
  match event with Activate => "activate" | Edit => "edit" | Toggle => "toggle"
  | ChooseFiles => "files" | Submit => "submit" | Dismiss => "dismiss" end.
Record event_binding := EventBinding { event : event_kind; action : json }.
Definition bindings (role : kind) (enabled : bool) (action : json) : list event_binding :=
  if enabled then
    match action with
    | JNull => []
    | _ => match role with
      | Button | Link => [EventBinding Activate action]
      | Field => [EventBinding Edit action]
      | Select => [EventBinding Edit action]
      | Checkbox => [EventBinding Toggle action]
      | Form => [EventBinding Submit action]
      | _ => []
      end
    end
  else [].

Record property := Property { property_name : string; property_value : string }.
Inductive node :=
| Element (key tag : string) (attributes styles : list property)
    (events : list event_binding) (children : list node) (metadata : json)
| TextNode (text : string)
| MarkdownNode (key text : string) (complete : bool) (source owner metadata : json)
| PortalNode (key target : string) (children : list node).

Definition tone_color (value : Graphics.tone) :=
  match value with
  | Graphics.Neutral => "currentColor" | Graphics.Accent => "var(--blue-500,#0169cc)"
  | Graphics.Success => "var(--green-500,#23814d)" | Graphics.Warning => "var(--orange-500,#ad5b00)"
  | Graphics.Danger => "var(--red-500,#c13046)" | Graphics.Muted => "var(--text-tertiary,GrayText)" end.
Definition coordinate_property name value := Property name (show_integer value).
Definition extent_property name value := Property name (show_natural value).
Definition graphic_primitive (key : string) (index : nat) (value : Graphics.primitive json) : node :=
  let identity := key ++ "/shape/" ++ show_nat index in
  let element tag properties styles events content metadata := Element identity tag
    (Property "data-key" identity :: properties) styles events content metadata in
  match value with
  | Graphics.Line x y u v tone => element "line"
      [coordinate_property "x1" x; coordinate_property "y1" y; coordinate_property "x2" u; coordinate_property "y2" v;
       Property "stroke" (tone_color tone); Property "stroke-width" "2"] [] [] [] JNull
  | Graphics.Rectangle x y width height tone => element "rect"
      [coordinate_property "x" x; coordinate_property "y" y; extent_property "width" width; extent_property "height" height;
       Property "fill" (tone_color tone)] [] [] [] JNull
  | Graphics.Circle x y radius tone => element "circle"
      [coordinate_property "cx" x; coordinate_property "cy" y; extent_property "r" radius; Property "fill" (tone_color tone)] [] [] [] JNull
  | Graphics.Label x y text tone => element "text"
      [coordinate_property "x" x; coordinate_property "y" y; Property "fill" (tone_color tone)]
      [Property "font" "inherit"] [] [TextNode text] JNull
  | Graphics.Hitbox target x y width height label action =>
      Element target "rect"
        [Property "data-key" target; coordinate_property "x" x; coordinate_property "y" y;
         extent_property "width" width; extent_property "height" height;
         Property "fill" "transparent"; Property "role" "button"; Property "tabindex" "0"; Property "aria-label" label]
        [Property "cursor" "pointer"] [EventBinding Activate action] []
        (JObject [("meta", JObject [("key_actions", JObject [("Enter", action); (" ", action)])])])
  end.
Definition render_graphic (key label : string) (value : Graphics.plot json) : node :=
  Element key "svg" [Property "data-key" key; Property "role" "img"; Property "aria-label" label;
      Property "viewBox" ("0 0 " ++ show_natural (Npos (Graphics.width value)) ++ " " ++ show_natural (Npos (Graphics.height value)))]
    [Property "inline-size" "100%"; Property "block-size" "var(--graphic-block-size,auto)"; Property "max-block-size" "var(--graphic-max-block-size,36rem)"] []
    (map (fun indexed => graphic_primitive key (fst indexed) (snd indexed))
      (combine (seq O (List.length (Graphics.primitives value))) (Graphics.primitives value))) JNull.

Definition allowed_attributes : list string :=
  ["id"; "class"; "title"; "role"; "name"; "type"; "placeholder";
     "draggable"; "data-card-id"; "data-card-revision"; "data-card-observed-at"; "data-drop-status"; "data-card-before"; "data-field"; "data-object-owner";
     "min"; "max"; "step"; "rows"; "cols"; "accept"; "multiple"; "required";
     "target"; "rel"; "alt"; "width"; "height"; "tabindex";
     "aria-label"; "aria-hidden"; "aria-labelledby"; "aria-describedby"; "aria-autocomplete"; "aria-activedescendant"; "aria-expanded";
     "aria-controls"; "aria-selected"; "aria-pressed"; "aria-haspopup"; "aria-live"; "aria-current"; "aria-modal";
     "data-owner"; "data-retain-focus"; "data-subject"; "data-action"; "data-code"; "data-logical-key"; "data-view"; "data-focus-alias"; "data-anchor"; "data-anchor-focus"; "data-layout"; "data-expanded"; "data-drawer-open"; "data-selected"; "data-reveal-on-layout"; "data-reading-root"; "data-reading-anchor"; "data-motion-paused"; "data-interactive-motion"; "data-interactive-motion-glyph"; "data-interactive-transition"; "data-interactive-stale"; "data-sources-fresh"].
Definition allowed_attribute (name : string) : bool :=
  existsb (String.eqb name) allowed_attributes.
Definition decode_properties (source : json) : list property :=
  match source with
  | JObject fields => flat_map (fun field =>
      let '(name, value) := field in
      if allowed_attribute name then
        match value with
        | JString text => [Property name text]
        | JNumber text => [Property name text]
        | JBool flag => [Property name (if flag then "true" else "false")]
        | _ => [] end
      else []) fields
  | _ => []
  end.
Definition admitted_link (url : string) : bool :=
  starts_with "https://" url || starts_with "http://" url ||
  starts_with "mailto:" url || starts_with "#" url ||
  (starts_with "/" url && negb (starts_with "//" url)).
Definition observation_properties (system_dark : bool) (source : json) : list property :=
  match string_field "layout" source with
  | Some layout => [Property "data-layout" layout] | None => [] end ++
  match string_field "value_kind" source with
  | Some kind => [Property "data-value-kind" kind] | None => [] end ++
  match string_field "appearance" source with
  | Some "dark" => [Property "data-theme" "dark"]
  | Some "light" => [Property "data-theme" "light"]
  | Some "system" => [Property "data-theme" (if system_dark then "dark" else "light")]
  | _ => [] end.
Definition resource_properties (role : kind) (source : json) : list property :=
  let url := optional_text "url" source in
  match role with
  | Link => if admitted_link url then
      [Property "href" url; Property "rel" "noopener noreferrer"] else []
  | Image => if starts_with "/api/board/attachments/" url then
      [Property "src" url; Property "alt" (optional_text "label" source)] else []
  | _ => []
  end.
(** CSS uses the user's root font scale, with the original nominal size as a floor.
    Native font shaping and intrinsic measurement remain browser responsibilities. *)
Definition scaled_pixels (nominal : N) : string :=
  "max(" ++ show_natural nominal ++ "px,calc(" ++ show_natural nominal ++ "rem / 16))".
Definition text_style (prefix : string) (dimensions : N * N) (weight : N) (family : string) :=
  let '(size,leading) := dimensions in
  [Property (prefix ++ "-size") (scaled_pixels size);
   Property (prefix ++ "-line") (scaled_pixels leading);
   Property (prefix ++ "-weight") (show_natural weight);
   Property (prefix ++ "-font") family].
Definition interface_font := "var(--font-sans,system-ui)".
Definition code_font := "var(--font-mono,monospace)".
Definition title_dimensions := (20%N,28%N).
Definition body_dimensions := (13%N,20%N).
Definition typography_styles :=
  flat_map (fun '(prefix,dimensions,weight,family) => text_style prefix dimensions weight family)
    [("--rich-title",title_dimensions,600%N,interface_font);
     ("--rich-section",(14%N,20%N),500%N,interface_font);
     ("--rich-body",body_dimensions,400%N,interface_font);
     ("--rich-support",(12%N,18%N),500%N,interface_font);
     ("--rich-code",body_dimensions,400%N,code_font);
     ("--rich-body-strong",body_dimensions,600%N,interface_font)].
Definition focus_width := 2%N.
Definition focus_inset := 2%N.
Definition application_styles : list property := typography_styles ++
  [Property "font-family" interface_font; Property "font-size" "var(--rich-body-size)";
   Property "line-height" "var(--rich-body-line)";
   Property "color" "var(--app-color-text-foreground)";
   Property "background" "var(--app-color-background-surface)";
   Property "--native-focus-ring" "var(--app-color-border-focus)";
   Property "--native-focus-width" (show_natural focus_width ++ "px");
   Property "--native-focus-offset" ("-" ++ show_natural (focus_width + focus_inset) ++ "px");
   Property "--native-disabled-opacity" "40%";
   Property "--native-writing-lines" (show_nat Appearance.initial_writing_lines);
   Property "--native-clearance" (scaled_pixels (N.of_nat Appearance.clearance_pixels));
   Property "--native-icon-size" (scaled_pixels (N.of_nat Appearance.icon_pixels))].

Definition render_symbol (key : string) (value : Appearance.symbol) : node :=
  Element (key ++ "/icon") "svg"
    [Property "viewBox" "0 0 20 20"; Property "aria-hidden" "true";
     Property "focusable" "false"; Property "data-icon" (Appearance.symbol_name value)]
    [Property "inline-size" "var(--native-icon-size)"; Property "block-size" "var(--native-icon-size)";
     Property "flex-shrink" "0"; Property "pointer-events" "none"] []
    [Element (key ++ "/icon/path") "path"
      ([Property "d" (Appearance.symbol_path value)] ++
       match Appearance.symbol_paint value with
       | Appearance.Filled => [Property "fill" "currentColor"]
       | Appearance.Outline => [Property "fill" "none"; Property "stroke" "currentColor";
           Property "stroke-width" "1.4"; Property "stroke-linecap" "round"; Property "stroke-linejoin" "round"] end)
      [] [] [] JNull] JNull.
Definition caption_nodes (key label : string) (source : json) : list node :=
  let caption := Element (key ++ "/caption") "span" [Property "class" "control-caption"] [] [] [TextNode label] JNull in
  match Appearance.find_symbol (optional_text "icon" source) with
  | None => [caption]
  | Some symbol => [render_symbol key symbol; caption]
  end.
(* Artwork expansion is irrelevant to renderer termination and event proofs.
   Extraction still executes this checked definition and its symbol declaration. *)
Opaque caption_nodes.
Definition reading_styles (attributes : json) : list property :=
  if existsb (fun p => String.eqb (property_name p) "data-reading-root" &&
                       String.eqb (property_value p) "true") (decode_properties attributes) then
    [Property "flex" "1"; Property "min-block-size" "8lh"; Property "overflow" "auto"]
  else [].
Definition navigation_columns : nat := 15.
Definition navigation_rail_columns : nat := 4.
Definition main_columns : nat := 20.
Definition workspace_padding : nat := 1.
Definition workspace_gap : nat := 1.
Definition rem_length (units : nat) := show_natural (N.of_nat units) ++ "rem".
Definition observed_number_style (source : json) (field_name css_name unit : string) : list property :=
  match number_field field_name source with
  | Some value => [Property css_name (value ++ unit)] | None => [] end.
Definition component_styles (source : json) : list property :=
  (match string_field "gap" source with
   | Some "none" => [Property "gap" "0"]
   | Some "sm" => [Property "gap" (scaled_pixels 6)]
   | Some "md" => [Property "gap" (scaled_pixels 12)]
   | Some "lg" => [Property "gap" (scaled_pixels 18)] | _ => [] end) ++
  match optional_text "tone" source with
  | "accent" => [Property "color" "var(--color-token-text-link-foreground)"]
  | "success" => [Property "color" "var(--interactive-tone-success)"]
  | "warning" => [Property "color" "var(--color-token-editor-warning-foreground)"]
  | "danger" => [Property "color" "var(--interactive-tone-danger)"]
  | "muted" => [Property "color" "var(--color-token-text-secondary)"] | _ => [] end.
Definition layout_styles (mode : presentation) (source : json) : list property :=
  match optional_text "layout" source with
  | "workspace" => [Property "display" "grid"; Property "grid-template-rows" "auto minmax(0,1fr)";
      Property "padding" "0"; Property "gap" "0"; Property "block-size" "100dvh";
      Property "overflow" "hidden"] ++ application_styles
  | "workspace-navigation" => [Property "display" "contents"]
  | "supporting-header" => [Property "flex-direction" "row"; Property "align-items" "center";
      Property "gap" "var(--native-clearance)"; Property "flex-shrink" "0";
      Property "position" "sticky"; Property "top" "0"; Property "z-index" "2";
      Property "background" "var(--app-color-background-surface)"]
  | "navigation-header" => [Property "flex-direction" "row"; Property "align-items" "center";
      Property "padding" "0.5rem"; Property "gap" "0.5rem"; Property "min-inline-size" "0"]
  | "global-navigation" => [Property "padding" "0.5rem"; Property "min-block-size" "0"; Property "overflow" "auto"]
  | "task-navigation" => [Property "gap" "0"; Property "min-block-size" "0"; Property "overflow" "auto"; Property "padding" "0.75rem"]
  | "responsive-alternative" => [Property "flex" "1"; Property "min-inline-size" "0"]
  | "simultaneous-only" => [Property "flex-direction" "row"; Property "overflow" "auto"; Property "align-items" "center"]
  | "sequential-only" => [Property "flex-direction" "row"]
  | "task-branch" => [Property "gap" "0"]
  | "project-task-group" => [Property "gap" "0"; Property "margin-block-start" "1rem"]
  | "project-tasks" => [Property "gap" "0"; Property "padding-inline-start" "var(--native-clearance)"]
  | "task-row" | "project-row" => [Property "flex-direction" "row"; Property "align-items" "center";
      Property "gap" "0"; Property "border-radius" "6px";
      Property "--native-button-border" "0"; Property "--native-button-padding" "4px";
      Property "--native-button-background" "transparent"]
  | "chart-viewport" => [Property "overflow" "auto"; Property "display" "block";
      Property "block-size" "240px"]
  | "graph-viewport" => [Property "overflow" "auto"; Property "min-block-size" "12rem";
      Property "block-size" "420px"; Property "display" "block"]
  | "graph-canvas" => [Property "position" "relative"; Property "display" "block";
      Property "--graphic-block-size" "100%"; Property "--graphic-max-block-size" "none"] ++
      observed_number_style source "width" "inline-size" "px" ++
      observed_number_style source "height" "block-size" "px"
  | "graph-edges" => [Property "position" "absolute"; Property "inset" "0";
      Property "inline-size" "100%"; Property "block-size" "100%"; Property "display" "block"]
  | "graph-node" => [Property "position" "absolute"; Property "z-index" "1"; Property "overflow" "auto"] ++
      observed_number_style source "x" "left" "px" ++ observed_number_style source "y" "top" "px" ++
      observed_number_style source "width" "inline-size" "px" ++ observed_number_style source "height" "block-size" "px"
  | "skill-option" => [Property "flex-direction" "column"; Property "align-items" "stretch";
      Property "gap" "2px"; Property "padding" "8px 12px"; Property "border-radius" "6px"]
  | "anchored-listbox" => [Property "position" "fixed"; Property "inset" "auto";
      Property "position-area" "top span-right"; Property "position-try-fallbacks" "flip-block,flip-inline,flip-block flip-inline";
      Property "margin" "0 0 6px 0"; Property "padding" "4px"; Property "list-style" "none";
      Property "inline-size" "anchor-size(width,min(32rem,calc(100dvw - 32px)))";
      Property "max-inline-size" "calc(100dvw - 24px)"; Property "max-block-size" "min(18rem,45dvh)";
      Property "overflow" "auto"; Property "z-index" "1000";
      Property "background" "var(--app-color-background-surface)";
      Property "border" "1px solid var(--app-color-border-heavy)"; Property "border-radius" "10px";
      Property "box-shadow" "0 6px 24px #0002"; Property "--native-button-border" "0";
      Property "--native-button-background" "transparent"]
  | "anchored-menu" => [Property "position" "fixed"; Property "inset" "auto";
      Property "margin" "0"; Property "position-area" "bottom span-right";
      Property "position-try-fallbacks" "flip-block,flip-inline,flip-block flip-inline";
      Property "inline-size" "max-content"; Property "max-inline-size" "min(24rem,calc(100dvw - 2 * var(--native-clearance)))";
      Property "max-block-size" "calc(100dvh - 2 * var(--native-clearance))";
      Property "padding" "var(--native-clearance)"]
  | "motion-wrapper" => [Property "flex-direction" "row"; Property "flex-wrap" "nowrap";
      Property "align-items" "center"; Property "gap" (scaled_pixels 6)]
  | "row" => [Property "flex-direction" "row"; Property "flex-wrap" "wrap"]
  | "column" => [Property "flex-direction" "column"]
  | "fill" => [Property "flex" "1"; Property "min-block-size" "0"]
  | "grid" => [Property "display" "grid"; Property "grid-template-columns" (match number_field "columns" source with
        | Some count => "repeat(" ++ count ++ ",minmax(0,1fr))"
        | None => "repeat(auto-fit,minmax(min(18rem,100%),1fr))" end)]
  | _ => []
  end.
Definition role_properties (role : kind) (key label value : string)
    (disabled checked : bool) : list property :=
  [Property "id" key; Property "data-key" key; Property "data-kind" (kind_name role)] ++
  (if String.eqb label "" then [] else [Property "aria-label" label]) ++
  (match role with
   | Field | Select | OptionView => [Property "value" value]
   | Button => [Property "type" "button"]
   | Checkbox => [Property "type" "checkbox"; Property "checked" (if checked then "true" else "false")]
   | Dialog => [Property "open" "true"]
   | Main => [Property "tabindex" "-1"] | _ => [] end) ++
  (if disabled then [Property "disabled" "true"] else []).
Definition base_styles (role : kind) : list property :=
  match role with
  | Group | Header | Navigation | Main | Aside | Section | Dialog | Form =>
      [Property "display" "flex"; Property "flex-direction" "column";
       Property "min-inline-size" "0"; Property "gap" "0.75rem"]
  | Button => [Property "font" "inherit"; Property "padding" "var(--native-button-padding,4px 8px)";
      Property "min-inline-size" (scaled_pixels (N.of_nat Appearance.motor_target_pixels));
      Property "min-block-size" (scaled_pixels (N.of_nat Appearance.motor_target_pixels));
      Property "display" "inline-flex"; Property "align-items" "center"; Property "gap" "0.5rem";
      Property "--native-rest-background" "var(--native-button-background,var(--app-color-background-button-tertiary))";
      Property "--native-rest-color" "var(--app-color-text-foreground)";
      Property "--native-hover-background" "var(--app-color-background-button-tertiary-hover)";
      Property "--native-pressed-background" "var(--app-color-background-button-tertiary-active)";
      Property "border" "var(--native-button-border,1px solid var(--app-color-border-heavy))"; Property "border-radius" "8px";
      Property "text-align" "start"]
  | Field | Select => [Property "font" "inherit"; Property "min-inline-size" "0";
      Property "padding" "6px 8px"; Property "min-block-size" (scaled_pixels (N.of_nat Appearance.motor_target_pixels));
      Property "background" "var(--app-color-background-surface)";
      Property "color" "var(--app-color-text-foreground)"; Property "border" "1px solid var(--app-color-border-heavy)";
      Property "border-radius" "8px"]
  | Heading => text_style "--heading" title_dimensions 500 interface_font ++
      [Property "margin" "0"; Property "font-size" "var(--heading-size)"; Property "line-height" "var(--heading-line)";
       Property "font-weight" "var(--heading-weight)"]
  | Image => [Property "max-inline-size" "100%"; Property "block-size" "auto"]
  | _ => []
  end.

Definition render_control (mode : presentation) (system_dark : bool) (role : kind)
    (key label value : string) (disabled checked multiline : bool)
    (action attributes source : json) (rendered : list node) : node :=
  let control := Element key (tag role multiline)
        (role_properties role key label value disabled checked ++
         (if String.eqb (optional_text "icon" source) "" then [] else [Property "title" label]) ++
         (match role with Field => if multiline then
           [Property "rows" (show_nat Appearance.initial_writing_lines)] else [] | _ => [] end) ++
         observation_properties system_dark source ++ resource_properties role source ++ decode_properties attributes)
        (base_styles role ++ layout_styles mode source ++ component_styles source ++ reading_styles attributes)
        (if disabled then [] else
          match string_field "type" attributes with
          | Some "file" => [EventBinding ChooseFiles action]
          | _ => bindings role true action ++
            match field "file_action" source with
            | Some file_action => [EventBinding ChooseFiles file_action] | None => [] end ++
            match role, mode, field "dismiss_action" source with
            | Dialog, _, Some dismiss_action | Aside, Sequential, Some dismiss_action => [EventBinding Dismiss dismiss_action] | _, _, _ => [] end
          end)
        (match role with
         | Text | Code => [TextNode value]
         | Icon => match Appearance.find_symbol (optional_text "icon" source) with
             | Some symbol => [render_symbol key symbol]
             | None => [TextNode label] end
         | _ => (if String.eqb label "" then [] else
           match role with
           | Button | Link => caption_nodes key label source
           | Header | Heading | OptionView | Icon => [TextNode label]
           | _ => [] end) ++ rendered
         end) source in
      match role with
      | Field | Select | Checkbox =>
          Element (key ++ "/field") "div" [Property "data-field" key]
            [Property "display" "flex"; Property "flex-direction" "column"; Property "gap" "0.25rem"; Property "min-inline-size" "0"] []
            ([Element (key ++ "/label") "label" [Property "for" key] [] [] [TextNode label] JNull;
              match control with Element key tag attrs styles events children metadata =>
                Element key tag (Property "id" key :: attrs) styles events
                  (match role with Select => children | _ => [] end) metadata
              | other => other end] ++
             (match role with Select => [] | _ => rendered end) ++
             (if String.eqb (optional_text "help" source) "" then [] else
               [Element (key ++ "/help") "small" [] [] [] [TextNode (optional_text "help" source)] JNull])) source
      | Main => match control with
          Element key tag attrs styles events children metadata =>
            Element key tag attrs (styles ++ [Property "flex" "1"; Property "min-block-size" "0"; Property "overflow" "auto";
              Property "min-inline-size" (match mode with Simultaneous => rem_length main_columns | Sequential => "0" end)]) events children metadata
          | other => other end
      | Aside => match control with
          | Element key tag attrs styles events children metadata =>
            let styles:=List.app styles [Property "min-block-size" "0"; Property "overflow" "auto"] in
            match mode with
            | Simultaneous => Element key tag attrs
                (styles ++ [Property "min-inline-size" (rem_length main_columns)]) events children metadata
            | Sequential => Element key "dialog" (Property "open" "true" :: attrs)
                (styles ++ [Property "position" "fixed"; Property "inset" (rem_length workspace_padding);
                 Property "inline-size" "auto"; Property "block-size" "auto"; Property "margin" "0";
                 Property "max-inline-size" "none"; Property "max-block-size" "none";
                 Property "box-sizing" "border-box"; Property "padding" (rem_length workspace_padding)]) events children metadata
            end
          | other => other end
      | _ => control end.

Definition render_scene_contents (mode : presentation) (system_dark : bool) (value : scene)
    (rendered : list node) : node :=
  match value with
  | GraphicScene key label plot => render_graphic key label plot
  | Scene role key label value disabled checked multiline action attributes source _ =>
    match role with
    | Markdown => MarkdownNode key value (optional_bool "complete" source)
        (optional_json "source" source) (optional_json "owner" source) source
    | Portal => PortalNode key (optional_text "target" source) rendered
    | _ => render_control mode system_dark role key label value disabled checked multiline
        action attributes source rendered
    end
  end.

Fixpoint render_scene (mode : presentation) (system_dark : bool) (value : scene) : node :=
  match value with
  | GraphicScene key label plot => render_graphic key label plot
  | Scene _ _ _ _ _ _ _ _ _ _ children =>
      render_scene_contents mode system_dark value (map (render_scene mode system_dark) children)
  end.

Definition node_metadata (value : node) : json :=
  match value with Element _ _ _ _ _ _ metadata | MarkdownNode _ _ _ _ _ metadata => metadata | _ => JNull end.
Definition node_layout (value : node) := optional_text "layout" (node_metadata value).
Definition node_children (value : node) :=
  match value with Element _ _ _ _ _ children _ | PortalNode _ _ children => children | _ => [] end.
Definition visible_in (mode : presentation) (value : node) : bool :=
  match node_layout value, mode with
  | "simultaneous-only", Sequential | "sequential-only", Simultaneous => false
  | _, _ => true end.
Definition tree_expanded (value : node) : bool :=
  String.eqb (optional_text "data-expanded" (optional_json "attrs" (node_metadata value))) "true".
Definition tree_drawer_open (value : node) : bool :=
  String.eqb (optional_text "data-drawer-open" (optional_json "attrs" (node_metadata value))) "true".
Definition task_navigation_scope (key : string) (header tree : node) : node :=
  let scope := key ++ "/scope" in
  Element scope "dialog"
    [Property "id" scope; Property "data-key" scope; Property "data-kind" "dialog";
     Property "data-layout" "task-navigation-scope"; Property "open" "true";
     Property "aria-label" (optional_text "label" (node_metadata tree))]
    [Property "display" "grid"; Property "grid-template-rows" "auto minmax(0,1fr)";
     Property "position" "fixed"; Property "inset" "0"; Property "inline-size" "100%";
     Property "block-size" "100dvh"; Property "max-inline-size" "none"; Property "max-block-size" "none";
     Property "margin" "0"; Property "padding" "0"; Property "border" "0"; Property "overflow" "hidden"]
    (match field "dismiss_action" (node_metadata tree) with
     | Some action => [EventBinding Dismiss action] | None => [] end)
    [header; tree] (JObject [("layout", JString "task-navigation-scope")]).
Definition navigation_content mode key rail header tree : list node :=
  match mode with
  | Simultaneous => [rail; header] ++ if tree_expanded tree || tree_drawer_open tree then [tree] else []
  | Sequential => if tree_drawer_open tree then [task_navigation_scope key header tree] else [header]
  end.
Definition rendered_support (value : node) : bool :=
  match value with Element _ "aside" _ _ _ _ _ => true | _ => false end.
Definition visible_task_tree (value : node) : bool :=
  String.eqb (node_layout value) "workspace-navigation" &&
    existsb (fun child => String.eqb (node_layout child) "task-navigation") (node_children value).
Definition workspace_columns mode children : string :=
  match mode with
  | Sequential => "minmax(0,1fr)"
  | Simultaneous => rem_length navigation_rail_columns ++ " " ++
      (if existsb visible_task_tree children then rem_length navigation_columns ++ " " else "") ++
      "minmax(0,1fr)" ++
      String.concat "" (repeat (" minmax(" ++ rem_length main_columns ++ ",1fr)")
        (List.length (filter rendered_support children)))
  end.

(* Physical projection changes placement, never the semantic identity of retained controls.
   In a compact task drawer the original header belongs to the drawer's focus scope. *)
Fixpoint project_navigation (mode : presentation) (value : node) {struct value} : node :=
  match value with
  | Element key tag attrs styles events children metadata =>
    let projected := filter (visible_in mode) (map (project_navigation mode) children) in
    let arranged := match optional_text "layout" metadata, projected with
      | "workspace-navigation", [rail; header; tree] => navigation_content mode key rail header tree
      | _, _ => projected end in
    let workspace := String.eqb (optional_text "layout" metadata) "workspace" in
    Element key tag
      (attrs ++ if workspace then
        [Property "data-presentation" (match mode with Simultaneous => "simultaneous" | Sequential => "sequential" end)] else [])
      (styles ++ if workspace then
        [Property "grid-template-columns" (workspace_columns mode arranged);
         Property "--navigation-rail-width" (rem_length navigation_rail_columns);
         Property "--task-navigation-width" (rem_length navigation_columns)] else [])
      events arranged metadata
  | PortalNode key target children => PortalNode key target
      (filter (visible_in mode) (map (project_navigation mode) children))
  | other => other
  end.

Definition property_json (value : property) := JObject
  [("name", JString (property_name value)); ("value", JString (property_value value))].
Definition event_json (value : event_binding) := JObject
  [("kind", JString (event_name (event value))); ("action", action value)].
Fixpoint node_json (value : node) : json :=
  match value with
  | TextNode text => JObject [("kind", JString "text"); ("value", JString text)]
  | MarkdownNode key text complete source owner metadata => JObject
      [("kind", JString "markdown"); ("key", JString key); ("value", JString text);
       ("complete", JBool complete); ("source", source); ("owner", owner); ("metadata", metadata)]
  | PortalNode key target children => JObject
      [("kind", JString "portal"); ("key", JString key); ("target", JString target);
       ("children", JArray (map node_json children))]
  | Element key tag attributes styles events children metadata => JObject
      [("kind", JString "element"); ("key", JString key); ("tag", JString tag);
       ("attributes", JArray (map property_json attributes));
       ("styles", JArray (map property_json styles));
       ("events", JArray (map event_json events)); ("children", JArray (map node_json children)); ("metadata", metadata)]
  end.
Definition workspace_allocation (font_pixels : nat) :=
  Allocation (navigation_columns * font_pixels) (main_columns * font_pixels) (navigation_rail_columns * font_pixels)
    ((2 * workspace_padding + workspace_gap) * font_pixels).
Fixpoint supporting_count (value:scene) : nat :=
 match value with
 | GraphicScene _ _ _ => O
 | Scene role _ _ _ _ _ _ _ _ _ children =>
   (match role with Aside => 1 | _ => O end) +
     fold_right Nat.add O (map supporting_count children)
 end.
Definition scene_allocation font_pixels scene :=
 let requirements:=workspace_allocation font_pixels in
 Allocation (navigation_minimum requirements) (content_minimum requirements)
   (rail_width requirements + supporting_count scene * (main_columns + workspace_gap) * font_pixels)
   (gap_width requirements).
Definition document (viewport font_pixels : nat) (system_dark : bool) (source : json) : json :=
  match decode_scene source with
  | Some scene =>
      let navigation_mode := allocate viewport (workspace_allocation font_pixels) in
      let supporting_mode := allocate viewport (scene_allocation font_pixels scene) in
      success (JObject [("title", JString "Selvedge");
        ("root", node_json (project_navigation navigation_mode (render_scene supporting_mode system_dark scene)))])
  | None => failure "TypeError" "Browser scene has an invalid kind or children"
  end.
