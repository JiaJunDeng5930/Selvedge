import Base
import ./typography.bend as T
import ./surfaces.bend as Surfaces
import ./design.bend as Design
import ./document.bend as Doc
import ./renderer.bend as Render
import ./MODEL.bend as Web
import ./controls.bend as Controls
import ./appearance.bend as Appearance
import ../core/SYSTEM.bend as Core
import ../core/ui-world.bend as View
import ../BOARD.bend as Board

def document_background(document: Doc.Document) -> String:
  Doc.Document{root, title} = document
  Render.attr(Doc.element_styles(root), "background")

def placed_scene(scene: Web.Scene) -> Doc.Document:
  Web.Scene{presentation, platform, generation, realization, layout} = scene
  Render.place(presentation, layout)

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
      {document_background(placed_scene(scene)) == Render.surface_background(Surfaces.Canvas{}, Surfaces.Rest{}) : String},
    lane_background: @+stage:Board.Stage ->
      {Render.attr(Render.board_lane_styles(stage), "background") ==
        Render.surface_background(Surfaces.Lane{Render.stage_surface_tone(stage)}, Surfaces.Rest{}) : String},
    chip_background: @+typography:T.Presentation -> @key:String -> @kind:String -> @text:String -> @+tone:Surfaces.Tone ->
      {Render.attr(Doc.element_styles(Render.card_chip(key, kind, text, tone, typography)), "background") ==
        Render.surface_background(Surfaces.Chip{tone}, Surfaces.Rest{}) : String},
    selected_background: @+typography:T.Presentation -> @+selected:Bool ->
      {Render.paint(Appearance.style_background(Appearance.navigation_family_style(selected, 2n, 6n, typography))) == Render.surface_background(Surfaces.Choice{selected}, Surfaces.Rest{}) : String},
    rest_background_property: @+value:String ->
      {Render.pointer_property("background", value) == Doc.Property{"--native-rest-background", value} : Doc.Property},
    rest_foreground_property: @+value:String ->
      {Render.pointer_property("color", value) == Doc.Property{"--native-rest-color", value} : Doc.Property},
    action_rest_background: @+key:String -> @+visual:Design.Style -> @input:Core.Input -> @availability:View.Availability ->
      @name:String -> @face:Controls.Face -> @behavior:Controls.Behavior -> @geometry:Controls.Geometry ->
      @placement:Controls.Placement -> @help:Controls.Help -> @feedback:Controls.Feedback ->
      {Render.attr(Doc.element_styles(Render.action(key, visual,
          Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback})),
          "--native-rest-background") == Render.attr(Render.style(visual), "background") : String}
  }

law evidence:
  Requirements
