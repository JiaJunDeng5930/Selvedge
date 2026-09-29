import Base
import ./laws.bend as Interaction
import ./render-laws.bend as Rendering

# The browser supplies measurements and executes effects. These witnesses cover
# the model's product refinement and what accepting those measurements means.
type Realization is Type:
  Realization{interaction: Interaction.Requirements, rendering: Rendering.Requirements}

def realization() -> Realization:
  Realization{Interaction.evidence(), Rendering.evidence()}
