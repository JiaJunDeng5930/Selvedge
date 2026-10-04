import Base
import ../surfaces.bend as Surfaces
import ../design.bend as Design
import ../renderer.bend as Render
import ../MODEL.bend as Web
import ../surface-render-laws.bend as Rule
import ./enclosure-render.bend as EnclosureRenderProof

def application_background(+scene: Web.Scene) ->
  {Rule.document_background(Rule.placed_scene(scene)) == Render.surface_background(Surfaces.Canvas{}, Surfaces.Rest{}) : String}:
  match scene:
    case Web.Scene{Design.PreparedSurface{Design.Surface{content, theme, source_base, source_overlays, active}, base, overlays}, platform, generation, realization,
      Design.Layout{Design.Viewport{width, height}, shell, main, placements, parameters, controls}}: {==}

def Rule.evidence():
  Rule.Requirements{+role => {==},
    {==}, +name => {==}, +foreground => +percent => +background => {==},
    +role => +phase =>
        {==}

      # This is the actual application document, rather than a palette-only assertion.
    , scene => application_background(scene), +stage => {==},
    +typography => key => kind => text => +tone => {==},
    +typography => +selected => {==},
    +value => {==}, +value =>
        {==}

      # The final action properties expose rest color variables to the CSS interpreter.
    ,
    +key => +visual => input => availability => name => face => behavior => geometry => placement => help => feedback => EnclosureRenderProof.action_background_preserved(key, visual, input, availability, name, face, behavior, geometry, placement, help, feedback)}
