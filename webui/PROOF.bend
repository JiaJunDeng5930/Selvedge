import Base
import ./laws.bend as Interaction
import ./render-laws.bend as Rendering
import ./layout-laws.bend as LayoutLaws
import ./appearance-laws.bend as AppearanceLaws
import ./presentation-laws.bend as PresentationLaws

# These witnesses bind interaction, rendered geometry, and the complete
# prescribed presentation to the Web model.
type Realization is Type:
  Realization{interaction: Interaction.Requirements, rendering: Rendering.Requirements,
    layout: LayoutLaws.Requirements, appearance: AppearanceLaws.Requirements,
    presentation: PresentationLaws.Requirements}

def realization() -> Realization:
  Realization{Interaction.evidence(), Rendering.evidence(), LayoutLaws.evidence(),
    AppearanceLaws.evidence(), PresentationLaws.evidence()}
