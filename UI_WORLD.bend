import Base
import ./core/interface.bend as Interface
import ./core/laws.bend as CoreLaws
import ./MODEL.bend as M
import ./core/SYSTEM.bend as Core
import ./core/ui-world.bend as View

def initial(program: M.World()) -> Core.State:
  Core.initial(program)

def step(input: Core.Input, state: Core.State) -> Core.Decision:
  Core.step(input, state)

def observe(capacity: View.Capacity, state: Core.State) -> Interface.Surface:
  Interface.observe(capacity, state)

def interact(capacity: View.Capacity, key: String, gesture: Interface.Gesture, state: Core.State) -> Core.Decision:
  Interface.interact(capacity, key, gesture, state)
