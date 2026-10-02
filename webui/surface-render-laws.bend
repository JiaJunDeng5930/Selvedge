import Base
import ./surfaces.bend as Surfaces
import ./design.bend as Design
import ./document.bend as Doc
import ./renderer.bend as Render
import ./MODEL.bend as Web
import ./controls.bend as Controls
import ../core/interface.bend as UI
import ../core/SYSTEM.bend as Core
import ../core/ui-world.bend as View
import ../BOARD.bend as Board

def node_styles(node: Doc.Node) -> +List<Doc.Property>:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: styles
    case _: Nil{}

def document_background(document: Doc.Document) -> String:
  Doc.Document{root, title} = document
  Render.attr(node_styles(root), "background")

def color_clear() -> {Render.surface_color(Surfaces.Clear{}) == "transparent" : String}:
  {==}

def color_token(+name: String) ->
  {Render.surface_color(Surfaces.Token{name}) == "var(" ++ name ++ ")" : String}:
  {==}

def color_blend(+foreground: String, +percent: Nat, +background: String) ->
  {Render.surface_color(Surfaces.Blend{foreground, percent, background}) ==
    "color-mix(in srgb, var(" ++ foreground ++ ") " ++ Nat.show(percent) ++ "%, var(" ++ background ++ "))" : String}:
  {==}

def surface_paint(+role: Surfaces.Role, +phase: Surfaces.Phase) ->
  {Render.paint(Design.SurfacePaint{role, phase}) == Render.surface_color(Surfaces.background(role, phase)) : String}:
  {==}

# This is the actual application document, rather than a palette-only assertion.
def application_background(+scene: Web.Scene) ->
  {document_background(Render.render(scene)) == Render.surface_background(Surfaces.Canvas{}, Surfaces.Rest{}) : String}:
  match scene:
    case Web.Scene{UI.Surface{content, base, overlays, active}, platform, generation, realization,
      Design.Presentation{Design.Layout{Design.Viewport{width, height}, shell, main, placements},
        Design.Visuals{theme, rhythm, base_appearance, overlay_appearance}}}: {==}

def lane_background(+stage: Board.Stage) ->
  {Render.attr(Render.board_lane_styles(stage), "background") ==
    Render.surface_background(Surfaces.Lane{Render.stage_surface_tone(stage)}, Surfaces.Rest{}) : String}:
  {==}

def chip_background(key: String, kind: String, text: String, +tone: Surfaces.Tone) ->
  {Render.attr(node_styles(Render.card_chip(key, kind, text, tone)), "background") ==
    Render.surface_background(Surfaces.Chip{tone}, Surfaces.Rest{}) : String}:
  {==}

def selected_background(+selected: Bool) ->
  {Render.project_selected_background(selected) ==
    Render.surface_background(Surfaces.Choice{selected}, Surfaces.Rest{}) : String}:
  {==}

def wrapper_phases(+role: Surfaces.Role) ->
  {(Render.attr(Render.native_surface_properties(role), "--native-rest-background"),
    (Render.attr(Render.native_surface_properties(role), "--native-hover-background"),
     Render.attr(Render.native_surface_properties(role), "--native-pressed-background"))) ==
    (Render.surface_background(role, Surfaces.Rest{}),
      (Render.surface_background(role, Surfaces.Hovered{}), Render.surface_background(role, Surfaces.Pressed{}))) :
    (String & (String & String))}:
  {==}

def rest_background_property(+value: String) ->
  {Render.pointer_property("background", value) == Doc.Property{"--native-rest-background", value} : Doc.Property}:
  {==}

def rest_foreground_property(+value: String) ->
  {Render.pointer_property("color", value) == Doc.Property{"--native-rest-color", value} : Doc.Property}:
  {==}

# The final action properties expose rest color variables to the CSS interpreter.
def action_rest_background(+key: String, +visual: Design.Style, input: Core.Input, availability: View.Availability,
  name: String, face: Controls.Face, behavior: Controls.Behavior, geometry: Controls.Geometry,
  placement: Controls.Placement, help: Controls.Help, feedback: Controls.Feedback) ->
  {Render.attr(node_styles(Render.action(key, Design.Appearance{key, visual, Controls.NoControl{}, Nil{}},
    Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback})),
    "--native-rest-background") == Render.attr(Render.style(visual), "background") : String}:
  match visual:
    case Design.Style{Design.TextStyle{font, size, line_height, weight}, Design.Chrome{foreground, background, border, border_width, radius, shadow},
      alignment, flow, overflow, inline, block, gap, height, maximum, states}: {==}

def surface_foreground(+role: Surfaces.Role) ->
  {Render.paint(Design.SurfaceForeground{role}) == Render.surface_color(Surfaces.foreground(role)) : String}:
  {==}

type Requirements is Type:
  Requirements{
    surface_foreground: @+role:Surfaces.Role -> {Render.paint(Design.SurfaceForeground{role}) == Render.surface_color(Surfaces.foreground(role)) : String},
    color_clear: {Render.surface_color(Surfaces.Clear{}) == "transparent" : String},
    color_token: @+name:String -> {Render.surface_color(Surfaces.Token{name}) == "var(" ++ name ++ ")" : String},
    color_blend: @+foreground:String -> @+percent:Nat -> @+background:String ->
      {Render.surface_color(Surfaces.Blend{foreground, percent, background}) ==
        "color-mix(in srgb, var(" ++ foreground ++ ") " ++ Nat.show(percent) ++ "%, var(" ++ background ++ "))" : String},
    surface_paint: @+role:Surfaces.Role -> @+phase:Surfaces.Phase ->
      {Render.paint(Design.SurfacePaint{role, phase}) == Render.surface_color(Surfaces.background(role, phase)) : String},
    application_background: @+scene:Web.Scene ->
      {document_background(Render.render(scene)) == Render.surface_background(Surfaces.Canvas{}, Surfaces.Rest{}) : String},
    lane_background: @+stage:Board.Stage ->
      {Render.attr(Render.board_lane_styles(stage), "background") ==
        Render.surface_background(Surfaces.Lane{Render.stage_surface_tone(stage)}, Surfaces.Rest{}) : String},
    chip_background: @key:String -> @kind:String -> @text:String -> @+tone:Surfaces.Tone ->
      {Render.attr(node_styles(Render.card_chip(key, kind, text, tone)), "background") ==
        Render.surface_background(Surfaces.Chip{tone}, Surfaces.Rest{}) : String},
    selected_background: @+selected:Bool ->
      {Render.project_selected_background(selected) == Render.surface_background(Surfaces.Choice{selected}, Surfaces.Rest{}) : String},
    wrapper_phases: @+role:Surfaces.Role ->
      {(Render.attr(Render.native_surface_properties(role), "--native-rest-background"),
        (Render.attr(Render.native_surface_properties(role), "--native-hover-background"),
          Render.attr(Render.native_surface_properties(role), "--native-pressed-background"))) ==
        (Render.surface_background(role, Surfaces.Rest{}),
          (Render.surface_background(role, Surfaces.Hovered{}), Render.surface_background(role, Surfaces.Pressed{}))) : (String & (String & String))},
    rest_background_property: @+value:String ->
      {Render.pointer_property("background", value) == Doc.Property{"--native-rest-background", value} : Doc.Property},
    rest_foreground_property: @+value:String ->
      {Render.pointer_property("color", value) == Doc.Property{"--native-rest-color", value} : Doc.Property},
    action_rest_background: @+key:String -> @+visual:Design.Style -> @input:Core.Input -> @availability:View.Availability ->
      @name:String -> @face:Controls.Face -> @behavior:Controls.Behavior -> @geometry:Controls.Geometry ->
      @placement:Controls.Placement -> @help:Controls.Help -> @feedback:Controls.Feedback ->
      {Render.attr(node_styles(Render.action(key, Design.Appearance{key, visual, Controls.NoControl{}, Nil{}},
        Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback})),
        "--native-rest-background") == Render.attr(Render.style(visual), "background") : String}
  }

def evidence() -> Requirements:
  Requirements{role => surface_foreground(role),
    color_clear(), name => color_token(name), foreground => percent => background => color_blend(foreground, percent, background),
    role => phase => surface_paint(role, phase), scene => application_background(scene), stage => lane_background(stage),
    key => kind => text => tone => chip_background(key, kind, text, tone), selected => selected_background(selected),
    role => wrapper_phases(role), value => rest_background_property(value), value => rest_foreground_property(value),
    key => visual => input => availability => name => face => behavior => geometry => placement => help => feedback =>
      action_rest_background(key, visual, input, availability, name, face, behavior, geometry, placement, help, feedback)}
