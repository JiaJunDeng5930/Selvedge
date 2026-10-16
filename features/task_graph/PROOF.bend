import Base
import ./CONTRACT.bend as C
import ./CODEC.bend as Codec
import ./construction-proof.bend as Construction
import ./registry-proof.bend as Registry

def boundary() -> C.RegistryBoundary:
  Registry.registry_boundary(Construction.admission())
