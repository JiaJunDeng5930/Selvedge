import Base
import ./core/laws.bend as CoreLaws
import ./MODEL.bend as M
import ./core/SYSTEM.bend as Core
import ./core/ui-world.bend as View

def initial(program: M.World()) -> Core.State:
  Core.initial(program)

def step(input: Core.Input, state: Core.State) -> Core.Decision:
  Core.step(input, state)

def observe(capacity: View.Capacity, state: Core.State) -> Core.Scene:
  Core.observe(capacity, state)
