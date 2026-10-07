import Base
import ./program-rules.bend as Rule

def Rule.interface_input(input, state):
  {==}

def Rule.interface_evidence():
  Rule.InterfaceRequirements{Rule.interface_input}
