import Base
import ../core/SYSTEM.bend as Core
import ./MODEL.bend as Model
import ./design.bend as Design
import ./font-observation.bend as F
import ./platform.bend as Platform

law production_commit_preserves_product:
  for +decision: Platform.Decision
  for +generation: Nat
  for +environment: Design.Environment
  for +font: F.State
  {Model.product(Model.production_commit(decision, generation, environment, font)) == Model.platform_product(decision) : Core.Decision}
