import Base
import ./laws.bend as Interaction
import ./render-laws.bend as Rendering
import ./layout-laws.bend as LayoutLaws
import ./appearance-laws.bend as AppearanceLaws
import ./presentation-laws.bend as PresentationLaws
import ./control-laws.bend as ControlLaws
import ../core/user-experience-laws.bend as UserExperienceLaws
import ./browser-laws.bend as BrowserLaws
import ./renderer-laws.bend as RendererLaws
import ./page-region-laws.bend as PageRegionLaws
import ./visibility.bend as Visibility
import ./focus.bend as Focus
import ./reading.bend as Reading

# These witnesses bind interaction, rendered geometry, and the complete
# prescribed presentation to the Web model.
type Realization is Type:
  Realization{interaction: Interaction.Requirements, rendering: Rendering.Requirements,
    layout: LayoutLaws.Requirements, appearance: AppearanceLaws.Requirements,
    presentation: PresentationLaws.Requirements, controls: ControlLaws.Requirements,
    commands: UserExperienceLaws.CommandRequirements, browser: BrowserLaws.Requirements, renderer: RendererLaws.Requirements, page_regions: PageRegionLaws.Requirements, visibility: Visibility.Requirements,
    focus_cycle: Focus.CycleRequirements, scroll_ownership: Reading.ScrollOwnershipRequirements}

def realization() -> Realization:
  Realization{Interaction.evidence(), Rendering.evidence(), LayoutLaws.evidence(),
    AppearanceLaws.evidence(), PresentationLaws.evidence(), ControlLaws.evidence(),
    UserExperienceLaws.command_evidence(), BrowserLaws.evidence(), RendererLaws.evidence(), PageRegionLaws.evidence(), Visibility.evidence(),
    Focus.cycle_evidence(), Reading.scroll_ownership_evidence()}
